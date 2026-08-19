--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Lookup helpers shared by the callgraph_* scenario tests, built on top
--  of Munin.Call_Graph_Providers's Node/Image-based interface.

with Munin.Call_Graph_Providers;

package Test_Call_Graph_Support is

   function Node_Of
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class;
      Symbol   : String)
      return Munin.Call_Graph_Providers.Call_Graph_Node;
   --  The node reachable from Provider.Tasks (the environment task and
   --  any task bodies) by following Callees whose Image is Symbol;
   --  raises Constraint_Error if there's none.

   function Has_Callee
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class;
      Node     : Munin.Call_Graph_Providers.Call_Graph_Node;
      Symbol   : String)
      return Boolean;
   --  True when one of Node's direct callees (per Provider) has Image
   --  Symbol.

   function Has_Caller
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class;
      Node     : Munin.Call_Graph_Providers.Call_Graph_Node;
      Symbol   : String)
      return Boolean;
   --  True when one of Node's direct callers (per Provider) has Image
   --  Symbol.

end Test_Call_Graph_Support;
