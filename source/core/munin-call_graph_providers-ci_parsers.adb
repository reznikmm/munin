--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Characters.Latin;
with VSS.Characters;
with VSS.Regular_Expressions;
with VSS.Strings.Conversions;

package body Munin.Call_Graph_Providers.CI_Parsers is

   use type VSS.Strings.Virtual_String;

   Internal_Matcher : constant VSS.Regular_Expressions.Regular_Expression :=
     VSS.Regular_Expressions.To_Regular_Expression
       ("^(\S+)\\n([^\n]*)\\n(\d+)[^\n]*\\n(\d+)");
   --  Matcher for the 'label' of an internal node (a subprogram in this CI
   --  file): plain name, source position, static stack size, dynamic
   --  object count.

   External_Matcher : constant VSS.Regular_Expressions.Regular_Expression :=
     VSS.Regular_Expressions.To_Regular_Expression ("(\S+)\\n([^\n]*)");
   --  Matcher for the 'label' of an external node (a subprogram not in
   --  this CI file): plain name, source position (or `<built-in>`).

   Indirect_Call_Placeholder : constant VSS.Strings.Virtual_String :=
     "Indirect Call Placeholder";

   function Tail
     (Value : VSS.Strings.Virtual_String) return VSS.Strings.Virtual_String
   is (Value.Split (':').Last_Element);
   --  Return tail of string after ':' or whole string if there is no ':'

   type Token_Kind is
     (CLASS,
      CLASSNAME,
      CLOSE_BRACE,
      COLON,
      EDGE,
      ELLIPSE,
      GRAPH,
      LABEL,
      NODE,
      OPEN_BRACE,
      PARENT,
      SHAPE,
      SOURCENAME,
      STRING,
      TARGETNAME,
      TITLE,
      VIRTUALS,
      ERROR,
      EOF);

   type Parser_State is limited record
      Stream  : access VSS.Text_Streams.Input_Text_Stream'Class;
      Success : Boolean;
      Error   : VSS.Strings.Virtual_String;
      String  : VSS.Strings.Virtual_String;
      Token   : Token_Kind;
      --  Next token in the stream
      Char    : VSS.Characters.Virtual_Character;
      --  Next character after the next token in the stream (if Token /=
      --  EOF)
   end record;

   procedure Expect_Token (Self : in out Parser_State; Token : Token_Kind);

   procedure Expect_String
     (Self : in out Parser_State; Value : Wide_Wide_String);

   procedure Parse_Start
     (Self : in out Parser_State;
      Unit : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                      .Compilation_Unit);
   --  start \
   --      : GRAPH COLON OPEN_BRACE title graph_contents CLOSE_BRACE
   --      | GRAPH COLON OPEN_BRACE title CLOSE_BRACE

   procedure Parse_Title
     (Self : in out Parser_State; Value : out VSS.Strings.Virtual_String);
   --  title : TITLE COLON STRING

   procedure Parse_Graph_Contents
     (Self : in out Parser_State;
      Unit : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                      .Compilation_Unit);
   --  graph_contents \
   --      : graph_item graph_contents
   --      | graph_item

   procedure Parse_Graph_Item
     (Self : in out Parser_State;
      Unit : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                      .Compilation_Unit);
   --  graph_item \
   --      : class
   --      | node
   --      | edge

   procedure Parse_Class (Self : in out Parser_State);
   --  class \
   --      : CLASS OPEN_BRACE \
   --        CLASSNAME COLON STRING \
   --        LABEL COLON STRING \
   --        PARENT COLON STRING \
   --        VIRTUALS COLON STRING \
   --        CLOSE_BRACE

   procedure Parse_Node
     (Self  : in out Parser_State;
      Value : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                       .Subprogram_Node);
   --  node : NODE COLON OPEN_BRACE title node_content CLOSE_BRACE

   procedure Parse_Node_Content
     (Self  : in out Parser_State;
      Value : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                       .Subprogram_Node);
   --  node_content \
   --      : internal_node
   --      | external_node
   --
   --  internal_node : LABEL COLON STRING
   --
   --  external_node : LABEL COLON STRING SHAPE COLON ELLIPSE

   procedure Parse_Edge
     (Self  : in out Parser_State;
      Value : in out Munin.Call_Graph_Providers.CI_Compilation_Units.Call);
   --  edge \
   --      : EDGE COLON OPEN_BRACE \
   --        SOURCENAME COLON STRING \
   --        TARGETNAME COLON STRING \
   --        LABEL COLON STRING \
   --        CLOSE_BRACE
   --      | EDGE COLON OPEN_BRACE \
   --        SOURCENAME COLON STRING \
   --        TARGETNAME COLON STRING \
   --        CLOSE_BRACE

   -----------
   -- Parse --
   -----------

   procedure Parse
     (Stream : in out VSS.Text_Streams.Input_Text_Stream'Class;
      Unit   : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                        .Compilation_Unit;
      Error  : out VSS.Strings.Virtual_String)
   is
      State : Parser_State :=
        (Stream  => Stream'Unchecked_Access,
         String  => VSS.Strings.Empty_Virtual_String,
         Error   => VSS.Strings.Empty_Virtual_String,
         Success => True,
         Char    => <>,
         Token   => EOF);
   begin
      if Stream.Is_End_Of_Stream then
         Error := "Empty `.ci` file";
         return;
      end if;

      Expect_Token (State, State.Token);
      Parse_Start (State, Unit);

      if State.Success and then State.Token /= EOF then
         Error := "Unexpected token: ";
         Error.Append
           (VSS.Strings.Conversions.To_Virtual_String (State.Token'Image));
      else
         Error := State.Error;
      end if;
   end Parse;

   -------------------
   -- Expect_String --
   -------------------

   procedure Expect_String
     (Self : in out Parser_State; Value : Wide_Wide_String)
   is
      Ok : Boolean renames Self.Success;
   begin
      for Char of Value loop
         if Wide_Wide_Character (Self.Char) /= Char then
            Ok := False;
         end if;

         exit when not Ok;

         if Self.Stream.Is_End_Of_Stream then
            Self.Char := VSS.Characters.Virtual_Character'First_Valid;
         else
            Self.Stream.Get (Self.Char, Ok);
         end if;
      end loop;
   end Expect_String;

   ------------------
   -- Expect_Token --
   ------------------

   procedure Expect_Token (Self : in out Parser_State; Token : Token_Kind) is
      use type VSS.Characters.Virtual_Character;

      Ok   : Boolean renames Self.Success;
      Done : Boolean := True;

      function Char return Wide_Wide_String
      is [Wide_Wide_Character (Self.Char)];

   begin
      if not Ok then
         return;

      elsif Self.Token /= Token then
         Self.Error :=
           "Expected token not found: "
           & VSS.Strings.Conversions.To_Virtual_String (Token'Image);

         Ok := False;
         return;

      elsif Self.Token = EOF then
         Self.Stream.Get (Self.Char, Ok);

         if not Ok then
            return;
         end if;
      end if;

      while Self.Char in ' ' | VSS.Characters.Latin.Line_Feed loop
         Self.Stream.Get (Self.Char, Done);

         if not Done then
            Self.Success := not Self.Stream.Has_Error;
            Self.Error := Self.Stream.Error_Message;
            Self.Token := (if Self.Success then EOF else ERROR);

            return;
         end if;
      end loop;

      case Self.Char is
         when '}' =>
            Expect_String (Self, Char);
            Self.Token := CLOSE_BRACE;

         when '{' =>
            Expect_String (Self, Char);
            Self.Token := OPEN_BRACE;

         when ':' =>
            Expect_String (Self, Char);
            Self.Token := COLON;

         when 'c' =>
            Expect_String (Self, "class");
            Self.Token := CLASS;

            if Ok and then Self.Char = 'n' then
               Expect_String (Self, "name");
               Self.Token := CLASSNAME;
            end if;

         when 'e' =>
            Expect_String (Self, Char);

            if Self.Char = 'd' then
               Expect_String (Self, "dge");
               Self.Token := EDGE;
            else
               Expect_String (Self, "llipse");
               Self.Token := ELLIPSE;
            end if;

         when 'g' =>
            Expect_String (Self, "graph");
            Self.Token := GRAPH;

         when 'l' =>
            Expect_String (Self, "label");
            Self.Token := LABEL;

         when 'n' =>
            Expect_String (Self, "node");
            Self.Token := NODE;

         when 'p' =>
            Expect_String (Self, "parent");
            Self.Token := PARENT;

         when 's' =>
            Expect_String (Self, Char);

            if Self.Char = 'h' then
               Expect_String (Self, "hape");
               Self.Token := SHAPE;
            else
               Expect_String (Self, "ourcename");
               Self.Token := SOURCENAME;
            end if;

         when 't' =>
            Expect_String (Self, Char);

            if Self.Char = 'a' then
               Expect_String (Self, "argetname");
               Self.Token := TARGETNAME;
            else
               Expect_String (Self, "itle");
               Self.Token := TITLE;
            end if;

         when 'v' =>
            Expect_String (Self, "virtuals");
            Self.Token := VIRTUALS;

         when '"' =>
            Expect_String (Self, Char);
            Self.Token := STRING;
            Self.String.Clear;

            while Ok and then Self.Char /= '"' loop
               Self.String.Append (Self.Char);
               Expect_String (Self, Char);
            end loop;

            if Ok and then Self.Char = '"' then
               Expect_String (Self, Char);
            end if;

         when others =>
            Self.Error := "Unexpected character: " & Self.Char;
            Self.Token := ERROR;
      end case;
   end Expect_Token;

   -----------------
   -- Parse_Class --
   -----------------

   procedure Parse_Class (Self : in out Parser_State) is
   begin
      Expect_Token (Self, CLASS);
      Expect_Token (Self, OPEN_BRACE);
      Expect_Token (Self, CLASSNAME);
      Expect_Token (Self, COLON);
      Expect_Token (Self, STRING);
      Expect_Token (Self, LABEL);
      Expect_Token (Self, COLON);
      Expect_Token (Self, STRING);
      Expect_Token (Self, PARENT);
      Expect_Token (Self, COLON);
      Expect_Token (Self, STRING);
      Expect_Token (Self, VIRTUALS);
      Expect_Token (Self, COLON);
      Expect_Token (Self, STRING);
      Expect_Token (Self, CLOSE_BRACE);
   end Parse_Class;

   ----------------
   -- Parse_Edge --
   ----------------

   procedure Parse_Edge
     (Self  : in out Parser_State;
      Value : in out Munin.Call_Graph_Providers.CI_Compilation_Units.Call)
   is
   begin
      Expect_Token (Self, EDGE);
      Expect_Token (Self, COLON);
      Expect_Token (Self, OPEN_BRACE);
      Expect_Token (Self, SOURCENAME);
      Expect_Token (Self, COLON);
      Expect_Token (Self, STRING);
      Value.Source := Tail (Self.String);
      --  for Ada sources, 'sourcename' is sometimes filename:source

      Expect_Token (Self, TARGETNAME);
      Expect_Token (Self, COLON);
      Expect_Token (Self, STRING);
      Value.Target := Tail (Self.String);
      --  for targets in this C source file, 'targetname' is
      --  filename:target

      if Self.Token = LABEL then
         Expect_Token (Self, LABEL);
         Expect_Token (Self, COLON);
         Expect_Token (Self, STRING);
         Value.Label := Self.String;
      end if;

      Expect_Token (Self, CLOSE_BRACE);
   end Parse_Edge;

   --------------------------
   -- Parse_Graph_Contents --
   --------------------------

   procedure Parse_Graph_Contents
     (Self : in out Parser_State;
      Unit : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                      .Compilation_Unit)
   is
   begin
      while Self.Success loop
         Parse_Graph_Item (Self, Unit);

         exit when Self.Token not in CLASS | NODE | EDGE;
      end loop;
   end Parse_Graph_Contents;

   ----------------------
   -- Parse_Graph_Item --
   ----------------------

   procedure Parse_Graph_Item
     (Self : in out Parser_State;
      Unit : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                      .Compilation_Unit)
   is
   begin
      case Self.Token is
         when CLASS =>
            Parse_Class (Self);  --  class, ignored

         when NODE =>
            declare
               Node : Munin.Call_Graph_Providers.CI_Compilation_Units
                        .Subprogram_Node;
            begin
               Parse_Node (Self, Node);

               if Node.Is_External then
                  Unit.External_Nodes.Append (Node);
               else
                  Unit.Internal_Nodes.Append (Node);
               end if;
            end;

         when EDGE =>
            declare
               Edge : Munin.Call_Graph_Providers.CI_Compilation_Units.Call;
            begin
               Parse_Edge (Self, Edge);
               Unit.Edges.Append (Edge);
            end;

         when others =>
            Self.Success := False;
      end case;
   end Parse_Graph_Item;

   ----------------
   -- Parse_Node --
   ----------------

   procedure Parse_Node
     (Self  : in out Parser_State;
      Value : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                       .Subprogram_Node)
   is
   begin
      Expect_Token (Self, NODE);
      Expect_Token (Self, COLON);
      Expect_Token (Self, OPEN_BRACE);
      Parse_Title (Self, Value.Title);
      Value.Symbol := Tail (Value.Title);

      Parse_Node_Content (Self, Value);
      Expect_Token (Self, CLOSE_BRACE);
   end Parse_Node;

   ------------------------
   -- Parse_Node_Content --
   ------------------------

   procedure Parse_Node_Content
     (Self  : in out Parser_State;
      Value : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                       .Subprogram_Node)
   is
      function To_Int (Text : VSS.Strings.Virtual_String) return Natural
      is (Natural'Wide_Wide_Value
            (VSS.Strings.Conversions.To_Wide_Wide_String (Text)));

      Content : VSS.Strings.Virtual_String;
      Match   : VSS.Regular_Expressions.Regular_Expression_Match;
   begin
      Expect_Token (Self, LABEL);
      Expect_Token (Self, COLON);
      Expect_Token (Self, STRING);
      Content := Self.String;

      if Content = Indirect_Call_Placeholder then
         Value.Name := Indirect_Call_Placeholder;
         Value.Source := VSS.Strings.Empty_Virtual_String;
         Expect_Token (Self, SHAPE);
         Expect_Token (Self, COLON);
         Expect_Token (Self, ELLIPSE);

      elsif Self.Token = SHAPE then  --  external node
         Expect_Token (Self, SHAPE);
         Expect_Token (Self, COLON);
         Expect_Token (Self, ELLIPSE);

         Match :=
           External_Matcher.Match
             (Content,
              Options =>
                [VSS.Regular_Expressions.Anchored_Match => True]);

         if not Match.Has_Match then
            raise Program_Error
              with VSS.Strings.Conversions.To_UTF_8_String (Content);
         end if;

         Value.Name := Match.Captured (1);
         Value.Source := Match.Captured (2);

      else  --  internal node
         Match := Internal_Matcher.Match (Content);

         if not Match.Has_Match then
            raise Program_Error;
         end if;

         Value :=
           (Is_External     => False,
            Title           => Value.Title,
            Symbol          => Value.Symbol,
            Name            => Match.Captured (1),
            Source          => Match.Captured (2),
            Static_Stack    => To_Int (Match.Captured (3)),
            Dynamic_Objects => To_Int (Match.Captured (4)));
      end if;
   end Parse_Node_Content;

   -----------------
   -- Parse_Start --
   -----------------

   procedure Parse_Start
     (Self : in out Parser_State;
      Unit : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                      .Compilation_Unit)
   is
   begin
      Expect_Token (Self, GRAPH);
      Expect_Token (Self, COLON);
      Expect_Token (Self, OPEN_BRACE);
      Parse_Title (Self, Unit.Title);

      if Self.Token = CLOSE_BRACE then
         Expect_Token (Self, CLOSE_BRACE);
      else
         Parse_Graph_Contents (Self, Unit);
         Expect_Token (Self, CLOSE_BRACE);
      end if;
   end Parse_Start;

   -----------------
   -- Parse_Title --
   -----------------

   procedure Parse_Title
     (Self : in out Parser_State; Value : out VSS.Strings.Virtual_String)
   is
   begin
      Expect_Token (Self, TITLE);
      Expect_Token (Self, COLON);
      Expect_Token (Self, STRING);
      Value := Self.String;
   end Parse_Title;

end Munin.Call_Graph_Providers.CI_Parsers;
