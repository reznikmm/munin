--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

--  Test module for the lock_check testcase crate.
--  Builds the crate as setup, then asserts on Munin.Lock_Checks.Check
--  results against its deliberately mixed clean/re-entrant scenarios.

with Trendy_Test;

package Test_Lock_Checks is

   procedure Test_Lock_Checks_Build (Op : in out Trendy_Test.Operation'Class);

end Test_Lock_Checks;
