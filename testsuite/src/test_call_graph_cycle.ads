--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Test module for the callgraph_cycle testcase crate: a single main
--  exercising mutual recursion between Proc_A and Proc_B.

with Trendy_Test;

package Test_Call_Graph_Cycle is

   procedure Test_Call_Graph_Cycle_Build
     (Op : in out Trendy_Test.Operation'Class);

end Test_Call_Graph_Cycle;
