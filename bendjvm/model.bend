import Base

# JVM words are raw U32 bits. IDs and decoded PCs are zero-based; reference 0 is null.
type Slot is Data:
  Slot{tag: U32, bits: U32}
  Wide{tag: U32, high: U32, low: U32}
  Unusable{}

def slot_tag(value: Slot) -> U32:
  match value:
    case Slot{tag, bits}: tag
    case Wide{tag, high, low}: tag
    case Unusable{}: 0

def slot_width(value: Slot) -> U32:
  match value:
    case Slot{+tag, bits}: Bool.pick(U32, U32.is_ge(tag, 1) && U32.is_le(tag, 3), 1, 0)
    case Wide{+tag, high, low}: Bool.pick(U32, U32.is_ge(tag, 4) && U32.is_le(tag, 5), 2, 0)
    case Unusable{}: 0

def slot_bits(value: Slot) -> U32:
  match value:
    case Slot{tag, bits}: bits
    case Wide{tag, high, low}: low
    case Unusable{}: 0

def default_slot(tag: U32) -> Slot:
  match tag:
    case 4: Wide{4, 0, 0}
    case 5: Wide{5, 0, 0}
    case _: Slot{tag, 0}

type Constant is Data:
  Unused{}
  Utf{text: String}
  Number{tag: U32, bits: U32}
  Index{tag: U32, index: U32}
  PairIndex{tag: U32, first: U32, second: U32}

type BootstrapArgument is Data:
  BootstrapArgument{argumentIndex: U32, constantIndex: U32, tag: U32, value: Constant}

type BootstrapMethod is Data:
  BootstrapMethod{index: U32, methodRef: U32, handleKind: U32, handleReference: U32, arguments: +List<BootstrapArgument>}

type BootstrapMethods is Data:
  BootstrapMethods{methods: +List<BootstrapMethod>}

type DynamicSite is Data:
  # state: 0 linking, 1 linked, 2 failed; cached references are zero when absent.
  DynamicSite{method: U32, pc: U32, owner: U32, constant: U32, state: U32, callsite: U32, failure: U32}


# Structured class-file metadata. Constant-pool references remain symbolic so
# annotation Class and enum values can resolve lazily at materialization time.
type AnnotationValue is Data:
  AnnotationConst{tag: U32, index: U32}
  AnnotationEnum{typeIndex: U32, nameIndex: U32}
  AnnotationClass{descriptorIndex: U32}
  AnnotationNested{typeIndex: U32, elements: +List<AnnotationValue>}
  AnnotationElementValue{nameIndex: U32, value: AnnotationValue}
  AnnotationArray{values: +List<AnnotationValue>}

type AnnotationElement is Data:
  AnnotationElement{nameIndex: U32, value: AnnotationValue}

type Annotation is Data:
  Annotation{typeIndex: U32, elements: +List<AnnotationElement>}

type TypeAnnotation is Data:
  TypeAnnotation{targetType: U32, targetInfo: +List<U32>, path: +List<U32>, annotation: Annotation}

type AnnotationMetadata is Data:
  AnnotationMetadata{flags: U32, exceptions: +List<U32>, annotations: +List<Annotation>, parameterAnnotations: +List<+List<Annotation>>, typeAnnotations: +List<TypeAnnotation>, defaultValue: Maybe<&2, AnnotationValue>, invisibleAnnotations: +List<Annotation>, invisibleParameterAnnotations: +List<+List<Annotation>>, invisibleTypeAnnotations: +List<TypeAnnotation>}

def empty_annotation_metadata() -> AnnotationMetadata:
  AnnotationMetadata{0, Nil{}, Nil{}, Nil{}, Nil{}, None{}, Nil{}, Nil{}, Nil{}}
type Attribute is Data:
  Attribute{name: String, bytes: +List<U32>}
  ValidatedAnnotations{metadata: AnnotationMetadata}

# One InnerClasses entry (JVMS 4.7.6); empty strings stand for index 0.
type InnerClass is Data:
  InnerClass{inner: String, outer: String, name: String, flags: U32}

# InnerClasses plus EnclosingMethod (JVMS 4.7.7); `method` is empty when the
# class is enclosed by an initializer rather than a method.
type Nesting is Data:
  Nesting{inner: +List<InnerClass>, enclosingClass: String, method: String, descriptor: String}

def empty_nesting() -> Nesting:
  Nesting{Nil{}, "", "", ""}

