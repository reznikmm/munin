--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Vectors;
with VSS.Strings.Conversions;

package body Test_Call_Graph_Support is

   use type Munin.Call_Graph_Providers.Call_Graph_Node;

   package Node_Vectors is new Ada.Containers.Vectors
     (Positive, Munin.Call_Graph_Providers.Call_Graph_Node);

   -------------
   -- Node_Of --
   -------------

   function Node_Of
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class;
      Symbol   : String)
      return Munin.Call_Graph_Providers.Call_Graph_Node
   is
      Visited : Node_Vectors.Vector;
      Queue   : Node_Vectors.Vector;

      function Is_Visited
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node) return Boolean
      is
      begin
         for Item of Visited loop
            if Item = Node then
               return True;
            end if;
         end loop;

         return False;
      end Is_Visited;

   begin
      for Node of Provider.Tasks loop
         Queue.Append (Node);
      end loop;

      while not Queue.Is_Empty loop
         declare
            Node : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
              Queue.Last_Element;
         begin
            Queue.Delete_Last;

            if not Is_Visited (Node) then
               Visited.Append (Node);

               if VSS.Strings.Conversions.To_UTF_8_String
                    (Provider.Image (Node))
                 = Symbol
               then
                  return Node;
               end if;

               for Callee of Provider.Callees (Node) loop
                  Queue.Append (Callee);
               end loop;
            end if;
         end;
      end loop;

      raise Constraint_Error with "No such node: " & Symbol;
   end Node_Of;

   -----------------
   -- Has_Callee --
   -----------------

   function Has_Callee
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class;
      Node     : Munin.Call_Graph_Providers.Call_Graph_Node;
      Symbol   : String)
      return Boolean
   is
   begin
      for Callee of Provider.Callees (Node) loop
         if VSS.Strings.Conversions.To_UTF_8_String (Provider.Image (Callee))
           = Symbol
         then
            return True;
         end if;
      end loop;

      return False;
   end Has_Callee;

   -----------------
   -- Has_Caller --
   -----------------

   function Has_Caller
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class;
      Node     : Munin.Call_Graph_Providers.Call_Graph_Node;
      Symbol   : String)
      return Boolean
   is
   begin
      for Caller of Provider.Callers (Node) loop
         if VSS.Strings.Conversions.To_UTF_8_String (Provider.Image (Caller))
           = Symbol
         then
            return True;
         end if;
      end loop;

      return False;
   end Has_Caller;

end Test_Call_Graph_Support;
