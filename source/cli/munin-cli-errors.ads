--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.String_Vectors;
with VSS.Strings;

package Munin.CLI.Errors is

   Failure_Status : constant := 2;
   --  Exit status for a usage error, a project that failed to load, missing
   --  data, or an internal error. (Status 1 is reserved for `check`
   --  commands that found violations.)

   procedure Report_Error (Message : VSS.Strings.Virtual_String)
   with No_Return;
   --  Write Message to standard error and terminate with Failure_Status.

   procedure Report_Error (Message : VSS.String_Vectors.Virtual_String_Vector)
   with No_Return;
   --  Write each line of Message to standard error and terminate with
   --  Failure_Status.

end Munin.CLI.Errors;
