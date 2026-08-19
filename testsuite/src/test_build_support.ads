--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Setup logic shared by testcase-crate-backed tests: locating the
--  testsuite root and building a testcase crate via `alr`.

with Trendy_Test;

package Test_Build_Support is

   function Testsuite_Root return String;
   --  The testsuite's own root directory (parent of the `bin/` directory
   --  the running test executable was launched from).

   procedure Build_Crate
     (Op        : in out Trendy_Test.Operation'Class;
      Crate_Dir : String;
      Log_Name  : String;
      Success   : out Boolean);
   --  Build the crate at Crate_Dir via `alr -C Crate_Dir build`, logging
   --  its output to Testsuite_Root & "/obj/" & Log_Name. On failure,
   --  fails Op with the (tail of the) build output and sets
   --  Success to False.

end Test_Build_Support;
