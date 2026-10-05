--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Hashed_Maps;

with Munin.Call_Graph_Providers;

package Munin.Stack_Analysis is

   type Stack_Usage is record
      Stack_Used      : Natural := 0;
      Indirect_Calls  : Natural := 0;
      Dynamic_Objects : Natural := 0;
      Cycle           : Boolean := False;
   end record;
   --  Stack_Used is Node's own static stack plus the maximum over all of
   --  its (recursively resolved) callees; Indirect_Calls/Dynamic_Objects
   --  count, respectively, calls through a pointer and heap/secondary
   --  stack allocations reachable from Node -- neither contributes to
   --  Stack_Used, so a nonzero count means the true worst case may be
   --  higher than reported. Cycle is set when Node's call graph is (or
   --  reaches) a recursive cycle, or reaches a node the provider knows
   --  nothing about, in which case Stack_Used is a lower bound, not the
   --  true worst case.

   type Analysis is tagged private;
   --  Holds the memoized results for one provider.

   procedure Initialize
     (Self     : in out Analysis;
      Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class);
   --  Discard any memoized results; Provider is the one Usage must be
   --  called with from now on.

   function Usage
     (Self     : in out Analysis;
      Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class;
      Root     : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Stack_Usage;
   --  Worst-case stack usage rooted at Root; see Stack_Usage.

private

   package Usage_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Munin.Call_Graph_Providers.Call_Graph_Node,
        Element_Type    => Stack_Usage,
        Hash            => Munin.Call_Graph_Providers.Hash,
        Equivalent_Keys => Munin.Call_Graph_Providers."=");

   type Analysis is tagged record
      Memo : Usage_Maps.Map;
      --  Result for every node already fully resolved.
   end record;

end Munin.Stack_Analysis;
