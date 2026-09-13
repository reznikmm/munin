--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Hashed_Maps;
with Ada.Containers.Hashed_Sets;

package body Munin.Lock_Checks is

   use type VSS.Strings.Virtual_String;

   package Node_Sets is new
     Ada.Containers.Hashed_Sets
       (Element_Type        => Munin.Call_Graph_Providers.Call_Graph_Node,
        Hash                => Munin.Call_Graph_Providers.Hash,
        Equivalent_Elements => Munin.Call_Graph_Providers."=");

   package Position_Sets is new
     Ada.Containers.Hashed_Sets
       (Element_Type        => Munin.Optional_Position,
        Hash                => Munin.Hash,
        Equivalent_Elements => Munin."=");

   package Object_Node_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => VSS.Strings.Virtual_String,
        Element_Type    => Node_Vectors.Vector,
        Hash            => VSS.Strings.Hash,
        Equivalent_Keys => VSS.Strings."=",
        "="             => Node_Vectors."=");
   --  Every reachable protected-operation call site (Is_Protected_Operation
   --  node), grouped by the qualified name of the object it was resolved
   --  to attach to.

   package Taint_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Munin.Call_Graph_Providers.Call_Graph_Node,
        Element_Type    => Boolean,
        Hash            => Munin.Call_Graph_Providers.Hash,
        Equivalent_Keys => Munin.Call_Graph_Providers."=");
   --  Tainted (Node): False as long as every call reaching Node, since
   --  the object currently being checked was entered, stayed within that
   --  object's own operations (a direct call from one of its operations
   --  to another); True from the point some call left those operations
   --  onward. Monotonically non-decreasing as the fixpoint below runs
   --  (never reset from True back to False), so the algorithm always
   --  terminates.

   package Predecessor_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Munin.Call_Graph_Providers.Call_Graph_Node,
        Element_Type    => Munin.Call_Graph_Providers.Call_Graph_Node,
        Hash            => Munin.Call_Graph_Providers.Hash,
        Equivalent_Keys => Munin.Call_Graph_Providers."=");
   --  Predecessor (Node): the node Tainted (Node)'s current value was
   --  last propagated from. Absent for a node seeded directly (the real
   --  body of one of the checked object's own operations). Used only to
   --  reconstruct one example call chain per reported violation.

   function Check
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class)
      return Violation_List
   is
      Object_Nodes : Object_Node_Maps.Map;
      --  Populated once, up front, by a plain reachability walk from
      --  Provider.Tasks (see the Collect block below).

      procedure Collect;
      --  Fill Object_Nodes with every protected-operation call site
      --  reachable from Provider.Tasks, keyed by the qualified name of
      --  the object it targets.

      procedure Collect is
         Visited  : Node_Sets.Set;
         Worklist : Node_Vectors.Vector;

         procedure Visit (Node : Munin.Call_Graph_Providers.Call_Graph_Node);

         procedure Visit (Node : Munin.Call_Graph_Providers.Call_Graph_Node) is
         begin
            if not Visited.Contains (Node) then
               Visited.Include (Node);
               Worklist.Append (Node);

               if Provider.Is_Protected_Operation (Node) then
                  declare
                     Name : constant VSS.Strings.Virtual_String :=
                       Provider.Protected_Object_Name (Node);
                  begin
                     if not Object_Nodes.Contains (Name) then
                        Object_Nodes.Insert (Name, Node_Vectors.Empty_Vector);
                     end if;

                     Object_Nodes (Name).Append (Node);
                  end;
               end if;
            end if;
         end Visit;
      begin
         for Root of Provider.Tasks loop
            Visit (Root);
         end loop;

         for Root of Provider.Interrupt_Handlers loop
            Visit (Root);
         end loop;

         while not Worklist.Is_Empty loop
            declare
               Node : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                 Worklist.Last_Element;
            begin
               Worklist.Delete_Last;

               for Callee of Provider.Callees (Node) loop
                  Visit (Callee);
               end loop;
            end;
         end loop;
      end Collect;

      function Check_Object
        (Name : VSS.Strings.Virtual_String; Nodes : Node_Vectors.Vector)
         return Violation_List;
      --  Every violating call site among Nodes (all of them resolved to
      --  the protected object Name).

      function Check_Object
        (Name : VSS.Strings.Virtual_String; Nodes : Node_Vectors.Vector)
         return Violation_List
      is
         Bodies : Node_Sets.Set;
         --  The real operation bodies Nodes' entries resolve to -- i.e.
         --  Name's own operations, as actually compiled.

         Body_Positions : Position_Sets.Set;
         --  Bodies' own declaration positions. GNAT compiles a protected
         --  procedure/function into two nodes sharing that one position:
         --  a locked, externally-callable wrapper, and the unprotected
         --  body it calls (see Node_By_Position's doc comment in
         --  Munin.Call_Graph_Providers.CI_Databases) -- only one of the
         --  two, whichever a specific call site's Base_Target happened
         --  to resolve to, ever lands in Bodies itself. Matching by
         --  position instead recognizes both halves of the pair as
         --  "Name's own operation", not just the one Bodies happens to
         --  name.

         Tainted     : Taint_Maps.Map;
         Predecessor : Predecessor_Maps.Map;
         Worklist    : Node_Vectors.Vector;

         function Path_To
           (Node : Munin.Call_Graph_Providers.Call_Graph_Node)
            return Node_Vectors.Vector;

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
      begin
         for Node of Nodes loop
            declare
               Callees :
                 constant Munin.Call_Graph_Providers.Call_Graph_Node_Array :=
                   Provider.Callees (Node);
            begin
               --  Is_Protected_Operation's contract guarantees exactly
               --  one real callee here -- the operation's compiled body.
               if Callees'Length = 1 then
                  Bodies.Include (Callees (Callees'First));
               end if;
            end;
         end loop;

         for Body_Node of Bodies loop
            declare
               Position : constant Munin.Optional_Position :=
                 Provider.Position (Body_Node);
            begin
               if Position.Is_Set then
                  Body_Positions.Include (Position);
               end if;
            end;
         end loop;

         for Body_Node of Bodies loop
            if not Tainted.Contains (Body_Node) then
               Tainted.Include (Body_Node, False);
               Worklist.Append (Body_Node);
            end if;
         end loop;

         while not Worklist.Is_Empty loop
            declare
               Node          :
                 constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                   Worklist.Last_Element;
               Active        : constant Boolean := Tainted (Node);
               Node_Position : constant Munin.Optional_Position :=
                 Provider.Position (Node);
               Is_Own_Body   : constant Boolean :=
                 Bodies.Contains (Node)
                 or else (Node_Position.Is_Set
                          and then Body_Positions.Contains (Node_Position));
               --  Node itself, or its P/N sibling (see Body_Positions).
            begin
               Worklist.Delete_Last;

               for Callee of Provider.Callees (Node) loop
                  declare
                     Callee_Position : constant Munin.Optional_Position :=
                       Provider.Position (Callee);
                     Same_Operation  : constant Boolean :=
                       Node_Position.Is_Set
                       and then Callee_Position.Is_Set
                       and then Node_Position = Callee_Position;
                     --  Callee is Node's own P/N sibling -- GNAT's
                     --  compiler-generated dispatch from the locked
                     --  wrapper to its unprotected body (or vice versa),
                     --  never a call written in the source -- rather
                     --  than a genuine call to leave Name's operations
                     --  through.
                     Propagated      : constant Boolean :=
                       Active
                       or else (Is_Own_Body
                                and then not Same_Operation
                                and then not (Provider.Is_Protected_Operation
                                                (Callee)
                                              and then Provider
                                                         .Protected_Object_Name
                                                            (Callee)
                                                       = Name));
                     --  Once tainted, stays tainted. Otherwise, only
                     --  Name's own operation body calling out to
                     --  something other than another operation of Name
                     --  itself -- an ordinary subprogram, or an
                     --  operation of some other protected object --
                     --  taints from here on; reaching Name again after
                     --  that is a re-entry, not an internal call.
                  begin
                     if not Tainted.Contains (Callee)
                       or else (Propagated and then not Tainted (Callee))
                     then
                        Tainted.Include (Callee, Propagated);
                        Predecessor.Include (Callee, Node);
                        Worklist.Append (Callee);
                     end if;
                  end;
               end loop;
            end;
         end loop;

         return Result : Violation_List do
            for Node of Nodes loop
               if Tainted.Contains (Node) and then Tainted (Node) then
                  Result.Append
                    (Violation'(Object_Name => Name, Path => Path_To (Node)));
               end if;
            end loop;
         end return;
      end Check_Object;

   begin
      Collect;

      return Result : Violation_List do
         for Cursor in Object_Nodes.Iterate loop
            Result.Append
              (Check_Object
                 (Object_Node_Maps.Key (Cursor),
                  Object_Node_Maps.Element (Cursor)));
         end loop;
      end return;
   end Check;

end Munin.Lock_Checks;
