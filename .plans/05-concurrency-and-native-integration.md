# Plan: Concurrency and native integration

Status: planned; no runtime changes implemented.
Source: `ROADMAP.md`, milestone 5.
Dependencies: [loading](01-jar-and-classpath-loading.md), [runtime expansion](02-java-runtime-expansion.md), [reflection/metadata](03-reflection-and-metadata.md), and [broader bytecode](04-broader-jvm-bytecode-support.md).

## Goal

Run concurrent Java 8 programs with correct thread lifecycle, monitors, synchronization, and volatile visibility; expose an explicit, restricted native-library bridge; and support concurrent TCP/NIO and authenticated TLS connections suitable for a small web-server compatibility example.

Java state and scheduling remain owned by Bend. The host supplies asynchronous OS effects and maintained TLS/native facilities. This is not full JNI, full JSSE/NIO compatibility, Spring Boot support, or a sandbox guarantee.

| Roadmap requirement | Deliverable |
| --- | --- |
| Add Java threads | Bend thread records, bounded preemptive scheduling, lifecycle/interruption/join/sleep, and per-thread frames/exceptions |
| Monitors and synchronized methods/blocks | Reentrant object/Class monitors, monitor bytecodes, implicit method locking, wait/notify, and correct release on return/unwind |
| Volatile memory semantics | An explicit sequentially consistent shared-state execution model with Java synchronization visibility and atomic wide volatile access |
| Controlled native-library interface | Versioned, allowlisted non-JNI ABI, explicit loading/binding, bounded arguments/results, failure containment, and cleanup |
| Networking and TLS primitives for web applications | Scheduler-aware TCP streams, selectable socket channels/buffers, and provider-backed client/server TLS with certificate validation |

All five rows require end-to-end Java-visible demonstrations.

## Current implementation and blockers

- `model.bend:VM` and `runtime/state.bend` have one frames list, status, exception, and result, alongside shared heap/statics/classes. There is no thread registry, monitor table, runnable queue, or pending-operation ownership.
- `runtime/execute.bend:loop_status` executes one frame stack recursively until completion, failure, or fuel exhaustion. An empty stack currently finishes the whole VM, not one thread.
- `loader/catalog.bend:field_records` rejects ACC_VOLATILE; `method_records` rejects ACC_SYNCHRONIZED; unknown native methods are rejected rather than bound to user libraries.
- The current decoder/runtime have no monitorenter/monitorexit execution paths. Method-return and exception unwinding need a shared mechanism for releasing implicit synchronized-method locks.
- `scripts/run.py:host_source` calls the generated runtime synchronously and flushes VM output after the run. A blocked OS call or a non-yielding generated run would otherwise stall every Java thread and host completion.
- `bendjvm/args.c` only supplies launcher defaults; it is not an application native ABI. Do not repurpose these symbols as if JNI or a native bridge already exists.
- Plan 2 proposes blocking TCP and typed host effects; plan 3 proposes append-only runtime class loading; plan 4 proposes wide values, general call sites, and a verifier. These are plans, not current delivered features.
- Plan 4 explicitly leaves MutableCallSite/VolatileCallSite concurrency and synchronization to this milestone. Class initialization, runtime type publication, mirror caches, and bootstrap linkage also need concurrency-safe state transitions.

## Architectural decisions

### Bend threads, not host-owned Java stacks

- Implement Java threads as VM-managed threads multiplexed on the existing Bend interpreter. Host OS threads/workers may perform OS effects, but they do not execute Java bytecode or mutate the heap.
- Split shared VM state from ThreadState. Shared state includes classes/member IDs, heap/statics, mirrors, call sites, monitors, runnable/wait queues, pending effects, limits, and output. Per-thread state includes stable ID/Thread object, frames, pending throwable/result, lifecycle/wait reason, interrupt flag, daemon/name metadata, and continuation.
- Start with bounded round-robin scheduling at bytecode/explicit intrinsic safe points. A compute-bound Java loop must not need Thread.yield to let another thread run. Preserve deterministic scheduling for a fixed recorded completion stream; do not claim live network arrival order is deterministic.
- Keep application-visible effects ordered by committed VM transitions. Never clone the shared heap into independently evolving thread VMs, and never use host races as an accidental Java memory model.
- Protect the host event loop: a generated Bend run returns after a bounded instruction quantum or effect boundary. Python/Bun adapters can then dispatch/poll completions before the next quantum.
- Parallelism is optional for independent parsing or host effects. Correct Java interleaving and memory semantics do not require simultaneous bytecode execution on multiple host cores.

