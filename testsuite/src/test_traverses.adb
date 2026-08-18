--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Libadalang.Analysis;
with Libadalang.Common;
with Munin.Contexts;
with Munin.Contexts.Traverses;
with Trendy_Test.Assertions;
with VSS.String_Vectors;
with VSS.Strings;
with VSS.Strings.Conversions;

package body Test_Traverses is

   Root : constant String :=
     Ada.Directories.Containing_Directory
       (Ada.Directories.Containing_Directory (Ada.Command_Line.Command_Name));

   procedure Test_Each_Library_Level_Name
     (Op : in out Trendy_Test.Operation'Class)
   is
      use Ada.Strings.Unbounded;

      --  Path to the priority testcase crate, relative to testsuite root
      Crate_Dir : constant String := Root & "/test_cases/priority";
      Log_File  : constant String := Root & "/obj/test_traverses_build.log";

      Max_Output_Length : constant Natural := 512;

      function Read_Log_File (Path : String) return String is
         File : Ada.Text_IO.File_Type;
         Data : Unbounded_String;
      begin
         if not Ada.Directories.Exists (Path) then
            return "<no build output log found>";
         end if;

         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            declare
               Line : constant String := Ada.Text_IO.Get_Line (File);
            begin
               if Length (Data) > 0 then
                  Append (Data, Ada.Characters.Latin_1.LF);
               end if;
               Append (Data, Line);
            end;
         end loop;
         Ada.Text_IO.Close (File);

         if Length (Data) = 0 then
            return "<build produced no output>";
         end if;

         return To_String (Data);
      exception
         when others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            return "<unable to read build output log>";
      end Read_Log_File;

      function Tail_Output (Text : String) return String is
      begin
         if Text'Length <= Max_Output_Length then
            return Text;
         end if;

         return
           "<output truncated to last "
           & Max_Output_Length'Image
           & " characters>"
           & Ada.Characters.Latin_1.LF
           & Text (Text'Last - Integer (Max_Output_Length) + 1 .. Text'Last);
      end Tail_Output;

      use type GNAT.OS_Lib.String_Access;

      Command : GNAT.OS_Lib.String_Access;
      Args    : GNAT.OS_Lib.Argument_List (1 .. 5);
      Success : Boolean;
      Result  : Integer;
   begin
      Op.Register (Parallelize => False);

      --  Setup: attempt to build the priority testcase crate.
      --  Requires gnat_arm_elf cross-compiler.
      Args :=
        (1 => new String'("-n"),
         2 => new String'("--no-tty"),
         3 => new String'("-C"),
         4 => new String'(Crate_Dir),
         5 => new String'("build"));

      Command := GNAT.OS_Lib.Locate_Exec_On_Path ("alr");

      if Command = null then
         Trendy_Test.Assertions.Fail (Op, "alr not found on PATH.");
         return;
      else
         GNAT.OS_Lib.Spawn (Command.all, Args, Log_File, Success, Result);
      end if;

      if not Success or else Result /= 0 then
         Trendy_Test.Assertions.Fail
           (Op,
            "Failed to build testcase crate."
            & Ada.Characters.Latin_1.LF
            & "Spawn output:"
            & Ada.Characters.Latin_1.LF
            & Tail_Output (Read_Log_File (Log_File)));
      end if;

      for I in Args'Range loop
         GNAT.OS_Lib.Free (Args (I));
      end loop;

      --  Testing: load the project, then exercise the traversal directly.
      declare
         Context : Munin.Contexts.Context;
         Errors  : VSS.String_Vectors.Virtual_String_Vector;
         Names   : VSS.String_Vectors.Virtual_String_Vector;

         function Any_Contains (Pattern : String) return Boolean is
         begin
            for Name of Names loop
               if Ada.Strings.Fixed.Index
                    (VSS.Strings.Conversions.To_UTF_8_String (Name), Pattern)
                 > 0
               then
                  return True;
               end if;
            end loop;

            return False;
         end Any_Contains;

         procedure Collect (Name : Libadalang.Analysis.Defining_Name) is
         begin
            Names.Append
              (VSS.Strings.To_Virtual_String (Name.P_Fully_Qualified_Name));
         exception
            when Libadalang.Common.Property_Error =>
               null;
         end Collect;
      begin
         Munin.Contexts.Load_Project
           (Self         => Context,
            Project_File =>
              VSS.Strings.Conversions.To_Virtual_String
                (Crate_Dir & "/priority.gpr"),
            Errors       => Errors);

         if not Errors.Is_Empty then
            declare
               Message : Unbounded_String :=
                 To_Unbounded_String ("Load_Project returned errors:");
            begin
               for Item of Errors loop
                  Append (Message, Ada.Characters.Latin_1.LF);
                  Append
                    (Message, VSS.Strings.Conversions.To_UTF_8_String (Item));
               end loop;

               Trendy_Test.Assertions.Fail (Op, To_String (Message));
               return;
            end;
         end if;

         Munin.Contexts.Traverses.Each_Library_Level_Name
           (Context, Collect'Access);

         --  Every library-level name is yielded, not just the ones
         --  Load_Project's classification goes on to report -- including
         --  bare task/protected type declarations Load_Project never
         --  reports (Guard_Type, Worker_Type, Accumulator).
         Op.Assert (Any_Contains ("Priority_Sample.Telemetry"));
         Op.Assert (Any_Contains ("Priority_Sample.Guard_Type"));
         Op.Assert (Any_Contains ("Priority_Sample.Guard"));
         Op.Assert (Any_Contains ("Priority_Sample.Worker_Type"));
         Op.Assert (Any_Contains ("Priority_Sample.Accumulator"));
         Op.Assert (Any_Contains ("Priority_Sample.Ready"));

         --  A generic instantiation is traversed via its designated
         --  generic, under the instantiation's own name.
         Op.Assert (Any_Contains ("Readers_24.Reader"));

         --  The generic template itself is never traversed on its own,
         --  and it is never instantiated from this fixture, so its name
         --  (and anything inside it) must never appear.
         Op.Assert (not Any_Contains ("Gen_Pkg"));

         --  Nor is the body of a generic template traversed, even though
         --  it contains its own instantiation (My_Readers) of Readers.
         Op.Assert (not Any_Contains ("My_Readers"));
      end;
   end Test_Each_Library_Level_Name;

end Test_Traverses;
