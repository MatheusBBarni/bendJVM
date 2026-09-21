# BendJVM

## 1. Overview

BendJVM is a Java Virtual Machine interpreter implemented in Bend.

Its purpose is to:

1. Read Java `.class` files directly from Bend.
2. Parse the JVM class-file format.
3. Decode JVM bytecode.
4. Model JVM runtime state in Bend.
5. Execute JVM bytecode instruction-by-instruction.
6. Implement a minimal Java runtime required to execute useful programs.
7. Formally verify selected JVM invariants using Bend laws and proofs.

The project does **not** compile Bend into JVM bytecode.

Instead:

```text
Java source
    │
    ▼
  javac
    │
    ▼
 .class
    │
    ▼
┌──────────────────────────────┐
│ BendJVM                      │
│ implemented in Bend          │
│                              │
│ class parser                 │
│ bytecode decoder             │
│ verifier                     │
│ frames                       │
│ operand stacks               │
│ heap                         │
│ class loader                 │
│ interpreter                  │
│ Java runtime intrinsics      │
└───────────────┬──────────────┘
                │
                ▼
          program result
```

The initial goal is not full JVM compatibility.

The first target is:

> Execute simple Java 8 class files compiled using `javac --release 8`, single-threaded, with integer arithmetic, method calls, objects, fields, arrays, strings, and basic console output.

---

# 2. Project Goals

BendJVM should demonstrate that Bend can implement a non-trivial systems runtime.

Primary goals:

* JVM class-file parsing in Bend.
* JVM bytecode execution in Bend.
* JVM stack-machine simulation.
* Object heap implemented in Bend.
* Dynamic class loading.
* Java method invocation.
* Basic object-oriented dispatch.
* Exceptions.
* Arrays.
* Minimal Java standard-runtime support.
* Formal runtime invariants expressed with `LAWS.bend`.
* Differential testing against a reference JVM.
* Deterministic execution where applicable.
* Clean separation between JVM semantics and Bend host effects.

Secondary goals:

* Bytecode verification.
* Garbage collection.
* Thread simulation.
* JVM long support.
* Performance benchmarking.
* Runtime debugging/tracing.
* Classpath support.

Long-term goals:

* Larger Java bytecode coverage.
* `invokedynamic`.
* JVM synchronization semantics.
* More complete Java library emulation.
* Optimizing interpreter.
* Parallel execution experiments.
* Potential JIT or partial evaluation.

---

# 3. Non-Goals for V1

The first version will not support:

* Full OpenJDK compatibility.
* JAR/ZIP loading.
* Java modules.
* JNI.
* Native libraries.
* Java agents.
* Reflection.
* Method handles.
* `invokedynamic`.
* Java threads.
* Monitors.
* `synchronized`.
* `volatile`.
* full `long` support.
* `double`.
* full floating-point edge-case compatibility.
* class redefinition.
* custom class loaders.
* annotations.
* generics at runtime.
* dynamic proxies.
* full verifier compatibility.
* Java security manager.
* JIT compilation.

V1 operates on one or more `.class` files.

---

# 4. Bend Constraints

The implementation must account for Bend 2's current characteristics.

Important Bend characteristics:

```text
available:
Nat
U32
F32
Array
List
Map
Set
File IO
binary file reads
recursion
dependent types
laws/proofs

missing:
U64
I64
F64
```

Therefore JVM types map as follows:

```text
JVM int        → U32 bit representation
JVM float      → F32
JVM reference  → U32 heap reference
JVM long       → two U32 values
JVM double     → unsupported initially
```

JVM 32-bit signed integer semantics must be implemented over raw U32 bits.

---

# 5. Initial Compatibility Target

Initial target:

```bash
javac --release 8 Main.java
```

Example supported program:

```java
public class Main {

    static int square(int value) {
        return value * value;
    }

    public static void main(String[] args) {
        int value = square(10);
        System.out.println(value);
    }
}
```

Expected:

```bash
bend bendjvm/main.bend -- Main.class
```

Output:

```text
100
```

---

# 6. Repository Structure

```text
bendjvm/
│
├── main.bend
│
├── classfile/
│   ├── model.bend
│   ├── reader.bend
│   ├── parser.bend
│   ├── constant_pool.bend
│   ├── field.bend
│   ├── method.bend
│   ├── attribute.bend
│   ├── descriptor.bend
│   └── access_flags.bend
│
├── bytecode/
│   ├── opcode.bend
│   ├── instruction.bend
│   ├── decode.bend
│   └── branch.bend
│
├── verifier/
│   ├── verifier.bend
│   ├── stack.bend
│   └── control_flow.bend
│
├── runtime/
│   ├── value.bend
│   ├── slot.bend
│   ├── frame.bend
│   ├── stack.bend
│   ├── locals.bend
│   ├── vm.bend
│   ├── execute.bend
│   ├── method.bend
│   └── result.bend
│
├── heap/
│   ├── heap.bend
│   ├── object.bend
│   ├── array.bend
│   └── gc.bend
│
├── loader/
│   ├── class_loader.bend
│   ├── loaded_class.bend
│   ├── resolver.bend
│   ├── symbols.bend
│   └── classpath.bend
│
├── java/
│   ├── intrinsic.bend
│   ├── object.bend
│   ├── string.bend
│   ├── system.bend
│   ├── print_stream.bend
│   ├── throwable.bend
│   └── math.bend
│
├── debug/
│   ├── tracer.bend
│   ├── dump.bend
│   └── disassemble.bend
│
├── tests/
│   ├── classfile/
│   ├── bytecode/
│   ├── execution/
│   ├── java/
│   └── fixtures/
│
├── LAWS.bend
└── PROOF.bend
```

