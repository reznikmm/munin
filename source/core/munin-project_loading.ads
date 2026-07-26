--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with GPR2.Project.Tree;
with Libadalang.Analysis;

with VSS.String_Vectors;
with VSS.Strings;

package Munin.Project_Loading is

   procedure Load
     (Project_File     : VSS.Strings.Virtual_String;
      Tree             : in out GPR2.Project.Tree.Object;
      Analysis_Context : in out Libadalang.Analysis.Analysis_Context;
      Sources          : out VSS.String_Vectors.Virtual_String_Vector;
      Errors           : in out VSS.String_Vectors.Virtual_String_Vector);

end Munin.Project_Loading;
