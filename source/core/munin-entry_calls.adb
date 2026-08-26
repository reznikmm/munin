--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package body Munin.Entry_Calls is

   procedure Include
     (Self   : in out Entry_Call_Register'Class;
      Call   : Position;
      Target : Position) is
   begin
      Self.Map.Include (Call, Target);
   end Include;

   function Target
     (Self : Entry_Call_Register'Class; Call : Position)
      return Optional_Position
   is
      Cursor : constant Position_Maps.Cursor := Self.Map.Find (Call);
   begin
      return
        (if Position_Maps.Has_Element (Cursor)
         then Position_Maps.Element (Cursor)
         else (Is_Set => False));
   end Target;

end Munin.Entry_Calls;
