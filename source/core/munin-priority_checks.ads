--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Checks the Ada RM D.3 priority-ceiling-locking protocol against a call
--  graph exposed through Munin.Call_Graph_Providers: for every task,
--  tracks the active priority it runs at (raised to a protected object's
--  ceiling on entry, per D.3(6)) as it walks the object's operations, and
--  reports every protected operation reachable at a priority higher than
--  its object's ceiling -- exactly the condition that raises Program_Error
--  at run time.

with Ada.Containers.Vectors;

with VSS.Strings;

with Munin.Call_Graph_Providers;
with Munin.Contexts;
with Munin.Priorities;

package Munin.Priority_Checks is

   use type Munin.Call_Graph_Providers.Call_Graph_Node;

   package Node_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Munin.Call_Graph_Providers.Call_Graph_Node);

   type Violation is record
      Object_Name : VSS.Strings.Virtual_String;
      --  Qualified name of the protected object whose ceiling is violated.

      Ceiling     : Munin.Priorities.Priority_Value;
      --  The object's ceiling (explicit, or the runtime's default).

      Reached_At  : Munin.Priorities.Priority_Value;
      --  The highest active priority found to reach the violating call --
      --  always > Ceiling.

      Path        : Node_Vectors.Vector;
      --  An example call chain realizing Reached_At: Path (Path.First_Index)
      --  is a task root (an element of some Call_Graph_Provider's Tasks),
      --  Path (Path.Last_Index) is the violating protected-operation node
      --  (Is_Protected_Operation is True for it).
   end record;

   package Violation_Vectors is new
     Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Violation);

   subtype Violation_List is Violation_Vectors.Vector;

   function Check
     (Context  : Munin.Contexts.Context;
      Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class)
      return Violation_List;
   --  Every priority-ceiling-locking violation reachable from Provider's
   --  Tasks, one per violating call site (regardless of how many distinct
   --  call paths reach it), each carrying the worst-case active priority
   --  and one example path that reaches it. Empty when no violation is
   --  reachable.

end Munin.Priority_Checks;
