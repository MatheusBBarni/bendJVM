# Plan: Spring Boot launcher support

Status: planned; no runtime changes implemented.
Source: `ROADMAP.md`, milestone 6.
Dependencies: [loading](01-jar-and-classpath-loading.md), [runtime expansion](02-java-runtime-expansion.md), [reflection/metadata](03-reflection-and-metadata.md), [bytecode](04-broader-jvm-bytecode-support.md), and [concurrency/native integration](05-concurrency-and-native-integration.md).

## Goal

Run an actual, small Spring Boot application from a normally repackaged executable JAR on BendJVM: execute the bundled launcher, load application classes and nested dependencies, discover configuration/resources, create a real Spring application context, invoke application beans, and close the context cleanly.

Loading a Boot-shaped ZIP or printing a banner is not completion. A Spring-like container from milestone 3 is not a substitute for running Spring Boot itself.

| Roadmap requirement | Deliverable |
| --- | --- |
| Support the Spring Boot launcher layout | Execute the pinned Boot JarLauncher from manifest Main-Class, preserving launcher/application loader separation and Start-Class handling |
| Resolve nested dependency JARs | Bounded nested archive access with correct source identity, archive ordering, and class/resource resolution |
| Load application resources and configuration files | BOOT-INF/classes resources, nested dependency enumeration/scanning, context-loader visibility, and real Spring externalized configuration |
| Run a small Spring Boot compatibility example | An unmodified-framework, reproducibly packaged Java 8 Boot application whose context, dependency injection, configuration, lifecycle, and shutdown match an OpenJDK reference |

## Version and compatibility target

- Pin Spring Boot **2.7.18** and its managed dependency graph for this milestone. Its documented minimum is Java 8; the documented Spring Framework minimum is 5.3.31. Pin the build plugin and dependency versions, not an unbounded `2.x` range.
- Treat this historical line as a compatibility fixture, not a recommendation for a new production service or a claim about its security/support status. Do not infer support for modern Boot releases with higher Java requirements or different launcher packages.
- Initial application type: **non-web Spring Boot application**, using the ordinary starter, real SpringApplication, annotation configuration/component discovery, bean injection, an ApplicationRunner, and explicit context closure. ROADMAP asks for a small compatibility example, not an embedded servlet-container milestone.
- Use `@SpringBootApplication(proxyBeanMethods = false)` as an ordinary application configuration choice. Do not remove default auto-configuration/logging or replace framework classes just to evade runtime gaps. Implement all remaining reachable requirements of the pinned fixture.
- Preserve the original Boot/Framework/dependency bytecode in the executable JAR. No shaded replacement framework, patched launcher, renamed application class, host JVM fallback, or host-side recreation of Spring's bean/configuration behavior.
- The required packaging target is the normal executable JAR with the 2.7 launcher family. WAR/WarLauncher, PropertiesLauncher/loader.path, launch-script-prefixed archives, layertools/jarmode execution, requiresUnpack libraries, signed-archive verification, nested native-library extraction, and later Boot launcher versions are explicitly not promised here.
- Include an exploded-layout differential fixture to verify classpath index behavior, but packaged `-jar` startup is the release gate. If an excluded feature is requested, fail clearly; do not silently treat it as the supported layout.

## Repository baseline and prerequisite gap

Current source still runs standalone classes:

- `scripts/run.py:main` selects a `.class` argument and guesses companion classes from target bytes. It does not currently implement the earlier plans' `-jar`, classpath sources, loader namespaces, or a Boot launch mode.
- The earlier five files are plans, not proof those milestones have shipped. Before implementation, run their relevant gates and inspect actual APIs; preserve their established boundaries where implemented.
- Milestone 1 explicitly excluded nested Boot archives and retained an eager dependency closure. Milestone 3 excluded custom class-loader subclasses, generic reflection, framework package scanning, and context-class-loader APIs. Milestone 5 excluded ThreadLocal and broad concurrency utilities. **Completing those plans does not by itself guarantee even this small Boot application can run.**
- The pinned launcher source calls Class.getProtectionDomain/CodeSource, creates archive objects, registers its jar URL handler, constructs a LaunchedURLClassLoader, installs it as Thread context loader, and invokes the application main reflectively.
- The Boot/Framework runtime also reaches Java library behavior beyond the previous minimum API matrices. Closing the fixture's actual dependency/API/bytecode requirements is a mandatory part of this milestone, not a deferred task after claiming launcher support.
- Reuse `scripts/test.py` for process execution, temporary fixture packaging, reference comparisons, and errors. Add a dedicated selectable Boot integration group rather than pretending ordinary integer fixtures prove framework compatibility.

