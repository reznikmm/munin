--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Indefinite_Vectors;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding;
with Ada.Text_IO;

with GNATCOLL.GMP.Integers;
with Langkit_Support.Text;
with Libadalang.Analysis;
with Libadalang.Common;

with Munin.Priorities;

with VSS.Strings.Conversions;

package body Munin.Contexts is

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type   => Positive,
      Element_Type => String);

   use type Ada.Directories.File_Kind;
   use type Libadalang.Common.Visit_Status;

   function To_Virtual_String
     (Value : Langkit_Support.Text.Text_Type)
      return VSS.Strings.Virtual_String;

   procedure Append_Error
     (Errors : in out VSS.String_Vectors.Virtual_String_Vector;
      Value  : String);

   function Ends_With (Value, Suffix : String) return Boolean;

   function Has_Ada_Extension (File_Name : String) return Boolean;

   function Extract_Quoted_Values
     (Text : String) return String_Vectors.Vector;

   function Source_Directories
     (Project_File : String) return String_Vectors.Vector;

   procedure Collect_Ada_Sources
     (Directory : String;
      Result    : in out String_Vectors.Vector);

   function Priority_For
     (Decl : Libadalang.Analysis.Basic_Decl'Class)
      return Munin.Priorities.Optional_Priority;

   procedure Append_Task_Unique
      (Self : in out Context;
       Item : Munin.Tasks.Task_Unit);

   function To_Virtual_String
     (Value : Langkit_Support.Text.Text_Type)
      return VSS.Strings.Virtual_String
   is
      UTF8 : constant Ada.Strings.UTF_Encoding.UTF_8_String :=
        Langkit_Support.Text.To_UTF8 (Value);
   begin
      return VSS.Strings.Conversions.To_Virtual_String (String (UTF8));
   end To_Virtual_String;

   procedure Append_Error
     (Errors : in out VSS.String_Vectors.Virtual_String_Vector;
      Value  : String) is
   begin
      Errors.Append (VSS.Strings.Conversions.To_Virtual_String (Value));
   end Append_Error;

   function Ends_With (Value, Suffix : String) return Boolean is
   begin
      if Value'Length < Suffix'Length then
         return False;
      end if;

      return Value (Value'Last - Suffix'Length + 1 .. Value'Last) = Suffix;
   end Ends_With;

   function Has_Ada_Extension (File_Name : String) return Boolean is
      Lower : constant String := Ada.Characters.Handling.To_Lower (File_Name);
   begin
      return Ends_With (Lower, ".adb")
        or else Ends_With (Lower, ".ads")
        or else Ends_With (Lower, ".ada")
        or else Ends_With (Lower, ".spc")
        or else Ends_With (Lower, ".bdy");
   end Has_Ada_Extension;

   function Extract_Quoted_Values
     (Text : String) return String_Vectors.Vector
   is
      Result   : String_Vectors.Vector;
      In_Quote : Boolean := False;
      Start    : Positive := Text'First;
   begin
      for Index in Text'Range loop
         if Text (Index) = '"' then
            if In_Quote then
               Result.Append (Text (Start .. Index - 1));
               In_Quote := False;
            else
               In_Quote := True;
               Start := Index + 1;
            end if;
         end if;
      end loop;

      return Result;
   end Extract_Quoted_Values;

   function Source_Directories
     (Project_File : String) return String_Vectors.Vector
   is
      use Ada.Strings.Unbounded;

      File        : Ada.Text_IO.File_Type;
      Statement   : Unbounded_String;
      In_Clause   : Boolean := False;
      Result      : String_Vectors.Vector;
      Project_Dir : constant String :=
        Ada.Directories.Containing_Directory (Project_File);
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Project_File);

      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line       : constant String := Ada.Text_IO.Get_Line (File);
            Lower_Line : constant String :=
              Ada.Characters.Handling.To_Lower (Line);
         begin
            if not In_Clause
              and then Ada.Strings.Fixed.Index
                (Lower_Line, "for source_dirs use") > 0
            then
               In_Clause := True;
            end if;

            if In_Clause then
               Append (Statement, Line);
               Append (Statement, " ");

               exit when Ada.Strings.Fixed.Index (Line, ";") > 0;
            end if;
         end;
      end loop;

      Ada.Text_IO.Close (File);

      if Length (Statement) = 0 then
         Result.Append (Project_Dir);
         return Result;
      end if;

      declare
         Quoted : constant String_Vectors.Vector :=
           Extract_Quoted_Values (To_String (Statement));
      begin
         for Item of Quoted loop
            declare
               Full : constant String :=
                 (if Item'Length > 0
                    and then Item (Item'First) = '/'
                  then
                     Item
                  else
                     Ada.Directories.Compose (Project_Dir, Item));
            begin
               if Ada.Directories.Exists (Full)
                 and then
                   Ada.Directories.Kind (Full) = Ada.Directories.Directory
               then
                  Result.Append (Full);
               end if;
            end;
         end loop;
      end;

      if Result.Is_Empty then
         Result.Append (Project_Dir);
      end if;

      return Result;

   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;

         return Result : String_Vectors.Vector do
            Result.Append (Project_Dir);
         end return;
   end Source_Directories;

   procedure Collect_Ada_Sources
     (Directory : String;
      Result    : in out String_Vectors.Vector)
   is
      Search     : Ada.Directories.Search_Type;
      Dir_Entry  : Ada.Directories.Directory_Entry_Type;
      Has_Search : Boolean := False;
   begin
      Ada.Directories.Start_Search
        (Search    => Search,
         Directory => Directory,
         Pattern   => "",
         Filter    =>
           (Ada.Directories.Ordinary_File => True,
            Ada.Directories.Directory     => True,
            Ada.Directories.Special_File  => False));
      Has_Search := True;

      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Dir_Entry);

         declare
            Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
            Full : constant String := Ada.Directories.Full_Name (Dir_Entry);
         begin
            if Ada.Directories.Kind (Dir_Entry)
              = Ada.Directories.Directory
            then
               if Name /= "." and then Name /= ".." then
                  Collect_Ada_Sources (Full, Result);
               end if;

            elsif Has_Ada_Extension (Name) then
               Result.Append (Full);
            end if;
         end;
      end loop;

      Ada.Directories.End_Search (Search);
      Has_Search := False;

   exception
      when others =>
         if Has_Search then
            Ada.Directories.End_Search (Search);
         end if;
   end Collect_Ada_Sources;

   function Priority_For
     (Decl : Libadalang.Analysis.Basic_Decl'Class)
      return Munin.Priorities.Optional_Priority
   is
      Aspect_Name : constant Langkit_Support.Text.Unbounded_Text_Type :=
        Langkit_Support.Text.To_Unbounded_Text
          (Langkit_Support.Text.To_Text ("Priority"));
      Expr        : constant Libadalang.Analysis.Expr :=
        Decl.P_Get_Aspect_Spec_Expr (Aspect_Name);
   begin
      if Expr.Is_Null then
         return Munin.Priorities.Default_Priority;
      end if;

      if not Expr.P_Is_Static_Expr then
         raise Constraint_Error with
           "Priority aspect must be static: "
           & String (Langkit_Support.Text.To_UTF8 (Expr.Text));
      end if;

      return Munin.Priorities.Explicit_Priority
        (Integer'Value (GNATCOLL.GMP.Integers.Image (Expr.P_Eval_As_Int)));
   end Priority_For;

   procedure Append_Task_Unique
     (Self : in out Context;
      Item : Munin.Tasks.Task_Unit)
   is
      use type VSS.Strings.Virtual_String;

      Name     : constant VSS.Strings.Virtual_String :=
        Munin.Tasks.Qualified_Name (Item);
      Priority : constant Munin.Priorities.Optional_Priority :=
        Munin.Tasks.Priority (Item);
   begin
      for Index in 1 .. Self.Task_Items.Last_Index loop
         declare
            Existing : constant Munin.Tasks.Task_Unit :=
              Self.Task_Items.Element (Index);
            Existing_Priority : constant Munin.Priorities.Optional_Priority :=
              Munin.Tasks.Priority (Existing);
         begin
            if Munin.Tasks.Qualified_Name (Existing) = Name then
               --  Keep a single entry per task name, preferring explicit
               --  priority over default when both declarations are seen.
               if not Existing_Priority.Has_Value and then Priority.Has_Value
               then
                  Self.Task_Items.Replace_Element (Index, Item);
               end if;

               return;
            end if;
         end;
      end loop;

      Self.Task_Items.Append (Item);
   end Append_Task_Unique;

   procedure Load_Project
     (Self         : in out Context;
      Project_File : VSS.Strings.Virtual_String;
      Errors       : out VSS.String_Vectors.Virtual_String_Vector)
   is
      Path : constant String :=
        VSS.Strings.Conversions.To_UTF_8_String (Project_File);
      Context : constant Libadalang.Analysis.Analysis_Context :=
        Libadalang.Analysis.Create_Context;
      Files   : String_Vectors.Vector;
   begin
      Errors.Clear;
      Self.Loaded_Project := Project_File;
      Self.Task_Items.Clear;
      Self.Protected_Items.Clear;

      if Project_File.Is_Empty then
         Append_Error (Errors, "project file path is empty");
         return;
      end if;

      if not Ada.Directories.Exists (Path) then
         Append_Error (Errors, "project file does not exist: " & Path);
         return;
      end if;

      if Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File then
         Append_Error (Errors, "project path is not a file: " & Path);
         return;
      end if;

      for Source_Dir of Source_Directories (Path) loop
         Collect_Ada_Sources (Source_Dir, Files);
      end loop;

      for File_Name of Files loop
         declare
            Unit : constant Libadalang.Analysis.Analysis_Unit :=
              Context.Get_From_File (File_Name);
            Root : constant Libadalang.Analysis.Ada_Node := Unit.Root;

            function Visit
              (Node : Libadalang.Analysis.Ada_Node'Class)
               return Libadalang.Common.Visit_Status;

            function Visit
              (Node : Libadalang.Analysis.Ada_Node'Class)
               return Libadalang.Common.Visit_Status
            is
               Kind : constant String := Libadalang.Analysis.Kind_Name (Node);
            begin
               if Kind = "TaskTypeDecl"
                 or else Kind = "SingleTaskDecl"
                 or else Kind = "SingleTaskTypeDecl"
               then
                  declare
                     Decl : constant Libadalang.Analysis.Basic_Decl :=
                       Node.As_Basic_Decl;
                     Current : constant Munin.Tasks.Task_Unit :=
                       Munin.Tasks.Create
                         (Qualified_Name =>
                            To_Virtual_String (Decl.P_Fully_Qualified_Name),
                          Priority       => Priority_For (Decl));
                  begin
                     Append_Task_Unique (Self, Current);
                  end;

               elsif Kind = "SingleProtectedDecl"
               then
                  declare
                     Decl : constant Libadalang.Analysis.Basic_Decl :=
                       Node.As_Basic_Decl;
                  begin
                     Self.Protected_Items.Append
                       (Munin.Protected_Objects.Create
                          (Qualified_Name =>
                             To_Virtual_String (Decl.P_Fully_Qualified_Name),
                           Priority       => Priority_For (Decl)));
                  end;
               end if;

               return Libadalang.Common.Into;
            end Visit;
         begin
            if Unit.Has_Diagnostics then
               for D of Unit.Diagnostics loop
                  Append_Error (Errors, Unit.Format_GNU_Diagnostic (D));
               end loop;
            end if;

            if not Root.Is_Null then
               Libadalang.Analysis.Traverse (Root, Visit'Access);
            end if;
         end;
      end loop;
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