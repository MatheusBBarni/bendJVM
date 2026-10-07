import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ../classfile/constant_pool.bend as CP
import ./outcome.bend as O

type Value is Data:
  Value{vm: M.VM, slot: M.Slot}
type Values is Data:
  Values{vm: M.VM, slots: +List<M.Slot>}
type Bindings is Data:
  Bindings{vm: M.VM, fields: +List<M.Binding>}

def bits(slot: M.Slot) -> U32:
  M.Slot{tag, value} = slot
  value

def tag(slot: M.Slot) -> U32:
  M.Slot{kind, value} = slot
  kind

def fields(entry: M.HeapEntry) -> +List<M.Binding>:
  M.HeapEntry{class, kind, element, bindings, values, chars} = entry
  bindings

def values(entry: M.HeapEntry) -> +List<M.Slot>:
  M.HeapEntry{class, kind, element, bindings, slots, chars} = entry
  slots

def kind(entry: M.HeapEntry) -> U32:
  M.HeapEntry{class, k, element, bindings, slots, chars} = entry
  k

def element(entry: M.HeapEntry) -> U32:
  M.HeapEntry{class, k, e, bindings, slots, chars} = entry
  e

def chars(entry: M.HeapEntry) -> +List<U32>:
  M.HeapEntry{class, k, e, bindings, slots, text} = entry
  text

def units(text: String) -> +List<U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{head, rest}: Con{Char.to_u32(head), units(rest)}

def text(chars: +List<U32>) -> String:
  match chars:
    case Nil{}: ""
    case Con{head, rest}: Char.show(Chr{head}) ++ text(rest)

def id(+vm: M.VM, name: String) -> U32:
  H.named_class(S.classes(vm), S.symbols(vm), name)

def trim_class(chars: +List<Char>, acc: +List<Char>) -> String:
  match chars:
    case Nil{}: String.from_list(M.reverse(Char, acc))
    case Con{Chr{59}, Nil{}}: String.from_list(M.reverse(Char, acc))
    case Con{head, rest}: trim_class(rest, Con{head, acc})

def class_name(descriptor: String) -> String:
  match descriptor:
    case "I": "int"
    case "Z": "boolean"
    case "B": "byte"
    case "S": "short"
    case "C": "char"
    case "F": "float"
    case "J": "long"
    case "D": "double"
    case "V": "void"
    case SCon{Chr{76}, rest}: trim_class(String.to_list(rest), Nil{})
    case other: other

def result_descriptor(chars: +List<Char>) -> String:
  match chars:
    case Nil{}: ""
    case Con{Chr{41}, rest}: String.from_list(rest)
    case Con{head, rest}: result_descriptor(rest)

def descriptor(+vm: M.VM, method: M.LoadedMethod) -> String:
  result_descriptor(String.to_list(Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))))

def method_find(methods: +List<M.LoadedMethod>, +owner: U32, +name: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), owner) && String.eq(Sy.text(symbols, M.loaded_method_name(method)), name), Some{method}, method_find(rest, owner, name, symbols))

def member_cons(found: Maybe<&2, M.LoadedMethod>, +rest: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match found:
    case Some{method}: Con{method, rest}
    case None{}: rest

def member_methods(methods: +List<M.LoadedMethod>, +owner: U32, +symbols: +List<String>) -> +List<M.LoadedMethod>:
  match methods:
    case Nil{}: Nil{}
    case Con{+method, +rest}:
      +name = Sy.text(symbols, M.loaded_method_name(method))
      +ordinary = Bool.not(String.eq(name, "<init>")) && Bool.not(String.eq(name, "<clinit>")) && U32.is_eq(U32.and(M.loaded_method_flags(method), 8), 0)
      member_cons(Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), owner) && ordinary, Some{method}, None{}), member_methods(rest, owner, symbols))

def allocated(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{vm, reference}}: Done{Value{vm, M.Slot{3, reference}}}

# Kind 11 nodes retain symbolic values without resolving Class or enum types.
# Tag 99 exists only in this module's result slot, never on a Java operand stack.
def node(+vm: M.VM, tag: U32, +slots: +List<M.Slot>, name: String) -> Result<&2, &2, String, Value>:
  allocated(H.allocate(vm, M.HeapEntry{id(vm, "java/lang/Object"), 11, tag, Nil{}, slots, units(name)}))

def constant_node(+vm: M.VM, +tag: U32, value: M.Constant) -> Result<&2, &2, String, Value>:
  match value:
    case M.Number{kind, bits}: node(vm, tag, [M.Slot{Bool.pick(U32, U32.is_eq(tag, 70), 2, 1), bits}], "")
    case M.PairIndex{kind, high, low}: node(vm, tag, [M.Slot{1, high}, M.Slot{1, low}], "")
    case _: Fail{"VmError.InvalidAnnotation: constant kind"}
def constant(+vm: M.VM, +pool: +List<M.Constant>, +tag: U32, index: U32) -> Result<&2, &2, String, Value>:
  match tag:
    case 115:
      do Result<&2, &2, String, Value>:
        name : String <- CP.utf(pool, index)
        result : Value <- node(vm, tag, Nil{}, name)
        return result
    case _:
      do Result<&2, &2, String, Value>:
        value : M.Constant <- CP.get(pool, index)
        result : Value <- constant_node(vm, tag, value)
        return result


type AnnOut is Data:
  OutValue{value: Value}
  OutBindings{value: Bindings}

type AnnJob is Data:
  JValue{value: M.AnnotationValue}
  JValuesNil{acc: +List<M.Slot>}
  JValuesCons{child: M.AnnotationValue, rest: +List<M.AnnotationValue>, acc: +List<M.Slot>}
  JValueRest{encoded: AnnOut, children: +List<M.AnnotationValue>, acc: +List<M.Slot>}
  JEnum{encoded: Value, owner: String}
  JObject{annotation: M.Annotation}
  JBindNil{owner: U32, acc: +List<M.Binding>}
  JBindCons{owner: U32, element: M.AnnotationElement, rest: +List<M.AnnotationElement>, acc: +List<M.Binding>}
  JBindMethod{found: Maybe<&2, M.LoadedMethod>, owner: U32, raw: M.AnnotationValue, rest: +List<M.AnnotationElement>, acc: +List<M.Binding>}
  JBindEncoded{encoded: AnnOut, owner: U32, method: U32, rest: +List<M.AnnotationElement>, acc: +List<M.Binding>}