type ClassMetadata is Data:
  ClassMetadata{owner: U32, flags: U32, metadata: AnnotationMetadata, visibleAnnotations: +List<String>, pool: +List<Constant>, signature: String, nesting: Nesting, source: String}

type FieldMetadata is Data:
  FieldMetadata{owner: U32, field: U32, metadata: AnnotationMetadata, signature: String}

# `lines` flattens a method's LineNumberTable: (start byte offset, line) pairs.
# One MethodParameters entry: `name` is empty when the attribute records no name.
type MethodParameter is Data:
  MethodParameter{name: String, flags: U32}

type MethodMetadata is Data:
  MethodMetadata{owner: U32, method: U32, metadata: AnnotationMetadata, signature: String, parameters: +List<MethodParameter>, lines: +List<U32>}

type Metadata is Data:
  Metadata{classes: +List<ClassMetadata>, fields: +List<FieldMetadata>, methods: +List<MethodMetadata>}

def empty_metadata() -> Metadata:
  Metadata{Nil{}, Nil{}, Nil{}}


type Handler is Data:
  Handler{start: U32, end: U32, target: U32, catch: U32}

# op is the JVM opcode; a/b hold normalized operands, targets are decoded PCs.
# Linking replaces CP operands with global IDs; calls use a=method ID,
# b=name symbol ID, c=descriptor symbol ID. Virtual dispatch uses b/c.
type Instruction is Data:
  Instruction{op: U32, a: U32, b: U32, c: U32, offset: U32}

type SwitchTable is Data:
  SwitchTable{kind: U32, low: U32, high: U32, keys: +List<U32>, targets: +List<U32>}

type Field is Data:
  Field{flags: U32, name: String, descriptor: String, constant: U32, attributes: +List<Attribute>}

type Method is Data:
  Method{flags: U32, name: String, descriptor: String, maxStack: U32, maxLocals: U32, code: +List<U32>, instructions: +List<Instruction>, handlers: +List<Handler>, attributes: +List<Attribute>, switches: +List<SwitchTable>}

type ClassFile is Data:
  ClassFile{minor: U32, major: U32, flags: U32, name: String, parent: String, interfaces: +List<String>, pool: +List<Constant>, fields: +List<Field>, methods: +List<Method>, attributes: +List<Attribute>}

type JvmType is Data:
  Primitive{tag: U32}
  ObjectType{name: String}
  ArrayType{element: JvmType}

type Descriptor is Data:
  Descriptor{parameters: +List<JvmType>, result: JvmType}

type Binding is Data:
  Binding{id: U32, value: Slot}

type LoadedField is Data:
  LoadedField{id: U32, owner: U32, name: U32, descriptor: U32, flags: U32, tag: U32}

type LoadedMethod is Data:
  LoadedMethod{id: U32, owner: U32, name: U32, descriptor: U32, flags: U32, parameters: U32, resultTag: U32, maxStack: U32, maxLocals: U32, instructions: +List<Instruction>, handlers: +List<Handler>, intrinsic: U32, switches: +List<SwitchTable>}
def loaded_field_owner(value: LoadedField) -> U32:
  LoadedField{id, owner, name, descriptor, flags, tag} = value
  owner

def loaded_field_name(value: LoadedField) -> U32:
  LoadedField{id, owner, name, descriptor, flags, tag} = value
  name

def loaded_field_descriptor(value: LoadedField) -> U32:
  LoadedField{id, owner, name, descriptor, flags, tag} = value
  descriptor

def loaded_field_id(value: LoadedField) -> U32:
  LoadedField{id, owner, name, descriptor, flags, tag} = value
  id

def loaded_field_tag(value: LoadedField) -> U32:
  LoadedField{id, owner, name, descriptor, flags, tag} = value
  tag

def loaded_field_flags(value: LoadedField) -> U32:
  LoadedField{id, owner, name, descriptor, flags, tag} = value
  flags

def loaded_method_id(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches} = value
  id
def loaded_method_owner(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches} = value
  owner

def loaded_method_name(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches} = value
  name

def loaded_method_descriptor(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches} = value
  descriptor
def loaded_method_flags(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches} = value
  flags

def loaded_method_intrinsic(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches} = value
  intrinsic

def loaded_method_result(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches} = value
  resultTag


