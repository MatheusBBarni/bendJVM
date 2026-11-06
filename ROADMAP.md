# BendJVM roadmap

## Current position

Milestone 3's bounded reflection slice is implemented and verified. The parser
validates structured annotation attributes, and the linker retains their
symbolic metadata. The runtime has Class literals and canonical mirrors for
classes, arrays, primitive types, and void; wrapper `TYPE` fields;
`Object.getClass`; binary-name `Class.forName` overloads;
`ClassLoader.getSystemClassLoader` and `ClassLoader.loadClass`. Declared
fields, methods, and constructors can be discovered through bounded
reflection wrappers, including exact name/parameter lookup, per-handle
accessibility, and declaring-class mirrors. Runtime-visible annotation objects
support supported scalar/reference values, defaults, parameter/type queries,
defensive array results, recursive `@Inherited`, repeatable containers,
structural equality, and enum identity. Interface dynamic proxies route calls
through `InvocationHandler` callbacks, preserve generated-class and interface
assignability checks, box category-one arguments, and wrap undeclared checked
throwables. The resource path is ordered and first-match for class-relative
lookup, including `./` and `..` normalization, origin-bound URL reopening,
ordered `Enumeration<URL>` results, local URL protocol/string accessors, and
ISO-8859-1/Unicode/continuation-aware `Properties.load(InputStream)` plus
bounded UTF-8 `Properties.load(Reader)` parsing. Host JDK classes are not
loaded.

Milestone 4 is implemented for Java 8 class files.
Long and double values are two-word category-two values with Bend-side binary64 arithmetic and JDK-compatible `Double.toString` output.
`tableswitch`, `lookupswitch` and every `wide` form decode, verify and execute.
`invokedynamic` runs user bootstrap methods and Java 8 lambdas and method references through one MethodHandle path.
Class loading is gated by a StackMapTable type checker written in Bend.

Milestone 5 is implemented.
Java threads run on a Bend scheduler with round-robin preemption, monitors and `wait`/`notify`, volatile fields and cross-thread class initialization.
Sockets, `java.nio` channels and selectors, and client/server TLS park only the calling thread while the host performs the I/O.
Native libraries load through BendJVM's own versioned plugin ABI into a supervised helper process, only from paths the launcher allows.
The thread, monitor, NIO, TCP and TLS fixtures produce the same output as OpenJDK, and a packaged HTTPS example serves concurrent clients through the CLI.

Current source verification: Bend 2.0.39 artifact preparation succeeds.
The fast suite passes 105 tests and the full suite passes 162.
`bend PROOF.bend` reports `ALL PROOFS CHECK`.
The full suite also runs the packaged reflective component container and the broader-bytecode application through the CLI.

Milestone 3 has no open exclusions left.
Its completion slices (initialization, parameters, generics and nested classes, Java 8 access rules, default-method handles, user class loaders, subclass proxies, package scanning, formatting, serialization, and privileged actions) each have a fixture that matches the JDK's output byte for byte.
See [plan 03](.plans/03-reflection-and-metadata.md) for the details and the remaining limitations of each slice.

## Spring Boot target

An actual Spring Boot application is not supported yet.
Reflection, annotations, proxies, class loaders and serialization now cover what Spring uses, but Spring Boot still requires:

- Class files newer than Java 8 and their linkage forms (`StringConcatFactory`, constant-dynamic).
- Threads, synchronization and the context class loader (plan 05).
- Native libraries, NIO, and TLS.
- A much larger Java standard library (for example the rest of `String`, `java.util.function` default methods, and `java.util.concurrent`).
- Nested-JAR launcher support (plan 06).

Without these features, a Spring Boot application would fail when it loads
missing runtime classes or reaches unsupported bytecode.

## Roadmap

### 1. JAR and classpath loading — complete

- Read classes from JAR and ZIP files with bounded stored/deflated reads.
- Resolve application dependencies from ordered directories and archives.
- Load resources from dependency archives through the MiniJRE stream slice.
- Support manifest `Main-Class` startup and local transitive `Class-Path`.

### 2. Java runtime expansion — complete

