--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.Priorities;
with Munin.Program_Units;
with VSS.Strings;

package Munin.Tasks is

   type Task_Unit is new Program_Units.Program_Unit with private;

   overriding function Qualified_Name (Self : Task_Unit)
     return VSS.Strings.Virtual_String;

   function Priority (Self : Task_Unit'Class)
     return Priorities.Optional_Priority;

   function Create
     (Qualified_Name : VSS.Strings.Virtual_String;
      Priority       : Priorities.Optional_Priority)
      return Task_Unit;

   type Task_Unit_Array is array (Positive range <>) of Task_Unit;

private

   type Task_Unit is new Program_Units.Program_Unit with record
      Qualified_Name    : VSS.Strings.Virtual_String;
      Assigned_Priority : Priorities.Optional_Priority;
   end record;

   function Create
     (Qualified_Name : VSS.Strings.Virtual_String;
      Priority       : Priorities.Optional_Priority)
      return Task_Unit is
        (Qualified_Name    => Qualified_Name,
         Assigned_Priority => Priority);

   function Priority
     (Self : Task_Unit'Class) return Priorities.Optional_Priority is
       (Self.Assigned_Priority);

   function Qualified_Name (Self : Task_Unit) return VSS.Strings.Virtual_String
     is (Self.Qualified_Name);

end Munin.Tasks;