### One shared effect boundary

- Extend the prior request/resume protocol, rather than introducing separate blocking protocols for files, networking, TLS, and native calls.
- Every request has a VM-run ID, monotonic operation ID, owning thread, typed operation, resource-handle generation, completion state, and optional deadline/cancellation policy.
- Requests can be outstanding concurrently. Completion wakes only its owner and commits at most once. Ignore/reject stale completions after cancellation, closure, thread termination, or VM restart without reviving dead threads or reusing stale handles.
- Blocking one Java operation parks that thread while others remain runnable. Resource close, timeout, interrupt, and external completion races are resolved by explicit state transitions, not callback arrival side effects.
- Host callbacks return data/events only. Bend owns exception construction, Java argument/type checks, thread state, monitor ownership, and returned references.

### Memory model: sequentially consistent baseline

- Use one serialized shared-memory transition order, preserving each thread's program order. Every ordinary/volatile read and write observes this coherent state; this deliberately implements stronger ordering than Java requires for data races.
- This is not permission to make compound operations atomic. `counter++` remains a read/compute/write sequence unless synchronized; schedules must be able to expose lost updates.
- Volatile long/double accesses publish/read a complete two-word value atomically. Never yield between halves. Atomic plain long/double access is a permitted stronger behavior and is the chosen baseline.
- Encode synchronization actions explicitly: monitor unlock/lock, volatile write/read, Thread.start, thread termination observed by join/isAlive, interruption detection, and class initialization completion. All reflection, method-handle, intrinsic, and native copy-back paths use the same field access rules.
- Do not add fake host fences as a substitute for VM semantics. If a future implementation parallelizes Java execution or caches field values, it must preserve this contract or implement a separately justified Java Memory Model refinement.
- Data-race tests check allowed outcomes/invariants; never require Bend to reproduce every weak-memory outcome from hardware/OpenJDK. The sequentially consistent baseline must still obey final-field construction/publication guarantees and prohibit out-of-thin-air values.

## Required Java/API compatibility slice

Each listed API is a deliverable. Record exact overload descriptors and flags in compatibility documentation; absent overloads remain explicitly unsupported.

| Area | Minimum surface |
| --- | --- |
| Runnable/Thread | Runnable.run; Thread constructors `()`, `(Runnable)`, `(String)`, `(Runnable,String)`; start/run/currentThread/isAlive/getState/getId; getName/setName; setDaemon/isDaemon; join(), join(long), join(long,int); sleep(long), sleep(long,int); yield; interrupt/isInterrupted/interrupted; holdsLock(Object) |
| Thread failure reporting | Thread.UncaughtExceptionHandler, per-thread get/setUncaughtExceptionHandler, static get/setDefaultUncaughtExceptionHandler; default terminal diagnostics when no handler is installed |
| Monitors | monitorenter/monitorexit; instance/static ACC_SYNCHRONIZED methods; Object.wait(), wait(long), wait(long,int), notify(), notifyAll() |
| Time | System.nanoTime() and currentTimeMillis() for deadlines/application measurements, with monotonic timers used internally |
| Shared publication | volatile instance/static fields for every supported value type; cross-thread class initialization; MutableCallSite.syncAll and VolatileCallSite target visibility |
| Native loading | System.load(String absolutePath), System.loadLibrary(String logicalName), and resolution of explicitly registered ACC_NATIVE methods through the BendJVM plugin ABI |
| Existing TCP | All Socket/ServerSocket and stream APIs promised by plan 2, now scheduler-aware; add Socket.shutdownInput/shutdownOutput/isClosed and stable socket/channel ownership |
| Buffers | Buffer position/limit/capacity/remaining/hasRemaining/clear/flip/rewind; ByteBuffer.allocate/wrap, relative and indexed byte get/put, bulk byte-array get/put, hasArray/array/arrayOffset |
| Selectable channels | SocketChannel.open(), configureBlocking, connect/finishConnect, read/write(ByteBuffer), close/isOpen, register; ServerSocketChannel.open(), bind(SocketAddress), configureBlocking, accept, close/isOpen, register |
| Selectors | Selector.open/select()/select(long)/selectNow/wakeup/close/isOpen/keys/selectedKeys; SelectionKey channel/selector/interestOps/readyOps/isValid/cancel and readable/writable/acceptable/connectable queries; required Set/Iterator view operations |
| TLS factories | SSLContext.getDefault/getSocketFactory/getServerSocketFactory; SSLSocketFactory default access and createSocket(String,int), plus layered createSocket(Socket,String,int,boolean); SSLServerSocketFactory default access and createServerSocket(int) |
| TLS sockets | SSLSocket.startHandshake/getInputStream/getOutputStream/close/getSession/getSSLParameters/setSSLParameters/getEnabledProtocols/setEnabledProtocols/getEnabledCipherSuites/setEnabledCipherSuites; SSLServerSocket.accept/close/setNeedClientAuth/getNeedClientAuth and protocol/cipher configuration |
| TLS parameters/session | SSLParameters endpoint-identification get/set; SSLSession.getProtocol/getCipherSuite/getPeerHost/getPeerPort/isValid; default-context trust/key material supplied through explicit runner configuration |

