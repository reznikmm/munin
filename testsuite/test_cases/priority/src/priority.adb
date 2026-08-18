--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  Main procedure for the priority testcase application.
--  Withing Priority_Sample causes its task and protected object to be
--  elaborated. This application targets the RP2040 (light-tasking runtime)
--  and is analyzed by Munin rather than executed on a host machine.

with Ada.Synchronous_Task_Control;

with Priority_Sample;
pragma Unreferenced (Priority_Sample);

with Gen_Pkg;
pragma Unreferenced (Gen_Pkg);

with Readers_24;
pragma Unreferenced (Readers_24);

procedure Priority is

   --  A library-level task/protected object can never be declared locally
   --  in main (No_Task_Hierarchy, No_Local_Protected_Objects), but an
   --  object of a private type whose full view is protected -- such as
   --  Ada.Synchronous_Task_Control.Suspension_Object -- is just an
   --  ordinary object declaration and isn't restricted; it is elaborated
   --  once, when main starts, and (per Munin.Contexts.Traverses.
   --  Each_Effectively_Global_Name's rationale) lives for the whole
   --  program.
   Main_Ready : Ada.Synchronous_Task_Control.Suspension_Object;

begin
   null;
end Priority;