## Verified upstream behavior

Primary references are listed at the end of this plan.

- Launcher classes live at the archive root under `org/springframework/boot/loader/`.
- Application classes/resources live under `BOOT-INF/classes/`; nested libraries live under `BOOT-INF/lib/`.
- Manifest Main-Class names `org.springframework.boot.loader.JarLauncher`; Start-Class names the application entrypoint. The VM launches Main-Class; the Java launcher selects Start-Class.
- Nested JAR entries in the outer archive must be **STORED** for this Boot loader, so it can seek into their contents. Entries within the nested JAR may be compressed. Supporting an ordinary deflated top-level JAR does not remove this Boot restriction.
- Boot's JarFile extends java.util.jar.JarFile, and its URLs work with JarURLConnection and URLClassLoader. Implementing only URL.openStream from milestone 3 is insufficient.
- Thread context class loader is the expected route to nested application libraries. The system loader must not be made to see every nested class merely to make tests pass.
- `ExecutableArchiveLauncher.getClassPathIndex` in v2.7.18 loads the classpath index only for **ExplodedArchive**. Packaged archives already have a defined order. Preserve the actual packaged archive iterator order; do not unconditionally sort dependency names or override it from classpath.idx.
- `BOOT-INF/layers.idx` is packaging/layer metadata, not an instruction to change class loading order.

## Architecture and ownership

### Launch the real launcher

- Keep one ordinary runner path: `python3 scripts/run.py [VM options] -jar app.jar [application arguments...]` from milestone 1.
- Read the normal manifest and load Main-Class from the outer archive. Execute the bundled JarLauncher bytecode in Bend. Do not introduce `if Spring then jump to Start-Class` semantics in Python or a framework-specific native launcher intrinsic.
- Host code supplies bounded file/range reads, decompression, and other OS effects. Boot archive selection, classpath construction, URL handler logic, Spring metadata/configuration parsing, and bean lifecycle run as their Java code where present.
- Extend MiniJRE/JDK primitives at their existing abstraction boundaries. For example, a java.util.zip inflater may use a host compression codec; a SpringApplication intrinsic that fabricates a context is prohibited.
- Keep framework/framework-loader classes subject to the same verifier, class initialization, exceptions, fuel/heap limits, reflection, method handles, and thread scheduler as application code.

### Nested source identity and bytes

- Extend the existing source model with an archive view identified by immutable outer-source identity plus an ordered chain of entry paths/offset ranges. A source is not merely the dependency basename.
- Allow the normal Boot shape: outer archive, BOOT-INF/classes directory view, and one level of library JARs under BOOT-INF/lib. Represent origin chains generally enough to avoid ambiguity, but impose an explicit nesting-depth limit; do not silently launch recursively executable Boot JARs as dependencies.
- STORED nested archives can use bounded seekable range views rather than extracting whole dependency trees. Keep archives indexed once; do not repeatedly decompress/copy each library on every lookup or parse all its classes at startup.
- Use the existing host ZIP primitives for ordinary JDK ZIP operations and byte sourcing. Where Boot executes its own nested archive parser, provide its required random-access/stream/Inflater/CRC primitives instead of replacing Boot's parser with a second policy implementation.
- Validate local/central-directory lengths, offsets, payload bounds, unsupported encryption/compression, CRC where read semantics require it, duplicate entries, and unsafe paths. A nested view cannot read outside its parent byte range.
- Apply limits cumulatively across nesting: entry count, compressed/uncompressed bytes, individual reads, open sources, total cached bytes, and depth. Nested boundaries must not reset decompression budgets.
- No disk extraction by default. Unsupported requiresUnpack/native-extraction paths report a limitation rather than writing to arbitrary filesystem locations.
- Cache keys include canonical outer source plus content/version identity and nested path; rebuilding app.jar must not reuse stale library/class bytes. Compiled Bend artifact caches must not embed application archive content.
- Preserve full origins in errors, e.g. `app.jar!/BOOT-INF/lib/library.jar!/pkg/Type.class`, while keeping archive URLs properly escaped rather than assembling them by naive string splitting.

