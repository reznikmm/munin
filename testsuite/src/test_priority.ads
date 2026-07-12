--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

--  Test module for the priority testcase crate.
--  Builds the priority crate as setup, then asserts on Munin analysis results
--  (assertions stubbed until Munin core API is implemented).

with Trendy_Test;

package Test_Priority is

   procedure Test_Priority_Build
     (Op : in out Trendy_Test.Operation'Class);

end Test_Priority;