---

# 7. Runtime Architecture

```text
                        .class
                           │
                           ▼
                  ┌────────────────┐
                  │ File Reader    │
                  └───────┬────────┘
                          │ bytes
                          ▼
                  ┌────────────────┐
                  │ Class Parser   │
                  └───────┬────────┘
                          │
                          ▼
                  ┌────────────────┐
                  │ Class Model    │
                  └───────┬────────┘
                          │
                          ▼
                  ┌────────────────┐
                  │ Class Loader   │
                  └───────┬────────┘
                          │
                          ▼
                  ┌────────────────┐
                  │ Bytecode       │
                  │ Decoder        │
                  └───────┬────────┘
                          │
                          ▼
                  ┌────────────────┐
                  │ Verifier       │
                  └───────┬────────┘
                          │
                          ▼
       ┌──────────────────────────────────┐
       │ VM                               │
       │                                  │
       │ frames                           │
       │ locals                           │
       │ operand stacks                   │
       │ heap                             │
       │ static fields                    │
       │ loaded classes                   │
       │ instruction pointer              │
       └───────────────┬──────────────────┘
                       │
                       ▼
               ┌────────────────┐
               │ Interpreter    │
               └───────┬────────┘
                       │
              ┌────────┴────────┐
              ▼                 ▼
         bytecode          intrinsic
         execution          execution
                                │
                                ▼
                            Bend IO
```

---

# 8. Class File Input

BendJVM receives:

```text
Main.class
```

V1 invocation:

```bash
bend main.bend -- Main.class
```

Future:

```bash
bend main.bend -- \
  --classpath ./classes \
  com.example.Main
```

---

# 9. Binary Reader

Class files are binary.

The reader must support:

```text
readU1
readU2
readU4
skip
slice
position
remaining
```

Reader state:

```text
Reader {
    bytes
    position
}
```

Conceptual API:

```text
read_u1(reader)
    -> Reader & Result<U32>

read_u2(reader)
    -> Reader & Result<U32>

read_u4(reader)
    -> Reader & Result<U32>
```

All reads are big-endian.

Example:

```text
CA FE BA BE
```

becomes:

```text
0xCAFEBABE
```

---

# 10. File Validation

Class-file parsing must validate:

```text
magic == 0xCAFEBABE
```

Then read:

```text
minor_version
major_version
```

V1 should accept Java 8 class versions.

Class version:

```text
major = 52
```

should be the recommended compatibility target.

Later versions may be accepted only when their required features are supported.

---

# 11. Class File Model

Conceptually:

```text
ClassFile {
    minorVersion
    majorVersion

    constantPool

    accessFlags

    thisClass
    superClass

    interfaces

    fields

    methods

    attributes
}
```

---

# 12. Constant Pool Model

V1 types:

```text
Utf8
Integer
Float
Class
String
FieldRef
MethodRef
InterfaceMethodRef
NameAndType
```

Later:

```text
Long
Double
MethodHandle
MethodType
Dynamic
InvokeDynamic
Module
Package
```

Suggested Bend representation:

```text
Constant =
    CpUtf8
    CpInteger
    CpFloat
    CpClass
    CpString
    CpFieldRef
    CpMethodRef
    CpInterfaceMethodRef
    CpNameAndType
```

References remain constant-pool indices.

---

# 13. UTF-8 Handling

Class-file names should not remain Bend strings during normal execution.

Examples:

```text
java/lang/Object
java/lang/System
println
main
Code
([Ljava/lang/String;)V
```

should be interned.

Pipeline:

```text
constant pool UTF-8 bytes
        │
        ▼
symbol interner
        │
        ▼
SymbolId : U32
```

Then runtime objects reference:

```text
ClassId
MethodId
FieldId
SymbolId
```

rather than comparing linked-list strings.

---

# 14. Symbol Table

Model:

```text
SymbolTable {
    symbols
}
```

Conceptually:

```text
17 -> java/lang/Object
18 -> java/lang/System
19 -> println
20 -> main
```

Internal comparisons use U32 IDs.

---

# 15. Descriptor Parser

Must parse JVM descriptors.

Examples:

```text
I
F
V

Ljava/lang/String;

[I

()V

(I)I

([Ljava/lang/String;)V
```

Representation:

```text
JvmType =
    TInt
    TFloat
    TLong
    TDouble
    TByte
    TChar
    TShort
    TBoolean
    TObject{class}
    TArray{element}
    TVoid
```

