--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with Ada.Characters.Latin_1;
with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Munin.Contexts;
with Munin.Priorities;
with Munin.Protected_Objects;
with Munin.Tasks;
with Trendy_Test.Assertions;
with VSS.String_Vectors;
with VSS.Strings.Conversions;

package body Test_Priority is

   Root : constant String :=
     Ada.Directories.Containing_Directory
       (Ada.Directories.Containing_Directory
          (Ada.Command_Line.Command_Name));

   procedure Test_Priority_Build
     (Op : in out Trendy_Test.Operation'Class)
   is
      use Ada.Strings.Unbounded;

      --  Path to the priority testcase crate, relative to testsuite root
      Crate_Dir : constant String := Root & "/test_cases/priority";
      Log_File : constant String := Root & "/obj/test_priority_build.log";

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

         return "<output truncated to last "
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
         GNAT.OS_Lib.Spawn
           (Command.all,
            Args,
            Log_File,
            Success,
            Result);
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

      --  Testing: load the project and validate discovered concurrency objects.
      declare
         Context : Munin.Contexts.Context;
         Errors  : VSS.String_Vectors.Virtual_String_Vector;

         Found_Task      : Boolean := False;
         Found_Protected : Boolean := False;

         function Lower_Name (Value : String) return String is
           (Ada.Characters.Handling.To_Lower (Value));

         function Contains (Text, Pattern : String) return Boolean is
           (Ada.Strings.Fixed.Index (Text, Pattern) > 0);
      begin
         Munin.Contexts.Load_Project
           (Self         => Context,
            Project_File => VSS.Strings.Conversions.To_Virtual_String
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
                    (Message,
                     VSS.Strings.Conversions.To_UTF_8_String (Item));
               end loop;

               Trendy_Test.Assertions.Fail (Op, To_String (Message));
               return;
            end;
         end if;

         declare
            Task_Items : constant Munin.Tasks.Task_Unit_Array :=
              Munin.Contexts.Tasks (Context);
            Protected_Items :
              constant Munin.Protected_Objects.Protected_Object_Array :=
                Munin.Contexts.Protected_Objects (Context);
         begin
            Op.Assert (Task_Items'Length = 1);
            Op.Assert (Protected_Items'Length = 1);

            for Item of Task_Items loop
               declare
                  Name : constant String :=
                    Lower_Name
                      (VSS.Strings.Conversions.To_UTF_8_String
                         (Munin.Tasks.Qualified_Name (Item)));
                  Priority : constant Munin.Priorities.Optional_Priority :=
                    Munin.Tasks.Priority (Item);
               begin
                  if Contains (Name, "priority_sample")
                    and then Contains (Name, "telemetry")
                  then
                     Found_Task := True;
                  end if;

                  Op.Assert (Priority.Has_Value);
                  Op.Assert (Priority.Value = 10);
               end;
            end loop;

            for Item of Protected_Items loop
               declare
                  Name : constant String :=
                    Lower_Name
                      (VSS.Strings.Conversions.To_UTF_8_String
                         (Munin.Protected_Objects.Qualified_Name (Item)));
                  Priority : constant Munin.Priorities.Optional_Priority :=
                    Munin.Protected_Objects.Priority (Item);
               begin
                  if Contains (Name, "priority_sample")
                    and then Contains (Name, "shared_register")
                  then
                     Found_Protected := True;
                  end if;

                  Op.Assert (Priority.Has_Value);
                  Op.Assert (Priority.Value = 20);
               end;
            end loop;
         end;

         Op.Assert (Found_Task);
         Op.Assert (Found_Protected);
      end;
   end Test_Priority_Build;

end Test_Priority;
