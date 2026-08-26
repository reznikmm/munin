--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Guard_Pkg is

   protected body Guard is
      entry Wait when Open is
      begin
         null;
      end Wait;

      procedure Signal is
      begin
         Open := True;
      end Signal;
   end Guard;

   task body Worker is
   begin
      Guard.Wait;
      Guard.Signal;
   end Worker;

end Guard_Pkg;
