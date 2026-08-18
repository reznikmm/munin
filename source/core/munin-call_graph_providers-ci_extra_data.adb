--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with VSS.JSON.Pull_Readers.JSON5;
with VSS.JSON.Streams;
with VSS.Text_Streams.File_Input;

package body Munin.Call_Graph_Providers.CI_Extra_Data is

   ---------------
   -- Read_JSON --
   ---------------

   procedure Read_JSON
     (Self  : in out Munin.Call_Graph_Providers.CI_Databases.Database;
      Name  : VSS.Strings.Virtual_String;
      Error : out VSS.String_Vectors.Virtual_String_Vector)
   is
      use type VSS.Strings.Virtual_String;
      use all type VSS.JSON.Streams.JSON_Stream_Element_Kind;

      procedure Read_Indirect_Call_Target;
      procedure Read_Top_Entries;

      Reader : aliased VSS.JSON.Pull_Readers.JSON5.JSON5_Pull_Reader;
      Input  : aliased VSS.Text_Streams.File_Input.File_Input_Text_Stream;

      -------------------------------
      -- Read_Indirect_Call_Target --
      -------------------------------

      procedure Read_Indirect_Call_Target is
         Caller : VSS.String_Vectors.Virtual_String_Vector;
         Target : VSS.Strings.Virtual_String;
      begin
         Reader.Read_Next;

         while Reader.Element_Kind = Key_Name loop
            declare
               Key : constant VSS.Strings.Virtual_String := Reader.Key_Name;
            begin
               Reader.Read_Next;

               if Key = "caller" then
                  if Reader.Element_Kind = Start_Array then
                     while Reader.Read_Next = String_Value loop
                        Caller.Append (Reader.String_Value);
                     end loop;

                     Reader.Read_Next;  --  End_Array
                  elsif Reader.Element_Kind = String_Value then
                     Caller.Append (Reader.String_Value);
                     Reader.Read_Next;
                  else
                     Error.Append ("Unexpected value for " & Key);
                     Reader.Skip_Current_Value;
                  end if;

               elsif Key = "target" then
                  if Reader.Element_Kind = String_Value then
                     Target := Reader.String_Value;
                     Reader.Read_Next;
                  elsif Reader.Element_Kind = Null_Value then
                     Target := "";
                     Reader.Read_Next;
                  else
                     Error.Append ("Unexpected value for " & Key);
                     Reader.Skip_Current_Value;
                  end if;
               end if;
            end;
         end loop;

         if Target.Is_Null then
            Error.Append ("No `target` in an `indirect_call_targets` element");
         elsif Caller.Is_Empty then
            Error.Append
              ("No (or empty) `caller` in an `indirect_call_targets` element");
         else
            Self.Add_Indirect_Call_Target (Caller, Target);
         end if;
      end Read_Indirect_Call_Target;

      ----------------------
      -- Read_Top_Entries --
      ----------------------

      procedure Read_Top_Entries is
      begin
         Reader.Read_Next;

         while Reader.Element_Kind = Key_Name loop
            declare
               use all type VSS.JSON.JSON_Number_Kind;

               Key  : constant VSS.Strings.Virtual_String := Reader.Key_Name;
               Size : Natural;
            begin
               if Reader.Read_Next = Number_Value
                 and then Reader.Number_Value.Kind in JSON_Integer
               then
                  Size := Natural (Reader.Number_Value.Integer_Value);
                  Self.Add_Entry (Key, Size);
                  Reader.Read_Next;
               else
                  Error.Append ("Unexpected value for " & Key);
                  Reader.Skip_Current_Value;
               end if;
            end;
         end loop;
      end Read_Top_Entries;

   begin
      Input.Open (Name);

      if Input.Has_Error then
         Error.Append (Input.Error_Message & ": " & Name);
         return;
      end if;

      Reader.Set_Stream (Input'Unchecked_Access);
      Reader.Read_Next;

      if not Reader.At_End
        and then not Reader.Has_Error
        and then Reader.Is_Start_Document
      then
         if Reader.Read_Next = Start_Object then
            Reader.Read_Next;

            while Reader.Element_Kind = Key_Name loop
               declare
                  Key : constant VSS.Strings.Virtual_String := Reader.Key_Name;
               begin
                  Reader.Read_Next;

                  if Key = "indirect_call_targets" then
                     if Reader.Element_Kind = Start_Array then
                        while Reader.Read_Next = Start_Object loop
                           Read_Indirect_Call_Target;
                        end loop;
                     else
                        Error.Append ("Unexpected value for " & Key);
                        Reader.Skip_Current_Value;
                     end if;

                  elsif Key = "top_entries" then
                     if Reader.Element_Kind = Start_Object then
                        Read_Top_Entries;
                        Reader.Read_Next;  --  End_Object
                     else
                        Error.Append ("Unexpected value for " & Key);
                        Reader.Skip_Current_Value;
                     end if;

                  else
                     Error.Append ("Unexpected key:" & Key);
                     Reader.Skip_Current_Value;
                  end if;
               end;
            end loop;

            Reader.Read_Next;  --  End_Object
         end if;
      end if;
   end Read_JSON;

end Munin.Call_Graph_Providers.CI_Extra_Data;
