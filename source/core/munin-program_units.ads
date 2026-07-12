--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;

package Munin.Program_Units is

   type Program_Unit is interface;

   function Qualified_Name
     (Self : Program_Unit) return VSS.Strings.Virtual_String is abstract;

end Munin.Program_Units;