import Base

# JVM words are raw U32 bits. IDs and decoded PCs are zero-based; reference 0 is null.
type Slot is Data:
  Slot{tag: U32, bits: U32}

type Constant is Data:
  Unused{}
  Utf{text: String}
  Number{tag: U32, bits: U32}
  Index{tag: U32, index: U32}
  PairIndex{tag: U32, first: U32, second: U32}

type Attribute is Data:
  Attribute{name: String, bytes: +List<U32>}

type Handler is Data:
  Handler{start: U32, end: U32, target: U32, catch: U32}

# op is the JVM opcode; a/b hold normalized operands, targets are decoded PCs.
# Linking replaces CP operands with global IDs; calls use a=method ID,
# b=name symbol ID, c=descriptor symbol ID. Virtual dispatch uses b/c.
type Instruction is Data:
  Instruction{op: U32, a: U32, b: U32, c: U32, offset: U32}

type Field is Data:
  Field{flags: U32, name: String, descriptor: String, constant: U32, attributes: +List<Attribute>}

type Method is Data:
  Method{flags: U32, name: String, descriptor: String, maxStack: U32, maxLocals: U32, code: +List<U32>, instructions: +List<Instruction>, handlers: +List<Handler>, attributes: +List<Attribute>}

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
  LoadedMethod{id: U32, owner: U32, name: U32, descriptor: U32, flags: U32, parameters: U32, resultTag: U32, maxStack: U32, maxLocals: U32, instructions: +List<Instruction>, handlers: +List<Handler>, intrinsic: U32}
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
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic} = value
  id
def loaded_method_owner(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic} = value
  owner

def loaded_method_name(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic} = value
  name

def loaded_method_descriptor(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic} = value
  descriptor
def loaded_method_flags(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic} = value
  flags

def loaded_method_intrinsic(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic} = value
  intrinsic

def loaded_method_result(value: LoadedMethod) -> U32:
  LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic} = value
  resultTag


# state: 0 loaded, 1 initializing, 2 initialized, 3 failed; parent=0xffffffff for Object.
type LoadedClass is Data:
  LoadedClass{id: U32, name: U32, parent: U32, interfaces: +List<U32>, fields: +List<Binding>, methods: +List<U32>, initializer: U32, state: U32}
def loaded_class_id(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state} = value
  id

def loaded_class_name(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state} = value
  name

def loaded_class_parent(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state} = value
  parent

def loaded_class_initializer(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state} = value
  initializer
def loaded_class_interfaces(value: LoadedClass) -> +List<U32>:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state} = value
  interfaces

def loaded_class_state(value: LoadedClass) -> U32:
  LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state} = value
  state


# kind: 0 object, 1 primitive array, 2 reference array, 3 UTF-16 string, 4 byte stream,
# 5 ArrayList, 6 HashMap, 7 StringBuilder.
# element is a primitive tag, component class, stream position, or collection size.
type HeapEntry is Data:
  HeapEntry{class: U32, kind: U32, element: U32, fields: +List<Binding>, values: +List<Slot>, chars: +List<U32>}

type Resource is Data:
  Resource{name: String, bytes: +List<U32>}

# Host effects are opaque OS requests. Bend keeps Java-visible state only.
type Effect is Data:
  Idle{}
  OpenFile{path: String, mode: U32, receiver: U32}
  StatPath{path: String, op: U32}
  ReadBytes{handle: U32, count: U32, timeout: U32}
  WriteBytes{handle: U32, bytes: +List<U32>}
  CloseHandle{handle: U32}
  ConnectTcp{host: String, port: U32, timeout: U32, receiver: U32}
  BindTcp{port: U32, receiver: U32}
  AcceptTcp{handle: U32, timeout: U32, receiver: U32}

# Continuation of an intrinsic after a virtual Java callback returns.
type Cont is Data:
  NeedHash{map: U32, key: U32, op: U32, extra: Slot}
  NeedEq{map: U32, key: U32, hash: U32, index: U32, op: U32, extra: Slot}
  NeedToString{op: U32, extra: U32}
  NeedEquals{op: U32, left: U32, right: U32}
  NeedListEq{list: U32, query: U32, index: U32, op: U32}

type Host is Data:
  Host{effect: Effect, cwd: String, caps: U32, maxPayload: U32, cont: +List<Cont>}

def idle_host() -> Host:
  Host{Idle{}, ".", 3, 16777216, Nil{}}

# pc is the next/current instruction. invokePc retains a caller's throwing location.
# initializing=0xffffffff for ordinary calls; otherwise class initialized on return.
# status: 0 run, 1 done, 3 fuel, 4 fail, 5 host, 6 java throw.
type Frame is Data:
  Frame{method: U32, pc: U32, invokePc: U32, locals: +List<Slot>, stack: +List<Slot>, initializing: U32}
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
