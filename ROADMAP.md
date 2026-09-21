# BendJVM roadmap

## Current position

Milestone 2 is complete: a Bend-owned MiniJRE runs small Java 8 apps that
use strings, collections, resources, files, blocking TCP, and try-with-resources.
Milestone 1 classpath/JAR/resource startup is unchanged. Host JDK classes are
not loaded.

## Spring Boot target

An actual Spring Boot application is not supported yet. Milestone 1 supplies
basic JAR/classpath/resource startup, but Spring Boot still requires:

- Reflection and runtime annotations.
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
