<div align="center">

# BendJVM

**A Java Virtual Machine interpreter implemented in Bend**

[Overview](#overview) • [Getting started](#getting-started) • [Usage](#usage) • [Testing](#testing) • [Architecture](#architecture)

</div>

BendJVM reads Java `.class` files, validates and decodes their bytecode, then executes them with an explicit JVM model written in [Bend](https://bend-lang.com/). JVM state stays in Bend: loaded classes, frames, locals, operand stacks, statics, heap entries, and interpreter status.

> [!WARNING]
> BendJVM is experimental. It targets a focused Java 8 compatibility slice, not full OpenJDK compatibility. Unsupported class-file features and opcodes fail explicitly.

## Overview

The execution pipeline is:

```text
Java source
    │  javac --release 8
    ▼
.class files
    │
    ▼
BendJVM
 ├─ binary reader and class-file parser
 ├─ constant-pool and descriptor validation
 ├─ bytecode decoder and branch validation
 ├─ stack-effect verifier
 ├─ class linker and bootstrap MiniJRE
 └─ explicit Bend-owned interpreter state
    │
    ▼
program output or a VM error
```

The project is designed around two boundaries:

- **Bend owns JVM semantics and state.** Host C/JavaScript code is limited to launch I/O, file/socket/TLS effects, the native-plugin helper, and the generated-artifact adapter. Java threads, monitors and their scheduling are Bend state.
- **The reference JVM is the oracle.** The differential test harness compiles the same Java fixture with `javac`, runs it with `java`, runs it with BendJVM, and compares observable output.

- Java 8 class files (major version 52)
- ordered directory, JAR, and ZIP classpath sources
- package-qualified class-name startup and standalone `.class` startup
- transitive application dependency resolution with first-match precedence
- manifest `Main-Class` and local `Class-Path` expansion for `-jar`
- classpath-root-relative resources through `ClassLoader.getSystemResourceAsStream`
- bounded stored/deflated archive reads with origin-aware diagnostics
- class loading, symbol interning, constant-pool linking, and descriptors
- integer and float arithmetic, signed integer behavior, branches, loops, and recursion
- static and virtual method calls, `invokeinterface`, constructors, objects, fields, and inherited fields
- primitive and reference arrays, array bounds, null references, and heap limits
- string constants, UTF-16 decoding, `String`/`StringBuilder`/`Integer`/`Math` MiniJRE methods
- `ArrayList`/`HashMap`, `invokeinterface`, in-memory and file streams, and UTF-8 readers
- blocking TCP client/server sockets, try-with-resources, and typed exception unwinding
- Java threads on a Bend scheduler: `Thread` lifecycle, interruption, `join`, `sleep`, daemon shutdown and uncaught-exception handlers, with preemption every 1000 instructions by default, weighted by thread priority
- JDK-style stack traces from `printStackTrace` and for uncaught exceptions, with source files and line numbers
- monitors: `synchronized` methods and blocks, `monitorenter`/`monitorexit`, `wait`/`notify`/`notifyAll`, and volatile fields under a sequentially consistent memory model
- scheduler-aware networking: classic sockets, `java.nio` buffers, `SocketChannel`/`ServerSocketChannel` and `Selector`, plus client/server TLS through `javax.net.ssl`
- a restricted native-plugin bridge (not JNI): `System.load`/`loadLibrary` of launcher-allowed libraries, run in a supervised helper process
- class initialization, typed Java exceptions, and `System.out.println` for supported primitive types
- instruction tracing, class dumps, disassembly, fuel limits, heap limits, and `--no-files`/`--no-net`
- structured annotation attributes parsed and retained through linking, including visible/invisible declaration, parameter, type, default, and `Exceptions` metadata
- `ldc` Class literals, cached mirrors for loaded classes/arrays, primitive and void mirrors, `Object.getClass`, `Class.forName(String)`, and `ClassLoader.loadClass(String)`
- bounded `Class` introspection, declared `Field`/`Method`/`Constructor` discovery, annotation materialization/defaults/repeatable queries, field access, reflective invocation, and construction
- interface dynamic proxies backed by Bend-owned handler callbacks, plus ordered classpath resource streams/URLs and bounded `Properties` parsing
- `ObjectOutputStream`/`ObjectInputStream` with the JDK stream format: computed or declared `serialVersionUID`s, back references, enums, arrays, proxies, custom `writeObject`/`readObject`, `writeReplace`/`readResolve`, `Externalizable`, unshared objects, `reset`, class evolution by field name, subclass hooks, `PutField`/`GetField`, validation callbacks, recorded write failures, serializable lambdas, any `InputStream` as a source, and stream classes loaded through the caller's class loader

## Getting started

### Prerequisites

Install the following tools:

- [Bend 2](https://bend-lang.com/)
- Python 3.10 or newer
- JDK 9 or newer, providing `javac --release 8` and `java`
- [Bun](https://bun.sh/), used to execute the JavaScript artifacts generated by Bend

From the project root, read the language guide and check the repository proof gate:

```bash
bend guide
bend PROOF.bend
```

### Run a Java class

Compile an example to a temporary output directory:

```bash
mkdir -p /tmp/bendjvm-classes
javac --release 8 -encoding UTF-8 \
  -d /tmp/bendjvm-classes \
  examples/HelloWorld.java
```

Run a standalone class file:

```bash
python3 scripts/run.py /tmp/bendjvm-classes/HelloWorld.class
```

Run a package-qualified class from an ordered directory/JAR/ZIP class path.
After compiling the packaged example below:

```bash
python3 scripts/run.py \
  -cp /tmp/bendjvm-app \
  example.hello.Main Bend
```

Launch an executable JAR. Its manifest supplies `Main-Class` and local
`Class-Path` dependencies:

```bash
python3 scripts/run.py -jar /tmp/example.jar application-argument
```

The runner builds and caches Bend loader/runtime artifacts under
`/tmp/bendjvm-cache` by default. Override tools or cache location with
`BEND`, `BUN`, or `BENDJVM_CACHE`.

Application arguments preserve spaces and Unicode and become a Bend-owned
`String[]`. CLI usage errors exit 2; loading and VM failures exit 1.

## Usage

```bash
python3 scripts/run.py [options] Main.class [application arguments...]
python3 scripts/run.py [options] -cp <entries> com.example.Main [arguments...]
python3 scripts/run.py [options] -jar app.jar [arguments...]
```

`-classpath` and `--class-path` are aliases for `-cp`; entries use the host
platform path separator. Classpath sources are searched left to right, and
the first matching class or resource wins. Empty entries mean the current
directory. `-jar` uses the selected archive and its manifest dependencies,
ignoring ordinary classpath settings.

Useful options:

| Option | Purpose |
| --- | --- |
| `--fuel N` | Stop after at most `N` interpreter steps. Default: `1000000`. |
| `--max-heap N` | Limit live heap entries. A collection runs when an allocation would pass the limit, and `OutOfMemoryError` is thrown if the live set still does not fit. Default: `1024`. |
| `--no-files` | Deny `FileInputStream`/`FileOutputStream` host effects. |
| `--no-net` | Deny socket, channel and TLS host effects. |
| `--quantum N` | Instructions a Java thread runs before the scheduler switches threads. Default: `1000`. |
| `--native-library NAME=PATH` | Allow `System.loadLibrary(NAME)` to load the plugin at absolute `PATH`. Repeatable. |
| `--native-allow PATH` | Allow `System.load(PATH)` for that absolute path. Repeatable. |
| `--native-timeout MS` | Deadline for one native call; on expiry the helper is stopped. Default: `30000`. |
| `--tls-trust PEM` | Trust roots for TLS peers. Without it the provider's system roots apply. |
| `--tls-key PEM` / `--tls-cert PEM` | The TLS identity: the server certificate, and the client certificate offered to servers that ask for one. Given together. |
| `--dump-class` | Print loaded class metadata without executing `main`. |
| `--disassemble` | Print class metadata and decoded instructions. |
| `--trace` | Print decoded instruction execution diagnostics to stderr. |
| `--prepare` | Build cached Bend loader/runtime artifacts without running a class. |

`--fuel` is one budget for every Java thread together. Native loading is off unless a `--native-*` option allows a library, and TLS material is checked (readable PEM, key matching certificate) before any Java code runs.

Archive sources accept stored and deflated entries. Reads are bounded at
64 MiB per entry and 512 MiB decompressed per archive. Unsafe names,
duplicates, encrypted entries, unsupported compression, and corrupt payloads
are rejected; archives are never extracted.

Example diagnostics:

```bash
python3 scripts/run.py --dump-class /tmp/bendjvm-classes/HelloWorld.class
python3 scripts/run.py --disassemble /tmp/bendjvm-classes/HelloWorld.class
python3 scripts/run.py --trace /tmp/bendjvm-classes/HelloWorld.class
python3 scripts/run.py --fuel 10000 /tmp/bendjvm-classes/HelloWorld.class
```

## Examples

Standalone programs in `examples/` cover the MiniJRE slice:

| File | What it shows |
| --- | --- |
| `HelloWorld.java` | strings, integers, and `String` concatenation of arguments |
| `ArithmeticAndBranches.java` | arithmetic, `for`/`while`, and comparisons |
| `ObjectsAndDispatch.java` | constructors, fields, virtual dispatch, and identity `equals` |
| `ArraysAndStrings.java` | integer arrays, `System.arraycopy`, and `substring` |
| `Exceptions.java` | caught `ArithmeticException` and `getMessage` |
| `StaticInitialization.java` | static fields and `<clinit>` |
| `CollectionsAndText.java` | `ArrayList`/`HashMap` via interfaces, boxing cache, `valueOf` |
| `FilesAndTryWithResources.java` | files, UTF-8 `readLine`, and try-with-resources |
| `TcpLoopback.java` | blocking TCP client and single-connection server |
| `ReflectionAndConfiguration.java` | direct runtime-visible annotation presence, private-field access, exact overload lookup, parameter mirrors, and `Properties` |

Both example harnesses validate output as well as exit status:
`python3 scripts/examples.py` runs the standalone corpus with selectable
`--only` entries, while `python3 examples/run.py` also exercises the packaged
directory and executable-JAR paths. The standalone reflection example focuses
on field/method/configuration behavior; the differential fixture corpus also
covers runtime annotation objects and dynamic proxies.

`examples/packaged/` is a small application: `example.hello.Main` depends on
`example.lib.Answer`, stores the argument and answer in an `ArrayList`, and
reads `banner.txt` from the classpath.

Run the standalone corpus with output assertions:

```bash
python3 scripts/examples.py
python3 scripts/examples.py --only ReflectionAndConfiguration --only TcpLoopback
```

Compile the standalone samples:

```bash
mkdir -p /tmp/bendjvm-classes
javac --release 8 -encoding UTF-8 -d /tmp/bendjvm-classes examples/*.java
python3 scripts/run.py /tmp/bendjvm-classes/HelloWorld.class
python3 scripts/run.py /tmp/bendjvm-classes/HelloWorld.class 'spaced arg'
python3 scripts/run.py /tmp/bendjvm-classes/CollectionsAndText.class
python3 scripts/run.py /tmp/bendjvm-classes/TcpLoopback.class
python3 scripts/run.py /tmp/bendjvm-classes/FilesAndTryWithResources.class /tmp/bendjvm-example.bin
python3 scripts/run.py /tmp/bendjvm-classes/ReflectionAndConfiguration.class
```

Compile and run the packaged application from a directory:

```bash
mkdir -p /tmp/bendjvm-app
javac --release 8 -encoding UTF-8 -d /tmp/bendjvm-app \
  examples/packaged/example/hello/Main.java \
  examples/packaged/example/lib/Answer.java
cp examples/packaged/banner.txt /tmp/bendjvm-app/
python3 scripts/run.py -cp /tmp/bendjvm-app example.hello.Main Bend
```

Expected packaged output:

```text
Bend
42
66
```

`66` is the first byte of `banner.txt` (`B`). The same classes also run from a
JAR whose manifest names `example.hello.Main`.

`examples/webserver/` is a small HTTPS/1.1 server: an acceptor thread feeds a
monitor-protected work queue, three workers answer requests, a volatile flag
stops it, and `POST /checksum` calls a native plugin. Build and run it with a
test CA and identity of your own (the test suite generates throwaway ones):

```bash
mkdir -p /tmp/bendjvm-web
javac --release 8 -d /tmp/bendjvm-web examples/webserver/example/web/*.java
cc -shared -fPIC -I bendjvm/native -o /tmp/bendjvm-web/libwebchecksum.so examples/webserver/native/web_checksum.c
python3 scripts/run.py --fuel 2000000000 --tls-trust ca.pem --tls-key server.key --tls-cert server.pem \
  --native-library webchecksum=/tmp/bendjvm-web/libwebchecksum.so -cp /tmp/bendjvm-web example.web.HttpsServer 8443
```

On macOS use `-dynamiclib` and a `.dylib` name for the plugin.

Run every example through the practical runner:

```bash
python3 examples/run.py
```

The broader differential corpus lives in `bendjvm/tests/fixtures/` and includes integer/float operations, arrays, inheritance, strings, exceptions, class initialization, collections, files, TCP, try-with-resources, fuel limits, heap limits, classpaths, archives, manifests, and resources.

## Testing

Run the fast differential suite:

```bash
python3 scripts/test.py --fast
```

Run the complete fixture corpus, malformed class-file cases, CLI checks, and 24 generated integer programs:

```bash
python3 scripts/test.py --full
```

Run selected fixtures:

```bash
python3 scripts/test.py --only Arithmetic --only IntArray
```

The harness requires Python 3.10+, a JDK, Bend 2, and Bun. It compiles sources and writes generated or mutated class files to temporary directories outside the repository. Override executables with `--bend`, `--java`, `--javac`, or the corresponding `BEND`, `JAVA`, and `JAVAC` environment variables.

## Architecture

| Area | Responsibility |
| --- | --- |
| `bendjvm/classfile/` | Big-endian reader, Java 8 class parser, constant pool, attributes, descriptors, and modified UTF-8. |
| `bendjvm/bytecode/` | Instruction decoding, operand normalization, decoded program counters, and branch-target checks. |
| `bendjvm/verifier/` | Stack contracts, local bounds, descriptor checks, and instruction validation. |
| `bendjvm/loader/` | Symbol interning, class catalog/linking, bootstrap classes, intrinsic registration, metadata retention, and VM construction. |
| `bendjvm/heap/` | Object, primitive-array, reference-array, string, and resource-stream entries with bounded allocation. |
| `bendjvm/java/` | MiniJRE intrinsics: objects/strings/collections, bounded class mirrors/member discovery, resources/URL/Properties, streams, files, threads and monitors, the `HostIO` socket gateway, native plugin calls, throwables, and `println`. |
| `bendjvm/runtime/` | The interpreter, frames, wide arithmetic, the thread/monitor records (`threads.bend`) and the scheduler (`scheduler.bend`). |
| `bendjvm/jre/` | MiniJRE classes written in Java and compiled during `--prepare`: `Thread`, sockets, `java.nio` buffers/channels/selectors, and `javax.net.ssl`. |
| `bendjvm/native/` | `bendjvm_plugin.h`, the versioned native-plugin ABI. |
| `bendjvm/native/helper.c` | The supervised process that loads allowed plugins and runs their calls; compiled on first use (needs `cc`). |
| `scripts/classpath.py` | Ordered directory/JAR/ZIP sources, manifest expansion, bounded reads, and resource lookup. |
| `scripts/run.py` | Builds cached Bend JavaScript artifacts and provides the structured practical command-line runner. |
| `scripts/test.py` | Differential, classpath/JAR, file/TCP, malformed-input, limit, debug-mode, and generated-program tests. |
| `LAWS.bend` / `PROOF.bend` | Bend law declarations and proofs checked by `bend PROOF.bend`. |

## MiniJRE surface

Supported methods are registered by exact owner, name, descriptor, and flags in
`bendjvm/loader/bootstrap.bend`. Unlisted overloads are not implied by a class
name; they fail with `NoSuchMethodError` before execution. Access flags are
`public` instance native (`0x0101`), `public static` native (`0x0109`), or
interface abstract (`0x0401`).

| Area | Classes and descriptors |
| --- | --- |
| Objects | `Object.<init>()V`, `equals(Ljava/lang/Object;)Z`, `hashCode()I`, `toString()Ljava/lang/String;`; `Objects.requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;`, `equals(Ljava/lang/Object;Ljava/lang/Object;)Z` |
| Strings | `String.length()I`, `isEmpty()Z`, `charAt(I)C`, `equals`, `hashCode`, `substring(I)`, `substring(II)`, `concat`, `toString`, `valueOf(I\|Z\|Ljava/lang/Object;)`; `StringBuilder.<init>()V`, `<init>(Ljava/lang/String;)V`, `append(String\|Object\|I\|C\|Z)`, `length`, `toString` |
| Integers / Math | `Integer.valueOf(I)`, `intValue()`, `parseInt`, `equals`, `hashCode`, `toString`; cached `valueOf` identities for `-128..127`; `Math.abs/min/max` on `I`; `System.arraycopy` |
| Collections | `ArrayList`/`List`/`Collection`/`Iterable`/`Iterator` and `HashMap`/`Map` as registered in bootstrap, including iterator `hasNext/next/remove` |
| Streams | `InputStream.read()I`, `read([B)I`, `read([BII)I`, `close`; `OutputStream.write(I\|[B\|[BII)`, `flush`, `close`; `ByteArrayInputStream([B)`, `ByteArrayOutputStream` `toByteArray/size/reset` |
| Serialization | `ObjectOutputStream(OutputStream)` `writeObject`, `writeUnshared`, `defaultWriteObject`, `reset`, `DataOutput` writes, `flush`, `close`; `ObjectInputStream(InputStream)` `readObject`, `readUnshared`, `defaultReadObject`, `DataInput` reads, `read`, `readFully`, `skipBytes`, `available`, `close`; `Externalizable`; the subclass hooks (`resolveClass`, `annotateClass`, `replaceObject`, `readClassDescriptor`, the override constructors and the rest); `ObjectStreamClass`/`ObjectStreamField`, `serialPersistentFields` with `PutField`/`GetField`, `registerValidation`, and `TC_EXCEPTION` |
| Files | `File(String)` `exists/isFile/isDirectory/getPath`; `FileInputStream(String)`; `FileOutputStream(String)` and `(String,Z)` |
| Reflection / metadata | `Object.getClass()`, cached primitive/void/array/class mirrors and wrapper `TYPE` fields, `Class` name/superclass/modifier/array/interface/primitive/assignability/instance checks, annotation queries/materialization/defaults/repeatable expansion, `cast`, `forName(String)` and `forName(String,boolean,ClassLoader)`, `ClassLoader.loadClass(String)`, declared member arrays and exact name/parameter lookup, declaring-class/basic metadata accessors, per-handle `AccessibleObject.setAccessible/isAccessible`, `Field.get/set`, `Method.invoke`, and `Constructor.newInstance`; generic accessors: `Class.getGenericSuperclass`, `Field.getGenericType`, `Method.getGenericReturnType/getGenericParameterTypes/getGenericExceptionTypes`; annotated accessors: `Field.getAnnotatedType`, `Method.getAnnotatedReturnType/getAnnotatedParameterTypes`; `Proxy`/`InvocationHandler` interface proxies, generated-class identity, category-one boxing, and handler lookup |
| Resources / configuration | `Class`/`ClassLoader` relative/root lookup, ordered `getResources`, origin-bound `URL.openStream`, local URL path/protocol/string accessors, `Properties.load(InputStream)` and bounded UTF-8 `Properties.load(Reader)` for memory-backed `InputStreamReader`, `getProperty`/default getter/`setProperty`; lookup is ordered and first-match |
| Text | `Reader.read()I`, `read([CII)I`, `close`; `Writer.write(I\|String\|[CII)`, `flush`, `close`; `InputStreamReader`/`OutputStreamWriter` `(stream, UTF-8)`; `BufferedReader.readLine` |
| Threads | `Runnable`; `Thread()`, `(Runnable)`, `(String)`, `(Runnable,String)`, `start`, `run`, `currentThread`, `isAlive`, `getState`, `getId`, `get/setName`, `set/isDaemon`, `join()`/`(J)`/`(JI)`, `sleep(J)`/`(JI)`, `yield`, `interrupt`, `isInterrupted`, `interrupted`, `holdsLock`, per-thread and default `UncaughtExceptionHandler`; `Thread.State`; `ThreadGroup` (hierarchy, `activeCount`, `enumerate`, `interrupt`, `setMaxPriority`, `uncaughtException`) and the `Thread(ThreadGroup, ...)` constructors; `Object.wait()`/`(J)`/`(JI)`, `notify`, `notifyAll`; `System.nanoTime`, `currentTimeMillis` |
| TCP | `InetAddress.getByName`, `getLoopbackAddress`, `getHostAddress`, `getHostName`, `getAddress`; `InetSocketAddress(String,I)`/`(InetAddress,I)`/`(I)`, `createUnresolved`, `isUnresolved`; `Socket()`, `(String,I)`, `connect`, `getInputStream`, `getOutputStream`, `setSoTimeout`, `shutdownInput`, `shutdownOutput`, `isClosed`, `isConnected`, `close`; `ServerSocket(I)`, `bind`, `getLocalPort`, `accept`, `setSoTimeout`, `close` |
| NIO | `Buffer` position/limit/capacity/`clear`/`flip`/`rewind`/`remaining`; `ByteBuffer.allocate/wrap`, relative, indexed and bulk `get`/`put`, `compact`, `slice`, `duplicate`, `array`; `SocketChannel`, `ServerSocketChannel`, `Selector`, `SelectionKey` with the `keys()`/`selectedKeys()` sets |
| TLS | `SSLContext.getDefault/getInstance`, `SSLSocketFactory`, `SSLServerSocketFactory`, `SSLSocket` handshake/session/parameters/protocol and suite selection, `SSLServerSocket` with `setNeedClientAuth`, `SSLParameters` endpoint identification, `SSLSession` |
| Native | `System.load(String)`, `System.loadLibrary(String)`, and `native` methods bound through `bendjvm/native/bendjvm_plugin.h` |
| Throwables | `Throwable` no-arg/message/cause/message+cause `<init>`, `getMessage`, `getCause`, `initCause`, `addSuppressed`, `getSuppressed`, `toString`, `printStackTrace()`/`(PrintStream)` with source lines; `UndeclaredThrowableException` cause access; `IOException` has the four Java 8 constructors |

The reflection slice is intentionally bounded. Class mirrors are cached for
loaded class and array identities. Declared members expose basic metadata;
`Field.get/set`, `Method.invoke`, and `Constructor.newInstance` cover the
supported access path, including primitive wrapper arguments and results.
Primitive/void mirrors and wrapper `TYPE` fields are supported. `setAccessible`
is tracked per reflective handle for bounded private-member access. Runtime
annotations materialize supported scalar/reference values, raw-word boxed
`Long`/`Double` values, defaults, parameter metadata, defensive array results,
and repeatable containers.
`Class.forName(name, false, loader)` leaves a loaded class uninitialized;
the `true` form initializes the superclass chain before the direct `<clinit>`,
and the supported application namespace is loader-aware. Interface proxies
generate a public `InvocationHandler` constructor, validate interface
visibility/conflicts/returns, preserve declared checked exceptions, cache by
loader and ordered interfaces, and wrap undeclared checked throwables.
Method, field, and class `Signature` attributes expose generic return,
parameter, exception, field, and superclass types, including parameterized
type arguments and type-variable names.
`AnnotatedType` covers method return/parameter types and field type-argument
paths; class type parameters, generic interfaces, and local-variable/expression
sites remain metadata-only.
`Class.forName(name, initialize, null)` resolves bootstrap classes through the
bootstrap loader.
Plan 03's completion slices go further: Java 8 access rules, default-method special invocation, user class loaders, subclass proxies, package scanning, JDK annotation and URL formatting, serialization, and privileged actions.
[Plan 03](.plans/03-reflection-and-metadata.md) lists each slice and its remaining limitations.

Resources are root-relative for `ClassLoader` and package-relative for `Class`;
relative class names normalize `./` and `..`, while single lookups preserve
first-match classpath order. `getResources` enumerates every matching origin in
order. Returned URLs retain the selected origin, reopen it independently, and
expose local `file:`/`jar:file:` protocol and UTF-8 percent-escaped string
forms for supported local paths.

`Properties.load(InputStream)` handles ISO-8859-1 bytes, Unicode escapes,
comments, separators, continuation lines, duplicate-key last-write behavior,
default getters, and malformed Unicode escape rejection. `load(Reader)` is
implemented for the bounded UTF-8 `InputStreamReader` over memory resources;
other reader backends remain unsupported.

The class-file metadata parser validates declaration, parameter, type, and
nested `Code` type-annotation attributes and links them into method metadata.
Runtime-visible annotations materialize supported values on demand; CLASS
retention remains absent from runtime query results. Wide annotation constants
are carried losslessly as two raw U32 words and box to ordinary `Long` and
`Double` values.

`long` and `double` run as two-word category-two values. Binary64 arithmetic,
remainder and conversions are computed in Bend, and `Double.toString` matches
the JDK's shortest-decimal output. `Long` and `Double` provide `valueOf`,
unboxing, `equals`, `hashCode`, `toString`, `parseLong`, `isNaN`,
`isInfinite` and the raw-bits conversions.

`java.lang.invoke` supports `MethodType`, `MethodHandles.lookup()` with the
`find*` family, `bindTo`, `asType`, `insertArguments`, `constant`,
`identity`, varargs collectors, `invokeExact`/`invoke`, and constant, mutable
and volatile call sites. `invokedynamic` runs any bootstrap method built from
that surface; `LambdaMetafactory.metafactory` and `altMetafactory` (including
`SerializedLambda`) back Java 8 lambdas and method references.

Host file and socket effects use opaque handles scoped to one VM run and never reused. `--no-files`
and `--no-net` deny those effects with `IOException` (`SocketException` for sockets). `--max-heap` counts live heap
entries. A file or socket that becomes garbage while still open is closed by the host after the collection that reclaimed it; there are no finalizers. Relative files resolve against the launch working directory. The host
closes remaining handles on every process exit, including fuel exhaustion and
uncaught exceptions. This is a capability control, not a sandbox.

## Compatibility boundary
BendJVM accepts Java 8 class files and ordered directory/JAR/ZIP classpaths, but
intentionally does not provide full JVM or OpenJDK compatibility. It does not
yet promise:

- full reflection access-edge compatibility (caller package cases), complex
  static-initialization edges, parameter-name reflection, or complete
  annotation formatting
- modules, JNI, agents, custom class-loader subclasses, arbitrary `defineClass`,
  or multiple independent application-loader namespaces
- `StringConcatFactory`, constant-dynamic linkage, or MethodHandle combinators
  beyond `bindTo`, `asType`, `insertArguments` and varargs collection
- default-method special proxy invocation
- verification beyond the Java 8 StackMapTable type checker; there is no
  inference-based fallback for class files without frames
- JNI (the native bridge is BendJVM's own restricted ABI), `ThreadLocal`, `java.util.concurrent`, `SSLEngine`, TLS over
  selectable channels, `DatagramChannel` or direct buffers
- moving or generational garbage collection, `System.gc`, soft/weak/phantom references, finalizers, JIT compilation, or Spring Boot nested-JAR layouts

BendJVM is not a sandbox-grade security boundary. Java code only reaches host behavior through registered intrinsics, but untrusted bytecode should still be treated as untrusted input.
Native plugins run real native code with the helper process's operating-system permissions: the separate process keeps a plugin crash away from the VM, but it does not contain a malicious library.

## Design direction

The project specification is documented in [`bendjvm-spec.md`](bendjvm-spec.md). Its guiding principles are:

1. Decode class files once and execute compact linked instructions.
2. Resolve names into numeric IDs before instruction execution.
3. Represent the JVM as explicit state transitions rather than relying on Bend call-stack state.
4. Reject unsupported semantics instead of approximating them.
5. Prove small interpreter invariants in Bend before optimizing representation or dispatch.

Classpath loading, the MiniJRE, reflection, the Java 8 bytecode set, threads, monitors,
networking, TLS and the native bridge are in place. The next milestone is the Spring
Boot launcher layout.
