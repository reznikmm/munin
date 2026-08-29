--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Single_Owner is

   protected body Counter is
      procedure Increment is
      begin
         if Current < 0 then
            Reset;  --  Unqualified self-call: always Counter itself.
         end if;

         Current := Current + 1;
      end Increment;

      procedure Reset is
      begin
         Current := 0;
      end Reset;

      function Value return Integer is
      begin
         return Current;
      end Value;
   end Counter;

   task body Ticker is
   begin
      Counter.Increment;
   end Ticker;

end Single_Owner;