### Loader namespaces, delegation, and lazy resolution

- Extend milestone 3's restricted loader model to execute the real Boot LaunchedURLClassLoader and its URLClassLoader ancestry. Class identity is `(defining loader, binary name)`; package identity/access checks include loader identity.
- Keep the bootstrap MiniJRE, outer launcher/system loader, and launched application loader distinct. Use the pinned launcher's delegation/resource behavior rather than a global flattened classpath.
- Add the ClassLoader/URLClassLoader subclass, lookup/definition, package, and protection-domain APIs reached by the actual loader. Defined bytes still pass the standard parser/verifier/publication transaction; no unverified defineClass path.
- Implement Class.getProtectionDomain and real CodeSource location metadata sufficient for launcher archive discovery. Do not return an arbitrary current-directory URL or a fake ProtectionDomain just for this class name. SecurityManager policy and signed-code certification remain outside the advertised subset.
- Implement Thread.getContextClassLoader/setContextClassLoader with Java inheritance and per-thread state; child threads see the inherited application loader. Do not replace getSystemClassLoader with the context loader.
- Class-loader locks, runtime publication, package metadata, mirror caches, and parallel-capable registration follow the supported concurrency model. Avoid deadlocks from holding a global VM lock while Java loader methods or resource effects suspend.
- Relax the previous eager dependency strategy where it would load every optional Boot auto-configuration dependency. Verify the defined class as required, but resolve symbolic references at the Java-specified use points; unused optional types in method bodies/metadata must not automatically abort unrelated startup.
- Distinguish allowed classpath presence probes (ClassNotFoundException/LinkageError observed by Java code) from malformed classes and missing required dependencies. Do not blanket-catch failures as `optional dependency absent`.
- All identity, casting, reflection, proxies/lambdas, method handles, generic Type objects, and package access checks must use the defining loader. A class loaded twice by distinct loaders is not assignment-compatible merely because its name matches.

## Required compatibility closure

Freeze the fixture and its resolved dependency graph first. Inventory declared/reachable API calls and actual startup failures, then implement the complete required Java contracts, not a list of fake return values. Static scanning alone is insufficient because reflection, configuration, logging, and loader callbacks reach additional paths.

The following are known areas to investigate and implement where reached; none is satisfied by claiming a previous milestone already covers all of java.*:

| Area | Required outcome for the pinned example |
| --- | --- |
| Archive I/O | File/RandomAccessFile-style seeking, ZipFile/ZipEntry/JarFile/JarEntry, Manifest/Attributes, compression/CRC and stream operations needed by the stock launcher |
| URLs | URI conversion, URL construction/handlers, URLConnection/JarURLConnection, URLClassLoader integration, and stable nested URL origin/access |
| Loader/type metadata | Class definition/lookup/package/protection-domain behavior, context loaders, and correct identity across loader boundaries |
| Reflection | Generic Signature/Type/ParameterizedType/TypeVariable/GenericArrayType/WildcardType and annotation/Method/Constructor APIs actually used by Spring's type/annotation resolution |
| Collections/text | Required Collection/Map/Set views, iteration, sorting/comparators/default methods, string operations, resource/Properties and charset paths beyond the earlier narrow matrices |
| Concurrency/context | ThreadLocal and any reached atomics/concurrent collections/locks with real semantics, not unsynchronized maps posing as Java concurrent APIs |
| System environment | Properties/getProperty/getProperties, getenv, locale/charset defaults, working directory, time, and required runtime/shutdown-hook behavior |
| Framework discovery | Nested package resource enumeration/scanning, metadata resources, service discovery where used, and optional dependency probing without eager resolution of all classes |
| Logging/lifecycle | The pinned starter's normal logging dependencies, Spring startup events/runners, context close/destroy callbacks, and required thread/handle shutdown |
| Bytecode/version | Every reached opcode/default-interface method/constant-pool form; support the actual base dependency class-file versions under their verifier rules |