Method descriptor:

```text
MethodDescriptor {
    parameters
    returnType
}
```

---

# 16. Method Model

```text
Method {
    id

    classId

    name
    descriptor

    accessFlags

    maxStack
    maxLocals

    code

    exceptionTable
}
```

Decoded bytecode should be stored separately from raw bytecode.

---

# 17. Instruction Decoding

Raw code:

```text
04
05
60
3C
B1
```

should become:

```text
IConst 1
IConst 2
IAdd
IStore 1
Return
```

The VM should not repeatedly decode raw bytecode while executing.

---

# 18. Instruction Representation

Suggested:

```text
Instruction =
    Nop
    IConst{value}
    BiPush{value}
    SiPush{value}

    ILoad{index}
    IStore{index}

    IAdd
    ISub
    IMul
    IDiv
    IRem
    INeg

    IInc{index, amount}

    IfEq{target}
    IfNe{target}
    IfLt{target}
    IfLe{target}
    IfGt{target}
    IfGe{target}

    IfICmpEq{target}
    IfICmpNe{target}
    IfICmpLt{target}
    IfICmpLe{target}
    IfICmpGt{target}
    IfICmpGe{target}

    Goto{target}

    GetStatic{field}
    PutStatic{field}

    GetField{field}
    PutField{field}

    New{class}

    InvokeStatic{method}
    InvokeSpecial{method}
    InvokeVirtual{method}

    IReturn
    Return
```

Later:

```text
arrays
long
float
references
exceptions
interfaces
switch
monitor
invokedynamic
```

---

# 19. Decoded Program Counter

The runtime should use decoded instruction indices rather than raw byte offsets.

During decoding:

```text
byteOffset -> instructionIndex
```

mapping must be built.

Example:

```text
raw:

0:  bipush 10
2:  istore_1
3:  goto 10
6:  ...

decoded:

0: BiPush(10)
1: IStore(1)
2: Goto(5)
```

Branches should be resolved to decoded instruction indices.

---

# 20. Branch Validation

Decoder/verifier must ensure:

```text
branch target exists

branch target points to
an instruction boundary
```

Invalid target:

```text
middle of SIPUSH operand
```

must reject the class.

---

# 21. JVM Value Representation

Use explicit JVM slots.

Suggested:

```text
Slot {
    tag
    value
}
```

Tags:

```text
EMPTY

INT
FLOAT
REFERENCE

LONG_HIGH
LONG_LOW

DOUBLE_HIGH
DOUBLE_LOW

RETURN_ADDRESS
```

Physical values are U32.

---

# 22. Integer Semantics

JVM `int` is signed 32-bit two's-complement.

Store raw bits:

```text
JvmInt = U32
```

Operations:

```text
iadd
isub
imul
```

naturally use wrapping 32-bit arithmetic.

Signed operations must use helper functions:

```text
int_is_negative
int_compare_signed
int_div_signed
int_rem_signed
int_shift_right_arithmetic
```

---

# 23. Integer Helpers

Required helpers:

```text
jint_add
jint_sub
jint_mul
jint_div
jint_rem
jint_neg

jint_shl
jint_shr
jint_ushr

jint_and
jint_or
jint_xor

jint_eq
jint_lt
jint_le
jint_gt
jint_ge
```

---

# 24. Float Semantics

JVM float maps to Bend:

```text
F32
```

Initial opcodes:

```text
fconst_*
fload
fstore

fadd
fsub
fmul
fdiv

freturn
```

Bend's current F32 proof limitations mean float semantics should be tested but not form part of strong arithmetic laws initially.

---

# 25. Long Representation

Future representation:

```text
JLong {
    hi: U32
    lo: U32
}
```

A JVM long uses two operand slots.

Required eventual operations:

```text
ladd
lsub
lmul
ldiv
lrem
lneg

lshl
lshr
lushr

land
lor
lxor

lcmp
```

V1 may reject all long opcodes.

---

# 26. Double Representation

Potential bit container:

```text
JDoubleBits {
    hi: U32
    lo: U32
}
```

This preserves binary data but does not provide F64 arithmetic.

V1:

```text
double unsupported
```

Any opcode such as:

```text
dadd
dmul
ddiv
dreturn
```

must return:

```text
UnsupportedOpcode
```

Future implementations may use:

* software F64
* foreign host effect
* future Bend native F64

---

# 27. References

Heap references are U32.

```text
0 = null

1...N = object IDs
```

Representation:

```text
JvmReference = U32
```

Null:

```text
0
```

---

# 28. Operand Stack

Each frame owns its JVM operand stack.

Representation:

```text
OperandStack {
    tags
    values
    pointer
}
```

Preferred:

```text
Array<U32> tags
Array<U32> values
U32 sp
```

Push:

```text
stack_push
```

Pop:

```text
stack_pop
```

Peek:

```text
stack_peek
```

Stack capacity:

```text
method.maxStack
```

---

# 29. Local Variables

Each frame owns:

```text
locals.tags
locals.values
```

capacity:

```text
method.maxLocals
```

Operations:

```text
local_get
local_set
```

