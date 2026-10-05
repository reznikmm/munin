--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Containers of Call_Graph_Node shared by every analysis package, so
--  that paths, node sets and predecessor maps are the same types
--  everywhere.

with Ada.Containers.Hashed_Maps;
with Ada.Containers.Hashed_Sets;
with Ada.Containers.Vectors;

package Munin.Call_Graph_Providers.Containers is
   pragma Preelaborate;

   package Node_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Call_Graph_Node);

   subtype Node_Path is Node_Vectors.Vector;
   --  A call chain, first element is the caller-most node.

   package Node_Sets is new
     Ada.Containers.Hashed_Sets
       (Element_Type        => Call_Graph_Node,
        Hash                => Hash,
        Equivalent_Elements => "=");

   package Node_Node_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Call_Graph_Node,
        Element_Type    => Call_Graph_Node,
        Hash            => Hash,
        Equivalent_Keys => "=");
   --  Typically a predecessor map for path reconstruction.

   function Path_To
     (Predecessors : Node_Node_Maps.Map; Node : Call_Graph_Node)
      return Node_Path;
   --  Follow Predecessors back from Node and return the chain in call
   --  order (root first, Node last).

end Munin.Call_Graph_Providers.Containers;
