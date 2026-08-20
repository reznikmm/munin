--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Test module: exercises Munin.Call_Graph_Cycles.Cycles directly against
--  the callgraph_cycle testcase crate's mutual recursion (Proc_A/Proc_B)
--  and direct self-recursion (Proc_C).

with Trendy_Test;

package Test_Call_Graph_Cycles_Scc is

   procedure Test_Call_Graph_Cycles_Scc_Build
     (Op : in out Trendy_Test.Operation'Class);

end Test_Call_Graph_Cycles_Scc;
