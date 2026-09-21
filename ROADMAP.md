# BendJVM roadmap

## Current position

Milestone 1 runs Java 8 applications from standalone classes, ordered directory
classpaths, JARs, and ZIPs. It resolves the selected class's transitive
application closure, reads dependency resources, and launches executable JARs
through manifest metadata.

The host owns source indexing, bounded archive bytes, manifest expansion, and
the structured launch request. Bend owns class parsing/linking, entry
validation, argument-array allocation, resource lookup, stream state, and VM
execution.

## Spring Boot target

An actual Spring Boot application is not supported yet. Milestone 1 supplies
basic JAR/classpath/resource startup, but Spring Boot still requires:

- Reflection and runtime annotations.
- Dynamic proxies.
- `invokedynamic`.
- Threads and synchronization.
- Native libraries, sockets, NIO, and TLS.
- A much larger Java standard library and nested-JAR launcher support.

Without these features, a Spring Boot application would fail when it loads
missing runtime classes or reaches unsupported bytecode.

## Roadmap

### 1. JAR and classpath loading — complete

- Read classes from JAR and ZIP files with bounded stored/deflated reads.
- Resolve application dependencies from ordered directories and archives.
- Load resources from dependency archives through the MiniJRE stream slice.
- Support manifest `Main-Class` startup and local transitive `Class-Path`.

### 2. Java runtime expansion

- Add the standard library classes needed by common applications.
- Expand file, stream, collection, and networking support.
- Improve exception and resource handling.

### 3. Reflection and metadata

- Parse runtime annotations.
- Implement reflective class, method, field, and constructor access.
- Support dynamic proxies.
- Add resource lookup for framework configuration.

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
