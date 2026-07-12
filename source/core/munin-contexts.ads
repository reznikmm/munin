--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Vectors;

with VSS.String_Vectors;
with VSS.Strings;

with Munin.Protected_Objects;
with Munin.Tasks;

package Munin.Contexts is

   type Context is tagged limited private;

   procedure Load_Project
     (Self         : in out Context;
      Project_File : VSS.Strings.Virtual_String;
      Errors       : out VSS.String_Vectors.Virtual_String_Vector);

   function Tasks (Self : Context) return Munin.Tasks.Task_Unit_Array;

   function Protected_Objects
     (Self : Context) return Munin.Protected_Objects.Protected_Object_Array;

private

   use type Munin.Tasks.Task_Unit;
   use type Munin.Protected_Objects.Protected_Object;

   package Task_Unit_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Munin.Tasks.Task_Unit);

   package Protected_Object_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Munin.Protected_Objects.Protected_Object);

   type Context is tagged limited record
      Loaded_Project  : VSS.Strings.Virtual_String :=
        VSS.Strings.Empty_Virtual_String;
      Task_Items      : Task_Unit_Vectors.Vector;
      Protected_Items : Protected_Object_Vectors.Vector;
   end record;

end Munin.Contexts;