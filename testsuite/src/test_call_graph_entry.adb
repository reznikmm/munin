--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Munin.Call_Graph_Providers;
with Munin.Contexts;
with Test_Build_Support;
with Test_Call_Graph_Support;
with Trendy_Test.Assertions;
with VSS.Characters.Latin;
with VSS.String_Vectors;
with VSS.Strings;
with VSS.Strings.Conversions;

package body Test_Call_Graph_Entry is

   use type Munin.Call_Graph_Providers.Call_Graph_Provider_Access;
   use type VSS.Strings.Virtual_String;

   procedure Test_Call_Graph_Entry_Build
     (Op : in out Trendy_Test.Operation'Class)
   is
      Crate_Dir : constant String :=
        Test_Build_Support.Testsuite_Root & "/test_cases/callgraph_entry";

      Success : Boolean;
   begin
      Op.Register (Parallelize => False);

      Test_Build_Support.Build_Crate
        (Op, Crate_Dir, "test_call_graph_entry_build.log", Success);

      if not Success then
         return;
      end if;

      --  Testing: load the project through the full Munin.Contexts
      --  pipeline (not Munin.Call_Graph_Providers.CI.Initialize
      --  directly, unlike the other callgraph_* tests), since building
      --  the entry-call target map that resolves Guard.Wait happens
      --  there, in Munin.Contexts.Load_Project.
      declare
         Context  : Munin.Contexts.Context;
         Errors   : VSS.String_Vectors.Virtual_String_Vector;
         Warnings : VSS.String_Vectors.Virtual_String_Vector;
      begin
         Munin.Contexts.Load_Project
           (Self         => Context,
            Project_File =>
              VSS.Strings.Conversions.To_Virtual_String
                (Crate_Dir & "/callgraph_entry.gpr"),
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
               Worker : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                 Test_Call_Graph_Support.Node_Of
                   (Provider.all, "guard_pkg__workerTKB");

               Entry_Body :
                 constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                   Test_Call_Graph_Support.Node_Of
                     (Provider.all, "guard_pkg__guard__wait_E3s");

               Entry_Position : constant Munin.Optional_Position :=
                 Provider.Position (Entry_Body);
            begin
               --  Guard.Wait resolved to the entry's own body, not left
               --  pointing at GNAT's generic entry-call dispatcher.
               Op.Assert (Provider.Is_Entry (Entry_Body));
               Op.Assert (Entry_Position.Is_Set);
               Op.Assert (Entry_Position.Line = 9);
               Op.Assert (Entry_Position.Column = 7);

               --  The dispatcher symbol itself is no longer a direct
               --  callee of Worker: the edge was replaced, not merely
               --  supplemented.
               Op.Assert
                 (not Test_Call_Graph_Support.Has_Callee
                        (Provider.all,
                         Worker,
                         "system__tasking__protected_objects__operations"
                         & "__protected_entry_call"));

               --  Regression guard: the ordinary protected procedure call
               --  (Guard.Signal) is still attributed, but now via a node
               --  synthesized to attribute it to Guard specifically --
               --  every resolvable protected-operation call is split this
               --  way, single-owner objects included, so the raw
               --  "signalP" symbol is no longer a direct callee of
               --  Worker.
               Op.Assert (not Provider.Is_Entry (Worker));
               Op.Assert
                 (not Test_Call_Graph_Support.Has_Callee
                        (Provider.all, Worker, "guard_pkg__guard__signalP"));

               declare
                  Signal_Call :
                    constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                      Test_Call_Graph_Support.Node_Of
                        (Provider.all,
                         "Guard_Pkg.Guard/guard_pkg__guard__signalP");
               begin
                  Op.Assert
                    (Test_Call_Graph_Support.Has_Callee
                       (Provider.all, Worker,
                        "Guard_Pkg.Guard/guard_pkg__guard__signalP"));
                  Op.Assert (Provider.Is_Protected_Operation (Signal_Call));
                  Op.Assert
                    (Provider.Protected_Object_Name (Signal_Call)
                     = "Guard_Pkg.Guard");
                  Op.Assert
                    (Test_Call_Graph_Support.Has_Callee
                       (Provider.all, Signal_Call,
                        "guard_pkg__guard__signalP"));
               end;

               --  The entry call is split the same uniform way: Worker's
               --  actual callee is a node attributing Guard.Wait to
               --  Guard, whose own single callee is the real entry body
               --  Entry_Body already identified above.
               declare
                  Wait_Call :
                    constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                      Test_Call_Graph_Support.Node_Of
                        (Provider.all,
                         "Guard_Pkg.Guard/guard_pkg__guard__wait_E3s");
               begin
                  Op.Assert
                    (Test_Call_Graph_Support.Has_Callee
                       (Provider.all, Worker,
                        "Guard_Pkg.Guard/guard_pkg__guard__wait_E3s"));
                  Op.Assert (Provider.Is_Protected_Operation (Wait_Call));
                  Op.Assert
                    (Provider.Protected_Object_Name (Wait_Call)
                     = "Guard_Pkg.Guard");
                  Op.Assert
                    (Test_Call_Graph_Support.Has_Callee
                       (Provider.all, Wait_Call,
                        "guard_pkg__guard__wait_E3s"));
                  Op.Assert
                    (not Provider.Is_Protected_Operation (Entry_Body));
               end;
            end;
         end;
      end;
   end Test_Call_Graph_Entry_Build;

end Test_Call_Graph_Entry;