Implementation rules:

- The previous parser's strict major-52 check is not enough evidence for third-party libraries: inventory actual base-entry versions in the pinned dependency graph. Add any required older class-file version handling with appropriate verifier rules; never rewrite version headers or run invalid code under the wrong verifier assumptions.
- Do not eagerly select `META-INF/versions/*` overlays for the Java 8 target. Newer entries in a multi-release dependency do not by themselves make the Java 8 base library unsupported.
- Use official API contracts and the reference JVM when adding default interface dispatch, generic reflection, loader methods, ThreadLocal, or concurrency utilities. These additions are explicit closure work in this milestone, not permission to weaken previous invariants.
- If Spring calls optional APIs on a guarded path, preserve their real error/availability behavior. Do not add `org.springframework.*` or logger-specific branching inside the interpreter to force a condition result.
- Maintain an implementation-time compatibility ledger with actual missing symbol/descriptor or bytecode, first caller, prerequisite owner, minimal observable regression, and completion evidence. Every item required by the fixed fixture is a completion blocker until implemented.
- A newly found required subsystem must be implemented or explicitly escalated for a user-approved scope change. Do not silently replace the real fixture with a plain Java main after discovery becomes difficult.

## Archive layout and order contracts

- For the packaged JarLauncher path, expose archive entries in the order observed from the pinned loader/reference artifact. Do not impose lexical ordering or automatically append arbitrary adjacent files from disk.
- Preserve BOOT-INF/classes and library source ordering exactly as constructed by JarLauncher; app-first precedence in ordinary plugin output must follow actual archive/launcher behavior, not a name-based hard-coded exception.
- Class duplicate behavior is normal ordered lookup within the correct loader. Resource enumeration includes distinct same-named resources in distinct nested JARs; never deduplicate by basename or resource path alone.
- Ordinary main-JAR manifest Class-Path behavior from milestone 1 must not be blindly applied as a second nested dependency resolver. Let the stock launcher/JDK URL loader execute their actual rules; do not flatten arbitrary external classpaths into the launched application.
- Test a packaged archive containing classpath.idx with an intentionally different listed order: match the pinned launcher's actual packaged behavior. Test the corresponding exploded layout where the index is consulted, including the manifest's Spring-Boot-Classpath-Index location override.
- Parse index files through the real launcher path; they are not general YAML documents. Validate unsafe references at the source boundary without inventing new valid-file ordering semantics.
- layers.idx does not affect runtime lookup. Unknown layout metadata is not a signal to guess another Boot version's behavior.
- Missing Main-Class/Start-Class, absent main method, missing required nested library, malformed nested archive, and unsupported launcher/layout must fail with origin-rich diagnostics, not fall through to a guessed class.

## Application resources and configuration

- BOOT-INF/classes is an application resource root: `application.properties` is requested without adding BOOT-INF/classes to the Java-facing resource name. Nested dependency roots behave the same way.
- Implement class-relative, loader-relative, `classpath:` and framework `classpath*:` resource behavior through the standard Java/Spring implementation paths. Spring scanning may require directory entries, URLConnection, and archive entry enumeration, not merely first-match InputStream lookup.
- Enumerate `META-INF/spring.factories`, `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`, and relevant services/index metadata from every source where present. Do not globally merge their bytes in the host; let the pinned Spring/Boot code parse and combine them.
- Preserve exact resource origins and nested URLs on reopen, even when multiple libraries have a file with the same name. Directory/prefix enumeration must remain bounded and must not decompress unrelated payloads.
- Resource scanning does not initialize every candidate class. Spring metadata inspection, presence checks, and normal VM initialization remain separate actions.
- Pass application arguments intact after `-jar`, including `--spring.profiles.active=...`, `--spring.config.additional-location=...`, and arbitrary application properties. Arguments with spaces/Unicode must survive the launcher/reflection boundary.
- Add runner `-Dkey=value` support if not already present; store system properties in the Java runtime, not solely in host environment variables. Expose environment variables with their real Java lookup semantics. Do not falsify java.version or feature detection to persuade Spring to choose an unimplemented code path.
- Relative external configuration resolves against the captured launch working directory, not the runner build/cache directory. Filesystem policy from milestone 5 still applies; denied/unreadable mandatory configuration must fail through the normal API.
- Let Boot's ConfigData pipeline implement profile activation, imports, placeholders, conversion, source precedence, and missing/optional locations. No Python parser may apply a simplified “Boot-like” override order.
- Required configuration format for the example is `.properties`; test packaged base/profile files, external files, command-line overrides, system properties, and environment overrides for selected keys. YAML and exotic ConfigData backends are not claimed merely because the starter contains their libraries.
- Preserve Properties byte/character decoding rules. Use a Unicode/escaped value in the end-to-end fixture to catch accidental UTF-8/Latin-1 substitutions.

