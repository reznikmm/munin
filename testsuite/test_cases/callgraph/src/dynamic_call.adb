--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  exercises an indirect call through an access-to-procedure value, which
--  GCC reports via the `__indirect_call` placeholder node.

with Convert, Nil;

procedure Dynamic_Call is
begin
   for J in 1 .. 10 loop
      exit when Convert (Nil'Access) < 10;
   end loop;
end Dynamic_Call;
