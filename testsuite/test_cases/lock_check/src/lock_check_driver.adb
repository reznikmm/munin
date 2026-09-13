--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Lock_Check_Sample;

package body Lock_Check_Driver is

   task body Driver is
   begin
      Lock_Check_Sample.Internal_Chain.Enter;
      Lock_Check_Sample.Reentered.Enter;
      Lock_Check_Sample.Clean.Op;
   end Driver;

end Lock_Check_Driver;
