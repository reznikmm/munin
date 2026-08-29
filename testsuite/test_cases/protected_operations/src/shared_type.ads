--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  A protected type shared by two named objects, each called via a plain
--  dotted call from a different task. GNAT compiles Accumulator's
--  operations once, shared by both Acc_A and Acc_B; used by Munin's own
--  testsuite to verify node splitting resolves each call to the specific
--  object it targets.

package Shared_Type is

   protected type Accumulator is
      procedure Add (Value : Integer);
      function Total return Integer;
   private
      Sum : Integer := 0;
   end Accumulator;

   Acc_A : Accumulator;
   Acc_B : Accumulator;

   task Producer_A;
   task Producer_B;

end Shared_Type;