Add Thread.State enum metadata and supporting exceptions: InterruptedException, IllegalThreadStateException, IllegalMonitorStateException, SecurityException, UnsatisfiedLinkError, relevant linkage errors, buffer overflow/underflow, IllegalBlockingModeException, ClosedChannelException, AsynchronousCloseException, ClosedByInterruptException, CancelledKeyException, ClosedSelectorException, and SSLException/SSLHandshakeException. Reuse existing Socket/IOException hierarchy and typed throwable machinery.

No Thread.stop/suspend/resume, thread priorities/groups, ThreadLocal, executor/fork-join framework, general java.util.concurrent catalog, Unsafe, off-heap direct buffers, memory mapping, asynchronous-channel APIs, DatagramChannel, full SSLContext provider configuration, SSLEngine, HTTP client/servlet framework, or public JNI is promised here. These exclusions do not remove concurrent TCP, NIO readiness, or client/server TLS.

## Thread lifecycle and scheduling contracts

- Thread.start atomically transitions a NEW thread to scheduled execution exactly once. Dispatch overridden Thread.run, or the Runnable target under the normal inherited implementation. Direct calls to run remain ordinary calls on the caller's thread.
- CurrentThread returns the executing Java Thread object, including a real main-thread object. IDs are stable and not reused while observable; names/daemon state follow Java inheritance and validation rules.
- Model NEW, RUNNABLE, BLOCKED, WAITING, TIMED_WAITING, and TERMINATED. Record the precise internal wait reason separately; map to public states according to Java semantics rather than reporting every host I/O wait as monitor BLOCKED.
- Global fuel covers all executed Java threads and callback/intrinsic work. Per-thread quanta provide progress, not separate unlimited fuel accounts. Bound thread count, stack depth, pending operations, and payload/handle allocation; report limits distinctly from Java scheduling events.
- join waits for actual termination and establishes visibility; timed join may return while the target is alive. Handle NEW/already-terminated targets, argument validation, interruption, and timeout with no lost wakeups.
- sleep does not release monitors. Interrupting sleep/join/wait throws InterruptedException and clears the interrupt status at the specified point; interrupted() clears the current thread's flag, isInterrupted() does not.
- Interrupt does not mean asynchronously injecting an exception into arbitrary bytecode. A running computation records the flag. Classic Socket stream I/O is not made interruptible merely because NIO channels are; preserve the API-specific behavior.
- Returning from main does not exit while non-daemon threads remain. Daemon-only liveness does not keep the VM alive. Uncaught exceptions terminate their thread and invoke its handler; they do not automatically kill unrelated non-daemon threads. Define launcher exit-status policy and test main-thread versus worker failures separately.
- No runnable threads with outstanding I/O/timers is idle, not completion or deadlock. A closed wait-for cycle with no external progress is a diagnostic condition; do not invent a catchable Java DeadlockException or silently release locks. Keep an independent runner deadline available.
- Thread termination cleans scheduler-owned records and releases implicit locks during Java unwind, but does not automatically close every application-owned socket/native handle that thread touched; shared handles may still belong to other threads. Whole-VM teardown closes remaining host resources.

## Monitors and synchronized code

