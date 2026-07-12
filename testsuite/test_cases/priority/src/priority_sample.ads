--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  Sample Ada source containing one task and one protected object, each with
--  an explicit static priority. Used as the "under test" project for the
--  Munin priority-discovery testcase.
--  This source is analyzed by Munin (via Libadalang); it is not executed.

package Priority_Sample is

   --  A single task with an explicit priority.
   task Telemetry
     with Priority => 10;

   --  A protected object with an explicit priority.
   protected Shared_Register
     with Priority => 20
   is
      procedure Write (Value : Integer);
      function Read return Integer;
   private
      Data : Integer := 0;
   end Shared_Register;

end Priority_Sample;
