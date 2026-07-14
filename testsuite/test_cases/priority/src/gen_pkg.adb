--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with Readers;

package body Gen_Pkg is

   package My_Readers is new Readers (Priority);

   procedure Dummy is null;

end Gen_Pkg;
