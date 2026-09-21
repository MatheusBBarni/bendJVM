# Plan: JAR and classpath loading

Status: planned; no runtime changes implemented.
Source: `ROADMAP.md`, milestone 1.

## Goal

Run a Java 8 application from directories, JARs, or ZIPs; resolve its local dependencies in a deterministic classpath order; read dependency resources from Java code; and launch an executable JAR using its manifest. Preserve standalone `.class` execution and Bend-owned JVM semantics.

All four roadmap requirements are deliverables:

| Requirement | Delivery |
| --- | --- |
| Read classes from JAR/ZIP files | Ordered directory/archive source abstraction and bounded entry reads |
| Resolve application dependencies | Bend-driven transitive dependency discovery and first-match classpath lookup |
| Load resources from dependency archives | Java-visible resource streams backed by the same ordered sources |
| Manifest-based startup | `-jar`, `Main-Class`, and local manifest `Class-Path` expansion |

## Repository baseline

- `scripts/run.py:main` selects a `.class` argument and guesses immediate sibling dependencies by searching their stems in the target bytes. It does not resolve packages or transitive dependencies.
- `scripts/run.py:host_source` transports filenames through newline-separated environment variables, reads all supplied files, calls the generated Bend loader, then runs the generated runtime.
- `bendjvm/loader/class_loader.bend:load_many` parses supplied classes, appends bootstrap classes, builds a catalog, and links the VM. Keep class-file interpretation and linking in Bend.
- `bendjvm/runtime_api.bend:entry_method` selects the first matching method name/descriptor across all loaded methods. It does not constrain selection to a requested entry class.
- `bendjvm/main.bend` has a separate startup implementation. Any shared startup/API changes must migrate this caller too, not leave divergent entry semantics.
- `bendjvm/loader/bootstrap.bend` and `bendjvm/java/intrinsic.bend` provide a small MiniJRE, not general class-loader or stream support.
- `scripts/test.py` compiles temporary Java 8 fixtures and compares output with OpenJDK. Extend this harness rather than introducing a second test framework.
- The artifact cache hashes `scripts/run.py` and Bend sources. Any new source incorporated into generated host artifacts must also participate in invalidation.

## Scope and compatibility contract

### Launch forms

```text
python3 scripts/run.py [VM options] Main.class [application arguments...]
python3 scripts/run.py [VM options] -cp <entries> com.example.Main [application arguments...]
python3 scripts/run.py [VM options] -jar app.jar [application arguments...]
```

- Accept `-classpath` and `--class-path` as spellings of `-cp`. Split entries with `os.pathsep`; preserve spaces and Unicode in filenames and arguments.
- Class-name mode uses explicit classpath, otherwise `CLASSPATH`, otherwise the current directory. Empty path entries mean the current directory.
- For `.class` mode, parse its internal name in Bend and derive the package root from the path. Require the path suffix to agree with that name. Search that root before explicit/environment dependency entries; pin the explicitly selected class bytes as the entry class.
- `-jar` uses the selected archive and its manifest dependencies, ignoring ordinary classpath settings as the Java launcher does.
- Stop parsing VM options at the launch target. Application arguments must become a real Bend-owned `String[]`, including a non-null empty array when no arguments are supplied.
- Preserve existing fuel, heap, dump, disassembly, trace, preparation, and harness invocation behavior. Retain the existing `bendjvm/main.bend --` runner prefix consumed by the harness.
- CLI usage errors exit 2; loading, manifest, and VM failures exit 1 with diagnostics on stderr. Never execute `main` after startup failure.

### Class and archive lookup

- Sources are directories or local JAR/ZIP archives, searched left to right. Resolve `com/example/Main` as exactly `com/example/Main.class`, not by basename or byte substring.
- Use Python standard-library `zipfile` for archive indexing and decompression. No shell extraction, external ZIP executable, or new package dependency.
- Bootstrap definitions cannot be replaced by application entries. First matching application definition wins across sources; reject duplicate entry names within one archive to avoid ambiguous lookup.
- Keep physical origins for diagnostics. Validate the parsed internal class name against the requested name; a corrupt first match is an error, not permission to fall through to another source.
- Missing classpath entries can remain non-matching entries, consistent with Java. An archive that exists but cannot be read or is corrupt must report its origin rather than silently disappear.
- Parse only the transitive class closure needed by the existing eager linker, not every class in every dependency. Unrelated classes with unsupported bytecode must not break startup.
- Dependency discovery comes from Bend-parsed class structure: superclass, interfaces, member owners, relevant descriptors, catch types, and class/array references needed by linking. Arrays resolve reference element types, not fictional `[L...;.class` files. Use a visited set to terminate cycles.
- Document that this preserves eager linking of the selected closure; it is not full JVM lazy class loading or support for dynamically named classes.
- Read archive entries without extraction. Reject unsafe entry names (absolute paths, traversal components, backslashes), encrypted entries, unsupported compression, and corrupt payloads/CRC. Support stored and deflated entries.
- Enforce documented per-entry and total decompressed-byte limits while reading, not solely from ZIP metadata. Keep archive-byte limits separate from simulated VM heap limits. Close archives on success and failure.

