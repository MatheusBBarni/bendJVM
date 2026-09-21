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

# kind: 0 object, 1 primitive array, 2 reference array, 3 UTF-16 string, 4 InputStream.
# element is a primitive tag, a reference-array component class ID, or stream position.
type HeapEntry is Data:
  HeapEntry{class: U32, kind: U32, element: U32, fields: +List<Binding>, values: +List<Slot>, chars: +List<U32>}

type Resource is Data:
  Resource{name: String, bytes: +List<U32>}


# pc is the next/current instruction. invokePc retains a caller's throwing location.
# initializing=0xffffffff for ordinary calls; otherwise class initialized on return.
type Frame is Data:
  Frame{method: U32, pc: U32, invokePc: U32, locals: +List<Slot>, stack: +List<Slot>, initializing: U32}
# resources are ordered host-provided classpath records; lookup uses the first match.
type VM is Data:
  VM{classes: +List<LoadedClass>, methods: +List<LoadedMethod>, fields: +List<LoadedField>, symbols: +List<String>, heap: +List<HeapEntry>, statics: +List<Binding>, resources: +List<Resource>, frames: +List<Frame>, status: U32, exception: U32, result: Slot, output: +List<String>, error: String, maxHeap: U32, steps: Nat}


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
