# Plan: Java runtime expansion

Status: implemented; verified by `python3 scripts/test.py --full` (90 passed) and `bend PROOF.bend`.
Source: `ROADMAP.md`, milestone 2.
Related plan: [JAR and classpath loading](01-jar-and-classpath-loading.md).

## Goal

Expand the Bend-owned MiniJRE enough to run small Java 8 applications that manipulate strings and collections, read configuration/resources, copy files, exchange bytes over TCP, and recover from Java exceptions while closing resources correctly.

This is a defined standard-library compatibility slice, not an OpenJDK replacement or Spring Boot support.

| Roadmap requirement | Deliverable |
| --- | --- |
| Add standard library classes needed by common applications | Core object/string utilities, integer boxing, collection interfaces and implementations, and supporting exception classes |
| Expand file, stream, collection, and networking support | In-memory and file streams, UTF-8 readers/writers, lists/maps/iterators, and blocking TCP client/server APIs |
| Improve exception and resource handling | Typed throwable objects, complete frame unwinding, causes/suppression, try-with-resources, and deterministic host-handle cleanup |

## Current implementation

The MiniJRE slice is implemented as synthetic bootstrap classes plus Bend
intrinsics. Exact registrations are in `bendjvm/loader/bootstrap.bend`.
`java/outcome.bend` is the typed intrinsic result. `invokeinterface` uses the
existing virtual lookup. Host file/TCP effects resume in `scripts/run.py`.
Historical blockers in earlier drafts of this section (output-only intrinsics,
stringless `athrow`, missing `invokeinterface`) are closed.

## Dependencies and milestone boundaries

- Treat milestone 1 as planned, not implemented. Its classpath source layer, explicit entry selection, argument array, and resource request/resume transport are prerequisites for the final packaged application.
- Reuse and extend milestone 1's `ClassLoader.getSystemResourceAsStream`, `InputStream`, and request/resume protocol. Do not introduce another resource store, subprocess protocol, or stream hierarchy.
- Pure runtime work can begin before milestone 1 is complete. If implementation starts first, agree and implement one shared result/effect boundary; migrate milestone 1 consumers to it rather than retaining adapters for two protocols.
- `invokeinterface` is a narrow prerequisite included here, even though broader bytecode work is milestone 4. Verify byte-array operations, reference returns, null branches, and javac-generated try-with-resources bytecode through the full decode/link/verify/execute pipeline.
- Networking here means synchronous TCP byte streams, including a one-connection server. Milestone 5 still owns concurrent server operation, monitors, general native-library integration, NIO, TLS, and production web-serving primitives.
- Reflection, runtime annotations, proxies, Java Stream API/lambdas, modules, garbage collection, full `long`/`double`, and wholesale loading of OpenJDK classes remain outside this milestone.

## Minimum supported API surface

Each listed method is a deliverable. List exact descriptors and access flags in the implementation's compatibility documentation. Other overloads remain explicitly unsupported; a class name alone is not a compatibility promise.

