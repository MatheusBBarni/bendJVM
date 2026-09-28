# BendJVM roadmap

## Current position

Milestone 3 is substantially implemented: the class-file parser validates
structured annotation attributes and the linker retains their symbolic
metadata. The runtime has Class literals and canonical mirrors for loaded
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

This is not full OpenJDK reflection. Complete Java access-edge compatibility,
proxy method-conflict/default-method and loader-namespace rules,
parent/complex static-initialization semantics, parameter-name reflection,
exact annotation formatting, and full URL escaping remain bounded or
unsupported. Method, field, and class `Signature` attributes and method-return
and field type-argument annotations are implemented.

## Spring Boot target

An actual Spring Boot application is not supported yet. The bounded milestone-3
slice does not supply the framework-scale reflection and runtime annotation
materialization that Spring requires. Spring Boot still requires:

- Full reflective access, invocation, and annotation materialization.
- Dynamic proxies.
- `invokedynamic`.
- Threads and synchronization.
- Native libraries, NIO, and TLS.
- A much larger Java standard library and nested-JAR launcher support.

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

### 3. Reflection and metadata — substantially implemented

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
- Remaining work: true category-two stack layout, proxy
  method-conflict/default-method and loader-namespace rules, parent/complex
  static-initialization semantics, parameter-name reflection, and
  complete URL escaping.

### 4. Broader JVM bytecode support

- Implement `invokedynamic`.
- Add complete `long` and `double` support.
- Add switch instructions.
- Improve verifier coverage and compatibility.

### 5. Concurrency and native integration

- Add Java threads.
- Implement monitors and `synchronized` methods and blocks.
- Add volatile memory semantics.
- Define a controlled interface for native libraries.
- Add the networking and TLS primitives needed by web applications.

### 6. Spring Boot launcher support

- Support the Spring Boot launcher layout.
- Resolve nested dependency JARs.
- Load application resources and configuration files.
- Run a small Spring Boot compatibility example.

## Near-term target

A small Spring-like Java application is a reasonable intermediate target.

A real Spring Boot application should be treated as a later compatibility milestone after JAR loading, reflection, runtime expansion, and broader bytecode support are implemented.
