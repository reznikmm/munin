--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with GPR2.Project.Tree;
with GPR2.Project.View;

with Libadalang.Common;

with VSS.Strings.Conversions;

package body Munin.Contexts.Traverses is

   use type Libadalang.Common.Ada_Node_Kind_Type;

   procedure Visit
     (Node   : Libadalang.Analysis.Ada_Node;
      Action : access procedure (Name : Libadalang.Analysis.Defining_Name));

   procedure Visit
     (Node   : Libadalang.Analysis.Ada_Node;
      Action : access procedure (Name : Libadalang.Analysis.Defining_Name))
   is
      Kind : constant Libadalang.Common.Ada_Node_Kind_Type := Node.Kind;
   begin
      --  Skip generic templates: only instantiations are traversed
      if Kind
         in Libadalang.Common.Ada_Generic_Package_Decl
          | Libadalang.Common.Ada_Generic_Subp_Decl
      then
         return;
      end if;

      --  Skip bodies of generic templates.
      --  Instantiations are handled explicitly below.
      if Kind
         in Libadalang.Common.Ada_Package_Body
          | Libadalang.Common.Ada_Subp_Body
      then
         begin
            declare
               Decl_Part : constant Libadalang.Analysis.Basic_Decl :=
                 Node.As_Body_Node.P_Decl_Part;
               Decl_Kind : constant Libadalang.Common.Ada_Node_Kind_Type :=
                 (if Decl_Part.Is_Null
                  then Libadalang.Common.Ada_Node_Kind_Type'First
                  else Decl_Part.Kind);
            begin
               if not Decl_Part.Is_Null
                 and Decl_Kind
                     in Libadalang.Common.Ada_Generic_Package_Decl
                      | Libadalang.Common.Ada_Generic_Subp_Decl
                      | Libadalang.Common.Ada_Generic_Package_Internal
                      | Libadalang.Common.Ada_Generic_Subp_Internal
               then
                  return;
               end if;
            end;
         exception
            when Libadalang.Common.Property_Error =>
               null;
         end;
      end if;

      --  Skip routine bodies: declarations inside are not global
      if Kind
         in Libadalang.Common.Ada_Subp_Body
          | Libadalang.Common.Ada_Entry_Body
          | Libadalang.Common.Ada_Task_Body
      then
         return;
      end if;

      --  For generic package instantiations, traverse designated generic
      if Kind = Libadalang.Common.Ada_Generic_Package_Instantiation then
         begin
            declare
               Inst       :
                 constant Libadalang.Analysis.Generic_Package_Instantiation :=
                   Node.As_Generic_Package_Instantiation;
               Designated : constant Libadalang.Analysis.Generic_Decl :=
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
      Action : access procedure (Name : Libadalang.Analysis.Defining_Name)) is
   begin
      for File_Name of Self.Sources loop
         declare
            File_Path : constant String :=
              VSS.Strings.Conversions.To_UTF_8_String (File_Name);
            Unit      : constant Libadalang.Analysis.Analysis_Unit :=
              Self.Analysis_Context.Get_From_File (File_Path);
            Root      : constant Libadalang.Analysis.Ada_Node := Unit.Root;
         begin
            if not Root.Is_Null then
               Visit (Root, Action);
            end if;
         end;
      end loop;
   end Each_Library_Level_Name;

   procedure Scan_Decls
     (Decls  : Libadalang.Analysis.Declarative_Part;
      Action : access procedure (Name : Libadalang.Analysis.Defining_Name));
   --  Visit each item of Decls' own item list (never descending into any
   --  nested declare block, loop, or subprogram body reached from it --
   --  those aren't elaborated exactly once).

   procedure Scan_Decls
     (Decls  : Libadalang.Analysis.Declarative_Part;
      Action : access procedure (Name : Libadalang.Analysis.Defining_Name)) is
   begin
      if Decls.Is_Null then
         return;
      end if;

      for Item of Decls.F_Decls loop
         if not Item.Is_Null then
            Visit (Libadalang.Analysis.Ada_Node (Item), Action);
         end if;
      end loop;
   end Scan_Decls;

   procedure Each_Effectively_Global_Name
     (Self   : Munin.Contexts.Context;
      Action : access procedure (Name : Libadalang.Analysis.Defining_Name))
   is
      procedure Recurse_If_Task (Node : Libadalang.Analysis.Ada_Node);
      --  If Node is a Single_Task_Decl/Single_Task_Type_Decl, scan its
      --  body's own first declarative section too, reporting (and
      --  recursing on) whatever is found there. A task can only be
      --  declared this way inside the environment task (main), since
      --  Ravenscar's No_Task_Hierarchy forbids a task depending on
      --  another, non-environment task.

      procedure Report (Name : Libadalang.Analysis.Defining_Name);
      --  Report Name to the caller, then recurse into it if it is itself
      --  a task -- used for names found while scanning a declarative
      --  section, as opposed to a task found by Each_Library_Level_Name
      --  (which already reports the task itself elsewhere).

      procedure Report (Name : Libadalang.Analysis.Defining_Name) is
      begin
         Action (Name);
         Recurse_If_Task (Name.Parent);
      end Report;

      procedure Recurse_If_Task (Node : Libadalang.Analysis.Ada_Node) is
      begin
         if Node.Kind
            in Libadalang.Common.Ada_Single_Task_Decl
             | Libadalang.Common.Ada_Single_Task_Type_Decl
         then
            declare
               Body_Part : constant Libadalang.Analysis.Body_Node :=
                 Node.As_Basic_Decl.P_Body_Part_For_Decl;
            begin
               if not Body_Part.Is_Null
                 and then Body_Part.Kind = Libadalang.Common.Ada_Task_Body
               then
                  Scan_Decls (Body_Part.As_Task_Body.F_Decls, Report'Access);
               end if;
            end;
         end if;
      exception
         when Libadalang.Common.Property_Error =>
            null;
      end Recurse_If_Task;

      procedure Task_Collector (Name : Libadalang.Analysis.Defining_Name);
      --  Each_Library_Level_Name already reports Name itself (to
      --  Process_Name, via Load_Project's separate call to it); only its
      --  body's locals are new here.

      procedure Task_Collector (Name : Libadalang.Analysis.Defining_Name) is
      begin
         Recurse_If_Task (Name.Parent);
      end Task_Collector;
   begin
      Each_Library_Level_Name (Self, Task_Collector'Access);

      for Main_Location of Self.Project_Tree.Root_Project.Mains loop
         declare
            File_Path : constant String := String (Main_Location.Source.Value);
            Unit      : constant Libadalang.Analysis.Analysis_Unit :=
              Self.Analysis_Context.Get_From_File (File_Path);
            Item      : constant Libadalang.Analysis.Ada_Node :=
              (if Unit.Root.Is_Null
                 or else Unit.Root.Kind
                         /= Libadalang.Common.Ada_Compilation_Unit
               then Libadalang.Analysis.No_Ada_Node
               else Unit.Root.As_Compilation_Unit.F_Body);

            Main_Decl : constant Libadalang.Analysis.Basic_Decl :=
              (if not Item.Is_Null
                 and then Item.Kind = Libadalang.Common.Ada_Library_Item
               then Item.As_Library_Item.F_Item
               else Libadalang.Analysis.No_Basic_Decl);
         begin
            if not Main_Decl.Is_Null
              and then Main_Decl.Kind = Libadalang.Common.Ada_Subp_Body
            then
               Scan_Decls (Main_Decl.As_Subp_Body.F_Decls, Report'Access);
            end if;
         exception
            when Libadalang.Common.Property_Error =>
               null;
         end;
      end loop;
   end Each_Effectively_Global_Name;

end Munin.Contexts.Traverses;
