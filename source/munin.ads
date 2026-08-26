--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers;

with VSS.Strings.Hash;

package Munin is
   pragma Preelaborate;

   type Optional_Position (Is_Set : Boolean := False) is record
      case Is_Set is
         when False =>
            null;

         when True =>
            File   : VSS.Strings.Virtual_String;
            Line   : Positive;
            Column : Positive;
      end case;
   end record;

   subtype Position is Optional_Position (Is_Set => True);

   function To_Position
     (File : VSS.Strings.Virtual_String; Line : Positive; Column : Positive)
      return Position
   is (True, File, Line, Column);

   function Hash (Position : Optional_Position) return Ada.Containers.Hash_Type
   is (if not Position.Is_Set
       then 0
       else
         Ada.Containers."xor"
           (Ada.Containers."xor"
              (VSS.Strings.Hash (Position.File),
               Ada.Containers.Hash_Type'Mod (Position.Line)),
            Ada.Containers.Hash_Type'Mod (Position.Column)));

end Munin;