| Area | Required classes and methods |
| --- | --- |
| Objects | `Object.<init>()`, `equals(Object)`, `hashCode()`, `toString()`; `Objects.requireNonNull(T)` and `Objects.equals(Object,Object)` |
| Strings | `String.length()`, `isEmpty()`, `charAt(int)`, `equals(Object)`, `hashCode()`, `substring(int)`, `substring(int,int)`, `concat(String)`, `toString()`, `valueOf(int)`, `valueOf(boolean)`, `valueOf(Object)` |
| String building | `StringBuilder.<init>()`, `<init>(String)`, `append(String/Object/int/char/boolean)`, `length()`, `toString()`; sufficient for ordinary Java 8 string concatenation |
| Boxed integers | `Integer.valueOf(int)`, `intValue()`, `parseInt(String)`, `equals(Object)`, `hashCode()`, `toString()`; Java-required cached identities for `valueOf(-128..127)` |
| Utilities | `Math.abs(int)`, `min(int,int)`, `max(int,int)`; `System.arraycopy(Object,int,Object,int,int)` |
| Collections | `Iterable.iterator()`; `Collection.size/isEmpty/add/contains/clear/iterator`; `List.get/set/add(int,Object)/remove(int)` plus inherited operations; `ArrayList.<init>()` and `<init>(int)`; `Iterator.hasNext/next/remove` |
| Maps | `Map.size/isEmpty/put/get/containsKey/remove/clear`; `HashMap.<init>()` implementing these operations |
| Stream contracts | `AutoCloseable.close()`, `Closeable.close()`, `Flushable.flush()`; `InputStream.read()/read(byte[])/read(byte[],int,int)/close()`; `OutputStream.write(int)/write(byte[])/write(byte[],int,int)/flush()/close()` |
| Memory streams | `ByteArrayInputStream(byte[])`; `ByteArrayOutputStream()` with `toByteArray()`, `size()`, `reset()`, and inherited operations |
| Files | `File(String)`, `exists()`, `isFile()`, `isDirectory()`, `getPath()`; `FileInputStream(String)`; `FileOutputStream(String)` and `(String,boolean)` with inherited stream operations |
| Text I/O | `Reader.read()/read(char[],int,int)/close()`; `Writer.write(int)/write(String)/write(char[],int,int)/flush()/close()`; `InputStreamReader(InputStream,String)` and `OutputStreamWriter(OutputStream,String)` supporting UTF-8; `BufferedReader(Reader).readLine()/close()` |
| TCP | `InetSocketAddress(String,int)`; `Socket()` and `(String,int)`, `connect(SocketAddress,int)`, `getInputStream()`, `getOutputStream()`, `setSoTimeout(int)`, `close()`; `ServerSocket(int)`, `getLocalPort()`, `accept()`, `setSoTimeout(int)`, `close()`; supporting SocketAddress hierarchy |
| Throwable state | `Throwable` no-arg/message/cause/message+cause constructors, `getMessage()`, `getCause()`, `initCause(Throwable)`, `addSuppressed(Throwable)`, `getSuppressed()`, `toString()`; matching constructors on supported exception subclasses where Java defines them |

Add supporting exception classes with correct ancestry: `IOException`, `FileNotFoundException`, `EOFException`, `UnsupportedEncodingException`, `SocketException`, `ConnectException`, `UnknownHostException`, `SocketTimeoutException`/`InterruptedIOException`, `IllegalArgumentException`, `IllegalStateException`, `IndexOutOfBoundsException`, `StringIndexOutOfBoundsException`, `NumberFormatException`, `NoSuchElementException`, `ConcurrentModificationException`, and `UnsupportedOperationException`. Preserve existing exceptions and correct their ancestry where needed. Add the linkage errors required for interface dispatch, including `AbstractMethodError` and `IncompatibleClassChangeError`.

Deliberate exclusions include collection views/default methods, sorting, general charset catalogs, regex, serialization, filesystem mutation APIs beyond output streams, random-access files, HTTP libraries, UDP, socket option catalogs, and public stack-trace reflection APIs. These exclusions do not remove file, networking, or resource deliverables.

## Semantic contracts

### Intrinsics and library representation

- Continue the existing synthetic MiniJRE/Bend-intrinsic approach. Split implementation by cohesive Java area under `bendjvm/java/`; avoid a monolithic dispatcher and avoid importing full host JDK classes.
- Register by exact owner/name/descriptor and correct static/interface/access flags. Constructors have real state initialization. Unknown natives fail explicitly before execution.
- Replace the output-only intrinsic result with a typed result capable of returning void/a slot, carrying an updated VM, throwing a Java reference, requesting a host effect, or reporting an internal VM failure. Output remains part of VM state.
- Pure methods mutate only Bend-owned state. Host effects perform OS operations and return raw results, not Java object graphs or Java method behavior.
- Calls from `equals`, `hashCode`, `toString`, and stream wrapper methods into user overrides must use normal VM dispatch with resumable continuations. Do not run hidden host callbacks or recursively execute outside the fuel-accounted interpreter.
- Preserve exception call-site PCs and exactly-once effects across suspension. Count method/loop work under the existing execution budget; bound large intrinsic loops so one invocation cannot bypass fuel indefinitely.

### Objects, strings, arrays, and collections