All access must bounds-check.

---

# 30. Frame

```text
Frame {
    classId
    methodId

    pc

    locals
    operandStack
}
```

The VM stores multiple frames.

---

# 31. Call Stack

Do not map Java calls directly onto Bend recursion.

Maintain explicit JVM frames:

```text
main
 │
 ▼
foo
 │
 ▼
bar
```

represented as:

```text
VM.frames
```

This is required for:

* proper JVM semantics
* exceptions
* stack traces
* recursion
* debugging
* future threads

---

# 32. VM State

```text
VM {
    classes

    heap

    staticFields

    frames

    status
}
```

Status:

```text
Running
Returned
Throwing
Halted
OutOfFuel
Failed
```

---

# 33. Interpreter Core

Core primitive:

```text
step(vm) -> StepResult
```

Exactly one JVM instruction is executed.

Example:

```text
IADD

pop b
pop a

push(a + b)

pc += 1
```

---

# 34. Interpreter Loop

Safe model:

```text
run(fuel, vm)
```

Each executed instruction consumes one unit.

```text
run(1000000, vm)
```

returns:

```text
Finished
OutOfFuel
Failed
```

This allows Bend's termination checker to prove the interpreter invocation terminates.

---

# 35. Unlimited Execution

Optional:

```text
@unsafe
run_forever(vm)
```

This may repeatedly call:

```text
step
```

without fuel.

Production CLI may use the unsafe runner.

Proofs should focus on:

```text
step
run(fuel, vm)
```

---

# 36. First Opcode Set

Milestone 1:

## Constants

```text
nop

iconst_m1
iconst_0
iconst_1
iconst_2
iconst_3
iconst_4
iconst_5

bipush
sipush

ldc
```

## Loads

```text
iload
iload_0
iload_1
iload_2
iload_3
```

## Stores

```text
istore
istore_0
istore_1
istore_2
istore_3
```

## Integer arithmetic

```text
iadd
isub
imul
idiv
irem
ineg
```

## Integer bit operations

```text
ishl
ishr
iushr

iand
ior
ixor
```

## Increment

```text
iinc
```

## Branch

```text
ifeq
ifne
iflt
ifge
ifgt
ifle

if_icmpeq
if_icmpne
if_icmplt
if_icmpge
if_icmpgt
if_icmple

goto
```

## Calls

```text
invokestatic
```

## Return

```text
ireturn
return
```

---

# 37. Milestone 1 Supported Program

```java
public class Main {

    static int fib(int n) {
        if (n <= 1) {
            return n;
        }

        return fib(n - 1) + fib(n - 2);
    }

    public static void main(String[] args) {
        fib(10);
    }
}
```

This milestone requires:

```text
class parser

constant pool

method parser

Code attribute

integer stack

local variables

branching

static method invocation

frame stack

return values
```

---

# 38. Objects

Milestone 2 adds:

```text
new
dup

getfield
putfield

getstatic
putstatic

invokespecial
invokevirtual
```

---

# 39. Heap

Use explicit simulated heap.

Initial design:

```text
Heap {
    objects
    nextReference
}
```

Object:

```text
HeapObject {
    classId
    fields
}
```

Reference:

```text
U32
```

---

# 40. Flat Heap Design

Preferred later optimization:

```text
ObjectTable

ID
ClassId
FieldOffset
FieldCount
Flags
```

plus:

```text
FieldTags[]
FieldValues[]
```

Example:

```text
Object ID 42

ObjectTable[42]:

class = Person
offset = 700
fields = 3
```

Fields:

```text
FieldTags[700..702]
FieldValues[700..702]
```

---

# 41. Allocation

`new`:

```text
resolve class

determine instance fields

allocate object

initialize fields to JVM defaults

push reference
```

Default values:

```text
int       = 0
float     = 0
reference = null
long      = 0
double    = 0
```

---

# 42. Fields

Class loader assigns:

```text
FieldId
```

and computes instance field layout.

Example:

```java
class Person {
    int age;
    Object parent;
}
```

becomes:

```text
field 0 → INT
field 1 → REFERENCE
```

---

# 43. Static Fields

Separate storage:

```text
StaticFields {
    tags
    values
}
```

indexed by:

```text
FieldId
```

---

# 44. Method Resolution

Method references contain:

```text
class
name
descriptor
```

Resolver returns:

```text
MethodId
```

Method resolution results should be cached.

---

# 45. Virtual Dispatch

For:

```text
invokevirtual
```

runtime:

```text
pop receiver

receiver
    ↓
heap lookup
    ↓
runtime class
    ↓
lookup method
    ↓
walk superclass chain
    ↓
MethodId
```

Cache:

```text
(RuntimeClassId, MethodReferenceId)
    ↓
ResolvedMethodId
```

---

# 46. Constructors

Java constructors use:

```text
invokespecial <init>
```

The VM treats them as ordinary instance methods with special resolution rules.

Object allocation and constructor invocation remain separate:

```text
new
dup
invokespecial <init>
```

---

# 47. Class Loader

V1:

```text
single directory
```

Lookup:

