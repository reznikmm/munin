--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  An ordinary subprogram, unrelated to any protected object of its
--  own, used by Lock_Check_Sample.Reentered to show a re-entrant call
--  reached through a third party rather than written directly.

package Lock_Check_Helper is

   procedure Trigger;
   --  Calls back into Lock_Check_Sample.Reentered.Inner -- with no
   --  knowledge, at this point in the source, of being called from
   --  inside one of Reentered's own protected actions.

end Lock_Check_Helper;
