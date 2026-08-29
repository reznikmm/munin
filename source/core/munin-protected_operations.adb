--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Munin.Protected_Operations is

   function Protected_Object
     (Self : Registry'Class; Call_Site : Position)
      return VSS.Strings.Virtual_String
   is
      Cursor : constant Position_Maps.Cursor := Self.Map.Find (Call_Site);
   begin
      return
        (if Position_Maps.Has_Element (Cursor)
         then Position_Maps.Element (Cursor)
         else VSS.Strings.Empty_Virtual_String);
   end Protected_Object;

   procedure Set_Protected_Object
     (Self           : in out Registry'Class;
      Call_Site      : Position;
      Qualified_Name : VSS.Strings.Virtual_String) is
   begin
      Self.Map.Include (Call_Site, Qualified_Name);
   end Set_Protected_Object;

end Munin.Protected_Operations;
