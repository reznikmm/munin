--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.Program_Units;
with VSS.Strings;

package Munin.Interrupt_Handlers is

   type Interrupt_Handler is new Program_Units.Program_Unit with private;

   overriding
   function Qualified_Name
     (Self : Interrupt_Handler) return VSS.Strings.Virtual_String;

   function Protected_Object
     (Self : Interrupt_Handler'Class) return VSS.Strings.Virtual_String;
   --  The qualified name of the protected object Self is declared in --
   --  the object whose Interrupt_Priority (Munin.Contexts.
   --  Protected_Object_Ceiling) Self actually runs at, per Ada RM C.3.1.

   function Position
     (Self : Interrupt_Handler'Class) return Munin.Optional_Position;
   --  The source position of Self's own body (Ada_Subp_Body), used to
   --  match this Interrupt_Handler against a Call_Graph_Provider's node --
   --  see Munin.Tasks.Position for why a position, not a name, is used
   --  for that match.

   function Create
     (Qualified_Name   : VSS.Strings.Virtual_String;
      Protected_Object : VSS.Strings.Virtual_String;
      Position         : Munin.Optional_Position) return Interrupt_Handler;

   type Interrupt_Handler_Array is
     array (Positive range <>) of Interrupt_Handler;

private

   type Interrupt_Handler is new Program_Units.Program_Unit with record
      Qualified_Name    : VSS.Strings.Virtual_String;
      Owner             : VSS.Strings.Virtual_String;
      Assigned_Position : Munin.Optional_Position;
   end record;

   function Create
     (Qualified_Name   : VSS.Strings.Virtual_String;
      Protected_Object : VSS.Strings.Virtual_String;
      Position         : Munin.Optional_Position) return Interrupt_Handler
   is (Qualified_Name    => Qualified_Name,
       Owner             => Protected_Object,
       Assigned_Position => Position);

   function Protected_Object
     (Self : Interrupt_Handler'Class) return VSS.Strings.Virtual_String
   is (Self.Owner);

   function Position
     (Self : Interrupt_Handler'Class) return Munin.Optional_Position
   is (Self.Assigned_Position);

   overriding
   function Qualified_Name
     (Self : Interrupt_Handler) return VSS.Strings.Virtual_String
   is (Self.Qualified_Name);

end Munin.Interrupt_Handlers;