```text
com/example/Foo

→

./classes/com/example/Foo.class
```

Later support:

```text
multiple classpath entries
JARs
bootstrap classes
```

---

# 48. Loaded Class Model

```text
LoadedClass {
    id

    name

    superClass

    interfaces

    fields

    methods

    constantPool

    initializationState
}
```

Initialization states:

```text
Loaded
Initializing
Initialized
Failed
```

---

# 49. Class Initialization

When a class is first actively used:

```text
initialize superclass

initialize static fields

run <clinit>
```

V1 may initially skip full `<clinit>` support.

Milestone 3 should implement it.

---

# 50. Arrays

Required opcodes:

```text
newarray
anewarray

arraylength

iaload
iastore

faload
fastore

aaload
aastore
```

Later:

```text
laload
lastore
daload
dastore
baload
bastore
caload
castore
saload
sastore

multianewarray
```

---

# 51. Array Heap Representation

Heap object variant:

```text
HeapEntry =
    ObjectEntry
    ArrayEntry
```

Array:

```text
ArrayEntry {
    elementType
    length
    tags
    values
}
```

References to arrays use ordinary heap references.

---

# 52. Null Semantics

Reference:

```text
0
```

means null.

Operations requiring a non-null reference must produce:

```text
java/lang/NullPointerException
```

once exception support exists.

Before exceptions are implemented:

```text
VmError.NullReference
```

---

# 53. Java Runtime Strategy

Do not attempt to execute the actual OpenJDK library initially.

Implement selected Java methods as BendJVM intrinsics.

---

# 54. Intrinsics

Intrinsic lookup:

```text
class
method
descriptor
```

Example:

```text
java/lang/Object
<init>
()V
```

may be:

```text
no-op
```

Example:

```text
java/io/PrintStream
println
(I)V
```

maps to Bend:

```text
IO.print(...)
```

---

# 55. Initial Intrinsics

Required:

```text
java/lang/Object.<init>:()V

java/io/PrintStream.println:(I)V

java/io/PrintStream.println:(Ljava/lang/String;)V

java/lang/System.out
```

Potential:

```text
java/lang/System.currentTimeMillis

java/lang/Math.abs

java/lang/Math.min

java/lang/Math.max
```

---

# 56. System.out

The VM should create a synthetic:

```text
PrintStream
```

object during bootstrap.

Then initialize:

```text
System.out
```

to that reference.

Calling:

```java
System.out.println(42);
```

follows ordinary JVM semantics until:

```text
invokevirtual PrintStream.println
```

which resolves to an intrinsic.

---

# 57. Strings

Java strings must be represented as heap objects.

V1 simplified representation:

```text
JavaString {
    bytes
}
```

or:

```text
JavaString {
    chars
}
```

Do not use Bend String as the VM's internal Java String representation.

Preferred:

```text
Array<U32>
```

where each entry stores a UTF-16 code unit.

---

# 58. String Constants

Constant-pool:

```text
CONSTANT_String
```

should resolve to an interned Java String object.

Maintain:

```text
stringConstantId
    ↓
heapReference
```

cache.

---

# 59. String Interning

Optional initial string pool:

```text
Symbol/StringConstant
        ↓
JavaString reference
```

Identical string literals should reuse one heap object.

---

# 60. Exceptions

Milestone 4.

VM state:

```text
Throwing{exceptionRef}
```

When exception occurs:

```text
current method
    ↓
exception table
    ↓
matching handler?
```

If yes:

```text
clear operand stack

push exception

pc = handler
```

Otherwise:

```text
pop frame
```

and continue in caller.

---

# 61. Exception Table

Each method Code attribute contains entries:

```text
start_pc
end_pc
handler_pc
catch_type
```

Decoder converts PCs into decoded instruction indices.

---

# 62. Uncaught Exceptions

When all frames are exhausted:

```text
UncaughtException {
    exceptionRef
}
```

CLI prints:

```text
Exception in thread "main" ...
```

A simplified stack trace is acceptable initially.

---

# 63. Built-in Exceptions

Initially synthesize:

```text
java/lang/ArithmeticException

java/lang/NullPointerException

java/lang/ArrayIndexOutOfBoundsException

java/lang/ClassCastException

java/lang/NegativeArraySizeException

java/lang/OutOfMemoryError
```

---

# 64. Garbage Collection

Do not implement GC in the first milestone.

Initial heap:

```text
monotonically growing
```

Set maximum:

```text
--max-heap
```

When exhausted:

```text
OutOfMemoryError
```

---

# 65. Future Mark-and-Sweep GC

Roots:

```text
frame locals

operand stacks

static fields

runtime intern table

class loader roots
```

Algorithm:

```text
roots
  ↓
mark reachable
  ↓
sweep unreachable
```

Because the JVM heap is explicit Bend data, GC is entirely implemented in Bend.

---

# 66. Bytecode Verification

Verification is an important part of the project.

Initial verifier validates:

```text
valid opcode

valid instruction encoding

branch targets valid

constant pool references valid

locals indices valid

stack never underflows

stack never exceeds max_stack
```

