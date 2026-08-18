--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;

package Munin.Call_Graph_Providers is
   pragma Preelaborate;

   type Call_Graph_Provider is interface;

   type Call_Graph_Provider_Access is access all Call_Graph_Provider'Class
   with Storage_Size => 0;

   type Call_Graph_Node is private;

   type Call_Graph_Node_Array is array (Positive range <>) of Call_Graph_Node;

   type Optional_Position (Is_Set : Boolean := False) is record
      case Is_Set is
         when False =>
            null;

         when True =>
            File   : VSS.Strings.Virtual_String;
            Line   : Positive;
            Column : Positive;
      end case;
   end record;

   function Callees
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return Call_Graph_Node_Array
   is abstract;
   --  Nodes directly called from Node.

   function Callers
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return Call_Graph_Node_Array
   is abstract;
   --  Nodes that directly call Node.

   function Qualified_Name
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is abstract;
   --  Best-effort dotted Ada name for Node, or an empty string when Self
   --  cannot recover one (for example a compiler-generated node with no
   --  Ada-level identity, or a backend that only records Node's
   --  undecorated simple name).

   function Position
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return Optional_Position
   is abstract;
   --  Node's declaration position, or a position with Has_Value => False
   --  when Self has no Ada source position for Node.

   function Tasks (Self : Call_Graph_Provider) return Call_Graph_Node_Array
   is abstract;
   --  Nodes for the task and main subprogram bodies known to Self, to use
   --  as roots when walking the call tree.

   function Image
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is abstract;
   --  Node's linker symbol or otherwise mangled unique name, as known to
   --  Self; unlike Qualified_Name, always defined for every Node.

private

   type Call_Graph_Node is new Integer;

end Munin.Call_Graph_Providers;
