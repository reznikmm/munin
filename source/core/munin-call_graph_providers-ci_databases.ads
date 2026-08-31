--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Doubly_Linked_Lists;
with Ada.Containers.Hashed_Maps;
with Ada.Containers.Hashed_Sets;
with Ada.Containers.Vectors;

with Munin.Entry_Calls;
with Munin.Protected_Operations;
with VSS.String_Vectors;
with VSS.Strings.Hash;
with VSS.Text_Streams;

with Munin.Call_Graph_Providers.CI_Compilation_Units;

package Munin.Call_Graph_Providers.CI_Databases is

   type Database is tagged private;
   --  The in-memory call graph assembled from one or more `.ci` files:
   --  every subprogram (node) seen, either as a `.ci` file's own
   --  subprogram or as the target of a call from one, and every call
   --  (edge) between them.

   procedure Load
     (Self    : in out Database;
      Stream  : in out VSS.Text_Streams.Input_Text_Stream'Class;
      Error   : out VSS.Strings.Virtual_String;
      Warning : out VSS.String_Vectors.Virtual_String_Vector);
   --  Parse Stream as one `.ci` file and merge its nodes/edges into Self.
   --  Warning collects non-fatal issues (e.g. a symbol declared more than
   --  once, in more than one loaded `.ci` file); Error is set only when
   --  Stream could not be parsed as a `.ci` file at all.

   procedure Complete
     (Self                 : in out Database;
      Entry_Calls          : Munin.Entry_Calls.Entry_Call_Register;
      Protected_Operations : Munin.Protected_Operations.Registry);
   --  Fold every edge parsed by Load into Self's queryable Callees/Callers
   --  graph (deferred until now, rather than done per-file by Load, so
   --  that two distinct entry calls from the same caller -- otherwise
   --  indistinguishable once folded, see below -- can still be told apart
   --  by their call-site position), then build the reverse-edge index
   --  needed by Callers. Call once after all `.ci` files (and any extra
   --  data) have been loaded into Self.
   --
   --  An edge that targets GNAT's generic protected-entry-call runtime
   --  dispatcher -- the same shared node for every entry call in a
   --  program, since the actual entry reached is a runtime-only decision
   --  invisible to the static call graph -- has its target resolved via
   --  Entry_Call_Targets instead: the call-site position captured for the
   --  edge is looked up in Entry_Call_Targets to find the real target
   --  entry body's own position, which is then matched against an
   --  internal node already present in Self (from the same `.ci` file) at
   --  that position. An edge whose call-site position isn't in
   --  Entry_Call_Targets, or whose resolved position matches no known
   --  node, is left pointing at the generic dispatcher.
   --
   --  Once that resolution is done, an edge whose call-site position
   --  Protected_Operations attributes to a specific protected object is
   --  redirected once more, to a node synthesized for that (object,
   --  target) pair -- see Is_Protected_Operation/Protected_Object_Name.
   --  That synthesized node's own (and only) callee is the original
   --  target, so Callees needs no special-casing for it at all.

   function Is_Entry
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Boolean;
   --  True for exactly the nodes Complete resolved an entry-call edge to.

   function Is_Environment_Task
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Boolean;
   --  True for exactly the node Tasks reports for gnatbind's fixed "main"
   --  link name.

   function Is_Protected_Operation
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Boolean;
   --  True for exactly the nodes Complete synthesized by attributing a
   --  call site to a specific protected object.

   function Protected_Object_Name
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String;
   --  The qualified name Node was synthesized for, or an empty string when
   --  Is_Protected_Operation (Self, Node) is False.

   function Callees
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array;

   function Callers
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array;

   function Qualified_Name
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String;
   --  The plain (undecorated) subprogram name captured from the `.ci`
   --  label, or an empty string when Node has none (a compiler-generated
   --  node with no Ada-level identity, or one never described by any
   --  loaded `.ci` file).

   function Position
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Optional_Position;

   function Image
     (Self : Database; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String;
   --  Node's symbol, always defined.

   function Tasks
     (Self : Database) return Munin.Call_Graph_Providers.Call_Graph_Node_Array;
   --  Nodes whose symbol matches GNAT's mangling for a task body (a
   --  `TKB`-suffixed segment), or is exactly `main` -- the environment
   --  task, exported under that fixed C link name by gnatbind's
   --  generated bind file regardless of the actual main subprogram's own
   --  name. A heuristic tied to GNAT's current mangling and binding
   --  convention -- `.ci` carries no explicit "this is a task" tag -- not
   --  a guaranteed-stable contract.

   procedure Add_Entry
     (Self   : in out Database;
      Symbol : VSS.Strings.Virtual_String;
      Size   : Natural);
   --  Record Symbol as a top-level entry (task body, main subprogram)
   --  with a stack budget of Size. For the future worst-case-stack
   --  feature; dormant for now.

   procedure Add_Indirect_Call_Target
     (Self   : in out Database;
      Caller : VSS.String_Vectors.Virtual_String_Vector;
      Target : VSS.Strings.Virtual_String);
   --  Record a known target for an indirect call, identified by the chain
   --  of calling symbols that leads to it (innermost last); an empty but
   --  non-null Target means the call is known to never execute. For the
   --  future worst-case-stack feature; dormant for now.

   type Resolve_Result is record
      Stack_Used      : Natural := 0;
      Indirect_Calls  : Natural := 0;
      Dynamic_Objects : Natural := 0;
      Cycle           : Boolean := False;
   end record;

   function Resolve
     (Self : in out Database;
      Node : Munin.Call_Graph_Providers.Call_Graph_Node) return Resolve_Result;
   --  Worst-case stack usage rooted at Node: its own static stack plus the
   --  maximum over all of its (recursively resolved) callees. Cycle is
   --  set when Node's call graph is (or reaches) a recursive cycle, in
   --  which case Stack_Used is a lower bound, not the true worst case.
   --  For the future worst-case-stack feature; dormant for now (nothing
   --  calls this yet).

