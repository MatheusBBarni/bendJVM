# Plan: Reflection and metadata

Status: complete, with no exclusions of its own left (2026-11-05).
Bend 2.0.39 artifact preparation succeeds; `scripts/test.py --fast --bend scripts/run.py` passes 89 tests and `--full` passes 141.
`bend PROOF.bend` reports `ALL PROOFS CHECK`.
The original bounded slices are below; the former exclusions became completion slices C1-C11 at the end of this plan, each gated by a JDK-oracle fixture.
Threads and the context class loader moved to plan 05, and Spring Boot nested-JAR layouts to plan 06.

Source: `ROADMAP.md`, milestone 3.
Dependencies: [JAR and classpath loading](01-jar-and-classpath-loading.md) and [Java runtime expansion](02-java-runtime-expansion.md).

## Goal

Run a small Java 8 application that discovers configured classes, reads runtime annotations, constructs and wires objects reflectively, intercepts interface calls through a dynamic proxy, and reads configuration from dependency archives.

The deliverable is a bounded reflection-capable MiniJRE, not Spring Boot compatibility or full OpenJDK reflection.
The 2026-11-05 decision in [Completion of the remaining exclusions](#completion-of-the-remaining-exclusions) widened this goal: plan 03 now ends with no exclusions of its own.

| Roadmap requirement | Deliverable |
| --- | --- |
| Parse runtime annotations | Validated structured annotation metadata retained through linking and exposed through Java annotation APIs |
| Reflective class, method, field, and constructor access | Class mirrors, member discovery, access checks, field reads/writes, method invocation, and construction |
| Support dynamic proxies | Java Proxy/InvocationHandler contracts backed by Bend-owned synthetic classes and normal VM invocation |
| Resource lookup for framework configuration | Class-relative and class-loader resource lookup, ordered enumeration, local resource URLs, and properties configuration |

## Current implementation and blockers

This section and the scope below record the original bounded slice.
Its open items were closed later by plan 04 and by slices C1-C11 at the end of this plan.

Repository evidence:

- `bendjvm/classfile/annotation.bend`, `model.bend`, and `loader/catalog.bend` validate and retain structured declaration, parameter, default, type, enum, Class, nested, and array annotation metadata through linking.
- `java/library.bend` exposes bounded Class/member reflection, caller-sensitive access checks, per-handle accessibility, runtime annotation materialization, recursive `@Inherited` lookup, repeatable containers, structural annotation equality, and cached enum singleton values.
- `Proxy` uses Bend-owned synthetic classes, canonical `(loader, ordered interfaces)` catalogs, interface validation, primitive category-one boxing, Object-method dispatch, and checked-throwable wrapping.
- `scripts/run.py` enumerates valid classpath classes in addition to bytecode dependencies, so configuration-only `Class.forName` and `ClassLoader.loadClass` lookups work without eagerly admitting malformed entries.
- `Class.forName` normalizes binary names, supports the one-argument and
  `(String, boolean, ClassLoader)` forms, and directly initializes the target
  `<clinit>` only when requested; the runner publishes configuration-only
  classes from dependency archives.

The current bounded expansion adds:

- caller/protected receiver checks, final instance-field restrictions, reflective virtual dispatch, constructor rejection for interfaces/abstract/enum targets, and public-constructor filtering;
- a single logical-slot raw-word long/double representation with long arithmetic, `lshl`, `i2l`, `l2i`, `dadd`, `dsub`, `dneg`, wide fields/calls/returns, boxed `Long`/`Double` value accessors, and bounded decimal formatting;
- custom loader object acceptance for the existing application catalog, default-interface fallback when class dispatch has no concrete override, `Method.isDefault()` fallback reflection, `InvocationTargetException` wrapping at reflective unwind boundaries, `Throwable(Throwable)` cause-to-message initialization, and `AnnotatedType` exposure for method return/parameter sites, including type-argument paths on parameterized returns;
- Java 8 method `Signature` attributes for generic return, parameter, and exception types, including `ParameterizedType` argument arrays and `TypeVariable` names. Non-generic throws stay on the `Exceptions` attribute when the signature omits them. `Class.forName(name, initialize, null)` uses the bootstrap loader for bootstrap classes.
- Field and class `Signature` attributes for `Field.getGenericType`, `Field.getAnnotatedType`, and `Class.getGenericSuperclass`, including type-argument annotations on fields.

The original slice left these incomplete (all done since): true category-two JVM stack/local layout and the remaining long/double opcodes/conversions, loader identity and multiple independent namespaces, special default-method proxy invocation, parameter-name reflection, `AnnotatedType` coverage for local-variable and expression targets, and byte-for-byte OpenJDK formatting/exception-message compatibility.

## Scope and boundaries

### Dependencies to reuse

- Milestone 1 supplies deterministic classpath/archive lookup, a Bend-driven loading session, source identity, manifest dependency order, and resource byte requests. Extend it for runtime requests and resource enumeration; do not add another scanner or Python class parser.
- Milestone 2 supplies interface dispatch, typed throwable objects, heap-mutating intrinsic results, Java callback continuations, boxed integers, collections, stream APIs, and cleanup. Reflection and proxies must use these paths instead of hidden host execution.
- Add category-one primitive wrapper support missing from milestone 2: Boolean, Byte, Short, Character, and Float, including `valueOf`, primitive-value accessors, and primitive `TYPE` mirrors. Add `Void.TYPE` and metadata-only primitive mirrors for all Java primitive types.
- Preserve raw long/double annotation constants and materialize them through boxed `Long`/`Double` reflection values using high/low U32 words. The current runtime additionally supports a single logical VM slot for bounded long arithmetic, `dadd`, wide field/call/return transport, and wrapper accessors; true category-two stack/local semantics and the remaining opcodes remain excluded.
- Add only the enum support required to compile and consume Java 8 annotation enum values: Enum construction/name/ordinal/identity semantics, constant lookup, and array cloning used by javac-generated `values()`. Enum switch execution remains milestone 4.

### Original exclusions (superseded)

These were the original slice's exclusions; slices C1-C11 removed them, and threads and Spring Boot archive layouts moved to plans 05 and 06.

Custom loader instances may resolve names from the existing application catalog, but arbitrary `defineClass`, loader identity, and multiple application-loader namespaces remain unsupported; modules/security managers, MethodHandles, `invokedynamic`, Class type-parameter and generic-interface reflection beyond recorded method/field/superclass signatures, parameter-name reflection, serialization of reflection/proxy objects, Java threading/context-class-loader APIs, subclass-based proxies, default-method special invocation, Spring Boot archive layouts, and general classpath/package scanning are also excluded.

Generic Signature and other unsupported attributes must not be invented into reflection results. Preserve validated metadata where useful, but advertise only implemented APIs. Application discovery in the integrated example uses explicit names in configuration, not an unbounded archive scan.

## Minimum Java API surface

Every API below is a deliverable for the supported primitive/reference domain. Document exact descriptors, access flags, and unsupported overloads during implementation.

| Area | Required surface |
| --- | --- |
| Class identity | `Object.getClass()`; reference/array `ldc` Class literals; wrapper `TYPE`; `Class.getName/getModifiers/getSuperclass/getInterfaces/getComponentType/getClassLoader`, `isPrimitive/isArray/isInterface/isAnnotation/isEnum`, `isAssignableFrom(Class)`, `isInstance(Object)`, and `cast(Object)` |
| Loading | `Class.forName(String)`, `Class.forName(String,boolean,ClassLoader)`; `ClassLoader.getSystemClassLoader()` and `loadClass(String)` |
| Member discovery | Class `getDeclaredFields/getFields`, `getDeclaredField/getField`, `getDeclaredMethods/getMethods`, `getDeclaredMethod/getMethod`, `getDeclaredConstructors/getConstructors`, and `getDeclaredConstructor/getConstructor` |
| Member identity | `Member.getName/getDeclaringClass/getModifiers`; Field/Method/Constructor Java-defined `equals/hashCode`; Method `getReturnType/getParameterTypes/getExceptionTypes/isBridge/isSynthetic/isVarArgs`; Constructor `getParameterTypes/getExceptionTypes/isSynthetic/isVarArgs`; Field `getType/isSynthetic/isEnumConstant` |
| Access and execution | `AccessibleObject.setAccessible(boolean)/isAccessible()`; `Field.get(Object)/set(Object,Object)` and `getInt/setInt`; `Method.invoke(Object,Object[])`; `Constructor.newInstance(Object[])` |
| Annotation queries | AnnotatedElement `getAnnotation/isAnnotationPresent/getAnnotations/getDeclaredAnnotations/getDeclaredAnnotation/getAnnotationsByType/getDeclaredAnnotationsByType`; implement on Class, Field, Method, and Constructor; Method/Constructor `getParameterAnnotations()`; Method `getDefaultValue()` |
| Annotation values | Annotation `annotationType/equals/hashCode/toString`; normal invocation of supported annotation element methods; Retention/RetentionPolicy, Target/ElementType, Inherited, Repeatable, Documented, and minimal Enum support |
| Proxies | InvocationHandler `invoke(Object,Method,Object[])`; Proxy `newProxyInstance(ClassLoader,Class[],InvocationHandler)`, `getProxyClass(ClassLoader,Class[])`, `isProxyClass(Class)`, `getInvocationHandler(Object)`, and the generated public InvocationHandler constructor |
| Class resources | Class `getResource(String)/getResourceAsStream(String)` |
| Loader resources | ClassLoader `getResource/getResourceAsStream/getResources` and static `getSystemResource/getSystemResources`, preserving milestone 1's `getSystemResourceAsStream` |
| Resource handles | Enumeration `hasMoreElements/nextElement`; local resource URL `toExternalForm/toString/getProtocol/openStream` for URLs returned by lookup |
| Configuration | Properties `Properties()`, `load(InputStream)`, `load(Reader)`, `getProperty(String)`, `getProperty(String,String)`, `setProperty(String,String)`, plus the Hashtable/Dictionary superclass metadata and inherited Map operations needed for a consistent runtime type hierarchy |

Supporting throwable types include `ReflectiveOperationException`,
`ClassNotFoundException`, `NoSuchMethodException`, `NoSuchFieldException`,
`IllegalAccessException`, `InstantiationException`, `InvocationTargetException`
with `getTargetException/getCause`, `UndeclaredThrowableException` with
`getUndeclaredThrowable/getCause`, `AnnotationFormatError`,
`IncompleteAnnotationException`, `AnnotationTypeMismatchException`,
`TypeNotPresentException`, and `EnumConstantNotPresentException`. Use the
existing typed exception mechanism and correct Java inheritance.

## Semantic and architecture contracts

### 1. Validated metadata retained once

- Add a focused annotation parser under `bendjvm/classfile/` using the existing bounded Reader/constant-pool helpers. Never interpret annotation bytes in host code or reparse them per reflective query.
- Decode RuntimeVisibleAnnotations, RuntimeInvisibleAnnotations, RuntimeVisibleParameterAnnotations, RuntimeInvisibleParameterAnnotations, and AnnotationDefault. Also parse/preserve Java 8 visible/invisible type-annotation records with target_info and type_path, including Code-level sites; exposing AnnotatedType is explicitly deferred.
- Validate attribute placement, multiplicity, exact payload consumption, constant-pool kinds, descriptors, element tags, counts, parameter layouts, and recursive nesting. Preserve the distinction between malformed class-file structure and annotation errors reported when metadata is materialized.
- Parse every annotation element_value form: integral/boolean/char, float, long/double raw bits, String, enum, Class, nested annotation, and arrays. Validate two-slot constants without lossy conversion to a host number.
- Preserve synthetic/mandated parameter alignment where class-file annotation tables omit compiler-added parameters; do not assume table count always equals descriptor arity.
- Retain class/member access flags, declared descriptors, declared Exceptions, synthetic/bridge/varargs/enum flags, and annotation/default metadata in a compact Bend-owned table keyed by stable IDs. Keep metadata distinct from decoded execution records when that avoids copying it into each frame.
- Keep symbolic type references for metadata that can resolve lazily. Do not eagerly initialize classes or reject an otherwise runnable class solely because an unused annotation Class value names an unavailable type.
- Apply bounded counts/depth/bytes using parser limits; malformed or oversized metadata cannot allocate unbounded lists or consume unlimited parser recursion.

### 2. Mirrors, runtime loading, and stable identity

- A Class mirror denotes a type identity, not an ordinary instance of that type. Cache one mirror per primitive/void type, array type, or `(defining loader, binary name)` in the VM. Repeated `getClass`, literals, and forName calls agree by identity.
- Model bootstrap and one application loader explicitly. Bootstrap classes remain protected from classpath replacement; array mirrors inherit appropriate component loader identity. Primitive mirrors do not require a `.class` file.
- Add Class constants through verifier, linker, and runtime together. Obtain mirrors without triggering class initialization. Arrays have Object superclass and Cloneable/Serializable interfaces; primitives/void have no superclass.
- `Class.forName` resolves configured classpath names; the explicit overload
  initializes the superclass chain parent-first and runs the target's direct
  `<clinit>` once when `true`, while `false` leaves it uninitialized.
  `loadClass` resolves without initialization. The supported explicit loader
  remains one application namespace. Array-name handling follows Java
  binary-name rules; `Class.forName("int")` does not resolve `int.class`.
- When a name appears only in a configuration file, request it through milestone 1's sources at runtime. Append symbols/classes/members and link the new closure transactionally; never renumber existing IDs, replace live statics, or clear initialization state.
- Failed runtime loading must not leave partially visible classes, dangling member IDs, duplicate mirrors, or inconsistent retry state. Loading cycles and initializer recursion use explicit state transitions.
- Distinguish ClassNotFoundException at explicit lookup from linkage errors while resolving dependencies. VM capability errors remain explicit and are not disguised as absence.

### 3. Member lookup and access rules

- Declared queries include only members declared by that class, with public/private/protected/package flags intact. Public queries implement Java superclass/interface inheritance rules; constructors are never inherited; `<clinit>` is never a reflective method.
- Select methods by name and exact parameter Class sequence, not arity alone. Preserve bridge/covariant-return cases and Java lookup precedence. Returning member arrays does not promise source/classfile order.
- Field hiding resolves the correct declaring member and storage ID. Reflective handles identify actual members, not independent field copies or host closures.
- Access checks account for caller class, declaring-class accessibility, package, protected receiver constraints, and private membership under Java 8 rules. Determine caller from VM frames, skipping implementation frames only by explicit contract.
- `setAccessible(true)` changes only that reflective object's override state. Equal handles obtained separately must not share mutable accessibility flags accidentally. No SecurityManager/module implementation is implied; enforce Java's non-overridable restrictions such as Class constructor access.
- Discovery and inspection alone do not initialize the represented class. Reflective static access/invocation and construction initialize the declaring class when Java requires it, using the existing initializer state machine.

### 4. Reflective invocation and field access

- Reuse normal invocation, virtual dispatch, field storage, constructor allocation, class initialization, fuel accounting, and exception machinery. Reflection is not a second interpreter.
- Instance invocation validates receiver assignability and uses virtual overrides where Java does; static invocation ignores its receiver. Null argument arrays mean zero arguments. Varargs reflection does not auto-pack trailing arguments.
- Unbox and widen only legal Java primitive conversions within the supported category-one domain; do not narrow, convert boolean numerically, or accept wrong wrapper types. Reference arguments use VM assignability. Null to a primitive is IllegalArgumentException, not an implicit zero.
- Return values are boxed or references; void returns null. Field.get boxes primitives; Field.set writes the existing static/object binding and follows Java conversion/access/final-field restrictions. Implement permitted Java 8 accessible non-static final writes; reject prohibited static-final writes.
- Constructor.newInstance allocates through the heap and invokes exactly the selected constructor. Reject interfaces, abstract classes, primitives, arrays, and enum construction as Java requires; do not bypass `<init>`.
- Wrap only exceptions thrown by the invoked target in InvocationTargetException. Pre-invocation receiver/argument/access errors remain direct, and initialization failures follow Java's separate semantics. Preserve target throwable identity as the cause.
- Exceeding fuel or corrupting the host protocol never becomes an InvocationTargetException that application code can swallow.

### 5. Annotation materialization

- Runtime-visible annotations are exposed; CLASS-retained/invisible annotations are parsed but absent from runtime query results. SOURCE-retained annotations are not expected in the class file.
- Implement declaration defaults, nested annotations, Class values, enum constants, and defensive copies of array-valued elements. Resolve values on demand where Java does; missing required elements and unavailable types/constants report the corresponding annotation exceptions, not invented values.
- `@Inherited` affects class annotation lookup through superclasses only, not interfaces, methods, or fields. Declared queries do not inherit. `getAnnotationsByType` expands valid repeatable containers using Java's directly/indirectly present and inheritance rules; ordinary getAnnotation does not flatten containers.
- Annotation equality/hash follow the Annotation contract, including primitive/reference array contents and floating-point value semantics. Deterministic toString is useful, but formatting is not a byte-for-byte OpenJDK oracle.
- Annotation interfaces and Enum metadata must have correct flags/hierarchy. Enum values are actual Java enum singleton objects, not strings.
- Use VM-managed annotation instances implementing their annotation interface. Share ordinary synthetic-class/interface dispatch machinery with proxies where appropriate, without requiring annotations to masquerade as user InvocationHandlers.
- Metadata parsing supports long/double forms and reflection materializes them as boxed raw-word `Long`/`Double` values holding high/low U32 words. General category-two bytecode, field, call, and primitive-unboxing execution remains milestone 4; do not advertise that broader support.

### 6. Dynamic proxies

- Implement JDK interface proxies, not class-subclass proxies. Synthesize a linked proxy class directly in Bend and register it through the same append-only class/member path as runtime loading; no host Java reflection, bytecode execution, or fake fixture-specific stubs.
- Cache the proxy Class by defining loader and ordered interface list. The same ordered list reuses the class; reversing it can change the class and duplicate-method precedence.
- Validate non-null handler, actual/visible interface types, duplicate interfaces, compatible method signatures/return types, and same-package constraints for non-public interfaces. Preserve Java-defined non-public proxy package/access rules.
- The proxy is assignable to all requested interfaces. Route calls into the supplied Java InvocationHandler using the normal callback continuation; pass the proxy, a real Method, and boxed argument array. Pass null arguments for zero-argument methods as specified by InvocationHandler.
- Route Object.equals/hashCode/toString to the handler using Object-declared Method objects. Keep duplicate interface method/declaring-class selection and covariant return behavior consistent with Java.
- Unbox/check handler returns, including null for primitive-return NullPointerException and incompatible return ClassCastException. Void ignores the handler's returned value.
- Propagate RuntimeException/Error and permitted declared checked exceptions; wrap other checked exceptions in UndeclaredThrowableException. For duplicate methods, honor the checked-exception contract across the contributing interfaces.
- The existing default-method body execution exclusion remains: invoking a proxy interface method routes to its handler; special invocation of a default implementation is not added here.
- Proxy construction, handlers, nested reflection, and handler failures remain fuel/heap bounded and preserve caller PCs. isProxyClass recognizes only runtime-generated proxy classes, not arbitrary subclasses of Proxy.

### 7. Framework configuration resources

- Extend the existing source abstraction with first-match lookup and ordered all-match enumeration. Source order includes manifest dependencies and existing source deduplication; distinct origins with the same resource path remain separate enumeration results.
- Class.getResource resolves a relative name against the class package and a leading slash against the root. ClassLoader names are root-relative without stripping a leading slash. Missing single lookups return null; missing enumeration is empty.
- URL objects returned by resource lookup retain their selected directory/archive origin. `openStream` reopens that exact source rather than repeating first-match resolution and accidentally reading another duplicate resource.
- Expose ordinary local `file:`/`jar:file:...!/` forms with correct escaping for spaces, Unicode, and archive entry names. These returned URLs need only support the documented local operations; no HTTP URLConnection or general network URL API is introduced.
- Reuse archive read limits, traversal protections, stream ownership, and host request/resume. Enumeration must not extract archives or decompress every resource eagerly. A corrupt source/read failure must not silently become a fabricated empty stream.
- Properties.load(InputStream) follows Java ISO-8859-1 plus Unicode escapes; Properties.load(Reader) consumes characters. Implement comments, separators, continuation lines, escapes, duplicate-key last-write behavior, and malformed Unicode-escape errors. Do not reinterpret byte-based properties as UTF-8.
- Resource lookup plus Properties and explicit class-name configuration is the framework-configuration contract. ServiceLoader, Thread context-loader access, Spring-specific resource resolvers, and automatic package scanning are not prerequisites.

## Ordered implementation slices

### 1. Structured annotation and reflection metadata

Targets: `model.bend`, `classfile/attribute.bend`, `classfile/parser.bend`, a focused annotation parser, and loader metadata construction.

- Parse and validate annotation/default/parameter/type records and Exceptions metadata.
- Preserve declaration flags, names/descriptors, and structured metadata through catalog linking.
- Avoid copying whole constant pools into each reflected member; use immutable resolved values/symbolic references with stable ownership.

Acceptance: parser-level fixtures cover all element tags, nested arrays/annotations, defaults, visible/invisible retention, parameter/type sites, and malformed count/tag/index/depth cases. Linked metadata preserves the distinctions needed by later slices without initializing user classes.

### 2. Class mirrors and append-only runtime loading

Targets: verifier literal rules, `loader/catalog.bend`, loading session/API, `runtime/execute.bend`, shared VM state, heap mirrors, and the existing runner source protocol.

- Support Class literals, primitive/array mirrors, Object.getClass, Class identity/introspection, and ClassLoader identities.
- Add forName/loadClass requests for configuration-only names and atomic append-only linking.
- Keep initialization separate from loading; extend API exports/cache inputs and both runner/alternate Bend entrypoints.

Acceptance: literals/getClass/forName agree by identity; forName(false) does not run `<clinit>`; forName(true) initializes once; a class named only in a runtime string loads from a dependency JAR while older live objects and frames still work. Failed loads leave no partial public definition. Cover arrays, primitives, bootstrap protection, and missing dependencies.

### 3. Member discovery, handles, and access checks

Targets: `java/` reflection modules, bootstrap metadata, stable member tables, caller inspection helpers.

- Implement the member-query and identity API rows, flags, exception types, and public-versus-declared inheritance rules.
- Add per-handle accessibility override state and caller/package/protected checks.
- Preserve metadata-only behavior and avoid eager target initialization.

Acceptance: overloaded/hidden/inherited/private members, interfaces, covariant bridges, and constructors return the correct declaring IDs/types. Separate equal handles do not leak setAccessible state. Cross-package protected and private access cases match Java 8 semantics. Compare normalized member sets, not unspecified enumeration order.

### 4. Reflective field operations, method calls, and construction

Targets: intrinsic callback continuations, runtime invocation/initialization paths, heap allocation/field helpers, wrapper registrations, and reflection error types.

- Implement get/set/getInt/setInt, invoke, and newInstance using ordinary VM operations.
- Add required category-one boxing/unboxing and widening; enforce receiver/argument/access/final rules.
- Resume reflective calls and wrap only target exceptions at the correct boundary.

Acceptance: create an object, inject an inherited/private field after permitted accessibility override, invoke an overridden method, and read the same field through normal bytecode. Cover static initialization, null/wrong receiver, overload selection, wrong arity/wrapper, widening versus narrowing, abstract/enum construction, target failures, and repeated initializer failure. Fuel exhaustion remains a VM stop.

### 5. Runtime annotation APIs and enum values

Targets: annotation MiniJRE types, metadata materialization, synthetic annotation instances, enum support, and query intrinsics.

- Implement visible/declared/inherited/repeatable queries and parameter annotations.
- Support defaults and category-one/reference element values through normal annotation-interface calls.
- Add defensive array copying and annotation equality/hash; distinguish parse errors from query/materialization errors.

Acceptance: runtime-retained annotations on classes/fields/methods/constructors/parameters are observable; CLASS retention remains hidden; defaults/nested values/enums/Class values work. Verify superclass-only inheritance, repeatable containers, missing values/types, independent returned arrays, and no incidental class initialization during metadata-only discovery.

### 6. Dynamic interface proxies

Targets: synthetic class builder, append-only registry, Proxy/InvocationHandler MiniJRE definitions, runtime interface/virtual dispatch, conversion/error helpers.

- Generate proxy classes from arbitrary supported interface definitions rather than per-fixture special cases.
- Route handler callbacks, Object methods, return conversions, and exception contracts through established runtime paths.
- Expose proxy identity/introspection and generated constructor behavior.

Acceptance: a Java handler intercepts two interfaces, delegates through Method.invoke, changes a result, and returns control to the original caller. Cover ordered cache keys, duplicate/covariant methods, non-public interface validation, zero arguments, primitive boxing/null return, declared versus undeclared exceptions, Object methods, and nested proxy/reflection calls.

### 7. Ordered resource lookup and properties configuration

Targets: existing classpath source module/protocol, resource/URL/Enumeration MiniJRE types, Class/ClassLoader intrinsics, Properties implementation.

- Add package-relative resolution, origin-bound URL handles, and all-source enumeration without changing milestone 1 precedence.
- Implement Properties parsing on existing byte/character streams and preserve correct superclass metadata.
- Keep each open independent and reuse bounded resource handling/cleanup.

Acceptance: enumerate two same-named configuration resources from distinct dependencies in classpath order; opening each URL yields its own bytes. Verify class-relative/root-relative paths, missing/empty resources, escaped archive paths, independent streams, Latin-1/Unicode escapes/continuations, and byte-versus-reader Properties decoding.

### 8. Integrated reflective application and compatibility gates

Targets: `scripts/test.py`, `bendjvm/tests/fixtures/`, `README.md`, relevant `bendjvm-spec.md` sections, `ROADMAP.md`, meaningful laws/proofs.

- Extend the existing harness with reflection/annotation/proxy/resource groups and temporary Java 8 archive fixtures. Use `javap -v` when establishing emitted annotation/member metadata.
- Build a small explicit-configuration component container: enumerate dependency properties, load configured classes by name, inspect runtime annotations, select a constructor, inject fields, invoke lifecycle/service methods, and wrap an interface service in a Proxy.
- Include a target failure to prove InvocationTargetException/UndeclaredThrowableException handling and resource cleanup. The container is a compatibility fixture, not a new production framework or a Spring claim.
- Run through milestone 1's manifest/JAR launch path and preserve standalone execution, debug modes, limits, and the milestone 2 suite.
- Document exact API/primitive-domain support, limitations, failure semantics, and which metadata does not trigger initialization.

Acceptance: ordinary Java 8 sources execute the complete sequence with OpenJDK-equivalent observable results, all four roadmap rows have runtime proof, and docs do not imply full reflection/JDK/Spring compatibility.

## Dependency and parallel-work map

- Slice 1 establishes metadata; slice 2 establishes type identity and runtime linking; slice 3 builds on both; slice 4 uses their handles and milestone 2 callback machinery; slice 5 uses metadata/mirrors/invocation; slice 6 reuses the same synthetic-class and invocation paths; slice 7 can proceed after mirror/source contracts are fixed; slice 8 integrates everything.
- After agreeing metadata ownership and mirror/ID contracts, parser work and source enumeration work can run concurrently in disjoint files. Annotation fixture preparation can run alongside reflective invocation implementation.
- One integration owner controls `model.bend`, bootstrap registrations, catalog IDs, runtime continuations, runner protocol, and shared harness registration. Do not allow independent proxy/annotation implementations to invent separate class registries or call stacks.
- Parallelize independent metadata decoding only where deterministic declaration order and error behavior are retained. Class publication, initialization, field mutation, user callbacks, and proxy interception are order-dependent and remain sequenced.

## Verification strategy

Before Bend implementation, run `bend guide`; inspect references for every exported-symbol change using an available language server. Re-read affected caller/API definitions because milestones 1–2 may have changed their shape since this plan was written.

Use `javac --release 8` and `javap -v -c -s` to establish real metadata and bytecode prerequisites, then run the actual Bend-generated artifacts. Validate parsing independently before relying on execution. Generate malformed class-file mutations in the existing Python harness, not through source-text assertions.

Differential checks compare observable values, mirror identity relationships, declaring types, initialization order, exceptions/causes, resource bytes, and handler interactions. Normalize unordered member arrays. Do not compare identity-hash values, generated proxy class names, unspecified method order, exact annotation toString formatting, or full exception diagnostic prose.

Keep regressions for the concrete metadata-loss/class-literal gaps and high-risk boundaries: failed incremental loading, access override isolation, target exception wrapping, defensive annotation arrays, proxy duplicate-method rules, and origin-bound resource reopening. Do not pad the suite with reflection-record field copies or host mock echoes.

Final commands:

```sh
python3 scripts/run.py --prepare
python3 scripts/test.py --fast
python3 scripts/test.py --full
bend PROOF.bend
```

Extend `--fast` with representative literal/discovery/invocation/annotation/proxy checks; `--full` covers all supported metadata/API groups and malformed boundaries. Run the packaged component-container fixture through the actual CLI in addition to focused tests. Exercise heap/fuel limits during callbacks, annotation materialization, and runtime class loading.

Candidate `LAWS.bend`/`PROOF.bend` invariants: appending types preserves existing IDs; mirror identity is canonical; field reflection accesses the same storage as bytecode; reflection/proxy continuations preserve caller stacks; failed publication leaves the visible registry unchanged. Prove bounded pure invariants, not host filesystem behavior. Run `bend PROOF.bend` before committing.

## Completion checklist

- The four roadmap rows have Java-visible evidence in the parser/runtime suites,
  including metadata retention, reflection, proxy calls, resource lookup, and
  Properties decoding.
- Structured annotation metadata survives parsing/linking without host-side
  interpretation or repeated reparsing.
- Class mirrors/literals, member discovery, reflective invocation/construction,
  and field access work for the documented supported domain.
- Runtime-visible annotation retention, defaults, parameter queries, Class and
  reference values, repeatable containers, recursive `@Inherited` lookup,
  structural equality, enum identity, defensive arrays, and boxed raw-word
  long/double reflection values are covered; general category-two execution
  remains excluded.
- Supported interface proxies invoke real Java handlers through the normal VM,
  including Object methods, generated-class identity, interface checks,
  category-one argument boxing, method-conflict/return validation,
  declared-exception handling, and undeclared checked-throwable wrapping.
  Default-method special invocation and multiple custom loader namespaces
  remain excluded.
- Framework configuration resources support class-relative `./` and `..`
  normalization, ordered enumeration, origin-bound reopening, and Properties
  decoding.
- Existing milestone behavior and Bend ownership are preserved; category-two
  execution, parameter-name reflection, complete Java access-edge, and
  default-method limitations remain explicit in documentation.
- Documentation and proof gates are updated after behavior verification.

Verification used isolated Bend 2.0.36. `python3 scripts/run.py --prepare`
succeeded. `python3 scripts/test.py --fast --bend scripts/run.py` passed 54
tests; `python3 scripts/test.py --full --bend scripts/run.py` passed 105,
including the packaged component-container CLI fixture; `bend PROOF.bend`
reported `ALL PROOFS CHECK`. Stress probes confirmed `OutOfFuel` in proxy and
configuration-only loading paths, and `OutOfMemoryError` during annotation
materialization at a 16-entry heap limit.

Exclusions the original slice left (closed since by plan 04 and slices C1-C11): general category-two bytecode/field/call execution,
complete access-edge compatibility, custom loader subclasses and multiple
application namespaces, default-method proxy dispatch, parent/complex
static-initialization semantics, parameter-name reflection, complete URL
escaping/annotation formatting, and full OpenJDK reflection compatibility.

## Completion of the remaining exclusions

Decision (2026-11-05): plan 03 ends with no exclusions of its own, because the target is an unmodified Spring Boot application.
Each former exclusion below becomes a slice with a JDK-oracle fixture; a slice is done only when its fixture matches `java -Xverify:all` byte for byte and is part of `scripts/test.py`.
Three former exclusions belong to other plans and move there rather than being dropped.
Threads and the context class loader are plan 05.
Spring Boot nested-JAR layouts are plan 06.
`MethodHandles` and `invokedynamic` were completed by plan 04.

### C1. Class initialization and field resolution (done)

- Field references resolve per JVMS 5.4.3.2: declared fields, then superinterfaces depth-first, then the superclass chain (`heap.resolve_field`).
- Every trigger follows JVMS 5.5: `new`, `getstatic`, `putstatic`, `invokestatic`, reflective static access and invocation, `Constructor.newInstance`, and `Class.forName(..., true, ...)`.
- A class initializes after its superclass and after superinterfaces that declare default methods; an interface initializes alone.
- Bytecode triggers re-execute after each `<clinit>`; intrinsics re-run through a `NeedIntrinsicRetry` callback, and `Class.forName` through `NeedClassMirror`.
- A non-`Error` exception leaving `<clinit>` becomes `ExceptionInInitializerError`; later use throws `NoClassDefFoundError: Could not initialize class X`.
- Fixture: `InitSemantics`.

### C2. Parameter metadata (done)

- `MethodParameters` is parsed into method metadata; `Executable` is the JDK superclass of `Method` and `Constructor` and declares `getParameters`, `getParameterCount` and the shared abstract members.
- `Parameter` implements `getName` (synthesized `argN` without a recorded name), `isNamePresent`, `getModifiers`, `isImplicit`, `isSynthetic`, `isVarArgs`, `getType`, `getParameterizedType`, `getDeclaringExecutable`, the annotation queries, `equals`, `hashCode` and `toString`.
- Malformed attributes raise `MalformedParametersException` as the JDK does.
- Method resolution now continues into maximally specific superinterface methods (JVMS 5.4.3.3), which calls through `Executable` and inherited interface methods need.
- Generic arrays and wildcards are complete in the generic type engine, and `Class.getTypeName` prints arrays as `T[]`.
- `java.lang.Comparable` exists; `String` and the eight wrappers implement it with JDK `compareTo` semantics, plus the static `compare` methods.
- Fixtures: `ParameterReflection` (compiled with and without `-parameters`) and `ComparableValues`.

### C3. Generic declarations and nested classes (done)

- `TypeVariable` records its generic declaration and computes bounds lazily, so recursive bounds such as `T extends Comparable<T>` work; equality follows the declaration and name.
- Type variables resolve through the JDK scope chain: method or constructor, declaring class, then enclosing method or class.
- `Class/Method/Constructor.getTypeParameters`, `Class.getGenericInterfaces`, and `toGenericString`.
- `ParameterizedType`, `TypeVariable`, `WildcardType` and `GenericArrayType` are interfaces implemented by the JDK's `sun.reflect.generics.reflectiveObjects` classes, and `GenericDeclaration` exists.
- Parse `InnerClasses` and `EnclosingMethod`; implement `Class.getSimpleName`, `getCanonicalName`, `getEnclosingClass`, `getDeclaringClass`, `getEnclosingMethod/Constructor`, `isMemberClass`, `isLocalClass`, `isAnonymousClass`, and `getDeclaredClasses/getClasses`.
- Fixtures: `GenericDeclarations`, `NestedClasses`, `ReflectionStrings`, and `ArraySemantics`.
- Also fixed on the way: array classes are created on first use for literals, `anewarray`, type tests and mirrors, and reference arrays record their component class; `multianewarray` is implemented (decoder, verifier and runtime); `Modifier`, `Method/Constructor/Field.toString` and `toGenericString` print in the JDK format; `PrintStream.print` writes without a newline; classes declaring unlinked `native` methods load and throw `UnsatisfiedLinkError` when called.
- The `AnnotatedType` family is the JDK's: `AnnotatedType`, `AnnotatedParameterizedType`, `AnnotatedArrayType`, `AnnotatedTypeVariable` and `AnnotatedWildcardType` are interfaces implemented by the `sun.reflect.annotation.AnnotatedTypeFactory$*Impl` classes, chosen by the annotated `Type`.
- Annotated types carry their site, index and full type path, so nested type arguments, array components and wildcard bounds find their type-use annotations; an implicit `Object` upper bound (a wildcard with lower bounds) has none, as in the JDK.
- `TypeVariable` implements `AnnotatedElement` (its type-parameter annotations) and `getAnnotatedBounds` (bound annotations, skipping the class-bound slot when the first bound is an interface).
- Fixture: `AnnotatedTypes`.

### Gaps found outside plan 03

- MiniJRE breadth: `String` and `StringBuilder` expose only a few methods (`trim`, `indexOf`, `split`, `replace`, `setLength` and many more are missing); this is runtime-expansion work that Spring needs.
- `volatile` fields, `synchronized` methods and `monitorenter`/`monitorexit` are rejected at load time; they belong to plan 05, but even a single-threaded Spring application needs them to load.

### C4. Java 8 access rules (done)

- Reflection follows `Reflection.verifyMemberAccess`: the member's class must be public or in the caller's package, privates are reachable only from their own class (Java 8 class files have no nestmates), and a protected instance member or constructor reached from another package needs a target of the caller's class.
- `IllegalAccessException` messages match the JDK ("class A cannot access a member of class B with modifiers \"protected\"", "with package access"), as do the final-field and wrong-type messages of `Field.set*` ("Can not set final int field ...").
- `MethodHandles.Lookup` checks run in the JDK's order: the symbolic class, then the lookup class's own resolution ("no such method"), then the lookup modes ("member is private", "expected a static field", "unexpected set of a final field").
- A protected member found from a subclass in another package narrows the handle's receiver to the lookup class, so other receivers fail with the JDK's `ClassCastException`.
- `Lookup.in` follows Java 8's mode rules, and handle invocation no longer re-checks access (it was checked at lookup).
- Bytecode linkage keeps the JVMS 5.4.4 rule, without the reflection-only class check.
- Also fixed on the way: `Class.toString`, `Class.newInstance`, `MethodType.toString`, and common `String` methods (`indexOf`, `lastIndexOf`, `startsWith`, `endsWith`, `trim`, `replace`, `equalsIgnoreCase`, case mapping, `toCharArray`, `valueOf(char[])`, `new String(...)`).
- Fixture: `AccessRules` (with `AccessRulesBase` and `AccessRulesSub` in two packages).

### C5. Default-method special invocation (done)

- The private `Lookup(Class, int)` and `Lookup(Class)` constructors exist and work through reflection, as Spring 5 uses them on Java 8.
- `unreflect`, `unreflectSpecial`, `unreflectConstructor`, `unreflectGetter` and `unreflectSetter` follow Java 8, including the trusted lookup for accessible members.
- `invokeWithArguments` spreads an array or list into a generic invocation, including varargs collectors.
- `invokespecial` handles run the selected body even on a proxy receiver, so an `InvocationHandler` can run an interface's default method.
- Also fixed: virtual handles select default methods; field-handle results and setters return through the `asType` boundary (a generic `invoke` of a setter returned no value before); `MethodType.methodType(Class, Class, Class...)` and `methodType(Class, MethodType)`.
- Fixture: `DefaultMethodProxy` (it falls back to `privateLookupIn` only where the JDK oracle lacks or closes the Java 8 constructors).

### C6. Class loaders, `defineClass` and namespaces (done)

- `ClassLoader` is subclassable: both constructors, `getParent`, `loadClass(String)` (calling the two-argument form virtually), `loadClass(String, boolean)` with the JDK algorithm (`findLoadedClass`, the parent, then `findClass`), `findClass`, `findLoadedClass`, `resolveClass`, `findSystemClass`, `getClassLoadingLock`, `registerAsParallelCapable`, `getResource`/`getResourceAsStream` delegation and `findResource`.
- Each loader owns a namespace; a `ClassNotFoundException` from the parent resumes `loadClass` through a catching boundary (`LoaderCatch`).
- `defineClass` (all three forms) checks the prohibited `java.*` packages, the expected name ("wrong name") and duplicates, resolves supertypes through the defining loader (a missing one is `NoClassDefFoundError`), and resolves every other name it mentions through that loader too.
- JVMS 5.4 lets a VM load referenced classes eagerly; a name the loader cannot load stays unresolvable and fails only at use, so laziness is not observable except through loader side effects before first use.
- A binary name defined by a second loader gets a distinct internal name (a U+E000 suffix that no Java source can produce), and its class file is renamed in its namespace; names print without the suffix.
- Verification of a user-defined class waits for linking (first initialization), where a failure is a `VerifyError` on every attempt.
- `Class.getClassLoader` reports the defining loader (arrays report their element's), runtime packages compare loaders, the system loader never sees user-defined classes, and `Class.forName` uses the caller's or the given loader.
- Host failures now reach boundaries at the suspended intrinsic first (a `ClassNotFoundException` from the system loader's class path lookup is catchable by a delegating loader).
- Also added on the way: array `clone()`, `java.lang.SecurityException`, and the binary name in class path `ClassNotFoundException` messages.
- A renamed class's `Signature` attributes and annotation type descriptors point at renamed Utf8 entries, and the classes they name resolve through the defining loader like any other name the class mentions, so a second definition's annotations and generic types stay in its namespace.
- Fixture: the `loaders/user-class-loaders` check runs `ClassLoaders` with `isolated.*` classes visible only as resources, including deserialization inside isolated code and a second definition's annotations and generic types.

### C7. Subclass proxies (done)

- Class bytes written at run time (as ASM writes them) are defined through a user loader and behave as CGLIB/ByteBuddy subclasses: overrides that call `super` (`invokespecial` on the parent), inherited protected fields, implemented interfaces, reflection over the generated members, and calls through the parent's `Method`.
- A generated class that fails verification is defined, and fails with `VerifyError` at first use.
- Also added: `ArrayList.toString` (elements through their own `toString`).
- Fixture: `SubclassProxies` (its class writer is in the fixture).

### C8. Classpath and package scanning (done)

- Class files and directories are resources: `getResource(s)` finds `pkg/` and `pkg` in directories and in jars with directory entries.
- `URL` keeps its external form; `URL(String)`, `URL(URL, String)` (relative resolution, also inside jars), `openConnection`, `toURI`, `getFile`, `getHost`, `getRef` and `equals`.
- `java.net.URI` parses and validates RFC 2396 references and decodes escapes as UTF-8.
- `File` normalizes paths and implements `listFiles`, `list`, `getName`, `getParent(File)`, `getAbsolutePath(File)`, `File(URI)`, `File(parent, child)` and the separator fields.
- `URLConnection`, `JarURLConnection`, `ZipFile`, `JarFile`, `ZipEntry` and `JarEntry` support the scanning sequence: entries in central-directory order, `getJarEntry`, and entry streams.
- Fixture: the `resources/package-scanning` check runs `PackageScanning` over a directory and a jar, as Spring 5's `PathMatchingResourcePatternResolver` does.

### C9. Formatting (done)

- Annotation `toString` matches the oracle JDK's `AnnotationInvocationHandler`: canonical names, quoted strings and chars, `L`/`f` suffixes, `(byte)0x..`, `.class` literals, `{...}` arrays, and the lone `value` shorthand.
- Members follow the JDK order: defaults in `AnnotationType`'s `HashMap` bucket order, then explicit members.
- Ties within one bucket follow HotSpot's internal method order, which no other VM can reproduce.
  This is a deliberate difference: declaration order is used, and the fixture avoids ties.
- The format is the oracle's (modern JDK), consistent with the rest of the suite; Java 8 printed strings unquoted.
- Resource URLs escape as `ParseUtil.encodePath` does: each UTF-16 unit, lowercase hex, and `;`, `=`, `?`, `#` and brackets among the escaped characters; class path roots are canonical paths as in the JDK.
- `Enum.toString`, `compareTo` and `getDeclaringClass` exist, and Object methods on proxies and annotations reached from intrinsic callbacks now dispatch like bytecode calls.
- Fixtures: `AnnotationFormatting` and the `resources/url-escaping` check (`ResourceUrls`).

### C10. Serialization (done)

- `ObjectOutputStream` and `ObjectInputStream` speak the JDK stream protocol, written in Bend (`bendjvm/java/serial.bend`) with Java callbacks resuming a task machine.
- Streams carry objects, strings, `Class` objects, enums, primitive and reference arrays, proxies (`TC_PROXYCLASSDESC`), null and back references; handles are assigned in the JDK's order, so repeated objects and cycles come back with their identity.
- Class descriptors list fields as `ObjectStreamField` sorts them (primitives first, then by name) and carry the declared `serialVersionUID`, or the one `computeDefaultSUID` derives with SHA-1 from the class's name, modifiers, interfaces, members and static initializer.
- MiniJRE classes the JDK serializes (`String`, `Enum`, `Number` and the boxes, `Proxy`, `SerializedLambda`) use the JDK's UIDs and field layouts.
- Private `writeObject`/`readObject` run in block-data mode with `defaultWriteObject`/`defaultReadObject`, `writeUTF`/`readUTF` and the other `DataOutput`/`DataInput` methods; unread custom data is skipped up to `TC_ENDBLOCKDATA`.
- `writeReplace` repeats while the replacement's class changes and is remembered for later writes; `readResolve` replaces the object and its handle.
- Serializable lambdas write a `SerializedLambda` and read back through the capturing class's `$deserializeLambda$`.
- Reading allocates without constructors except the no-argument constructor of the first non-serializable superclass, which must be accessible (`no valid constructor` otherwise), and rejects a `serialVersionUID` mismatch with the JDK's `InvalidClassException` message.
- `Externalizable` classes write `SC_EXTERNALIZABLE | SC_BLOCK_DATA` descriptors and their `writeExternal` data in block-data mode; reading runs the public no-argument constructor, then `readExternal`.
- `writeUnshared` and `readUnshared` keep the object out of the handle table; a back reference to it, or `readUnshared` of a back reference, is the JDK's `InvalidObjectException`.
- `reset` writes `TC_RESET` and forgets handles and replacements (`IOException: stream active` inside a write); the reader accepts `TC_RESET` between objects and between data blocks, with the JDK's recursion-depth check.
- Fields are matched by name as `ObjectStreamClass.matchFields` does, and a primitive type change is an `InvalidClassException`.
- Class data follows `getClassDataLayout`: stream classes the object lacks are read and dropped, and local classes missing from the stream get `readObjectNoData`.
- `ObjectInputStream` reads any `InputStream`: `ByteArrayInputStream` and resource streams in place, others through their own `read()` and `read(byte[], int, int)`, asking for exactly the bytes it needs.
- Each reader step is a pure step over the VM state; a step that runs short of bytes, or meets a class its loader has not loaded, fails with a request, and replays once the Java call returns.
- Stream classes resolve through `latestUserDefinedLoader()`: a class the loader's namespace already knows is used directly, and any other is loaded with `Class.forName(name, false, loader)`.
- Also added: `writeBytes`, `writeChars`, `read(byte[], int, int)`, `readFully(byte[], int, int)`, `skipBytes`, `available`, and `close` closing the source stream.
- Also fixed on the way: a serializable lambda's generated `writeReplace` had duplicate symbol ids, so name lookups could not find it; `java.lang.reflect.Proxy` implements `Serializable`; the core `java.util.function` interfaces exist (abstract methods only).
- Also fixed: `InputStream.read()` returned sign-extended bytes, `read(byte[])` and `read(byte[], int, int)` read one byte without filling the array, `ObjectInputStream` never advanced a `ByteArrayInputStream`'s position, and `Integer.parseInt(String, int)` was missing.
- Also fixed in the runtime: a native that an intrinsic calls back and that waits on the host (a file read, a class load) now resumes the intrinsic's continuation instead of returning into the frame below, and the host loop applies an effect that a resumed callback chain requests right away.
- Subclass hooks run as Java callbacks: `writeStreamHeader`/`readStreamHeader`, `writeClassDescriptor`/`readClassDescriptor`, `annotateClass`/`annotateProxyClass` (written in block-data mode, skipped JDK-style when not read), `resolveClass`/`resolveProxyClass`, `replaceObject`/`resolveObject` under `enableReplaceObject`/`enableResolveObject`, and `writeObjectOverride`/`readObjectOverride` through the protected constructors.
- Descriptor reading and writing are steps of the task machines, so each hook sees the stream exactly where the JDK calls it.
- `ObjectStreamClass` (`lookup`, `lookupAny`, `getName`, `getSerialVersionUID`, `forClass`, `getFields`, `getField`, `toString`) and `ObjectStreamField` exist; a descriptor read from a stream is an `ObjectStreamClass`, and a class's own is cached on its mirror.
- `serialPersistentFields` declares the serializable fields (bound to same-named fields of the same type), and `putFields`/`writeFields` and `readFields` (`GetField.get`, `defaulted`, `getObjectStreamClass`) work with the JDK's `IllegalArgumentException` messages.
- `registerValidation` callbacks run after the top-level `readObject`, highest priority first.
- A top-level write that meets an `IOException`, whether the serializer's own or one thrown by a `writeObject`/`writeExternal`/hook callback (caught by a `SerialCatch` call boundary), writes `TC_EXCEPTION` and the exception, then rethrows; the reader turns it into `WriteAbortedException`. `Throwable` is `Serializable`, with its message and cause as fields.
- A reference field whose local type changed rejects a value of another type with the JDK's `ClassCastException` message.
- `useProtocolVersion(1)` writes `Externalizable` data without block-data mode, and `drain` is available to subclasses.
- Known differences, all on error paths: a `ClassNotFoundException` from resolving a stream class is thrown at once, where the JDK records it, reads on, and throws it when `readObject` returns; duplicate names in `serialPersistentFields` are not rejected; and the writer reads `serialPersistentFields` without initializing a class it only describes (`writeObject(SomeClass.class)`).
- Fixtures: `SerializationStreams` (its hex dumps match the JDK's bytes), `SerializationEvolution` and `SerializationHooks`.

### C11. Security and privileged actions (done)

- `System.getSecurityManager()` returns `null`.
- `AccessController.doPrivileged` runs `PrivilegedAction` and `PrivilegedExceptionAction` (with or without a context) on the caller's stack.
- A checked exception from a `PrivilegedExceptionAction` becomes a `PrivilegedActionException` cause, with a null message; runtime exceptions and errors pass through.
- Fixture: `PrivilegedActions`.
