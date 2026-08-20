--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

--  Testsuite main runner for Munin unit tests

with Ada.Text_IO;
with Ada.Strings.Unbounded;
with Test_Call_Graph_Cycle;
with Test_Call_Graph_Cycles_Scc;
with Test_Call_Graph_Dynamic;
with Test_Call_Graph_Hello_World;
with Test_Priority;
with Test_Traverses;
with Trendy_Test;

procedure Testsuite is
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;

   Tests : constant Trendy_Test.Test_Group :=
     (Test_Priority.Test_Priority_Build'Access,
      Test_Traverses.Test_Each_Library_Level_Name'Access,
      Test_Traverses.Test_Each_Effectively_Global_Name'Access,
      Test_Call_Graph_Hello_World.Test_Call_Graph_Hello_World_Build'Access,
      Test_Call_Graph_Cycle.Test_Call_Graph_Cycle_Build'Access,
      Test_Call_Graph_Cycles_Scc.Test_Call_Graph_Cycles_Scc_Build'Access,
      Test_Call_Graph_Dynamic.Test_Call_Graph_Dynamic_Build'Access);

   Results : Trendy_Test.Test_Report_Vectors.Vector;

begin
   Trendy_Test.Register (Tests);
   Results := Trendy_Test.Run;

   Put_Line ("=== Testsuite Results ===");
   for Report of Results loop
      declare
         Name   : constant String := To_String (Report.Name);
         Status : constant String := Report.Status'Image;
      begin
         Put_Line (Name & ": " & Status);

         if Length (Report.Failure) > 0 then
            Put_Line (To_String (Report.Failure));
         end if;
      end;
   end loop;
end Testsuite;