# state: 0 loaded, 1 initializing, 2 initialized, 3 failed; parent=0xffffffff for Object.
type LoadedClass is Data:
  LoadedClass{id: U32, name: U32, parent: U32, interfaces: +List<U32>, fields: +List<Binding>, methods: +List<U32>, initializer: U32, state: U32, bootstrapMethods: +List<BootstrapMethod>}
def loaded_class_id(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods} = value
  id

def loaded_class_name(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods} = value
  name

def loaded_class_parent(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods} = value
  parent

def loaded_class_initializer(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods} = value
  initializer
def loaded_class_interfaces(value: LoadedClass) -> +List<U32>:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods} = value
  interfaces

def loaded_class_bootstrap_methods(value: LoadedClass) -> +List<BootstrapMethod>:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods} = value
  bootstrapMethods

def loaded_class_state(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods} = value
  state


# kind: 0 object, 1 primitive array, 2 reference array, 3 UTF-16 string, 4 byte stream,
# 5 ArrayList, 6 HashMap, 7 StringBuilder.
# element is a primitive tag, component class, stream position, or collection size.
type HeapEntry is Data:
  HeapEntry{class: U32, kind: U32, element: U32, fields: +List<Binding>, values: +List<Slot>, chars: +List<U32>}

type Resource is Data:
  Resource{name: String, origin: String}

# Host effects are opaque OS requests. Bend keeps Java-visible state only.
type Effect is Data:
  Idle{}
  ReflectCall{}
  ReflectConstructor{reference: U32}
  ProxyCall{descriptor: String, method: U32, owners: +List<U32>}
  HandleAdapter{targetDescriptor: U32, requestedDescriptor: U32}
  HandleConstructor{reference: U32}
  RuntimeClass{name: String, initialize: Bool, loader: U32}
  ReadResource{name: String, origin: String}
  OpenFile{path: String, mode: U32, receiver: U32}
  StatPath{path: String, op: U32}
  ReadBytes{handle: U32, count: U32, timeout: U32}
  WriteBytes{handle: U32, bytes: +List<U32>}
  CloseHandle{handle: U32}
  # AccessController.doPrivileged(PrivilegedExceptionAction): wraps checked exceptions.
  PrivilegedCall{}
  # File.listFiles/list: the host lists `path`; results are children of `parent`.
  ListDirectory{path: String, parent: String, files: Bool}
  # ZipFile/JarFile: the host lists the archive's entries into `receiver`;
  # op 0 finishes a constructor, 1 returns the JarFile, 2 the connection's entry.
  ListArchive{path: String, receiver: U32, op: U32, connection: U32, entry: String}
  # The bytes of a file (empty `entry`) or of an archive entry, as an InputStream.
  ReadPathBytes{path: String, entry: String}
  # A ClassNotFoundException escaping the callee resumes its callback with null.
  LoaderCatch{}
  # Loading supertype `name` for defineClass: ClassNotFoundException becomes
  # NoClassDefFoundError.
  LoaderSuper{name: String}
  # A top-level ObjectOutputStream.writeObject callback: an IOException resumes
  # the writer, which records it in the stream (TC_EXCEPTION) and rethrows.
  SerialCatch{}
  # A thread parked inside the VM (sleep, join, wait, yield); never sent to the host.
  Park{}
  # sun.nio.ch.HostIO.call: host operation `op` on `handle`; the reply bytes go
  # back into array[offset, offset+length).
  # A plugin native call (java/natives.bend): flattened arguments, the arrays to
  # copy back, and the monitor a synchronized native holds until it returns.
  NativeCall{method: U32, owner: String, name: String, descriptor: String, isStatic: Bool, words: +List<U32>, arrays: +List<U32>, lock: U32}
  # System.load(absolute path) / System.loadLibrary(logical name).
  LoadLibrary{name: String, absolute: Bool}
  HostIO{op: U32, handle: U32, arg: U32, data: +List<U32>, array: U32, offset: U32, length: U32}

# A piece of rendered text: literal UTF-16 units, or a reference whose
# toString() result is spliced in.
type TextItem is Data:
  TextUnits{units: +List<U32>}
  TextCall{reference: U32}
  # Rendering stopped: throw this exception instead of producing text.
  TextThrow{reference: U32}

# A serializable field (plan 03, C10): its type code, name, type string for
# objects and arrays, and the binding that holds its value.
type SerialField is Data:
  SerialField{code: U32, name: String, signature: String, slot: U32}

