--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

with Ada.Directories;

with GPR2;
with GPR2.Project.View;

with VSS.Characters;
with VSS.Characters.Latin;
with VSS.Strings.Conversions;
with VSS.Text_Streams.File_Input;

with Munin.Call_Graph_Providers.CI_Extra_Data;

package body Munin.Call_Graph_Providers.CI is

   use type VSS.Strings.Virtual_String;

   LF : constant VSS.Characters.Virtual_Character :=
     VSS.Characters.Latin.Line_Feed;

   procedure Add_CI_Files_In
     (Directory : String;
      Result    : in out VSS.String_Vectors.Virtual_String_Vector);
   --  Append the `*.ci` files found directly in Directory to Result, if
   --  Directory exists.

   ---------------------
   -- Add_CI_Files_In --
   ---------------------

   procedure Add_CI_Files_In
     (Directory : String;
      Result    : in out VSS.String_Vectors.Virtual_String_Vector)
   is
      procedure Process (Item : Ada.Directories.Directory_Entry_Type);

      procedure Process (Item : Ada.Directories.Directory_Entry_Type) is
      begin
         Result.Append
           (VSS.Strings.Conversions.To_Virtual_String
              (Ada.Directories.Full_Name (Item)));
      end Process;

   begin
      if Ada.Directories.Exists (Directory) then
         Ada.Directories.Search
           (Directory,
            "*.ci",
            [Ada.Directories.Ordinary_File => True, others => False],
            Process'Access);
      end if;
   end Add_CI_Files_In;

   ---------------
   -- Add_Entry --
   ---------------

   procedure Add_Entry
     (Self   : in out CI_Provider;
      Symbol : VSS.Strings.Virtual_String;
      Size   : Natural)
   is
   begin
      Self.DB.Add_Entry (Symbol, Size);
   end Add_Entry;

   ------------------------------
   -- Add_Indirect_Call_Target --
   ------------------------------

   procedure Add_Indirect_Call_Target
     (Self   : in out CI_Provider;
      Caller : VSS.String_Vectors.Virtual_String_Vector;
      Target : VSS.Strings.Virtual_String)
   is
   begin
      Self.DB.Add_Indirect_Call_Target (Caller, Target);
   end Add_Indirect_Call_Target;

   -------------
   -- Callees --
   -------------

   overriding
   function Callees
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array
   is (Self.DB.Callees (Node));

   -------------
   -- Callers --
   -------------

   overriding
   function Callers
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array
   is (Self.DB.Callers (Node));

   -------------------
   -- Find_CI_Files --
   -------------------

   function Find_CI_Files
     (Tree : GPR2.Project.Tree.Object)
      return VSS.String_Vectors.Virtual_String_Vector
   is
      Result : VSS.String_Vectors.Virtual_String_Vector;
   begin
      for View of
        Tree.Root_Project.Closure
          (Include_Self       => True,
           Include_Extended   => True,
           Include_Aggregated => True)
      loop
         if not View.Is_Runtime
           and then View.Kind in GPR2.With_Object_Dir_Kind
         then
            Add_CI_Files_In (View.Object_Directory.String_Value, Result);
         end if;
      end loop;

      return Result;
   end Find_CI_Files;

   -----------
   -- Image --
   -----------

   overriding
   function Image
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is (Self.DB.Image (Node));

   ----------------
   -- Initialize --
   ----------------

   procedure Initialize
     (Self  : in out CI_Provider;
      Tree  : GPR2.Project.Tree.Object;
      Error : out VSS.Strings.Virtual_String)
   is
      Files      : constant VSS.String_Vectors.Virtual_String_Vector :=
        Find_CI_Files (Tree);
      Any_Loaded : Boolean := False;
      Failures   : VSS.String_Vectors.Virtual_String_Vector;
   begin
      Error := VSS.Strings.Empty_Virtual_String;

      if Files.Is_Empty then
         Error :=
           "No `.ci` files found for project '"
           & VSS.Strings.Conversions.To_Virtual_String
               (String (Tree.Root_Project.Name))
           & "'. Build it with GCC's `-fcallgraph-info=su,da` switch, e.g."
           & " add"
           & LF
           & "  package Compiler is"
           & LF
           & "     for Switches (""Ada"") use Compiler'Switches (""Ada"")"
           & " & (""-fcallgraph-info=su,da"");"
           & LF
           & "  end Compiler;"
           & LF
           & "to the project file (or pass"
           & " `-cargs -fcallgraph-info=su,da` to gprbuild), then rebuild.";

         return;
      end if;

      for File_Name of Files loop
         declare
            Stream     : VSS.Text_Streams.File_Input.File_Input_Text_Stream;
            File_Error : VSS.Strings.Virtual_String;
            Warning    : VSS.String_Vectors.Virtual_String_Vector;
         begin
            Stream.Open (File_Name, "utf-8");

            if Stream.Has_Error then
               Failures.Append (Stream.Error_Message & ": " & File_Name);
            else
               Self.DB.Load (Stream, File_Error, Warning);

               if File_Error.Is_Empty then
                  Any_Loaded := True;
               else
                  Failures.Append (File_Error & ": " & File_Name);
               end if;
            end if;
         end;
      end loop;

      if not Any_Loaded then
         Error := "Failed to parse any `.ci` file:";

         for Item of Failures loop
            Error := @ & LF & "  " & Item;
         end loop;

         return;
      end if;

      Self.DB.Complete;
   end Initialize;

   ---------------------
   -- Load_Extra_Data --
   ---------------------

   procedure Load_Extra_Data
     (Self   : in out CI_Provider;
      Path   : VSS.Strings.Virtual_String;
      Errors : out VSS.String_Vectors.Virtual_String_Vector)
   is
   begin
      Munin.Call_Graph_Providers.CI_Extra_Data.Read_JSON
        (Self.DB, Path, Errors);
   end Load_Extra_Data;

   --------------------
   -- Qualified_Name --
   --------------------

   overriding
   function Qualified_Name
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return VSS.Strings.Virtual_String
   is (Self.DB.Qualified_Name (Node));

   --------------
   -- Position --
   --------------

   overriding
   function Position
     (Self : CI_Provider; Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.Optional_Position
   is (Self.DB.Position (Node));

   -------------
   -- Resolve --
   -------------

   function Resolve
     (Self : in out CI_Provider;
      Node : Munin.Call_Graph_Providers.Call_Graph_Node)
      return Munin.Call_Graph_Providers.CI_Databases.Resolve_Result
   is (Self.DB.Resolve (Node));

   -----------
   -- Tasks --
   -----------

   overriding
   function Tasks
     (Self : CI_Provider)
      return Munin.Call_Graph_Providers.Call_Graph_Node_Array
   is (Self.DB.Tasks);

end Munin.Call_Graph_Providers.CI;
