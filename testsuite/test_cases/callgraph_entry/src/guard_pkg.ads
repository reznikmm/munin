--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  A protected object with one entry and one procedure, and a task that
--  calls both directly. Used by Munin's own testsuite to verify that the
--  CI-backed call graph provider resolves the entry call (Guard.Wait) to
--  the entry's own body, instead of leaving it pointing at GNAT's opaque
--  runtime entry-call dispatcher.

package Guard_Pkg is

   protected Guard is
      entry Wait;
      procedure Signal;
   private
      Open : Boolean := False;
   end Guard;

   task Worker;

end Guard_Pkg;