def out_value(result: Result<&2, &2, String, Value>) -> Result<&2, &2, String, AnnOut>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: Done{OutValue{value}}

def value_vm(value: Value) -> M.VM:
  match value:
    case Value{vm, slot}: vm

def nested_elements(values: +List<M.AnnotationValue>) -> +List<M.AnnotationElement>:
  match values:
    case Nil{}: Nil{}
    case Con{M.AnnotationElementValue{nameIndex, value}, rest}: Con{M.AnnotationElement{nameIndex, value}, nested_elements(rest)}
    case Con{other, rest}: nested_elements(rest)

def object_after(value: Bindings, +owner: U32) -> Result<&2, &2, String, Value>:
  match value:
    case Bindings{vm, fields}: allocated(H.allocate(vm, M.HeapEntry{owner, 9, owner, fields, Nil{}, Nil{}}))

def object_out(out: AnnOut, owner: U32) -> Result<&2, &2, String, AnnOut>:
  match out:
    case OutBindings{value}: out_value(object_after(value, owner))
    case OutValue{value}: Fail{"InvalidState: annotation object"}

def values_job(children: +List<M.AnnotationValue>, acc: +List<M.Slot>) -> AnnJob:
  match children:
    case Nil{}: JValuesNil{acc}
    case Con{child, rest}: JValuesCons{child, rest, acc}

def bind_job(owner: U32, elements: +List<M.AnnotationElement>, acc: +List<M.Binding>) -> AnnJob:
  match elements:
    case Nil{}: JBindNil{owner, acc}
    case Con{element, rest}: JBindCons{owner, element, rest, acc}

@unsafe def ann_go(+vm: M.VM, +pool: +List<M.Constant>, job: AnnJob) -> Result<&2, &2, String, AnnOut>:
  match job:
    case JValue{M.AnnotationConst{tag, index}}: out_value(constant(vm, pool, tag, index))
    case JValue{M.AnnotationClass{index}}:
      do Result<&2, &2, String, AnnOut>:
        name : String <- CP.utf(pool, index)
        result : AnnOut <- out_value(node(vm, 99, Nil{}, name))
        return result
    case JValue{M.AnnotationEnum{typeIndex, nameIndex}}:
      do Result<&2, &2, String, AnnOut>:
        +owner : String <- CP.utf(pool, typeIndex)
        +name : String <- CP.utf(pool, nameIndex)
        +named : Value <- allocated(H.allocate(vm, H.string_entry(id(vm, "java/lang/String"), units(name))))
        result : AnnOut <- ann_go(value_vm(named), pool, JEnum{named, owner})
        return result
    case JValue{M.AnnotationNested{typeIndex, elements}}: ann_go(vm, pool, JObject{M.Annotation{typeIndex, nested_elements(elements)}})
    case JValue{M.AnnotationArray{children}}: ann_go(vm, pool, values_job(children, Nil{}))
    case JValue{M.AnnotationElementValue{nameIndex, child}}: Fail{"VmError.InvalidAnnotation: element wrapper"}
    case JValuesNil{acc}: out_value(node(vm, 91, M.reverse(M.Slot, acc), ""))
    case JValuesCons{child, +rest, +acc}:
      do Result<&2, &2, String, AnnOut>:
        +encoded : AnnOut <- ann_go(vm, pool, JValue{child})
        result : AnnOut <- ann_go(vm, pool, JValueRest{encoded, rest, acc})
        return result
    case JEnum{Value{vm, slot}, owner}: out_value(node(vm, 101, [slot], owner))
    case JObject{M.Annotation{typeIndex, elements}}:
      do Result<&2, &2, String, AnnOut>:
        descriptor : String <- CP.utf(pool, typeIndex)
        +owner : U32 = id(vm, class_name(descriptor))
        checked : Unit <- S.check(U32.is_ne(owner, 4294967295), "java/lang/TypeNotPresentException")
        bound : AnnOut <- ann_go(vm, pool, bind_job(owner, elements, Nil{}))
        result : AnnOut <- object_out(bound, owner)
        return result
    case JBindNil{owner, acc}: Done{OutBindings{Bindings{vm, M.reverse(M.Binding, acc)}}}
    case JBindCons{+owner, M.AnnotationElement{nameIndex, raw}, rest, acc}:
      do Result<&2, &2, String, AnnOut>:
        name : String <- CP.utf(pool, nameIndex)
        result : AnnOut <- ann_go(vm, pool, JBindMethod{method_find(S.methods(vm), owner, name, S.symbols(vm)), owner, raw, rest, acc})
        return result
    case JBindMethod{None{}, owner, raw, rest, acc}: ann_go(vm, pool, bind_job(owner, rest, acc))
    case JBindMethod{Some{method}, owner, raw, rest, acc}:
      do Result<&2, &2, String, AnnOut>:
        +encoded : AnnOut <- ann_go(vm, pool, JValue{raw})
        result : AnnOut <- ann_go(vm, pool, JBindEncoded{encoded, owner, M.loaded_method_id(method), rest, acc})
        return result
    case JBindEncoded{OutValue{Value{vm, slot}}, owner, method, rest, acc}: ann_go(vm, pool, bind_job(owner, rest, Con{M.Binding{method, slot}, acc}))
    case JValueRest{OutValue{Value{vm, slot}}, children, acc}: ann_go(vm, pool, values_job(children, Con{slot, acc}))
    case JValueRest{OutBindings{value}, children, acc}: Fail{"InvalidState: annotation array"}
    case JBindEncoded{OutBindings{value}, owner, method, rest, acc}: Fail{"InvalidState: annotation binding"}

def encode_out(out: AnnOut) -> Value:
  match out:
    case OutValue{value}: value
    case OutBindings{Bindings{vm, fields}}: Value{vm, M.Slot{3, 0}}

