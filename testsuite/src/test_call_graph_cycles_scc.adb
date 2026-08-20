--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers;
with GPR2.Options;
with GPR2.Project.Tree;
with Munin.Call_Graph_Cycles;
with Munin.Call_Graph_Providers;
with Munin.Call_Graph_Providers.CI;
with Test_Build_Support;
with Test_Call_Graph_Support;
with Trendy_Test.Assertions;
with VSS.Strings;
with VSS.Strings.Conversions;

package body Test_Call_Graph_Cycles_Scc is

   use type Ada.Containers.Count_Type;

   procedure Test_Call_Graph_Cycles_Scc_Build
     (Op : in out Trendy_Test.Operation'Class)
   is
      Crate_Dir : constant String :=
        Test_Build_Support.Testsuite_Root & "/test_cases/callgraph_cycle";

      Success : Boolean;
   begin
      Op.Register (Parallelize => False);

      Test_Build_Support.Build_Crate
        (Op, Crate_Dir, "test_call_graph_cycles_scc_build.log", Success);

      if not Success then
         return;
      end if;

      declare
         Tree     : GPR2.Project.Tree.Object;
         Options  : GPR2.Options.Object := GPR2.Options.Empty_Options;
         Provider : aliased Munin.Call_Graph_Providers.CI.CI_Provider;
         Error    : VSS.Strings.Virtual_String;
      begin
         GPR2.Options.Add_Switch
           (Options,
            Switch => GPR2.Options.P,
            Param  => Crate_Dir & "/callgraph_cycle.gpr");

         if not Tree.Load
                  (Options              => Options,
                   With_Runtime         => True,
                   Artifacts_Info_Level => GPR2.Sources_Units,
                   Check_Drivers        => False)
         then
            Trendy_Test.Assertions.Fail
              (Op, "Failed to load callgraph_cycle.gpr");
            return;
         end if;

         Munin.Call_Graph_Providers.CI.Initialize (Provider, Tree, Error);

         if not Error.Is_Empty then
            Trendy_Test.Assertions.Fail
              (Op,
               "Initialize failed: "
               & VSS.Strings.Conversions.To_UTF_8_String (Error));
            return;
         end if;

         declare
            Proc_A : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
              Test_Call_Graph_Support.Node_Of (Provider, "_ada_proc_a");
            Proc_B : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
              Test_Call_Graph_Support.Node_Of (Provider, "_ada_proc_b");
            Proc_C : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
              Test_Call_Graph_Support.Node_Of (Provider, "_ada_proc_c");

            Groups : constant Munin.Call_Graph_Cycles.Cycle_Groups :=
              Munin.Call_Graph_Cycles.Cycles (Provider);

            Mutual_Recursion_Found : Boolean := False;
            Self_Loop_Found        : Boolean := False;
         begin
            for Group of Groups loop
               if Group.Contains (Proc_A) and then Group.Contains (Proc_B)
               then
                  Op.Assert (Group.Length = 2);
                  Mutual_Recursion_Found := True;
               end if;

               if Group.Contains (Proc_C) then
                  Op.Assert (Group.Length = 1);
                  Self_Loop_Found := True;
               end if;
            end loop;

            Op.Assert (Mutual_Recursion_Found);
            Op.Assert (Self_Loop_Found);
         end;
      end;
   end Test_Call_Graph_Cycles_Scc_Build;

end Test_Call_Graph_Cycles_Scc;
