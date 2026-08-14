---
name: diagnosing-bugs
description: Diagnose hard bugs, crashes, hangs, data corruption, and performance or timing regressions across host software and embedded C/C++ systems. Use when Codex must debug compilation or linking failures, MCU/SoC faults, RTOS tasks, interrupts, concurrency, memory corruption or leaks, drivers, DMA/cache issues, communication protocols, hardware interactions, or intermittent field failures.
---

# Diagnosing Bugs

Use evidence to turn an observed symptom into a verified root cause. Skip a phase only with an explicit reason.

Read `CONTEXT.md` and relevant ADRs if present. For firmware, also inspect the target, board revision, toolchain, linker script, memory map, RTOS configuration, startup code, and hardware documents relevant to the failing path.

For firmware, collect this minimum context before forming hypotheses; explicitly list whatever is missing and ask for it rather than guessing:

- exact chip part number and silicon revision;
- toolchain name/version and the optimisation level of the failing build;
- RTOS (or bare-metal) and its configuration;
- linker script and map file, and the unstripped ELF matching the failing image (verify build ID or CRC);
- reset-cause register value from the failing event;
- board revision, rework history, and any BOM substitutions.

## Phase 0 - Protect people, hardware, and evidence

Before reproducing or attaching a debugger:

- Identify hazardous outputs, actuators, high voltage/current, thermal limits, destructive writes, and watchdog or reset behavior. Define a safe test state. Never loop a hazardous failure unattended.
- Preserve the exact failing artifacts: source commit, dirty diff, firmware image, ELF with symbols, map file, build flags, generated configuration, bootloader and persistent-data versions, board and silicon revisions, reset cause, logs, traces, dumps, and probe or instrument setup.
- Do not rebuild, reflash, power-cycle, clear faults, acknowledge read-to-clear registers, or attach a halt-mode debugger until considering whether it destroys evidence or changes hardware state.
- Record whether peripherals, DMA, watchdogs, other cores, or external devices continue while a core is halted.

If evidence is perishable, capture it before attempting a reproduction. When a human operates the hardware, give them an explicit "do not" list first (do not reset, power-cycle, reflash, or read/clear specific status registers) before any capture instructions.

## Phase 1 - Define the signal and evidence path

Write one exact symptom and its verdict. Prefer a numeric or machine-checkable condition: fault PC and status bits, wrong frame bytes, deadline miss, unexpected reset cause, invariant violation, resource watermark, or measured latency. "Did not crash" is too weak.

Choose the strongest available path:

1. **Automated reproduction** - host test, simulator, target script, hardware-in-the-loop rig, captured-input replay, protocol harness, fuzz/property loop, differential test, or automated flash/run/check loop.
2. **Controlled manual reproduction** - a written setup and trigger with captured probe, serial, trace, logic-analyzer, oscilloscope, or power data. Use `scripts/hitl-loop.template.sh` when useful.
3. **Artifact-first diagnosis** - a non-reproducible field failure with enough preserved evidence to test hypotheses: crash record, exception frame, core dump, retained trace, watchdog/reset reason, protocol capture, memory snapshot, or matching ELF and map file.

Do not reject valid embedded evidence merely because it is not fast, deterministic, or agent-runnable. State which path is being used and its limits.

For an automated path, tighten the loop where feasible:

- Assert the exact symptom and drive the real code path.
- Reduce setup and flash time without replacing target-dependent behavior with mocks.
- Pin controllable inputs, time, seeds, configuration, firmware, and hardware revision.
- Report run count and reproduction rate for intermittent failures; do not call a probabilistic result deterministic.

For an artifact-first path, establish provenance before interpreting it:

- Match the dump or addresses to the exact executable and load addresses.
- Treat disassembly of the shipped image as first-class evidence: confirm what the compiler actually emitted at the fault site, and account for inlining and tail calls that distort reconstructed call stacks.
- Distinguish primary-fault evidence from secondary damage after continued execution.
- Record missing, overwritten, optimized-out, or suspect fields.

Read [references/embedded-debug-playbook.md](references/embedded-debug-playbook.md) when the target includes an MCU/SoC, RTOS, ISR, DMA/cache, device driver, communication bus, wireless or network stack, low-power mode, bootloader/OTA update path, custom board, or hardware-dependent failure. Select only the relevant playbook sections.

## Phase 2 - Reproduce or reconstruct, then minimise safely

Confirm the evidence represents the user's failure rather than a nearby failure with a similar symptom.

