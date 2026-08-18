--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Test module for the callgraph testcase crate.
--  Builds the callgraph crate as setup, then exercises
--  Munin.Call_Graph_Providers.CI against its generated `.ci` files.

with Trendy_Test;

package Test_Call_Graph_CI is

   procedure Test_Call_Graph_CI_Build
     (Op : in out Trendy_Test.Operation'Class);

end Test_Call_Graph_CI;
