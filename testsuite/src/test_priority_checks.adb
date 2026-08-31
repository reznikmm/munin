--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.Call_Graph_Providers;
with Munin.Contexts;
with Munin.Priority_Checks;
with Test_Build_Support;
with Trendy_Test.Assertions;
with VSS.Characters.Latin;
with VSS.String_Vectors;
with VSS.Strings;
with VSS.Strings.Conversions;

package body Test_Priority_Checks is

   use type Munin.Call_Graph_Providers.Call_Graph_Provider_Access;
   use type VSS.Strings.Virtual_String;

   procedure Test_Priority_Checks_Build
     (Op : in out Trendy_Test.Operation'Class)
   is
      Crate_Dir : constant String :=
        Test_Build_Support.Testsuite_Root & "/test_cases/priority_check";

      Success : Boolean;
   begin
      Op.Register (Parallelize => False);

      Test_Build_Support.Build_Crate
        (Op, Crate_Dir, "test_priority_checks_build.log", Success);

      if not Success then
         return;
      end if;

      declare
         Context  : Munin.Contexts.Context;
         Errors   : VSS.String_Vectors.Virtual_String_Vector;
         Warnings : VSS.String_Vectors.Virtual_String_Vector;
      begin
         Munin.Contexts.Load_Project
           (Self         => Context,
            Project_File =>
              VSS.Strings.Conversions.To_Virtual_String
                (Crate_Dir & "/priority_check.gpr"),
            Errors       => Errors,
            Warnings     => Warnings);

         if not Errors.Is_Empty then
            declare
               Message : VSS.Strings.Virtual_String := "Load_Project errors:";
            begin
               for Item of Errors loop
                  Message := Message & VSS.Characters.Latin.Line_Feed & Item;
               end loop;

               Trendy_Test.Assertions.Fail
                 (Op, VSS.Strings.Conversions.To_UTF_8_String (Message));
               return;
            end;
         end if;

         declare
            Provider :
              constant Munin.Call_Graph_Providers.Call_Graph_Provider_Access :=
                Munin.Contexts.Call_Graph (Context);
         begin
            if Provider = null then
               Trendy_Test.Assertions.Fail
                 (Op,
                  "No call graph: "
                  & VSS.Strings.Conversions.To_UTF_8_String
                      (Munin.Contexts.Call_Graph_Error (Context)));
               return;
            end if;

            declare
               Violations : constant Munin.Priority_Checks.Violation_List :=
                 Munin.Priority_Checks.Check (Context, Provider.all);

               Found_Direct  : Boolean := False;
               Found_Nested  : Boolean := False;
               Found_Unexpected : Boolean := False;
            begin
               for Item of Violations loop
                  if Item.Object_Name = "Priority_Check_Sample.Low_Ceiling"
                  then
                     Op.Assert (Item.Ceiling = 5);
                     Op.Assert (Item.Reached_At = 10);
                     Op.Assert (not Item.Path.Is_Empty);
                     Found_Direct := True;

                  elsif Item.Object_Name
                    = "Priority_Check_Sample.Nested_Low"
                  then
                     Op.Assert (Item.Ceiling = 8);
                     Op.Assert (Item.Reached_At = 20);
                     Op.Assert (not Item.Path.Is_Empty);
                     Found_Nested := True;

                  else
                     --  Consistent, High_Ceiling, and Default_Object are
                     --  all clean (their ceiling is never exceeded by any
                     --  active priority that reaches them) -- any other
                     --  reported violation is a false positive.
                     Found_Unexpected := True;
                  end if;
               end loop;

               Op.Assert (Found_Direct);
               Op.Assert (Found_Nested);
               Op.Assert (not Found_Unexpected);
               Op.Assert (Natural (Violations.Length) = 2);
            end;
         end;
      end;
   end Test_Priority_Checks_Build;

end Test_Priority_Checks;
