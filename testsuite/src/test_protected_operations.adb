--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Strings.Fixed;

with Munin.Call_Graph_Providers;
with Munin.Contexts;
with Test_Build_Support;
with Test_Call_Graph_Support;
with Trendy_Test.Assertions;
with VSS.Characters.Latin;
with VSS.String_Vectors;
with VSS.Strings;
with VSS.Strings.Conversions;

package body Test_Protected_Operations is

   use type Munin.Call_Graph_Providers.Call_Graph_Provider_Access;
   use type VSS.Strings.Virtual_String;

   procedure Test_Protected_Operations_Build
     (Op : in out Trendy_Test.Operation'Class)
   is
      Crate_Dir : constant String :=
        Test_Build_Support.Testsuite_Root
        & "/test_cases/protected_operations";

      Success : Boolean;

      function Contains (Text, Pattern : String) return Boolean is
        (Ada.Strings.Fixed.Index (Text, Pattern) > 0);
   begin
      Op.Register (Parallelize => False);

      Test_Build_Support.Build_Crate
        (Op, Crate_Dir, "test_protected_operations_build.log", Success);

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
                (Crate_Dir & "/protected_operations.gpr"),
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

         --  Unlike the other scenarios, one non-fatal warning (from
         --  Unresolvable) is expected here -- checked explicitly below.

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

            --  Scenario 1 & 2: single-owner object, plus a self-call.
            declare
               Ticker : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                 Test_Call_Graph_Support.Node_Of
                   (Provider.all, "single_owner__tickerTKB");

               Increment_Call :
                 constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                   Test_Call_Graph_Support.Node_Of
                     (Provider.all,
                      "Single_Owner.Counter/"
                      & "single_owner__counter__incrementP");
            begin
               --  The common case is split too: the raw locked symbol is
               --  no longer a direct callee of Ticker.
               Op.Assert
                 (not Test_Call_Graph_Support.Has_Callee
                        (Provider.all, Ticker,
                         "single_owner__counter__incrementP"));
               Op.Assert
                 (Test_Call_Graph_Support.Has_Callee
                    (Provider.all, Ticker,
                     "Single_Owner.Counter/"
                     & "single_owner__counter__incrementP"));
               Op.Assert
                 (Provider.Is_Protected_Operation (Increment_Call));
               Op.Assert
                 (Provider.Protected_Object_Name (Increment_Call)
                  = "Single_Owner.Counter");
               Op.Assert
                 (Test_Call_Graph_Support.Has_Callee
                    (Provider.all, Increment_Call,
                     "single_owner__counter__incrementP"));

               --  The self-call (Reset, called unqualified from within
               --  Increment) resolves to the same object, with no error.
               declare
                  Increment_Body :
                    constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                      Test_Call_Graph_Support.Node_Of
                        (Provider.all, "single_owner__counter__incrementN");

                  Reset_Call :
                    constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                      Test_Call_Graph_Support.Node_Of
                        (Provider.all,
                         "Single_Owner.Counter/"
                         & "single_owner__counter__resetN");
               begin
                  Op.Assert
                    (Test_Call_Graph_Support.Has_Callee
                       (Provider.all, Increment_Body,
                        "Single_Owner.Counter/"
                        & "single_owner__counter__resetN"));
                  Op.Assert (Provider.Is_Protected_Operation (Reset_Call));
                  Op.Assert
                    (Provider.Protected_Object_Name (Reset_Call)
                     = "Single_Owner.Counter");
               end;
            end;

            --  Scenario 3: shared type, two objects, resolvable calls.
            declare
               Producer_A :
                 constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                   Test_Call_Graph_Support.Node_Of
                     (Provider.all, "shared_type__producer_aTKB");

               Producer_B :
                 constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                   Test_Call_Graph_Support.Node_Of
                     (Provider.all, "shared_type__producer_bTKB");

               Add_A : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                 Test_Call_Graph_Support.Node_Of
                   (Provider.all,
                    "Shared_Type.Acc_A/shared_type__accumulator__addP");

               Add_B : constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                 Test_Call_Graph_Support.Node_Of
                   (Provider.all,
                    "Shared_Type.Acc_B/shared_type__accumulator__addP");
            begin
               Op.Assert
                 (Provider.Protected_Object_Name (Add_A)
                  = "Shared_Type.Acc_A");
               Op.Assert
                 (Provider.Protected_Object_Name (Add_B)
                  = "Shared_Type.Acc_B");

               --  Both split nodes reach the same shared implementation
               --  in one hop -- proves Callees isn't duplicated per
               --  owner.
               Op.Assert
                 (Test_Call_Graph_Support.Has_Callee
                    (Provider.all, Add_A,
                     "shared_type__accumulator__addP"));
               Op.Assert
                 (Test_Call_Graph_Support.Has_Callee
                    (Provider.all, Add_B,
                     "shared_type__accumulator__addP"));

               --  But their callers are genuinely distinct -- no
               --  aliasing there.
               Op.Assert
                 (Test_Call_Graph_Support.Has_Caller
                    (Provider.all, Add_A, "shared_type__producer_aTKB"));
               Op.Assert
                 (not Test_Call_Graph_Support.Has_Caller
                        (Provider.all, Add_A, "shared_type__producer_bTKB"));
               Op.Assert
                 (Test_Call_Graph_Support.Has_Caller
                    (Provider.all, Add_B, "shared_type__producer_bTKB"));
               Op.Assert
                 (not Test_Call_Graph_Support.Has_Caller
                        (Provider.all, Add_B, "shared_type__producer_aTKB"));

               Op.Assert
                 (Test_Call_Graph_Support.Has_Callee
                    (Provider.all, Producer_A,
                     "Shared_Type.Acc_A/shared_type__accumulator__addP"));
               Op.Assert
                 (Test_Call_Graph_Support.Has_Callee
                    (Provider.all, Producer_B,
                     "Shared_Type.Acc_B/shared_type__accumulator__addP"));
            end;

            --  Scenario 4: an array of protected objects, indexed
            --  dynamically -- the call site can't be attributed to one
            --  object, so it stays unsplit and gets reported instead.
            declare
               Selector :
                 constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                   Test_Call_Graph_Support.Node_Of
                     (Provider.all, "unresolvable__selectorTKB");

               Found_Error : Boolean := False;
            begin
               Op.Assert
                 (Test_Call_Graph_Support.Has_Callee
                    (Provider.all, Selector, "unresolvable__cell__setP"));

               declare
                  Direct_User :
                    constant Munin.Call_Graph_Providers.Call_Graph_Node :=
                      Test_Call_Graph_Support.Node_Of
                        (Provider.all, "unresolvable__direct_userTKB");
               begin
                  Op.Assert
                    (Test_Call_Graph_Support.Has_Callee
                       (Provider.all, Direct_User,
                        "Unresolvable.Direct/unresolvable__cell__setP"));
               end;

               for Item of Warnings loop
                  declare
                     Text : constant String :=
                       VSS.Strings.Conversions.To_UTF_8_String (Item);
                  begin
                     if Contains (Text, "unresolvable.adb")
                       and then Contains
                                  (Text,
                                   "cannot determine which protected"
                                   & " object")
                     then
                        Found_Error := True;
                     end if;
                  end;
               end loop;

               Op.Assert (Found_Error);
            end;

            --  Scenario 5 (regression): an ordinary, non-protected node
            --  (a task body, or a protected operation's raw base symbol
            --  left unsplit because no call site ever resolved to a
            --  specific owner) is never mistaken for a resolved one.
            Op.Assert
              (not Provider.Is_Protected_Operation
                     (Test_Call_Graph_Support.Node_Of
                        (Provider.all, "single_owner__tickerTKB")));
            Op.Assert
              (not Provider.Is_Protected_Operation
                     (Test_Call_Graph_Support.Node_Of
                        (Provider.all, "unresolvable__cell__setP")));
         end;
      end;
   end Test_Protected_Operations_Build;

end Test_Protected_Operations;
