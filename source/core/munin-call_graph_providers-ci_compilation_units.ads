--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Vectors;

with VSS.Strings;

package Munin.Call_Graph_Providers.CI_Compilation_Units is
   pragma Preelaborate;

   type Subprogram_Node (Is_External : Boolean := True) is record
      Title : VSS.Strings.Virtual_String;
      --  The subprogram's symbol, possibly annotated with the file name

      Symbol : VSS.Strings.Virtual_String;
      --  The subprogram's symbol

      Source : VSS.Strings.Virtual_String;
      --  For an internal node, its `file:line:column` declaration
      --  position; for an external one, either that same position (when
      --  known, e.g. a runtime unit compiled elsewhere) or `<built-in>`.

      Name : VSS.Strings.Virtual_String;
      --  The plain (undecorated, unqualified) subprogram name, when known

      case Is_External is
         when False =>
            Static_Stack : Natural := 0;
            --  The amount of stack used in this subprogram

            Dynamic_Objects : Natural := 0;
            --  The number of dynamic (variably-sized) objects declared in
            --  this subprogram

         when True =>
            null;
      end case;
   end record;
   --  Effectively abstract: either an internal or an external graph node.
   --  * The internal node is a subprogram declared in this compilation
   --    unit (its `.ci` file has stack usage information for it).
   --  * The external node is a subprogram called from this unit but not
   --    defined in it (declared in another `.ci` file not yet loaded, or
   --    not compiled with `-fcallgraph-info`, or a compiler-generated
   --    helper with no Ada-level identity at all).

   type Call is record
      Source : VSS.Strings.Virtual_String;
      --  The calling subprogram

      Target : VSS.Strings.Virtual_String;
      --  The called subprogram

      Label : VSS.Strings.Virtual_String;
      --  The call site's `file:line:column`, when known
   end record;
   --  Represents a call from a subprogram in this compilation unit. The
   --  target may be local (an internal node) or not (an external node).

   package Node_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Subprogram_Node);

   package Call_Vectors is new
     Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Call);

   type Compilation_Unit is tagged limited record
      Title : VSS.Strings.Virtual_String;
      --  The unit's file name

      Internal_Nodes : Node_Vectors.Vector;
      --  Subprograms declared in this unit

      External_Nodes : Node_Vectors.Vector;
      --  Subprograms called from this unit but external to it

      Edges : Call_Vectors.Vector;
      --  Calls made from this unit
   end record;
   --  The interesting content of one `.ci` file.

end Munin.Call_Graph_Providers.CI_Compilation_Units;