## Reproducible real Boot example

### Build shape

Proposed implementation location: `examples/spring-boot-compat/`, with a pinned Maven build, application module, and a small dependency module. These files are deliverables of implementation, not created by this planning task.

- Pin Boot parent/dependency management and repackage plugin to 2.7.18; pin the build-tool/compiler configuration and record the resolved dependency graph/checksums and build JDK used for the reference artifact.
- Target Java 8 application bytecode. Build/reference execution may use a supported newer JDK, but compatibility assertions must account for the selected Java 8 runtime/library contract.
- Use the ordinary Spring Boot starter and its managed transitive dependencies. The helper dependency contributes a service/bean or scanned component and a resource that demonstrably originates from its nested JAR.
- Build the archive with the official repackage plugin. Do not manually create a pretend executable archive and call that the Spring Boot acceptance fixture. Keep tiny synthetic archive fixtures separately for parser/order failures.
- Dependency download occurs only during explicit fixture build/preparation, not when BendJVM loads a class. Cache artifact inputs and allow an offline rerun after preparation. Missing Maven/artifacts is an explicit integration-test prerequisite failure, not a reported pass.
- Set reproducible packaging timestamps/order where supported. Both OpenJDK and BendJVM execute the **same built JAR bytes** for comparisons; record the checksum to establish this.

### Application behavior

- Main calls SpringApplication.run using the annotated application class, not a handwritten bean registry. The default web type is NONE because no web starter is included.
- Use real component discovery and constructor injection of a helper-library bean into an application runner. Include an annotation-driven configuration value from application.properties and an overridden profile/external/CLI value.
- The runner emits a small stable result record derived from the injected service, selected configuration, a resource read from the nested dependency, and its received application arguments. It must fail if any input/bean is absent rather than printing a fixed success string.
- Observe a Spring lifecycle event and close the ConfigurableApplicationContext explicitly after runner completion; a destroy callback emits a stable teardown marker. Do not call System.exit merely to hide surviving threads/resource leaks.
- Keep default framework/logging output separate from stable application assertions. Do not compare nondeterministic timestamps/startup durations or suppress a framework startup error to obtain a cleaner transcript.
- Include a negative startup case (missing required configuration or a deliberately failing bean) proving Spring failure reporting reaches a nonzero runner result and cleanup still occurs.
- Keep the application small, but do not modify the selected target behavior after seeing gaps without explicit approval. An HTTP/Spring MVC example can be a later separately scoped extension, not an undisclosed replacement requirement or a reason to omit this genuine Boot context.

### Required executions

- OpenJDK `java -jar` positive baseline on the packaged fixture.
- BendJVM `-jar` on exactly the same artifact with equivalent working directory, system properties, environment, and arguments.
- Packaged base configuration, activated profile, external override, CLI override, and failure variant.
- Dependency resource/class duplicate-order fixtures, nested paths with spaces/Unicode, and a launch where the working directory differs from the JAR directory.
- Exploded reference/Bend launcher comparison for classpath.idx, distinct from the mandatory packaged-JAR path.

## Ordered implementation slices

### 1. Freeze the compatibility fixture and map real prerequisites

Targets: proposed example Maven/modules/resources, harness build/preparation helper, compatibility ledger, predecessor gate results.

