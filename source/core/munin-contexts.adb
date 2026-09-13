--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Characters.Handling;
with Ada.Exceptions;

with GNATCOLL.GMP.Integers;
with GPR2;
with GPR2.Build.Source.Sets;
with Langkit_Support.Slocs;
with Langkit_Support.Text;
with Libadalang.Common;

with Munin.Call_Graph_Providers.CI;
with Munin.Project_Loading;
with Munin.Contexts.Traverses;

with VSS.Strings.Conversions;

package body Munin.Contexts is

   use type VSS.Strings.Virtual_String;

   use type Libadalang.Common.Ada_Node_Kind_Type;

   type CI_Provider_Access is
     access all Munin.Call_Graph_Providers.CI.CI_Provider;
   --  A normally-allocatable access type used only to obtain the aliased
   --  CI_Provider that Self.Call_Graph (a zero-storage-size access type)
   --  is then converted to point at.

   procedure Load_Files
     (Self     : in out Context'Class;
      Units    : Libadalang.Analysis.Analysis_Unit_Array;
      Warnings : in out VSS.String_Vectors.Virtual_String_Vector);

   function To_Virtual_String
     (Value : Langkit_Support.Text.Text_Type)
      return VSS.Strings.Virtual_String;

   procedure Append_Error
     (Errors : in out VSS.String_Vectors.Virtual_String_Vector;
      Value  : String);

   function Priority_For
     (Decl : Libadalang.Analysis.Basic_Decl'Class)
      return Munin.Priorities.Optional_Priority;

   function Resolve_Default_Ceiling
     (Analysis_Context : Libadalang.Analysis.Analysis_Context'Class)
      return Munin.Priorities.Priority_Value;
   --  Evaluate System.Priority'Last for the runtime backing
   --  Analysis_Context -- Ada RM D.3's default ceiling for a protected
   --  object with no explicit Priority/Interrupt_Priority aspect, and the
   --  effective priority a task is raised to upon entering one.

   function Resolve_Default_Task_Priority
     (Analysis_Context : Libadalang.Analysis.Analysis_Context'Class)
      return Munin.Priorities.Priority_Value;
   --  Evaluate System.Default_Priority for the runtime backing
   --  Analysis_Context -- the priority a task runs at when it has no
   --  explicit Priority/Interrupt_Priority aspect.

   procedure Append_Task_Unique
     (Self : in out Context'Class; Item : Munin.Tasks.Task_Unit);

   procedure Append_Interrupt_Handler_Unique
     (Self : in out Context'Class;
      Item : Munin.Interrupt_Handlers.Interrupt_Handler);
   --  Self.Interrupt_Handler_Items.Append (Item), unless Item's Qualified_
   --  Name is already present -- true whenever the same protected type's
   --  handler procedure is seen again through another object of that type
   --  (Collect_Operations runs once per object, but a handler procedure's
   --  own declaration, and hence Qualified_Name, is shared by every object
   --  of its type).

   function To_Virtual_String
     (Value : Langkit_Support.Text.Text_Type) return VSS.Strings.Virtual_String
   is (VSS.Strings.To_Virtual_String (Value));

   function To_Source_Position
     (Unit : Libadalang.Analysis.Analysis_Unit'Class;
      Sloc : Langkit_Support.Slocs.Source_Location) return Optional_Position
   is (To_Position
         (File   =>
            VSS.Strings.Conversions.To_Virtual_String (Unit.Get_Filename),
          Line   => Positive (Sloc.Line),
          Column => Positive (Sloc.Column)));

   function To_Source_Position
     (Unit : Libadalang.Analysis.Analysis_Unit'Class;
      Sloc : Langkit_Support.Slocs.Source_Location_Range)
      return Optional_Position
   is (To_Source_Position (Unit, Langkit_Support.Slocs.Start_Sloc (Sloc)));

   function Body_Position
     (Decl      : Libadalang.Analysis.Basic_Decl'Class;
      Body_Kind : Libadalang.Common.Ada_Node_Kind_Type)
      return Optional_Position;
   --  Decl's own body's declaration position (e.g. the `task body Foo is`
   --  construct, for a task Decl) when Decl has a body of exactly
   --  Body_Kind; Is_Set => False otherwise (Decl has no body, or one of a
   --  different kind -- e.g. Decl is a generic template).

   function Body_Position
     (Decl      : Libadalang.Analysis.Basic_Decl'Class;
      Body_Kind : Libadalang.Common.Ada_Node_Kind_Type)
      return Optional_Position
   is
      Body_Part : constant Libadalang.Analysis.Body_Node :=
        Decl.P_Body_Part_For_Decl;
   begin
      if Body_Part.Is_Null or else Body_Part.Kind /= Body_Kind then
         return (Is_Set => False);
      end if;

      return To_Source_Position (Body_Part.Unit, Body_Part.Sloc_Range);
   end Body_Position;

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

      Full_Type_Decl : constant Libadalang.Analysis.Base_Type_Decl :=
        (if Type_Decl.Is_Null
           or else Type_Decl.Kind
                   in Libadalang.Common.Ada_Protected_Type_Decl
                    | Libadalang.Common.Ada_Task_Type_Decl_Range
           or else Type_Decl.P_Full_View.Is_Null
         then Type_Decl
         else Type_Decl.P_Full_View);
      --  A private type (e.g. Ada.Synchronous_Task_Control.Suspension_Object)
      --  can be implemented as protected/task in its full view, only
      --  visible from within the package that declares it. Follow that full
      --  view when the type itself isn't already a task/protected type.

      --  The declaration that actually carries the Priority/
      --  Interrupt_Priority aspect: the resolved (full) type for an object
      --  declaration, Decl itself for a task/protected (type) declaration.
      Aspect_Decl : constant Libadalang.Analysis.Basic_Decl'Class :=
        (if Full_Type_Decl.Is_Null then Decl else Full_Type_Decl);

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

   -----------------------------
   -- Resolve_Default_Ceiling --
   -----------------------------

   function Resolve_Default_Ceiling
     (Analysis_Context : Libadalang.Analysis.Analysis_Context'Class)
      return Munin.Priorities.Priority_Value
   is
      System_Unit : constant Libadalang.Analysis.Analysis_Unit :=
        Analysis_Context.Get_From_Provider
          (Name => Langkit_Support.Text.To_Text ("system"),
           Kind => Libadalang.Common.Unit_Specification);

      System_Decl : constant Libadalang.Analysis.Basic_Decl :=
        (if System_Unit.Root.Is_Null
           or else System_Unit.Root.Kind
                   /= Libadalang.Common.Ada_Compilation_Unit
         then Libadalang.Analysis.No_Basic_Decl
         else System_Unit.Root.As_Compilation_Unit.P_Decl);

      Public_Decls : constant Libadalang.Analysis.Ada_Node_List :=
        (if System_Decl.Is_Null
           or else System_Decl.Kind /= Libadalang.Common.Ada_Package_Decl
         then Libadalang.Analysis.No_Ada_Node_List
         else System_Decl.As_Base_Package_Decl.F_Public_Part.F_Decls);

      Priority_Decl : Libadalang.Analysis.Base_Type_Decl :=
        Libadalang.Analysis.No_Base_Type_Decl;
   begin
      if not Public_Decls.Is_Null then
         for Item of Public_Decls loop
            if Item.Kind = Libadalang.Common.Ada_Subtype_Decl
              and then Ada.Characters.Handling.To_Lower
                         (String
                            (Langkit_Support.Text.To_UTF8
                               (Item.As_Basic_Decl.P_Defining_Name.Text)))
                       = "priority"
            then
               Priority_Decl := Item.As_Base_Type_Decl;
               exit;
            end if;
         end loop;
      end if;

      if Priority_Decl.Is_Null then
         raise Constraint_Error
           with "Unable to locate System.Priority in the target runtime";
      end if;

      return
        Munin.Priorities.Priority_Value'Value
          (GNATCOLL.GMP.Integers.Image
             (Libadalang.Analysis.High_Bound (Priority_Decl.P_Discrete_Range)
                .P_Eval_As_Int));

   exception
      when Libadalang.Common.Property_Error =>
         raise Constraint_Error
           with
             "Unable to resolve System.Priority'Last from the target"
             & " runtime";
   end Resolve_Default_Ceiling;

   -----------------------------------
   -- Resolve_Default_Task_Priority --
   -----------------------------------

   function Resolve_Default_Task_Priority
     (Analysis_Context : Libadalang.Analysis.Analysis_Context'Class)
      return Munin.Priorities.Priority_Value
   is
      System_Unit : constant Libadalang.Analysis.Analysis_Unit :=
        Analysis_Context.Get_From_Provider
          (Name => Langkit_Support.Text.To_Text ("system"),
           Kind => Libadalang.Common.Unit_Specification);

      System_Decl : constant Libadalang.Analysis.Basic_Decl :=
        (if System_Unit.Root.Is_Null
           or else System_Unit.Root.Kind
                   /= Libadalang.Common.Ada_Compilation_Unit
         then Libadalang.Analysis.No_Basic_Decl
         else System_Unit.Root.As_Compilation_Unit.P_Decl);

      Public_Decls : constant Libadalang.Analysis.Ada_Node_List :=
        (if System_Decl.Is_Null
           or else System_Decl.Kind /= Libadalang.Common.Ada_Package_Decl
         then Libadalang.Analysis.No_Ada_Node_List
         else System_Decl.As_Base_Package_Decl.F_Public_Part.F_Decls);

      Default_Priority_Decl : Libadalang.Analysis.Object_Decl :=
        Libadalang.Analysis.No_Object_Decl;
   begin
      if not Public_Decls.Is_Null then
         for Item of Public_Decls loop
            if Item.Kind = Libadalang.Common.Ada_Object_Decl
              and then Ada.Characters.Handling.To_Lower
                         (String
                            (Langkit_Support.Text.To_UTF8
                               (Item.As_Basic_Decl.P_Defining_Name.Text)))
                       = "default_priority"
            then
               Default_Priority_Decl := Item.As_Object_Decl;
               exit;
            end if;
         end loop;
      end if;

      if Default_Priority_Decl.Is_Null then
         raise Constraint_Error
           with
             "Unable to locate System.Default_Priority in the target"
             & " runtime";
      end if;

      return
        Munin.Priorities.Priority_Value'Value
          (GNATCOLL.GMP.Integers.Image
             (Default_Priority_Decl.F_Default_Expr.P_Eval_As_Int));

   exception
      when Libadalang.Common.Property_Error =>
         raise Constraint_Error
           with
             "Unable to resolve System.Default_Priority from the target"
             & " runtime";
   end Resolve_Default_Task_Priority;

   procedure Append_Task_Unique
     (Self : in out Context'Class; Item : Munin.Tasks.Task_Unit)
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

   procedure Append_Interrupt_Handler_Unique
     (Self : in out Context'Class;
      Item : Munin.Interrupt_Handlers.Interrupt_Handler)
   is
      Name : constant VSS.Strings.Virtual_String :=
        Munin.Interrupt_Handlers.Qualified_Name (Item);
   begin
      for Existing of Self.Interrupt_Handler_Items loop
         if Munin.Interrupt_Handlers.Qualified_Name (Existing) = Name then
            return;
         end if;
      end loop;

      Self.Interrupt_Handler_Items.Append (Item);
   end Append_Interrupt_Handler_Unique;

   procedure Load_Files
     (Self     : in out Context'Class;
      Units    : Libadalang.Analysis.Analysis_Unit_Array;
      Warnings : in out VSS.String_Vectors.Virtual_String_Vector)
   is
      function Compute_Own_Sources
         return VSS.String_Vectors.Virtual_String_Vector;
      --  The root project's own Ada source files -- not its dependencies,
      --  and not the runtime -- unlike Self.Sources, which deliberately
      --  spans the whole project closure (needed for Units, so that
      --  project-wide P_Find_All_Calls queries below also see calls made
      --  from within a dependency). A call whose target object can't be
      --  determined is only worth reporting when it sits in this
      --  narrower set: a call inside a dependency (e.g. Ada.
      --  Synchronous_Task_Control's own body, parameterized over "any
      --  object of this type") is typically unresolvable there by
      --  construction, and not something the project's own author can
      --  act on.

      function Compute_Own_Sources
         return VSS.String_Vectors.Virtual_String_Vector
      is
         use type GPR2.Language_Id;

         Result : VSS.String_Vectors.Virtual_String_Vector;
      begin
         for Source of Self.Project_Tree.Root_Project.Sources loop
            if Source.Language = GPR2.Ada_Language
              and then Source.Path_Name.Has_Value
            then
               Result.Append
                 (VSS.Strings.Conversions.To_Virtual_String
                    (String (Source.Path_Name.Value)));
            end if;
         end loop;

         return Result;
      end Compute_Own_Sources;

      Own_Sources : constant VSS.String_Vectors.Virtual_String_Vector :=
        Compute_Own_Sources;

      function Call_Site_Position
        (Ref : Libadalang.Analysis.Base_Id'Class) return Optional_Position;
      --  Ref's own position, unless it is the selector of a dotted
      --  name (the usual `Object.Entry_Name;` form), in which case the
      --  position of the '.' that precedes it -- what GCC records as
      --  the call site for the edge into its generic entry-call
      --  dispatcher (confirmed empirically; see the design notes for
      --  Munin.Call_Graph_Providers.CI_Databases.Complete).

      function Call_Site_Position
        (Ref : Libadalang.Analysis.Base_Id'Class) return Optional_Position
      is
         use type Libadalang.Common.Token_Reference;
         use type Libadalang.Common.Token_Kind;

         Previous_Token : constant Libadalang.Common.Token_Reference :=
           Libadalang.Common.Previous (Ref.Token_Start);
      begin
         if Previous_Token /= Libadalang.Common.No_Token
           and then Libadalang.Common.Kind
                      (Libadalang.Common.Data (Previous_Token))
                    = Libadalang.Common.Ada_Dot
         then
            return
              To_Source_Position
                (Ref.Unit,
                 Libadalang.Common.Sloc_Range
                   (Libadalang.Common.Data (Previous_Token)));
         end if;

         return To_Source_Position (Ref.Unit, Ref.Sloc_Range);
      end Call_Site_Position;

      procedure Collect_Operations
        (Decl  : Libadalang.Analysis.Basic_Decl'Class;
         Owner : VSS.Strings.Virtual_String);
      --  For every entry, procedure, or function in Decl's (a protected
      --  declaration's) visible part, resolve every call to it
      --  project-wide (via Units/P_Find_All_Calls) and record the object
      --  it targets: Owner itself for an unqualified self-call from
      --  within the object's own body (the only way Ada allows one), or
      --  the call's dotted prefix resolved via Libadalang cross-reference
      --  otherwise. A call whose target object can't be determined this
      --  way is reported via Warnings instead of recorded. Entries
      --  additionally resolve their own body position into Entry_Calls,
      --  exactly as before -- unrelated machinery, untouched.

      procedure Process_Name (Name : Libadalang.Analysis.Defining_Name);

      procedure Collect_Operations
        (Decl  : Libadalang.Analysis.Basic_Decl'Class;
         Owner : VSS.Strings.Virtual_String)
      is
         function Owner_Of_Call
           (Reference : Libadalang.Analysis.Base_Id'Class)
            return VSS.Strings.Virtual_String;
         --  The qualified name of the protected object statically
         --  identified as the target of the call at Reference: Owner
         --  itself when Reference is not the selector of a dotted name
         --  (an unqualified self-call -- Ada requires a prefix for any
         --  call from outside the object's own body, so this can only be
         --  one), or the dotted name's prefix's referenced object
         --  otherwise. Empty when the prefix doesn't resolve to a plain
         --  object declaration -- an ordinary object (e.g. `Acc_10 :
         --  Accumulator (10);`) or an anonymous single protected object
         --  (`protected Guard is ... end Guard;`, whose own name resolves
         --  directly to its Single_Protected_Decl, not to a wrapping
         --  Object_Decl) -- or Property_Error is raised while trying.

         function Owner_Of_Call
           (Reference : Libadalang.Analysis.Base_Id'Class)
            return VSS.Strings.Virtual_String
         is
            Parent : constant Libadalang.Analysis.Ada_Node := Reference.Parent;
         begin
            if Parent.Kind /= Libadalang.Common.Ada_Dotted_Name then
               return Owner;
            end if;

            declare
               Prefix : constant Libadalang.Analysis.Name :=
                 Parent.As_Dotted_Name.F_Prefix;
            begin
               --  Reject anything more complex than a plain (possibly
               --  qualified) name up front: P_Referenced_Decl on an
               --  indexing expression like `Cells (I)` resolves to the
               --  array object itself, discarding the index, which would
               --  otherwise be silently (and wrongly) accepted as if it
               --  named one specific element. Likewise for an explicit
               --  dereference (`Ptr.all.Op`).
               if Prefix.Kind
                  not in Libadalang.Common.Ada_Identifier
                       | Libadalang.Common.Ada_Dotted_Name
               then
                  return VSS.Strings.Empty_Virtual_String;
               end if;

               declare
                  Object_Decl : constant Libadalang.Analysis.Basic_Decl :=
                    Prefix.P_Referenced_Decl;
               begin
                  if Object_Decl.Is_Null
                    or else Object_Decl.Kind
                            not in Libadalang.Common.Ada_Object_Decl
                                 | Libadalang.Common.Ada_Single_Protected_Decl
                  then
                     return VSS.Strings.Empty_Virtual_String;
                  end if;

                  return
                    To_Virtual_String (Object_Decl.P_Fully_Qualified_Name);
               end;
            end;
         exception
            when Libadalang.Common.Property_Error =>
               return VSS.Strings.Empty_Virtual_String;
         end Owner_Of_Call;

         procedure Handle_Call (Reference : Libadalang.Analysis.Base_Id'Class);
         --  Record Reference's target object in Protected_Operations, or
         --  append a diagnostic to Warnings when it can't be determined --
         --  but only when Reference itself sits in one of the project's
         --  own sources. A call written inside the runtime's own
         --  implementation (e.g. a generic protected-type body in
         --  Ada.Synchronous_Task_Control, reached via Full_Type_Decl for
         --  a private-type object like a Suspension_Object) is typically
         --  parameterized over "any object of this type" and therefore
         --  genuinely, permanently unresolvable there -- not a call the
         --  project's own author can act on, so it is silently skipped
         --  rather than reported.

         procedure Handle_Call (Reference : Libadalang.Analysis.Base_Id'Class)
         is
            function Trimmed_Image (Value : Positive) return String;

            function Trimmed_Image (Value : Positive) return String is
               Image : constant String := Value'Image;
            begin
               return Image (Image'First + 1 .. Image'Last);
            end Trimmed_Image;

            Call_Owner : VSS.Strings.Virtual_String;
            Call_Site  : Position;
         begin
            if not Own_Sources.Contains
                     (VSS.Strings.Conversions.To_Virtual_String
                        (Reference.Unit.Get_Filename))
            then
               return;
            end if;

            Call_Owner := Owner_Of_Call (Reference);
            Call_Site := Call_Site_Position (Reference);

            if Call_Owner.Is_Empty then
               Warnings.Append
                 (VSS.Strings.Conversions.To_Virtual_String
                    (VSS.Strings.Conversions.To_UTF_8_String (Call_Site.File)
                     & ":"
                     & Trimmed_Image (Call_Site.Line)
                     & ":"
                     & Trimmed_Image (Call_Site.Column)
                     & ": cannot determine which protected object is"
                     & " called here"));
            else
               Self.Protected_Operations.Set_Protected_Object
                 (Call_Site, Call_Owner);
            end if;
         end Handle_Call;

         Decls : constant Libadalang.Analysis.Ada_Node_List :=
           (case Decl.Kind is
              when Libadalang.Common.Ada_Single_Protected_Decl =>
                Decl
                  .As_Single_Protected_Decl
                  .F_Definition
                  .F_Public_Part
                  .F_Decls,
              when Libadalang.Common.Ada_Protected_Type_Decl   =>
                Decl.As_Protected_Type_Decl.F_Definition.F_Public_Part.F_Decls,
              when others                                      =>
                Libadalang.Analysis.No_Ada_Node_List);

         function Has_Handler_Pragma
           (Op : Libadalang.Analysis.Basic_Decl'Class; Name : String)
            return Boolean;
         --  True when a `pragma Name (Op, ...);` -- the pre-aspect syntax
         --  for Interrupt_Handler/Attach_Handler, naming Op as its first
         --  argument -- sits among Decls, the same visible declarative
         --  items Op itself was found in.

         function Has_Handler_Pragma
           (Op : Libadalang.Analysis.Basic_Decl'Class; Name : String)
            return Boolean
         is
            Op_Name : constant String :=
              Ada.Characters.Handling.To_Lower
                (String
                   (Langkit_Support.Text.To_UTF8 (Op.P_Defining_Name.Text)));
         begin
            if Decls.Is_Null then
               return False;
            end if;

            for Item of Decls loop
               if Item.Kind = Libadalang.Common.Ada_Pragma_Node
                 and then Ada.Characters.Handling.To_Lower
                            (String
                               (Langkit_Support.Text.To_UTF8
                                  (Item.As_Pragma_Node.F_Id.Text)))
                          = Ada.Characters.Handling.To_Lower (Name)
               then
                  for Assoc of Item.As_Pragma_Node.F_Args loop
                     if Ada.Characters.Handling.To_Lower
                          (String
                             (Langkit_Support.Text.To_UTF8
                                (Assoc.P_Assoc_Expr.Text)))
                       = Op_Name
                     then
                        return True;
                     end if;
                  end loop;
               end if;
            end loop;

            return False;
         end Has_Handler_Pragma;

         function Is_Interrupt_Handler
           (Op : Libadalang.Analysis.Basic_Decl'Class) return Boolean;
         --  True when Op (an individual protected procedure) is itself
         --  registered as an interrupt handler, via Ada RM C.3.1's
         --  Interrupt_Handler or Attach_Handler aspect (modern `with ...`
         --  syntax, recognized regardless of whether it carries a value)
         --  or its pre-aspect pragma equivalent.

         function Is_Interrupt_Handler
           (Op : Libadalang.Analysis.Basic_Decl'Class) return Boolean
         is (Op.P_Has_Aspect
               (Langkit_Support.Text.To_Unbounded_Text
                  (Langkit_Support.Text.To_Text ("Interrupt_Handler")))
             or else Op.P_Has_Aspect
                       (Langkit_Support.Text.To_Unbounded_Text
                          (Langkit_Support.Text.To_Text ("Attach_Handler")))
             or else Has_Handler_Pragma (Op, "Interrupt_Handler")
             or else Has_Handler_Pragma (Op, "Attach_Handler"));
      begin
         if Decls.Is_Null then
            return;
         end if;

         for Item of Decls loop
            case Item.Kind is
               when Libadalang.Common.Ada_Entry_Decl =>
                  declare
                     Entry_Item : constant Libadalang.Analysis.Entry_Decl :=
                       Item.As_Entry_Decl;
                     Entry_Body : constant Libadalang.Analysis.Body_Node :=
                       Entry_Item.P_Body_Part;
                  begin
                     if not Entry_Body.Is_Null then
                        declare
                           Target_Position : constant Optional_Position :=
                             To_Source_Position
                               (Entry_Body.Unit, Entry_Body.Sloc_Range);

                           Refs :
                             constant Libadalang.Analysis.Ref_Result_Array :=
                               Entry_Item.F_Spec.F_Entry_Name.P_Find_All_Calls
                                 (Units => Units);
                        begin
                           for Ref of Refs loop
                              declare
                                 Reference :
                                   constant Libadalang
                                              .Analysis
                                              .Base_Id'Class :=
                                     Libadalang.Analysis.Ref (Ref);
                              begin
                                 Self.Entry_Calls.Include
                                   (Call_Site_Position (Reference),
                                    Target_Position);
                                 Handle_Call (Reference);
                              end;
                           end loop;
                        end;
                     end if;
                  end;

               when Libadalang.Common.Ada_Subp_Decl  =>
                  declare
                     Subp_Item : constant Libadalang.Analysis.Subp_Decl :=
                       Item.As_Subp_Decl;
                     Refs      :
                       constant Libadalang.Analysis.Ref_Result_Array :=
                         Subp_Item.F_Subp_Spec.F_Subp_Name.P_Find_All_Calls
                           (Units => Units);
                  begin
                     for Ref of Refs loop
                        Handle_Call (Libadalang.Analysis.Ref (Ref));
                     end loop;

                     if Is_Interrupt_Handler (Subp_Item.As_Basic_Decl) then
                        Append_Interrupt_Handler_Unique
                          (Self,
                           Munin.Interrupt_Handlers.Create
                             (Qualified_Name   =>
                                To_Virtual_String
                                  (Subp_Item
                                     .As_Basic_Decl
                                     .P_Fully_Qualified_Name),
                              Protected_Object => Owner,
                              Position         =>
                                Body_Position
                                  (Subp_Item.As_Basic_Decl,
                                   Libadalang.Common.Ada_Subp_Body)));
                     end if;
                  end;

               when others                           =>
                  null;
            end case;
         end loop;
      exception
         when Libadalang.Common.Property_Error =>
            null;
      end Collect_Operations;

      procedure Process_Name (Name : Libadalang.Analysis.Defining_Name) is
         Node : constant Libadalang.Analysis.Ada_Node := Name.Parent;
      begin
         case Node.Kind is
            --  Single task/protected declarations always denote one
            --  concrete object; a bare task/protected type declaration
            --  (with no object) never is, so it is never reported here.

            when Libadalang.Common.Ada_Single_Task_Decl
               | Libadalang.Common.Ada_Single_Task_Type_Decl =>
               Append_Task_Unique
                 (Self,
                  Munin.Tasks.Create
                    (Qualified_Name =>
                       To_Virtual_String
                         (Node.As_Basic_Decl.P_Fully_Qualified_Name),
                     Priority       => Priority_For (Node.As_Basic_Decl),
                     Position       =>
                       Body_Position
                         (Node.As_Basic_Decl,
                          Libadalang.Common.Ada_Task_Body)));

            when Libadalang.Common.Ada_Single_Protected_Decl =>
               declare
                  Qualified_Name : constant VSS.Strings.Virtual_String :=
                    To_Virtual_String
                      (Node.As_Basic_Decl.P_Fully_Qualified_Name);
               begin
                  Self.Protected_Items.Include
                    (Qualified_Name,
                     Munin.Protected_Objects.Create
                       (Qualified_Name => Qualified_Name,
                        Priority       => Priority_For (Node.As_Basic_Decl),
                        Position       =>
                          Body_Position
                            (Node.As_Basic_Decl,
                             Libadalang.Common.Ada_Protected_Body)));
                  Collect_Operations (Node.As_Basic_Decl, Qualified_Name);
               end;

            --  A library-level object declaration of a named task/
            --  protected type (e.g. `Object : Protected_Type;`) is a
            --  concrete object too; classify it by the designated type's
            --  kind, but never report the type declaration itself.

            when Libadalang.Common.Ada_Defining_Name_List    =>
               if Node.Parent.Kind = Libadalang.Common.Ada_Object_Decl then
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

                     Full_Type_Decl :
                       constant Libadalang.Analysis.Base_Type_Decl :=
                         (if Type_Decl.Is_Null
                            or else Type_Decl.Kind
                                    in Libadalang
                                         .Common
                                         .Ada_Protected_Type_Decl
                                     | Libadalang
                                         .Common
                                         .Ada_Task_Type_Decl_Range
                            or else Type_Decl.P_Full_View.Is_Null
                          then Type_Decl
                          else Type_Decl.P_Full_View);
                     --  A private type (e.g.
                     --  Ada.Synchronous_Task_Control.Suspension_Object) can
                     --  be implemented as protected/task in its full view;
                     --  follow it when Type_Decl itself isn't already one.

                     Type_Kind :
                       constant Libadalang.Common.Ada_Node_Kind_Type :=
                         (if Full_Type_Decl.Is_Null
                          then Libadalang.Common.Ada_Node_Kind_Type'First
                          else Full_Type_Decl.Kind);
                  begin
                     --  Position, here, is the shared task/protected
                     --  type's own body -- every object of the same type
                     --  necessarily gets the same Position, since GNAT
                     --  compiles the type's body once. Task_Priority's
                     --  Position-based match is then ambiguous among
                     --  them, same as the call graph's own single shared
                     --  `.ci` node for all such objects.
                     if Type_Kind = Libadalang.Common.Ada_Protected_Type_Decl
                     then
                        declare
                           Qualified_Name :
                             constant VSS.Strings.Virtual_String :=
                               To_Virtual_String (Name.P_Fully_Qualified_Name);
                        begin
                           Self.Protected_Items.Include
                             (Qualified_Name,
                              Munin.Protected_Objects.Create
                                (Qualified_Name => Qualified_Name,
                                 Priority       => Priority_For (Object_Decl),
                                 Position       =>
                                   Body_Position
                                     (Full_Type_Decl.As_Basic_Decl,
                                      Libadalang.Common.Ada_Protected_Body)));
                           Collect_Operations
                             (Full_Type_Decl.As_Basic_Decl, Qualified_Name);
                        end;

                     elsif Type_Kind = Libadalang.Common.Ada_Task_Type_Decl
                     then
                        Append_Task_Unique
                          (Self,
                           Munin.Tasks.Create
                             (Qualified_Name =>
                                To_Virtual_String
                                  (Name.P_Fully_Qualified_Name),
                              Priority       => Priority_For (Object_Decl),
                              Position       =>
                                Body_Position
                                  (Full_Type_Decl.As_Basic_Decl,
                                   Libadalang.Common.Ada_Task_Body)));
                     end if;
                  end;
               end if;

            when others                                      =>
               null;
         end case;
      exception
         when Libadalang.Common.Property_Error =>
            null;
      end Process_Name;

   begin
      --  Process library-level names, including those in
      --  generic instantiations

      Munin.Contexts.Traverses.Each_Library_Level_Name
        (Self, Process_Name'Access);

      Munin.Contexts.Traverses.Each_Effectively_Global_Name
        (Self, Process_Name'Access);
   end Load_Files;

   procedure Load_Project
     (Self         : in out Context;
      Project_File : VSS.Strings.Virtual_String;
      Errors       : out VSS.String_Vectors.Virtual_String_Vector;
      Warnings     : out VSS.String_Vectors.Virtual_String_Vector)
   is
      Path  : constant String :=
        VSS.Strings.Conversions.To_UTF_8_String (Project_File);
      Files : VSS.String_Vectors.Virtual_String_Vector;
   begin
      Errors.Clear;
      Warnings.Clear;
      Self.Loaded_Project := Project_File;
      Self.Task_Items.Clear;
      Self.Protected_Items.Clear;
      Self.Interrupt_Handler_Items.Clear;
      Self.Call_Graph := null;
      Self.Call_Graph_Error := VSS.Strings.Empty_Virtual_String;

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

      --  Collect diagnostics from all files, and keep every unit around
      --  (Units) for Entry_Call_Targets' project-wide P_Find_All_Calls
      --  query below.
      declare
         Units : Libadalang.Analysis.Analysis_Unit_Array (1 .. Files.Length);
      begin
         for Index in Units'Range loop
            declare
               File_Path : constant String :=
                 VSS.Strings.Conversions.To_UTF_8_String
                   (Files.Element (Index));
               Unit      : constant Libadalang.Analysis.Analysis_Unit :=
                 Self.Analysis_Context.Get_From_File (File_Path);
            begin
               Units (Index) := Unit;

               if Unit.Has_Diagnostics then
                  for D of Unit.Diagnostics loop
                     Append_Error (Errors, Unit.Format_GNU_Diagnostic (D));
                  end loop;
               end if;
            end;
         end loop;

         Self.Load_Files (Units, Warnings);
      end;

      Self.Default_Ceiling := Resolve_Default_Ceiling (Self.Analysis_Context);
      Self.Default_Task_Priority :=
        Resolve_Default_Task_Priority (Self.Analysis_Context);

      declare
         Provider : constant CI_Provider_Access :=
           new Munin.Call_Graph_Providers.CI.CI_Provider;
      begin
         Munin.Call_Graph_Providers.CI.Initialize
           (Provider.all,
            Self.Project_Tree,
            Self.Entry_Calls,
            Self.Protected_Operations,
            Self.Call_Graph_Error);

         if Self.Call_Graph_Error.Is_Empty then
            Self.Call_Graph :=
              Munin.Call_Graph_Providers.Call_Graph_Provider_Access (Provider);
         end if;
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
      Last : constant Natural := Natural (Self.Protected_Items.Length);
   begin
      return
         Result : Munin.Protected_Objects.Protected_Object_Array (1 .. Last)
      do
         declare
            Index : Positive := Result'First;
         begin
            for Item of Self.Protected_Items loop
               Result (Index) := Item;
               Index := Index + 1;
            end loop;
         end;
      end return;
   end Protected_Objects;

   function Interrupt_Handlers
     (Self : Context) return Munin.Interrupt_Handlers.Interrupt_Handler_Array
   is
      Last : constant Natural := Self.Interrupt_Handler_Items.Last_Index;
   begin
      return
         Result : Munin.Interrupt_Handlers.Interrupt_Handler_Array (1 .. Last)
      do
         for Index in Result'Range loop
            Result (Index) := Self.Interrupt_Handler_Items.Element (Index);
         end loop;
      end return;
   end Interrupt_Handlers;

   function Task_Priority
     (Self : Context; Task_Position : Munin.Optional_Position)
      return Munin.Priorities.Priority_Value is
   begin
      --  Task_Position unset (no source position known for the root at
      --  all -- true of the environment task, whose Position, when set,
      --  points into compiler-generated code, not user source) always
      --  means "no match": deliberately checked first and returned on
      --  its own, rather than falling into the loop below and relying
      --  on Optional_Position's predefined "=" to reject it -- two
      --  unset positions *are* equal under that "=" (the variant has no
      --  fields left to compare once Is_Set is False), so comparing an
      --  unset Task_Position against an Item with an equally-unset
      --  Position would otherwise match by accident.
      if not Task_Position.Is_Set then
         return Self.Default_Task_Priority;
      end if;

      for Item of Self.Task_Items loop
         if Munin.Tasks.Position (Item) = Task_Position then
            declare
               Priority : constant Munin.Priorities.Optional_Priority :=
                 Munin.Tasks.Priority (Item);
            begin
               return
                 (if Priority.Has_Value
                  then Priority.Value
                  else Self.Default_Task_Priority);
            end;
         end if;
      end loop;

      return Self.Default_Task_Priority;
   end Task_Priority;

   function Protected_Object_Ceiling
     (Self : Context; Qualified_Name : VSS.Strings.Virtual_String)
      return Munin.Priorities.Priority_Value
   is
      Cursor : constant Protected_Object_Maps.Cursor :=
        Self.Protected_Items.Find (Qualified_Name);
   begin
      if not Protected_Object_Maps.Has_Element (Cursor) then
         return Self.Default_Ceiling;
      end if;

      declare
         Priority : constant Munin.Priorities.Optional_Priority :=
           Munin.Protected_Objects.Priority
             (Protected_Object_Maps.Element (Cursor));
      begin
         return
           (if Priority.Has_Value
            then Priority.Value
            else Self.Default_Ceiling);
      end;
   end Protected_Object_Ceiling;

end Munin.Contexts;
