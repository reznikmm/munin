--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

--  Testsuite main runner for Munin unit tests

with Ada.Text_IO;
with Ada.Strings.Unbounded;
with Test_Priority;
with Test_Traverses;
with Trendy_Test;

procedure Testsuite is
   use Ada.Text_IO;
   use Ada.Strings.Unbounded;

   Tests : constant Trendy_Test.Test_Group :=
     (Test_Priority.Test_Priority_Build'Access,
      Test_Traverses.Test_Each_Library_Level_Name'Access,
      Test_Traverses.Test_Each_Effectively_Global_Name'Access);

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
      end;
   end loop;
end Testsuite;