### Manifest startup

- Read `META-INF/MANIFEST.MF`; parse the main section, continuation lines, case-insensitive attribute names, UTF-8 values, and CRLF/LF line endings. Named sections must not override startup attributes.
- Require a non-empty, valid `Main-Class` for `-jar`; normalize the binary name to an internal class name and validate its public static `main([Ljava/lang/String;)V` entry in Bend.
- Expand manifest `Class-Path` for JAR sources in both classpath and `-jar` mode. Entries are space-separated URL references, not platform-separated paths.
- Resolve local relative URLs against the containing JAR, including percent-encoded spaces. Insert dependencies immediately after their owning archive in declared order; expand transitively with canonical-source deduplication and cycle termination.
- Support local file references and directories. Reject remote URL schemes explicitly; never fetch dependencies. Missing manifest dependencies behave as missing search entries and fail when required.
- Fix ordering with OpenJDK differential cases involving an explicit trailing classpath source, transitive dependencies, and a cycle.

### Java-visible resources

- Provide the minimal standard API slice needed to consume resources without reflection: `ClassLoader.getSystemResourceAsStream(String)`, `InputStream.read()`, and `InputStream.close()`.
- Search classpath-root-relative, case-sensitive resource names in the same effective source order as classes. First match wins; missing resources return Java `null`; a present empty resource produces a stream returning `-1` immediately.
- Preserve binary bytes, including zero and values above 127. `read()` returns 0–255 or `-1`. Independent opens have independent positions; closing releases stream state. Define and test closed-stream behavior against the chosen MiniJRE implementation, without claiming behavior uniform across every OpenJDK stream type.
- Bend owns resource lookup requests, heap references, stream positions, and exceptions. The host supplies bytes only; it must not emulate Java objects or decide method behavior.
- Use a narrow request/resume boundary for resource reads so archives need not be fully decompressed at startup. Read a selected resource once per open and let Bend execute subsequent byte reads; do not cross the host boundary per byte.
- `Class.getResource*`, URLs, enumeration, service loading, reflective class loaders, and a general stream library remain later work. This milestone must nevertheless demonstrate resource consumption by an actual Java application, not only a Python helper.

### Explicit non-goals

Spring Boot layouts and nested JARs, Maven/Gradle dependency downloading, wildcard classpath expansion, modules, signature verification and package sealing, custom class loaders, reflection, `invokedynamic`, threads, networking, and broad standard-library expansion. Use Java 8 base entries; do not select multi-release entries under `META-INF/versions/`. Loading an archive does not imply that its library bytecode is supported.

## Architecture and ownership

1. **Host source layer:** add `scripts/classpath.py` for ordered source handles, bounded byte reads, resource lookup, and manifest expansion. Keep CLI/build/process orchestration in `scripts/run.py`.
2. **Bend loading session:** add a small loader session API alongside `class_loader.bend` that accepts the requested class and supplied bytes, parses once, and returns requested unresolved names or a linked result. Reuse the parser/catalog; do not add a Python class parser for dependency discovery. Cache parsed classes for final linking rather than reparsing the closure.
3. **Transport:** replace ad hoc classfile/flag environment strings in the practical runner with a structured, versioned launch/request protocol. Use a dedicated IPC channel or tagged records consumed by Python so internal requests never leak into application stdout. Send origin metadata and bytes without splitting paths on whitespace/newlines. No persistent cache of application archive contents in compiled artifacts.
4. **Runtime startup:** pass the selected entry identity and application arguments explicitly. Share startup logic between `runtime_api.bend` and the alternate Bend entrypoint. Let Bend validate access/signature, allocate arguments within heap limits, and initialize the entry class.
5. **Resource execution:** extend the runtime result/state boundary for a pending resource request and resume exactly once with bytes, absence, or an I/O error. Update all VM construction/destructuring sites and intrinsic callers. A host round trip must preserve frames, output ordering, exceptions, and the remaining fuel budget.

These interfaces are proposed contracts, not existing APIs. Before editing exported symbols, inspect references with the available language server and map every adapter/caller. Run `bend guide` before Bend implementation. Record durable invariants in `LAWS.bend`; avoid host-side copies of JVM semantics.

## Ordered implementation slices

### 1. Explicit startup and structured launch transport

Targets: `scripts/run.py`, `bendjvm/runtime_api.bend`, `bendjvm/main.bend`, applicable argument adapters and heap helpers.

- Replace suffix scanning with unambiguous option/target parsing and structured argument transport.
- Select the entry class explicitly, check entry flags/signature, and construct `String[]` arguments.
- Consolidate duplicate startup behavior and update generated export discovery/cache inputs.
- Keep standalone class execution working before adding archives.

Acceptance: two loaded classes with `main` cannot change the selected target; empty and Unicode/spaced arguments reach Java correctly; invalid entry methods fail before execution; existing CLI modes retain behavior.

### 2. Ordered directory classpaths and Bend-driven dependency closure

Targets: new `scripts/classpath.py`, loader session/API, existing parser/catalog integration, runner host adapter.