- Monitor identity is the object reference, including Class mirrors for static synchronized methods. Distinct equal objects do not share monitors. Store owner thread ID, recursion depth, entry contenders, and wait set separately from ordinary object fields.
- monitorenter is reentrant; contenders park without consuming CPU quanta in a spin loop. A null reference throws NullPointerException. monitorexit requires ownership and decrements depth; non-owner exit throws IllegalMonitorStateException.
- Synchronized instance methods lock the receiver; static methods lock the declaring Class mirror, not the receiver's runtime class or a loader-global lock. Acquisition occurs before executing the body and applies to synchronized native methods too.
- Frame metadata records implicit monitor ownership. Normal return and abrupt frame unwind release the method's acquisition exactly once. Explicit synchronized blocks use bytecode monitorenter/monitorexit and compiler-generated finally paths; do not globally auto-unlock every explicit monitor on an arbitrary throw and mask invalid bytecode.
- Extend decoder/verifier rules for opcodes 194/195 and synchronized flags. Adopt/document the JVM structured-locking policy consistently with runtime checks; do not over-reject legal control flow by assuming only a lexical javac pattern can lock correctly.
- wait requires ownership, atomically joins the wait set and releases all recursive acquisitions of that monitor. On timeout/notification/interruption it contends to reacquire the monitor and restores the prior recursion depth before returning or throwing.
- notify moves at most one waiter toward contention; notifyAll moves all. Neither releases the notifier's lock, transfers ownership immediately, nor stores a notification when nobody waits.
- Resolve notify/interrupt/timeout races within allowed Java outcomes without losing interrupts or waking the same wait twice. Public Java code must loop around a condition predicate; spurious wakeups are permitted, not required as the default scheduler behavior.
- Thread.join may use dedicated scheduler wait queues internally; do not expose them as an accidental dependency on locking the Thread object. Still preserve the public synchronization/visibility contract.

## Shared runtime publication

- Class initialization tracks owner thread and waiting threads. Recursive requests by the initializer owner proceed under Java rules; other threads wait for success/failure. Class-init locking is an internal mechanism, not automatically the user-observable Class monitor.
- Publish initialized static state before waking waiters; failing initialization retains the correct original/later error behavior and never reruns a failed initializer.
- Runtime class loading, class mirrors, strings/boxing caches, proxy/lambda class generation, and catalog append must not create duplicate identities or partially visible metadata under interleaving.
- Revisit invokedynamic resolution under concurrency: the JVM may allow concurrent bootstrap evaluations, but installs a valid stable outcome according to linkage rules. Do not extend a single-thread exactly-once-bootstrap assumption into a promise Java does not make. Test stable publication and allowed failure behavior, not a hard-coded parallel bootstrap count.
- VolatileCallSite target updates have volatile visibility; MutableCallSite.syncAll establishes the required target visibility. Immediate visibility of ordinary mutable targets is an allowed stronger baseline. Do not keep documented single-thread placeholder semantics after this milestone.
- Reflection/MethodHandle field writes, annotation materialization, proxy callbacks, and native return/copy-back commit through shared-state transitions. No host callback may overwrite a newer VM snapshot with stale shared state.

## Controlled native-library interface

### Boundary and security model

- Define a BendJVM-specific versioned plugin ABI, not an implicit JNI compatibility claim. System.load/loadLibrary accept only paths/logical names allowed by explicit launcher configuration; native loading is disabled without that configuration.
- Use a dedicated supervised native-helper process to load approved shared libraries through platform loading APIs. The helper exposes typed request/response records; it never receives the Bend heap as raw pointers.
- A library exports one versioned registration entry with exact Java owner/name/descriptor/staticness mappings and ABI function entries. Reject duplicate/conflicting bindings, malformed descriptors, unsupported ABI versions, and attempts to replace protected MiniJRE intrinsics.
- Support portable scalar int/float/long/double values, explicit UTF-16 strings, bounded copied primitive arrays/buffers, and opaque plugin resource handles. The high/low-word numeric transport remains lossless.
- Java object pointers, arbitrary memory addresses, arbitrary symbol calls, attached native threads, and callbacks into Java from foreign OS threads are not supported. Reject unsupported signatures before entering native code; never return fake zeros/nulls.
- For mutable array arguments, define copy-in/copy-out explicitly. Stage result validation and all copy-back writes as one VM commit; document that this is the custom bridge's contract, not JNI's pinning semantics. Define alias handling when the same array appears more than once; avoid inconsistent independent copies.
- Native functions return a typed value, declared bridge error, or pending completion according to the ABI. Map errors to registered Java exception types without letting plugins forge heap references or arbitrary class definitions.
- Bind ACC_NATIVE methods lazily when first invoked so Java static initialization can call System.loadLibrary before method resolution; preserve rejection of unbound natives as UnsatisfiedLinkError rather than making them empty Java methods.

### Lifecycle and containment

