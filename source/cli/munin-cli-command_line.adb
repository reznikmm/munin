--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Application;
with VSS.Command_Line.Parsers;
with VSS.Strings.Conversions;

package body Munin.CLI.Command_Line is

   use type VSS.Strings.Virtual_String;

   function Parse return Command is
      Parser         : VSS.Command_Line.Parsers.Command_Line_Parser;
      Help_Option    : constant VSS.Command_Line.Binary_Option :=
        (Short_Name  => "h",
         Long_Name   => "help",
         Description => "Display help information");
      Project_Option : constant VSS.Command_Line.Value_Option :=
        (Short_Name  => "P",
         Long_Name   => "project",
         Value_Name  => "<project-file>",
         Description => "Path to the target Ada project (.gpr) file");
      Command_Option : constant VSS.Command_Line.Positional_Option :=
        (Name => "command", Description => "Command to run: show");
      Subject_Option : constant VSS.Command_Line.Positional_Option :=
        (Name        => "subject",
         Description => "What to show: priorities, callgraph");
   begin
      Parser.Add_Option (Help_Option);
      Parser.Add_Option (Project_Option);
      Parser.Add_Option (Command_Option);
      Parser.Add_Option (Subject_Option);

      if not Parser.Parse (VSS.Application.Arguments) then
         VSS.Command_Line.Report_Error (Parser.Error_Message);
      end if;

      if Parser.Is_Specified (Help_Option) then
         VSS.Command_Line.Report_Message (Parser.Help_Text);
      end if;

      if not Parser.Unknown_Option_Arguments.Is_Empty then
         VSS.Command_Line.Report_Error
           (VSS.Strings.Conversions.To_Virtual_String
              ("Unknown option: "
               & VSS.Strings.Conversions.To_UTF_8_String
                   (Parser.Unknown_Option_Arguments.First_Element)));
      end if;

      if not Parser.Is_Specified (Project_Option) then
         VSS.Command_Line.Report_Error
           (VSS.Strings.Conversions.To_Virtual_String
              ("Missing required --project/-P argument"));
      end if;

      if Parser.Value (Command_Option) /= "show" then
         VSS.Command_Line.Report_Error
           (VSS.Strings.Conversions.To_Virtual_String
              ("Expected command: show priorities|callgraph"));
      end if;

      return Result : Command do
         Result.Project_File := Parser.Value (Project_Option);

         if Parser.Value (Subject_Option) = "priorities" then
            Result.Subject := Show_Priorities;

         elsif Parser.Value (Subject_Option) = "callgraph" then
            Result.Subject := Show_Callgraph;

         else
            VSS.Command_Line.Report_Error
              (VSS.Strings.Conversions.To_Virtual_String
                 ("Expected subject: priorities or callgraph"));
         end if;
      end return;
   end Parse;

end Munin.CLI.Command_Line;
