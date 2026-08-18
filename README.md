# Munin

[![Build with Alire](https://github.com/reznikmm/munin/actions/workflows/alire.yml/badge.svg)](https://github.com/reznikmm/munin/actions/workflows/alire.yml)
[![Alire](https://img.shields.io/endpoint?url=https://alire.ada.dev/badges/munin.json)](https://alire.ada.dev/crates/munin.html)
[![REUSE status](https://api.reuse.software/badge/github.com/reznikmm/munin)](https://api.reuse.software/info/github.com/reznikmm/munin)

> A lightweight developer companion for embedded Ravenscar applications.

WORK IN PROGRESS!

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

## Running Tests

From the repository root, run:

```bash
alr test
```
