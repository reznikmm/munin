--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Libadalang.Analysis;

package Munin.Contexts.Traverses is

   procedure Each_Library_Level_Name
     (Self   : Munin.Contexts.Context;
      Action : access
        procedure (Name : Libadalang.Analysis.Defining_Name));

end Munin.Contexts.Traverses;