@unsafe def encode(+vm: M.VM, +pool: +List<M.Constant>, value: M.AnnotationValue) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    out : AnnOut <- ann_go(vm, pool, JValue{value})
    return encode_out(out)

@unsafe def object(+vm: M.VM, +pool: +List<M.Constant>, annotation: M.Annotation) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    out : AnnOut <- ann_go(vm, pool, JObject{annotation})
    return encode_out(out)

def error_alloc(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, Value>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{vm, reference}}: Done{Value{vm, M.Slot{99, reference}}}

def error(+vm: M.VM, name: String, first: M.Slot, second: M.Slot) -> Result<&2, &2, String, Value>:
  error_alloc(H.allocate(vm, H.object_entry(id(vm, name), [M.Binding{0, M.Slot{3, 0}}, M.Binding{1, M.Slot{3, 0}}, M.Binding{4, first}, M.Binding{5, second}])))

def string_error_after(value: Value, name: String, second: M.Slot) -> Result<&2, &2, String, Value>:
  match value:
    case Value{vm, slot}: error(vm, name, slot, second)
def string_error(+vm: M.VM, +name: String, first: String, second: M.Slot) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    value : Value <- allocated(H.allocate(vm, H.string_entry(id(vm, "java/lang/String"), units(first))))
    result : Value <- string_error_after(value, name, second)
    return result


def mirror_found(+vm: M.VM, +target: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, Value>:
  match found:
    case Some{reference}: Done{Value{vm, M.Slot{3, reference}}}
    case None{}: allocated(H.allocate(vm, H.class_mirror_entry(id(vm, "java/lang/Class"), target)))

def mirror(+vm: M.VM, +target: U32) -> Result<&2, &2, String, Value>:
  mirror_found(vm, target, H.class_mirror(S.heap(vm), target))

def enum_field(fields: +List<M.LoadedField>, +owner: U32, +name: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedField>:
  match fields:
    case Nil{}: None{}
    case Con{+field, rest}:
      Bool.pick(Maybe<&2, M.LoadedField>, U32.is_eq(M.loaded_field_owner(field), owner) && U32.is_ne(U32.and(M.loaded_field_flags(field), 16384), 0) && String.eq(Sy.text(symbols, M.loaded_field_name(field)), name), Some{field}, enum_field(rest, owner, name, symbols))

def enum_missing_after(value: Value, nameSlot: M.Slot) -> Result<&2, &2, String, Value>:
  match value:
    case Value{vm, slot}: error(vm, "java/lang/EnumConstantNotPresentException", slot, nameSlot)
def enum_field_cons(found: Maybe<&2, M.LoadedField>, +rest: +List<M.LoadedField>) -> +List<M.LoadedField>:
  match found:
    case Some{field}: Con{field, rest}
    case None{}: rest
def enum_fields(fields: +List<M.LoadedField>, +owner: U32) -> +List<M.LoadedField>:
  match fields:
    case Nil{}: Nil{}
    case Con{+field, +rest}: enum_field_cons(Bool.pick(Maybe<&2, M.LoadedField>, U32.is_eq(M.loaded_field_owner(field), owner) && U32.is_ne(U32.and(M.loaded_field_flags(field), 16384), 0), Some{field}, None{}), enum_fields(rest, owner))
type EnumInit is Data:
  IFields{fields: +List<M.LoadedField>, owner: U32, ordinal: U32}
  INamed{value: Value, rest: +List<M.LoadedField>, owner: U32, ordinal: U32, field: U32}
  IConstant{value: Value, rest: +List<M.LoadedField>, owner: U32, ordinal: U32, field: U32}

@unsafe def initialize_enum_job(+vm: M.VM, job: EnumInit) -> Result<&2, &2, String, M.VM>:
  match job:
    case IFields{Nil{}, owner, ordinal}: Done{vm}
    case IFields{Con{+field, rest}, +owner, ordinal}:
      do Result<&2, &2, String, M.VM>:
        +name : Value <- allocated(H.allocate(vm, H.string_entry(id(vm, "java/lang/String"), units(Sy.text(S.symbols(vm), M.loaded_field_name(field))))))
        result : M.VM <- initialize_enum_job(value_vm(name), INamed{name, rest, owner, ordinal, M.loaded_field_id(field)})
        return result
    case INamed{Value{vm, slot}, rest, +owner, +ordinal, field}:
      do Result<&2, &2, String, M.VM>:
        +value : Value <- allocated(H.allocate(vm, H.object_entry(owner, [M.Binding{0, slot}, M.Binding{1, M.Slot{1, ordinal}}])))
        result : M.VM <- initialize_enum_job(value_vm(value), IConstant{value, rest, owner, ordinal, field})
        return result
    case IConstant{Value{+vm, slot}, rest, owner, ordinal, field}: initialize_enum_job(S.with_statics(vm, H.binding_set(S.statics(vm), field, slot)), IFields{rest, owner, (ordinal + 1 : U32)})

def initialize_enum(+vm: M.VM, fields: +List<M.LoadedField>, owner: U32, ordinal: U32) -> Result<&2, &2, String, M.VM>:
  initialize_enum_job(vm, IFields{fields, owner, ordinal})
def enum_slot_value(found: Maybe<&2, M.Slot>) -> M.Slot:
  match found:
    case None{}: M.Slot{0, 0}
    case Some{slot}: slot

def enum_store(+vm: M.VM, field: M.LoadedField) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    +slot : M.Slot <- S.require(M.Slot, H.binding_find(S.statics(vm), M.loaded_field_id(field)), "InvalidState: enum singleton uninitialized")
    checked : Unit <- S.check(U32.is_ne(bits(slot), 0), "InvalidState: enum singleton uninitialized")
    return Value{vm, slot}

def enum_materialize(+vm: M.VM, +owner: U32, field: M.LoadedField, slot: M.Slot, missing: Bool) -> Result<&2, &2, String, Value>:
  match missing:
    case False{}: Done{Value{vm, slot}}
    case True{}:
      do Result<&2, &2, String, Value>:
        updated : M.VM <- initialize_enum(S.set_class_state(vm, owner, 2), enum_fields(S.fields(vm), owner), owner, 0)
        result : Value <- enum_store(updated, field)
        return result

def enum_materialize_slot(+vm: M.VM, +owner: U32, field: M.LoadedField, +slot: M.Slot) -> Result<&2, &2, String, Value>:
  enum_materialize(vm, owner, field, slot, U32.is_eq(bits(slot), 0))

def enum_found(found: Maybe<&2, M.LoadedField>, +vm: M.VM, owner: U32, nameSlot: M.Slot) -> Result<&2, &2, String, Value>:
  match found:
    case None{}:
      do Result<&2, &2, String, Value>:
        typeMirror : Value <- mirror(vm, owner)
        result : Value <- enum_missing_after(typeMirror, nameSlot)
        return result
    case Some{+field}: enum_materialize_slot(vm, owner, field, enum_slot_value(H.binding_find(S.statics(vm), M.loaded_field_id(field))))


def enum_lookup(+vm: M.VM, +owner: U32, +nameSlot: M.Slot) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    entry : M.HeapEntry <- H.get(S.heap(vm), bits(nameSlot))
    result : Value <- enum_found(enum_field(S.fields(vm), owner, text(chars(entry)), S.symbols(vm)), vm, owner, nameSlot)
    return result

def component(descriptor: String) -> String:
  match descriptor:
    case SCon{Chr{91}, rest}: rest
    case _: ""

def primitive_tag(descriptor: String) -> U32:
  match descriptor:
    case "[Z": 4
    case "[C": 5
    case "[F": 6
    case "[D": 7
    case "[B": 8
    case "[S": 9
    case "[I": 10
    case "[J": 11
    case _: 0

def array_alloc(+vm: M.VM, +descriptor: String, +slots: +List<M.Slot>) -> Result<&2, &2, String, Value>:
  +array : U32 = id(vm, descriptor)
  +primitive : U32 = primitive_tag(descriptor)
  Bool.pick(Result<&2, &2, String, Value>, U32.is_eq(primitive, 0) || U32.is_eq(primitive, 7) || U32.is_eq(primitive, 11), allocated(H.allocate(vm, H.reference_array_entry(array, id(vm, class_name(component(descriptor))), slots))), allocated(H.allocate(vm, H.primitive_array_entry(array, primitive, slots))))

def scalar_descriptor(tag: U32) -> String:
  match tag:
    case 66: "B"
    case 67: "C"
    case 68: "D"
    case 70: "F"
    case 73: "I"
    case 74: "J"
    case 83: "S"
    case 90: "Z"
    case 115: "Ljava/lang/String;"
    case 99: "Ljava/lang/Class;"
    case _: ""

def mismatch_reflected(value: Value, slot: M.Slot) -> Result<&2, &2, String, Value>:
  match value:
    case Value{vm, method}: error(vm, "java/lang/annotation/AnnotationTypeMismatchException", method, slot)
def mismatch_after(value: Value, +method: U32) -> Result<&2, &2, String, Value>:
  match value:
    case Value{+vm, slot}:
      do Result<&2, &2, String, Value>:
        +loaded : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), method), "InvalidState: annotation member")
        reflected : Value <- allocated(H.allocate(vm, H.object_entry(id(vm, "java/lang/reflect/Method"), [M.Binding{0, M.Slot{1, M.loaded_method_owner(loaded)}}, M.Binding{1, M.Slot{1, method}}, M.Binding{2, M.Slot{1, 0}}])))
        result : Value <- mismatch_reflected(reflected, slot)
        return result

