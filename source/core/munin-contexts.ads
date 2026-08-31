--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;

with GPR2.Project.Tree;
with Libadalang.Analysis;

with VSS.String_Vectors;
with VSS.Strings;

with Munin.Call_Graph_Providers;
with Munin.Entry_Calls;
with Munin.Priorities;
with Munin.Protected_Objects;
with Munin.Protected_Operations;
with Munin.Tasks;

package Munin.Contexts is

   type Context is tagged limited private;

   procedure Load_Project
     (Self         : in out Context;
      Project_File : VSS.Strings.Virtual_String;
      Errors       : out VSS.String_Vectors.Virtual_String_Vector;
      Warnings     : out VSS.String_Vectors.Virtual_String_Vector);
   --  Errors reports issues serious enough that the project couldn't be
   --  fully understood (a project file failed to load or parse, or a
   --  compile unit has GNU diagnostics); a caller should treat a non-empty
   --  Errors as fatal to further analysis. Warnings reports narrower,
   --  non-fatal notices -- currently just "cannot determine which
   --  protected object is called here" for one specific call site -- that
   --  don't prevent everything else Self reports from still being
   --  meaningful.

   function Tasks (Self : Context) return Munin.Tasks.Task_Unit_Array;

   function Protected_Objects
     (Self : Context) return Munin.Protected_Objects.Protected_Object_Array;

   function Call_Graph
     (Self : Context)
      return Munin.Call_Graph_Providers.Call_Graph_Provider_Access;
   --  Null when Load_Project could not find or parse any `.ci` file for
   --  the project (see Call_Graph_Error for why).

   function Call_Graph_Error
     (Self : Context) return VSS.Strings.Virtual_String;
   --  Explanation for why Call_Graph is null; empty when Call_Graph is
   --  set.

   function Default_Ceiling
     (Self : Context) return Munin.Priorities.Priority_Value;
   --  System.Priority'Last for the runtime Self was loaded against -- the
   --  ceiling Ada RM D.3 assigns a protected object with no explicit
   --  Priority/Interrupt_Priority aspect, and the effective priority a
   --  task is raised to upon entering one. Meaningful only after a
   --  successful Load_Project.

   function Default_Task_Priority
     (Self : Context) return Munin.Priorities.Priority_Value;
   --  System.Default_Priority for the runtime Self was loaded against --
   --  the priority a task runs at when it has no explicit
   --  Priority/Interrupt_Priority aspect. Meaningful only after a
   --  successful Load_Project.

   function Task_Priority
     (Self          : Context;
      Task_Position : Munin.Optional_Position)
      return Munin.Priorities.Priority_Value;
   --  The priority assigned to the task whose body is declared at
   --  Task_Position, or Default_Task_Priority when it has no explicit
   --  priority, when Task_Position matches no task known to Self (e.g.
   --  the environment task, whose Position points into compiler-
   --  generated code, not any Munin.Tasks.Task_Unit's own), or when
   --  Task_Position itself is unset.

   function Protected_Object_Ceiling
     (Self           : Context;
      Qualified_Name : VSS.Strings.Virtual_String)
      return Munin.Priorities.Priority_Value;
   --  The ceiling of the protected object named Qualified_Name, or
   --  Default_Ceiling when it has no explicit Priority/Interrupt_Priority
   --  aspect or when Qualified_Name matches no protected object known to
   --  Self (e.g. one Libadalang could not statically resolve a call to).

private

   use type Munin.Tasks.Task_Unit;
   use type Munin.Protected_Objects.Protected_Object;

   package Task_Unit_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Munin.Tasks.Task_Unit);

   package Protected_Object_Maps is new
     Ada.Containers.Ordered_Maps
       (Key_Type     => VSS.Strings.Virtual_String,
        Element_Type => Munin.Protected_Objects.Protected_Object,
        "<"          => VSS.Strings."<");
   --  Keyed by qualified name, rather than a plain Vector: lets Priority
   --  look a single object up in O(log n) instead of scanning every
   --  object known to Self. Ordered (not hashed) so Protected_Objects
   --  (rebuilt by iterating the map) stays deterministic -- alphabetical
   --  by qualified name.

   type Context is tagged limited record
      Loaded_Project        : VSS.Strings.Virtual_String :=
        VSS.Strings.Empty_Virtual_String;
      Project_Tree          : GPR2.Project.Tree.Object;
      Analysis_Context      : Libadalang.Analysis.Analysis_Context;
      Sources               : VSS.String_Vectors.Virtual_String_Vector;
      Task_Items            : Task_Unit_Vectors.Vector;
      Protected_Items       : Protected_Object_Maps.Map;
      Entry_Calls           : Munin.Entry_Calls.Entry_Call_Register;
      Protected_Operations  : Munin.Protected_Operations.Registry;
      Call_Graph            :
        Munin.Call_Graph_Providers.Call_Graph_Provider_Access;
      Call_Graph_Error      : VSS.Strings.Virtual_String :=
        VSS.Strings.Empty_Virtual_String;
      Default_Ceiling       : Munin.Priorities.Priority_Value := 0;
      Default_Task_Priority : Munin.Priorities.Priority_Value := 0;
   end record;

   function Call_Graph
     (Self : Context)
      return Munin.Call_Graph_Providers.Call_Graph_Provider_Access
   is (Self.Call_Graph);

   function Call_Graph_Error (Self : Context) return VSS.Strings.Virtual_String
   is (Self.Call_Graph_Error);

   function Default_Ceiling
     (Self : Context) return Munin.Priorities.Priority_Value
   is (Self.Default_Ceiling);

   function Default_Task_Priority
     (Self : Context) return Munin.Priorities.Priority_Value
   is (Self.Default_Task_Priority);

end Munin.Contexts;
