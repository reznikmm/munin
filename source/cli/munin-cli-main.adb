--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.Contexts;
with Munin.Priorities;
with Munin.Protected_Objects;
with Munin.Tasks;

with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with VSS.Application;
with VSS.Command_Line;
with VSS.Command_Line.Parsers;
with VSS.String_Vectors;
with VSS.Strings;
with VSS.Strings.Conversions;

procedure Munin.CLI.Main is

   function Pad_Right (Text : String; Width : Natural) return String;

   function Priority_Image (Value : Munin.Priorities.Optional_Priority)
      return String;

   function Name_Column_Width
     (Task_Items : Munin.Tasks.Task_Unit_Array;
      Protected_Items : Munin.Protected_Objects.Protected_Object_Array)
      return Natural;

   Parser : VSS.Command_Line.Parsers.Command_Line_Parser;
   Help_Option : constant VSS.Command_Line.Binary_Option :=
     (Short_Name  => "h",
      Long_Name   => "help",
      Description => "Display help information");
   Project_Option : constant VSS.Command_Line.Value_Option :=
     (Short_Name  => "P",
      Long_Name   => "project",
      Value_Name  => "<project-file>",
      Description => "Path to the target Ada project (.gpr) file");

   function Pad_Right (Text : String; Width : Natural) return String is
   begin
      if Text'Length >= Width then
         return Text;
      end if;

      return Text & (1 .. Width - Text'Length => ' ');
   end Pad_Right;

   function Priority_Image (Value : Munin.Priorities.Optional_Priority)
      return String
   is
   begin
      if Value.Has_Value then
         return
           Ada.Strings.Fixed.Trim (Value.Value'Image, Ada.Strings.Both);
      else
         return "(Default)";
      end if;
   end Priority_Image;

   function Name_Column_Width
     (Task_Items : Munin.Tasks.Task_Unit_Array;
      Protected_Items : Munin.Protected_Objects.Protected_Object_Array)
      return Natural
   is
      Result : Natural := 0;
   begin
      for Item of Task_Items loop
         declare
            Name : constant String :=
              VSS.Strings.Conversions.To_UTF_8_String
                (Munin.Tasks.Qualified_Name (Item));
         begin
            if Name'Length > Result then
               Result := Name'Length;
            end if;
         end;
      end loop;

      for Item of Protected_Items loop
         declare
            Name : constant String :=
              VSS.Strings.Conversions.To_UTF_8_String
                (Munin.Protected_Objects.Qualified_Name (Item));
         begin
            if Name'Length > Result then
               Result := Name'Length;
            end if;
         end;
      end loop;

      return Result;
   end Name_Column_Width;

begin
   Parser.Add_Option (Help_Option);
   Parser.Add_Option (Project_Option);

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

   if not Parser.Positional_Arguments.Is_Empty then
      VSS.Command_Line.Report_Error
        (VSS.Strings.Conversions.To_Virtual_String
           ("Unexpected argument: "
            & VSS.Strings.Conversions.To_UTF_8_String
                (Parser.Positional_Arguments.First_Element)));
   end if;

   if not Parser.Is_Specified (Project_Option) then
      VSS.Command_Line.Report_Error
        (VSS.Strings.Conversions.To_Virtual_String
           ("Missing required --project/-P argument"));
   end if;

   Ada.Text_IO.Put_Line
     ("Scanning project: "
         & VSS.Strings.Conversions.To_UTF_8_String
               (Parser.Value (Project_Option)));
   Ada.Text_IO.New_Line;

   declare
      Context : Munin.Contexts.Context;
      Errors  : VSS.String_Vectors.Virtual_String_Vector;
   begin
      Munin.Contexts.Load_Project
        (Self         => Context,
         Project_File => Parser.Value (Project_Option),
         Errors       => Errors);

      if not Errors.Is_Empty then
         VSS.Command_Line.Report_Error (Errors);
      end if;

      declare
         Task_Items : constant Munin.Tasks.Task_Unit_Array :=
           Munin.Contexts.Tasks (Context);
         Protected_Items :
           constant Munin.Protected_Objects.Protected_Object_Array :=
             Munin.Contexts.Protected_Objects (Context);
         Name_Width : constant Natural :=
           Name_Column_Width (Task_Items, Protected_Items);
         Label_Width : constant Natural := 11;
         Total : constant Natural :=
           Task_Items'Length + Protected_Items'Length;
      begin
         Ada.Text_IO.Put_Line ("Discovered Concurrency Objects:");
         Ada.Text_IO.Put_Line
           ("--------------------------------------------------");

         for Item of Task_Items loop
            declare
               Name : constant String :=
                 VSS.Strings.Conversions.To_UTF_8_String
                   (Munin.Tasks.Qualified_Name (Item));
            begin
               Ada.Text_IO.Put_Line
                 (Pad_Right ("[TASK]", Label_Width)
                  & " "
                  & Pad_Right (Name, Name_Width)
                  & "  Priority: "
                  & Priority_Image (Munin.Tasks.Priority (Item)));
            end;
         end loop;

         for Item of Protected_Items loop
            declare
               Name : constant String :=
                 VSS.Strings.Conversions.To_UTF_8_String
                   (Munin.Protected_Objects.Qualified_Name (Item));
            begin
               Ada.Text_IO.Put_Line
                 (Pad_Right ("[PROTECTED]", Label_Width)
                  & " "
                  & Pad_Right (Name, Name_Width)
                  & "  Priority: "
                  & Priority_Image (Munin.Protected_Objects.Priority (Item)));
            end;
         end loop;

         Ada.Text_IO.Put_Line
           ("--------------------------------------------------");
         Ada.Text_IO.Put_Line
           ("Scan complete. Found "
            & Ada.Strings.Fixed.Trim (Total'Image, Ada.Strings.Both)
            & " objects.");
      end;
   end;
end Munin.CLI.Main;
