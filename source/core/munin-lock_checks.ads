--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Detects a protected object called back into while a task is already
--  inside one of its own operations, reached through some other
--  subprogram rather than a direct call between two of the object's own
--  operations -- exactly the condition that deadlocks (or raises
--  Program_Error) at run time, since a protected object's lock is not
--  reentrant for a call arriving that way.
--
--  A direct call from one operation of a protected object straight to
--  another operation of the *same* object is an internal call (Ada RM
--  9.5.1) and is always safe; it is never reported, no matter how many
--  such calls chain together. Only a path that leaves the object's own
--  operations -- through an ordinary subprogram, or through an
--  operation of some *other* protected object -- and then comes back to
--  the original object is flagged.
--
--  A private subprogram declared directly among the protected object's
--  own protected_operation_items (Ada RM 9.4) -- a helper, not itself
--  part of its visible or private spec -- has the same direct
--  (unqualified-name) visibility to the object's own operations as they
--  have to each other, so a chain that passes through it is recognized
--  as internal too (see Munin.Contexts.Load_Files's Collect_Operations,
--  which attributes such a helper's own callers to the object exactly
--  as it does for a declared operation).

with Ada.Containers.Vectors;

with VSS.Strings;

with Munin.Call_Graph_Providers;

package Munin.Lock_Checks is

   use type Munin.Call_Graph_Providers.Call_Graph_Node;

   package Node_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Munin.Call_Graph_Providers.Call_Graph_Node);

   type Violation is record
      Object_Name : VSS.Strings.Virtual_String;
      --  Qualified name of the protected object called back into while
      --  already locked.

      Path : Node_Vectors.Vector;
      --  An example call chain realizing the re-entry: Path
      --  (Path.First_Index) is the real body of the operation through
      --  which Object_Name was first entered, Path (Path.Last_Index) is
      --  the re-entrant protected-operation node (Is_Protected_Operation
      --  is True for it, with the same Object_Name) -- reached, at some
      --  point along the way, through a call that left Object_Name's
      --  own operations.
   end record;

   package Violation_Vectors is new
     Ada.Containers.Vectors
       (Index_Type   => Positive,
        Element_Type => Violation);

   subtype Violation_List is Violation_Vectors.Vector;

   function Check
     (Provider : Munin.Call_Graph_Providers.Call_Graph_Provider'Class)
      return Violation_List;
   --  Every protected-operation call site reachable, considering only
   --  code reachable from Provider's Tasks and Interrupt_Handlers, from a
   --  call that left its own protected object's operations and came back
   --  to the same object -- one violation per such violating call site
   --  (regardless of how many distinct call paths reach it). Empty when
   --  no such re-entry is reachable.

end Munin.Lock_Checks;
