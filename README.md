# Munin

[![Build with Alire](https://github.com/reznikmm/munin/actions/workflows/alire.yml/badge.svg)](https://github.com/reznikmm/munin/actions/workflows/alire.yml)
[![Alire](https://img.shields.io/endpoint?url=https://alire.ada.dev/badges/munin.json)](https://alire.ada.dev/crates/munin.html)
[![REUSE status](https://api.reuse.software/badge/github.com/reznikmm/munin)](https://api.reuse.software/info/github.com/reznikmm/munin)

> A lightweight developer companion for embedded Ravenscar applications.

WORK IN PROGRESS!

## Usage

Point Munin at a project's `.gpr` file and pick what to report:

```bash
munin show priorities  -P my_project.gpr
munin show callgraph   -P my_project.gpr
munin show cycles      -P my_project.gpr
munin show interrupts  -P my_project.gpr
munin show stack       -P my_project.gpr
munin check priorities -P my_project.gpr
munin check locks      -P my_project.gpr
```

`show priorities` lists every discovered task and protected object with its
resolved priority (see [Priority Resolution](#priority-resolution) below).

`show interrupts` lists every discovered interrupt handler procedure (see
[Interrupt Handler Recognition](#interrupt-handler-recognition) below), its
owning protected object, and that object's resolved priority -- the priority
the handler actually runs at, per Ada RM C.3.1.

`show callgraph` prints the call tree rooted at every task body, main
subprogram, and interrupt handler procedure, read from GCC's
`-fcallgraph-info=su,da` output. Build the project with that switch first,
e.g.:

```ada
package Compiler is
   for Switches ("Ada") use Compiler'Switches ("Ada")
     & ("-fcallgraph-info=su,da");
end Compiler;
```

If no `.ci` file is found, Munin reports this and explains how to enable it.

`show cycles` reports every group of mutually-recursive subprograms --
either two or more subprograms forming a strongly connected component, or
a single subprogram that calls itself directly -- reachable from a task
body, the main subprogram, or an interrupt handler procedure, derived from
the same `-fcallgraph-info=su,da` output as `show callgraph`.

`show stack` reports the worst-case stack usage of every task, the
environment task, and every interrupt handler: its own static stack usage
plus the maximum over all of its (recursively resolved) callees, walking
the same `-fcallgraph-info=su,da`-derived call graph as the other `show`/
`check` commands. A root whose call graph reaches a recursive cycle is
flagged -- the reported figure is then a lower bound, not the true worst
case, since the cycle's own contribution can't be statically bounded. A
root that reaches an indirect call (through a pointer) or a dynamic
(heap/secondary-stack) allocation is flagged too, for the same reason:
neither contributes to the reported figure, so the true worst case may be
higher. Munin does not check this figure against anything -- there's no
declared "this task's stack must fit in N bytes" budget in the source to
check it against -- it only reports the number; compare it yourself
against your runtime's actual stack allocation for the object.

`check priorities` checks the Ada RM D.3 priority-ceiling-locking protocol:
for every task and interrupt handler, it tracks the active priority it runs
at as it walks the call tree (raised to a protected object's ceiling on
entry, and back down again on return), and reports every protected
operation reachable at a priority higher than its object's ceiling --
exactly the condition that raises `Program_Error` at run time. Also derived
from `-fcallgraph-info=su,da` output, and from the same priority resolution
described below, falling back to `System.Default_Priority`/
`System.Priority'Last` for a task or protected object with no explicit
priority.

`check locks` reports every protected object called back into while a task
is already inside one of its own operations, reached through some other
subprogram rather than a direct call between two of the object's own
operations -- exactly the condition that deadlocks (or raises
`Program_Error`) at run time, since a protected object's lock is not
reentrant for a call arriving that way. A direct call from one operation of
a protected object straight to another operation of the *same* object is
an internal call (Ada RM 9.5.1) and is always safe, no matter how many
such calls chain together; only a path that leaves the object's own
operations -- through an ordinary subprogram, or through an operation of
some *other* protected object -- and then comes back is flagged. Also
derived from `-fcallgraph-info=su,da` output.

## Priority Resolution

Munin resolves the `Priority`/`Interrupt_Priority` of every discovered task
and protected object, however it is expressed:

1. **Aspect on the declaration** — a static or target-dependent expression
   given directly on the task/protected (type) declaration:

   ```ada
   protected Shared_Register with Priority => 20 is ...
   task Interrupt_Task with Interrupt_Priority => System.Interrupt_Priority'First;
   ```

2. **Generic formal parameter** — the aspect expression names a generic
   formal, resolved per instantiation:

   ```ada
   generic
      Priority : System.Priority;
   package Readers is
      task Reader with Priority => Priority;
   end Readers;

   package Readers_24 is new Readers (Priority => 24);
   ```

3. **Discriminant** — the aspect expression names a discriminant of the
   task/protected type, resolved per object using that object's actual
   discriminant value:

   ```ada
   protected type Accumulator (Pr : System.Any_Priority) with Priority => Pr is ...

   Acc_10 : Accumulator (Pr => 10);
   Acc_11 : Accumulator (11);
   ```

4. **Pre-aspect pragma** — the older `pragma Priority (...)`/
   `pragma Interrupt_Priority (...)` form, recognized the same way as the
   aspect syntax:

   ```ada
   protected Pragma_Register is
      pragma Priority (22);
      ...
   end Pragma_Register;
   ```

## Concurrency Object Recognition

Besides task/protected (type) declarations and library-level objects of a
named task/protected type, Munin also recognizes an object of a **private
type whose full view is implemented as protected or task**, such as
`Ada.Synchronous_Task_Control.Suspension_Object`:

```ada
with Ada.Synchronous_Task_Control;

Ready : Ada.Synchronous_Task_Control.Suspension_Object;
```

Only the object (`Ready`) is reported, never the private type itself. Since
the implementation lives in the runtime and isn't visible from the
analyzed source, its priority is reported as `(Default)`.

## Interrupt Handler Recognition

Munin finds every protected procedure registered as an interrupt handler,
however it is declared:

1. **Modern aspect** -- `Attach_Handler` (statically attached to a given
   interrupt) or the valueless `Interrupt_Handler` (available for dynamic
   attachment at run time via `Ada.Interrupts.Attach_Handler`):

   ```ada
   protected Interrupt_Controller
     with Interrupt_Priority => System.Interrupt_Priority'Last
   is
      procedure Handle with Attach_Handler => Ada.Interrupts.Interrupt_ID'First;
   end Interrupt_Controller;
   ```

2. **Pre-aspect pragma** -- the older `pragma Attach_Handler (...)`/
   `pragma Interrupt_Handler (...)` form, recognized the same way as the
   aspect syntax.

An interrupt handler is invoked by the runtime directly, with no static
caller of its own -- exactly like a task body -- so Munin treats it as an
extra root alongside every task when walking the call tree: `show
callgraph`, `show cycles`, `show stack`, and `check priorities` all reach
it and whatever it calls, not just the object's own operations.

Note the Ravenscar/Jorvik profile's `No_Dynamic_Attachment` restriction
forbids the valueless `Interrupt_Handler` aspect outright -- only
`Attach_Handler` (aspect or pragma) is actually usable under it.

## Effectively Global Locals

In a Ravenscar/Jorvik program, tasks never terminate, and the environment
task waits for all of them before the partition completes (RM 10.2). So an
object declared in the main subprogram's own first declarative section, or
in a task's own first declarative section, is elaborated exactly once and
lives for the whole program — exactly like a library-level object. Munin
reports such objects too, under their own (nested) name, never the
enclosing task/subprogram itself.

Ravenscar/Jorvik's `No_Task_Hierarchy` and `No_Local_Protected_Objects`
restrictions mean a task or protected object can never actually be
declared this way — but an object of a private type whose full view is
protected, such as `Ada.Synchronous_Task_Control.Suspension_Object`, is
just an ordinary object declaration and isn't restricted, so this is the
pattern that occurs in practice:

```ada
task body Telemetry is
   Local_Ready : Ada.Synchronous_Task_Control.Suspension_Object;
begin
   ...
end Telemetry;

procedure Main is
   Main_Ready : Ada.Synchronous_Task_Control.Suspension_Object;
begin
   ...
end Main;
```

Both `Telemetry.Local_Ready` and `Main.Main_Ready` are reported, alongside
every other discovered task and protected object.

## Running Tests

From the repository root, run:

```bash
alr test
```