# One step of an ObjectOutputStream (W*) or ObjectInputStream (R*) task machine.
type SerialTask is Data:
  WMode{block: Bool}
  WContext{object: U32, class: U32, put: U32}
  WEndCustom{}
  WObject{value: U32}
  WReplaced{original: U32, class: U32}
  WData{object: U32, classes: +List<U32>}
  WFields{object: U32, fields: +List<SerialField>}
  WValues{values: +List<Slot>, code: U32}
  WSend{}
  WTarget{name: String, descriptor: String}
  WUnshared{value: U32}
  WExternal{object: U32}
  # A class descriptor, then what follows a descriptor in each writeObject0 case.
  WDesc{class: U32}
  WAnnotate{class: U32, proxy: Bool}
  WClassBody{object: U32}
  WArrayBody{object: U32}
  WEnumBody{object: U32}
  WInstance{object: U32, class: U32}
  # replaceObject returned; `original` was the object before replacement.
  WHooked{original: U32}
  WSlots{fields: +List<SerialField>, values: +List<Slot>}
  # writeFatalException: an IOException a callback threw at depth 0.
  WCaught{exception: U32}
  WClear{}
  WThrow{exception: U32}
  RMode{block: Bool}
  RRead{}
  RStore{object: U32, slot: U32, signature: String}
  RElement{array: U32, index: U32}
  RFields{object: U32, fields: +List<SerialField>}
  RSkipCustom{}
  RResolve{object: U32, handle: U32}
  RResolved{handle: U32}
  RPush{value: U32}
  RContext{object: U32, class: U32}
  RVoid{}
  # One class's data in an object (mode 0: none in the stream, 1: into the
  # local class, 2: a stream class the object lacks, read and dropped).
  RSlot{object: U32, class: U32, mode: U32}
  RExternal{object: U32, block: Bool}
  RDrop{}
  RLeave{}
  # A Java InputStream returned bytes into `array` (0: a single read()).
  RFill{array: U32}
  # Class.forName through `loader` returned the class named `name`.
  RLoaded{loader: U32, name: String}
  RRetry{id: U32, args: +List<Slot>}
  # readClassDesc: a descriptor's class id is pushed on the values.
  RDesc{}
  RDescRead{handle: U32}
  RDescResolved{handle: U32, desc: U32}
  RDescFinish{handle: U32, desc: U32, class: U32}
  RProxyResolved{handle: U32}
  RProxyFinish{handle: U32, class: U32}
  # The readObject0 case that follows its descriptor (the class id on top).
  ROrdinary{}
  RArray{}
  REnum{}
  RClassObject{}
  RDescObject{}
  RCheckResolve{handle: U32}
  RValidate{}
  RAbort{}

# Continuation of an intrinsic after a virtual Java callback returns.
type Cont is Data:
  NeedHash{map: U32, key: U32, op: U32, extra: Slot}
  NeedEq{map: U32, key: U32, hash: U32, index: U32, op: U32, extra: Slot}
  NeedThrowableMessage{receiver: U32, cause: U32}
  NeedToString{op: U32, extra: U32}
  NeedEquals{op: U32, left: U32, right: U32}
  NeedListEq{list: U32, query: U32, index: U32, op: U32}
  # Marks the frame depth of a Java callback whose result resumes the Need* below it.
  HostCallback{depth: U32}
  CallBoundary{depth: U32, effect: Effect, descriptor: U32}
  # Re-run an intrinsic once the <clinit> it requested returns (JVMS 5.5).
  NeedIntrinsicRetry{kind: U32, args: +List<Slot>}
  # Class.forName: keep initializing `target`, then return its mirror.
  NeedClassMirror{target: U32}
  # Concatenate `items` after a Java toString() call returns (see library.text_join).
  NeedTextJoin{acc: +List<U32>, items: +List<TextItem>}
  # ClassLoader.loadClass: the parent's answer (null after ClassNotFoundException).
  NeedLoaderParent{loader: U32, name: U32}
  # defineClass: the defining loader resolved `job`'s current name.
  NeedDefine{job: DefineJob}
  # Class.forName with a user loader: initialize the loaded class if asked.
  NeedForName{initialize: Bool}
  # ClassLoader.getResource: the parent's URL, else findResource.
  NeedResourceParent{loader: U32, name: U32}
  # ClassLoader.getResourceAsStream: open the URL getResource returned.
  NeedResourceStream{}
  # ObjectOutputStream: a writeReplace/writeObject/stream callback returned; run `tasks`.
  NeedSerialWrite{stream: U32, tasks: +List<SerialTask>}
  # ObjectInputStream: a readObject/readResolve/constructor callback returned.
  NeedSerialRead{stream: U32, tasks: +List<SerialTask>, values: +List<Slot>}
  # InputStream.read(byte[], int, int): read() returned; `got` bytes so far.
  NeedBulkRead{stream: U32, array: U32, offset: U32, length: U32, got: U32}
  HandleInvocation{depth: U32, kind: U32, owner: U32, name: U32, descriptor: U32, method: U32, entry: HeapEntry, args: +List<Slot>, target: String, requested: String, max: U32, previousEffect: Effect}
  HandleInitReturn{depth: U32, effect: Effect}
  DynamicBootstrap{depth: U32, method: U32, pc: U32, owner: U32, constant: U32, args: +List<Slot>}