- A native call parks only the owning Java thread. A bounded worker facility inside helpers or separate helper instances prevents one slow call from blocking unrelated Java/host work; serialize non-thread-safe libraries according to declared capabilities.
- No callback runs while holding an implicit global VM lock. If the Java call is synchronized, its object monitor remains owned by the parked Java thread until normal return/unwind.
- Validate length/count/type/handle ownership on both sides. Enforce call deadlines, response-size limits, and a cap on outstanding native work. Define helper failure fan-out to all affected pending calls.
- Cancellation does not undo external side effects. If a native call cannot be safely interrupted, terminate its helper on the runner deadline, invalidate its handles, and prevent stale completion/copy-back. Do not unload a library with live calls or handles.
- Native plugins execute real native code with the helper's OS permissions. Process separation limits VM crash propagation but is not an OS sandbox or a guarantee against malicious libraries; document this risk prominently.
- Deliver a small real C plugin fixture exercising scalar wide values, copied buffers, a plugin resource handle, and failure/cleanup. Compile a platform-appropriate shared library during tests rather than mocking its calls. No untrusted third-party native binary is required.

## Scheduler-aware networking and NIO

- Evolve milestone 2 TCP operations into nonblocking host requests behind Java's blocking API. Pending DNS/connect/accept/read/write must allow other Java threads to run and must carry deadline/close ownership.
- Use maintained host socket/readiness APIs, not one polling thread per Java byte read. Resolve DNS away from the Java execution loop and report errors through existing Java exception mapping.
- Preserve partial reads/writes, EOF, half-close, connection refusal, backlog/bind failures, and close semantics. Closing a shared socket from another thread wakes blocked operations with the specified error instead of leaking a wait forever.
- NIO blocking-channel interruption closes the channel and raises ClosedByInterruptException with the appropriate interrupt status; asynchronous close uses AsynchronousCloseException. Classic socket streams retain their different interruption semantics.
- ByteBuffer position/limit mutations remain in Bend; the host receives only the bounded remaining slice and reports bytes transferred. Validate position <= limit <= capacity, overflow/underflow, bulk bounds, and no position advance for a failed operation where Java forbids it.
- SocketChannel nonblocking read/write may return zero; accept may return null; connect/finishConnect uses an explicit pending state. Registration requires a nonblocking selectable channel.
- Selector selection parks only its Java thread. Readiness events update SelectionKey sets in Bend, with valid interest/ready masks, cancellation processing, and selected-set iteration/removal semantics. Repeated readiness must not duplicate keys.
- wakeup makes the current or next blocking selection return under Java semantics. Handle races among select, wakeup, interrupt, key cancellation, and selector/channel close without dropping events or leaving stale keys.
- Use generation-tagged OS handles and operation IDs to prevent an old readiness event from attaching to a newly reused socket.
- Network capabilities apply equally to streams, channels, and TLS. Distinguish connect/listen permissions if the existing configuration permits; no NIO/TLS bypass around a disabled network policy.

## TLS provider integration

- Never implement cryptography, certificate parsing, or TLS record protection in Bend. Use a maintained host TLS provider through the existing effect boundary; Bend owns Java socket/session identities and API semantics, while the provider owns cryptographic state and OS-facing TLS records.
- Select the existing host's supported provider during implementation after capability checks. The concrete baseline is the maintained Python ssl provider in the Python host service, with nonblocking sockets/selectors and SSLContext trust/key loading; do not shell out to openssl per connection. Verify actual protocol/cipher capabilities and report unavailable requirements explicitly.
- Default context trust roots come from explicit/system provider configuration. Server certificates/private keys and optional client credentials are supplied by explicit runner paths, never committed secrets or hard-coded test keys in runtime code. Configuration parsing must reject unreadable or inconsistent material before serving traffic.
- Deliver authenticated TLS client and server connections with TLS 1.2 minimum; allow TLS 1.3 when the provider supports it. Do not enable obsolete protocols or silently downgrade because a requested protocol/cipher is unavailable.
- A client must validate the certificate chain and validity period. Implement SSLParameters endpoint identification (HTTPS hostname/IP verification) and test it. Raw SSLSocket Java semantics do not automatically imply HTTPS hostname checks: document the need to enable the algorithm and make the web example explicitly do so, never suggest chain validation alone proves server identity.
- Send appropriate SNI for DNS peers; validate hostnames/IP subjectAltNames through the maintained provider. Do not add a trust-all workaround for self-signed fixtures: install the fixture CA explicitly for that test.
- Support server need-client-auth using configured trust roots and client credentials. Test accepted and missing/untrusted client certificates. General pluggable Java TrustManager/KeyManager providers and dynamic SSLContext.init are outside this fixed-provider subset.
- Handshake is a resumable operation; WANT_READ/WANT_WRITE schedules readiness rather than blocking the VM. A slow or failed handshake cannot stop another Java connection/thread.
- Preserve timeout/close races, handshake failure cleanup, partial application I/O, close_notify, and abrupt transport EOF distinctions permitted by the selected Java API/provider. Never return truncated ciphertext as successful plaintext or silently convert certificate failure into a normal empty stream.
- Map provider failures to SSLHandshakeException/SSLException or the appropriate socket/timeout exception; keep native provider diagnostics on an internal diagnostic channel without leaking credentials/private-key material.
- SSLSocket uses the same Java InputStream/OutputStream surface as plain TCP. Layered sockets obey autoClose ownership. Closing all wrappers does not double-close a newly reused host handle.
- SSLEngine, TLS-over-selectable-channel APIs, ALPN/HTTP2, session-cache management APIs, OCSP/provider catalogs, and a general JSSE replacement remain outside scope. A concurrent HTTPS/1.1 example uses blocking Java TLS streams scheduled over nonblocking host I/O.

