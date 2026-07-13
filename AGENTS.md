# AGENTS.md

## Purpose

Munin is an Ada tool that scans a `.gpr` project and reports concurrency objects
(tasks and protected objects) with resolved priorities.

## Repository Map

- `source/core/`: Core library logic (`Munin.*` packages)
- `source/cli/`: CLI entry point and command-line integration
- `testsuite/`: Separate test crate and test projects
- `testsuite/test_cases/*`: Embedded crate to be analyzed with the corresponding test case
- `config/`: Build-time configuration artifacts written by Alire (do not edit manually)
- `obj/`, `bin/`: Build outputs (do not edit manually)

## Ground Rules

1. Keep public Core API free of Libadalang types.
2. Prefer `VSS.Strings.Virtual_String` for project-facing string handling.
3. Keep changes focused and minimal; avoid unrelated refactors.
4. Don't introduce extra (sub-)type conversions, like Integer to Natural.
5. Preserve existing style and naming conventions in nearby code. Don't use abbreviations.

## Build And Test Commands

Run from repository root unless noted otherwise.

- Compile/check one file (`<unit>.adb`):
  - `alr exec -- gprbuild -q -f -c -u -gnatc -P munin.gpr <unit>.adb '-cargs:ada' -gnatef`
- Build project:
  - `alr build`
- Run main tests:
  - `testsuite/run.sh`
- Build testsuite crate:
  - `alr -C testsuite/ build -- -j3`
- Build test cases crate:
  - `alr -C testsuite/test_case build`

## Change Workflow For Agents

1. Read relevant package spec/body before editing. Read `*.adb` only if reading of corresponding `*.ads` is not enough.
2. Implement the smallest viable patch.
3. Re-run compile check for touched units.
4. Run targeted runtime/test command when behavior changes.
5. Report exactly what changed and what was validated.

## Ada-Specific Notes

- Use predefined Ada container packages compatible with this toolchain
  (for example, `Ada.Containers.Hashed_Sets`).
- Keep code compatible with project language settings (avoid Ada 2022-only syntax
  unless the project is explicitly configured for it).
- If static evaluation assumptions change (priority extraction), ensure error
  paths remain explicit and user-readable.

## Output And Error Handling Expectations

- Diagnostics should be actionable and include path/context when possible.
- Avoid duplicate reporting for the same discovered source/declaration.
- Preserve CLI output format unless explicitly requested to change it.

## When Unsure

- Prefer conservative changes.
- Ask for clarification before large architectural rewrites.
- Document assumptions in the final update.
