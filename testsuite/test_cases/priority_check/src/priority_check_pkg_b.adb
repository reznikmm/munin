--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Priority_Check_Pkg_B is

   protected body Guard is
      procedure Op is
      begin
         null;
      end Op;
   end Guard;

   task body Worker is
   begin
      Guard.Op;
   end Worker;

end Priority_Check_Pkg_B;
