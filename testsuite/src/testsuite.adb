--  SPDX-FileCopyrightText: 2026 Munin Developer
--
--  SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception
--
--  Testsuite main runner for Munin unit tests

with Test_Dummy;
with Trendy_Test.Reports;

procedure Testsuite is

   Tests : constant Trendy_Test.Test_Group :=
     (Test_Dummy.Test_Basic_Arithmetic'Access,
      Test_Dummy.Test_Comparison_Operations'Access);

begin
   Trendy_Test.Register (Tests);
   Trendy_Test.Reports.Print_Basic_Report (Trendy_Test.Run);
end Testsuite;
