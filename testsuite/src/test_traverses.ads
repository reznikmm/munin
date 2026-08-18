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

end Test_Traverses;
