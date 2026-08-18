--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  Sample Ada source containing one task and one protected object, each with
--  an explicit static priority. Used as the "under test" project for the
--  Munin priority-discovery testcase.
--  This source is analyzed by Munin (via Libadalang); it is not executed.

with System;

package Priority_Sample is

   --  A single task with a target-sensitive priority.
   task Telemetry
     with Priority => Standard'Address_Size;

   --  A protected object with an explicit priority.
   protected Shared_Register
     with Priority => 20
   is
      procedure Write (Value : Integer);
      function Read return Integer;
   private
      Data : Integer := 0;
   end Shared_Register;

   --  A task with an explicit interrupt priority.
   task Interrupt_Task
     with Interrupt_Priority => System.Interrupt_Priority'First;

   --  A protected type with an explicit priority, and a library-level
   --  object of it. Only the object (Guard), not the type, should be
   --  reported.
   protected type Guard_Type with Priority => 15 is
      procedure Set (Value : Integer);
      function Get return Integer;
   private
      Data : Integer := 0;
   end Guard_Type;

   Guard : Guard_Type;

   --  A task type with an explicit priority, and a library-level object of
   --  it. Only the object (Worker), not the type, should be reported.
   task type Worker_Type with Priority => 18;

   Worker : Worker_Type;

end Priority_Sample;
