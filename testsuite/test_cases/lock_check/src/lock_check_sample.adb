--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Lock_Check_Helper;

package body Lock_Check_Sample is

   protected body Internal_Chain is
      procedure Enter is
      begin
         Middle;
      end Enter;

      procedure Middle is
      begin
         Inner;
      end Middle;

      procedure Inner is
      begin
         null;
      end Inner;
   end Internal_Chain;

   protected body Reentered is
      procedure Enter is
      begin
         Lock_Check_Helper.Trigger;
      end Enter;

      procedure Inner is
      begin
         null;
      end Inner;
   end Reentered;

   protected body Clean is
      procedure Op is
      begin
         null;
      end Op;
   end Clean;

end Lock_Check_Sample;
