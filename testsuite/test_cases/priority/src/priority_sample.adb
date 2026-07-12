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

end Priority_Sample;