## Ordered implementation slices

### 1. Split shared state and add bounded thread scheduling

Targets: `model.bend`, `runtime/state.bend`, `runtime/execute.bend`, frame/continuation records, runtime API, generated host adapter, and every shared VM constructor/destructor.

- Introduce ThreadState, runnable/wait bookkeeping, and bounded interpreter quanta while retaining one coherent shared heap/catalog.
- Preserve existing single-thread execution as a one-thread scheduler run, not a parallel legacy interpreter.
- Add global instruction/thread/stack limits and host-poll boundaries; map exported-symbol references before changing APIs.

Acceptance: existing programs retain behavior; two CPU-bound Java execution contexts alternate without host blocking; completion/error in one does not overwrite the other's frames/result. Global fuel is shared and adapter round trips cannot reset it. Verify deterministic execution with a fixed scheduler/completion input.

### 2. Java Thread lifecycle, interruption, and join

Targets: bootstrap Thread/Runnable/State/handler types, `java/` thread intrinsics, scheduler timers and wait queues, launcher completion policy.

- Implement the declared Thread API and normal virtual dispatch of run/Runnable.
- Add timed waits, interrupt flags, terminal events, daemon shutdown, and uncaught exception handlers.
- Separate application thread failure from VM corruption/fuel termination.

Acceptance: start-once, run-versus-start, currentThread identity, timed/untimed join, interrupted sleep/join, cleared/preserved flags, inherited daemon state, main exit with a live worker, and worker uncaught exceptions follow the contract. No sleeps used merely to hope a test thread has started; use explicit rendezvous.

### 3. Monitors, synchronized calls, and wait sets

Targets: decoder/verifier monitor rules, monitor table, runtime invocation/return/unwind, Object wait/notify intrinsics, synchronized native-call integration.

- Implement reentrant monitor acquisition/release and parked contention.
- Support synchronized instance/static methods, explicit monitor blocks, and wait/notify/notifyAll with recursive depth restoration.
- Remove synchronized rejection only after the full implicit-lock return/unwind path works.

Acceptance: contested increments lose no updates under synchronization; static/instance lock identities are distinct/correct; recursive wait reacquires its complete depth; notification does not prematurely transfer ownership; exceptions/returns release implicit locks; invalid owner/null accesses throw correctly. Exercise timeout/notify/interrupt races and a blocked native call retaining its synchronized monitor.

### 4. Volatile and cross-thread runtime publication

Targets: field access helpers/catalog flags, method-handle/reflection paths, class initialization/loading/mirror caches, callsite publication, and shared state laws.

- Remove volatile rejection and route all reads/writes through the serialized memory transitions.
- Add class-initialization owner/waiter states and concurrency-safe append/publication for dynamically loaded/synthesized classes.
- Complete MutableCallSite.syncAll and VolatileCallSite visibility; preserve wide-value atomicity.

Acceptance: volatile message passing publishes associated data; volatile long/double never tear; synchronized/start/join publication holds; unsynchronized increments are not accidentally one atomic operation. Competing class initialization/load/proxy/lambda requests preserve identity and errors. Dynamic callsite races install a valid stable target without requiring an invalid bootstrap-count assumption.

### 5. Multiplex host effects and resource cancellation

Targets: runner protocol/host service, pending operation records, runtime request/resume, existing file/resource/TCP adapters, teardown paths.

- Allow concurrent outstanding requests and park/resume their owning threads at most once.
- Add deadlines, resource generations, close/cancel races, and late-completion handling.
- Migrate previous synchronous adapters cleanly; no separate blocking transport left for a library API.

