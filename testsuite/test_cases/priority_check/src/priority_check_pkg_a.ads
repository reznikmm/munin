--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  Declares a task named Worker, same simple name as
--  Priority_Check_Pkg_B.Worker in a different package -- used together
--  with that package to prove Munin.Contexts.Task_Priority's
--  Position-based join attributes each Worker's priority independently,
--  rather than by (ambiguous) simple name.

package Priority_Check_Pkg_A is

   protected Guard with Priority => 20 is
      procedure Op;
   end Guard;

   task Worker with Priority => 10;
   --  10 <= Guard's ceiling (20): no violation.

end Priority_Check_Pkg_A;
