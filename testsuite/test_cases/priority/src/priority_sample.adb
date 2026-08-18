--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

package body Priority_Sample is

   task body Telemetry is
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

end Priority_Sample;
