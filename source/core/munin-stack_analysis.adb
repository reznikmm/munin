--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.Call_Graph_Providers.Containers;

package body Munin.Stack_Analysis is

   function "+" (Left, Right : Stack_Usage) return Stack_Usage
   is (Natural'Max (Left.Stack_Used, Right.Stack_Used),
       Left.Indirect_Calls + Right.Indirect_Calls,
       Left.Dynamic_Objects + Right.Dynamic_Objects,
       Boolean'Max (Left.Cycle, Right.Cycle));
   --  Combine two alternative callees: the deepest stack, the sum of the
   --  counts.

   Unknown_Cycle : constant Stack_Usage :=
     (Stack_Used      => 0,
      Indirect_Calls  => 0,
      Dynamic_Objects => 0,
      Cycle           => True);
   --  Nothing but the Cycle flag: a node still being resolved, or one the
   --  provider knows nothing about.

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Self     : in out Analysis;
      Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class)
   is
      pragma Unreferenced (Provider);
   begin
      Self.Memo.Clear;
   end Initialize;

   -----------
   -- Usage --
   -----------

   function Usage
     (Self     : in out Analysis;
      Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class;
      Root     : Munin.Call_Graph_Providers.Call_Graph_Node) return Stack_Usage
   is
      In_Progress : Munin.Call_Graph_Providers.Containers.Node_Sets.Set;
      --  Nodes on the call chain being resolved, to detect a call cycle.

      function Resolve
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node) return Stack_Usage;

      function Resolve
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node) return Stack_Usage
      is
         Result : Stack_Usage;
      begin
         if In_Progress.Contains (Node) then
            --  Recursed back into a node still being resolved: a call
            --  cycle. Its own stack contribution isn't known yet (that's
            --  what this very call chain is computing), so contribute
            --  nothing but flag Cycle.
            return Unknown_Cycle;

         elsif Self.Memo.Contains (Node) then
            return Self.Memo (Node);

         elsif Provider.Is_Indirect_Call (Node) then
            --  A call through a pointer with no known target contributes
            --  nothing: Indirect_Calls is deliberately left 0 and Cycle
            --  unset, exactly what the provider-based Resolve did in
            --  practice (an empty "no override" target was treated as
            --  "known never to execute").
            Result :=
              (Stack_Used      => 0,
               Indirect_Calls  => 0,
               Dynamic_Objects => 0,
               Cycle           => False);

         elsif not Provider.Is_Known (Node) then
            Result := Unknown_Cycle;

         else
            In_Progress.Insert (Node);

            Result :=
              (Stack_Used      => 0,
               Indirect_Calls  => 0,
               Dynamic_Objects => Provider.Dynamic_Objects (Node),
               Cycle           => False);

            for Callee of Provider.Callees (Node) loop
               Result := @ + Resolve (Callee);
            end loop;

            Result.Stack_Used := @ + Provider.Own_Stack (Node);
            In_Progress.Delete (Node);
         end if;

         Self.Memo.Insert (Node, Result);

         return Result;
      end Resolve;

   begin
      return Resolve (Root);
   end Usage;

end Munin.Stack_Analysis;