- String indexing and hashes operate on UTF-16 code units, not host Unicode code points. Cover surrogate pairs and unpaired surrogates. StringBuilder results are immutable snapshots, not aliases of later mutations.
- Default Object equality is identity; hashes remain stable. Do not compare OpenJDK identity-hash numeric values in tests. `String.valueOf(Object)` uses `"null"` for null and virtual `toString()` otherwise.
- Integer parsing rejects malformed/overflowing decimal input with NumberFormatException. Integer `MIN_VALUE` behavior for `abs` remains Java-compatible rather than mathematically widened.
- `System.arraycopy` validates nulls, array kinds, bounds, overlap, and reference assignment compatibility, including Java's partial-copy behavior when reference element assignment fails.
- ArrayList supports nulls, index checks, replacement return values, removal shifts, and iterator state/fail-fast behavior for structural changes. `Iterator.remove` follows the one-remove-per-next rule.
- HashMap supports null keys/values, collision resolution, replacement returning the old value, and user-overridden equality/hashing. `containsKey` distinguishes absent keys from present null values. Do not promise iteration order or add iteration APIs not listed above.
- Java heap references and collection/string state stay in Bend. Keep the current `--max-heap` meaning; separately bound array/buffer payloads and host handles so one huge allocation cannot evade an entry-count limit. Document the added limits and failure mapping rather than silently redefining heap units.

### Exceptions and cleanup

- A thrown value is a non-null Throwable reference; `athrow null` synthesizes NullPointerException. Preserve identity and message/cause state through catches and rethrows.
- Search exception table entries in order, checking both `[start,end)` and type assignability; catch type zero means catch-all. Unwind as many callers as necessary and push the actual throwable reference at handler entry.
- Separate catchable Java exceptions from verifier failures, unsupported VM operations, host protocol corruption, and execution-budget termination. Java catch blocks cannot swallow arbitrary implementation errors.
- Preserve existing class-initialization success/failure transitions when exceptions unwind an initializer. Subsequent accesses to a failed class must not rerun initialization.
- Support javac's normal try-with-resources lowering: reverse close order, primary exception preservation, suppressed close failures, null resources, and early returns. Enforce Throwable self-suppression/null and cause initialization rules.
- Handle allocation failure while constructing an exception without recursive allocation failure; use a documented emergency OutOfMemoryError strategy.
- Uncaught diagnostics include type/message and useful method/PC frames. Exact OpenJDK diagnostic wording and stack-trace APIs are not required.

### Streams, files, and text

- Reads return unsigned bytes or `-1`; bulk reads can be short, zero-length reads return zero after required argument checks, and writes honor offsets/counts. Never decode binary streams implicitly.
- Memory-stream close behavior follows the corresponding Java class (not a universal closed flag). File/socket streams reject operations after closure with the appropriate I/O exception.
- Closing a wrapper closes its owned underlying resource; repeated close is harmless. Flush drains pending encoder/output buffers; closing a text writer finalizes and flushes encoding before releasing its handle.
- UTF-8 conversion is incremental across buffer boundaries, including split multi-byte sequences and surrogate pairs. Match the selected Java constructor's malformed-input replacement semantics; unsupported charset names raise UnsupportedEncodingException.
- `BufferedReader.readLine` handles LF, CR, and CRLF, excludes terminators, returns the last unterminated line, and returns null at EOF with no remaining data.
- Relative file paths resolve against the launch working directory captured before the runner switches to its build directory. File output implements truncation versus append exactly; errors become catchable Java I/O exceptions.
- No real OS descriptors are stored as Java references. The host owns opaque handle IDs scoped to one VM run; Bend owns their Java-visible state. Release all handles on normal exit, uncaught failure, fuel exhaustion, timeout, and host-process error.

### Networking and host capabilities

- Deliver blocking TCP client and single-connection server paths using the same byte-stream and effect machinery as files. DNS and OS connect/bind/accept/read/write are host operations; Java validation, timeout interpretation, and exception mapping remain in Bend.
- Validate port ranges and Java timeout arguments. Support ephemeral server ports and report the actual bound port. A peer half-close produces EOF on input; closing a Socket closes its associated streams.
- Respect connect/read/accept deadlines; account for partial writes and reads. A zero Java timeout means no Java deadline, but an independent runner wall-clock limit may terminate the VM. Do not misreport runner termination as SocketTimeoutException.
- Add explicit launch controls for disabling application file access and networking. Keep archive/classpath loading distinct from application file access; this is a capability control, not a sandbox guarantee. Document defaults and denial behavior consistently with existing runner flags.
- Run network verification against local loopback servers only. No public services, external DNS dependency, Java thread implementation, or host JVM execution of application code.

## Ordered implementation slices

### 1. Unify intrinsic results and implement interface dispatch

