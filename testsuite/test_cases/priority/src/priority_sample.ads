--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  Sample Ada source containing one task and one protected object, each with
--  an explicit static priority. Used as the "under test" project for the
--  Munin priority-discovery testcase.
--  This source is analyzed by Munin (via Libadalang); it is not executed.

with Ada.Synchronous_Task_Control;
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

   --  A protected type whose priority is given by a discriminant, and two
   --  library-level objects of it with different discriminant values (one
   --  named, one positional). Each object should get its own priority.
   protected type Accumulator (Pr : System.Any_Priority) with Priority => Pr
   is
      procedure Add (Value : Integer);
      function Total return Integer;
   private
      Sum : Integer := 0;
   end Accumulator;

   Acc_10 : Accumulator (Pr => 10);
   Acc_11 : Accumulator (11);

   --  A protected object using the pre-aspect pragma syntax.
   protected Pragma_Register is
      pragma Priority (22);

      procedure Write (Value : Integer);
      function Read return Integer;
   private
      Data : Integer := 0;
   end Pragma_Register;

   --  A task using the pre-aspect pragma syntax for Interrupt_Priority.
   task Pragma_Task is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);
   end Pragma_Task;

   --  A library-level object of a private type whose full view (in the
   --  runtime's private part) is implemented as protected. Only the object
   --  (Ready), not the type, should be reported.
   Ready : Ada.Synchronous_Task_Control.Suspension_Object;

end Priority_Sample;
