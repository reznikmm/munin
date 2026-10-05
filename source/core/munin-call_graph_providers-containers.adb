--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Munin.Call_Graph_Providers.Containers is

   function Path_To
     (Predecessors : Node_Node_Maps.Map; Node : Call_Graph_Node)
      return Node_Path
   is
      Reversed : Node_Vectors.Vector;
      Current  : Call_Graph_Node := Node;
   begin
      loop
         Reversed.Append (Current);

         exit when not Predecessors.Contains (Current);

         Current := Predecessors (Current);
      end loop;

      return Result : Node_Path do
         for Index in reverse Reversed.First_Index .. Reversed.Last_Index loop
            Result.Append (Reversed (Index));
         end loop;
      end return;
   end Path_To;

end Munin.Call_Graph_Providers.Containers;