def mismatch(+vm: M.VM, +method: U32, found: String) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    name : Value <- allocated(H.allocate(vm, H.string_entry(id(vm, "java/lang/String"), units(found))))
    result : Value <- mismatch_after(name, method)
    return result


def class_text_found(found: Maybe<&2, M.LoadedClass>, symbols: +List<String>) -> String:
  match found:
    case None{}: ""
    case Some{class}: Sy.text(symbols, M.loaded_class_name(class))
def class_text(+vm: M.VM, owner: U32) -> String:
  class_text_found(M.nth(M.LoadedClass, S.classes(vm), owner), S.symbols(vm))

def first(values: +List<M.Slot>) -> M.Slot:
  match values:
    case Con{slot, rest}: slot
    case Nil{}: M.Slot{3, 0}

def wide(+vm: M.VM, wrapper: String, slots: +List<M.Slot>) -> Result<&2, &2, String, Value>:
  match slots:
    case Con{high, Con{low, rest}}: allocated(H.allocate(vm, H.object_entry(id(vm, wrapper), [M.Binding{0, high}, M.Binding{1, low}])))
    case _: Fail{"VmError.InvalidAnnotation: wide constant"}

def resolve_enum(+vm: M.VM, +entry: M.HeapEntry) -> Result<&2, &2, String, Value>:
  +name : String = class_name(text(chars(entry)))
  +owner : U32 = id(vm, name)
  Bool.pick(Result<&2, &2, String, Value>, U32.is_eq(owner, 4294967295), string_error(vm, "java/lang/TypeNotPresentException", name, M.Slot{3, 0}), enum_lookup(vm, owner, first(values(entry))))

def resolve_scalar(+vm: M.VM, +entry: M.HeapEntry, tag: U32) -> Result<&2, &2, String, Value>:
  match tag:
    case 115: allocated(H.allocate(vm, H.string_entry(id(vm, "java/lang/String"), chars(entry))))
    case 99:
      +name : String = class_name(text(chars(entry)))
      +target : U32 = id(vm, name)
      Bool.pick(Result<&2, &2, String, Value>, U32.is_eq(target, 4294967295), string_error(vm, "java/lang/TypeNotPresentException", name, M.Slot{3, 0}), mirror(vm, target))
    case 74: wide(vm, "java/lang/Long", values(entry))
    case 68: wide(vm, "java/lang/Double", values(entry))
    case _: Done{Value{vm, first(values(entry))}}

type ResolveJob is Data:
  RSlot{slot: M.Slot, descriptor: String, method: U32}
  RNode{entry: M.HeapEntry, descriptor: String, method: U32, tag: U32}
  RArray{children: +List<M.Slot>, component: String, descriptor: String, method: U32, acc: +List<M.Slot>}
  RNext{value: Value, children: +List<M.Slot>, component: String, descriptor: String, method: U32, acc: +List<M.Slot>}

