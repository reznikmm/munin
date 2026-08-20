--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.CLI.Command_Line;
with Munin.Call_Graph_Providers;
with Munin.Contexts;
with Munin.Priorities;
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
   --  Print the call tree rooted at every task/main entry point known to
   --  Context's Call_Graph_Provider.

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
         Position       :
           constant Munin.Call_Graph_Providers.Optional_Position :=
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

      Ada.Text_IO.Put_Line
        ("--------------------------------------------------");
   end Print_Call_Graph;

   Command : constant Munin.CLI.Command_Line.Command :=
     Munin.CLI.Command_Line.Parse;

begin
   Ada.Text_IO.Put_Line
     ("Scanning project: "
      & VSS.Strings.Conversions.To_UTF_8_String (Command.Project_File));
   Ada.Text_IO.New_Line;

   declare
      Context : Munin.Contexts.Context;
      Errors  : VSS.String_Vectors.Virtual_String_Vector;
   begin
      Munin.Contexts.Load_Project
        (Self         => Context,
         Project_File => Command.Project_File,
         Errors       => Errors);

      if not Errors.Is_Empty then
         VSS.Command_Line.Report_Error (Errors);
      end if;

      case Command.Subject is
         when Munin.CLI.Command_Line.Show_Priorities =>
            Print_Priorities (Context);

         when Munin.CLI.Command_Line.Show_Callgraph  =>
            Print_Call_Graph (Context);
      end case;
   end;
end Munin.CLI.Main;