- Resolve package-qualified class names across ordered directory roots.
- Replace sibling byte-substring matching with requests produced from Bend-parsed dependencies.
- Maintain stable source selection and cycle handling; parse once and feed the selected closure to the existing linker.
- Protect bootstrap ownership and validate requested versus declared class identity.

Acceptance: a packaged application resolves a dependency and its transitive parent/helper from separate roots; reversing duplicate-class roots changes observable output; cycles terminate; a malformed unrelated class is not parsed; a missing required class identifies its requester and searched origins.

### 3. JAR/ZIP byte sources

Targets: `scripts/classpath.py`, runner diagnostics, archive fixture generation in `scripts/test.py`.

- Add archive indexing and entry reads under the exact same lookup contract as directories.
- Support stored/deflated payloads, bounded decompression, deterministic errors, and handle cleanup.
- Preserve first-match behavior when mixing roots, JARs, and ZIPs.

Acceptance: the same application runs from a directory, JAR, and ZIP with identical output; transitive dependencies span mixed sources; duplicate entries, name mismatches, corrupt/unsupported archives, and oversized payloads fail without executing the application or extracting files.

### 4. Manifest application launch

Targets: manifest/source logic in `scripts/classpath.py`, CLI in `scripts/run.py`, startup validation already delivered by slice 1.

- Implement `-jar`, main-section parsing, and transitive local `Class-Path` expansion.
- Resolve manifest URLs relative to each declaring JAR, with deterministic duplicate/cycle handling.
- Keep runtime options and application arguments distinct; ignore external classpaths in JAR launch mode.

Acceptance: a folded manifest starts the specified packaged main and resolves a sibling dependency through a path containing spaces; transitive/cyclic manifests terminate in the expected order; missing/invalid startup metadata and remote references produce actionable failures.

### 5. Dependency resource streams

Targets: source/IPC layers, `model.bend`, runtime state/execution, `loader/bootstrap.bend`, `java/intrinsic.bend`, heap support, and every affected API adapter.

- Add the minimal ClassLoader/InputStream signatures and Bend-owned stream state.
- Implement resource request/resume with bounded byte transport and Java-visible missing/error behavior.
- Keep resource paths separate from class-name normalization and class parsing.

Acceptance: Java reads and prints/checks bytes from a dependency archive; duplicate resources obey classpath order; missing/empty/binary resources, EOF, independent streams, and close behavior work; suspension does not reset fuel or duplicate output. Exercise heap exhaustion and resource-read failure paths.

### 6. Integrated milestone verification and documentation

Targets: `scripts/test.py`, `bendjvm/tests/fixtures/`, `README.md`, `ROADMAP.md`, relevant sections of `bendjvm-spec.md`, and `LAWS.bend`/`PROOF.bend` where invariants warrant proofs.

- Extend the existing harness to package temporary fixtures and run every launch mode against OpenJDK where contracts overlap. Use Python ZIP generation for malformed archive cases.
- Retain only behavior-focused regression cases for the risks above; do not assert generated source strings or internal record layouts.
- Run a final application using manifest startup, transitive archive dependencies, application arguments, and a dependency resource together.
- Update usage, compatibility boundaries, host/Bend responsibilities, limits, and examples. Mark milestone completion only after all four roadmap requirements pass; do not imply Spring Boot support.

## Dependency and parallel-work map

- Slice 1 establishes the launch/startup contract; slice 2 establishes the source/session boundary; slice 3 builds on slice 2; slice 4 builds on slices 1 and 3; slice 5 uses slices 1–3; slice 6 integrates everything.
- After agreeing the source and IPC contracts, archive/manifest host work and Bend resource-stream work may proceed concurrently with separate file ownership. The integration owner owns `scripts/run.py`, shared VM/API edits, and final validation.
- Packaging fixture preparation can run alongside implementation after CLI semantics are fixed. Never let concurrent agents independently redesign the protocol or edit the same shared model.
- Within Bend, parallelize independent parsing/validation where supported; commit selected definitions and IDs in deterministic source order. Do not parallelize order-dependent lookup or initialization.

## Verification gates and completion

During implementation, run each slice's focused scenario before moving on. Archive and manifest boundary tests can run without rebuilding Bend; VM behaviors require the real generated runner, not mocked linking or intrinsics.

Final commands:

```sh
python3 scripts/run.py --prepare
python3 scripts/test.py --fast
python3 scripts/test.py --full
bend PROOF.bend
```

Extend the existing suite so `--full` includes the classpath/archive/manifest/resource scenarios; add representative packaged startup and resource checks to `--fast`. Run the integrated manifest application manually through the real CLI and compare stdout/exit status to the reference JVM. Run `bend PROOF.bend` before any commit.

Completion requires all four roadmap rows, preserved standalone behavior, no accidental bootstrap replacement, deterministic precedence, correct selected entry/arguments, bounded archive reads, actual Java-visible resources, useful origin diagnostics, and updated documentation. Remove temporary experimental scripts and generated archives after verification; keep reusable fixture sources and harness packaging logic.

Planning verification: grounded in current runner, loader, runtime entry, bootstrap/intrinsic, and harness sources. Runtime tests are intentionally not claimed or executed for this documentation-only change.
