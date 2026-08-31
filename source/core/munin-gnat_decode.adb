--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Characters.Handling;
with Interfaces.C;
with System;

with VSS.Strings.Conversions;

package body Munin.Gnat_Decode is

   procedure Gnat_Decode
     (Coded_Name_Addr : System.Address;
      Ada_Name_Addr   : System.Address;
      Verbose         : Interfaces.C.int);
   pragma Import (C, Gnat_Decode, "__gnat_decode");

   procedure To_Mixed_Case (Value : in out String);
   --  Value with the first letter of each "word" upper-cased and every
   --  other letter lower-cased -- a word starts at Value'First and after
   --  each '_' or '.' (the separators Decode's output ever uses, for a
   --  package/scope-qualification boundary and an Ada identifier's own
   --  word boundary respectively). Matches conventional Ada identifier
   --  casing; __gnat_decode itself never preserves the original source
   --  casing (GNAT's symbol table doesn't keep it), so this is a
   --  best-effort convention, not a recovery of the real spelling.

   procedure To_Mixed_Case (Value : in out String) is
      Start_Of_A_Word : Boolean := True;
   begin
      for Item of Value loop
         if Start_Of_A_Word then
            Item := Ada.Characters.Handling.To_Upper (Item);
         else
            Item := Ada.Characters.Handling.To_Lower (Item);
         end if;

         Start_Of_A_Word := Item in '_' | '.';
      end loop;
   end To_Mixed_Case;

   ------------
   -- Decode --
   ------------

   function Decode
     (Symbol : VSS.Strings.Virtual_String) return VSS.Strings.Virtual_String
   is
      use Interfaces.C;

      Coded   : constant char_array :=
        To_C (VSS.Strings.Conversions.To_UTF_8_String (Symbol));
      Decoded : char_array (0 .. size_t (Coded'Length) * 2 + 60);
   begin
      Gnat_Decode (Coded'Address, Decoded'Address, Verbose => 0);

      declare
         Result : String := To_Ada (Decoded);
      begin
         To_Mixed_Case (Result);

         return VSS.Strings.Conversions.To_Virtual_String (Result);
      end;
   end Decode;

end Munin.Gnat_Decode;
