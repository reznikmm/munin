--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Trendy_Test.Assertions;

package body Test_Build_Support is

   use Ada.Strings.Unbounded;

   Max_Output_Length : constant Natural := 512;

   function Read_Log_File (Path : String) return String;
   --  The log file's content, or a placeholder string describing why it
   --  couldn't be read.

   function Tail_Output (Text : String) return String;
   --  Text, or its last Max_Output_Length characters (with a note) when
   --  longer than that.

   -------------------
   -- Read_Log_File --
   -------------------

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

   -----------------
   -- Tail_Output --
   -----------------

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

   --------------------
   -- Testsuite_Root --
   --------------------

   function Testsuite_Root return String is
     (Ada.Directories.Containing_Directory
        (Ada.Directories.Containing_Directory
           (Ada.Command_Line.Command_Name)));

   -----------------
   -- Build_Crate --
   -----------------

   procedure Build_Crate
     (Op        : in out Trendy_Test.Operation'Class;
      Crate_Dir : String;
      Log_Name  : String;
      Success   : out Boolean)
   is
      use type GNAT.OS_Lib.String_Access;

      Log_File : constant String := Testsuite_Root & "/obj/" & Log_Name;
      Command  : GNAT.OS_Lib.String_Access;
      Args     : GNAT.OS_Lib.Argument_List (1 .. 5);
      Result   : Integer;
   begin
      Args :=
        (1 => new String'("-n"),
         2 => new String'("--no-tty"),
         3 => new String'("-C"),
         4 => new String'(Crate_Dir),
         5 => new String'("build"));

      Command := GNAT.OS_Lib.Locate_Exec_On_Path ("alr");

      if Command = null then
         Trendy_Test.Assertions.Fail (Op, "alr not found on PATH.");
         Success := False;
      else
         GNAT.OS_Lib.Spawn (Command.all, Args, Log_File, Success, Result);

         if not Success or else Result /= 0 then
            Trendy_Test.Assertions.Fail
              (Op,
               "Failed to build testcase crate."
               & Ada.Characters.Latin_1.LF
               & "Spawn output:"
               & Ada.Characters.Latin_1.LF
               & Tail_Output (Read_Log_File (Log_File)));
            Success := False;
         end if;
      end if;

      for I in Args'Range loop
         GNAT.OS_Lib.Free (Args (I));
      end loop;
   end Build_Crate;

end Test_Build_Support;
