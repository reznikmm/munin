--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Characters.Handling;
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
      function Build_Substitutions
        (Constraints : Libadalang.Analysis.Param_Actual_Array)
         return Libadalang.Analysis.Substitution_Array;

      function Build_Substitutions
        (Constraints : Libadalang.Analysis.Param_Actual_Array)
         return Libadalang.Analysis.Substitution_Array
      is
         Result : Libadalang.Analysis.Substitution_Array (Constraints'Range);
      begin
         for Index in Constraints'Range loop
            declare
               Discriminant : constant Libadalang.Analysis.Basic_Decl :=
                 Libadalang.Analysis.Param (Constraints (Index)).P_Basic_Decl;
            begin
               Result (Index) :=
                 Libadalang.Analysis.Create_Substitution
                   (From_Decl  => Discriminant,
                    To_Value   =>
                      Libadalang.Analysis.Actual (Constraints (Index))
                        .P_Eval_As_Int,
                    Value_Type =>
                      Discriminant.P_Type_Expression.P_Designated_Type_Decl);
            end;
         end loop;

         return Result;
      end Build_Substitutions;

      --  When Decl is a library-level object declaration of a named task/
      --  protected type (e.g. `Object : Accumulator (Pr => 10);`), the
      --  Priority/Interrupt_Priority aspect lives on the type, not the
      --  object, and may reference one of the type's discriminants; resolve
      --  both so a per-object priority can be evaluated using the object's
      --  actual discriminant value.
      Type_Expr : constant Libadalang.Analysis.Type_Expr :=
        (if Decl.Kind = Libadalang.Common.Ada_Object_Decl
         then Decl.P_Type_Expression
         else Libadalang.Analysis.No_Type_Expr);

      Designated_Type : constant Libadalang.Analysis.Base_Type_Decl :=
        (if Type_Expr.Is_Null
         then Libadalang.Analysis.No_Base_Type_Decl
         else Type_Expr.P_Designated_Type_Decl);

      Type_Decl : constant Libadalang.Analysis.Base_Type_Decl :=
        (if Designated_Type.Is_Null
         then Libadalang.Analysis.No_Base_Type_Decl
         else Designated_Type.P_Canonical_Type);

      --  The declaration that actually carries the Priority/
      --  Interrupt_Priority aspect: the resolved type for an object
      --  declaration, Decl itself for a task/protected (type) declaration.
      Aspect_Decl : constant Libadalang.Analysis.Basic_Decl'Class :=
        (if Type_Decl.Is_Null then Decl else Type_Decl);

      function Visible_Decls
        (Decl : Libadalang.Analysis.Basic_Decl'Class)
         return Libadalang.Analysis.Ada_Node_List
      is (case Decl.Kind is
            when Libadalang.Common.Ada_Task_Type_Decl_Range  =>
              (if Decl.As_Task_Type_Decl.F_Definition.Is_Null
               then Libadalang.Analysis.No_Ada_Node_List
               else Decl.As_Task_Type_Decl.F_Definition.F_Public_Part.F_Decls),
            when Libadalang.Common.Ada_Protected_Type_Decl   =>
              Decl.As_Protected_Type_Decl.F_Definition.F_Public_Part.F_Decls,
            when Libadalang.Common.Ada_Single_Protected_Decl =>
              Decl.As_Single_Protected_Decl.F_Definition.F_Public_Part.F_Decls,
            when others                                      =>
              Libadalang.Analysis.No_Ada_Node_List);
      --  Declarative items of the task/protected (type) declaration's
      --  visible part, where a pre-aspect `pragma Priority (...);` /
      --  `pragma Interrupt_Priority (...);` would be declared. Libadalang's
      --  own P_Get_Pragma does not reliably find such a pragma for a task
      --  declaration (unlike for a protected one), so it is searched for
      --  manually here, uniformly for both.

      function Pragma_Expr (Name : String) return Libadalang.Analysis.Expr;
      --  Return the argument expression of a `pragma Name (...);` found
      --  among Aspect_Decl's visible declarative items, if any.

      function Pragma_Expr (Name : String) return Libadalang.Analysis.Expr is
         Decls : constant Libadalang.Analysis.Ada_Node_List :=
           Visible_Decls (Aspect_Decl);
      begin
         if not Decls.Is_Null then
            for Item of Decls loop
               if Item.Kind = Libadalang.Common.Ada_Pragma_Node
                 and then Ada.Characters.Handling.To_Lower
                            (String
                               (Langkit_Support.Text.To_UTF8
                                  (Item.As_Pragma_Node.F_Id.Text)))
                          = Ada.Characters.Handling.To_Lower (Name)
               then
                  for Assoc of Item.As_Pragma_Node.F_Args loop
                     return Assoc.P_Assoc_Expr;
                  end loop;
               end if;
            end loop;
         end if;

         return Libadalang.Analysis.No_Expr;
      end Pragma_Expr;

      function Aspect_Expr (Name : String) return Libadalang.Analysis.Expr;
      --  Both the modern aspect syntax (`with Priority => ...`) and the
      --  older `pragma Priority (...);` form are recognized, in that order.

      function Aspect_Expr (Name : String) return Libadalang.Analysis.Expr is
         Spec_Expr : constant Libadalang.Analysis.Expr :=
           Aspect_Decl.P_Get_Aspect_Spec_Expr
             (Langkit_Support.Text.To_Unbounded_Text
                (Langkit_Support.Text.To_Text (Name)));
      begin
         return (if Spec_Expr.Is_Null then Pragma_Expr (Name) else Spec_Expr);
      end Aspect_Expr;

      Priority_Expr : constant Libadalang.Analysis.Expr :=
        Aspect_Expr ("Priority");

      --  Ada RM 13.7: a task/protected declaration specifies at most one of
      --  Priority / Interrupt_Priority, so falling back to Interrupt_Priority
      --  only when Priority is absent is sufficient for valid code.
      Expr : constant Libadalang.Analysis.Expr :=
        (if Priority_Expr.Is_Null
         then Aspect_Expr ("Interrupt_Priority")
         else Priority_Expr);

      --  Substitutions for the object's actual discriminant values, used to
      --  evaluate a discriminant-dependent Priority/Interrupt_Priority
      --  expression (Ada RM D.1); empty when Decl isn't an object
      --  declaration or its type has no discriminants.
      Substitutions : constant Libadalang.Analysis.Substitution_Array :=
        (if Type_Expr.Is_Null
         then []
         else Build_Substitutions (Type_Expr.P_Discriminant_Constraints));

      function Evaluated_Priority return Munin.Priorities.Optional_Priority
      is (Munin.Priorities.Explicit_Priority
            (Integer'Value
               (GNATCOLL.GMP.Integers.Image
                  (Expr.P_Eval_As_Int_In_Env (Substitutions)))));
   begin
      if Expr.Is_Null then
         return Munin.Priorities.Default_Priority;
      end if;

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
                 Node.Kind;
            begin
               --  Single task/protected declarations always denote one
               --  concrete object; a bare task/protected type declaration
               --  (with no object) never is, so it is never reported here.
               if Kind
                  in Libadalang.Common.Ada_Single_Task_Decl
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

               --  A library-level object declaration of a named task/
               --  protected type (e.g. `Object : Protected_Type;`) is a
               --  concrete object too; classify it by the designated type's
               --  kind, but never report the type declaration itself.
               elsif Kind = Libadalang.Common.Ada_Defining_Name_List
                 and then Node.Parent.Kind = Libadalang.Common.Ada_Object_Decl
               then
                  declare
                     Object_Decl : constant Libadalang.Analysis.Basic_Decl :=
                       Node.Parent.As_Basic_Decl;

                     Type_Expr : constant Libadalang.Analysis.Type_Expr :=
                       Object_Decl.P_Type_Expression;

                     Designated_Type :
                       constant Libadalang.Analysis.Base_Type_Decl :=
                         (if Type_Expr.Is_Null
                          then Libadalang.Analysis.No_Base_Type_Decl
                          else Type_Expr.P_Designated_Type_Decl);

                     Type_Decl : constant Libadalang.Analysis.Base_Type_Decl :=
                       (if Designated_Type.Is_Null
                        then Libadalang.Analysis.No_Base_Type_Decl
                        else Designated_Type.P_Canonical_Type);

                     Type_Kind :
                       constant Libadalang.Common.Ada_Node_Kind_Type :=
                         (if Type_Decl.Is_Null
                          then Libadalang.Common.Ada_Node_Kind_Type'First
                          else Type_Decl.Kind);
                  begin
                     if Type_Kind = Libadalang.Common.Ada_Protected_Type_Decl
                     then
                        Self.Protected_Items.Append
                          (Munin.Protected_Objects.Create
                             (Qualified_Name =>
                                To_Virtual_String
                                  (Name.P_Fully_Qualified_Name),
                              Priority       => Priority_For (Object_Decl)));

                     elsif Type_Kind = Libadalang.Common.Ada_Task_Type_Decl
                     then
                        Append_Task_Unique
                          (Self,
                           Munin.Tasks.Create
                             (Qualified_Name =>
                                To_Virtual_String
                                  (Name.P_Fully_Qualified_Name),
                              Priority       => Priority_For (Object_Decl)));
                     end if;
                  end;
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