- For a live repro, repeat enough times to establish a baseline rate and capture the first divergence from known-good behavior.
- For a one-shot failure, reconstruct the event sequence from immutable evidence and label each inference separately from observed facts.
- Minimise inputs, configuration, tasks, interrupt sources, peripherals, and timing conditions one variable at a time.
- Do not minimise away the property under investigation. A host mock cannot prove a target cache, interrupt, electrical, or timing bug.
- Do not inject delays, add logs, change optimisation, halt the core, or disable the watchdog without treating that change as an experiment that may mask or create the bug.

Done when the smallest defensible reproducer or evidence set remains, and its limitations are recorded.

## Phase 3 - Build ranked, falsifiable hypotheses

Generate 3-5 ranked hypotheses before modifying the suspected code. For each, write:

- supporting and contradicting evidence;
- a prediction that distinguishes it from the other hypotheses;
- the cheapest low-intrusion probe that can falsify it;
- the expected observer effect and safety risk.

Use the form: "If X is the cause, then observation or change Y will produce Z; otherwise this hypothesis loses rank."

Rank by evidence, not familiarity. Include software, toolchain, RTOS, hardware, and measurement-system causes when the boundary is not yet known. When the failure depends on optimisation level, build configuration, or "goes away under the debugger", the hypothesis list must include at least one undefined-behavior/toolchain cause, one hardware/electrical cause, and one measurement-system cause before any of them is dismissed. Show the ranked list to the user, then continue unless a decision or physical action requires them.

## Phase 4 - Instrument with an intrusion budget

Change one variable at a time and map every probe to a prediction.

Prefer the least intrusive source that can discriminate hypotheses:

1. Existing crash state, retained events, status registers, trace, bus capture, or external measurements.
2. Hardware trace, data watchpoints, cycle counters, RTOS-aware debugger views, or non-halting inspection.
3. Bounded in-memory event records with monotonic timestamps.
4. Targeted assertions, counters, GPIO markers, or rate-limited logs.
5. Breakpoints or step debugging only after checking halt behavior and timing impact.

For every added probe, record RAM/flash cost, stack use, execution time, blocking behavior, ISR safety, concurrency behavior, and persistence across reset. Never log from an ISR through a blocking or non-reentrant path. Never assume `volatile` provides atomicity or inter-core ordering.

Tag temporary instrumentation with a unique marker such as `[DEBUG-a4f2]`. Keep permanent low-cost diagnostics only when they have an owner, bounded storage, and a defined privacy or safety policy.

For timing and performance failures, measure on the relevant target using an appropriate clock, cycle counter, trace, GPIO pulse, or external instrument. Preserve distributions, worst cases, and load conditions; an average alone can hide deadline failures.

## Phase 5 - Prove root cause, fix, and regress

Do not equate correlation with root cause. A confirmed root cause must explain the observed evidence and predict an intervention that removes the failure without merely hiding it.

Before the fix, capture a failing regression at the closest valid seam:

- host test for portable logic or parsers;
- simulator/emulator where modeled behavior is sufficient;
- target or HIL test for interrupts, RTOS scheduling, DMA/cache, peripheral, timing, or electrical behavior;
- crash-artifact decoder test for field-only exceptions;
- statistical stress test with a stated run count, duration, and acceptance threshold for intermittent failures.

Apply the smallest root-cause fix. Then:

1. Run the minimised regression.
2. Run the original scenario or replay the original artifact through its decoder.
3. Check adjacent modes and error paths.
4. Re-test on the actual target and production optimisation when target behavior matters.
5. Verify timing, stack, memory, power, and binary-size budgets affected by the change.

If no valid regression seam exists, document the evidence and architectural limitation instead of adding a shallow test that gives false confidence.

## Phase 6 - Cleanup and preserve diagnostics

Before declaring completion:

- State the root cause, trigger, failure mechanism, and why the fix works.
- Separate verified facts, remaining assumptions, and residual risk.
- Re-run the original evidence path and relevant regression checks.
- Remove temporary instrumentation and debug-only timing changes; search for its unique marker.
- Preserve useful crash capture, assertions, counters, and tests when their production cost is bounded.
- Record exact firmware/toolchain/hardware versions and commands needed to reproduce or decode the failure.
- Check that diagnostics do not expose secrets, violate safety constraints, wear flash, or create unbounded blocking.
- Put the proven causal explanation in the commit or PR description.

Ask what earlier invariant, assertion, static analysis rule, test, trace point, or architecture boundary could have prevented or shortened the incident. Recommend broader architecture work only after the immediate bug is fixed or explicitly scoped out.

