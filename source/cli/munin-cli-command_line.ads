--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Command line for the `munin` executable:
--
--    munin show priorities -P <project-file>
--    munin show callgraph  -P <project-file>

with VSS.Strings;

package Munin.CLI.Command_Line is

   type Subject_Kind is (Show_Priorities, Show_Callgraph);

   type Command is record
      Subject      : Subject_Kind;
      Project_File : VSS.Strings.Virtual_String;
   end record;

   function Parse return Command;
   --  Parse VSS.Application.Arguments as `show priorities|callgraph -P
   --  <project-file>`. On a parse error, an unknown/missing argument, or
   --  -h/--help, reports the message and terminates the process (via
   --  VSS.Command_Line.Report_Error/Report_Message) instead of returning.

end Munin.CLI.Command_Line;
