--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

--  Dummy test case for Munin core API (Iteration 1 smoke test)

with Trendy_Test;

package Test_Dummy is

   procedure Test_Basic_Arithmetic
     (Op : in out Trendy_Test.Operation'Class);

   procedure Test_Comparison_Operations
     (Op : in out Trendy_Test.Operation'Class);

end Test_Dummy;
