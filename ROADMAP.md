# BendJVM roadmap

## Current position

BendJVM currently runs standalone Java 8 `.class` files.

The runner loads the target class and nearby companion `.class` files.

It does not yet run full Java applications or resolve dependency classpaths.

## Spring Boot target

An actual Spring Boot application is not supported yet.

Spring Boot requires several capabilities outside the current V1 runtime:

- JAR and dependency classpath loading.
- Reflection and runtime annotations.
- Dynamic proxies.
- `invokedynamic`.
- Threads and synchronization.
- Native libraries, sockets, NIO, and TLS.
- A much larger Java standard library.

Without these features, a Spring Boot application would fail when it loads missing runtime classes or reaches unsupported bytecode.

## Roadmap

### 1. JAR and classpath loading

- Read classes from JAR and ZIP files.
- Resolve application dependencies from a classpath.
- Load resources from dependency archives.
- Support manifest-based application startup.

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
