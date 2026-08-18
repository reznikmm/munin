--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

--  Test module for Munin.Contexts.Traverses.Each_Library_Level_Name.
--  Builds the priority testcase crate as setup, then asserts on which
--  library-level names the traversal itself discovers -- as opposed to
--  Munin.Contexts.Load_Project's higher-level task/protected-object
--  classification, which is covered by Test_Priority.

with Trendy_Test;

package Test_Traverses is

   procedure Test_Each_Library_Level_Name
     (Op : in out Trendy_Test.Operation'Class);

   procedure Test_Each_Effectively_Global_Name
     (Op : in out Trendy_Test.Operation'Class);
   --  Test module for
   --  Munin.Contexts.Traverses.Each_Effectively_Global_Name: asserts on the
   --  names it discovers in main's and a task's own first declarative
   --  section, as opposed to Each_Library_Level_Name's proper library-level
   --  names, which are covered above and must not be re-yielded here.

end Test_Traverses;
