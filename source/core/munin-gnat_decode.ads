--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
------------------------------------------------------------------

--  Best-effort demangling of a GNAT linker symbol into a readable,
--  dotted, conventionally-cased Ada name, via the runtime's own
--  __gnat_decode -- the same routine GNAT.Traceback.Symbolic and
--  System.Object_Reader's Decoded_Ada_Name use to produce symbolic
--  exception tracebacks. Display-only: __gnat_decode collapses
--  overloaded/homonym symbols to the same decoded name, and never
--  recovers the original source casing (GNAT's symbol table doesn't
--  keep it -- Decode's own Mixed_Case re-casing is a convention, not a
--  recovery of the real spelling), so it is not exact enough to
--  identify an entity -- see Munin.Contexts.Task_Priority, which
--  matches by declaration Position instead.

with VSS.Strings;

package Munin.Gnat_Decode is

   function Decode
     (Symbol : VSS.Strings.Virtual_String) return VSS.Strings.Virtual_String;
   --  Symbol, demangled, with "__" package/scope separators rendered as
   --  "." and every word (Symbol'First, and each character right after a
   --  "_" or ".") upper-cased, every other letter lower-cased -- e.g.
   --  "pkg__high_taskTKB" decodes to "Pkg.High_TaskTKB". Any
   --  compiler-generated suffix __gnat_decode doesn't recognize (e.g.
   --  some task/protected object init-procedure symbols) is left
   --  attached verbatim, re-cased the same way as everything else.
   --  "main" (the environment task's C symbol) decodes to "Main" --
   --  Decode re-cases unconditionally, whether or not Symbol turns out
   --  to be a real mangled Ada name.

end Munin.Gnat_Decode;
