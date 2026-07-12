--  SPDX-FileCopyrightText: 2026 Munin Developer
--
--  SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception
--
--  Dummy test case for Munin core API (Iteration 1 smoke test)

package body Test_Dummy is

   procedure Test_Basic_Arithmetic
     (Op : in out Trendy_Test.Operation'Class)
   is
   begin
      Op.Register;
      Op.Assert (2 + 2 = 4);
      Op.Assert (10 - 3 = 7);
      Op.Assert (5 * 2 = 10);
   end Test_Basic_Arithmetic;

   procedure Test_Comparison_Operations
     (Op : in out Trendy_Test.Operation'Class)
   is
   begin
      Op.Register;
      Op.Assert (3 > 1);
      Op.Assert (5 <= 5);
      Op.Assert (2 < 3);
      Op.Assert (not (10 < 5));
   end Test_Comparison_Operations;

end Test_Dummy;