# User class loaders (plan 03, C6). Each loader object owns a namespace number;
# `aliases` record what a namespace's names resolve to (classes it defined or
# initiated), `defined` each user-defined class's defining loader, `pending` the
# class files whose verification waits for linking (first initialization), and
# `defining` the names a namespace is defining right now (cycles resolve to them).
type Loaders is Data:
  Loaders{next: U32, aliases: +List<LoaderAlias>, defined: +List<DefinedClass>, pending: +List<PendingVerify>, defining: +List<DefiningName>}

type LoaderAlias is Data:
  LoaderAlias{namespace: U32, name: String, target: U32}

type DefinedClass is Data:
  DefinedClass{class: U32, loader: U32}

type PendingVerify is Data:
  PendingVerify{class: U32, file: ClassFile}

type DefiningName is Data:
  DefiningName{namespace: U32, name: String, internal: String}

type NameMap is Data:
  NameMap{name: String, internal: String}

# defineClass in progress: the names still to resolve through `loader`
# (supertypes first), the resolved names, and the name being resolved.
type DefineJob is Data:
  DefineJob{loader: U32, namespace: U32, file: ClassFile, actual: String, internal: String, supers: +List<String>, others: +List<String>, mapping: +List<NameMap>, current: String, super: Bool}

def empty_loaders() -> Loaders:
  Loaders{1, Nil{}, Nil{}, Nil{}, Nil{}}

# Java threads (plan 05). Clock values are unsigned 64-bit nanoseconds.
type Clock is Data:
  Clock{high: U32, low: U32}

# Why a thread is not running. Status 7 threads re-execute their current
# instruction once woken (monitor entry, another thread's class initializer);
# status 8 threads resume like a completed host effect (void, or a thrown
# InterruptedException). Status 5 threads wait for host operation `op`.
type Wait is Data:
  NoWait{}
  HostOp{op: U32}
  EnterMonitor{object: U32}
  InitWait{class: U32}
  # Status 8 form of InitWait for an intrinsic: it re-runs once woken.
  InitPark{class: U32}
  # Status 8: a method handle's initialization chain waits for another thread's
  # <clinit>, then re-walks from its HandleInvocation continuation.
  HandleInitWait{class: U32}
  # Status 8: an intrinsic (a synchronized native) waits for a free monitor, then re-runs.
  MonitorPark{object: U32}
  Sleeping{}
  Joining{target: U32}
  Waiting{object: U32, depth: U32}
  Reacquire{object: U32, depth: U32, interrupted: Bool}
  Yielding{}

# One Java thread. `object` is its java.lang.Thread (0 until the main thread's
# object exists). The execution fields (frames..cont) are a saved copy: while a
# thread runs they live in the VM and Host, and the copy here is stale.
type ThreadState is Data:
  ThreadState{id: U32, object: U32, daemon: Bool, interrupted: Bool, wait: Wait, timed: Bool, deadline: Clock, seq: U32, priority: U32, frames: +List<Frame>, status: U32, exception: U32, result: Slot, effect: Effect, cont: +List<Cont>}

# An owned monitor: `depth` counts reentrant acquisitions by `owner`.
type Monitor is Data:
  Monitor{object: U32, owner: U32, depth: U32}

# The thread running a class's <clinit> (JVMS 5.5 step 2).
type InitOwner is Data:
  InitOwner{class: U32, thread: U32}

