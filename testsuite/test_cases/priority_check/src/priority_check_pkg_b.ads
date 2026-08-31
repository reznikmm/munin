--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  Declares a task named Worker, same simple name as
--  Priority_Check_Pkg_A.Worker in a different package -- see that
--  package's header comment.

package Priority_Check_Pkg_B is

   protected Guard with Priority => 20 is
      procedure Op;
   end Guard;

   task Worker with Priority => 25;
   --  25 > Guard's ceiling (20): a violation -- and, unlike
   --  Priority_Check_Pkg_A.Worker (priority 10, same simple name,
   --  same-ceilinged Guard), it must be reported as one.

end Priority_Check_Pkg_B;
