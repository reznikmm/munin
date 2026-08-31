--  SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
--
--  SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
--
--  Sample Ada source exercising the priority-ceiling-locking protocol
--  (Ada RM D.3), used as the "under test" project for Munin's
--  priority-check testcase. This source is analyzed by Munin (via
--  Libadalang and its `.ci` call graph); it is not executed.

package Priority_Check_Sample is

   --  Direct violation: High_Task's own priority (10) exceeds
   --  Low_Ceiling's ceiling (5).
   protected Low_Ceiling with Priority => 5 is
      procedure Op;
   end Low_Ceiling;

   task High_Task with Priority => 10;

   --  Nested violation: Nested_Task's own priority (3) is fine for
   --  High_Ceiling (20), but entering High_Ceiling raises the active
   --  priority to 20 -- which then exceeds Nested_Low's ceiling (8) when
   --  High_Ceiling calls into it.
   protected High_Ceiling with Priority => 20 is
      procedure Enter_Nested;
   end High_Ceiling;

   protected Nested_Low with Priority => 8 is
      procedure Op;
   end Nested_Low;

   task Nested_Task with Priority => 3;

   --  Clean case: Clean_Task's priority (10) never exceeds Consistent's
   --  ceiling (15) -- no violation.
   protected Consistent with Priority => 15 is
      procedure Op;
   end Consistent;

   task Clean_Task with Priority => 10;

   --  Default-priority fallback: neither Default_Task nor Default_Object
   --  has an explicit priority, so both fall back to the runtime's
   --  System.Default_Priority / System.Priority'Last -- which never
   --  violate each other.
   protected Default_Object is
      procedure Op;
   end Default_Object;

   task Default_Task;

end Priority_Check_Sample;
