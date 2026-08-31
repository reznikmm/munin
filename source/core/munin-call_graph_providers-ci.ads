--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Implements Munin.Call_Graph_Providers.Call_Graph_Provider over GCC's
--  `-fcallgraph-info=su,da` `.ci` files, using the parser and in-memory
--  graph.

with GPR2.Project.Tree;

with Munin.Entry_Calls;
with Munin.Protected_Operations;
with VSS.String_Vectors;
with VSS.Strings;

with Munin.Call_Graph_Providers.CI_Databases;

package Munin.Call_Graph_Providers.CI is

   type CI_Provider is
     new Munin.Call_Graph_Providers.Call_Graph_Provider with private;

   overriding
   function Callees
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array;

   overriding
   function Callers
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array;

   overriding
   function Qualified_Name
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String;

   overriding
   function Position
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Optional_Position;

   overriding
   function Tasks
     (Self : CI_Provider)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array;

   overriding
   function Is_Entry
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Boolean;

   overriding
   function Is_Environment_Task
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Boolean;

   overriding
   function Is_Protected_Operation
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Boolean;

   overriding
   function Protected_Object_Name
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String;

   overriding
   function Image
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String;

   procedure Add_Entry
     (Self   : in out CI_Provider;
      Symbol : VSS.Strings.Virtual_String;
      Size   : Natural);
   --  See Munin.Call_Graph_Providers.CI_Databases.Add_Entry. For the
   --  future worst-case-stack feature; dormant for now.

   procedure Add_Indirect_Call_Target
     (Self   : in out CI_Provider;
      Caller : VSS.String_Vectors.Virtual_String_Vector;
      Target : VSS.Strings.Virtual_String);
   --  See Munin.Call_Graph_Providers.CI_Databases.Add_Indirect_Call_Target.
   --  For the future worst-case-stack feature; dormant for now.

   procedure Load_Extra_Data
     (Self   : in out CI_Provider;
      Path   : VSS.Strings.Virtual_String;
      Errors : out VSS.String_Vectors.Virtual_String_Vector);
   --  Read Add_Entry/Add_Indirect_Call_Target overrides from the JSON5
   --  file at Path (see Munin.Call_Graph_Providers.CI_Extra_Data). Not
   --  called automatically by Initialize -- there's no project-relative
   --  way to discover such a file.

   function Resolve
     (Self : in out CI_Provider;
      Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.CI_Databases.Resolve_Result;
   --  See Munin.Call_Graph_Providers.CI_Databases.Resolve. For the future
   --  worst-case-stack feature; dormant for now.

   function Find_CI_Files
     (Tree : GPR2.Project.Tree.Object)
      return VSS.String_Vectors.Virtual_String_Vector;
   --  `.ci` files found in the object directories of Tree's project
   --  closure (root project plus any it extends or aggregates, excluding
   --  runtime sources), one per compiled Ada source that produced one.

   procedure Initialize
     (Self                 : in out CI_Provider;
      Tree                 : GPR2.Project.Tree.Object;
      Entry_Calls          : Munin.Entry_Calls.Entry_Call_Register;
      Protected_Operations : Munin.Protected_Operations.Registry;
      Error                : out VSS.Strings.Virtual_String);
   --  Find (via Find_CI_Files) and load every `.ci` file for Tree's
   --  project closure into Self. Error is left empty on success.
   --
   --  Entry_Calls and Protected_Operations are forwarded to
   --  Munin.Call_Graph_Providers.CI_Databases.Complete -- see there for
   --  how they let a protected entry call be attributed to the entry it
   --  actually calls, and a protected operation call be attributed to the
   --  object it targets; pass empty registers to skip that resolution
   --  (every entry call is then left pointing at GNAT's generic runtime
   --  dispatcher, and no node reports Is_Protected_Operation, as in the
   --  raw `.ci` data).
   --
   --  When no `.ci` file is found at all, Error explains that the
   --  project needs to be (re)built with GCC's
   --  `-fcallgraph-info=su,da` switch and Self is left empty.
   --
   --  When at least one `.ci` file is found but every one of them fails
   --  to parse, Error reports that too and Self is left empty. A `.ci`
   --  file that fails to parse while others succeed is skipped rather
   --  than failing Initialize.

private

   type CI_Provider is new Munin.Call_Graph_Providers.Call_Graph_Provider
   with record
      DB : Munin.Call_Graph_Providers.CI_Databases.Database;
   end record;

end Munin.Call_Graph_Providers.CI;
