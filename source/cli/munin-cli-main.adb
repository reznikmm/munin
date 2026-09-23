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
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with VSS.Command_Line;
with VSS.String_Vectors;
with VSS.Strings;
with VSS.Strings.Conversions;
with VSS.Strings.Hash;

procedure Munin.CLI.Main is

   use type Munin.Call_Graph_Providers.Call_Graph_Provider_Access;

   function Pad_Right (Text : String; Width : Natural) return String;

   function Priority_Image
     (Value : Munin.Priorities.Optional_Priority) return String;

   function Name_Column_Width
     (Task_Items      : Munin.Tasks.Task_Unit_Array;
      Protected_Items : Munin.Protected_Objects.Protected_Object_Array)
      return Natural;

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

   function Pad_Right (Text : String; Width : Natural) return String is
   begin
      if Text'Length >= Width then
         return Text;
      end if;

      return Text & (1 .. Width - Text'Length => ' ');
   end Pad_Right;

   function Priority_Image
     (Value : Munin.Priorities.Optional_Priority) return String is
   begin
      if Value.Has_Value then
         return Ada.Strings.Fixed.Trim (Value.Value'Image, Ada.Strings.Both);
      else
         return "(Default)";
      end if;
   end Priority_Image;

   function Name_Column_Width
     (Task_Items      : Munin.Tasks.Task_Unit_Array;
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

   procedure Print_Priorities (Context : Munin.Contexts.Context) is
      Task_Items      : constant Munin.Tasks.Task_Unit_Array :=
        Munin.Contexts.Tasks (Context);
      Protected_Items :
        constant Munin.Protected_Objects.Protected_Object_Array :=
          Munin.Contexts.Protected_Objects (Context);
      Name_Width      : constant Natural :=
        Name_Column_Width (Task_Items, Protected_Items);
      Label_Width     : constant Natural := 11;
      Total           : constant Natural :=
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
         Name           : constant String :=
           VSS.Strings.Conversions.To_UTF_8_String
             (if Qualified_Name.Is_Empty then Image else Qualified_Name);
         Position       : constant Munin.Optional_Position :=
           Provider.Position (Node);
      begin
         Ada.Text_IO.Put ((1 .. Depth * 2 => ' ') & Name);

         if Position.Is_Set then
            Ada.Text_IO.Put
              (" ("
               & Ada.Directories.Simple_Name
                   (VSS.Strings.Conversions.To_UTF_8_String (Position.File))
               & ":"
               & Ada.Strings.Fixed.Trim (Position.Line'Image, Ada.Strings.Both)
               & ":"
               & Ada.Strings.Fixed.Trim
                   (Position.Column'Image, Ada.Strings.Both)
               & ")");
         end if;

         if Path.Contains (Image) then
            Ada.Text_IO.Put_Line ("  (recursive call)");
            return;
         end if;

         Ada.Text_IO.New_Line;
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

      Ada.Text_IO.Put_Line ("Call Graph:");
      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");

      for Root of Provider.Tasks loop
         Print_Node (Root, 0, Path);
      end loop;

      for Root of Provider.Interrupt_Handlers loop
         Print_Node (Root, 0, Path);
      end loop;

      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");
   end Print_Call_Graph;

   procedure Print_Cycles (Context : Munin.Contexts.Context) is
      Provider :
        constant Munin.Call_Graph_Providers.Call_Graph_Provider_Access :=
          Munin.Contexts.Call_Graph (Context);

      procedure Print_Group
        (Group : Munin.Call_Graph_Cycles.Cycle_Group; Index : Positive);

      procedure Print_Group
        (Group : Munin.Call_Graph_Cycles.Cycle_Group; Index : Positive) is
      begin
         Ada.Text_IO.Put_Line
           ("Cycle "
            & Ada.Strings.Fixed.Trim (Index'Image, Ada.Strings.Both)
            & ":");

         for Node of Group loop
            declare
               Qualified_Name : constant VSS.Strings.Virtual_String :=
                 Provider.Qualified_Name (Node);
               Name           : constant String :=
                 VSS.Strings.Conversions.To_UTF_8_String
                   (if Qualified_Name.Is_Empty
                    then Provider.Image (Node)
                    else Qualified_Name);
               Position       : constant Munin.Optional_Position :=
                 Provider.Position (Node);
            begin
               Ada.Text_IO.Put ("  " & Name);

               if Position.Is_Set then
                  Ada.Text_IO.Put
                    (" ("
                     & Ada.Directories.Simple_Name
                         (VSS.Strings.Conversions.To_UTF_8_String
                            (Position.File))
                     & ":"
                     & Ada.Strings.Fixed.Trim
                         (Position.Line'Image, Ada.Strings.Both)
                     & ":"
                     & Ada.Strings.Fixed.Trim
                         (Position.Column'Image, Ada.Strings.Both)
                     & ")");
               end if;

               Ada.Text_IO.New_Line;
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

      Ada.Text_IO.Put_Line ("Cycles:");
      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");

      if Groups.Is_Empty then
         Ada.Text_IO.Put_Line ("No cycles found.");
      else
         for Index in 1 .. Groups.Last_Index loop
            Print_Group (Groups (Index), Index);
         end loop;
      end if;

      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");
   end Print_Cycles;

   procedure Print_Priority_Violations (Context : Munin.Contexts.Context) is
      Provider :
        constant Munin.Call_Graph_Providers.Call_Graph_Provider_Access :=
          Munin.Contexts.Call_Graph (Context);

      procedure Print_Node (Node : Munin.Call_Graph_Providers.Call_Graph_Node);

      procedure Print_Node (Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      is
         Qualified_Name : constant VSS.Strings.Virtual_String :=
           Provider.Qualified_Name (Node);
         Name           : constant String :=
           VSS.Strings.Conversions.To_UTF_8_String
             (if Qualified_Name.Is_Empty
              then Provider.Image (Node)
              else Qualified_Name);
         Position       : constant Munin.Optional_Position :=
           Provider.Position (Node);
      begin
         Ada.Text_IO.Put ("    " & Name);

         if Position.Is_Set then
            Ada.Text_IO.Put
              (" ("
               & Ada.Directories.Simple_Name
                   (VSS.Strings.Conversions.To_UTF_8_String (Position.File))
               & ":"
               & Ada.Strings.Fixed.Trim (Position.Line'Image, Ada.Strings.Both)
               & ":"
               & Ada.Strings.Fixed.Trim
                   (Position.Column'Image, Ada.Strings.Both)
               & ")");
         end if;

         Ada.Text_IO.New_Line;
      end Print_Node;

      Violations : Munin.Priority_Checks.Violation_List;
   begin
      if Provider = null then
         VSS.Command_Line.Report_Error
           (Munin.Contexts.Call_Graph_Error (Context));
      end if;

      Violations := Munin.Priority_Checks.Check (Context, Provider.all);

      Ada.Text_IO.Put_Line ("Priority-Ceiling Violations:");
      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");

      if Violations.Is_Empty then
         Ada.Text_IO.Put_Line ("No priority-ceiling violations found.");
      else
         for Item of Violations loop
            Ada.Text_IO.Put_Line
              (VSS.Strings.Conversions.To_UTF_8_String (Item.Object_Name)
               & "  ceiling:"
               & Item.Ceiling'Image
               & "  reached at priority:"
               & Item.Reached_At'Image);

            for Node of Item.Path loop
               Print_Node (Node);
            end loop;

            Ada.Text_IO.New_Line;
         end loop;
      end if;

      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");
   end Print_Priority_Violations;

   procedure Print_Interrupts (Context : Munin.Contexts.Context) is
      Handler_Items :
        constant Munin.Interrupt_Handlers.Interrupt_Handler_Array :=
          Munin.Contexts.Interrupt_Handlers (Context);
      Name_Width    : Natural := 0;
   begin
      for Item of Handler_Items loop
         declare
            Name : constant String :=
              VSS.Strings.Conversions.To_UTF_8_String
                (Munin.Interrupt_Handlers.Qualified_Name (Item));
         begin
            if Name'Length > Name_Width then
               Name_Width := Name'Length;
            end if;
         end;
      end loop;

      Ada.Text_IO.Put_Line ("Interrupt Handlers:");
      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");

      for Item of Handler_Items loop
         declare
            Name    : constant String :=
              VSS.Strings.Conversions.To_UTF_8_String
                (Munin.Interrupt_Handlers.Qualified_Name (Item));
            Owner   : constant VSS.Strings.Virtual_String :=
              Munin.Interrupt_Handlers.Protected_Object (Item);
            Ceiling : constant Munin.Priorities.Priority_Value :=
              Munin.Contexts.Protected_Object_Ceiling (Context, Owner);
         begin
            Ada.Text_IO.Put_Line
              (Pad_Right (Name, Name_Width)
               & "  Protected Object: "
               & VSS.Strings.Conversions.To_UTF_8_String (Owner)
               & "  Priority: "
               & Ada.Strings.Fixed.Trim (Ceiling'Image, Ada.Strings.Both));
         end;
      end loop;

      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");
      Ada.Text_IO.Put_Line
        ("Scan complete. Found "
         & Ada.Strings.Fixed.Trim
             (Handler_Items'Length'Image, Ada.Strings.Both)
         & " interrupt handlers.");
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
         Name           : constant String :=
           VSS.Strings.Conversions.To_UTF_8_String
             (if Qualified_Name.Is_Empty
              then Provider.Image (Node)
              else Qualified_Name);
         Position       : constant Munin.Optional_Position :=
           Provider.Position (Node);
      begin
         Ada.Text_IO.Put ("    " & Name);

         if Position.Is_Set then
            Ada.Text_IO.Put
              (" ("
               & Ada.Directories.Simple_Name
                   (VSS.Strings.Conversions.To_UTF_8_String (Position.File))
               & ":"
               & Ada.Strings.Fixed.Trim (Position.Line'Image, Ada.Strings.Both)
               & ":"
               & Ada.Strings.Fixed.Trim
                   (Position.Column'Image, Ada.Strings.Both)
               & ")");
         end if;

         Ada.Text_IO.New_Line;
      end Print_Node;

      Violations : Munin.Lock_Checks.Violation_List;
   begin
      if Provider = null then
         VSS.Command_Line.Report_Error
           (Munin.Contexts.Call_Graph_Error (Context));
      end if;

      Violations := Munin.Lock_Checks.Check (Provider.all);

      Ada.Text_IO.Put_Line ("Protected-Object Re-Entries:");
      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");

      if Violations.Is_Empty then
         Ada.Text_IO.Put_Line ("No protected-object re-entries found.");
      else
         for Item of Violations loop
            Ada.Text_IO.Put_Line
              (VSS.Strings.Conversions.To_UTF_8_String (Item.Object_Name)
               & "  called back into while already locked");

            for Node of Item.Path loop
               Print_Node (Node);
            end loop;

            Ada.Text_IO.New_Line;
         end loop;
      end if;

      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");
   end Print_Lock_Violations;

   procedure Print_Stack_Usage (Context : Munin.Contexts.Context) is
      Provider :
        constant Munin.Call_Graph_Providers.Call_Graph_Provider_Access :=
          Munin.Contexts.Call_Graph (Context);

      function Node_Name
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node) return String;

      function Node_Name
        (Node : Munin.Call_Graph_Providers.Call_Graph_Node) return String
      is
         Qualified_Name : constant VSS.Strings.Virtual_String :=
           Provider.Qualified_Name (Node);
      begin
         return
           VSS.Strings.Conversions.To_UTF_8_String
             (if Qualified_Name.Is_Empty
              then Provider.Image (Node)
              else Qualified_Name);
      end Node_Name;

      procedure Print_Root
        (Node       : Munin.Call_Graph_Providers.Call_Graph_Node;
         Label      : String;
         Name_Width : Natural);

      procedure Print_Root
        (Node       : Munin.Call_Graph_Providers.Call_Graph_Node;
         Label      : String;
         Name_Width : Natural)
      is
         Usage : constant Munin.Call_Graph_Providers.Stack_Usage :=
           Provider.Resolve (Node);
      begin
         Ada.Text_IO.Put
           (Pad_Right (Label, 13)
            & " "
            & Pad_Right (Node_Name (Node), Name_Width)
            & "  Stack: "
            & Ada.Strings.Fixed.Trim (Usage.Stack_Used'Image, Ada.Strings.Both)
            & " bytes");

         if Usage.Cycle then
            Ada.Text_IO.Put ("  [call cycle: lower bound only]");
         end if;

         if Usage.Indirect_Calls > 0 then
            Ada.Text_IO.Put
              ("  [indirect calls: "
               & Ada.Strings.Fixed.Trim
                   (Usage.Indirect_Calls'Image, Ada.Strings.Both)
               & "]");
         end if;

         if Usage.Dynamic_Objects > 0 then
            Ada.Text_IO.Put
              ("  [dynamic allocations: "
               & Ada.Strings.Fixed.Trim
                   (Usage.Dynamic_Objects'Image, Ada.Strings.Both)
               & "]");
         end if;

         Ada.Text_IO.New_Line;
      end Print_Root;

   begin
      if Provider = null then
         VSS.Command_Line.Report_Error
           (Munin.Contexts.Call_Graph_Error (Context));
      end if;

      declare
         Task_Items    :
           constant Munin.Call_Graph_Providers.Call_Graph_Node_Array :=
             Provider.Tasks;
         Handler_Items :
           constant Munin.Call_Graph_Providers.Call_Graph_Node_Array :=
             Provider.Interrupt_Handlers;
         Name_Width    : Natural := 0;
      begin
         for Node of Task_Items loop
            Name_Width := Natural'Max (Name_Width, Node_Name (Node)'Length);
         end loop;

         for Node of Handler_Items loop
            Name_Width := Natural'Max (Name_Width, Node_Name (Node)'Length);
         end loop;

         Ada.Text_IO.Put_Line ("Worst-Case Stack Usage:");
         Ada.Text_IO.Put_Line
           ("--------------------------------------------------");

         for Node of Task_Items loop
            Print_Root (Node, "[TASK]", Name_Width);
         end loop;

         for Node of Handler_Items loop
            Print_Root (Node, "[INTERRUPT]", Name_Width);
         end loop;

         Ada.Text_IO.Put_Line
           ("--------------------------------------------------");
         Ada.Text_IO.Put_Line
           ("Scan complete. Found "
            & Ada.Strings.Fixed.Trim
                (Natural'(Task_Items'Length + Handler_Items'Length)'Image,
                 Ada.Strings.Both)
            & " roots.");
      end;
   end Print_Stack_Usage;

   Command : constant Munin.CLI.Command_Line.Command :=
     Munin.CLI.Command_Line.Parse;

begin
   Ada.Text_IO.Put_Line
     ("Scanning project: "
      & VSS.Strings.Conversions.To_UTF_8_String (Command.Project_File));
   Ada.Text_IO.New_Line;

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
         Ada.Text_IO.Put_Line
           ("warning: " & VSS.Strings.Conversions.To_UTF_8_String (Item));
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
