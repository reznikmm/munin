--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Priority_Check_Sample is

   protected body Low_Ceiling is
      procedure Op is
      begin
         null;
      end Op;
   end Low_Ceiling;

   task body High_Task is
   begin
      Low_Ceiling.Op;
   end High_Task;

   protected body High_Ceiling is
      procedure Enter_Nested is
      begin
         Nested_Low.Op;
      end Enter_Nested;
   end High_Ceiling;

   protected body Nested_Low is
      procedure Op is
      begin
         null;
      end Op;
   end Nested_Low;

   task body Nested_Task is
   begin
      High_Ceiling.Enter_Nested;
   end Nested_Task;

   protected body Consistent is
      procedure Op is
      begin
         null;
      end Op;
   end Consistent;

   task body Clean_Task is
   begin
      Consistent.Op;
   end Clean_Task;

   protected body Default_Object is
      procedure Op is
      begin
         null;
      end Op;
   end Default_Object;

   task body Default_Task is
   begin
      Default_Object.Op;
   end Default_Task;

end Priority_Check_Sample;
