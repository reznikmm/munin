--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;

with Munin.Priorities;

package Munin.Priority_Sources is

   type Priority_Source is limited interface;
   --  Answers the priority queries needed by Munin.Priority_Checks.

   function Task_Priority
     (Self : Priority_Source; Task_Position : Munin.Optional_Position)
      return Munin.Priorities.Priority_Value
   is abstract;
   --  The priority of the task whose body is declared at Task_Position.

   function Interrupt_Handler_Priority
     (Self : Priority_Source; Handler_Position : Munin.Optional_Position)
      return Munin.Priorities.Priority_Value
   is abstract;
   --  The active priority of the interrupt handler declared at
   --  Handler_Position.

   function Protected_Object_Ceiling
     (Self : Priority_Source; Qualified_Name : VSS.Strings.Virtual_String)
      return Munin.Priorities.Priority_Value
   is abstract;
   --  The ceiling of the protected object named Qualified_Name.

end Munin.Priority_Sources;
