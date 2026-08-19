--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings.Conversions;

with Munin.Call_Graph_Providers.CI_Parsers;

package body Munin.Call_Graph_Providers.CI_Databases is

   Indirect_Call : constant VSS.Strings.Virtual_String := "__indirect_call";
   --  GCC's placeholder target symbol for a call through a pointer, whose
   --  real target it cannot know statically.

   function "+" (Left, Right : Resolve_Result) return Resolve_Result
   is (Natural'Max (Left.Stack_Used, Right.Stack_Used),
       Left.Indirect_Calls + Right.Indirect_Calls,
       Left.Dynamic_Objects + Right.Dynamic_Objects,
       Boolean'Max (Left.Cycle, Right.Cycle));

   function Static_Stack_Of
     (Node : Munin.Call_Graph_Providers.CI_Compilation_Units.Subprogram_Node)
      return Natural
   is (if Node.Is_External then 0 else Node.Static_Stack);
   --  External nodes (never compiled with `-fcallgraph-info`, or not yet
   --  loaded) have no known stack usage; treat as 0.

   function Dynamic_Objects_Of
     (Node : Munin.Call_Graph_Providers.CI_Compilation_Units.Subprogram_Node)
      return Natural
   is (if Node.Is_External then 0 else Node.Dynamic_Objects);

   function To_Position
     (Text : VSS.Strings.Virtual_String)
      return Munin.Call_Graph_Providers.Optional_Position;
   --  Decompose a `file:line:column` string (as captured from a `.ci`
   --  label) into its parts; anything that doesn't split into exactly
   --  three ':'-separated tokens (e.g. `<built-in>`) has no position.

   procedure Register
     (Self : in out Database; Symbol : VSS.Strings.Virtual_String);
   --  Ensure Symbol has a stable node id, minting a new one the first
   --  time Symbol is seen.

   function Node_Of
     (Self : Database; Symbol : VSS.Strings.Virtual_String)
      return Munin.Call_Graph_Providers.Call_Graph_Node
   is (Munin.Call_Graph_Providers.Call_Graph_Node (Self.Ids (Symbol)));
   --  Symbol's node; Symbol must already be registered (true for every
   --  symbol appearing in Self.Edges/Reverse_Edges, all registered by
   --  Register while loading).

   function Symbol_Of
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is (Self.Symbols (Positive (Node)));

   function Known_Indirect_Call
     (Self  : Database;
      Trace : VSS.String_Vectors.Virtual_String_Vector)
      return VSS.Strings.Virtual_String;
   --  The known target for an indirect call reached through the given
   --  calling chain (innermost last), an empty (but non-null) string when
   --  that call is known to never execute, or a null string when no
   --  override was given for it at all.

   function In_Progress
     (Trace : VSS.String_Vectors.Virtual_String_Vector;
      Name  : VSS.Strings.Virtual_String) return Boolean;
   --  True when Name is already on Trace, i.e. Resolve is in the middle
   --  of computing Name's own result and has recursed back into it: a
   --  call cycle. Checking this directly (rather than relying on the
   --  Calculated flag, which can't tell "still being computed" apart
   --  from "computed and cached") is what lets Resolve detect and flag
   --  cycles without a separate pre-pass over the whole graph.

   function Resolve
     (Self  : in out Database;
      Name  : VSS.Strings.Virtual_String;
      Trace : VSS.String_Vectors.Virtual_String_Vector) return Resolve_Result;
   --  Symbol-keyed worker behind the public, Node-keyed Resolve.

   --------------
   -- Add_Entry --
   --------------

   procedure Add_Entry
     (Self   : in out Database;
      Symbol : VSS.Strings.Virtual_String;
      Size   : Natural)
   is
   begin
      Self.Top.Append ((Symbol, Size));
   end Add_Entry;

   ------------------------------
   -- Add_Indirect_Call_Target --
   ------------------------------

   procedure Add_Indirect_Call_Target
     (Self   : in out Database;
      Caller : VSS.String_Vectors.Virtual_String_Vector;
      Target : VSS.Strings.Virtual_String)
   is
      Last : constant VSS.Strings.Virtual_String := Caller.Last_Element;
   begin
      if not Self.ICT.Contains (Last) then
         Self.ICT.Insert (Last, ICT_Lists.Empty);
      end if;

      Self.ICT (Last).Append ((Caller, Target));
   end Add_Indirect_Call_Target;

   -------------
   -- Callees --
   -------------

   function Callees
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array
   is
      Symbol : constant VSS.Strings.Virtual_String := Self.Symbol_Of (Node);
   begin
      if not Self.Edges.Contains (Symbol) then
         return [];
      end if;

      return
        Result :
          Munin.Call_Graph_Providers.Call_Graph_Node_Array
            (1 .. Natural (Self.Edges (Symbol).Length))
      do
         declare
            Index : Positive := Result'First;
         begin
            for Target of Self.Edges (Symbol) loop
               Result (Index) := Self.Node_Of (Target);
               Index := Index + 1;
            end loop;
         end;
      end return;
   end Callees;

   -------------
   -- Callers --
   -------------

   function Callers
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array
   is
      Symbol : constant VSS.Strings.Virtual_String := Self.Symbol_Of (Node);
   begin
      if not Self.Reverse_Edges.Contains (Symbol) then
         return [];
      end if;

      return
        Result :
          Munin.Call_Graph_Providers.Call_Graph_Node_Array
            (1 .. Natural (Self.Reverse_Edges (Symbol).Length))
      do
         declare
            Index : Positive := Result'First;
         begin
            for Source of Self.Reverse_Edges (Symbol) loop
               Result (Index) := Self.Node_Of (Source);
               Index := Index + 1;
            end loop;
         end;
      end return;
   end Callers;

   --------------
   -- Complete --
   --------------

   procedure Complete (Self : in out Database) is
   begin
      for Cursor in Self.Edges.Iterate loop
         declare
            Source : constant VSS.Strings.Virtual_String :=
              Edge_Maps.Key (Cursor);
         begin
            for Target of Edge_Maps.Element (Cursor) loop
               if not Self.Reverse_Edges.Contains (Target) then
                  Self.Reverse_Edges.Insert (Target, String_Sets.Empty_Set);
               end if;

               Self.Reverse_Edges (Target).Include (Source);
            end loop;
         end;
      end loop;

      --  Pre-resolved placeholder node for a call through a pointer, whose
      --  real target GCC cannot know statically: contributes no stack of
      --  its own but counts as one indirect call, and is flagged as a
      --  Cycle so a stack figure that includes it reads as a lower bound.
      if not Self.Sources.Contains (Indirect_Call) then
         Self.Register (Indirect_Call);
         Self.Sources.Insert
           (Indirect_Call,
            (Node       =>
               (Is_External => True,
                Title       => Indirect_Call,
                Symbol      => Indirect_Call,
                Source      => VSS.Strings.Empty_Virtual_String,
                Name        => "Indirect Call Placeholder"),
             Result     => (0, 1, 0, True),
             Calculated => True));
      end if;
   end Complete;

   --------------
   -- Register --
   --------------

   procedure Register
     (Self : in out Database; Symbol : VSS.Strings.Virtual_String)
   is
   begin
      if not Self.Ids.Contains (Symbol) then
         Self.Symbols.Append (Symbol);
         Self.Ids.Insert (Symbol, Self.Symbols.Last_Index);
      end if;
   end Register;

   -----------
   -- Image --
   -----------

   function Image
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is (Self.Symbol_Of (Node));

   -------------------------
   -- Known_Indirect_Call --
   -------------------------

   function Known_Indirect_Call
     (Self  : Database;
      Trace : VSS.String_Vectors.Virtual_String_Vector)
      return VSS.Strings.Virtual_String
   is
      use type VSS.String_Vectors.Virtual_String_Vector;

      function Match
        (Trace, Known : VSS.String_Vectors.Virtual_String_Vector)
         return Boolean
      is (Trace.Length >= Known.Length
          and then Trace.Slice (Trace.Length - Known.Length + 1, Trace.Length)
                   = Known);

      Last : constant VSS.Strings.Virtual_String := Trace.Last_Element;
   begin
      if Self.ICT.Contains (Last) then
         for Item of Self.ICT (Last) loop
            if Match (Trace, Item.Caller) then
               return Item.Target;
            end if;
         end loop;
      end if;

      return VSS.Strings.Empty_Virtual_String;
   end Known_Indirect_Call;

   -----------------
   -- In_Progress --
   -----------------

   function In_Progress
     (Trace : VSS.String_Vectors.Virtual_String_Vector;
      Name  : VSS.Strings.Virtual_String) return Boolean
   is
   begin
      for Item of Trace loop
         if Item = Name then
            return True;
         end if;
      end loop;

      return False;
   end In_Progress;

   ----------
   -- Load --
   ----------

   procedure Load
     (Self    : in out Database;
      Stream  : in out VSS.Text_Streams.Input_Text_Stream'Class;
      Error   : out VSS.Strings.Virtual_String;
      Warning : out VSS.String_Vectors.Virtual_String_Vector)
   is
      Unit : Munin.Call_Graph_Providers.CI_Compilation_Units.Compilation_Unit;
   begin
      Warning.Clear;
      Munin.Call_Graph_Providers.CI_Parsers.Parse (Stream, Unit, Error);

      if not Error.Is_Empty then
         return;
      end if;

      for Node of Unit.Internal_Nodes loop
         Self.Register (Node.Symbol);

         if not Self.Sources.Contains (Node.Symbol) then
            Self.Sources.Insert (Node.Symbol, (Node => Node, others => <>));
         elsif Self.Sources (Node.Symbol).Node.Is_External then
            --  Node.Symbol was seen earlier only as another unit's
            --  external reference (a forward reference to a `.ci` file
            --  not yet loaded at the time); its real definition, with
            --  actual stack usage information, now arrives -- replace
            --  the placeholder rather than treating this as a conflict.
            Self.Sources (Node.Symbol).Node := Node;
         else
            Warning.Append ("Duplicate subprogram: " & Node.Symbol);
         end if;
      end loop;

      for Node of Unit.External_Nodes loop
         Self.Register (Node.Symbol);

         if not Self.Sources.Contains (Node.Symbol) then
            Self.Sources.Insert (Node.Symbol, (Node => Node, others => <>));
         end if;
      end loop;

      for Edge of Unit.Edges loop
         Self.Register (Edge.Source);
         Self.Register (Edge.Target);

         if Self.Edges.Contains (Edge.Source) then
            Self.Edges (Edge.Source).Include (Edge.Target);
         else
            Self.Edges.Insert (Edge.Source, [Edge.Target]);
         end if;
      end loop;
   end Load;

   --------------------
   -- Qualified_Name --
   --------------------

   function Qualified_Name
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is
      Symbol : constant VSS.Strings.Virtual_String := Self.Symbol_Of (Node);
   begin
      return
        (if Self.Sources.Contains (Symbol)
         then Self.Sources (Symbol).Node.Name
         else VSS.Strings.Empty_Virtual_String);
   end Qualified_Name;

   --------------
   -- Position --
   --------------

   function Position
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Optional_Position
   is
      Symbol : constant VSS.Strings.Virtual_String := Self.Symbol_Of (Node);
   begin
      return
        (if Self.Sources.Contains (Symbol)
         then To_Position (Self.Sources (Symbol).Node.Source)
         else (Is_Set => False));
   end Position;

   -------------
   -- Resolve --
   -------------

   function Resolve
     (Self : in out Database;
      Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Resolve_Result
   is
   begin
      return
        Self.Resolve
          (Self.Symbol_Of (Node),
           VSS.String_Vectors.Empty_Virtual_String_Vector);
   end Resolve;

   function Resolve
     (Self  : in out Database;
      Name  : VSS.Strings.Virtual_String;
      Trace : VSS.String_Vectors.Virtual_String_Vector) return Resolve_Result
   is
      Result : Resolve_Result;
      Next   : VSS.String_Vectors.Virtual_String_Vector;
   begin
      if In_Progress (Trace, Name) then
         --  Recursed back into a node still being resolved: a call cycle.
         --  Its own stack contribution isn't known yet (that's what this
         --  very call chain is computing), so contribute nothing but flag
         --  Cycle; this does not touch Self.Sources(Name), which the
         --  in-progress outer call is still in the middle of computing.
         return
           (Stack_Used      => 0,
            Indirect_Calls  => 0,
            Dynamic_Objects => 0,
            Cycle           => True);
      end if;

      if not Self.Sources.Contains (Name) then
         Self.Sources.Insert
           (Name,
            (Node       =>
               (Is_External => True,
                Title       => Name,
                Symbol      => Name,
                Source      => VSS.Strings.Empty_Virtual_String,
                Name        => VSS.Strings.Empty_Virtual_String),
             Result     => (0, 0, 0, True),
             Calculated => True));

      elsif Name = Indirect_Call then
         declare
            Target : constant VSS.Strings.Virtual_String :=
              Self.Known_Indirect_Call (Trace);
         begin
            if not Target.Is_Empty then
               return Self.Resolve (Target, Trace);
            elsif not Target.Is_Null then
               --  Empty, but not null: this indirect call is known never
               --  to execute.
               return Result;
            end if;

            --  Null: no override was given; fall through to the
            --  pre-resolved __indirect_call placeholder set up by
            --  Complete.
         end;
      end if;

      if Self.Sources (Name).Calculated then
         return Self.Sources (Name).Result;
      end if;

      Self.Sources (Name).Calculated := True;
      Next := Trace;
      Next.Append (Name);

      Result :=
        (Stack_Used      => 0,
         Indirect_Calls  => 0,
         Dynamic_Objects => Dynamic_Objects_Of (Self.Sources (Name).Node),
         Cycle           => False);

      if Self.Edges.Contains (Name) then
         for Target of Self.Edges (Name) loop
            Result := @ + Self.Resolve (Target, Next);
         end loop;
      end if;

      Result.Stack_Used := @ + Static_Stack_Of (Self.Sources (Name).Node);
      Self.Sources (Name).Result := Result;

      return Result;
   end Resolve;

   -----------
   -- Tasks --
   -----------

   function Tasks
     (Self : Database)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array
   is
      function Is_Task_Or_Main
        (Symbol : VSS.Strings.Virtual_String) return Boolean;
      --  True for a symbol matching GNAT's mangling for a task body, or
      --  for "main" -- the environment task, exported by gnatbind's
      --  generated bind file under that fixed C link name regardless of
      --  the actual main subprogram's own name.

      function Is_Task_Or_Main
        (Symbol : VSS.Strings.Virtual_String) return Boolean
      is
         Text : constant String :=
           VSS.Strings.Conversions.To_UTF_8_String (Symbol);
      begin
         return
           (Text'Length >= 3
            and then Text (Text'Last - 2 .. Text'Last) = "TKB")
           or else Text = "main";
      end Is_Task_Or_Main;

      Count : Natural := 0;
   begin
      for Symbol of Self.Symbols loop
         if Is_Task_Or_Main (Symbol) then
            Count := Count + 1;
         end if;
      end loop;

      return
        Result : Munin.Call_Graph_Providers.Call_Graph_Node_Array (1 .. Count)
      do
         declare
            Index : Positive := Result'First;
         begin
            for Symbol of Self.Symbols loop
               if Is_Task_Or_Main (Symbol) then
                  Result (Index) := Self.Node_Of (Symbol);
                  Index := Index + 1;
               end if;
            end loop;
         end;
      end return;
   end Tasks;

   -----------------
   -- To_Position --
   -----------------

   function To_Position
     (Text : VSS.Strings.Virtual_String)
      return Munin.Call_Graph_Providers.Optional_Position
   is
      Parts : constant VSS.String_Vectors.Virtual_String_Vector :=
        Text.Split (':');
   begin
      if Parts.Length /= 3 then
         return (Is_Set => False);
      end if;

      return
        (Is_Set => True,
         File   => Parts.Element (1),
         Line   =>
           Positive'Wide_Wide_Value
             (VSS.Strings.Conversions.To_Wide_Wide_String
                (Parts.Element (2))),
         Column =>
           Positive'Wide_Wide_Value
             (VSS.Strings.Conversions.To_Wide_Wide_String
                (Parts.Element (3))));
   end To_Position;

end Munin.Call_Graph_Providers.CI_Databases;
