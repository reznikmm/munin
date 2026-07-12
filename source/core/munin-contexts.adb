--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Directories;

with VSS.Strings.Conversions;

package body Munin.Contexts is

   use type Ada.Directories.File_Kind;

   procedure Load_Project
     (Self         : in out Context;
      Project_File : VSS.Strings.Virtual_String;
      Errors       : out VSS.String_Vectors.Virtual_String_Vector)
   is
      Path : constant String :=
        VSS.Strings.Conversions.To_UTF_8_String (Project_File);
   begin
      Errors.Clear;
      Self.Loaded_Project := Project_File;
      Self.Task_Items.Clear;
      Self.Protected_Items.Clear;

      if Project_File.Is_Empty then
         Errors.Append
           (VSS.Strings.To_Virtual_String ("project file path is empty"));
         return;
      end if;

      if not Ada.Directories.Exists (Path) then
         Errors.Append
           (VSS.Strings."&"
              (VSS.Strings.To_Virtual_String ("project file does not exist: "),
               Project_File));
         return;
      end if;

      if Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File then
         Errors.Append
           (VSS.Strings."&"
              (VSS.Strings.To_Virtual_String ("project path is not a file: "),
               Project_File));
      end if;
   end Load_Project;

   function Tasks (Self : Context) return Munin.Tasks.Task_Unit_Array is
      Last : constant Natural := Self.Task_Items.Last_Index;
   begin
      return Result : Munin.Tasks.Task_Unit_Array (1 .. Last) do
         for Index in Result'Range loop
            Result (Index) := Self.Task_Items.Element (Index);
         end loop;
      end return;
   end Tasks;

   function Protected_Objects
     (Self : Context) return Munin.Protected_Objects.Protected_Object_Array
   is
      Last : constant Natural := Self.Protected_Items.Last_Index;
   begin
      return Result :
        Munin.Protected_Objects.Protected_Object_Array (1 .. Last)
      do
         for Index in Result'Range loop
            Result (Index) := Self.Protected_Items.Element (Index);
         end loop;
      end return;
   end Protected_Objects;

end Munin.Contexts;