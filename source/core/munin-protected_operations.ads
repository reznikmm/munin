--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Per-call-site protected object attribution

with Ada.Containers.Hashed_Maps;

with VSS.Strings;

package Munin.Protected_Operations is

   type Registry is tagged limited private;

   function Protected_Object
     (Self : Registry'Class; Call_Site : Position)
      return VSS.Strings.Virtual_String;
   --  The qualified name of the protected object statically determined to
   --  be the target of the call at Call_Site, or an empty string when
   --  Call_Site was never recorded (the call's target object could not be
   --  determined -- e.g. a dynamically indexed array of protected objects).

   procedure Set_Protected_Object
     (Self           : in out Registry'Class;
      Call_Site      : Position;
      Qualified_Name : VSS.Strings.Virtual_String);
   --  Record that the call at Call_Site (a specific source reference)
   --  statically resolves to the protected object named Qualified_Name --
   --  either directly (an unqualified self-call from within the object's
   --  own body) or via Libadalang cross-reference on a dotted call's
   --  prefix.

private

   package Position_Maps is new
     Ada.Containers.Hashed_Maps
       (Key_Type        => Position,
        Element_Type    => VSS.Strings.Virtual_String,
        Hash            => Hash,
        Equivalent_Keys => "=",
        "="             => VSS.Strings."=");
   --  Maps a call site's own source position to the qualified name of the
   --  protected object it targets; used to carry a caller-position-
   --  independent record of "the call at this position targets this
   --  object" from Libadalang-based analysis (Munin.Contexts) into a
   --  Call_Graph_Provider implementation that cannot make that
   --  determination on its own (see
   --  Munin.Call_Graph_Providers.CI_Databases's node-splitting
   --  resolution). Plain data, no Libadalang types, so a provider
   --  implementation need not depend on Libadalang to consume it.

   type Registry is tagged limited record
      Map : Position_Maps.Map;
   end record;

end Munin.Protected_Operations;
