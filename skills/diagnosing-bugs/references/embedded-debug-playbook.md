# Embedded Debug Playbook

Use only the sections relevant to the observed failure. Vendor register names and tool commands vary; verify them against the exact architecture, silicon revision, RTOS, compiler, and probe documentation.

## Contents

- Build and link failures
- Undefined behavior and optimisation interaction
- Faults, exceptions, and resets
- Stack, heap, and memory corruption
- RTOS, interrupts, races, and deadlocks
- Timing, performance, and intermittent failures
- Drivers, peripherals, DMA, and cache
- Communication protocols
- Wireless and network stacks
- Low-power modes and wake-up failures
- Bootloader, IAP/OTA, and the boot chain
- Logging, assertions, and field evidence
- Soft/hardware boundary checklist
- Appendix A: non-Cortex-M fault-state equivalents
- Appendix B: tool quick reference

## Build and link failures

Capture the complete command and first causal diagnostic, not only the final build-system error.

**Compile:** inspect preprocessed output, include resolution, generated headers, target macros, language mode, ABI flags, packing/alignment, warnings, optimisation, aliasing assumptions, and C/C++ linkage. Compare the failing translation unit's real flags with a working one.

**Link:** inspect the map file, linker script, memory-region sizes, section placement, discarded sections, undefined and duplicate symbols, weak/strong resolution, static-library order, C++ name mangling, runtime libraries, LTO, and garbage collection. Check vector-table and startup symbol placement, load versus run addresses, and bootloader/application memory contracts.

A link success does not prove layout correctness. Verify stack/heap reservations, retained/no-init data, DMA buffers, execute/read/write permissions, alignment, and image metadata against the boot chain.

## Undefined behavior and optimisation interaction

When a bug appears only at a higher optimisation level, disappears when logging is added, or moves when unrelated code changes, suspect undefined behavior or a memory-layout dependency before suspecting the compiler.

Standard sequence for "only fails at -O2/-Os":

1. Diff the failing and working build flags completely, including defines and LTO.
2. Run the portable part on the host with UBSan and ASan; fix every report before continuing, even ones that look unrelated.
3. Bisect by translation unit: lower optimisation one file at a time (or use per-function optimisation attributes) to isolate the sensitive TU, then the function.
4. Compare the disassembly of the sensitive function across optimisation levels; identify which load, store, or check the optimiser removed or reordered, and ask what language rule allowed it.

Common causes to audit explicitly:

- strict-aliasing violations from casting between unrelated pointer types (buffer-to-struct casts in protocol code are the classic case); use `memcpy` or unions per the dialect's rules;
- missing `volatile` on memory-mapped registers or ISR-shared flags — and the converse: `volatile` used where atomicity or ordering (barriers, atomics) is actually required;
- signed integer overflow, shifts wider than the type, and out-of-bounds indexing that the optimiser exploits to delete "impossible" branches;
- reading uninitialised locals, dangling pointers to expired stack frames, and misaligned accesses hidden by lenient hardware at low optimisation;
- data placement shifts: a latent overflow that only corrupts something important after the linker rearranges sections. Compare map files across the two builds.

An actual compiler bug is the last hypothesis, and it requires a minimal reproducer plus a disassembly showing emitted code that contradicts defined behavior.

## Faults, exceptions, and resets

Preserve the first fault before resetting or letting handlers overwrite evidence.

For Cortex-M-class faults, normally capture the stacked general registers, xPSR, PC, LR, active stack pointer, exception-return value, configurable fault status, hard-fault status, fault addresses when valid, interrupt state, and reset reason. Decode addresses with the exact unstripped ELF and load address. Verify whether the frame is basic or extended and whether stacking itself faulted. Do not blindly dereference reported fault addresses unless their validity bits make them meaningful. On cores exposing them, preserve the raw `HFSR`/`CFSR` value and relevant `MMFAR`/`BFAR` validity bits; distinguish `FORCED`, precise versus imprecise bus faults, stacking/unstacking faults, and an exception raised inside the fault handler. Use `EXC_RETURN` to select the stacked MSP/PSP and account for an extended FPU frame; do not infer these fields from a formatted log after the handler has modified them.

Then test common mechanisms:

