--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  An array of protected objects, indexed by a runtime-computed value, so
--  no static call site can be attributed to one specific element. Used by
--  Munin's own testsuite to verify this is reported as a load-time
--  "cannot determine" diagnostic rather than misattributed. Direct is a
--  plain object of the same type, called directly -- Cell's operations
--  are only ever scanned for call sites at all because a named object of
--  the type exists (an array component type alone never triggers that);
--  Direct also exercises the ordinary, resolvable case for contrast.

package Unresolvable is

   protected type Cell is
      procedure Set (Value : Integer);
      function Get return Integer;
   private
      Data : Integer := 0;
   end Cell;

   Direct : Cell;

   type Index is range 1 .. 2;

   Cells : array (Index) of Cell;

   task Direct_User;
   task Selector;

end Unresolvable;