Acceptance: a pending file/socket operation does not stop a CPU-bound thread; out-of-order completions resume the right callers; duplicate/stale responses cannot replay writes or reanimate terminated threads. Closing handles while operations wait releases them; VM shutdown/fuel exhaustion terminates pending host work and leaves no handles/processes.

### 6. Versioned native plugin ABI and real library loading

Targets: explicit binding metadata/native resolution, launcher allowlist controls, a small supervised helper executable/protocol, native intrinsic continuation, and a C fixture plugin.

- Define and implement ABI registration, lossless marshalling, bounded buffers, opaque resources, and typed errors.
- Integrate System.load/loadLibrary and lazy binding without permitting replacement of protected intrinsics.
- Implement cancellation/helper-crash handling and documented restrictions on callbacks/pointers.

Acceptance: Java loads an approved compiled library, invokes scalar/wide/buffer/resource methods, and catches mapped failures. Disallowed paths, wrong ABI, missing symbols/mappings, oversized responses, forged handles, and native-helper crashes fail explicitly while unrelated Java threads remain coherent. A slow native call does not freeze the VM; teardown reaps helpers and handles.

### 7. Concurrent TCP and NIO readiness

Targets: existing networking effects, ByteBuffer/channel/selector MiniJRE modules, SelectionKey collections, scheduler event loop and diagnostics.

- Complete blocking TCP concurrency, close/half-close ownership, and DNS/connect/accept/read/write deadlines.
- Implement the bounded NIO API surface and buffer semantics over the same host socket registry.
- Add wakeup/cancellation/interruption/selector-close transitions with stale-event protection.

Acceptance: concurrent clients are served while another connection blocks; a nonblocking echo server progresses via Selector; partial/zero-byte transfers preserve buffer positions; closing/interruption wakes the correct operations; cancelled keys and recycled socket handles cannot receive old readiness. All tests use loopback and bounded handshakes.

### 8. Provider-backed TLS client/server sockets

Targets: maintained host TLS adapter, SSLContext/factory/socket/parameter/session MiniJRE classes, capability/credential configuration, scheduler readiness/timeout/close integration.

- Implement the fixed-provider JSSE subset with nonblocking handshakes and standard streams.
- Add chain/hostname verification, server credentials, optional required client authentication, explicit protocol/cipher selection, and correct layered socket ownership.
- Keep cryptography/provider state outside Bend but all Java control state inside it.

Acceptance: Java TLS client and server interoperate with independent local peers; trusted hostname-correct connections succeed, while untrusted/expired/wrong-host certificates and missing required client certificates fail. A stalled handshake does not block other Java threads/connections. Verify close_notify/abrupt close, deadline cleanup, and disabled-network policy with no trust-all or plaintext fallback.

### 9. Integrated web compatibility example and milestone gates

Targets: `scripts/test.py`, reusable fixtures/native helper build logic, local TCP/TLS peers, README/spec/roadmap, and meaningful laws/proofs.

- Run a packaged Java 8 example with multiple worker threads, a monitor-protected work queue, volatile shutdown state, a configured native plugin operation, and TLS request/response handling.
- Keep the HTTP demonstration bounded and explicit (simple HTTP/1.1 requests with defined framing/connection closure); do not add a production servlet stack or claim Spring Boot compatibility. Exercise NIO separately if the example uses blocking TLS streams.
- Extend the harness with deterministic synchronization fixtures, bounded schedule variation, crash/cancellation tests, local certificates, and interoperability checks. Use independent host peers rather than only BendJVM talking to itself.
- Preserve all previous milestone behavior and update API/ABI/permission/limit/provider documentation. Mark completion only when every roadmap row is demonstrated.

Acceptance: concurrent requests produce correct responses, slow clients do not starve unrelated work, synchronized shared data remains correct, native/TLS failures are contained according to the documented boundary, and all resources/helpers are reaped at shutdown.

## Dependency and parallel-work map

- Slice 1 fixes state/scheduler ownership; slice 2 builds lifecycle; slice 3 builds monitor semantics; slice 4 depends on the shared-state and synchronization contracts. Slice 5 fixes concurrent host effects and can progress alongside pure monitor/publication work after the scheduler interface is stable.
- Native helper work (slice 6) and NIO/provider host work (slices 7–8) can run independently after the typed effect/handle contract is agreed. TLS Java API integration depends on stream ownership and asynchronous networking.
- One integration owner controls shared VM/ThreadState, lifecycle transitions, monitor ownership, runtime APIs, protocol versions, and bootstrap registrations. Parallel tasks own disjoint helper/provider modules or fixture families; they do not invent alternate schedulers.
- Parallelize independent host I/O, numeric-free metadata verification, and fixture preparation. Java-visible state commits and synchronization order remain owned by the Bend scheduler; do not parallelize heap mutation until a different memory model is designed and verified.

