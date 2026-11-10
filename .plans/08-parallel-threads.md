# Plan: Parallel Java threads

Status: in progress.
Source: user direction after milestone 5 ("threads need to run in parallel, that's the point of Bend").
Supersedes the serialized-execution decision in [plan 05](05-concurrency-and-native-integration.md) ("Memory model: sequentially consistent baseline" and "Bend threads, not host-owned Java stacks").
Dependencies: plan 05 (threads, monitors, scheduler, host effects).

## Goal

Run runnable Java threads at the same time on several CPU cores, using Bend's parallel calls, while keeping every Java-visible behavior that plan 05 delivered.

A CPU-bound program with several threads must finish measurably faster than the same work on one thread, and the speedup must come from Bend evaluating the threads in parallel, not from host workers running Java code.

## Findings that shape the design

- The JavaScript target runs every Bend program sequentially (`bend guide`: "The JavaScript target ignores all that and just runs sequentially").
  BendJVM currently runs as a generated `.mjs` module on Bun, so no scheduler change can make it parallel.
  Parallel calls only use several cores in a native build (`bend file.bend -o binary` or `.c`).
- The native build of `bendjvm/runtime_api.bend` fails today after about 60 minutes with `Error: an arity over 247`.
  The C backend flattens unboxed records into parameter words, and an entry with more than 247 words is rejected.
- The whole JVM state is one immutable `VM` value.
  Threads can read one shared heap snapshot without locks, which is what makes a parallel design cheap to reason about.
- The heap is a positional `+List<HeapEntry>`: a reference is the list position plus one, lookups are linear, and allocation appends.
  Concurrent allocation cannot work with positional ids, and linear lookup dominates run time.
- The host layer lives in JavaScript (`scripts/run.py:host_source`): files, TCP, selectors, TLS through `node:tls`, DNS, timers and the native-helper client.
  The native target has none of that, but it has built-in TCP, file, process, timer and channel effects, and it accepts user effects written in C that wait on file descriptors through the same event loop (`~/.bend/bend2/effs/*.c`).
- OpenSSL 3 is installed (`/opt/homebrew/opt/openssl@3`); a C effect can load `libssl` with `dlopen`, as Bend's own `window.c` does for system libraries.

## Architectural decisions

### Native target only

- BendJVM builds as a native Bend program, and the Bun host is retired.
- `scripts/run.py` stays the command-line front end: it resolves the classpath, compiles the MiniJRE, builds the binary, and starts it.
- The host loop that `host_source` implements in JavaScript moves into Bend (`bendjvm/host/*.bend`) on top of native effects.
- The user approved this choice over a Bun I/O sidecar, which also replaces the earlier Bun TLS approval with OpenSSL.

### Rounds: parallel slices, serial synchronization

Execution proceeds in rounds.

1. Parallel phase: every runnable thread runs a slice of at most `quantum * priority / 5` instructions against the heap snapshot taken at the start of the round.
   A thread sees its own writes, and nobody else's from this round.
   A slice stops early, before executing it, at the first synchronization action.
2. Merge: the threads' write logs are applied to the snapshot in thread-id order.
3. Serial phase: each thread that stopped at a synchronization action executes exactly that action against the merged state, in thread-id order.
   This includes monitor acquisition, which may park the thread exactly as today.
4. Wake pass, host completions and deadlines, as in plan 05.

Synchronization actions:

- `monitorenter`, `monitorexit`, and entry to or return from a `synchronized` method;
- volatile field reads and writes, including through reflection, method handles and `VolatileCallSite`;
- `wait`, `notify`, `notifyAll`, `Thread.start`, `join`, `interrupt`, `isInterrupted`/`interrupted`, `sleep`, `yield`, `setPriority`, and thread termination;
- class initialization state changes, and the first access to a class that is not yet initialized;
- operations on shared VM tables: class loading and linking, string interning, `Class` mirror creation, call-site linkage, and reflection caches;
- host effects (I/O, native calls), which already end a slice today;
- running out of the thread's allocation arena (see below).

Thread scheduling records, monitors and wait sets stay in `Sched` and only change in the serial phase.

### Memory model

This is a Java Memory Model refinement that plan 05 explicitly allowed ("implement a separately justified Java Memory Model refinement").

- Synchronization actions execute in one total order, (round, thread id), consistent with each thread's program order.
- Every write that precedes a release in program order is merged before the serial phase that executes the release, so any thread acquiring afterwards reads in a later parallel phase that starts from a snapshot containing the write.
  Correctly synchronized programs therefore behave as under sequential consistency, which is the JMM's data-race-free guarantee.
- A read in a parallel phase returns the snapshot value or the thread's own latest write.
  It never sees a write that happens after it, and it never sees a value no thread wrote, so out-of-thin-air results are impossible.
- Racy programs can observe stale values for the rest of a round; the JMM permits this, and it is the only behavior that changes from plan 05.
- `long` and `double` stay atomic, and adjacent array elements and fields never tear, because merging works per field and per element.
- `final` fields are stronger than required: another thread can only obtain a reference after the merge that also publishes the constructor's writes.

### Heap: sparse persistent map and allocation arenas

- The heap becomes a persistent radix tree keyed by the 32-bit reference, replacing the positional list.
  Lookups and updates become logarithmic, and snapshots stay free because unchanged subtrees are shared.