private

   use type VSS.Strings.Virtual_String;

   type Node_Record is record
      Node : Munin.Call_Graph_Providers.CI_Compilation_Units.Subprogram_Node;

      Result     : Resolve_Result;
      Calculated : Boolean := False;
   end record;

   package Node_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => VSS.Strings.Virtual_String,
        Element_Type    => Node_Record,
        Hash            => VSS.Strings.Hash,
        Equivalent_Keys => VSS.Strings."=");

   package String_Sets is new
     Ada.Containers.Hashed_Sets
       (VSS.Strings.Virtual_String,
        VSS.Strings.Hash,
        VSS.Strings."=",
        VSS.Strings."=");

   package Edge_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => VSS.Strings.Virtual_String,
        Element_Type    => String_Sets.Set,
        Hash            => VSS.Strings.Hash,
        Equivalent_Keys => VSS.Strings."=",
        "="             => String_Sets."=");

   package Owner_Name_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => VSS.Strings.Virtual_String,
        Element_Type    => VSS.Strings.Virtual_String,
        Hash            => VSS.Strings.Hash,
        Equivalent_Keys => VSS.Strings."=",
        "="             => VSS.Strings."=");

   type Top_Entry is record
      Symbol : VSS.Strings.Virtual_String;
      Size   : Natural;
   end record;

   package Top_Entry_Lists is new
     Ada.Containers.Doubly_Linked_Lists (Top_Entry);

   type Indirect_Call_Target is record
      Caller : VSS.String_Vectors.Virtual_String_Vector;
      Target : VSS.Strings.Virtual_String;
   end record;

   package ICT_Lists is new
     Ada.Containers.Doubly_Linked_Lists (Indirect_Call_Target);

   package ICT_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => VSS.Strings.Virtual_String,
        Element_Type    => ICT_Lists.List,
        Hash            => VSS.Strings.Hash,
        Equivalent_Keys => VSS.Strings."=",
        "="             => ICT_Lists."=");

   --  Node identity: every symbol seen (as a node's own symbol, or as an
   --  edge endpoint) gets a stable Positive index the first time it's
   --  seen, and Call_Graph_Node is that index -- new relative to the
   --  ported original, which never needed a handle distinct from the
   --  symbol string itself.

   package Symbol_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => VSS.Strings.Virtual_String);

   package Symbol_Ids is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => VSS.Strings.Virtual_String,
        Element_Type    => Positive,
        Hash            => VSS.Strings.Hash,
        Equivalent_Keys => VSS.Strings."=");

   type Database is tagged record
      Sources : Node_Maps.Map;
      --  Every node seen, keyed by symbol: internal ones carry stack
      --  usage information, external ones carry whatever name/position
      --  the `.ci` label recorded (possibly none, e.g. `<built-in>`).

      Pending_Edges :
        Munin.Call_Graph_Providers.CI_Compilation_Units.Call_Vectors.Vector;
      --  Every edge parsed by Load, not yet folded into Edges/
      --  Reverse_Edges; folded (and cleared implicitly by not being
      --  consulted again) by Complete, which needs each edge's own
      --  call-site position (Call.Label) still distinguishable per call
      --  site -- lost once folded into Edges' per-caller callee Set.

      Edges : Edge_Maps.Map;
      --  Forward call edges: {caller symbol -> {callee symbols}}

      Reverse_Edges : Edge_Maps.Map;
      --  Reverse call edges: {callee symbol -> {caller symbols}}. Built by
      --  Complete; new relative to the ported original, which never
      --  needed to walk edges backwards.

      ICT : ICT_Maps.Map;
      --  Indirect call targets, grouped by the last (innermost) symbol in
      --  their calling chain.

      Top : Top_Entry_Lists.List;
      --  Top-level entries (task bodies, main subprogram, ...) with a
      --  stack budget.

      Symbols : Symbol_Vectors.Vector;
      Ids     : Symbol_Ids.Map;

      Entry_Nodes : String_Sets.Set;
      --  Symbols Complete resolved an entry-call edge to; see Is_Entry.

      Protected_Operation_Nodes : String_Sets.Set;
      --  Symbols Complete synthesized by attributing a call site to a
      --  specific protected object -- always a synthesized node, never a
      --  raw `.ci` symbol; see Is_Protected_Operation.

      Owner_Names : Owner_Name_Maps.Map;
      --  Protected_Operation_Nodes member -> the qualified name of the
      --  protected object it was synthesized for; see
      --  Protected_Object_Name.
   end record;

end Munin.Call_Graph_Providers.CI_Databases;
