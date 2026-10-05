--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers;

with VSS.Strings;

package Munin.Call_Graph_Providers is
   pragma Preelaborate;

   type Call_Graph_Provider is interface;

   type Call_Graph_Provider_Access is access all Call_Graph_Provider'Class
   with Storage_Size => 0;

   type Call_Graph_Node is private;

   type Call_Graph_Node_Array is array (Positive range <>) of Call_Graph_Node;

   function Callees
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return Call_Graph_Node_Array
   is abstract;
   --  Nodes directly called from Node.

   function Callers
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return Call_Graph_Node_Array
   is abstract;
   --  Nodes that directly call Node.

   function Qualified_Name
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is abstract;
   --  Best-effort dotted Ada name for Node, or an empty string when Self
   --  cannot recover one (for example a compiler-generated node with no
   --  Ada-level identity, or a backend that only records Node's
   --  undecorated simple name).

   function Position
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return Optional_Position
   is abstract;
   --  Node's declaration position, or a position with Has_Value => False
   --  when Self has no Ada source position for Node.

   function Tasks (Self : Call_Graph_Provider) return Call_Graph_Node_Array
   is abstract;
   --  Nodes for the task bodies and the environment task (the linked
   --  program's actual entry point, calling the Ada main subprogram
   --  indirectly through gnatbind's generated bind file) known to Self,
   --  to use as roots when walking the call tree.

   function Interrupt_Handlers
     (Self : Call_Graph_Provider) return Call_Graph_Node_Array
   is abstract;
   --  Nodes for every interrupt handler procedure (see Munin.Contexts.
   --  Interrupt_Handlers) known to Self, to use as extra roots alongside
   --  Tasks when walking the call tree: the runtime invokes such a
   --  procedure directly, with no static caller of its own, exactly like
   --  a task body.

   function Is_Entry
     (Self : Call_Graph_Provider; Node : Call_Graph_Node) return Boolean
   is abstract;
   --  True when Node is a protected entry's body. A call to a protected
   --  entry cannot generally be attributed to a specific entry from the
   --  call graph alone (every entry call in a program can compile down to
   --  one shared runtime dispatcher); a provider that resolves this some
   --  other way and rewrites the graph accordingly (see
   --  Munin.Call_Graph_Providers.CI) reports the resolved node here for
   --  diagnostic purposes. Always False for a provider that does not do
   --  such a resolution.

   function Is_Environment_Task
     (Self : Call_Graph_Provider; Node : Call_Graph_Node) return Boolean
   is abstract;
   --  True iff Node is the environment task (RM 10.2) -- the linked
   --  partition's actual entry point, with no Ada-level declaration of
   --  its own. Always one of Self.Tasks; Position for it, when set,
   --  points into compiler-generated code (e.g. gnatbind's bind file),
   --  never user source.

   function Is_Protected_Operation
     (Self : Call_Graph_Provider; Node : Call_Graph_Node) return Boolean
   is abstract;
   --  True iff Node is a synthesized node produced by resolving some call
   --  site to a specific protected object -- a fact about how Node was
   --  constructed, not an independent declaration lookup. Unlike Is_Entry
   --  (a narrow, entry-dispatcher-only diagnostic, unrelated to this),
   --  this is defined uniformly for entries and ordinary protected
   --  procedures/functions alike. Node's single callee (see Callees) is
   --  always the real compiled operation body this node was resolved
   --  against.

   function Protected_Object_Name
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is abstract;
   --  The qualified name of the protected object Node was resolved to
   --  attach to. Empty whenever Is_Protected_Operation is False.

   function Image
     (Self : Call_Graph_Provider; Node : Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is abstract;
   --  Node's linker symbol or otherwise mangled unique name, as known to
   --  Self; unlike Qualified_Name, always defined for every Node.

   function Hash (Node : Call_Graph_Node) return Ada.Containers.Hash_Type;
   --  Hash for Node, so it can be used as the key of an
   --  Ada.Containers.Hashed_Maps.Map or Hashed_Sets.Set.

   function Own_Stack
     (Self : Call_Graph_Provider; Node : Call_Graph_Node) return Natural
   is abstract;
   --  Static stack used by Node's own frame, as reported by the backend; 0
   --  when unknown (see Is_Known).

   function Dynamic_Objects
     (Self : Call_Graph_Provider; Node : Call_Graph_Node) return Natural
   is abstract;
   --  Number of dynamic (heap/secondary-stack) allocations in Node's own
   --  body; 0 when unknown (see Is_Known).

   function Is_Known
     (Self : Call_Graph_Provider; Node : Call_Graph_Node) return Boolean
   is abstract;
   --  False when Self has no record of Node at all, so nothing (neither its
   --  own stack nor its callees) is known about it. True otherwise, even
   --  for a node that is only an external reference (Own_Stack is then 0).

   function Is_Indirect_Call
     (Self : Call_Graph_Provider; Node : Call_Graph_Node) return Boolean
   is abstract;
   --  True for the synthetic node representing a call through a pointer
   --  whose target is not known.

private

   type Call_Graph_Node is new Integer;

   function Hash (Node : Call_Graph_Node) return Ada.Containers.Hash_Type
   is (Ada.Containers.Hash_Type (Node));

end Munin.Call_Graph_Providers;
