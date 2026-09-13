--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  A task calling into every protected object of Lock_Check_Sample, kept
--  in its own unit rather than declared in Lock_Check_Sample itself: a
--  library-level task's activation happens as part of its own package
--  body's elaboration, so a task calling back into protected objects
--  declared in that very same package creates a circular elaboration
--  dependency that GNAT's static elaboration model rejects outright.
--  Depending on Lock_Check_Sample instead, rather than sharing its
--  package, elaborates it first and avoids the cycle.

package Lock_Check_Driver is

   task Driver;

end Lock_Check_Driver;
