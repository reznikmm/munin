--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with GPR2.Options;
with GPR2.Project.Tree;
with Munin.Call_Graph_Providers;
with Munin.Call_Graph_Providers.CI;
with Munin.Call_Graph_Providers.CI_Databases;
with Test_Build_Support;
with Test_Call_Graph_Support;
with Trendy_Test.Assertions;
with VSS.Strings;
with VSS.Strings.Conversions;

package body Test_Call_Graph_Cycle is

   procedure Test_Call_Graph_Cycle_Build
     (Op : in out Trendy_Test.Operation'Class)
   is
      Crate_Dir : constant String :=
        Test_Build_Support.Testsuite_Root & "/test_cases/callgraph_cycle";

      Success : Boolean;
   begin
      Op.Register (Parallelize => False);

      Test_Build_Support.Build_Crate
        (Op, Crate_Dir, "test_call_graph_cycle_build.log", Success);

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
         begin
            --  Forward/reverse edges agree on the mutual-recursion cycle.
            Op.Assert
              (Test_Call_Graph_Support.Has_Callee
                 (Provider, Proc_A, "_ada_proc_b"));
            Op.Assert
              (Test_Call_Graph_Support.Has_Callee
                 (Provider, Proc_B, "_ada_proc_a"));
            Op.Assert
              (Test_Call_Graph_Support.Has_Caller
                 (Provider, Proc_A, "_ada_proc_b"));

            Op.Assert
              (VSS.Strings.Conversions.To_UTF_8_String
                 (Provider.Qualified_Name (Proc_A))
               = "Proc_A");
            Op.Assert (Provider.Position (Proc_A).Is_Set);

            --  Resolve (dormant future-feature machinery) must terminate
            --  on the Proc_A/Proc_B cycle and flag it as such.
            declare
               Usage : constant
                 Munin.Call_Graph_Providers.CI_Databases.Resolve_Result :=
                   Provider.Resolve (Proc_A);
            begin
               Op.Assert (Usage.Cycle);
               Op.Assert (Usage.Stack_Used > 0);
            end;
         end;
      end;
   end Test_Call_Graph_Cycle_Build;

end Test_Call_Graph_Cycle;
