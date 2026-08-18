--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  exercises mutual recursion between Proc_A and Proc_B.

with Proc_A;

procedure Cycle_Call is
begin
   Proc_A (2);
end Cycle_Call;
