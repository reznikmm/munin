--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

with System;

generic
   Priority : System.Priority;
package Readers is

   task Reader
     with
       Priority => Priority,
       Storage_Size => 1536;

end Readers;