@unsafe def resolve_job(+vm: M.VM, job: ResolveJob) -> Result<&2, &2, String, Value>:
  match job:
    case RSlot{+slot, +descriptor, +method}:
      do Result<&2, &2, String, Value>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), bits(slot))
        result : Value <- Bool.pick(Result<&2, &2, String, Value>, U32.is_eq(kind(entry), 9), Bool.pick(Result<&2, &2, String, Value>, String.eq(descriptor, "L" ++ class_text(vm, H.entry_class(entry)) ++ ";"), Done{Value{vm, slot}}, mismatch(vm, method, "annotation")), resolve_job(vm, RNode{entry, descriptor, method, element(entry)}))
        return result
    case RNode{+entry, +descriptor, +method, +tag}:
      match tag:
        case 91: Bool.pick(Result<&2, &2, String, Value>, String.is_empty(component(descriptor)), mismatch(vm, method, "array"), resolve_job(vm, RArray{values(entry), component(descriptor), descriptor, method, Nil{}}))
        case 101: Bool.pick(Result<&2, &2, String, Value>, String.eq(text(chars(entry)), descriptor), resolve_enum(vm, entry), mismatch(vm, method, text(chars(entry))))
        case _: Bool.pick(Result<&2, &2, String, Value>, String.eq(scalar_descriptor(tag), descriptor), resolve_scalar(vm, entry, tag), mismatch(vm, method, scalar_descriptor(tag)))
    case RArray{Nil{}, component, descriptor, method, acc}: array_alloc(vm, descriptor, M.reverse(M.Slot, acc))
    case RArray{Con{slot, rest}, +component, +descriptor, +method, acc}:
      do Result<&2, &2, String, Value>:
        value : Value <- resolve_job(vm, RSlot{slot, component, method})
        result : Value <- resolve_job(vm, RNext{value, rest, component, descriptor, method, acc})
        return result
    case RNext{Value{vm, M.Slot{99, error}}, children, component, descriptor, method, acc}: Done{Value{vm, M.Slot{99, error}}}
    case RNext{Value{vm, slot}, children, component, descriptor, method, acc}: resolve_job(vm, RArray{children, component, descriptor, method, Con{slot, acc}})

@unsafe def resolve(+vm: M.VM, slot: M.Slot, descriptor: String, method: U32) -> Result<&2, &2, String, Value>:
  resolve_job(vm, RSlot{slot, descriptor, method})

def metadata_default(metadata: M.AnnotationMetadata) -> Maybe<&2, M.AnnotationValue>:
  M.AnnotationMetadata{flags, exceptions, annotations, parameters, types, value, invisible, invisibleParameters, invisibleTypes} = metadata
  value

def default_found(found: Maybe<&2, M.MethodMetadata>) -> Maybe<&2, M.AnnotationValue>:
  match found:
    case None{}: None{}
    case Some{M.MethodMetadata{owner, method, metadata, signature}}: metadata_default(metadata)
def default_metadata(metadata: M.Metadata, method: U32) -> Maybe<&2, M.AnnotationValue>:
  M.Metadata{classes, fields, methods} = metadata
  default_found(M.nth(M.MethodMetadata, methods, method))


def pool_found(found: Maybe<&2, M.ClassMetadata>) -> +List<M.Constant>:
  match found:
    case None{}: Nil{}
    case Some{M.ClassMetadata{owner, flags, metadata, names, pool, signature}}: pool
def pool_metadata(metadata: M.Metadata, owner: U32) -> +List<M.Constant>:
  M.Metadata{classes, fields, methods} = metadata
  pool_found(M.nth(M.ClassMetadata, classes, owner))


def incomplete_named(value: Value, annotationType: M.Slot) -> Result<&2, &2, String, Value>:
  match value:
    case Value{vm, name}: error(vm, "java/lang/annotation/IncompleteAnnotationException", annotationType, name)
def incomplete_after(value: Value, name: String) -> Result<&2, &2, String, Value>:
  match value:
    case Value{+vm, slot}:
      do Result<&2, &2, String, Value>:
        named : Value <- allocated(H.allocate(vm, H.string_entry(id(vm, "java/lang/String"), units(name))))
        result : Value <- incomplete_named(named, slot)
        return result


@unsafe def resolve_after(value: Value, descriptor: String, method: U32) -> Result<&2, &2, String, Value>:
  match value:
    case Value{vm, slot}: resolve(vm, slot, descriptor, method)
@unsafe def default_value(+vm: M.VM, +method: M.LoadedMethod, found: Maybe<&2, M.AnnotationValue>) -> Result<&2, &2, String, Value>:
  match found:
    case None{}:
      do Result<&2, &2, String, Value>:
        typeMirror : Value <- mirror(vm, M.loaded_method_owner(method))
        result : Value <- incomplete_after(typeMirror, Sy.text(S.symbols(vm), M.loaded_method_name(method)))
        return result
    case Some{value}:
      do Result<&2, &2, String, Value>:
        encoded : Value <- encode(vm, pool_metadata(S.metadata(vm), M.loaded_method_owner(method)), value)
        result : Value <- resolve_after(encoded, descriptor(vm, method), M.loaded_method_id(method))
        return result


@unsafe def effective(+vm: M.VM, +method: M.LoadedMethod, found: Maybe<&2, M.Slot>) -> Result<&2, &2, String, Value>:
  match found:
    case Some{slot}: resolve(vm, slot, descriptor(vm, method), M.loaded_method_id(method))
    case None{}: default_value(vm, method, default_metadata(S.metadata(vm), M.loaded_method_id(method)))

def outcome(value: Value) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case Value{vm, M.Slot{99, reference}}: Done{O.ThrownRef{vm, reference}}
    case Value{vm, slot}: Done{O.Returned{vm, Some{slot}}}

@unsafe def value(+vm: M.VM, +pool: +List<M.Constant>, raw: M.AnnotationValue, descriptor: String, method: U32) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    encoded : Value <- encode(vm, pool, raw)
    result : Value <- resolve_after(encoded, descriptor, method)
    return result