- References are `arena << 20 | counter`.
  Each running thread owns one arena, a counter space of about one million objects, so threads allocate without coordination.
  Arenas of terminated threads return to a pool and keep their counters, so ids are never reused while objects live.
  Running out of arena space is a synchronization action that grants a fresh arena in the serial phase.
- `maxHeap` keeps counting live entries; the check uses the snapshot count plus the thread's own allocations, and the merge enforces the exact limit.
- Every heap and static-field access goes through `heap/heap.bend`; direct list scans (`string_intern_scan`, `class_mirror_scan`) become indexed tables in `Sched`-owned state.

### Write logs and three-way merge

- Each slice records the references it allocated or modified, and the static fields it wrote.
- The merge applies, for each logged reference, only the fields, array elements and characters that differ between the round's snapshot and the thread's version, on top of the state merged so far.
  This keeps writes by different threads to different fields of the same object, and to different elements of the same array.
- Two writes to the same field in one round are a data race; the later thread in id order wins, which is an allowed JMM outcome.
- Output written by a slice is buffered per thread and appended in thread order at the merge, so each `println` stays whole.

### Parallel evaluation

- The parallel phase splits the runnable threads in halves recursively and evaluates the halves with a Bend parallel call (`a b = slices(left) slices(right)`).
- Slices get equal instruction budgets, because Bend's fork-join scheduler never moves a task between cores once it has started, so balance has to come from the work split.
- Fuel is shared: each round reserves the sum of the slice budgets from the global budget, and unused fuel returns at the merge.

### Host I/O on native effects

- Files, stdout and stderr, timers and TCP use Bend's built-in native effects.
- Custom C effects in `bendjvm/host/effects/` cover what Bend lacks:
  non-blocking connect, half-close, socket addresses and ports, readiness polling for selectors, DNS (`getaddrinfo`), TLS through OpenSSL (client and server, certificate and hostname checks, client certificates, protocol and cipher selection), and spawning the native helper with pipes.
- Every request keeps plan 05's contract: an owning thread, an operation id, cancellation on interrupt and close, and at-most-once completion.

## Ordered implementation slices

### 1. Native build

- Find the entries over 247 words (a patched copy of the Bend compiler prints them) and restructure them: box large records, split multi-record helpers.
- Measure where the 60-minute build goes and bring it down to something usable for development.
- Exit: `runtime_api.bend` and `loader_api.bend` compile to C and link.

### 2. Bend host loop for console programs

- Port the run loop, class and resource loading, stdout/stderr, files, exit codes and the error reporting from `host_source` to Bend IO.
- `scripts/run.py` builds and starts the native binary.
- Exit: every non-network test in the suite passes on the native binary with the plan-05 scheduler.

### 3. Networking, selectors and DNS

- Port sockets, server sockets, NIO channels and selectors, and name resolution to native and custom C effects.
- Exit: the TCP, NIO and address fixtures pass natively.

### 4. TLS through OpenSSL

- Exit: `TlsFixture`, `tls/client-server-interop` and `web/https-example` pass natively.

### 5. Native helper

- Exit: `native/plugin-bridge` and the web example's checksum route pass natively; no helper process outlives the VM.

### 6. Heap map and arenas

- Replace the positional heap with the radix tree and arena references, still on the serial scheduler.
- Exit: the full suite passes; record the speed change against slice 2.

### 7. Rounds with write logs and synchronization stops

- Implement the parallel phase, merge and serial phase, evaluating the slices one after another first.
- Exit: the full suite passes, and new litmus fixtures pass (see "Verification").

### 8. Parallel evaluation

- Turn the slice evaluation into balanced parallel calls.
- Exit: the speedup and CPU-time checks below pass, and the full suite still passes.

### 9. Documentation, laws and proofs

- Update the spec, README, ROADMAP, plan 05's superseded sections, and the MiniJRE notes.
- Add laws for the merge (empty log is the identity, disjoint field writes commute, a thread's last write wins) and for the classification of synchronization actions, with proofs in `PROOF.bend`.

## Verification

- Every existing test passes on the native binary, and every differential fixture still matches OpenJDK.
- `threads/parallel-speedup`: four threads doing the same CPU-bound work finish at least twice as fast as one thread doing four times that work, on this 10-core machine.
- `threads/parallel-cpu`: during that run the process's user CPU time is at least twice its wall-clock time, which shows several cores were busy.
- Litmus fixtures, checked against the outcomes the JMM allows rather than one fixed output:
  message passing through `volatile` and through `synchronized` never shows the flag without the data;
  a counter incremented under a lock is exact;
  an unsynchronized counter may lose updates but never exceeds the total;
  writes to adjacent array elements and adjacent fields by different threads are all kept;
  a safely published object's `final` fields are always seen.
- Determinism: a fixed program with no host input produces the same output on every run.

## Completion checklist

- Runnable Java threads execute in parallel on several cores, demonstrated by the speedup and CPU-time checks.
- No Java code runs through the JavaScript target, and no Bun host remains in active paths.
- Every plan-05 behavior and test still passes natively.
- The memory-model argument above is reflected in the spec, and the merge laws are proved.
- Docs, laws and proofs are updated.
