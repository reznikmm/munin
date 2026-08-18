--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with Ada.Synchronous_Task_Control;

package body Priority_Sample is

   task body Telemetry is
      Local_Ready : Ada.Synchronous_Task_Control.Suspension_Object;
   begin
      loop
         delay 1.0;
      end loop;
   end Telemetry;

   protected body Shared_Register is

      procedure Write (Value : Integer) is
      begin
         Data := Value;
      end Write;

      function Read return Integer is
      begin
         return Data;
      end Read;

   end Shared_Register;

   task body Interrupt_Task is
   begin
      loop
         delay 1.0;
      end loop;
   end Interrupt_Task;

   protected body Guard_Type is

      procedure Set (Value : Integer) is
      begin
         Data := Value;
      end Set;

      function Get return Integer is
      begin
         return Data;
      end Get;

   end Guard_Type;

   task body Worker_Type is
   begin
      loop
         delay 1.0;
      end loop;
   end Worker_Type;

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

   protected body Pragma_Register is

      procedure Write (Value : Integer) is
      begin
         Data := Value;
      end Write;

      function Read return Integer is
      begin
         return Data;
      end Read;

   end Pragma_Register;

   task body Pragma_Task is
   begin
      loop
         delay 1.0;
      end loop;
   end Pragma_Task;

end Priority_Sample;
