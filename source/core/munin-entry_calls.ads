--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  List of entry calls

with Ada.Containers.Hashed_Maps;

package Munin.Entry_Calls is

   type Entry_Call_Register is tagged limited private;

   function Target
     (Self : Entry_Call_Register'Class; Call : Position)
      return Optional_Position;

   procedure Include
     (Self   : in out Entry_Call_Register'Class;
      Call   : Position;
      Target : Position);

private

   package Position_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Position,
        Element_Type    => Position,
        Hash            => Hash,
        Equivalent_Keys => "=");
   --  Maps one resolved source position to another; used to carry a
   --  caller-position-independent record of "a call at this position
   --  really targets the code at that position" from Libadalang-based
   --  analysis (Munin.Contexts) into a Call_Graph_Provider implementation
   --  that cannot make that determination on its own (see
   --  Munin.Call_Graph_Providers.CI's entry-call resolution). Plain data,
   --  no Libadalang types, so a provider implementation need not depend on
   --  Libadalang to consume it.

   type Entry_Call_Register is tagged limited record
      Map : Position_Maps.Map;
   end record;

end Munin.Entry_Calls;
