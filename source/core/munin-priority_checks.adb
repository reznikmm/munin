--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Hashed_Maps;

package body Munin.Priority_Checks is

   package Priority_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Munin.Call_Graph_Providers.Call_Graph_Node,
        Element_Type    => Munin.Priorities.Priority_Value,
        Hash            => Munin.Call_Graph_Providers.Hash,
        Equivalent_Keys => Munin.Call_Graph_Providers."=");
   --  Best (Node): the highest active priority known to reach Node -- the
   --  priority the task calling into Node holds just before the call, i.e.
   --  before any ceiling raise Node itself might cause. Monotonically
   --  non-decreasing as the fixpoint below runs, and bounded by the
   --  runtime's priority range, so the algorithm always terminates.

   package Predecessor_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Munin.Call_Graph_Providers.Call_Graph_Node,
        Element_Type    => Munin.Call_Graph_Providers.Call_Graph_Node,
        Hash            => Munin.Call_Graph_Providers.Hash,
        Equivalent_Keys => Munin.Call_Graph_Providers."=");
   --  Predecessor (Node): the node Best (Node)'s current value was last
   --  propagated from. Absent for a task root. Used only to reconstruct
   --  one example call chain per reported violation.

   function Check
     (Context  : Munin.Contexts.Context;
      Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class)
      return Violation_List
   is
      Best        : Priority_Maps.Map;
      Predecessor : Predecessor_Maps.Map;
      Worklist    : Node_Vectors.Vector;

      function Path_To
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node)
         return Node_Vectors.Vector;
      --  Node and its chain of Predecessor links, back to (and including)
      --  the task root it was ultimately reached from, in call order.

      function Path_To
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node)
         return Node_Vectors.Vector
      is
         Reversed : Node_Vectors.Vector;
         Current  : Munin.Call_Graph_Providers.Call_Graph_Node := Node;
      begin
         loop
            Reversed.Append (Current);

            exit when not Predecessor.Contains (Current);

            Current := Predecessor (Current);
         end loop;

         return Result : Node_Vectors.Vector do
            for Index in reverse Reversed.First_Index .. Reversed.Last_Index
            loop
               Result.Append (Reversed (Index));
            end loop;
         end return;
      end Path_To;

      procedure Seed_Root
        (Root    : Munin.Call_Graph_Providers.Call_Graph_Node;
         Initial : Munin.Priorities.Priority_Value);
      --  Best.Include (Root, Initial) and Worklist.Append (Root), unless
      --  Root is already known at an active priority >= Initial.

      procedure Seed_Root
        (Root    : Munin.Call_Graph_Providers.Call_Graph_Node;
         Initial : Munin.Priorities.Priority_Value) is
      begin
         if not Best.Contains (Root) or else Initial > Best (Root) then
            Best.Include (Root, Initial);
            Worklist.Append (Root);
         end if;
      end Seed_Root;

   begin
      for Root of Provider.Tasks loop
         Seed_Root (Root, Context.Task_Priority (Provider.Position (Root)));
      end loop;

      for Root of Provider.Interrupt_Handlers loop
         Seed_Root
           (Root,
            Context.Interrupt_Handler_Priority (Provider.Position (Root)));
      end loop;

      while not Worklist.Is_Empty loop
         declare
            Node       : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
              Worklist.Last_Element;
            Active     : constant Munin.Priorities.Priority_Value :=
              Best (Node);
            Propagated : Munin.Priorities.Priority_Value := Active;
         begin
            Worklist.Delete_Last;

            if Provider.Is_Protected_Operation (Node) then
               Propagated :=
                 Munin.Priorities.Priority_Value'Max
                   (Active,
                    Context.Protected_Object_Ceiling
                      (Provider.Protected_Object_Name (Node)));
            end if;

            for Callee of Provider.Callees (Node) loop
               if not Best.Contains (Callee) or else Propagated > Best (Callee)
               then
                  Best.Include (Callee, Propagated);
                  Predecessor.Include (Callee, Node);
                  Worklist.Append (Callee);
               end if;
            end loop;
         end;
      end loop;

      return Result : Violation_List do
         for Cursor in Best.Iterate loop
            declare
               Node : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                 Priority_Maps.Key (Cursor);
            begin
               if Provider.Is_Protected_Operation (Node) then
                  declare
                     Object_Name : constant VSS.Strings.Virtual_String :=
                       Provider.Protected_Object_Name (Node);
                     Ceiling     : constant Munin.Priorities.Priority_Value :=
                       Context.Protected_Object_Ceiling (Object_Name);
                     Reached_At  : constant Munin.Priorities.Priority_Value :=
                       Priority_Maps.Element (Cursor);
                  begin
                     if Reached_At > Ceiling then
                        Result.Append
                          (Violation'
                             (Object_Name => Object_Name,
                              Ceiling     => Ceiling,
                              Reached_At  => Reached_At,
                              Path        => Path_To (Node)));
                     end if;
                  end;
               end if;
            end;
         end loop;
      end return;
   end Check;

end Munin.Priority_Checks;