Later:

```text
type-state verification

constructor rules

uninitialized object tracking

reference compatibility
```

---

# 67. Verification Pipeline

```text
.class
  ↓
parse
  ↓
decode
  ↓
verify structural validity
  ↓
verify stack behavior
  ↓
LoadedClass
```

Execution should normally require verified classes.

Debug option:

```text
--no-verify
```

may exist later.

---

# 68. Verification Stack Analysis

For each instruction:

```text
input stack height
output stack height
```

Example:

```text
IADD

requires: 2
produces: 1
delta: -1
```

Control-flow analysis propagates stack heights through the method.

Conflicting stack heights at the same instruction should reject the method.

---

# 69. Formal Bend Laws

`LAWS.bend` should focus on small, meaningful VM invariants.

---

# 70. Law: Stack Push/Pop Round Trip

```text
push(stack, x)
then
pop
```

returns:

```text
x
```

and restores the original stack.

---

# 71. Law: Stack Pointer Bounds

For valid stack operations:

```text
0 <= sp <= maxStack
```

---

# 72. Law: Local Access Bounds

Verifier-approved:

```text
ILOAD index
```

must satisfy:

```text
index < maxLocals
```

---

# 73. Law: Branch Target Safety

Every verifier-approved branch target must point to a valid decoded instruction.

---

# 74. Law: IADD Stack Effect

If the input stack contains:

```text
... a b
```

then executing IADD results in:

```text
... a+b
```

and reduces stack size by exactly one.

---

# 75. Law: ISTORE/ILOAD Round Trip

Given valid local index:

```text
ISTORE n
ILOAD n
```

returns the same JVM integer value.

---

# 76. Law: Object References

Every non-null heap reference returned by allocation must refer to a valid heap entry.

---

# 77. Law: Heap Isolation

Updating field:

```text
object A.field X
```

must not mutate fields belonging to object B.

---

# 78. Law: Frame Isolation

Updating locals in the active frame must not mutate caller locals.

---

# 79. Law: Method Return

Executing a method return must restore the caller frame and place the returned value on the caller operand stack exactly once.

---

# 80. Law: Fuel Termination

```text
run(fuel, vm)
```

must consume at most:

```text
fuel
```

instructions.

---

# 81. Law: Deterministic Step

For VM states without external effects:

```text
step(vm)
```

must always return the same next VM state.

---

# 82. Proof Boundary

Formal guarantees apply to Bend semantics.

Host effects remain trusted.

For example:

```text
IO.print
File.read_bytes
```

are outside pure execution laws.

---

# 83. Runtime Errors

Internal error type:

```text
VmError =
    InvalidClassFile
    InvalidMagic
    UnsupportedClassVersion

    InvalidConstantPool
    InvalidDescriptor

    InvalidOpcode
    UnsupportedOpcode

    InvalidBranchTarget

    StackUnderflow
    StackOverflow

    InvalidLocalIndex

    InvalidReference

    NullReference

    MissingClass
    MissingMethod
    MissingField

    OutOfMemory

    InvalidState
```

---

# 84. Unsupported Feature Errors

Unsupported bytecode should fail clearly.

Example:

```text
UnsupportedOpcode {
    opcode: DADD
    method: com/example/Main.foo
    pc: 23
}
```

Never silently skip unsupported instructions.

---

# 85. Debug Tracing

CLI option:

```bash
--trace
```

Output:

```text
[Main.main pc=0] iconst_1
stack: []

[Main.main pc=1] iconst_2
stack: [1]

[Main.main pc=2] iadd
stack: [1, 2]

[Main.main pc=3] istore_1
stack: [3]
```

---

# 86. Disassembler

Command:

```bash
bendjvm --disassemble Main.class
```

Output:

```text
Main.main([Ljava/lang/String;)V

0   iconst_1
1   iconst_2
2   iadd
3   istore_1
4   return
```

This should use the same decoder as execution.

---

# 87. Class Dump

Command:

```bash
bendjvm --dump-class Main.class
```

shows:

```text
version

constant pool

fields

methods

attributes
```

Useful while implementing the class parser.

---

# 88. CLI

Initial:

```bash
bend bendjvm/main.bend -- Main.class
```

Options:

```text
--trace

--disassemble

--dump-class

--fuel <n>

--max-heap <n>

--entry <method>

--classpath <path>
```

Future executable:

```bash
bend bendjvm/main.bend -o bendjvm
```

then:

```bash
./bendjvm Main.class
```

---

# 89. Entry Point

Default entry:

```text
public static void main(String[] args)
```

descriptor:

```text
([Ljava/lang/String;)V
```

The VM creates an empty String array for V1.

Later command arguments may populate it.

---

# 90. Testing Strategy

Testing must compare BendJVM against a real JVM whenever possible.

---

# 91. Golden Test Pipeline

For each Java fixture:

```text
Test.java
    │
    ▼
javac --release 8
    │
    ▼
Test.class
    │
    ├────────────────┐
    ▼                ▼
java Test         BendJVM
    │                │
    └───────┬────────┘
            ▼
       compare output
```

