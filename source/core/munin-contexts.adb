--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Exceptions;

with GNATCOLL.GMP.Integers;
with Langkit_Support.Text;
with Libadalang.Common;

with Munin.Priorities;
with Munin.Project_Loading;
with Munin.Contexts.Traverses;

with VSS.Strings.Conversions;

package body Munin.Contexts is

   use type VSS.Strings.Virtual_String;

   use type Libadalang.Common.Ada_Node_Kind_Type;
   use type Libadalang.Common.Visit_Status;

   function To_Virtual_String
     (Value : Langkit_Support.Text.Text_Type)
      return VSS.Strings.Virtual_String;

   procedure Append_Error
     (Errors : in out VSS.String_Vectors.Virtual_String_Vector;
      Value  : String);

   function Priority_For
     (Decl : Libadalang.Analysis.Basic_Decl'Class)
      return Munin.Priorities.Optional_Priority;

   procedure Append_Task_Unique
     (Self : in out Context; Item : Munin.Tasks.Task_Unit);

   function To_Virtual_String
     (Value : Langkit_Support.Text.Text_Type) return VSS.Strings.Virtual_String
   is (VSS.Strings.To_Virtual_String (Value));

   procedure Append_Error
     (Errors : in out VSS.String_Vectors.Virtual_String_Vector; Value : String)
   is
   begin
      Errors.Append (VSS.Strings.Conversions.To_Virtual_String (Value));
   end Append_Error;

   function Priority_For
     (Decl : Libadalang.Analysis.Basic_Decl'Class)
      return Munin.Priorities.Optional_Priority
   is
      function Aspect_Expr (Name : String) return Libadalang.Analysis.Expr
      is (Decl.P_Get_Aspect_Spec_Expr
            (Langkit_Support.Text.To_Unbounded_Text
               (Langkit_Support.Text.To_Text (Name))));

      Priority_Expr : constant Libadalang.Analysis.Expr :=
        Aspect_Expr ("Priority");

      --  Ada RM 13.7: a task/protected declaration specifies at most one of
      --  Priority / Interrupt_Priority, so falling back to Interrupt_Priority
      --  only when Priority is absent is sufficient for valid code.
      Expr : constant Libadalang.Analysis.Expr :=
        (if Priority_Expr.Is_Null
         then Aspect_Expr ("Interrupt_Priority")
         else Priority_Expr);

      function Evaluated_Priority return Munin.Priorities.Optional_Priority
      is (Munin.Priorities.Explicit_Priority
            (Integer'Value
               (GNATCOLL.GMP.Integers.Image (Expr.P_Eval_As_Int))));
   begin
      if Expr.Is_Null then
         return Munin.Priorities.Default_Priority;
      end if;

      if Expr.P_Is_Static_Expr then
         return Evaluated_Priority;
      end if;

      --  Libadalang can evaluate some target-dependent predefined attributes
      --  even when the static-expression predicate is conservative.
      return Evaluated_Priority;

   exception
      when E : others =>
         raise Constraint_Error
           with
             (if Priority_Expr.Is_Null
              then "Interrupt_Priority"
              else "Priority")
             & " aspect must be static at "
             & String
                 (Langkit_Support.Text.To_UTF8
                    (Libadalang.Analysis.Full_Sloc_Image (Expr)))
             & ": "
             & String (Langkit_Support.Text.To_UTF8 (Expr.Text))
             & " ("
             & Ada.Exceptions.Exception_Message (E)
             & ")";
   end Priority_For;

   procedure Append_Task_Unique
     (Self : in out Context; Item : Munin.Tasks.Task_Unit)
   is
      Name : constant VSS.Strings.Virtual_String :=
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
      Path  : constant String :=
        VSS.Strings.Conversions.To_UTF_8_String (Project_File);
      Files : VSS.String_Vectors.Virtual_String_Vector;
   begin
      Errors.Clear;
      Self.Loaded_Project := Project_File;
      Self.Task_Items.Clear;
      Self.Protected_Items.Clear;

      Munin.Project_Loading.Load
        (Project_File     => Project_File,
         Tree             => Self.Project_Tree,
         Analysis_Context => Self.Analysis_Context,
         Sources          => Files,
         Errors           => Errors);

      if not Errors.Is_Empty then
         return;
      end if;

      Self.Sources := Files;

      --  Collect diagnostics from all files
      for File_Name of Files loop
         declare
            File_Path : constant String :=
              VSS.Strings.Conversions.To_UTF_8_String (File_Name);
            Unit      : constant Libadalang.Analysis.Analysis_Unit :=
              Self.Analysis_Context.Get_From_File (File_Path);
         begin
            if Unit.Has_Diagnostics then
               for D of Unit.Diagnostics loop
                  Append_Error (Errors, Unit.Format_GNU_Diagnostic (D));
               end loop;
            end if;
         end;
      end loop;

      --  Process library-level names, including those in
      --  generic instantiations
      declare
         procedure Process_Name (Name : Libadalang.Analysis.Defining_Name);

         procedure Process_Name (Name : Libadalang.Analysis.Defining_Name) is
         begin
            declare
               Node : constant Libadalang.Analysis.Ada_Node := Name.Parent;
               Kind : constant Libadalang.Common.Ada_Node_Kind_Type :=
                 Libadalang.Analysis.Kind (Node);
            begin
               if Kind
                  in Libadalang.Common.Ada_Task_Type_Decl
                   | Libadalang.Common.Ada_Single_Task_Decl
                   | Libadalang.Common.Ada_Single_Task_Type_Decl
               then
                  Append_Task_Unique
                    (Self,
                     Munin.Tasks.Create
                       (Qualified_Name =>
                          To_Virtual_String
                            (Node.As_Basic_Decl.P_Fully_Qualified_Name),
                        Priority       => Priority_For (Node.As_Basic_Decl)));

               elsif Kind = Libadalang.Common.Ada_Single_Protected_Decl then
                  Self.Protected_Items.Append
                    (Munin.Protected_Objects.Create
                       (Qualified_Name =>
                          To_Virtual_String
                            (Node.As_Basic_Decl.P_Fully_Qualified_Name),
                        Priority       => Priority_For (Node.As_Basic_Decl)));
               end if;
            end;
         exception
            when Libadalang.Common.Property_Error =>
               null;
         end Process_Name;
      begin
         Munin.Contexts.Traverses.Each_Library_Level_Name
           (Self, Process_Name'Access);
      end;

   exception
      when E : others =>
         Append_Error
           (Errors,
            "failed to initialize analysis context for '"
            & Path
            & "': "
            & Ada.Exceptions.Exception_Message (E));
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
      return
         Result : Munin.Protected_Objects.Protected_Object_Array (1 .. Last)
      do
         for Index in Result'Range loop
            Result (Index) := Self.Protected_Items.Element (Index);
         end loop;
      end return;
   end Protected_Objects;

end Munin.Contexts;