# Shared scheduler state. `threads` is ordered by id; `fuel` is the global
# instruction budget left; `left` is the budget a slice left unused;
# `mainError` is the report of an exception that ended main ("" when none);
# `mainHandler` is 1 while Thread.mainUncaught runs for it and 2 once a Java
# UncaughtExceptionHandler took it (the run still exits with status 1);
# `quantum` is how many instructions a thread runs before the next one does.
type Sched is Data:
  Sched{current: U32, nextThread: U32, nextOp: U32, nextSeq: U32, threads: +List<ThreadState>, monitors: +List<Monitor>, inits: +List<InitOwner>, now: Clock, wall: Clock, fuel: Nat, left: Nat, mainError: String, mainHandler: U32, quantum: Nat}

def empty_sched() -> Sched:
  Sched{0, 1, 1, 1, Nil{}, Nil{}, Nil{}, Clock{0, 0}, Clock{0, 0}, 0n, 0n, "", 0, 1000n}

type Host is Data:
  Host{effect: Effect, cwd: String, caps: U32, maxPayload: U32, cont: +List<Cont>, metadata: Metadata, dynamicSites: +List<DynamicSite>, loaders: Loaders, sched: Sched, errors: +List<String>}

def idle_host() -> Host:
  Host{Idle{}, ".", 3, 16777216, Nil{}, empty_metadata(), Nil{}, empty_loaders(), empty_sched(), Nil{}}

# pc is the next/current instruction. invokePc retains a caller's throwing location.
# initializing=0xffffffff for ordinary calls; otherwise class initialized on return.
# monitor: the object a synchronized method locked on entry (0 before entry or
# for other methods), released when the frame returns or unwinds.
# status: 0 run, 1 done, 3 fuel, 4 fail, 5 host, 6 java throw, 7 blocked (retry
# the instruction), 8 parked (resume like a host effect), 9 uncaught exception.
type Frame is Data:
  Frame{method: U32, pc: U32, invokePc: U32, locals: +List<Slot>, stack: +List<Slot>, initializing: U32, monitor: U32}
# resources are ordered host-provided classpath records; lookup uses the first match.
type VM is Data:
  VM{classes: +List<LoadedClass>, methods: +List<LoadedMethod>, fields: +List<LoadedField>, symbols: +List<String>, heap: +List<HeapEntry>, statics: +List<Binding>, resources: +List<Resource>, frames: +List<Frame>, status: U32, exception: U32, result: Slot, output: +List<String>, error: String, maxHeap: U32, steps: Nat, host: Host}


# Result uses messages carrying the stable VmError category plus location detail.
def error(-A: Data, text: String) -> Result<&2, &2, String, A>:
  Fail{text}


def nth_nat(-A: Data, xs: +List<A>, n: Nat) -> Maybe<&2, A>:
  match xs n:
    case Nil{} _:
      None{}
    case Con{h, t} 0n:
      Some{h}
    case Con{h, t} 1n+p:
      nth_nat(A, t, p)

def nth(-A: Data, xs: +List<A>, index: U32) -> Maybe<&2, A>:
  nth_nat(A, xs, U32.to_nat(index))
def length(-A: Data, xs: +List<A>) -> U32:
  match xs:
    case Nil{}:
      0
    case Con{h, t}:
      (1 + length(A, t) : U32)

def reverse_acc(-A: Data, xs: +List<A>, acc: +List<A>) -> +List<A>:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      reverse_acc(A, t, Con{h, acc})

def reverse(-A: Data, xs: +List<A>) -> +List<A>:
  reverse_acc(A, xs, Nil{})

def append(-A: Data, xs: +List<A>, ys: +List<A>) -> +List<A>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      Con{h, append(A, t, ys)}

def replace(-A: Data, xs: +List<A>, n: Nat, value: A) -> +List<A>:
  match xs n:
    case Nil{} _:
      Nil{}
    case Con{h, t} 0n:
      Con{value, t}
    case Con{h, t} 1n+p:
      Con{h, replace(A, t, p, value)}

def zeros(n: Nat) -> +List<Slot>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{Slot{0, 0}, zeros(p)}

def take(-A: Data, xs: +List<A>, n: Nat) -> +List<A>:
  match xs n:
    case Nil{} _:
      Nil{}
    case _ 0n:
      Nil{}
    case Con{h, t} 1n+p:
      Con{h, take(A, t, p)}

def drop(-A: Data, xs: +List<A>, n: Nat) -> +List<A>:
  match xs n:
    case Nil{} _:
      Nil{}
    case rest 0n:
      rest
    case Con{h, t} 1n+p:
      drop(A, t, p)
