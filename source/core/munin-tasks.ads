--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.Priorities;
with Munin.Program_Units;
with VSS.Strings;

package Munin.Tasks is

   type Task_Unit is new Program_Units.Program_Unit with private;

   overriding
   function Qualified_Name
     (Self : Task_Unit) return VSS.Strings.Virtual_String;

   function Priority
     (Self : Task_Unit'Class) return Priorities.Optional_Priority;

   function Position (Self : Task_Unit'Class) return Munin.Optional_Position;
   --  The source position of the task's own body (Ada_Task_Body), used to
   --  match this Task_Unit against a Call_Graph_Provider's task-root node
   --  -- exact, unlike name-based matching, since a Call_Graph_Provider's
   --  own Qualified_Name for an ordinary node is never package-qualified.
   --  Unset when Self has no body of its own to point to (e.g. Self is
   --  one of several objects of the same task type -- all such objects
   --  necessarily share their type's one compiled body).

   function Create
     (Qualified_Name : VSS.Strings.Virtual_String;
      Priority       : Priorities.Optional_Priority;
      Position       : Munin.Optional_Position) return Task_Unit;

   type Task_Unit_Array is array (Positive range <>) of Task_Unit;

private

   type Task_Unit is new Program_Units.Program_Unit with record
      Qualified_Name    : VSS.Strings.Virtual_String;
      Assigned_Priority : Priorities.Optional_Priority;
      Assigned_Position : Munin.Optional_Position;
   end record;

   function Create
     (Qualified_Name : VSS.Strings.Virtual_String;
      Priority       : Priorities.Optional_Priority;
      Position       : Munin.Optional_Position) return Task_Unit
   is (Qualified_Name    => Qualified_Name,
       Assigned_Priority => Priority,
       Assigned_Position => Position);

   function Priority
     (Self : Task_Unit'Class) return Priorities.Optional_Priority
   is (Self.Assigned_Priority);

   function Position (Self : Task_Unit'Class) return Munin.Optional_Position
   is (Self.Assigned_Position);

   function Qualified_Name (Self : Task_Unit) return VSS.Strings.Virtual_String
   is (Self.Qualified_Name);

end Munin.Tasks;