Targets: `loader/bootstrap.bend`, `loader/catalog.bend`, `java/intrinsic.bend`, `runtime/execute.bend`, shared model/runtime APIs, and generated adapter code.

- Inventory exact method signatures/flags, replace constructor wildcard matching, and introduce the shared typed intrinsic result.
- Implement `invokeinterface` resolution through the existing class/interface graph, receiver validation, concrete target selection, and Java linkage errors. Do not claim Java 8 default-method support.
- Establish ordinary VM continuations for intrinsic-to-Java callbacks; migrate current println/constructor paths without compatibility shims.
- Integrate with milestone 1's suspension/result contract and update all constructors, destructuring sites, exports, and cache inputs affected by the change.

Acceptance: existing fixtures retain output; a user interface dispatches to two different implementations; null/invalid receivers fail correctly; an intrinsic returns a value and mutates heap state without losing the caller stack; unregistered constructors are not silently accepted.

### 2. Correct throwable objects and frame unwinding

Targets: `model.bend`, `runtime/execute.bend`, `runtime/state.bend`, `heap/heap.bend`, bootstrap and new throwable implementation under `java/`.

- Implement typed Java throw state, exception objects, catch matching, multi-frame search, and actual references on handler stacks.
- Add message/cause/suppression methods and the necessary exception hierarchy.
- Preserve initializer failure state; distinguish internal VM faults; make allocation-failure handling finite.

Acceptance: an unmatched first catch falls through to a matching superclass catch; exceptions cross three frames, retain identity through rethrow, and cannot be caught by unrelated types. Verify catch-all/finally, initializer failure, cause rules, and suppressed exception ordering. These cases become regressions for observed implementation gaps.

### 3. Core object, string, integer, and array utilities

Targets: exact bootstrap registrations, cohesive `java/` modules, existing string/array heap helpers, intrinsic callback continuations.

- Implement the core API rows, using UTF-16 and Java integer behavior.
- Provide user override dispatch for Object conversions and stable identity hashing.
- Implement arraycopy with overlap and failure semantics; account for allocation and bounded intrinsic work.

Acceptance: normal javac Java 8 concatenation works; surrogate indexing/hash/equality, immutable builder snapshots, integer overflow rejection, boxing cache identity, overlap copies, and partial reference-copy failures match OpenJDK.

### 4. Collections with Java interface contracts

Targets: MiniJRE List/Map/Iterator class metadata, `java/` collection implementations, heap-backed collection state, callbacks from slice 1.

- Implement ArrayList and HashMap with the API surface above; reuse Object/String equality and hashing.
- Support erased reference descriptors, boxing through Integer, mutation-aware iterators, and Java exception paths.
- Keep operations fuel-accounted, especially collision chains, resizing, and user callbacks.

Acceptance: interface-typed list/map programs match OpenJDK for null elements/keys, replacement/removal return values, colliding custom keys, custom equals/hashCode that throw, invalid indexes, exhausted iterators, and structural modification. Tests must not depend on unspecified map ordering.

### 5. Memory/file/text streams and try-with-resources

Targets: stream bootstrap types, `java/` I/O implementations, existing milestone 1 resource streams, host effect adapter, CLI capability controls, handle lifecycle.

- Complete memory streams and bulk operations before adding OS handles.
- Add file open/read/write/flush/close/stat requests and Java-visible file classes.
- Add incremental UTF-8 wrappers and buffered line reading.
- Exercise compiler-generated AutoCloseable calls and suppression with real resources; make teardown cover all VM exit paths.

Acceptance: copy binary data, append/truncate a temporary file, read split UTF-8/CRLF lines, consume an archive resource through the same InputStream API, and catch missing-file/closed-stream errors. Try-with-resources closes in reverse order and retains both primary and suppressed failures. Repeated runs, including fuel exhaustion, do not accumulate host handles.

### 6. Blocking TCP client and server

Targets: Java networking metadata/implementation, shared host effect handler, file/socket stream ownership, test-harness loopback helpers.

- Add address, socket, and server socket operations without a separate networking protocol.
- Implement timeout/error mapping, partial I/O, ownership of socket streams, and close/EOF transitions.
- Bound host waits independently from VM instruction fuel; implement network capability denial.

