--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Detects groups of mutually-recursive subprograms in a call graph
--  exposed through Munin.Call_Graph_Providers, using Tarjan's strongly
--  connected components algorithm run purely against the abstract
--  Call_Graph_Provider interface (Callees, Tasks); provider-agnostic, so
--  it works unchanged for any current or future Call_Graph_Provider
--  implementation.

with Ada.Containers.Vectors;

with Munin.Call_Graph_Providers;

package Munin.Call_Graph_Cycles is
   pragma Preelaborate;

   use type Munin.Call_Graph_Providers.Call_Graph_Node;

   package Node_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Munin.Call_Graph_Providers.Call_Graph_Node);

   subtype Cycle_Group is Node_Vectors.Vector;
   --  The subprograms making up one mutually-recursive cycle: either a
   --  strongly connected component of two or more distinct nodes, or a
   --  single node that directly calls itself. Members are in Tarjan's
   --  pop order, not call order.

   use type Node_Vectors.Vector;

   package Cycle_Group_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Cycle_Group);

   subtype Cycle_Groups is Cycle_Group_Vectors.Vector;

   function Cycles
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class)
      return Cycle_Groups;
   --  Every group of mutually-recursive subprograms reachable from
   --  Provider.Tasks: each strongly connected component of Provider's
   --  call graph with more than one node, plus every single node with a
   --  direct self-loop. A node not reachable from any of Provider.Tasks
   --  is never visited, so a cycle entirely among such nodes (e.g. dead
   --  code) is not reported -- consistent with Munin.CLI.Main's call-tree
   --  printing, which is rooted the same way. Uses Tarjan's algorithm (a
   --  single pass over Callees; no separate reverse-graph pass, unlike
   --  Kosaraju's). Empty when Provider's call graph, restricted to what's
   --  reachable from Provider.Tasks, is acyclic.

end Munin.Call_Graph_Cycles;
