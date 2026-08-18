--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.Strings;
with VSS.String_Vectors;

with Munin.Call_Graph_Providers.CI_Databases;

package Munin.Call_Graph_Providers.CI_Extra_Data is

   procedure Read_JSON
     (Self  : in out Munin.Call_Graph_Providers.CI_Databases.Database;
      Name  : VSS.Strings.Virtual_String;
      Error : out VSS.String_Vectors.Virtual_String_Vector);
   --  Read Self's `top_entries`/`indirect_call_targets` overrides from the
   --  JSON5 file Name (see the "Extra information" section of README).
   --  For the future worst-case-stack feature; not called automatically by
   --  Initialize.

end Munin.Call_Graph_Providers.CI_Extra_Data;
