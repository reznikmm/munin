--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Containers.Hashed_Sets;
with Ada.Directories;
with Ada.Exceptions;

with GPR2;
with GPR2.Build.Source.Sets;
with GPR2.Options;
with GPR2.Project.View;

with VSS.Strings.Conversions;
with VSS.Strings.Hash;

package body Munin.Project_Loading is

   use type VSS.Strings.Virtual_String;

   package Source_Sets is new
     Ada.Containers.Hashed_Sets
       (Element_Type        => VSS.Strings.Virtual_String,
        Hash                => VSS.Strings.Hash,
        Equivalent_Elements => VSS.Strings."=");

   use type Ada.Directories.File_Kind;

   procedure Append_Error
     (Errors : in out VSS.String_Vectors.Virtual_String_Vector;
      Value  : String);

   procedure Load_Project_Tree
     (Project_File : String;
      Tree         : in out GPR2.Project.Tree.Object;
      Errors       : in out VSS.String_Vectors.Virtual_String_Vector);

   procedure Collect_Project_Ada_Sources
     (Tree    : GPR2.Project.Tree.Object;
      Sources : out VSS.String_Vectors.Virtual_String_Vector;
      Errors  : in out VSS.String_Vectors.Virtual_String_Vector);

   procedure Append_Error
     (Errors : in out VSS.String_Vectors.Virtual_String_Vector; Value : String)
   is
   begin
      Errors.Append (VSS.Strings.Conversions.To_Virtual_String (Value));
   end Append_Error;

   procedure Load_Project_Tree
     (Project_File : String;
      Tree         : in out GPR2.Project.Tree.Object;
      Errors       : in out VSS.String_Vectors.Virtual_String_Vector)
   is
      Options : GPR2.Options.Object := GPR2.Options.Empty_Options;
   begin
      GPR2.Options.Add_Switch
        (Options, Switch => GPR2.Options.P, Param => Project_File);

      if Tree.Load
           (Options              => Options,
            With_Runtime         => True,
            Artifacts_Info_Level => GPR2.Sources_Units,
            Check_Drivers        => False)
      then
         null;  --  Project loaded successfully

      elsif Tree.Is_Defined and then Tree.Has_Messages then
         for Message of Tree.Log_Messages.all loop
            Append_Error (Errors, Message.Format (Full_Path_Name => True));
         end loop;
      else
         Append_Error (Errors, "unable to load project file: " & Project_File);
      end if;

   exception
      when E : others =>
         Append_Error
           (Errors,
            "failed to load project file '"
            & Project_File
            & "': "
            & Ada.Exceptions.Exception_Message (E));
   end Load_Project_Tree;

   procedure Collect_Project_Ada_Sources
     (Tree    : GPR2.Project.Tree.Object;
      Sources : out VSS.String_Vectors.Virtual_String_Vector;
      Errors  : in out VSS.String_Vectors.Virtual_String_Vector)
   is
      Result : Source_Sets.Set;

      procedure Add_Sources_From_View (View : GPR2.Project.View.Object);

      procedure Add_Sources_From_View (View : GPR2.Project.View.Object) is
         Project_Sources : constant GPR2.Build.Source.Sets.Object :=
           View.Sources;
         use type GPR2.Language_Id;
      begin
         for Source of Project_Sources loop
            if Source.Language = GPR2.Ada_Language
              and then Source.Path_Name.Has_Value
            then
               Result.Include
                 (VSS.Strings.Conversions.To_Virtual_String
                    (String (Source.Path_Name.Value)));
            end if;
         end loop;
      end Add_Sources_From_View;

   begin
      Sources.Clear;

      --  Process the closure of the root project, including aggregated
      --  libraries and projects that they might extend.
      for View of
        Tree.Root_Project.Closure
          (Include_Self       => True,
           Include_Extended   => True,
           Include_Aggregated => True)
      loop
         if not View.Is_Runtime then
            Add_Sources_From_View (View);
         end if;
      end loop;

      for File_Name of Result loop
         Sources.Append (File_Name);
      end loop;

   exception
      when E : others =>
         Append_Error
           (Errors,
            "failed to collect project sources: "
            & Ada.Exceptions.Exception_Message (E));
   end Collect_Project_Ada_Sources;

   procedure Load
     (Project_File     : VSS.Strings.Virtual_String;
      Tree             : in out GPR2.Project.Tree.Object;
      Analysis_Context : in out Libadalang.Analysis.Analysis_Context;
      Sources          : out VSS.String_Vectors.Virtual_String_Vector;
      Errors           : in out VSS.String_Vectors.Virtual_String_Vector)
   is
      Path : constant String :=
        VSS.Strings.Conversions.To_UTF_8_String (Project_File);
   begin
      Sources.Clear;

      if Project_File.Is_Empty then
         Append_Error (Errors, "project file path is empty");
         return;
      end if;

      if not Ada.Directories.Exists (Path) then
         Append_Error (Errors, "project file does not exist: " & Path);
         return;
      end if;

      if Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File then
         Append_Error (Errors, "project path is not a file: " & Path);
         return;
      end if;

      Load_Project_Tree (Path, Tree, Errors);

      if not Errors.Is_Empty then
         return;
      end if;

      Collect_Project_Ada_Sources (Tree, Sources, Errors);

      if not Errors.Is_Empty then
         return;
      end if;

      begin
         Analysis_Context :=
           Libadalang.Analysis.Create_Context_From_Project (Tree);
      exception
         when E : others =>
            Append_Error
              (Errors,
               "failed to initialize analysis context for '"
               & Path
               & "': "
               & Ada.Exceptions.Exception_Message (E));
      end;
   end Load;

end Munin.Project_Loading;
