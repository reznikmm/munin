--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

package Munin.Priorities is

   subtype Priority_Value is Integer;

   type Optional_Priority (Has_Value : Boolean := False) is record
      case Has_Value is
         when False =>
            null;
         when True =>
            Value : Priority_Value;
      end case;
   end record;

   Default_Priority : constant Optional_Priority := (Has_Value => False);

   function Explicit_Priority
     (Value : Priority_Value) return Optional_Priority is
       (Has_Value => True, Value => Value);

end Munin.Priorities;