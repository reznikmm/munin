--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.CLI.Command_Line;
with Munin.Call_Graph_Cycles;
with Munin.Call_Graph_Providers;
with Munin.Contexts;
with Munin.Interrupt_Handlers;
with Munin.Lock_Checks;
with Munin.Priorities;
with Munin.Priority_Checks;
with Munin.Protected_Objects;
with Munin.Tasks;

with Ada.Containers.Hashed_Sets;
with Ada.Directories;

with VSS.Characters.Latin;
with VSS.Command_Line;
with VSS.String_Vectors;
with VSS.Strings;
with VSS.Strings.Conversions;
with VSS.Strings.Formatters.Integers;
with VSS.Strings.Formatters.Strings;
with VSS.Strings.Hash;
with VSS.Strings.Templates;
with VSS.Text_Streams;
with VSS.Text_Streams.Standards;

procedure Munin.CLI.Main is

   use type Munin.Call_Graph_Providers.Call_Graph_Provider_Access;
   use type VSS.Strings.Character_Offset;

   Output  : VSS.Text_Streams.Output_Text_Stream'Class :=
     VSS.Text_Streams.Standards.Standard_Output;
   Success : Boolean := True;
   --  Every report below is written through Output; Success is threaded
   --  through every call and, per VSS.Text_Streams's contract, latches
   --  False on the first write failure and makes every later call a
   --  no-op -- so it is set up once here and never inspected again.

   Separator : constant VSS.Strings.Virtual_String :=
     "--------------------------------------------------";

   Scanning_Template :
     constant VSS.Strings.Templates.Virtual_String_Template :=
       "Scanning project: {1}";

   Warning_Template : constant VSS.Strings.Templates.Virtual_String_Template :=
     "warning: {1}";

   Scan_Complete_Template :
     constant VSS.Strings.Templates.Virtual_String_Template :=
       "Scan complete. Found {1} {2}.";

   function Pad_Right
     (Text : VSS.Strings.Virtual_String; Width : VSS.Strings.Character_Count)
      return VSS.Strings.Virtual_String;
   --  Text, right-padded with spaces to Width characters; returned
   --  unchanged when Text is already Width characters or longer. VSS's
   --  string template placeholders carry no general column-width/
   --  alignment support of their own (only a formatter-specific "format"
   --  string, which VSS.Strings.Formatters.Strings ignores entirely), so
   --  column alignment is done by pre-padding the value passed to the
   --  template instead.

   function Priority_Image
     (Value : Munin.Priorities.Optional_Priority)
      return VSS.Strings.Virtual_String;
   --  "(Default)", or Value.Value formatted as a plain integer.

   function Position_Suffix
     (Position : Munin.Optional_Position) return VSS.Strings.Virtual_String;
   --  " (file:line:column)", or an empty string when Position.Is_Set is
   --  False.

   procedure Print_Priorities (Context : Munin.Contexts.Context);
   --  Print the "Discovered Concurrency Objects" report.

   procedure Print_Call_Graph (Context : Munin.Contexts.Context);
   --  Print the call tree rooted at every task/main/interrupt-handler
   --  entry point known to Context's Call_Graph_Provider.

   procedure Print_Cycles (Context : Munin.Contexts.Context);
   --  Print every group of mutually-recursive subprograms found by
   --  Munin.Call_Graph_Cycles.Cycles, rooted at Context's
   --  Call_Graph_Provider's Tasks.

   procedure Print_Priority_Violations (Context : Munin.Contexts.Context);
   --  Print every priority-ceiling-locking violation found by
   --  Munin.Priority_Checks.Check.

   procedure Print_Interrupts (Context : Munin.Contexts.Context);
   --  Print the "Interrupt Handlers" report.

   procedure Print_Lock_Violations (Context : Munin.Contexts.Context);
   --  Print every protected-object re-entry found by
   --  Munin.Lock_Checks.Check.

   procedure Print_Stack_Usage (Context : Munin.Contexts.Context);
   --  Print the worst-case stack usage, computed by
   --  Munin.Call_Graph_Providers.Resolve, of every task and interrupt
   --  handler known to Context's Call_Graph_Provider.

   function Pad_Right
     (Text : VSS.Strings.Virtual_String; Width : VSS.Strings.Character_Count)
      return VSS.Strings.Virtual_String
   is
      Result : VSS.Strings.Virtual_String := Text;
   begin
      if Text.Character_Length < Width then
         Result.Append
           ((Width - Text.Character_Length) * VSS.Characters.Latin.Space);
      end if;

      return Result;
   end Pad_Right;

   function Priority_Image
     (Value : Munin.Priorities.Optional_Priority)
      return VSS.Strings.Virtual_String
   is
      Template : constant VSS.Strings.Templates.Virtual_String_Template :=
        "{1}";
   begin
      if Value.Has_Value then
         return
           Template.Format
             (VSS.Strings.Formatters.Integers.Image (Value.Value));
      else
         return "(Default)";
      end if;
   end Priority_Image;

   function Position_Suffix
     (Position : Munin.Optional_Position) return VSS.Strings.Virtual_String
   is
      Template : constant VSS.Strings.Templates.Virtual_String_Template :=
        " ({1}:{2}:{3})";
   begin
      if not Position.Is_Set then
         return "";
      end if;

      return
        Template.Format
          (VSS.Strings.Formatters.Strings.Image
             (VSS.Strings.Conversions.To_Virtual_String
                (Ada.Directories.Simple_Name
                   (VSS.Strings.Conversions.To_UTF_8_String (Position.File)))),
           VSS.Strings.Formatters.Integers.Image (Position.Line),
           VSS.Strings.Formatters.Integers.Image (Position.Column));
   end Position_Suffix;

   procedure Print_Priorities (Context : Munin.Contexts.Context) is
      Task_Items      : constant Munin.Tasks.Task_Unit_Array :=
        Munin.Contexts.Tasks (Context);
      Protected_Items :
        constant Munin.Protected_Objects.Protected_Object_Array :=
          Munin.Contexts.Protected_Objects (Context);

      Object_Template :
        constant VSS.Strings.Templates.Virtual_String_Template :=
          "{1} {2}  Priority: {3}";
   begin
      Output.Put_Line ("Discovered Concurrency Objects:", Success);
      Output.Put_Line (Separator, Success);

      for Item of Task_Items loop
         Output.Put_Line
           (Object_Template.Format
              (VSS.Strings.Formatters.Strings.Image (Pad_Right ("[TASK]", 11)),
               VSS.Strings.Formatters.Strings.Image
                 (Pad_Right (Munin.Tasks.Qualified_Name (Item), 24)),
               VSS.Strings.Formatters.Strings.Image
                 (Priority_Image (Munin.Tasks.Priority (Item)))),
            Success);
      end loop;

      for Item of Protected_Items loop
         Output.Put_Line
           (Object_Template.Format
              (VSS.Strings.Formatters.Strings.Image
                 (Pad_Right ("[PROTECTED]", 11)),
               VSS.Strings.Formatters.Strings.Image
                 (Pad_Right
                    (Munin.Protected_Objects.Qualified_Name (Item), 24)),
               VSS.Strings.Formatters.Strings.Image
                 (Priority_Image (Munin.Protected_Objects.Priority (Item)))),
            Success);
      end loop;

      Output.Put_Line (Separator, Success);
      Output.Put_Line
        (Scan_Complete_Template.Format
           (VSS.Strings.Formatters.Integers.Image
              (Task_Items'Length + Protected_Items'Length),
            VSS.Strings.Formatters.Strings.Image ("objects")),
         Success);
   end Print_Priorities;

   procedure Print_Call_Graph (Context : Munin.Contexts.Context) is
      package Symbol_Sets is new
        Ada.Containers.Hashed_Sets
          (Element_Type        => VSS.Strings.Virtual_String,
           Hash                => VSS.Strings.Hash,
           Equivalent_Elements => VSS.Strings."=",
           "="                 => VSS.Strings."=");

      Provider :
        constant Munin.Call_Graph_Providers.Call_Graph_Provider_Access :=
          Munin.Contexts.Call_Graph (Context);

      procedure Print_Node
        (Node  : Munin.Call_Graph_Providers.Call_Graph_Node;
         Depth : Natural;
         Path  : in out Symbol_Sets.Set);
      --  Print Node and its callees, indented by Depth levels; Path holds
      --  the symbols of Node's ancestors on the current branch, used to
      --  print a recursive call as a leaf instead of looping forever.

      procedure Print_Node
        (Node  : Munin.Call_Graph_Providers.Call_Graph_Node;
         Depth : Natural;
         Path  : in out Symbol_Sets.Set)
      is
         Image          : constant VSS.Strings.Virtual_String :=
           Provider.Image (Node);
         Qualified_Name : constant VSS.Strings.Virtual_String :=
           Provider.Qualified_Name (Node);
         Name           : constant VSS.Strings.Virtual_String :=
           (if Qualified_Name.Is_Empty then Image else Qualified_Name);
         Indent         : constant String (1 .. Depth * 2) := [others => ' '];
      begin
         Output.Put
           (VSS.Strings.Conversions.To_Virtual_String (Indent), Success);
         Output.Put (Name, Success);
         Output.Put (Position_Suffix (Provider.Position (Node)), Success);

         if Path.Contains (Image) then
            Output.Put_Line ("  (recursive call)", Success);
            return;
         end if;

         Output.New_Line (Success);
         Path.Insert (Image);

         for Callee of Provider.Callees (Node) loop
            Print_Node (Callee, Depth + 1, Path);
         end loop;

         Path.Delete (Image);
      end Print_Node;

      Path : Symbol_Sets.Set;
   begin
      if Provider = null then
         VSS.Command_Line.Report_Error
           (Munin.Contexts.Call_Graph_Error (Context));
      end if;

      Output.Put_Line ("Call Graph:", Success);
      Output.Put_Line (Separator, Success);

      for Root of Provider.Tasks loop
         Print_Node (Root, 0, Path);
      end loop;

      for Root of Provider.Interrupt_Handlers loop
         Print_Node (Root, 0, Path);
      end loop;

      Output.Put_Line (Separator, Success);
   end Print_Call_Graph;

   procedure Print_Cycles (Context : Munin.Contexts.Context) is
      Provider :
        constant Munin.Call_Graph_Providers.Call_Graph_Provider_Access :=
          Munin.Contexts.Call_Graph (Context);

      Cycle_Header_Template :
        constant VSS.Strings.Templates.Virtual_String_Template := "Cycle {1}:";

      procedure Print_Group
        (Group : Munin.Call_Graph_Cycles.Cycle_Group; Index : Positive);

      procedure Print_Group
        (Group : Munin.Call_Graph_Cycles.Cycle_Group; Index : Positive) is
      begin
         Output.Put_Line
           (Cycle_Header_Template.Format
              (VSS.Strings.Formatters.Integers.Image (Index)),
            Success);

         for Node of Group loop
            declare
               Qualified_Name : constant VSS.Strings.Virtual_String :=
                 Provider.Qualified_Name (Node);
               Name           : constant VSS.Strings.Virtual_String :=
                 (if Qualified_Name.Is_Empty
                  then Provider.Image (Node)
                  else Qualified_Name);
            begin
               Output.Put ("  ", Success);
               Output.Put (Name, Success);
               Output.Put
                 (Position_Suffix (Provider.Position (Node)), Success);
               Output.New_Line (Success);
            end;
         end loop;
      end Print_Group;

      Groups : Munin.Call_Graph_Cycles.Cycle_Groups;
   begin
      if Provider = null then
         VSS.Command_Line.Report_Error
           (Munin.Contexts.Call_Graph_Error (Context));
      end if;

      Groups := Munin.Call_Graph_Cycles.Cycles (Provider.all);

      Output.Put_Line ("Cycles:", Success);
      Output.Put_Line (Separator, Success);

      if Groups.Is_Empty then
         Output.Put_Line ("No cycles found.", Success);
      else
         for Index in 1 .. Groups.Last_Index loop
            Print_Group (Groups (Index), Index);
         end loop;
      end if;

      Output.Put_Line (Separator, Success);
   end Print_Cycles;

   procedure Print_Priority_Violations (Context : Munin.Contexts.Context) is
      Provider :
        constant Munin.Call_Graph_Providers.Call_Graph_Provider_Access :=
          Munin.Contexts.Call_Graph (Context);

      Violation_Template :
        constant VSS.Strings.Templates.Virtual_String_Template :=
          "{1}  ceiling:{2}  reached at priority:{3}";

      procedure Print_Node (Node : Munin.Call_Graph_Providers.Call_Graph_Node);

      procedure Print_Node (Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      is
         Qualified_Name : constant VSS.Strings.Virtual_String :=
           Provider.Qualified_Name (Node);
         Name           : constant VSS.Strings.Virtual_String :=
           (if Qualified_Name.Is_Empty
            then Provider.Image (Node)
            else Qualified_Name);
      begin
         Output.Put ("    ", Success);
         Output.Put (Name, Success);
         Output.Put (Position_Suffix (Provider.Position (Node)), Success);
         Output.New_Line (Success);
      end Print_Node;

      Violations : Munin.Priority_Checks.Violation_List;
   begin
      if Provider = null then
         VSS.Command_Line.Report_Error
           (Munin.Contexts.Call_Graph_Error (Context));
      end if;

      Violations := Munin.Priority_Checks.Check (Context, Provider.all);

      Output.Put_Line ("Priority-Ceiling Violations:", Success);
      Output.Put_Line (Separator, Success);

      if Violations.Is_Empty then
         Output.Put_Line ("No priority-ceiling violations found.", Success);
      else
         for Item of Violations loop
            Output.Put_Line
              (Violation_Template.Format
                 (VSS.Strings.Formatters.Strings.Image (Item.Object_Name),
                  VSS.Strings.Formatters.Integers.Image (Item.Ceiling),
                  VSS.Strings.Formatters.Integers.Image (Item.Reached_At)),
               Success);

            for Node of Item.Path loop
               Print_Node (Node);
            end loop;

            Output.New_Line (Success);
         end loop;
      end if;

      Output.Put_Line (Separator, Success);
   end Print_Priority_Violations;

   procedure Print_Interrupts (Context : Munin.Contexts.Context) is
      Handler_Items :
        constant Munin.Interrupt_Handlers.Interrupt_Handler_Array :=
          Munin.Contexts.Interrupt_Handlers (Context);

      Handler_Template :
        constant VSS.Strings.Templates.Virtual_String_Template :=
          "{1}  Protected Object: {2}  Priority: {3}";
   begin
      Output.Put_Line ("Interrupt Handlers:", Success);
      Output.Put_Line (Separator, Success);

      for Item of Handler_Items loop
         declare
            Owner   : constant VSS.Strings.Virtual_String :=
              Munin.Interrupt_Handlers.Protected_Object (Item);
            Ceiling : constant Munin.Priorities.Priority_Value :=
              Munin.Contexts.Protected_Object_Ceiling (Context, Owner);
         begin
            Output.Put_Line
              (Handler_Template.Format
                 (VSS.Strings.Formatters.Strings.Image
                    (Pad_Right
                       (Munin.Interrupt_Handlers.Qualified_Name (Item), 24)),
                  VSS.Strings.Formatters.Strings.Image (Owner),
                  VSS.Strings.Formatters.Integers.Image (Ceiling)),
               Success);
         end;
      end loop;

      Output.Put_Line (Separator, Success);
      Output.Put_Line
        (Scan_Complete_Template.Format
           (VSS.Strings.Formatters.Integers.Image (Handler_Items'Length),
            VSS.Strings.Formatters.Strings.Image ("interrupt handlers")),
         Success);
   end Print_Interrupts;

   procedure Print_Lock_Violations (Context : Munin.Contexts.Context) is
      Provider :
        constant Munin.Call_Graph_Providers.Call_Graph_Provider_Access :=
          Munin.Contexts.Call_Graph (Context);

      procedure Print_Node (Node : Munin.Call_Graph_Providers.Call_Graph_Node);

      procedure Print_Node (Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      is
         Qualified_Name : constant VSS.Strings.Virtual_String :=
           Provider.Qualified_Name (Node);
         Name           : constant VSS.Strings.Virtual_String :=
           (if Qualified_Name.Is_Empty
            then Provider.Image (Node)
            else Qualified_Name);
      begin
         Output.Put ("    ", Success);
         Output.Put (Name, Success);
         Output.Put (Position_Suffix (Provider.Position (Node)), Success);
         Output.New_Line (Success);
      end Print_Node;

      Violations : Munin.Lock_Checks.Violation_List;
   begin
      if Provider = null then
         VSS.Command_Line.Report_Error
           (Munin.Contexts.Call_Graph_Error (Context));
      end if;

      Violations := Munin.Lock_Checks.Check (Provider.all);

      Output.Put_Line ("Protected-Object Re-Entries:", Success);
      Output.Put_Line (Separator, Success);

      if Violations.Is_Empty then
         Output.Put_Line ("No protected-object re-entries found.", Success);
      else
         for Item of Violations loop
            Output.Put (Item.Object_Name, Success);
            Output.Put_Line
              ("  called back into while already locked", Success);

            for Node of Item.Path loop
               Print_Node (Node);
            end loop;

            Output.New_Line (Success);
         end loop;
      end if;

      Output.Put_Line (Separator, Success);
   end Print_Lock_Violations;

   procedure Print_Stack_Usage (Context : Munin.Contexts.Context) is
      Provider :
        constant Munin.Call_Graph_Providers.Call_Graph_Provider_Access :=
          Munin.Contexts.Call_Graph (Context);

      Root_Template : constant VSS.Strings.Templates.Virtual_String_Template :=
        "{1} {2}  Stack: {3} bytes";

      Cycle_Note : constant VSS.Strings.Virtual_String :=
        "  [call cycle: lower bound only]";

      Indirect_Note_Template :
        constant VSS.Strings.Templates.Virtual_String_Template :=
          "  [indirect calls: {1}]";

      Dynamic_Note_Template :
        constant VSS.Strings.Templates.Virtual_String_Template :=
          "  [dynamic allocations: {1}]";

      function Node_Name
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node)
         return VSS.Strings.Virtual_String;

      function Node_Name
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node)
         return VSS.Strings.Virtual_String
      is
         Qualified_Name : constant VSS.Strings.Virtual_String :=
           Provider.Qualified_Name (Node);
      begin
         return
           (if Qualified_Name.Is_Empty
            then Provider.Image (Node)
            else Qualified_Name);
      end Node_Name;

      procedure Print_Root
        (Node  : Munin.Call_Graph_Providers.Call_Graph_Node;
         Label : VSS.Strings.Virtual_String);

      procedure Print_Root
        (Node  : Munin.Call_Graph_Providers.Call_Graph_Node;
         Label : VSS.Strings.Virtual_String)
      is
         Usage : constant Munin.Call_Graph_Providers.Stack_Usage :=
           Provider.Resolve (Node);
      begin
         Output.Put
           (Root_Template.Format
              (VSS.Strings.Formatters.Strings.Image (Pad_Right (Label, 11)),
               VSS.Strings.Formatters.Strings.Image
                 (Pad_Right (Node_Name (Node), 24)),
               VSS.Strings.Formatters.Integers.Image (Usage.Stack_Used)),
            Success);

         if Usage.Cycle then
            Output.Put (Cycle_Note, Success);
         end if;

         if Usage.Indirect_Calls > 0 then
            Output.Put
              (Indirect_Note_Template.Format
                 (VSS.Strings.Formatters.Integers.Image
                    (Usage.Indirect_Calls)),
               Success);
         end if;

         if Usage.Dynamic_Objects > 0 then
            Output.Put
              (Dynamic_Note_Template.Format
                 (VSS.Strings.Formatters.Integers.Image
                    (Usage.Dynamic_Objects)),
               Success);
         end if;

         Output.New_Line (Success);
      end Print_Root;

   begin
      if Provider = null then
         VSS.Command_Line.Report_Error
           (Munin.Contexts.Call_Graph_Error (Context));
      end if;

      Output.Put_Line ("Worst-Case Stack Usage:", Success);
      Output.Put_Line (Separator, Success);

      for Node of Provider.Tasks loop
         Print_Root (Node, "[TASK]");
      end loop;

      for Node of Provider.Interrupt_Handlers loop
         Print_Root (Node, "[INTERRUPT]");
      end loop;

      Output.Put_Line (Separator, Success);
      Output.Put_Line
        (Scan_Complete_Template.Format
           (VSS.Strings.Formatters.Integers.Image
              (Provider.Tasks'Length + Provider.Interrupt_Handlers'Length),
            VSS.Strings.Formatters.Strings.Image ("roots")),
         Success);
   end Print_Stack_Usage;

   Command : constant Munin.CLI.Command_Line.Command :=
     Munin.CLI.Command_Line.Parse;

begin
   Output.Put_Line
     (Scanning_Template.Format
        (VSS.Strings.Formatters.Strings.Image (Command.Project_File)),
      Success);
   Output.New_Line (Success);

   declare
      Context  : Munin.Contexts.Context;
      Errors   : VSS.String_Vectors.Virtual_String_Vector;
      Warnings : VSS.String_Vectors.Virtual_String_Vector;
   begin
      Munin.Contexts.Load_Project
        (Self         => Context,
         Project_File => Command.Project_File,
         Errors       => Errors,
         Warnings     => Warnings);

      if not Errors.Is_Empty then
         VSS.Command_Line.Report_Error (Errors);
      end if;

      for Item of Warnings loop
         Output.Put_Line
           (Warning_Template.Format
              (VSS.Strings.Formatters.Strings.Image (Item)),
            Success);
      end loop;

      case Command.Subject is
         when Munin.CLI.Command_Line.Show_Priorities  =>
            Print_Priorities (Context);

         when Munin.CLI.Command_Line.Show_Callgraph   =>
            Print_Call_Graph (Context);

         when Munin.CLI.Command_Line.Show_Cycles      =>
            Print_Cycles (Context);

         when Munin.CLI.Command_Line.Show_Interrupts  =>
            Print_Interrupts (Context);

         when Munin.CLI.Command_Line.Show_Stack       =>
            Print_Stack_Usage (Context);

         when Munin.CLI.Command_Line.Check_Priorities =>
            Print_Priority_Violations (Context);

         when Munin.CLI.Command_Line.Check_Locks      =>
            Print_Lock_Violations (Context);
      end case;
   end;
end Munin.CLI.Main;
