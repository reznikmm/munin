--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

procedure Proc_C (Count : Natural) is
begin
   if Count > 0 then
      Proc_C (Count - 1);
   end if;
end Proc_C;