- Build the pinned stock Boot application and run it on OpenJDK first; record dependency graph, archive entries/manifests, class-file versions, checksum, stable output, and lifecycle/configuration results.
- Inventory the real launcher and first framework execution requirements against the implemented MiniJRE. Identify closure items by actual symbols/descriptors/bytecodes and ownership, not broad claims that “reflection is done”.
- Fix the artifact/behavior target before iterating on BendJVM so reference evidence cannot drift to an easier example.

Acceptance: a real repackaged Boot artifact starts/closes under the reference JVM and exhibits every named application behavior; prerequisites and additional runtime areas have concrete evidence. This slice alone is not BendJVM compatibility.

### 2. Add bounded nested archive and source primitives

Targets: existing host classpath/source module from milestone 1, request protocol, Java file/ZIP primitives, archive view/resource ownership.

- Add origin-preserving nested range views, seek/read/decompression support, and cumulative limits.
- Support Java ZIP/JAR/Manifest APIs and low-level stream/random-access primitives required by the stock launcher without replacing Boot classes.
- Preserve packaged entry order, invalidation, path safety, and deterministic close behavior.

Acceptance: nested classes/resources are readable with correct full origins; stored outer/deﬂated inner entries work; unsupported compressed nested containers, corruption, unsafe paths, duplicate ambiguity, oversized content, stale caches, and out-of-parent reads fail predictably without extraction or application execution.

### 3. Execute the stock launcher with real loader namespaces

Targets: ClassLoader/URLClassLoader MiniJRE, namespace-aware runtime registry/verification, Class protection-domain metadata, Thread context loader, URL handler/connection support, ordinary runner manifest startup.

- Execute manifest Main-Class from the outer JAR and support the launcher-created LaunchedURLClassLoader.
- Implement the required loader APIs, CodeSource/URI discovery, package metadata, context-loader inheritance, and nested resource URLs.
- Preserve append-only publication and concurrency; replace inappropriate eager optional-dependency linking with correct resolution timing.

Acceptance: a stock loader-only Boot archive reaches its Start-Class in Bend without bypassing JarLauncher, forwards arguments, and loads a nested helper. The helper is visible through the context loader but not accidentally through the system loader; type identities/access checks differ correctly across loaders. Framework context startup is still a separate gate.

### 4. Preserve classpath order and resource discovery

Targets: nested source enumeration, URLConnection/JarURLConnection support, framework scanning primitives, exploded source/index integration.

- Exercise packaged archive iteration order and exploded classpath.idx semantics against the exact pinned launcher.
- Implement bounded directory/prefix/archive resource enumeration and origin-bound stream reopening.
- Ensure duplicate framework metadata resources remain discoverable across dependencies and layers.idx does not alter lookup.

Acceptance: duplicate class/resource selection and all-match enumeration agree with OpenJDK for packaged and exploded fixtures, including deliberately conflicting index order, custom index location, nested paths, and missing/invalid entries. Spring-required scanning primitives do not initialize candidates as a side effect.

### 5. Close the pinned Spring runtime/API requirements

Targets: existing java/runtime/loader/verifier modules according to the evidence ledger; new cohesive modules only where needed.

- Implement required generic reflection, collection/default-method, ThreadLocal/concurrency, system/environment, logging, lifecycle, and class-file-version contracts missing after milestones 1–5.
- Add focused observable regressions for each nontrivial gap using ordinary Java/reference behavior before rerunning full Boot startup.
- Preserve ordinary missing-type checks and lazy resolution while refusing malformed bytecode or fake unsupported-API success.
- Execute unmodified dependency classes in Bend; no Spring/ASM/logger class-name special cases in the interpreter.

Acceptance: the frozen artifact reaches and completes real Spring context refresh, runs its injected ApplicationRunner, and closes correctly. Every required ledger entry has implemented behavior and evidence; no unresolved gap can be labelled “launcher complete” merely because Main-Class executed.

### 6. Verify real configuration loading and application resources

Targets: runner system-property/argument/environment transport, resource/source APIs, Properties/stream operations, example resource/configuration variants.

- Pass JVM-style properties and Boot application arguments through the ordinary paths.
- Let Boot ConfigData perform packaged/profile/external/import/override processing and Spring parse its metadata resources.
- Ensure application/dependency resources are located through the launched loader and external paths honor launch cwd/capabilities.