def pending_found(found: Maybe<&2, M.LoadedClass>, owner: U32) -> U32:
  match found:
    case None{}: 4294967295
    case Some{M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state}}:
      Bool.pick(U32, U32.is_eq(state, 0), owner, 4294967295)

type PendingJob is Data:
  PClass{owner: U32}
  PSlots{slots: +List<M.Slot>}
  PSlot{slot: M.Slot}
  PEntry{entry: M.HeapEntry}
  PRaw{pool: +List<M.Constant>, raw: M.AnnotationValue}
  PRaws{pool: +List<M.Constant>, raw: +List<M.AnnotationValue>}
  PDefault{method: M.LoadedMethod, found: Maybe<&2, M.AnnotationValue>}
  PMember{method: M.LoadedMethod, found: Maybe<&2, M.Slot>}
  PMembers{methods: +List<M.LoadedMethod>, bindings: +List<M.Binding>}

@unsafe def pending_job(+vm: M.VM, job: PendingJob) -> Result<&2, &2, String, U32>:
  match job:
    case PClass{+owner}: Done{pending_found(M.nth(M.LoadedClass, S.classes(vm), owner), owner)}
    case PSlots{Nil{}}: Done{4294967295}
    case PSlots{Con{slot, rest}}:
      do Result<&2, &2, String, U32>:
        +target : U32 <- pending_job(vm, PSlot{slot})
        result : U32 <- Bool.pick(Result<&2, &2, String, U32>, U32.is_ne(target, 4294967295), Done{target}, pending_job(vm, PSlots{rest}))
        return result
    case PSlot{slot}:
      do Result<&2, &2, String, U32>:
        entry : M.HeapEntry <- H.get(S.heap(vm), bits(slot))
        result : U32 <- pending_job(vm, PEntry{entry})
        return result
    case PEntry{M.HeapEntry{owner, 9, element, bindings, values, chars}}: pending_job(vm, PMembers{member_methods(S.methods(vm), owner, S.symbols(vm)), bindings})
    case PEntry{M.HeapEntry{owner, 11, 101, bindings, values, chars}}: pending_job(vm, PClass{id(vm, class_name(text(chars)))})
    case PEntry{M.HeapEntry{owner, 11, 91, bindings, values, chars}}: pending_job(vm, PSlots{values})
    case PEntry{_}: Done{4294967295}
    case PRaw{+pool, M.AnnotationEnum{typeIndex, nameIndex}}:
      do Result<&2, &2, String, U32>:
        name : String <- CP.utf(pool, typeIndex)
        result : U32 <- pending_job(vm, PClass{id(vm, class_name(name))})
        return result
    case PRaw{pool, M.AnnotationArray{values}}: pending_job(vm, PRaws{pool, values})
    case PRaw{pool, M.AnnotationNested{typeIndex, elements}}: pending_job(vm, PRaws{pool, elements})
    case PRaw{pool, M.AnnotationElementValue{nameIndex, child}}: pending_job(vm, PRaw{pool, child})
    case PRaw{pool, _}: Done{4294967295}
    case PRaws{+pool, Nil{}}: Done{4294967295}
    case PRaws{+pool, Con{value, rest}}:
      do Result<&2, &2, String, U32>:
        +target : U32 <- pending_job(vm, PRaw{pool, value})
        result : U32 <- Bool.pick(Result<&2, &2, String, U32>, U32.is_ne(target, 4294967295), Done{target}, pending_job(vm, PRaws{pool, rest}))
        return result
    case PDefault{method, None{}}: Done{4294967295}
    case PDefault{method, Some{raw}}: pending_job(vm, PRaw{pool_metadata(S.metadata(vm), M.loaded_method_owner(method)), raw})
    case PMember{method, Some{slot}}: pending_job(vm, PSlot{slot})
    case PMember{+method, None{}}: pending_job(vm, PDefault{method, default_metadata(S.metadata(vm), M.loaded_method_id(method))})
    case PMembers{Nil{}, bindings}: Done{4294967295}
    case PMembers{Con{+method, rest}, +bindings}:
      do Result<&2, &2, String, U32>:
        +target : U32 <- pending_job(vm, PMember{method, H.binding_find(bindings, M.loaded_method_id(method))})
        result : U32 <- Bool.pick(Result<&2, &2, String, U32>, U32.is_ne(target, 4294967295), Done{target}, pending_job(vm, PMembers{rest, bindings}))
        return result

@unsafe def initialization_target(vm: M.VM, receiver: U32) -> Result<&2, &2, String, U32>:
  pending_job(vm, PSlot{M.Slot{3, receiver}})

def float_bits(+bits: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.and(bits, 2139095040), 2139095040) && U32.is_ne(U32.and(bits, 8388607), 0), 2143289344, bits)

def double_high(+high: U32, +low: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.and(high, 2146435072), 2146435072) && (U32.is_ne(U32.and(high, 1048575), 0) || U32.is_ne(low, 0)), 2146959360, high)

def double_low(+high: U32, +low: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.and(high, 2146435072), 2146435072) && (U32.is_ne(U32.and(high, 1048575), 0) || U32.is_ne(low, 0)), 0, low)

def found_bits(found: Maybe<&2, M.Slot>) -> U32:
  match found:
    case None{}: 0
    case Some{slot}: bits(slot)

def field_bits(bindings: +List<M.Binding>, field: U32) -> U32:
  found_bits(H.binding_find(bindings, field))


def bool_value(vm: M.VM, equal: Bool) -> Value:
  Value{vm, M.Slot{1, Bool.pick(U32, equal, 1, 0)}}

def wide_equal(+vm: M.VM, left: M.Slot, right: M.Slot, +double: Bool) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    +l : M.HeapEntry <- H.get(S.heap(vm), bits(left))
    +r : M.HeapEntry <- H.get(S.heap(vm), bits(right))
    +lh : U32 = field_bits(fields(l), 0)
    +ll : U32 = field_bits(fields(l), 1)
    +rh : U32 = field_bits(fields(r), 0)
    +rl : U32 = field_bits(fields(r), 1)
    return bool_value(vm, U32.is_eq(Bool.pick(U32, double, double_high(lh, ll), lh), Bool.pick(U32, double, double_high(rh, rl), rh)) && U32.is_eq(Bool.pick(U32, double, double_low(lh, ll), ll), Bool.pick(U32, double, double_low(rh, rl), rl)))

