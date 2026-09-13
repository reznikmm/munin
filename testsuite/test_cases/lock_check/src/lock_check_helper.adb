--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Lock_Check_Sample;

package body Lock_Check_Helper is

   procedure Trigger is
   begin
      Lock_Check_Sample.Reentered.Inner;
   end Trigger;

end Lock_Check_Helper;
