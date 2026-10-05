--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with GNAT.OS_Lib;

with VSS.Text_Streams.Standards;

package body Munin.CLI.Errors is

   procedure Report_Error (Message : VSS.Strings.Virtual_String) is
      Lines : VSS.String_Vectors.Virtual_String_Vector;
   begin
      Lines.Append (Message);
      Report_Error (Lines);
   end Report_Error;

   procedure Report_Error (Message : VSS.String_Vectors.Virtual_String_Vector)
   is
      Error   : VSS.Text_Streams.Output_Text_Stream'Class :=
        VSS.Text_Streams.Standards.Standard_Error;
      Success : Boolean := True;
   begin
      for Line of Message loop
         Error.Put_Line (Line, Success);
      end loop;

      GNAT.OS_Lib.OS_Exit (Failure_Status);
   end Report_Error;

end Munin.CLI.Errors;
