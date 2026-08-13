--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Libadalang.Common;

with VSS.Strings.Conversions;

package body Munin.Contexts.Traverses is

   use type Libadalang.Common.Ada_Node_Kind_Type;

   procedure Visit
     (Node   : Libadalang.Analysis.Ada_Node;
      Action : access
        procedure (Name : Libadalang.Analysis.Defining_Name));

   procedure Visit
     (Node   : Libadalang.Analysis.Ada_Node;
      Action : access
        procedure (Name : Libadalang.Analysis.Defining_Name))
   is
      Kind : constant Libadalang.Common.Ada_Node_Kind_Type :=
        Libadalang.Analysis.Kind (Node);
   begin
      --  Skip routine bodies: declarations inside are not global
      if Kind in Libadalang.Common.Ada_Subp_Body
               | Libadalang.Common.Ada_Entry_Body
               | Libadalang.Common.Ada_Task_Body
      then
         return;
      end if;

      --  Skip generic templates: only instantiations are traversed
      if Kind in Libadalang.Common.Ada_Generic_Package_Decl
               | Libadalang.Common.Ada_Generic_Subp_Decl
      then
         return;
      end if;

      --  For generic package instantiations, traverse designated generic
      if Kind = Libadalang.Common.Ada_Generic_Package_Instantiation then
         begin
            declare
               Inst : constant
                 Libadalang.Analysis.Generic_Package_Instantiation :=
                   Node.As_Generic_Package_Instantiation;
               Designated :
                 constant Libadalang.Analysis.Generic_Decl :=
                   Inst.P_Designated_Generic_Decl;
            begin
               if not Designated.Is_Null then
                  for Index in 1 .. Designated.Children_Count loop
                     declare
                        Child_Node : constant Libadalang.Analysis.Ada_Node :=
                          Designated.Child (Index);
                     begin
                        if not Child_Node.Is_Null then
                           Visit (Child_Node, Action);
                        end if;
                     end;
                  end loop;
               end if;
            end;
         exception
            when Libadalang.Common.Property_Error =>
               null;
         end;
         return;
      end if;

      if Kind = Libadalang.Common.Ada_Defining_Name then
         Action (Node.As_Defining_Name);
         return;
      end if;

      for Index in 1 .. Libadalang.Analysis.Children_Count (Node) loop
         declare
            Child_Node : constant Libadalang.Analysis.Ada_Node :=
              Libadalang.Analysis.Child (Node, Index);
         begin
            if not Child_Node.Is_Null then
               Visit (Child_Node, Action);
            end if;
         end;
      end loop;
   end Visit;

   procedure Each_Library_Level_Name
     (Self   : Munin.Contexts.Context;
      Action : access
        procedure (Name : Libadalang.Analysis.Defining_Name))
   is
   begin
      for File_Name of Self.Sources loop
         declare
            File_Path : constant String :=
              VSS.Strings.Conversions.To_UTF_8_String (File_Name);
            Unit : constant Libadalang.Analysis.Analysis_Unit :=
              Self.Analysis_Context.Get_From_File (File_Path);
            Root : constant Libadalang.Analysis.Ada_Node := Unit.Root;
         begin
            if not Root.Is_Null then
               Visit (Root, Action);
            end if;
         end;
      end loop;
   end Each_Library_Level_Name;

end Munin.Contexts.Traverses;
