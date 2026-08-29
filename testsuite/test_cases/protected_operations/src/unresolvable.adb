--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Unresolvable is

   protected body Cell is
      procedure Set (Value : Integer) is
      begin
         Data := Value;
      end Set;

      function Get return Integer is
      begin
         return Data;
      end Get;
   end Cell;

   task body Direct_User is
   begin
      Direct.Set (7);
   end Direct_User;

   task body Selector is
      I : Index := 1;
   begin
      Cells (I).Set (42);
   end Selector;

end Unresolvable;
