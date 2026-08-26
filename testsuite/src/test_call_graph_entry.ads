--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Test module for the callgraph_entry testcase crate: a task calling a
--  protected object's entry and procedure directly. Exercises Munin's
--  entry-call resolution against the Call_Graph_Providers API only --
--  no priority-ceiling checking yet (that's a separate, later feature).

with Trendy_Test;

package Test_Call_Graph_Entry is

   procedure Test_Call_Graph_Entry_Build
     (Op : in out Trendy_Test.Operation'Class);

end Test_Call_Graph_Entry;
