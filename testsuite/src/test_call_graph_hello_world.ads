--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Test module for the callgraph_hello_world testcase crate: a single
--  main with no callees of its own.

with Trendy_Test;

package Test_Call_Graph_Hello_World is

   procedure Test_Call_Graph_Hello_World_Build
     (Op : in out Trendy_Test.Operation'Class);

end Test_Call_Graph_Hello_World;
