--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;
with VSS.Text_Streams;

with Munin.Call_Graph_Providers.CI_Compilation_Units;

package Munin.Call_Graph_Providers.CI_Parsers is

   procedure Parse
     (Stream : in out VSS.Text_Streams.Input_Text_Stream'Class;
      Unit   : in out Munin.Call_Graph_Providers.CI_Compilation_Units
                        .Compilation_Unit;
      Error  : out VSS.Strings.Virtual_String);
   --  Parse the `.ci` (GCC `-fcallgraph-info`) content of Stream into
   --  Unit. Error is left empty on success.

end Munin.Call_Graph_Providers.CI_Parsers;