---

# 92. Initial Fixtures

```text
HelloInteger

Arithmetic

Branching

WhileLoop

ForLoop

StaticMethod

RecursiveMethod

MultipleArguments

ObjectCreation

Fields

VirtualMethod

IntArray

ObjectArray

StringConstant

Println

ExceptionCaught

ExceptionUncaught
```

---

# 93. Opcode Unit Tests

Each opcode should have isolated fixtures.

Example:

```text
iadd

input:
1
2

expected:
3
```

Also edge cases:

```text
2147483647 + 1
→ -2147483648
```

represented in U32 form.

---

# 94. Differential Random Testing

Generate small Java methods programmatically containing:

```text
integer constants
integer arithmetic
locals
branches
loops
static calls
```

Compile them with javac.

Compare:

```text
HotSpot result

vs

BendJVM result
```

This is critical for detecting subtle arithmetic and stack bugs.

---

# 95. Class Parser Tests

Use real `.class` fixtures with:

```text
different constant pools

multiple methods

interfaces

fields

attributes

long names

UTF-8 constants
```

Malformed class files should also be tested.

---

# 96. Fuzzing

Long-term:

```text
random byte arrays
    ↓
ClassFile.parse
```

Expected outcome:

```text
valid parsed class

or

clean parse error
```

Never:

```text
crash
infinite loop
out-of-bounds access
```

---

# 97. Performance Strategy

Correctness first.

Avoid premature optimization.

Initial interpreter may use:

```text
Array
List
Map
```

as appropriate.

Later profile:

```text
instruction decode

stack push/pop

frame creation

heap access

method lookup

constant pool resolution
```

---

# 98. Important Performance Rule

Do not perform repeated:

```text
String comparisons
```

inside instruction execution.

Resolve names into numeric IDs at load time.

---

# 99. Method Caches

Caches:

```text
MethodRefId
    ↓
ResolvedMethodId
```

Virtual cache:

```text
ClassId + MethodRefId
    ↓
ResolvedMethodId
```

Field cache:

```text
FieldRefId
    ↓
ResolvedFieldId
```

---

# 100. Decoding Cache

Every method's bytecode is decoded once.

Never:

```text
read opcode byte
decode operands
```

on every execution.

---

# 101. Class State

Classes progress:

```text
Unloaded
    ↓
Loaded
    ↓
Linked
    ↓
Initialized
```

V1 may combine:

```text
Loaded + Linked
```

to reduce complexity.

---

# 102. Native Boundary

Java bytecode does not directly call arbitrary Bend effects.

Instead:

```text
Java method
    ↓
Intrinsic registry
    ↓
known intrinsic?
```

If yes:

```text
Bend implementation
```

If no:

```text
normal JVM bytecode
```

---

# 103. Intrinsic Registry

Key:

```text
ClassId
MethodNameId
DescriptorId
```

Result:

```text
IntrinsicId
```

Examples:

```text
Object_init

PrintStream_println_int

PrintStream_println_string

System_currentTimeMillis
```

---

# 104. Security Model

BendJVM executes untrusted bytecode only after validation.

V1 does not promise sandbox-grade security.

However:

```text
Java code has no direct operating-system access
```

except through explicitly supported BendJVM intrinsics.

This naturally creates a capability boundary.

---

# 105. Potential Sandbox Mode

Future:

```bash
bendjvm \
  --no-files \
  --no-network \
  --max-heap 64mb \
  --fuel 10000000 \
  Main.class
```

Because JVM IO only exists through BendJVM intrinsics, capabilities can be controlled centrally.

---

# 106. Threading

No Java threads in V1.

Future simulated threads:

```text
JvmThread {
    id
    frames
    status
}
```

VM:

```text
VM {
    threads
    currentThread
    heap
}
```

Scheduler executes:

```text
N instructions
```

per thread.

This preserves one Bend-owned shared JVM state.

---

# 107. Thread States

Future:

```text
RUNNABLE
BLOCKED
WAITING
TIMED_WAITING
TERMINATED
```

---

# 108. Monitors

Future heap objects include:

```text
monitorOwner
monitorDepth
waiters
```

Required for:

```text
monitorenter
monitorexit
synchronized
wait
notify
```

---

# 109. JAR Support

Later:

```text
JAR
 ↓
ZIP
 ↓
class entries
```

This requires:

```text
ZIP central directory

DEFLATE
```

and is intentionally postponed.

---

# 110. Java Library Strategy

Do not target OpenJDK library compatibility early.

Instead build:

```text
MiniJRE
```

covering only required classes.

Initial:

```text
java/lang/Object

java/lang/String

java/lang/System

java/io/PrintStream

java/lang/Throwable

java/lang/Exception

java/lang/RuntimeException
```

---

# 111. MiniJRE Representation

Some classes may be:

```text
synthetic VM classes
```

rather than loaded from `.class` files.

Eventually, more of the Java runtime may itself be compiled Java bytecode.

---

# 112. Phase Plan

## Phase 0 — Binary Infrastructure

Implement:

