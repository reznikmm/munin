--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.Priorities;
with Munin.Program_Units;
with VSS.Strings;

package Munin.Protected_Objects is

   type Protected_Object is new Program_Units.Program_Unit with private;

   overriding
   function Qualified_Name
     (Self : Protected_Object) return VSS.Strings.Virtual_String;

   function Priority
     (Self : Protected_Object'Class) return Priorities.Optional_Priority;

   function Position
     (Self : Protected_Object'Class) return Munin.Optional_Position;
   --  The source position of the protected object's own body
   --  (Ada_Protected_Body). Unset when Self has no body of its own to
   --  point to (e.g. Self is one of several objects of the same
   --  protected type -- all such objects necessarily share their type's
   --  one compiled body).

   function Create
     (Qualified_Name : VSS.Strings.Virtual_String;
      Priority       : Priorities.Optional_Priority;
      Position       : Munin.Optional_Position) return Protected_Object;

   type Protected_Object_Array is
     array (Positive range <>) of Protected_Object;

private

   type Protected_Object is new Program_Units.Program_Unit with record
      Qualified_Name    : VSS.Strings.Virtual_String;
      Assigned_Priority : Priorities.Optional_Priority;
      Assigned_Position : Munin.Optional_Position;
   end record;

   function Create
     (Qualified_Name : VSS.Strings.Virtual_String;
      Priority       : Priorities.Optional_Priority;
      Position       : Munin.Optional_Position) return Protected_Object
   is (Qualified_Name    => Qualified_Name,
       Assigned_Priority => Priority,
       Assigned_Position => Position);

   function Priority
     (Self : Protected_Object'Class) return Priorities.Optional_Priority
   is (Self.Assigned_Priority);

   function Position
     (Self : Protected_Object'Class) return Munin.Optional_Position
   is (Self.Assigned_Position);

   overriding
   function Qualified_Name
     (Self : Protected_Object) return VSS.Strings.Virtual_String
   is (Self.Qualified_Name);

end Munin.Protected_Objects;
