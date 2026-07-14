--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  Main procedure for the priority testcase application.
--  Withing Priority_Sample causes its task and protected object to be
--  elaborated. This application targets the RP2040 (light-tasking runtime)
--  and is analyzed by Munin rather than executed on a host machine.

with Priority_Sample;
pragma Unreferenced (Priority_Sample);

with Gen_Pkg;
pragma Unreferenced (Gen_Pkg);

with Readers_24;
pragma Unreferenced (Readers_24);

procedure Priority is
begin
   null;
end Priority;