Acceptance: compare selected values across base/profile/external/system/environment/CLI cases to OpenJDK using the same artifact. Include optional-versus-required missing config, Unicode/escape values, nested-origin resource content, and denied external access. Configuration failure cannot produce the successful application result record.

### 7. Integrate lifecycle, limits, failures, and repeatability

Targets: scheduler/loader/effect teardown, Boot harness group, artifact caches, diagnostics, negative variants.

- Run repeated startup/close with bounded heap/fuel/source/handle settings and concurrent-safe class loading enabled.
- Exercise missing Start-Class/dependency, wrong loader/version, malformed nested archive, bean initialization failure, and resource/runner-limit termination.
- Ensure framework close and whole-VM teardown release archives, streams, threads, native/host resources, and pending effects according to their ownership.

Acceptance: no stale class/source cache leaks across artifact rebuilds, no output-only success after context failure, no leftover non-daemon threads/host helpers, and errors identify the launcher/application/nested origin involved. The real context close marker occurs once on successful runs.

### 8. Compatibility gates and documentation

Targets: `scripts/test.py`, example build sources, README/spec/roadmap, relevant laws/proofs and compatibility support matrix.

- Add a selectable Boot integration group with explicit build/JDK/artifact prerequisites and an offline execution mode after preparation. Keep small archive/loader regressions in routine suites; full release verification includes the real Boot group.
- Document exact Boot/Framework/build versions, checksum provenance, supported launcher/layout, non-web application feature slice, API extensions, rejected layouts, configuration scenarios, and remaining library/security limitations.
- Update ROADMAP/README only after all four roadmap deliverables pass. Distinguish “tested Boot 2.7.18 non-web fixture” from “runs arbitrary Spring Boot applications”.

Acceptance: reproducible build and reference/Bend runs are executable from documented commands, all predecessor regressions pass, every named Boot scenario has proof, and no unsupported web/container/JDK claim appears in documentation.

## Dependency and parallel-work map

- Slice 1 fixes the actual artifact and exposes dependencies. Slice 2 supplies archive primitives; slice 3 consumes them and loader identity; slice 4 validates order/resource APIs. Slice 5 closes the runtime requirements; slice 6 proves configuration; slice 7 hardens lifecycle/failures; slice 8 gates delivery.
- After archive-source/loader contracts are fixed, generic-reflection/library closure work and host archive primitives can proceed concurrently in disjoint files. Reference fixture preparation and order/configuration fixture generation can proceed alongside runtime implementation.
- One integration owner controls loader identity, stable IDs, protocol/schema changes, shared VM/API records, bootstrap registrations, and harness result contracts. Do not let one worker flatten nested classpaths while another builds true loader namespaces.
- Parallelize independent metadata validation, archive indexing, and fixture builds where deterministic source order is retained. Java launcher decisions, class definition, initialization, configuration precedence, and bean lifecycle remain under ordinary Java/Bend sequencing.

## Verification strategy

Before Bend implementation, run `bend guide`, inspect exported-symbol references with an available language server, and re-read preceding milestone APIs. Retrieve the exact upstream source/dependency versions being exercised; unversioned current Boot documentation is not the authority for a Java 8-era launcher.

Evidence is layered:

1. **Reference artifact:** official repackage build; OpenJDK startup, bean output, selected properties, resource origins, close marker, and checksum.
2. **Archive primitives:** real nested bytes, order, bounds, invalid input, and cleanup; these checks do not prove Spring execution.
3. **Stock launcher:** evidence that JarLauncher ran in Bend, created/used the launched loader, and invoked Start-Class. Do not assert only an internal dispatch-table string.
4. **Framework context:** injected service behavior, configuration binding, Spring event/runner lifecycle, failure behavior, and context close from the same artifact.
5. **Regression/limits:** prior milestone suites, runtime limits, repeated launch/cache invalidation, malformed archives, and teardown.

Use the same JAR bytes, working directory, configuration files, environment values, system properties, and application arguments for reference/Bend runs. Compare stable application events/data and exit semantics; do not compare banners, log timestamps, startup duration, reflection order, or generated class names.

Suggested implementation-time commands (the example and Boot harness option do not exist yet):

