--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Proc_A;

procedure Proc_B (Count : Natural) is
begin
   if Count > 0 then
      Proc_A (Count - 1);
   end if;
end Proc_B;