- Object, Objects, String, StringBuilder, Integer, Math, and `System.arraycopy`.
- ArrayList/HashMap plus collection interfaces, with `invokeinterface`.
- Memory and file streams, UTF-8 readers/writers, `BufferedReader.readLine`, and TWR.
- Blocking TCP client/server sockets with host resume, capability flags, and handle teardown.
- Typed throwables, catch-type unwinding, and a packaged integrated-app check.

### 3. Reflection and metadata - complete

- Parse and retain structured visible/invisible annotation, parameter, type,
  default, and `Exceptions` metadata through linking.
- Support Class literals and canonical loaded-class/array/primitive/void
  mirrors, wrapper `TYPE` fields, `getClass`, `isInstance`, binary-name
  `forName` overloads, and `ClassLoader.loadClass(String)`, including
  configuration-only classpath entries.
- Discover declared fields, methods, and constructors, including exact
  name/parameter lookup, declaring-class mirrors, per-handle accessibility,
  flags, exception types, and bounded type metadata.
- Materialize supported runtime-visible annotations, defaults, nested/reference
  values, parameter annotations, defensive arrays, recursive `@Inherited`,
  repeatable containers, structural equality, and enum identity.
- Execute bounded `Field.get/set`, `Method.invoke`, and
  `Constructor.newInstance` operations with category-one wrapper conversion.
- Route supported interface proxies through Java `InvocationHandler` objects,
  including Object methods, generated proxy mirrors, interface checks,
  category-one argument boxing, and undeclared checked-throwable wrapping.
- Keep ordered first-match resource streams, class-relative `./` and `..`
  normalization, origin-bound URL handles, ordered resource enumeration,
  local URL protocol/string forms, ISO-8859-1/Unicode/continuation-aware
  `Properties.load(InputStream)`, and bounded UTF-8 `Properties.load(Reader)`.
- Completion slices C1-C11: JVMS 5.5 initialization, parameter metadata, generic declarations and nested classes, Java 8 access rules, default-method special invocation, user class loaders with `defineClass` and namespaces, subclass proxies, classpath and package scanning, JDK formatting, object serialization, and privileged actions.

### 4. Broader JVM bytecode support - complete

- General `invokedynamic` with user bootstrap methods, cached and reentrant linkage, `BootstrapMethodError` wrapping, and Java 8 LambdaMetafactory lambdas and method references.
- MethodType, MethodHandles.Lookup `find*` methods, `bindTo`, `asType`, `insertArguments`, varargs collectors, and constant, mutable and volatile call sites.
- Complete `long` and `double` execution: every opcode and conversion, fields, arrays, calls, wrappers, reflection and annotations.
- `tableswitch` and `lookupswitch`, plus every Java 8 `wide` form.
- A JVMS 4.10.1 StackMapTable type checker on every class-loading path, replacing the runner's Python stack check.
- Remaining exclusions: `StringConcatFactory`, constant-dynamic, newer class-file versions, and further MethodHandle combinators.

### 5. Concurrency and native integration - complete

- Java threads multiplexed on the Bend interpreter: lifecycle, interruption, `join`, `sleep`, daemon shutdown, uncaught-exception handlers, and one global fuel budget.
- Reentrant monitors for `synchronized` methods and blocks, `wait`/`notify`/`notifyAll` with full recursion-depth restore, and a deadlock diagnostic.
- Volatile fields under a sequentially consistent memory model, with atomic `long`/`double` and race-free class initialization.
- A versioned, allowlisted native-plugin ABI with copied buffers, opaque handles, mapped errors, deadlines and crash containment.
- Scheduler-aware TCP, `java.nio` buffers, channels and selectors, and TLS 1.2/1.3 sockets with certificate, hostname and client-certificate checks.
- See [plan 05](.plans/05-concurrency-and-native-integration.md) for the design, the remaining limits and the checks that demonstrate each row.

### 6. Spring Boot launcher support

- Support the Spring Boot launcher layout.
- Resolve nested dependency JARs.
- Load application resources and configuration files.
- Run a small Spring Boot compatibility example.

## Near-term target

A small Spring-like Java application is a reasonable intermediate target.

A real Spring Boot application should be treated as a later compatibility milestone after JAR loading, reflection, runtime expansion, and broader bytecode support are implemented.