Acceptance: a Java client exchanges binary bytes with a local host server; a Java ServerSocket accepts a host client on an ephemeral port and responds. Compare observable bytes/exit state with OpenJDK. Cover refused connections, read/accept timeouts, peer EOF, repeated close, and closure on exceptional exit. Use deterministic synchronization rather than sleeps.

### 7. Integrated application, compatibility documentation, and release gates

Targets: `scripts/test.py`, reusable fixture sources under `bendjvm/tests/fixtures/`, `README.md`, `bendjvm-spec.md`, `ROADMAP.md`, and relevant laws/proofs.

- Extend the current harness with targeted runtime-expansion groups, isolated temporary files, archive packaging, and supervised loopback peers. Keep external services out of the suite.
- Run a small Java 8 application that reads a dependency resource, builds strings/collections, writes and rereads a file, exchanges bytes over TCP, and recovers from an I/O failure using try-with-resources.
- Package and launch that application through milestone 1's JAR/manifest path; also preserve standalone `.class` mode and existing debug/limit flags.
- Document exact supported descriptors, unsupported overloads, classpath/host ownership, capability controls, memory/handle/time limits, and error behavior. Update roadmap status only after every named deliverable is exercised.

Acceptance: integrated output/data agree with OpenJDK, existing suites pass, host handles are released on all exit paths, and the compatibility documentation does not imply full JDK or Spring Boot support.

## Dependency and parallel-work map

- Slices 1–2 establish shared runtime contracts. Slice 3 enables collection semantics; slice 4 follows it. Slice 5 needs throwable/effect contracts and the string helpers used by text I/O. Slice 6 follows the common stream/handle layer. Slice 7 integrates all slices and milestone 1.
- After shared contracts are fixed, collection implementation and host file-effect work can proceed concurrently in disjoint files. Networking fixture peers can be prepared alongside pure core-library work.
- One integration owner controls `model.bend`, bootstrap registration, runtime dispatch, runner transport, and harness integration. Do not let parallel writers independently define intrinsic IDs or shared state layouts.
- Parallelize independent Bend computation only where it preserves Java evaluation order and determinism. Java-visible callbacks, mutation, exception propagation, and I/O remain ordered. No Java threading is implied.

## Verification strategy

Before implementation, run `bend guide`; inspect exported-symbol references with an available language server before changing contracts. Record important Bend invariants in `LAWS.bend` and extend proofs where meaningful: reference preservation during unwinding, return-stack correctness, and resource-state transitions are candidates, not promises of proving OS behavior.

For each slice, compile ordinary fixture sources with `javac --release 8`, inspect emitted instructions with `javap -c -s` when a prerequisite is uncertain, then exercise the real generated runner. Do not work around missing interface dispatch or cleanup bytecode by writing fixtures against concrete classes only.

Keep focused regressions for uncertain boundaries and concrete bugs. Compare returned values, output, exception type/identity/cause/suppression, filesystem bytes, and TCP bytes; avoid source-text assertions, exact diagnostic prose, implementation layouts, hash bucket order, or timing equality.

Final commands:

```sh
python3 scripts/run.py --prepare
python3 scripts/test.py --fast
python3 scripts/test.py --full
bend PROOF.bend
```

Extend `--fast` with representative core/exception/stream coverage and `--full` with every runtime-expansion group, including local TCP. Run the packaged integrated application through the actual CLI in addition to focused tests. Exercise host teardown on timeout/abnormal termination with a supervised process. Run `bend PROOF.bend` before any commit.

## Completion checklist

- All three roadmap requirements have working end-to-end demonstrations.
- Every method in the minimum API matrix is implemented or the plan is explicitly revised with user approval; no no-op constructors or success-shaped placeholders.
- Interface invocation and typed exception propagation work across normal and intrinsic calls.
- Java owns heap/collection/throwable/stream state in Bend; the host performs only bounded OS effects.
- Files, dependency resources, text streams, collections, TCP clients, and a single-connection TCP server are usable from Java.
- Causes, suppression, finally/try-with-resources, initialization failures, and uncaught teardown preserve the specified behavior.
- Standalone and packaged launch modes, diagnostics, limits, and existing fixtures remain supported.
- Documentation and meaningful laws/proofs reflect implemented behavior. Remove throwaway probes and generated artifacts after verification; retain reusable fixtures and harness logic.

Planning verification: source-grounded documentation only. No runtime implementation, execution, or test success is claimed by saving this plan.