- invalid branch/return address or corrupted exception frame;
- precise versus imprecise bus fault;
- unaligned or illegal access;
- divide/undefined instruction trap;
- MPU/MMU permission or translation fault;
- stack overflow or invalid SP;
- interrupt vector, priority, or handler mismatch;
- fault escalation after a disabled or unhandled configurable exception;
- watchdog, brownout, lockup, or external reset misreported as a software crash.

On other cores, collect the architecture-equivalent exception syndrome, fault address, privilege/mode, stack frame, core ID, and MMU/MPU state. Never apply Cortex-M register interpretations by analogy.

## Stack, heap, and memory corruption

Separate task stack, interrupt/main stack, exception nesting, heap, fixed pools, DMA memory, shared memory, and persistent memory.

**Stack:** inspect bounds, canaries or fill pattern, high-water marks, worst-case call paths, local arrays, recursion, library stack use, FPU/context frames, interrupt nesting, and stack alignment. A healthy sampled watermark is not proof against a transient overwrite. Reproduce with production optimisation and representative interrupts.

**Bounds/corruption:** use host sanitizers or fuzzing for portable code, then target watchpoints, MPU guards, canaries, ownership checks, and precise event records. Suspect the writer before the location where corrupted data is consumed. Audit integer overflow, length conversion, packing, alignment, lifetime, aliasing, DMA ownership, and cache visibility.

**Leak/exhaustion:** distinguish true lost allocations from fragmentation, pool exhaustion, queue/object leakage, retained references, and legitimate high-water growth. Record allocation site or owner, outstanding count/bytes, failure count, largest free block where meaningful, and behavior across reconnect/reset/error paths. Avoid adding a heavy allocator tracer whose memory or locking changes the failure.

## RTOS, interrupts, races, and deadlocks

Capture a coherent snapshot when possible: task state, priority, stack bounds, wait object, timeout, mutex owner, queue counts, scheduler state, active interrupts, and recent context-switch or ISR events.

Check:

- ISR-safe API use and interrupt-priority rules (for example, the RTOS's `FromISR` variants and the configured maximum syscall interrupt priority; names and semantics are port-specific);
- shared state protected across task/ISR/core contexts;
- atomicity, memory barriers, and cache coherency, not merely `volatile`;
- critical-section duration and nesting;
- lost wakeups, missed notifications, queue/stream-buffer/notification saturation, and timeout races;
- mutex ownership, recursive use, lock order, and priority inheritance;
- priority inversion, starvation, livelock, and a high-priority busy loop;
- calling blocking, allocating, logging, or non-reentrant code from an ISR;
- object deletion or reuse while another context still references it;
- multicore affinity, inter-core interrupts, and publication ordering.

For deadlocks, build a wait-for graph from observed owners and waiters. For races, seek the first invariant violation and record event ordering; a debugger that halts one or all cores may remove the race.

## Timing, performance, and intermittent failures

Define the actual constraint: deadline, jitter, interrupt latency, execution time, throughput, bus occupancy, startup time, or power-state transition. Record min/max/percentiles or a bounded worst case, not only averages.

Use target cycle counters, trace, timer capture, GPIO markers, logic analyzer, oscilloscope, or bus analyzer as appropriate. State clock source, resolution, wrap behavior, synchronisation, probe loading, and measurement overhead.

For intermittent failures, preserve a baseline reproduction rate before perturbation. Report exposure (frames, transactions, iterations, or device-hours), run count, duration, environment, and an acceptance threshold; zero failures in a short run is not proof of absence. Sweep one factor at a time: input rate, interrupt phase, task priority, clock, voltage, temperature, compiler optimisation, memory placement, bus load, or power cycling. Randomise or deliberately scan timing phases rather than inserting arbitrary sleeps and declaring victory.

Use event-sequence ring buffers and fault-triggered freeze to retain pre-failure history. Treat "failure disappeared under logging/debugger" as evidence of a timing, memory-layout, or observer-effect dependency, not as a fix.

## Drivers, peripherals, DMA, and cache

Debug from the boundary inward:

1. Verify board/silicon revision, supply rails, reset, clock tree, pin mux, electrical levels, pull configuration, and peripheral ownership.
2. Compare configuration registers with the reference manual while accounting for reset values, reserved bits, write-one-to-clear and read-to-clear behavior, shadow registers, and required access sequences.
3. Check status/error flags before clearing them, interrupt enable/pending/priority/routing, and handler acknowledgment order.
4. Validate DMA descriptor lifetime, address, width, count, alignment, circular/double-buffer/wrap behavior, ownership transfer, completion/error paths, and accessibility of the chosen memory region. For UART-like receivers, correlate DMA write position/remaining count with IDLE, half-transfer, transfer-complete, FIFO, and overrun/error flags; snapshot head/tail indices atomically before clearing flags.
5. On cached systems, verify clean/invalidate direction and range, cache-line alignment, barriers, coherency domain, and whether descriptors and payloads require different treatment. First establish that the exact core and memory region actually have a data cache and are reachable by the DMA master; do not prescribe cache maintenance to a non-cached part. Keep descriptor ownership and payload visibility as separate hypotheses.
6. Confirm peripheral and DMA operations are ordered around enable/disable/reset and low-power transitions.
7. Correlate firmware events with external waveforms or bus captures. Software status alone cannot prove that a signal reached the pin or met electrical timing.

Check the exact silicon errata before inventing a software workaround. A probe read can alter state; preserve raw register snapshots and note read side effects.

## Communication protocols

Separate layers so evidence localises the failure:

- physical/electrical signal and clock;
- framing, bit/byte order, sampling, arbitration, and error counters;
- length, escaping, CRC/checksum, sequence number, timeout, and retransmission;
- parser bounds and malformed-input behavior;
- connection/session/state-machine transitions;
- application semantics and persistent state.

Capture raw bytes with timestamps and direction before decoded summaries. Preserve errors and gaps. Record the protocol's CRC polynomial, width, initial value, reflection, final XOR, byte order, and independent golden vectors; "CRC mismatch" alone does not identify a framing or implementation fault. Replay captures through the production parser on the host when portable, fuzz malformed/truncated/duplicated/reordered frames, and validate again on target for timing and driver behavior. For UART, inspect baud-clock error, FIFO and framing/parity/noise/overrun flags; for CAN-like buses, inspect controller error counters, last-error status, ACK/bus-off state, arbitration, and termination before blaming application payload CRC. Differentially compare known-good hardware, firmware, configuration, or peer implementation when available.

## Wireless and network stacks

Apply the same layer separation, but get the stack's own diagnostics before instrumenting application code: disconnect/abort reason codes, stack event logs, and an over-the-air or on-wire capture (BLE sniffer, Wi-Fi monitor mode, or PCAP at the peer) usually localise the failure faster than firmware logs.

**BLE:** record the disconnect reason from the controller (supervision timeout, MIC failure, LMP timeout, remote-terminated) — each implicates a different layer. Check connection interval/latency/supervision-timeout negotiation, MTU and data-length extension results versus assumptions in the profile code, pairing/bonding state machine and key storage across resets, and ATT queue depth. Supervision timeouts under load implicate scheduling (radio time-slicing with Wi-Fi coexistence, long ISRs, flash writes blocking the link layer) before RF.

**Wi-Fi:** capture the disassociation/deauthentication reason code and distinguish driver-initiated from AP-initiated. Separate RF/roaming problems (RSSI, channel, retries) from supplicant state (auth/assoc/4-way handshake step reached) from IP layer (DHCP, ARP, gateway loss). Beacon loss and power-save interaction is a common false "random disconnect".

**Embedded IP stacks (lwIP-class):** most "random drops" are resource exhaustion, not RF: check pbuf/pool and socket/PCB counts, netconn/netbuf leaks on error paths, and whether callbacks run in the stack's context with its locking rules honoured (`tcpip_thread`-only APIs called from other tasks or ISRs). Verify timeouts, retransmission counters, and window behavior from a PCAP before touching application code.

**WebSocket/TLS sessions:** half-open connections survive silently until a write fails — verify keepalive/ping-pong policy and who detects death first. On TLS failures, capture the alert code and check certificate time validity against the device's actual RTC, entropy source quality, and session resumption behavior across device resets. Fragmented/coalesced frames across TCP segment boundaries are a standard parser bug: fuzz the reassembly path on the host.

For any wireless failure, record RSSI/link quality, coexistence configuration, and antenna/board environment alongside the software evidence; correlate failure times against radio activity before assuming a protocol defect.

## Low-power modes and wake-up failures

Treat every sleep entry/exit as a state transition with an explicit contract: which clocks, regulators, RAM banks, peripheral states, and pin states survive, and which must be reconfigured on wake. Most wake failures are a violated assumption in that contract.

- **Fails to wake:** verify the wake source end-to-end — the interrupt/event is enabled *and* routed in the mode actually entered (deeper modes progressively disable sources; EXTI/wake-up-pin routing differs from normal interrupt routing), the pending flag is cleared before sleep entry (a stale pending event either blocks re-arming or causes instant wake), and no race exists between the sleep decision and a wake event arriving in the window before WFI/WFE.
- **Wakes but misbehaves:** after deep sleep, the clock tree, PLL, flash wait states, peripheral registers, and pin mux may be at reset defaults while the code assumes runtime configuration. Faults immediately after wake often come from touching a peripheral whose clock gate is off — a bus fault on a peripheral address right after resume is a clock/power-domain gate until proven otherwise.
- **Retention:** confirm which RAM banks and register sets are actually retained in the specific mode, that retained variables are placed in the retained region by the linker script, and that no-init sections are not zeroed by startup code on wake-from-reset-style resumes.
- **Tickless RTOS:** check timer wrap and compensation math, the maximum suppressed-tick interval, and drift between the low-power clock source and the run-mode clock; missed or late software timers after sleep implicate this path.
- **Instant re-wake / never sleeps:** enumerate pending interrupt flags and busy peripherals blocking mode entry; many parts silently demote the sleep mode when a blocker exists — verify the mode actually reached, not the mode requested.
- **Evidence:** a current-consumption trace (power analyzer or shunt + scope) is the ground truth for which mode was reached and when wake occurred; correlate it with GPIO markers around sleep entry/exit. Beware that an attached debugger commonly keeps power domains awake and masks or creates these bugs — confirm on a detached target.

## Bootloader, IAP/OTA, and the boot chain

Debug the boot chain as a handoff contract between independently-built images: entry address, vector-table location, memory ownership, peripheral/interrupt state at handoff, and metadata format must match on both sides.

**Application does not start after update:** check in order — image written to the slot the bootloader actually reads; metadata (magic, length, CRC/signature, version) valid and covering the right byte range; vector table offset register (VTOR or equivalent) set to the application base; initial SP/PC in the application's vector table pointing into valid RAM/flash; bootloader disabled its interrupts and de-initialised peripherals before jump (an interrupt firing after the jump but before the application configures its vectors is a classic silent death); linker script base address matching the slot the image runs from, or position-independence actually verified.

**Power-loss atomicity:** an update must be a transaction. Verify write ordering — image fully written and verified *before* the commit/metadata record is written, and the commit record itself is a single atomic unit (one word or one page with CRC), not a multi-write sequence a power cut can tear. Enumerate every interruption point (during erase, during image write, during metadata write, during first boot) and confirm each leaves the device bootable into either the old or new image. Test by cutting power at those points, not by reasoning alone.

**Rollback and trial boots:** if a trial-boot/confirm mechanism exists, verify the confirm is written only after the application proves health, the watchdog is armed across the first boot so a hang triggers rollback, and the rollback counter/state survives resets without being corrupted by the failure it is meant to recover from.

**Versioning and persistent data:** an update that boots but misbehaves often read old-schema NV data. Check the settings/calibration schema version, the migration path, and bootloader↔application shared-structure layout (a struct shared by images built at different times needs an explicit versioned format, not a shared header assumption).

**Transport-stage failures:** distinguish download failure (verify received image CRC against the server's), flash-write failure (readback verify, erase-before-write, write-while-erase-suspend rules, writing flash from the same bank code executes from), and verification failure (signature algorithm, key selection, digest coverage — signed bytes versus transmitted bytes).

Field OTA failures deserve their own retained evidence: record the update state machine's last state and error code in retention memory so a bricked-then-recovered unit can report what happened.

## Logging, assertions, and field evidence

Prefer compact fixed-size event records over formatted strings on constrained targets. Include a monotonic timestamp or sequence, event ID, essential arguments, execution context, and firmware/build identity. Use a bounded ring and define overwrite/freeze behavior.

Assertions should capture context before entering a controlled safe state or reset. Decide separately for development and production whether to halt, reset, degrade, or continue. Never put side effects inside assertions that may compile out.

Crash storage must be bounded and robust against torn writes and reset loops. Consider retention RAM before flash; if flash is used, bound erase/write frequency and account for power loss and wear. Validate the decoder against known synthetic records. Before trusting a retained ring, check record version, sequence continuity, length, commit marker, CRC, reset-cause snapshot, and whether the fault handler itself could have overflowed or partially written it.

Log transport must have an explicit policy for backpressure. Avoid blocking an ISR or real-time task on UART, semihosting, filesystem, network, or a shared lock. Remove secrets and sensitive payloads from field logs.

## Soft/hardware boundary checklist

Before assigning blame, correlate:

- schematic/net names, BOM substitutions, board rework, and revision;
- silicon revision and errata;
- voltage, clock quality, reset waveform, temperature, and power sequencing;
- debugger/probe connection and halt behavior;
- compiler, linker, libraries, generated code, bootloader, and fuse/option bytes;
- calibration, nonvolatile schema, manufacturing data, and migration path;
- differences between known-good and failing unit, firmware, load, environment, and test equipment.

Use substitution deliberately: swap one known-good board, cable, peer, supply, firmware image, or probe at a time. Record the matrix; repeated swapping without a hypothesis merely moves the uncertainty.

## Appendix A: non-Cortex-M fault-state equivalents

Never apply Cortex-M register interpretations by analogy; collect the architecture's own fault state.

**RISC-V:** on trap, capture `mcause` (interrupt bit + exception code: instruction/load/store access or misaligned, illegal instruction, ecall, page fault), `mepc` (faulting PC), `mtval` (faulting address or offending instruction bits), `mstatus` (privilege, interrupt-enable stack), and `mtvec` mode (direct versus vectored changes what a "wrong handler" looks like). There is no automatic register stacking as on Cortex-M — the frame layout is whatever the trap handler's assembly saved, so decode it from that code, not from an assumed ABI frame. PMP violations report as access faults; check PMP configuration before suspecting a wild pointer.

**Xtensa (ESP32-class):** capture `EXCCAUSE`, `EXCVADDR`, `EPC`, and `PS`; on ESP-IDF, the panic handler and `esp_reset_reason()` already decode most of this — preserve the full panic dump and backtrace text verbatim, and use the exact matching ELF with the IDF monitor/`xtensa-esp32-elf-addr2line` to symbolise. Distinguish genuine exceptions from interrupt-watchdog and task-watchdog resets, and from brownout resets. Note the windowed-register ABI: backtraces can be wrong after stack corruption in ways flat-register architectures do not exhibit.

On any architecture, additionally record the reset/trap reason register, the active privilege level and stack pointer, and which core faulted on multicore parts.

## Appendix B: tool quick reference

Adjust triple/tool names to the toolchain in use; these are the common GNU forms.

**Symbolise an address** (fault PC, LR, stacked return addresses):

```
arm-none-eabi-addr2line -e app.elf -f -C -i 0x0800a3c2
```

`-i` shows inlined frames — without it an inlined callee is misattributed to its caller.

**Disassemble around a fault site:**

```
arm-none-eabi-objdump -d -S -C app.elf --start-address=0x0800a380 --stop-address=0x0800a400
```

**Inspect layout:** `arm-none-eabi-nm --size-sort -C app.elf` for symbol sizes; `arm-none-eabi-readelf -S app.elf` for section addresses; in the map file, verify which object claimed a symbol and where stack/heap regions landed.

**Decode a stacked exception frame by hand (Cortex-M):** from the active SP at fault entry, the words are R0, R1, R2, R3, R12, LR, PC, xPSR (plus FPU registers if the frame is extended per `EXC_RETURN`). The stacked PC/LR are the primary evidence; symbolise both.

**Non-halting inspection with a probe** (read memory/registers without stopping the core, when supported):

```
pyocd cmd -t <target> -c "read32 0xE000ED28 4"      # CFSR/HFSR area on Cortex-M
openocd ... -c "mdw 0x20000000 16"
```

Confirm first whether attach halts the core on this probe/target configuration, and remember reads of read-to-clear registers are destructive.

**GDB against a live or dumped target:** `arm-none-eabi-gdb app.elf`, then `target extended-remote :3333` (probe server) — `bt`, `info registers`, `x/8wx $sp`. For RTOS-aware views, prefer the probe/IDE's thread-aware plugin so per-task stacks decode correctly.

**Host-side checks for portable code:** build the parser/logic with `-fsanitize=address,undefined -g -O2` and replay captured inputs; run golden-vector CRC checks on host before debugging CRC on target.

