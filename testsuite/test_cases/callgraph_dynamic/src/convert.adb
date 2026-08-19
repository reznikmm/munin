--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

function Convert (Func : access procedure) return Integer is
   pragma Suppress (All_Checks);
begin
   Func.all;
   return 0;
end Convert;
