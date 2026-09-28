# Plan: Reflection and metadata

Status: substantially implemented; parser/linker metadata, bounded reflection,
runtime annotation materialization, interface proxies, ordered resources, and
bounded memory-Reader Properties are implemented.
Source: `ROADMAP.md`, milestone 3.
Dependencies: [JAR and classpath loading](01-jar-and-classpath-loading.md) and [Java runtime expansion](02-java-runtime-expansion.md).

## Goal

Run a small Java 8 application that discovers configured classes, reads runtime annotations, constructs and wires objects reflectively, intercepts interface calls through a dynamic proxy, and reads configuration from dependency archives.

The deliverable is a bounded reflection-capable MiniJRE, not Spring Boot compatibility or full OpenJDK reflection.

| Roadmap requirement | Deliverable |
| --- | --- |
| Parse runtime annotations | Validated structured annotation metadata retained through linking and exposed through Java annotation APIs |
| Reflective class, method, field, and constructor access | Class mirrors, member discovery, access checks, field reads/writes, method invocation, and construction |
| Support dynamic proxies | Java Proxy/InvocationHandler contracts backed by Bend-owned synthetic classes and normal VM invocation |
| Resource lookup for framework configuration | Class-relative and class-loader resource lookup, ordered enumeration, local resource URLs, and properties configuration |

## Current implementation and blockers

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
- custom loader object acceptance for the existing application catalog, default-interface fallback when class dispatch has no concrete override, `Method.isDefault()` fallback reflection, `InvocationTargetException` wrapping at reflective unwind boundaries, `Throwable(Throwable)` cause-to-message initialization, and bounded `AnnotatedType` type/owner/actual-argument exposure for erased descriptors.

The following remain incomplete: true category-two JVM stack/local layout and the remaining long/double opcodes/conversions, loader identity and multiple independent namespaces, special default-method proxy invocation, generic `Signature`/`MethodParameters`/`TypeVariable` reflection, full `AnnotatedType` target/type-path exposure, and byte-for-byte OpenJDK formatting/exception-message compatibility. `AnnotatedType.getType()`, `Type.getTypeName()`, `Method.getGenericReturnType()`, `Method.getGenericParameterTypes()`, and `Method.getGenericExceptionTypes()` expose erased descriptor types only.

## Scope and boundaries

### Dependencies to reuse

- Milestone 1 supplies deterministic classpath/archive lookup, a Bend-driven loading session, source identity, manifest dependency order, and resource byte requests. Extend it for runtime requests and resource enumeration; do not add another scanner or Python class parser.
- Milestone 2 supplies interface dispatch, typed throwable objects, heap-mutating intrinsic results, Java callback continuations, boxed integers, collections, stream APIs, and cleanup. Reflection and proxies must use these paths instead of hidden host execution.
- Add category-one primitive wrapper support missing from milestone 2: Boolean, Byte, Short, Character, and Float, including `valueOf`, primitive-value accessors, and primitive `TYPE` mirrors. Add `Void.TYPE` and metadata-only primitive mirrors for all Java primitive types.
- Preserve raw long/double annotation constants and materialize them through boxed `Long`/`Double` reflection values using high/low U32 words. The current runtime additionally supports a single logical VM slot for bounded long arithmetic, `dadd`, wide field/call/return transport, and wrapper accessors; true category-two stack/local semantics and the remaining opcodes remain excluded.
- Add only the enum support required to compile and consume Java 8 annotation enum values: Enum construction/name/ordinal/identity semantics, constant lookup, and array cloning used by javac-generated `values()`. Enum switch execution remains milestone 4.

### Explicit exclusions

Custom loader instances may resolve names from the existing application catalog, but arbitrary `defineClass`, loader identity, and multiple application-loader namespaces remain unsupported; modules/security managers, MethodHandles, `invokedynamic`, full generic Type/Signature reflection, parameter-name reflection, serialization of reflection/proxy objects, Java threading/context-class-loader APIs, subclass-based proxies, default-method special invocation, Spring Boot archive layouts, and general classpath/package scanning are also excluded.

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
- Existing milestone behavior and Bend ownership are preserved; category-two,
  generic/signature, complete Java access-edge, and default-method limitations
  remain explicit in documentation.
- Documentation and proof gates are updated after behavior verification.


Planning verification: the bounded milestone is exercised by repository checks.
Parser/linker metadata, reflective member access, runtime annotation objects
including repeatable containers, interface proxies, resources, and both
bounded Properties paths have permanent fixtures or suite coverage. Remaining
limits are recorded in `README.md` and this plan: general category-two
bytecode/field/call execution, complete access-edge compatibility, custom
loader subclasses and multiple application namespaces, default-method proxy
dispatch, generic/signature reflection, and full OpenJDK reflection
compatibility.
