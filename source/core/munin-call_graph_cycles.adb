--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Hashed_Maps;

package body Munin.Call_Graph_Cycles is

   use type Ada.Containers.Count_Type;

   type Node_Info is record
      Index    : Positive;
      --  Tarjan discovery index: the order Node was first visited in.
      Low_Link : Positive;
      --  The lowest discovery index reachable from Node via Callees,
      --  including through nodes still on Stack.
      On_Stack : Boolean;
   end record;

   package Node_Info_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Munin.Call_Graph_Providers.Call_Graph_Node,
        Element_Type    => Node_Info,
        Hash            => Munin.Call_Graph_Providers.Hash,
        Equivalent_Keys => Munin.Call_Graph_Providers."=");

   function Cycles
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class)
      return Cycle_Groups
   is
      Infos      : Node_Info_Maps.Map;
      Next_Index : Positive := 1;
      Stack      : Node_Vectors.Vector;
      Result     : Cycle_Groups;

      function Has_Self_Loop
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node) return Boolean;
      --  True when Node appears among its own Callees.

      procedure Strong_Connect
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node);
      --  Tarjan's algorithm, run once per not-yet-visited node reachable
      --  from a root in Provider.Tasks.

      function Has_Self_Loop
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node) return Boolean is
      begin
         for Callee of Provider.Callees (Node) loop
            if Callee = Node then
               return True;
            end if;
         end loop;

         return False;
      end Has_Self_Loop;

      procedure Strong_Connect
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      is
         Self_Index : constant Positive := Next_Index;
      begin
         Next_Index := Next_Index + 1;
         Infos.Insert
           (Node,
            (Index => Self_Index, Low_Link => Self_Index, On_Stack => True));
         Stack.Append (Node);

         for Callee of Provider.Callees (Node) loop
            if not Infos.Contains (Callee) then
               Strong_Connect (Callee);
               Infos (Node).Low_Link :=
                 Positive'Min (Infos (Node).Low_Link, Infos (Callee).Low_Link);

            elsif Infos (Callee).On_Stack then
               Infos (Node).Low_Link :=
                 Positive'Min (Infos (Node).Low_Link, Infos (Callee).Index);
            end if;
         end loop;

         if Infos (Node).Low_Link = Infos (Node).Index then
            declare
               Group : Cycle_Group;
            begin
               loop
                  declare
                     Member :
                       constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                         Stack.Last_Element;
                  begin
                     Stack.Delete_Last;
                     Infos (Member).On_Stack := False;
                     Group.Append (Member);

                     exit when Member = Node;
                  end;
               end loop;

               if Group.Length > 1 or else Has_Self_Loop (Node) then
                  Result.Append (Group);
               end if;
            end;
         end if;
      end Strong_Connect;

   begin
      for Root of Provider.Tasks loop
         if not Infos.Contains (Root) then
            Strong_Connect (Root);
         end if;
      end loop;

      return Result;
   end Cycles;

end Munin.Call_Graph_Cycles;