```text
File.read_bytes integration

ByteReader

readU1
readU2
readU4

error handling
```

Success:

```text
read CAFEBABE
```

---

## Phase 1 — Class Parser

Implement:

```text
class header

constant pool

access flags

class references

methods

Code attribute
```

Success:

```bash
bendjvm --dump-class Main.class
```

---

## Phase 2 — Integer VM

Implement:

```text
frames

locals

operand stack

integer constants

integer arithmetic

branches

invokestatic

ireturn

return
```

Success:

```java
static int fib(int n)
```

runs correctly.

---

## Phase 3 — Objects

Implement:

```text
heap

new

dup

getfield

putfield

getstatic

putstatic

invokespecial

invokevirtual
```

Success:

```java
new Counter().increment();
```

---

## Phase 4 — Mini Java Runtime

Implement:

```text
Object

String

System

PrintStream

println
```

Success:

```java
System.out.println("Hello");
```

---

## Phase 5 — Arrays

Implement:

```text
newarray

anewarray

arraylength

iaload

iastore

aaload

aastore
```

---

## Phase 6 — Exceptions

Implement:

```text
athrow

exception table

stack unwinding

built-in exceptions
```

---

## Phase 7 — Verifier

Implement:

```text
CFG

stack-height verification

local bounds

branch validation

constant pool validation
```

---

## Phase 8 — Bend Proofs

Formalize:

```text
stack safety

local safety

branch safety

frame isolation

heap reference validity

run fuel termination
```

---

## Phase 9 — Long

Implement:

```text
JLong{hi, lo}

long operations
```

---

## Phase 10 — GC

Implement mark-and-sweep.

---

## Phase 11 — Interfaces

Add:

```text
invokeinterface

interface resolution
```

---

## Phase 12 — Class Initialization

Implement complete:

```text
<clinit>
```

semantics.

---

## Phase 13 — Threads

Implement simulated Java threads.

---

## Phase 14 — Modern Java Bytecode

Add:

```text
method handles

bootstrap methods

invokedynamic
```

---

# 113. Milestone Acceptance Criteria

## Milestone A

```text
parse valid Java 8 .class

print class metadata
```

---

## Milestone B

Execute:

```java
public class Main {
    static int add(int a, int b) {
        return a + b;
    }

    public static void main(String[] args) {
        add(20, 22);
    }
}
```

Expected internal return:

```text
42
```

---

## Milestone C

Execute:

```java
public class Main {
    static int fib(int n) {
        if (n <= 1) return n;
        return fib(n - 1) + fib(n - 2);
    }
}
```

---

## Milestone D

Execute:

```java
class Counter {

    int value;

    Counter(int value) {
        this.value = value;
    }

    int increment() {
        value++;
        return value;
    }
}
```

---

## Milestone E

Execute:

```java
public class Main {

    public static void main(String[] args) {
        System.out.println(42);
    }
}
```

Expected:

```text
42
```

---

# 114. Architectural Principles

## Bend Owns JVM State

All JVM state belongs to Bend.

Do not move:

```text
heap
frames
locals
operand stacks
```

into foreign C or JavaScript.

---

## Host Effects Are Minimal

Use Bend effects only for:

```text
reading .class files

printing

clock

future filesystem/network intrinsics
```

JVM semantics stay inside Bend.

---

## Decode Once

Class loading performs expensive parsing.

Execution uses compact decoded structures.

---

## Numeric IDs Internally

Use:

```text
ClassId
FieldId
MethodId
SymbolId
```

instead of names during execution.

---

## Reject Unsupported Semantics

Never approximate unsupported JVM instructions.

Return explicit errors.

---

## Correctness Before Performance

Interpreter behavior should match HotSpot before optimizing memory layout or instruction dispatch.

---

# 115. Definition of V1

BendJVM V1 is complete when it can execute Java 8 programs using:

```text
int

float

objects

instance fields

static fields

static methods

virtual methods

constructors

primitive arrays

reference arrays

strings

branches

loops

recursion

basic exceptions

System.out.println
```

without:

```text
long

double

threads

reflection

JNI

invokedynamic

JAR files
```

and when core interpreter invariants are protected by Bend laws.

---

# 116. Final Technical Direction

BendJVM should be designed as:

```text
                 Java bytecode
                       │
                       ▼
              verified class model
                       │
                       ▼
                decoded methods
                       │
                       ▼
                explicit JVM state
                       │
      ┌────────────────┼────────────────┐
      ▼                ▼                ▼
    frames            heap          loaded classes
      │                │                │
      └────────────────┼────────────────┘
                       ▼
                  Bend step()
                       │
                       ▼
                next JVM state
```

The central abstraction is not:

```text
execute Java using Bend functions
```

but:

> **Represent the JVM as explicit state and define a Bend state transition for each JVM instruction.**

That makes the project easier to reason about, easier to test against the JVM specification, and suitable for Bend's law/proof system.

The two most important functions should eventually be:

```text
verify(class) -> VerificationResult
```

and:

```text
step(vm) -> StepResult
```

Everything else exists to construct, validate, or inspect the state consumed by those two operations.

