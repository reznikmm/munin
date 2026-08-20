# Munin

[![Build with Alire](https://github.com/reznikmm/munin/actions/workflows/alire.yml/badge.svg)](https://github.com/reznikmm/munin/actions/workflows/alire.yml)
[![Alire](https://img.shields.io/endpoint?url=https://alire.ada.dev/badges/munin.json)](https://alire.ada.dev/crates/munin.html)
[![REUSE status](https://api.reuse.software/badge/github.com/reznikmm/munin)](https://api.reuse.software/info/github.com/reznikmm/munin)

> A lightweight developer companion for embedded Ravenscar applications.

WORK IN PROGRESS!

## Usage

Point Munin at a project's `.gpr` file and pick what to report:

```bash
munin show priorities -P my_project.gpr
munin show callgraph  -P my_project.gpr
munin show cycles     -P my_project.gpr
```

`show priorities` lists every discovered task and protected object with its
resolved priority (see [Priority Resolution](#priority-resolution) below).

`show callgraph` prints the call tree rooted at every task body and main
subprogram, read from GCC's `-fcallgraph-info=su,da` output. Build the
project with that switch first, e.g.:

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
body or the main subprogram, derived from the same `-fcallgraph-info=su,da`
output as `show callgraph`.

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