type EqJob is Data:
  ESlot{left: M.Slot, right: M.Slot, descriptor: String}
  ERef{left: U32, right: U32, descriptor: String}
  EEntries{left: M.HeapEntry, right: M.HeapEntry, lref: U32, rref: U32, descriptor: String}
  EArrays{left: +List<M.Slot>, right: +List<M.Slot>, descriptor: String}
  EArrayNext{value: Value, left: +List<M.Slot>, right: +List<M.Slot>, descriptor: String}
  EMembers{methods: +List<M.LoadedMethod>, left: +List<M.Binding>, right: +List<M.Binding>}
  ELeft{value: Value, method: M.LoadedMethod, rest: +List<M.LoadedMethod>, left: +List<M.Binding>, right: +List<M.Binding>}
  ERight{value: Value, leftSlot: M.Slot, descriptor: String, rest: +List<M.LoadedMethod>, left: +List<M.Binding>, right: +List<M.Binding>}
  EMembersNext{value: Value, methods: +List<M.LoadedMethod>, left: +List<M.Binding>, right: +List<M.Binding>}

@unsafe def equal_job(+vm: M.VM, job: EqJob) -> Result<&2, &2, String, Value>:
  match job:
    case ESlot{+left, +right, descriptor}:
      match descriptor:
        case "F": Done{bool_value(vm, U32.is_eq(float_bits(bits(left)), float_bits(bits(right))))}
        case "J": wide_equal(vm, left, right, False{})
        case "D": wide_equal(vm, left, right, True{})
        case _: Bool.pick(Result<&2, &2, String, Value>, U32.is_eq(tag(left), 3), equal_job(vm, ERef{bits(left), bits(right), descriptor}), Done{bool_value(vm, U32.is_eq(bits(left), bits(right)))})
    case ERef{+left, +right, descriptor}:
      match left:
        case 0: Done{bool_value(vm, U32.is_eq(right, 0))}
        case lref:
          match right:
            case 0: Done{bool_value(vm, False{})}
            case rref:
              do Result<&2, &2, String, Value>:
                +l : M.HeapEntry <- H.get(S.heap(vm), lref)
                +r : M.HeapEntry <- H.get(S.heap(vm), rref)
                result : Value <- equal_job(vm, EEntries{l, r, lref, rref, descriptor})
                return result
    case EEntries{M.HeapEntry{+lc, 9, le, lf, lv, ln}, M.HeapEntry{rc, 9, re, rf, rv, rn}, lref, rref, descriptor}:
      Bool.pick(Result<&2, &2, String, Value>, U32.is_eq(lc, rc), equal_job(vm, EMembers{member_methods(S.methods(vm), lc, S.symbols(vm)), lf, rf}), Done{bool_value(vm, False{})})
    case EEntries{M.HeapEntry{lc, 3, le, lf, lv, ln}, M.HeapEntry{rc, 3, re, rf, rv, rn}, lref, rref, descriptor}: Done{bool_value(vm, H.units_equal(ln, rn))}
    case EEntries{+left, +right, lref, rref, +descriptor}:
      Bool.pick(Result<&2, &2, String, Value>, Bool.not(String.is_empty(component(descriptor))), equal_job(vm, EArrays{values(left), values(right), component(descriptor)}), Done{bool_value(vm, U32.is_eq(lref, rref))})
    case EArrays{Nil{}, Nil{}, descriptor}: Done{bool_value(vm, True{})}
    case EArrays{Con{l, ls}, Con{r, rs}, +descriptor}:
      do Result<&2, &2, String, Value>:
        value : Value <- equal_job(vm, ESlot{l, r, descriptor})
        result : Value <- equal_job(vm, EArrayNext{value, ls, rs, descriptor})
        return result
    case EArrays{left, right, descriptor}: Done{bool_value(vm, False{})}
    case EArrayNext{Value{vm, M.Slot{1, 1}}, left, right, descriptor}: equal_job(vm, EArrays{left, right, descriptor})
    case EArrayNext{other, left, right, descriptor}: Done{other}
    case EMembers{Nil{}, left, right}: Done{bool_value(vm, True{})}
    case EMembers{Con{+method, rest}, +left, right}:
      do Result<&2, &2, String, Value>:
        value : Value <- effective(vm, method, H.binding_find(left, M.loaded_method_id(method)))
        result : Value <- equal_job(vm, ELeft{value, method, rest, left, right})
        return result
    case ELeft{Value{vm, M.Slot{99, error}}, method, rest, left, right}: Done{Value{vm, M.Slot{99, error}}}
    case ELeft{Value{+vm, slot}, +method, rest, left, +right}:
      do Result<&2, &2, String, Value>:
        value : Value <- effective(vm, method, H.binding_find(right, M.loaded_method_id(method)))
        result : Value <- equal_job(vm, ERight{value, slot, descriptor(vm, method), rest, left, right})
        return result
    case ERight{Value{+vm, M.Slot{99, error}}, leftSlot, descriptor, rest, left, right}: Done{Value{vm, M.Slot{99, error}}}
    case ERight{Value{vm, slot}, leftSlot, descriptor, rest, left, right}:
      do Result<&2, &2, String, Value>:
        value : Value <- equal_job(vm, ESlot{leftSlot, slot, descriptor})
        result : Value <- equal_job(vm, EMembersNext{value, rest, left, right})
        return result
    case EMembersNext{Value{vm, M.Slot{1, 1}}, methods, left, right}: equal_job(vm, EMembers{methods, left, right})
    case EMembersNext{other, methods, left, right}: Done{other}

@unsafe def equal_ref(+vm: M.VM, left: U32, right: U32, descriptor: String) -> Result<&2, &2, String, Value>:
  equal_job(vm, ERef{left, right, descriptor})

def string_hash(chars: +List<U32>, acc: U32) -> U32:
  match chars:
    case Nil{}: acc
    case Con{c, rest}: string_hash(rest, (31 * acc + c : U32))