```sh
mvn -f examples/spring-boot-compat/pom.xml clean package
java -jar examples/spring-boot-compat/app/target/spring-boot-compat.jar
python3 scripts/run.py --prepare
python3 scripts/run.py -jar examples/spring-boot-compat/app/target/spring-boot-compat.jar
python3 scripts/test.py --fast
python3 scripts/test.py --full
python3 scripts/test.py --boot
bend PROOF.bend
```

The build must configure that stable finalName, and the harness must implement `--boot` before documenting these as runnable commands. `--boot` runs the real reference/Bend integration and fails clearly when build/artifact prerequisites are missing; it never reports skipped Boot execution as compatibility success. Release acceptance requires `--full` and `--boot` together.

Fetch Maven dependencies only during explicit preparation. Do not require public network access for the runtime checks. Generate corrupt/special-order fixtures under temporary directories, keep framework JARs cached outside source control, and preserve required third-party notices if any binaries/sources are redistributed.

Candidate laws: a nested view's readable range stays within its parent; source identity includes nesting/loader identity; appending a class cannot change an existing loader/type identity; resource enumeration preserves ordered distinct origins; failed class publication leaves the visible namespace unchanged. Prove pure bounded invariants, not Spring's complete behavior or host ZIP implementation correctness. Run `bend PROOF.bend` before committing.

## Completion checklist

- The actual pinned JarLauncher executes in Bend; manifest Main-Class is not bypassed for Start-Class.
- BOOT-INF/classes and stored nested BOOT-INF/lib JARs resolve classes/resources with correct bounds, order, URL origins, and cleanup.
- System versus launched/context loaders retain distinct visibility and correct type/package/protection-domain identity.
- All required additional runtime/library/version behavior is implemented; completion of earlier plans is not used as a substitute for evidence.
- Spring itself performs context creation, component discovery, dependency injection, configuration resolution, application runner/lifecycle behavior, and context closure.
- The same official-plugin-built artifact runs under OpenJDK and BendJVM with equivalent stable results for every required configuration/failure scenario.
- The example is genuinely Boot, not the earlier Spring-like fixture, a host JVM subprocess, patched framework, or a fixed-output simulation.
- Ordinary class/JAR behavior and prior runtime/reflection/bytecode/threading/IO tests remain supported.
- Documentation names the exact tested version/layout/non-web scope and does not imply general Boot/web-container support.
- No required prerequisite is deferred behind a success claim; any scope change needs explicit user approval. Remove throwaway probes/generated artifacts after verification while retaining reproducible fixture/build/harness sources.

## Primary sources used for this plan

- [Spring Boot 2.7.18 system requirements](https://docs.spring.io/spring-boot/docs/2.7.18/reference/html/getting-started.html#getting-started.system-requirements): Java 8 minimum and Spring Framework/build-tool requirements.
- [Spring Boot 2.7.18 executable JAR format](https://docs.spring.io/spring-boot/docs/2.7.18/reference/html/executable-jar.html): layouts, launcher manifest, nested ZIP storage, URLs, context-loader restrictions, and index formats.
- [v2.7.18 JarLauncher.java](https://github.com/spring-projects/spring-boot/blob/v2.7.18/spring-boot-project/spring-boot-tools/spring-boot-loader/src/main/java/org/springframework/boot/loader/JarLauncher.java): actual nested archive selection.
- [v2.7.18 ExecutableArchiveLauncher.java](https://github.com/spring-projects/spring-boot/blob/v2.7.18/spring-boot-project/spring-boot-tools/spring-boot-loader/src/main/java/org/springframework/boot/loader/ExecutableArchiveLauncher.java): Start-Class, packaged versus exploded ordering, and classpath-index handling.
- [v2.7.18 Launcher.java](https://github.com/spring-projects/spring-boot/blob/v2.7.18/spring-boot-project/spring-boot-tools/spring-boot-loader/src/main/java/org/springframework/boot/loader/Launcher.java): protection-domain archive discovery, URL class-loader creation, context loader, and application invocation.

Planning verification: grounded in current repository source, preceding plans, and pinned upstream documentation/source. No Boot fixture was built or run for this documentation-only change; no runtime compatibility or test success is claimed.
