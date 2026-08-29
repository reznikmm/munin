--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Shared_Type is

   protected body Accumulator is
      procedure Add (Value : Integer) is
      begin
         Sum := Sum + Value;
      end Add;

      function Total return Integer is
      begin
         return Sum;
      end Total;
   end Accumulator;

   task body Producer_A is
   begin
      Acc_A.Add (1);
   end Producer_A;

   task body Producer_B is
   begin
      Acc_B.Add (2);
   end Producer_B;

end Shared_Type;