def hash_wide(+vm: M.VM, slot: M.Slot, +double: Bool) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits(slot))
    +high : U32 = field_bits(fields(entry), 0)
    +low : U32 = field_bits(fields(entry), 1)
    return Value{vm, M.Slot{1, U32.xor(Bool.pick(U32, double, double_high(high, low), high), Bool.pick(U32, double, double_low(high, low), low))}}

type HashJob is Data:
  HSlot{slot: M.Slot, descriptor: String}
  HRef{reference: U32, descriptor: String}
  HEntry{entry: M.HeapEntry, reference: U32, descriptor: String}
  HArray{slots: +List<M.Slot>, descriptor: String, acc: U32}
  HArrayNext{value: Value, slots: +List<M.Slot>, descriptor: String, acc: U32}
  HMembers{methods: +List<M.LoadedMethod>, bindings: +List<M.Binding>, acc: U32}
  HMemberValue{value: Value, method: M.LoadedMethod, rest: +List<M.LoadedMethod>, bindings: +List<M.Binding>, acc: U32}
  HMemberNext{value: Value, rest: +List<M.LoadedMethod>, bindings: +List<M.Binding>, acc: U32, nameHash: U32}

@unsafe def hash_job(+vm: M.VM, job: HashJob) -> Result<&2, &2, String, Value>:
  match job:
    case HSlot{+slot, descriptor}:
      match descriptor:
        case "Z": Done{Value{vm, M.Slot{1, Bool.pick(U32, U32.is_eq(bits(slot), 0), 1237, 1231)}}}
        case "F": Done{Value{vm, M.Slot{1, float_bits(bits(slot))}}}
        case "J": hash_wide(vm, slot, False{})
        case "D": hash_wide(vm, slot, True{})
        case _: Bool.pick(Result<&2, &2, String, Value>, U32.is_eq(tag(slot), 3), hash_job(vm, HRef{bits(slot), descriptor}), Done{Value{vm, M.Slot{1, bits(slot)}}})
    case HRef{+reference, +descriptor}:
      do Result<&2, &2, String, Value>:
        entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        result : Value <- hash_job(vm, HEntry{entry, reference, descriptor})
        return result
    case HEntry{M.HeapEntry{owner, 9, element, bindings, slots, chars}, reference, descriptor}: hash_job(vm, HMembers{member_methods(S.methods(vm), owner, S.symbols(vm)), bindings, 0})
    case HEntry{M.HeapEntry{owner, 3, element, bindings, slots, chars}, reference, descriptor}: Done{Value{vm, M.Slot{1, string_hash(chars, 0)}}}
    case HEntry{+entry, reference, +descriptor}: Bool.pick(Result<&2, &2, String, Value>, Bool.not(String.is_empty(component(descriptor))), hash_job(vm, HArray{values(entry), component(descriptor), 1}), Done{Value{vm, M.Slot{1, reference}}})
    case HArray{Nil{}, descriptor, acc}: Done{Value{vm, M.Slot{1, acc}}}
    case HArray{Con{slot, rest}, +descriptor, acc}:
      do Result<&2, &2, String, Value>:
        value : Value <- hash_job(vm, HSlot{slot, descriptor})
        result : Value <- hash_job(vm, HArrayNext{value, rest, descriptor, acc})
        return result
    case HArrayNext{Value{+vm, M.Slot{99, error}}, slots, descriptor, acc}: Done{Value{vm, M.Slot{99, error}}}
    case HArrayNext{Value{vm, slot}, slots, descriptor, acc}: hash_job(vm, HArray{slots, descriptor, (31 * acc + bits(slot) : U32)})
    case HMembers{Nil{}, bindings, acc}: Done{Value{vm, M.Slot{1, acc}}}
    case HMembers{Con{+method, rest}, +bindings, acc}:
      do Result<&2, &2, String, Value>:
        value : Value <- effective(vm, method, H.binding_find(bindings, M.loaded_method_id(method)))
        result : Value <- hash_job(vm, HMemberValue{value, method, rest, bindings, acc})
        return result
    case HMemberValue{Value{+vm, M.Slot{99, error}}, method, rest, bindings, acc}: Done{Value{vm, M.Slot{99, error}}}
    case HMemberValue{Value{+vm, slot}, +method, rest, bindings, acc}:
      do Result<&2, &2, String, Value>:
        +nameHash : U32 = string_hash(units(Sy.text(S.symbols(vm), M.loaded_method_name(method))), 0)
        value : Value <- hash_job(vm, HSlot{slot, descriptor(vm, method)})
        result : Value <- hash_job(vm, HMemberNext{value, rest, bindings, acc, nameHash})
        return result
    case HMemberNext{Value{+vm, M.Slot{99, error}}, rest, bindings, acc, nameHash}: Done{Value{vm, M.Slot{99, error}}}
    case HMemberNext{Value{vm, slot}, rest, bindings, acc, nameHash}: hash_job(vm, HMembers{rest, bindings, (acc + U32.xor((127 * nameHash : U32), bits(slot)) : U32)})

@unsafe def hash_ref(+vm: M.VM, reference: U32, descriptor: String) -> Result<&2, &2, String, Value>:
  hash_job(vm, HRef{reference, descriptor})


def enum_statics(+vm: M.VM, fields: +List<M.LoadedField>) -> Result<&2, &2, String, +List<M.Slot>>:
  match fields:
    case Nil{}: Done{Nil{}}
    case Con{field, rest}:
      do Result<&2, &2, String, +List<M.Slot>>:
        slot : M.Slot <- S.require(M.Slot, H.binding_find(S.statics(vm), M.loaded_field_id(field)), "InvalidState: enum constant")
        slots : +List<M.Slot> <- enum_statics(vm, rest)
        return Con{slot, slots}

def enum_values(+vm: M.VM, +owner: U32) -> Result<&2, &2, String, Value>:
  do Result<&2, &2, String, Value>:
    slots : +List<M.Slot> <- enum_statics(vm, enum_fields(S.fields(vm), owner))
    result : Value <- array_alloc(vm, "[L" ++ class_text(vm, owner) ++ ";", slots)
    return result
