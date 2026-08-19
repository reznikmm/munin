--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with GPR2.Options;
with GPR2.Project.Tree;
with Munin.Call_Graph_Providers;
with Munin.Call_Graph_Providers.CI;
with Test_Build_Support;
with Test_Call_Graph_Support;
with Trendy_Test.Assertions;
with VSS.Strings;
with VSS.Strings.Conversions;

package body Test_Call_Graph_Dynamic is

   procedure Test_Call_Graph_Dynamic_Build
     (Op : in out Trendy_Test.Operation'Class)
   is
      Crate_Dir : constant String :=
        Test_Build_Support.Testsuite_Root & "/test_cases/callgraph_dynamic";

      Success : Boolean;
   begin
      Op.Register (Parallelize => False);

      Test_Build_Support.Build_Crate
        (Op, Crate_Dir, "test_call_graph_dynamic_build.log", Success);

      if not Success then
         return;
      end if;

      --  Testing: load the project, initialize the CI-backed call graph
      --  provider, and query it.
      declare
         Tree     : GPR2.Project.Tree.Object;
         Options  : GPR2.Options.Object := GPR2.Options.Empty_Options;
         Provider : aliased Munin.Call_Graph_Providers.CI.CI_Provider;
         Error    : VSS.Strings.Virtual_String;
      begin
         GPR2.Options.Add_Switch
           (Options,
            Switch => GPR2.Options.P,
            Param  => Crate_Dir & "/callgraph_dynamic.gpr");

         if not Tree.Load
                  (Options              => Options,
                   With_Runtime         => True,
                   Artifacts_Info_Level => GPR2.Sources_Units,
                   Check_Drivers        => False)
         then
            Trendy_Test.Assertions.Fail
              (Op, "Failed to load callgraph_dynamic.gpr");
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
            Convert_Node : constant
              Munin.Call_Graph_Providers.Call_Graph_Node :=
                Test_Call_Graph_Support.Node_Of (Provider, "_ada_convert");
         begin
            --  The indirect call through Nil'Access shows up as the
            --  `__indirect_call` placeholder among Convert's callees.
            Op.Assert
              (Test_Call_Graph_Support.Has_Callee
                 (Provider, Convert_Node, "__indirect_call"));
         end;
      end;
   end Test_Call_Graph_Dynamic_Build;

end Test_Call_Graph_Dynamic;