## Verification strategy

Before implementation, run `bend guide`, inspect exported-symbol references using an available language server, and re-read shared contracts changed by earlier milestones. Check local compiler, dynamic-library loader, TLS provider/version, and certificate-generation capabilities before selecting platform-specific helper build commands.

- Compile normal fixtures with `javac --release 8`; inspect monitor/volatile/method flags and exception paths with `javap -v -c` when establishing coverage.
- Compare Java-specified lifecycle, visibility, exception, socket, and TLS outcomes against OpenJDK. Do not compare exact schedules, thread IDs, wall-clock durations, provider wording, negotiated cipher order, or all weak-memory outcomes.
- Use explicit monitor/volatile rendezvous, deadlines, and schedule seeds. Sweep a bounded set of legal interleavings for lost wakeups, recursive waits, class initialization, close/interrupt/completion races, and publication. Stress runs complement deterministic transition tests; neither alone proves the Java Memory Model.
- Verify blocking progress through observable concurrent work, not elapsed-time guesses. Timeouts are broad safety bounds; no test relies on a tiny sleep winning a race.
- Compile and load a real harmless native fixture. Exercise native crash/hang behavior only in its supervised helper, never by deliberately crashing the main assistant/runner process.
- Generate ephemeral local CA/server/client material for TLS fixtures, with explicit trust stores for BendJVM and the reference JDK. Use deliberately wrong-host/untrusted/expired certificates for negative cases. No public network, committed private keys, or certificate-verification bypass.
- Test network/TLS interoperability in both directions with an independent local peer. Include partial payloads and peers that stall, close, or fail authentication.
- Check resource cleanup using helper lifecycle and host handle counters/OS observations, not just a successful exit status. Include daemon-only shutdown, worker exceptions, fuel exhaustion, hard runner timeout, and native-helper failure.
- Keep permanent tests for behavioral invariants and realistic races; avoid source-text, internal-record layout, or artificial mock-response assertions as proof of threading/TLS support.

Final commands:

```sh
python3 scripts/run.py --prepare
python3 scripts/test.py --fast
python3 scripts/test.py --full
bend PROOF.bend
```

Extend `--fast` with representative thread/monitor/volatile progress and bounded local I/O checks. `--full` includes native-plugin, schedule-variation, NIO, TLS authentication, and cleanup groups. Run the packaged concurrent TLS example through the actual CLI. Launch long-running servers/helpers with supervised processes, observe readiness, then stop and verify teardown.

Candidate laws: each thread is in exactly one lifecycle/wait state; monitor ownership/depth is consistent; wait atomically releases/reacquires its recursion state; a completion commits at most once; stale handle generations cannot revive resources; shared updates preserve unrelated thread state; publication is atomic. Prove bounded pure transitions, not OS thread fairness, native library safety, cryptographic correctness, or the entire Java Memory Model. Run `bend PROOF.bend` before committing.

## Completion checklist

- Java threads make progress without explicit yield and have correct lifecycle, interrupts, joins, daemon shutdown, and isolated exceptions.
- Monitors, synchronized methods/blocks, wait/notify, and unwind behavior enforce ownership and recursion rules.
- Volatile and other synchronization actions provide the documented visibility/atomicity, including wide values and reflective/handle access.
- Class initialization, dynamic loading, mirrors, proxies/lambdas, and callsite publication remain coherent under interleaving.
- Native loading uses the explicit allowlisted versioned ABI; a real native library runs without obtaining arbitrary Java heap pointers. Limitations and remaining OS privileges are documented.
- Blocking TCP, nonblocking channels/selectors, and client/server TLS work without freezing unrelated Java threads.
- TLS validates trust and requested endpoint identity, handles configured client authentication, and never falls back to plaintext or trust-all.
- All loading/runtime/reflection/bytecode regressions remain supported; no old single-thread transport or memory-model placeholder remains in active paths.
- Each named API and acceptance case is implemented or scope is changed with explicit user approval. No simulated network successes, stub native returns, no-op locks, or fake certificate validation.
- Documentation and meaningful laws/proofs match exercised behavior. Remove throwaway probes/generated libraries/certificates after verification; retain reproducible fixture sources and harness generation logic.

Planning verification: grounded in the current VM/state/execute/catalog/runner/native-launcher files and preceding milestone plans. This documentation-only change does not claim implemented concurrency, native loading, networking, TLS, or passing runtime tests.
