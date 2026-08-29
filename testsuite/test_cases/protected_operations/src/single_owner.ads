--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  A plain protected object with exactly one owner, called from a task,
--  plus an unqualified self-call between two of its own operations. Used
--  by Munin's own testsuite to verify Is_Protected_Operation/
--  Protected_Object_Name resolve both cases correctly, and that a
--  self-call never produces a "cannot determine" diagnostic.

package Single_Owner is

   protected Counter is
      procedure Increment;
      procedure Reset;
      function Value return Integer;
   private
      Current : Integer := 0;
   end Counter;

   task Ticker;

end Single_Owner;
