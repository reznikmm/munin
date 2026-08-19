--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Test module for the callgraph_dynamic testcase crate: a single main
--  exercising an indirect call through an access-to-procedure value.

with Trendy_Test;

package Test_Call_Graph_Dynamic is

   procedure Test_Call_Graph_Dynamic_Build
     (Op : in out Trendy_Test.Operation'Class);

end Test_Call_Graph_Dynamic;
