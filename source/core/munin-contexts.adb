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
      Aspect_Name : constant Langkit_Support.Text.Unbounded_Text_Type :=
        Langkit_Support.Text.To_Unbounded_Text
          (Langkit_Support.Text.To_Text ("Priority"));

      Expr : constant Libadalang.Analysis.Expr :=
        Decl.P_Get_Aspect_Spec_Expr (Aspect_Name);

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
             "Priority aspect must be static at "
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

      for File_Name of Files loop
         declare
            File_Path           : constant String :=
              VSS.Strings.Conversions.To_UTF_8_String (File_Name);
            Unit                : constant Libadalang.Analysis.Analysis_Unit :=
              Self.Analysis_Context.Get_From_File (File_Path);
            Root                : constant Libadalang.Analysis.Ada_Node :=
              Unit.Root;
            Instantiation_Depth : Natural := 0;

            procedure Add_Task (Decl : Libadalang.Analysis.Basic_Decl'Class);

            procedure Add_Protected
              (Decl : Libadalang.Analysis.Basic_Decl'Class);

            procedure Process_Instance_Node
              (Node : Libadalang.Analysis.Ada_Node'Class);

            procedure Add_Task (Decl : Libadalang.Analysis.Basic_Decl'Class) is
            begin
               Append_Task_Unique
                 (Self,
                  Munin.Tasks.Create
                    (Qualified_Name =>
                       To_Virtual_String (Decl.P_Fully_Qualified_Name),
                     Priority       => Priority_For (Decl)));
            end Add_Task;

            procedure Add_Protected
              (Decl : Libadalang.Analysis.Basic_Decl'Class) is
            begin
               Self.Protected_Items.Append
                 (Munin.Protected_Objects.Create
                    (Qualified_Name =>
                       To_Virtual_String (Decl.P_Fully_Qualified_Name),
                     Priority       => Priority_For (Decl)));
            end Add_Protected;

            procedure Process_Instance_Node
              (Node : Libadalang.Analysis.Ada_Node'Class)
            is
               Node_Kind : constant Libadalang.Common.Ada_Node_Kind_Type :=
                 Libadalang.Analysis.Kind (Node);
            begin
               if Node_Kind
                  in Libadalang.Common.Ada_Task_Type_Decl
                   | Libadalang.Common.Ada_Single_Task_Decl
                   | Libadalang.Common.Ada_Single_Task_Type_Decl
               then
                  Add_Task (Node.As_Basic_Decl);

               elsif Node_Kind = Libadalang.Common.Ada_Single_Protected_Decl
               then
                  Add_Protected (Node.As_Basic_Decl);

               elsif Node_Kind
                 = Libadalang.Common.Ada_Generic_Package_Instantiation
               then
                  --  Skip nested instantiations inside generic bodies. Only
                  --  analyze instantiations at the top level (outside any
                  --  generic scope).
                  return;
               end if;

               for Child of Node.Children loop
                  if not Child.Is_Null then
                     Process_Instance_Node (Child);
                  end if;
               end loop;

            exception
               when Libadalang.Common.Property_Error =>
                  --  Some synthetic nodes in instantiated generic trees can
                  --  trigger invalid property requests in Libadalang.
                  --  Skip only the failing subtree and keep scanning
                  --  siblings.
                  null;
            end Process_Instance_Node;

            function Visit
              (Node : Libadalang.Analysis.Ada_Node'Class)
               return Libadalang.Common.Visit_Status;

            function Visit
              (Node : Libadalang.Analysis.Ada_Node'Class)
               return Libadalang.Common.Visit_Status
            is
               Kind : constant Libadalang.Common.Ada_Node_Kind_Type :=
                 Libadalang.Analysis.Kind (Node);

               --  Check if Node is inside a generic package template
               function Is_Inside_Generic_Template return Boolean;

               function Is_Inside_Generic_Template return Boolean is
                  Ancestor : Libadalang.Analysis.Ada_Node :=
                    Node.Parent.As_Ada_Node;
               begin
                  while not Ancestor.Is_Null loop
                     if Libadalang.Analysis.Kind (Ancestor)
                       = Libadalang.Common.Ada_Generic_Package_Decl
                     then
                        return True;
                     end if;
                     Ancestor := Ancestor.Parent.As_Ada_Node;
                  end loop;
                  return False;
               end Is_Inside_Generic_Template;
            begin
               if Kind = Libadalang.Common.Ada_Generic_Package_Instantiation
               then
                  --  Skip nested instantiations and instantiations
                  --  inside generic templates: only process top-level
                  --  instantiations outside of any generic scope.
                  if Instantiation_Depth > 0 or else Is_Inside_Generic_Template
                  then
                     return Libadalang.Common.Over;
                  end if;

                  begin
                     declare
                        Inst       :
                          constant Libadalang
                                     .Analysis
                                     .Generic_Package_Instantiation :=
                            Node.As_Generic_Package_Instantiation;
                        Designated :
                          constant Libadalang.Analysis.Generic_Decl :=
                            Inst.P_Designated_Generic_Decl;
                     begin
                        if not Designated.Is_Null
                          and then Designated.Kind
                                   = Libadalang.Common.Ada_Generic_Package_Decl
                        then
                           Instantiation_Depth := Instantiation_Depth + 1;
                           begin
                              declare
                                 Generic_Package :
                                   constant Libadalang
                                              .Analysis
                                              .Generic_Package_Decl :=
                                     Designated.As_Generic_Package_Decl;

                                 Package_Decl :
                                   constant Libadalang
                                              .Analysis
                                              .Generic_Package_Internal :=
                                     Generic_Package.F_Package_Decl;
                              begin
                                 Process_Instance_Node (Package_Decl);
                              end;
                           exception
                              when Libadalang.Common.Property_Error =>
                                 null;
                              when others =>
                                 Instantiation_Depth :=
                                   Instantiation_Depth - 1;
                                 raise;
                           end;
                           Instantiation_Depth := Instantiation_Depth - 1;
                        end if;
                     end;
                  exception
                     when Libadalang.Common.Property_Error =>
                        --  Some instantiation node properties are not
                        --  available or invalid; skip this instantiation.
                        null;
                  end;

                  return Libadalang.Common.Over;

               elsif Kind = Libadalang.Common.Ada_Generic_Package_Decl
                 and then Instantiation_Depth = 0
               then
                  --  Skip generic package specs in normal traversal. Their
                  --  instantiated declarations are traversed via a generic
                  --  package instantiation.
                  return Libadalang.Common.Over;

               elsif Kind = Libadalang.Common.Ada_Package_Body
                 and then Instantiation_Depth = 0
               then
                  --  Skip bodies of generic packages. Only instantiations
                  --  trigger analysis of a generic package's contents.
                  begin
                     declare
                        Spec : constant Libadalang.Analysis.Basic_Decl :=
                          Node.As_Package_Body.P_Decl_Part;
                     begin
                        if not Spec.Is_Null
                          and then Libadalang.Analysis.Kind (Spec)
                                   = Libadalang
                                       .Common
                                       .Ada_Generic_Package_Internal
                        then
                           return Libadalang.Common.Over;
                        end if;
                     end;
                  exception
                     when Libadalang.Common.Property_Error =>
                        null;
                  end;

               elsif Kind = Libadalang.Common.Ada_Task_Type_Decl
                 or else Kind = Libadalang.Common.Ada_Single_Task_Decl
                 or else Kind = Libadalang.Common.Ada_Single_Task_Type_Decl
               then
                  Add_Task (Node.As_Basic_Decl);

               elsif Kind = Libadalang.Common.Ada_Single_Protected_Decl then
                  Add_Protected (Node.As_Basic_Decl);
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
