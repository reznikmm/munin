--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Libadalang.Analysis;

package Munin.Contexts.Traverses is

   procedure Each_Library_Level_Name
     (Self   : Munin.Contexts.Context;
      Action : access procedure (Name : Libadalang.Analysis.Defining_Name));

   procedure Each_Effectively_Global_Name
     (Self   : Munin.Contexts.Context;
      Action : access procedure (Name : Libadalang.Analysis.Defining_Name));
   --  In a Ravenscar/Jorvik program, tasks never terminate and the
   --  environment task waits for all of them before the partition
   --  completes (RM 10.2), so an object declared in the main subprogram's
   --  own first declarative section, or in a (non-generic) task's own
   --  first declarative section, is elaborated exactly once and lives for
   --  the whole program -- exactly like a library-level object. This finds
   --  the `Defining_Name`s of such objects (never the enclosing task/main
   --  itself, which `Each_Library_Level_Name` already finds).

end Munin.Contexts.Traverses;
