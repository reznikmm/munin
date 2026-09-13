--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  Sample Ada source exercising Munin's `check locks` re-entrancy check,
--  used as the "under test" project for Munin's lock-check testcase.
--  This source is analyzed by Munin (via Libadalang and its `.ci` call
--  graph); it is not executed.

package Lock_Check_Sample is

   protected Internal_Chain is
      procedure Enter;
      procedure Middle;
      procedure Inner;
   end Internal_Chain;
   --  Enter calls Middle, and Middle calls Inner, both by plain
   --  (unqualified) name from within Internal_Chain's own body -- a
   --  chain of internal calls (Ada RM 9.5.1), always safe, never
   --  reported.

   protected Reentered is
      procedure Enter;
      procedure Inner;
   end Reentered;
   --  Enter calls Lock_Check_Helper.Trigger, an ordinary subprogram
   --  declared outside Reentered, which calls back into Reentered.Inner
   --  through a dotted (external) call. Since Trigger is only ever
   --  reached from Reentered.Enter, Reentered is already locked by the
   --  same task at that point -- reported.

   protected Clean is
      procedure Op;
   end Clean;
   --  Never re-entered -- no violation expected here.

   protected Private_Helper is
      procedure Enter;
      procedure Inner;
   end Private_Helper;
   --  Enter calls Helper -- a subprogram declared directly in
   --  Private_Helper's own body (a protected_operation_item, Ada RM 9.4),
   --  not part of its visible or private spec -- which itself calls
   --  Inner. Helper has the same direct (unqualified-name) visibility to
   --  Private_Helper's own operations as any of them has to each other
   --  (Ada RM 9.5.1), so this whole chain is internal too -- never
   --  reported.

end Lock_Check_Sample;
