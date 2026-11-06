import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../runtime/value.bend as V
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ../classfile/constant_pool.bend as CP
import ./outcome.bend as O
import ../classfile/descriptor.bend as D
import ../runtime/wide.bend as W
import ../runtime/binary64.bend as B64
import ./generic.bend as G
import ../classfile/signature.bend as Sig
import ./annotation_runtime.bend as AR
import ../loader/class_loader.bend as CL
import ../loader/bootstrap.bend as B
import ./loader_state.bend as LS
import ../runtime/threads.bend as Th
import ../runtime/trace.bend as Tr
type ReflectRefs is Data:
  ReflectRefs{vm: M.VM, refs: +List<U32>}
type AnnotationValueRef is Data:
  AnnotationValueRef{vm: M.VM, slot: M.Slot}
type AnnotationValueRefs is Data:
  AnnotationValueRefs{vm: M.VM, slots: +List<M.Slot>}
type AnnotationBindings is Data:
  AnnotationBindings{vm: M.VM, bindings: +List<M.Binding>}

type ProxyClassResult is Data:
  ProxyClassResult{vm: M.VM, classId: U32}
type ParameterAnnotationRefs is Data:
  ParameterAnnotationRefs{vm: M.VM, slots: +List<M.Slot>}

type ProxyBoxedArgs is Data:
  ProxyBoxedArgs{vm: M.VM, values: +List<M.Slot>}

type ProxyBoxedValue is Data:
  ProxyBoxedValue{vm: M.VM, slot: M.Slot}
type ProxyMethodSig is Data:
  ProxyMethodSig{name: String, parameters: String, result: String}
type ProxyCallPlan is Data:
  ProxyCallPlan{allocation: H.Allocation, method: U32, owners: +List<U32>}

type ProxyExceptionGroup is Data:
  ProxyExceptionGroup{types: +List<U32>}

type ClassForNameArgs is Data:
  ClassForNameArgs{name: M.Slot, shouldInit: Bool, loader: U32}

type ClassForNameAction is Data:
  Initialize{}
  NoInitialize{}


type AnnotationMetadataRef is Data:
  AnnotationMetadataRef{vm: M.VM, pool: +List<M.Constant>, metadata: M.AnnotationMetadata}
type ResourceRefs is Data:
  ResourceRefs{vm: M.VM, refs: +List<U32>}
type PropPair is Data:
  PropPair{key: String, value: String}
type PropSlots is Data:
  PropSlots{vm: M.VM, slots: +List<M.Slot>, count: U32, props: U32}
type UrlOrigin is Data:
  UrlOrigin{archive: Bool, text: String}
def class_id(+vm: M.VM, name: String) -> U32:
  H.named_class(S.classes(vm), S.symbols(vm), name)
def wrapper_value_field_id_scan(fields: +List<M.LoadedField>, +owner: U32, +symbols: +List<String>, +descriptor: String) -> Maybe<&2, U32>:
  match fields:
    case Nil{}: None{}
    case Con{+field, rest}:
      +match_field = U32.is_eq(M.loaded_field_owner(field), owner) &&
        String.eq(Sy.text(symbols, M.loaded_field_name(field)), "value") &&
        String.eq(Sy.text(symbols, M.loaded_field_descriptor(field)), descriptor)
      Bool.pick(Maybe<&2, U32>, match_field, Some{M.loaded_field_id(field)}, wrapper_value_field_id_scan(rest, owner, symbols, descriptor))

def wrapper_value_field_id(+vm: M.VM, class_name: String, descriptor: String) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +owner : U32 = class_id(vm, class_name)
    field : U32 <- S.require(U32, wrapper_value_field_id_scan(S.fields(vm), owner, S.symbols(vm), descriptor), "java/lang/NoSuchFieldException")
    return field


def entry_fields(entry: M.HeapEntry) -> +List<M.Binding>:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  fields

def entry_kind(entry: M.HeapEntry) -> U32:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  kind

def entry_values(entry: M.HeapEntry) -> +List<M.Slot>:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  values

def entry_element(entry: M.HeapEntry) -> U32:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  element

def entry_chars(entry: M.HeapEntry) -> +List<U32>:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  chars

# Decode Java UTF-16 code units for host output; unpaired surrogates become U+FFFD.
def high_surrogate(+unit: U32) -> Bool:
  Bool.and(U32.is_ge(unit, 55296), U32.is_le(unit, 56319))

def low_surrogate(+unit: U32) -> Bool:
  Bool.and(U32.is_ge(unit, 56320), U32.is_le(unit, 57343))

def utf16_unit(+pending: U32, +unit: U32, paired: Bool) -> String:
  match paired:
    case True{}:
      Char.show(Chr{U32.add(65536, U32.add(U32.shln(U32.sub(pending, 55296), 10n), U32.sub(unit, 56320)))})
    case False{}:
      Bool.pick(String, U32.is_eq(pending, 0), "", Char.show(Chr{65533})) ++ Bool.pick(String, high_surrogate(unit), "", Char.show(Chr{Bool.pick(U32, low_surrogate(unit), 65533, unit)}))

def utf16(units: +List<U32>, +pending: U32) -> String:
  match units:
    case Nil{}:
      Bool.pick(String, U32.is_eq(pending, 0), "", Char.show(Chr{65533}))
    case Con{+unit, tail}:
      +paired = Bool.and(U32.is_ne(pending, 0), low_surrogate(unit))
      utf16_unit(pending, unit, paired) ++ utf16(tail, Bool.pick(U32, Bool.and(Bool.not(paired), high_surrogate(unit)), unit, 0))

def name_text(chars: +List<U32>) -> String:
  match chars:
    case Nil{}: ""
    case Con{unit, rest}: Char.show(Chr{unit}) ++ name_text(rest)

def string_text(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 3), "java/lang/IllegalArgumentException")
    return name_text(entry_chars(entry))

def loaded_class_name_found(found: Maybe<&2, M.LoadedClass>) -> U32:
  match found:
    case None{}: 0
    case Some{value}: M.loaded_class_name(value)

def loaded_class_name_at(+id: U32, classes: +List<M.LoadedClass>) -> U32:
  loaded_class_name_found(M.nth(M.LoadedClass, classes, id))

def class_name_text(+vm: M.VM, id: U32) -> String:
  Sy.text(S.symbols(vm), loaded_class_name_at(id, S.classes(vm)))

def npe() -> String:
  "java/lang/NullPointerException"

def oob() -> String:
  "java/lang/IndexOutOfBoundsException"

def sioob() -> String:
  "java/lang/StringIndexOutOfBoundsException"

def nfe() -> String:
  "java/lang/NumberFormatException"

def iae() -> String:
  "java/lang/IllegalArgumentException"

def ise() -> String:
  "java/lang/IllegalStateException"

def nsee() -> String:
  "java/lang/NoSuchElementException"

def cme() -> String:
  "java/lang/ConcurrentModificationException"

def ase() -> String:
  "java/lang/ArrayStoreException"

def returned(+vm: M.VM, value: Maybe<&2, M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  Done{O.Returned{vm, value}}

def void_out(+vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  returned(vm, None{})

def int_out(+vm: M.VM, bits: U32) -> Result<&2, &2, String, O.Outcome>:
  returned(vm, Some{M.Slot{1, bits}})

def ref_out(+vm: M.VM, bits: U32) -> Result<&2, &2, String, O.Outcome>:
  returned(vm, Some{M.Slot{3, bits}})

def bool_out(+vm: M.VM, value: Bool) -> Result<&2, &2, String, O.Outcome>:
  int_out(vm, Bool.pick(U32, value, 1, 0))

def throw_name(+vm: M.VM, name: String) -> Result<&2, &2, String, O.Outcome>:
  Done{O.ThrownName{vm, name}}

def throw_ref(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, O.Outcome>:
  Done{O.ThrownRef{vm, reference}}

def slot0(args: +List<M.Slot>) -> Result<&2, &2, String, M.Slot>:
  match args:
    case Con{value, rest}: Done{value}
    case _: Fail{"InvalidState: intrinsic argument count"}

def slot1(args: +List<M.Slot>) -> Result<&2, &2, String, M.Slot>:
  match args:
    case Con{a, Con{value, rest}}: Done{value}
    case _: Fail{"InvalidState: intrinsic argument count"}

def slot2(args: +List<M.Slot>) -> Result<&2, &2, String, M.Slot>:
  match args:
    case Con{a, Con{b, Con{value, rest}}}: Done{value}
    case _: Fail{"InvalidState: intrinsic argument count"}

def slot3(args: +List<M.Slot>) -> Result<&2, &2, String, M.Slot>:
  match args:
    case Con{a, Con{b, Con{c, Con{value, rest}}}}: Done{value}
    case _: Fail{"InvalidState: intrinsic argument count"}

def slot4(args: +List<M.Slot>) -> Result<&2, &2, String, M.Slot>:
  match args:
    case Con{a, Con{b, Con{c, Con{d, Con{value, rest}}}}}: Done{value}
    case _: Fail{"InvalidState: intrinsic argument count"}

def bits_of(slot: M.Slot) -> U32:
  M.slot_bits(slot)
def alloc_ok(allocation: H.Allocation, cont: M.VM -> U32 -> Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case H.Allocation{vm, reference}:
      cont(vm, reference)

def alloc_result(result: Result<&2, &2, String, H.Allocation>, cont: M.VM -> U32 -> Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{allocation}: alloc_ok(allocation, cont)

def intern_or_alloc_found(+vm: M.VM, +chars: +List<U32>, found: Maybe<&2, U32>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{reference}: ref_out(vm, reference)
    case None{}:
      alloc_result(H.allocate(vm, H.string_entry(class_id(vm, "java/lang/String"), chars)), vm2 => reference => ref_out(vm2, reference))

def intern_or_alloc(+vm: M.VM, +chars: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  intern_or_alloc_found(vm, chars, H.string_intern(S.heap(vm), chars))

def units_from_char(+u: U32, +rest: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_le(u, 65535), Con{u, rest}, Con{U32.add(55296, U32.shrn(U32.sub(u, 65536), 10n)), Con{U32.add(56320, U32.and(U32.sub(u, 65536), 1023)), rest}})

def units_from_list(values: +List<Char>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}: units_from_char(Char.to_u32(head), units_from_list(tail))

def units_from_string(text: String) -> +List<U32>:
  units_from_list(String.to_list(text))
def class_mirror_out_found(+vm: M.VM, +target: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{reference}:
      ref_out(vm, reference)
    case None{}:
      alloc_result(H.allocate(vm, H.class_mirror_entry(class_id(vm, "java/lang/Class"), target)), vm2 => reference => ref_out(vm2, reference))

def class_mirror_out(+vm: M.VM, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  class_mirror_out_found(vm, target, H.class_mirror(S.heap(vm), target))
def proxy_field(+vm: M.VM, reference: U32, index: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    value : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), index), "java/lang/IllegalStateException")
    return bits_of(value)

def proxy_own_method(methods: +List<M.LoadedMethod>, +symbols: +List<String>, +owner: U32, +name: String, +desc: String) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>,
        U32.is_eq(M.loaded_method_owner(method), owner) &&
        String.eq(Sy.text(symbols, M.loaded_method_name(method)), name) &&
        String.eq(Sy.text(symbols, M.loaded_method_descriptor(method)), desc),
        Some{method}, proxy_own_method(rest, symbols, owner, name, desc))

def proxy_parent_found(found: Maybe<&2, M.LoadedClass>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{value}: M.loaded_class_parent(value)

def proxy_parent(+classes: +List<M.LoadedClass>, owner: U32) -> U32:
  proxy_parent_found(M.nth(M.LoadedClass, classes, owner))
def proxy_method_continue(found: Maybe<&2, M.LoadedMethod>, parent: U32, next: U32 -> Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case Some{value}: Some{value}
    case None{}:
      match parent:
        case 4294967295: None{}
        case value: next(value)
@unsafe def proxy_method_hierarchy(fuel: Nat, +classes: +List<M.LoadedClass>, +methods: +List<M.LoadedMethod>, +symbols: +List<String>, +owner: U32, +name: String, +desc: String) -> Maybe<&2, M.LoadedMethod>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      proxy_method_continue(proxy_own_method(methods, symbols, owner, name, desc), proxy_parent(classes, owner), parent => proxy_method_hierarchy(p, classes, methods, symbols, parent, name, desc))

def proxy_handler_method(+vm: M.VM, handler: U32) -> Result<&2, &2, String, M.LoadedMethod>:
  do Result<&2, &2, String, M.LoadedMethod>:
    entry : M.HeapEntry <- H.get(S.heap(vm), handler)
    method : M.LoadedMethod <- S.require(M.LoadedMethod, proxy_method_hierarchy(256n, S.classes(vm), S.methods(vm), S.symbols(vm), H.entry_class(entry), "invoke", "(Ljava/lang/Object;Ljava/lang/reflect/Method;[Ljava/lang/Object;)Ljava/lang/Object;"), "java/lang/AbstractMethodError")
    return method


def proxy_box_alloc_result(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, ProxyBoxedValue>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, +reference}}: Done{ProxyBoxedValue{vm, M.Slot{3, reference}}}

def proxy_box_alloc(+vm: M.VM, value: M.Slot, name: String) -> Result<&2, &2, String, ProxyBoxedValue>:
  proxy_box_alloc_result(H.allocate(vm, H.object_entry(class_id(vm, name), [M.Binding{0, value}])))
def proxy_box_wide(+vm: M.VM, +value: M.Slot, +class_name: String, +descriptor: String) -> Result<&2, &2, String, ProxyBoxedValue>:
  do Result<&2, &2, String, ProxyBoxedValue>:
    +tag : U32 = Bool.pick(U32, String.eq(descriptor, "J"), 4, 5)
    checked : Unit <- S.check(U32.is_eq(M.slot_tag(value), tag), "java/lang/IllegalArgumentException")
    field : U32 <- wrapper_value_field_id(vm, class_name, descriptor)
    allocation : H.Allocation <- H.allocate(vm, H.object_entry(class_id(vm, class_name), [M.Binding{field, value}]))
    boxed : ProxyBoxedValue <- proxy_box_alloc_result(Done{allocation})
    return boxed

def proxy_box_primitive(+vm: M.VM, value: M.Slot, tag: U32) -> Result<&2, &2, String, ProxyBoxedValue>:
  match tag:
    case 90: proxy_box_alloc(vm, value, "java/lang/Boolean")
    case 66: proxy_box_alloc(vm, value, "java/lang/Byte")
    case 83: proxy_box_alloc(vm, value, "java/lang/Short")
    case 67: proxy_box_alloc(vm, value, "java/lang/Character")
    case 73: proxy_box_alloc(vm, value, "java/lang/Integer")
    case 70: proxy_box_alloc(vm, value, "java/lang/Float")
    case 74: proxy_box_wide(vm, value, "java/lang/Long", "J")
    case 68: proxy_box_wide(vm, value, "java/lang/Double", "D")
    case _: Fail{"java/lang/IllegalArgumentException"}

def proxy_box_value(+vm: M.VM, value: M.Slot, jvm_type: M.JvmType) -> Result<&2, &2, String, ProxyBoxedValue>:
  match jvm_type:
    case M.Primitive{tag}: proxy_box_primitive(vm, value, tag)
    case _: Done{ProxyBoxedValue{vm, value}}

def proxy_box_value_continue(result: Result<&2, &2, String, ProxyBoxedValue>, next: M.VM -> M.Slot -> Result<&2, &2, String, ProxyBoxedArgs>) -> Result<&2, &2, String, ProxyBoxedArgs>:
  match result:
    case Fail{error}: Fail{error}
    case Done{ProxyBoxedValue{+vm, slot}}: next(vm, slot)

def proxy_box_args(+types: +List<M.JvmType>, +values: +List<M.Slot>, +vm: M.VM, +acc: +List<M.Slot>) -> Result<&2, &2, String, ProxyBoxedArgs>:
  match types values:
    case Nil{} Nil{}: Done{ProxyBoxedArgs{vm, M.reverse(M.Slot, acc)}}
    case Con{jvm_type, rest} Con{value, values_rest}:
      do Result<&2, &2, String, ProxyBoxedArgs>:
        result : ProxyBoxedArgs <- proxy_box_value_continue(proxy_box_value(vm, value, jvm_type), boxed_vm => boxed_slot => proxy_box_args(rest, values_rest, boxed_vm, Con{boxed_slot, acc}))
        return result
    case _ _: Fail{"java/lang/IllegalArgumentException"}

def proxy_class_pool_found(found: Maybe<&2, M.ClassMetadata>) -> Result<&2, &2, String, +List<M.Constant>>:
  match found:
    case None{}: Fail{"InvalidState: missing class metadata"}
    case Some{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, +pool, signature, nesting, source}}: Done{pool}

def proxy_class_pool(metadata: M.Metadata, owner: U32) -> Result<&2, &2, String, +List<M.Constant>>:
  match metadata:
    case M.Metadata{+classes, fields, methods}: proxy_class_pool_found(M.nth(M.ClassMetadata, classes, owner))

def proxy_annotation_exceptions(value: M.AnnotationMetadata) -> +List<U32>:
  match value:
    case M.AnnotationMetadata{+flags, +exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue, ia, ip, it}: exceptions

def proxy_method_exceptions_found(found: Maybe<&2, M.MethodMetadata>) -> Result<&2, &2, String, +List<U32>>:
  match found:
    case None{}: Fail{"InvalidState: missing method metadata"}
    case Some{M.MethodMetadata{owner, method, metadata, signature, parameters, lines}}: Done{proxy_annotation_exceptions(metadata)}

def proxy_metadata_exceptions(metadata: M.Metadata, method: U32) -> Result<&2, &2, String, +List<U32>>:
  match metadata:
    case M.Metadata{classes, fields, +methods}: proxy_method_exceptions_found(M.nth(M.MethodMetadata, methods, method))

def proxy_exception_ids(+vm: M.VM, +pool: +List<M.Constant>, +values: +List<U32>, +acc: +List<U32>) -> Result<&2, &2, String, +List<U32>>:
  match values:
    case Nil{}: Done{M.reverse(U32, acc)}
    case Con{index, rest}:
      do Result<&2, &2, String, +List<U32>>:
        name : String <- CP.class_name(pool, index)
        tail : +List<U32> <- proxy_exception_ids(vm, pool, rest, Con{class_id(vm, name), acc})
        return tail


def proxy_call_array_after(boxed: ProxyBoxedArgs, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, method_ref: U32, +descriptor: String, +method_id: U32, +owners: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  match boxed:
    case ProxyBoxedArgs{vm, Nil{}}:
      Done{O.Call{S.with_effect(vm, M.ProxyCall{descriptor, method_id, owners}), handler_method, [M.Slot{3, handler}, M.Slot{3, proxy}, M.Slot{3, method_ref}, M.Slot{3, 0}]}}
    case ProxyBoxedArgs{+vm, +values}:
      alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/Object;"), class_id(vm, "java/lang/Object"), values)),
        array_vm => array_ref => Done{O.Call{S.with_effect(array_vm, M.ProxyCall{descriptor, method_id, owners}), handler_method, [M.Slot{3, handler}, M.Slot{3, proxy}, M.Slot{3, method_ref}, M.Slot{3, array_ref}]}})

def proxy_call_array_values(+vm: M.VM, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, method_ref: U32, +descriptor: String, method_id: U32, +owners: +List<U32>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    parsed : M.Descriptor <- D.parse_method(descriptor)
    boxed : ProxyBoxedArgs <- proxy_box_args(D.parameter_types(parsed), values, vm, Nil{})
    result : O.Outcome <- proxy_call_array_after(boxed, handler, proxy, handler_method, method_ref, descriptor, method_id, owners)
    return result

def proxy_call_array(+vm: M.VM, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, method_ref: U32, +descriptor: String, method_id: U32, +owners: +List<U32>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  proxy_call_array_values(vm, handler, proxy, handler_method, method_ref, descriptor, method_id, owners, M.drop(M.Slot, values, 1n))

def proxy_call_method_alloc(allocation: H.Allocation, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, +descriptor: String, method_id: U32, +owners: +List<U32>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case H.Allocation{+vm, reference}: proxy_call_array(vm, handler, proxy, handler_method, reference, descriptor, method_id, owners, values)


def proxy_binding_set(xs: +List<M.Binding>, +id: U32, +value: M.Slot) -> +List<M.Binding>:
  match xs:
    case Nil{}: [M.Binding{id, value}]
    case Con{M.Binding{+binding_id, old}, rest}:
      Con{M.Binding{binding_id, Bool.pick(M.Slot, U32.is_eq(binding_id, id), value, old)}, proxy_binding_set(rest, id, value)}

def proxy_hash_slots(values: +List<M.Slot>, acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case Con{M.Slot{tag, bits}, rest}: proxy_hash_slots(rest, U32.add(U32.mul(31, acc), U32.add(tag, bits)))
    case Con{M.Wide{tag, high, low}, rest}:
      +tag_hash = U32.add(U32.mul(31, acc), tag)
      +high_hash = U32.add(U32.mul(31, tag_hash), high)
      +low_hash = U32.add(U32.mul(31, high_hash), low)
      proxy_hash_slots(rest, low_hash)
    case Con{M.Unusable{}, rest}: proxy_hash_slots(rest, U32.add(U32.mul(31, acc), 4294967295))

def proxy_cache_key(loader: U32, values: +List<M.Slot>) -> U32:
  U32.add(1073741824, U32.and(U32.add(U32.mul(65537, loader), proxy_hash_slots(values, 0)), 1048575))

def proxy_interface_ids(fuel: Nat, +vm: M.VM, values: +List<M.Slot>, +acc: +List<U32>) -> Result<&2, &2, String, +List<U32>>:
  match fuel values:
    case 0n _: Fail{"java/lang/IllegalArgumentException"}
    case 1n+remaining Nil{}: Done{M.reverse(U32, acc)}
    case 1n+remaining Con{slot, rest}:
      do Result<&2, &2, String, +List<U32>>:
        +mirror : M.HeapEntry <- H.get(S.heap(vm), bits_of(slot))
        checked : Unit <- S.check(U32.is_eq(entry_kind(mirror), 8), "java/lang/IllegalArgumentException")
        result : +List<U32> <- proxy_interface_ids(remaining, vm, rest, Con{entry_element(mirror), acc})
        return result

def proxy_class_flags_found(found: Maybe<&2, M.ClassMetadata>) -> U32:
  match found:
    case None{}: 0
    case Some{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, pool, signature, nesting, source}}: flags

def proxy_class_flags(metadata: M.Metadata, target: U32) -> U32:
  match metadata:
    case M.Metadata{classes, fields, methods}: proxy_class_flags_found(M.nth(M.ClassMetadata, classes, target))

def proxy_id_seen(ids: +List<U32>, +target: U32) -> Bool:
  match ids:
    case Nil{}: False{}
    case Con{head, rest}: Bool.or(U32.is_eq(head, target), proxy_id_seen(rest, target))

# Package prefix of a slash-separated name ("a/b/C" -> "a/b/", "C" -> "").
def name_package_scan(chars: +List<Char>, +before: String, +segment: +List<Char>) -> String:
  match chars:
    case Nil{}: before
    case Con{Chr{47}, tail}: name_package_scan(tail, before ++ String.from_list(M.reverse(Char, segment)) ++ "/", Nil{})
    case Con{head, tail}: name_package_scan(tail, before, Con{head, segment})

def binary_package(+name: String) -> String:
  name_package_scan(String.to_list(name), "", Nil{})

def proxy_class_package(+vm: M.VM, target: U32) -> String:
  binary_package(class_name_text(vm, target))

def proxy_validate_ids(ids: +List<U32>, +vm: M.VM, +metadata: M.Metadata, +seen: +List<U32>, +nonpublic: Bool, +package: String) -> Result<&2, &2, String, Unit>:
  match ids:
    case Nil{}: Done{Unit{}}
    case Con{target, rest}:
      do Result<&2, &2, String, Unit>:
        +target_ref : U32 = target
        +flags : U32 = proxy_class_flags(metadata, target_ref)
        +is_interface : Bool = U32.is_ne(U32.and(flags, 512), 0)
        +is_public : Bool = U32.is_ne(U32.and(flags, 1), 0)
        +target_package : String = proxy_class_package(vm, target_ref)
        +package_ok : Bool = is_public || Bool.not(nonpublic) || String.eq(package, target_package)
        checked : Unit <- S.check(is_interface && Bool.not(proxy_id_seen(seen, target_ref)) && package_ok, "java/lang/IllegalArgumentException")
        +next_nonpublic : Bool = Bool.pick(Bool, nonpublic, True{}, Bool.not(is_public))
        +next_package : String = Bool.pick(String, nonpublic || is_public, package, target_package)
        result : Unit <- proxy_validate_ids(rest, vm, metadata, Con{target_ref, seen}, next_nonpublic, next_package)
        return result

def proxy_method_owner_ids(ids: +List<U32>, +classes: +List<M.LoadedClass>, +owner: U32) -> Bool:
  match ids:
    case Nil{}: False{}
    case Con{target, rest}: Bool.or(H.hierarchy(classes, target, owner), proxy_method_owner_ids(rest, classes, owner))

def proxy_interface_owners(fuel: Nat, +pending: +List<U32>, +classes: +List<M.LoadedClass>, +seen: +List<U32>) -> Result<&2, &2, String, +List<U32>>:
  match fuel pending:
    case 0n _: Fail{"java/lang/IllegalArgumentException"}
    case 1n+remaining Nil{}: Done{seen}
    case 1n+remaining Con{target, rest}:
      do Result<&2, &2, String, +List<U32>>:
        class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, classes, target), "java/lang/NoClassDefFoundError")
        +interfaces : +List<U32> = M.loaded_class_interfaces(class)
        +found : Bool = proxy_id_seen(seen, target)
        +next_seen : +List<U32> = Bool.pick(+List<U32>, found, seen, Con{target, seen})
        +expanded : +List<U32> = M.append(U32, interfaces, rest)
        +next_pending : +List<U32> = Bool.pick(+List<U32>, found, rest, expanded)
        result : +List<U32> <- proxy_interface_owners(remaining, next_pending, classes, next_seen)
        return result









def proxy_descriptor_parameters(+chars: +List<Char>, +acc: +List<Char>) -> String:
  match chars:
    case Nil{}: String.from_list(M.reverse(Char, acc))
    case Con{Chr{41}, tail}: String.from_list(M.reverse(Char, acc))
    case Con{head, tail}: proxy_descriptor_parameters(tail, Con{head, acc})

def proxy_descriptor_return(+chars: +List<Char>) -> String:
  match chars:
    case Nil{}: ""
    case Con{Chr{41}, tail}: String.from_list(tail)
    case Con{head, tail}: proxy_descriptor_return(tail)

def proxy_method_sig(+vm: M.VM, method: M.LoadedMethod) -> ProxyMethodSig:
  match method:
    case M.LoadedMethod{id, owner, +name, +descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}:
      +descriptor_text : String = Sy.text(S.symbols(vm), descriptor)
      ProxyMethodSig{Sy.text(S.symbols(vm), name), proxy_descriptor_parameters(String.to_list(descriptor_text), Nil{}), proxy_descriptor_return(String.to_list(descriptor_text))}

def proxy_reference_result(+descriptor: String) -> Bool:
  String.starts_with(descriptor, "L") || String.starts_with(descriptor, "[")

def proxy_results_compatible(+vm: M.VM, +left: String, +right: String) -> Bool:
  String.eq(left, right) || (proxy_reference_result(left) && proxy_reference_result(right) &&
    (H.descriptor_assignable(left, right, S.classes(vm), S.symbols(vm)) || H.descriptor_assignable(right, left, S.classes(vm), S.symbols(vm))))

def proxy_sig_conflict(+vm: M.VM, left: ProxyMethodSig, right: ProxyMethodSig) -> Bool:
  match left right:
    case ProxyMethodSig{+left_name, +left_parameters, +left_result} ProxyMethodSig{+right_name, +right_parameters, +right_result}:
      String.eq(left_name, right_name) && String.eq(left_parameters, right_parameters) && Bool.not(proxy_results_compatible(vm, left_result, right_result))

def proxy_sig_check(+vm: M.VM, +value: ProxyMethodSig, +rest: +List<ProxyMethodSig>) -> Result<&2, &2, String, Unit>:
  match rest:
    case Nil{}: Done{Unit{}}
    case Con{head, tail}:
      do Result<&2, &2, String, Unit>:
        checked : Unit <- S.check(Bool.not(proxy_sig_conflict(vm, value, head)), "java/lang/IllegalArgumentException")
        result : Unit <- proxy_sig_check(vm, value, tail)
        return result

def proxy_validate_methods(fuel: Nat, +methods: +List<M.LoadedMethod>, +owners: +List<U32>, +vm: M.VM, +sigs: +List<ProxyMethodSig>) -> Result<&2, &2, String, Unit>:
  match fuel methods:
    case 0n _: Fail{"java/lang/IllegalArgumentException"}
    case 1n+remaining Nil{}: Done{Unit{}}
    case 1n+remaining Con{+method, rest}:
      match method:
        case M.LoadedMethod{+id, +owner, +name, +descriptor, +flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}:
          do Result<&2, &2, String, Unit>:
            +method_name : String = Sy.text(S.symbols(vm), name)
            +descriptor_text : String = Sy.text(S.symbols(vm), descriptor)
            +ordinary : Bool = Bool.not(String.eq(method_name, "<init>")) && Bool.not(String.eq(method_name, "<clinit>"))
            +object_owner : Bool = U32.is_eq(owner, class_id(vm, "java/lang/Object"))
            +instance : Bool = U32.is_eq(U32.and(flags, 8), 0)
            +candidate : Bool = ordinary && Bool.not(object_owner) && instance && U32.is_ne(U32.and(flags, 1), 0) && proxy_id_seen(owners, owner)
            +sig : ProxyMethodSig = ProxyMethodSig{method_name, proxy_descriptor_parameters(String.to_list(descriptor_text), Nil{}), proxy_descriptor_return(String.to_list(descriptor_text))}
            checked : Unit <- Bool.pick(Result<&2, &2, String, Unit>, candidate, proxy_sig_check(vm, sig, sigs), Done{Unit{}})
            +next_sigs : +List<ProxyMethodSig> = Bool.pick(+List<ProxyMethodSig>, candidate, Con{sig, sigs}, sigs)
            result : Unit <- proxy_validate_methods(remaining, rest, owners, vm, next_sigs)
            return result

def proxy_method_signature_equal(left: ProxyMethodSig, right: ProxyMethodSig) -> Bool:
  match left right:
    case ProxyMethodSig{+left_name, +left_parameters, left_result} ProxyMethodSig{+right_name, +right_parameters, right_result}:
      String.eq(left_name, right_name) && String.eq(left_parameters, right_parameters)

def proxy_method_owner_match(+owners: +List<U32>, +classes: +List<M.LoadedClass>, owner: U32, exact: Bool) -> Bool:
  match exact:
    case True{}: proxy_id_seen(owners, owner)
    case False{}: proxy_method_owner_ids(owners, classes, owner)

def proxy_method_candidate(+vm: M.VM, +method: M.LoadedMethod, signature: ProxyMethodSig, +owners: +List<U32>, exact: Bool) -> Bool:
  +owner = M.loaded_method_owner(method)
  +flags = M.loaded_method_flags(method)
  +name = Sy.text(S.symbols(vm), M.loaded_method_name(method))
  +descriptor = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
  +ordinary = Bool.not(String.eq(name, "<init>")) && Bool.not(String.eq(name, "<clinit>"))
  +public = U32.is_ne(U32.and(flags, 1), 0)
  +instance = U32.is_eq(U32.and(flags, 8), 0)
  +object_method = U32.is_eq(owner, class_id(vm, "java/lang/Object"))
  +owner_match = proxy_method_owner_match(owners, S.classes(vm), owner, exact)
  +candidate_sig : ProxyMethodSig = ProxyMethodSig{name, proxy_descriptor_parameters(String.to_list(descriptor), Nil{}), proxy_descriptor_return(String.to_list(descriptor))}
  ordinary && public && instance && Bool.not(object_method) && owner_match && proxy_method_signature_equal(candidate_sig, signature)

def proxy_method_scan_select(candidate: Bool, +method: M.LoadedMethod, next: Unit -> Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match candidate:
    case True{}: Some{method}
    case False{}: next(Unit{})

def proxy_method_scan(fuel: Nat, +methods: +List<M.LoadedMethod>, +vm: M.VM, +owners: +List<U32>, +signature: ProxyMethodSig, +exact: Bool) -> Maybe<&2, M.LoadedMethod>:
  match fuel methods:
    case 0n _: None{}
    case 1n+remaining Nil{}: None{}
    case 1n+remaining Con{+method, rest}:
      proxy_method_scan_select(proxy_method_candidate(vm, method, signature, owners, exact), method, unit => proxy_method_scan(remaining, rest, vm, owners, signature, exact))


def proxy_method_ordered_select(found: Maybe<&2, M.LoadedMethod>, next: Unit -> Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case Some{method}: Some{method}
    case None{}: next(Unit{})

def proxy_method_ordered(fuel: Nat, +owners: +List<U32>, +vm: M.VM, +signature: ProxyMethodSig) -> Maybe<&2, M.LoadedMethod>:
  match fuel owners:
    case 0n _: None{}
    case 1n+remaining Nil{}: None{}
    case 1n+remaining Con{+owner, rest}:
      proxy_method_ordered_select(proxy_method_scan(100000n, S.methods(vm), vm, [owner], signature, True{}), unit => proxy_method_ordered(remaining, rest, vm, signature))

def proxy_method_select_found(found: Maybe<&2, M.LoadedMethod>, fallback: M.LoadedMethod) -> M.LoadedMethod:
  match found:
    case Some{method}: method
    case None{}: fallback

def proxy_method_lookup(object_method: Bool, +owners: +List<U32>, +vm: M.VM, signature: ProxyMethodSig) -> Maybe<&2, M.LoadedMethod>:
  match object_method:
    case True{}: None{}
    case False{}: proxy_method_ordered(100000n, owners, vm, signature)

def proxy_select_method(+vm: M.VM, +owners: +List<U32>, +method: M.LoadedMethod) -> M.LoadedMethod:
  +owner = M.loaded_method_owner(method)
  +signature = proxy_method_sig(vm, method)
  +object_method = U32.is_eq(owner, class_id(vm, "java/lang/Object"))
  found : Maybe<&2, M.LoadedMethod> = proxy_method_lookup(object_method, owners, vm, signature)
  proxy_method_select_found(found, method)

def proxy_instance_interface_ids(+vm: M.VM, reference: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    +array_reference : U32 <- proxy_field(vm, reference, 1)
    +array : M.HeapEntry <- H.get(S.heap(vm), array_reference)
    checked : Unit <- S.check(U32.is_eq(entry_kind(array), 2), "java/lang/IllegalArgumentException")
    ids : +List<U32> <- proxy_interface_ids(100000n, vm, entry_values(array), Nil{})
    return ids

def proxy_method_exception_ids(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    pool : +List<M.Constant> <- proxy_class_pool(S.metadata(vm), M.loaded_method_owner(method))
    raw : +List<U32> <- proxy_metadata_exceptions(S.metadata(vm), M.loaded_method_id(method))
    exceptions : +List<U32> <- proxy_exception_ids(vm, pool, raw, Nil{})
    return exceptions

def proxy_method_exception_group_value(+vm: M.VM, owner: U32, method: U32) -> Result<&2, &2, String, ProxyExceptionGroup>:
  do Result<&2, &2, String, ProxyExceptionGroup>:
    pool : +List<M.Constant> <- proxy_class_pool(S.metadata(vm), owner)
    raw : +List<U32> <- proxy_metadata_exceptions(S.metadata(vm), method)
    exceptions : +List<U32> <- proxy_exception_ids(vm, pool, raw, Nil{})
    return ProxyExceptionGroup{exceptions}

def proxy_method_exception_group_result(result: Result<&2, &2, String, ProxyExceptionGroup>) -> Result<&2, &2, String, Maybe<&2, ProxyExceptionGroup>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{group}: Done{Some{group}}

def proxy_method_exception_group_select(candidate: Bool, +vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, Maybe<&2, ProxyExceptionGroup>>:
  match candidate:
    case True{}: proxy_method_exception_group_result(proxy_method_exception_group_value(vm, M.loaded_method_owner(method), M.loaded_method_id(method)))
    case False{}: Done{None{}}

def proxy_method_exception_group(+vm: M.VM, +method: M.LoadedMethod, signature: ProxyMethodSig, +owners: +List<U32>) -> Result<&2, &2, String, Maybe<&2, ProxyExceptionGroup>>:
  proxy_method_exception_group_select(proxy_method_candidate(vm, method, signature, owners, True{}), vm, method)
def proxy_method_exception_groups_append(found: Maybe<&2, ProxyExceptionGroup>, +groups: +List<U32>) -> +List<U32>:
  match found:
    case None{}: groups
    case Some{ProxyExceptionGroup{+types}}: M.append(U32, types, Con{0, groups})


def proxy_method_exception_groups(fuel: Nat, +methods: +List<M.LoadedMethod>, +owners: +List<U32>, +signature: ProxyMethodSig, +vm: M.VM, +groups: +List<U32>) -> Result<&2, &2, String, +List<U32>>:
  match fuel methods:
    case 0n _: Fail{"java/lang/IllegalArgumentException"}
    case 1n+remaining Nil{}: Done{groups}
    case 1n+remaining Con{+method, rest}:
      do Result<&2, &2, String, +List<U32>>:
        found : Maybe<&2, ProxyExceptionGroup> <- proxy_method_exception_group(vm, method, signature, owners)
        next : +List<U32> = proxy_method_exception_groups_append(found, groups)
        result : +List<U32> <- proxy_method_exception_groups(remaining, rest, owners, signature, vm, next)
        return result

def proxy_exception_groups_result(groups: +List<U32>, +fallback: +List<U32>) -> +List<U32>:
  match groups:
    case Nil{}: Con{0, fallback}
    case Con{head, rest}: Con{head, rest}

def proxy_exception_policy(+vm: M.VM, method_id: U32, +owners: +List<U32>) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    +selected : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), method_id), "java/lang/IllegalArgumentException")
    signature : ProxyMethodSig = proxy_method_sig(vm, selected)
    groups : +List<U32> <- proxy_method_exception_groups(100000n, S.methods(vm), owners, signature, vm, Nil{})
    fallback : +List<U32> <- proxy_method_exception_ids(vm, selected)
    exceptions : +List<U32> = proxy_exception_groups_result(groups, fallback)
    return exceptions


def proxy_call_plan(+vm: M.VM, +owners: +List<U32>, method: M.LoadedMethod) -> Result<&2, &2, String, ProxyCallPlan>:
  do Result<&2, &2, String, ProxyCallPlan>:
    +selected : M.LoadedMethod = proxy_select_method(vm, owners, method)
    allocation : H.Allocation <- H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/Method"), [M.Binding{0, M.Slot{1, M.loaded_method_owner(selected)}}, M.Binding{1, M.Slot{1, M.loaded_method_id(selected)}}, M.Binding{2, M.Slot{1, 0}}]))
    return ProxyCallPlan{allocation, M.loaded_method_id(selected), owners}

def proxy_call_plan_ready(plan: ProxyCallPlan, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, +descriptor: String, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match plan:
    case ProxyCallPlan{+allocation, method, +owners}: proxy_call_method_alloc(allocation, handler, proxy, handler_method, descriptor, method, owners, values)

def proxy_call_ready(+vm: M.VM, +handler: U32, +proxy: U32, method: M.LoadedMethod, +descriptor: String, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    handler_method : M.LoadedMethod <- proxy_handler_method(vm, handler)
    +interfaces : +List<U32> <- proxy_instance_interface_ids(vm, proxy)
    +reverse_owners : +List<U32> <- proxy_interface_owners(100000n, interfaces, S.classes(vm), Nil{})
    +owners : +List<U32> = M.reverse(U32, reverse_owners)
    plan : ProxyCallPlan <- proxy_call_plan(vm, owners, method)
    result : O.Outcome <- proxy_call_plan_ready(plan, handler, proxy, handler_method, descriptor, values)
    return result


def proxy_cache_slot_bits(found: Maybe<&2, M.Slot>) -> U32:
  match found:
    case None{}: 0
    case Some{slot}: M.slot_bits(slot)

def proxy_catalog_found(found: Maybe<&2, M.Slot>) -> Maybe<&2, U32>:
  match found:
    case None{}: None{}
    case Some{slot}: Some{M.slot_bits(slot)}


def proxy_slots_equal(left: +List<M.Slot>, right: +List<M.Slot>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{M.Slot{left_tag, left_bits}, left_rest} Con{M.Slot{right_tag, right_bits}, right_rest}:
      U32.is_eq(left_tag, right_tag) && U32.is_eq(left_bits, right_bits) && proxy_slots_equal(left_rest, right_rest)
    case Con{M.Wide{left_tag, left_high, left_low}, left_rest} Con{M.Wide{right_tag, right_high, right_low}, right_rest}:
      U32.is_eq(left_tag, right_tag) && U32.is_eq(left_high, right_high) && U32.is_eq(left_low, right_low) && proxy_slots_equal(left_rest, right_rest)
    case Con{M.Unusable{}, left_rest} Con{M.Unusable{}, right_rest}: proxy_slots_equal(left_rest, right_rest)
    case _ _: False{}

def proxy_cache_node_match(+vm: M.VM, reference: U32, loader: U32, +values: +List<M.Slot>) -> Result<&2, &2, String, Bool>:
  do Result<&2, &2, String, Bool>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 0), "java/lang/IllegalArgumentException")
    +node_loader : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), 0), "java/lang/IllegalArgumentException")
    +node_array : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), 1), "java/lang/IllegalArgumentException")
    +array : M.HeapEntry <- H.get(S.heap(vm), bits_of(node_array))
    array_checked : Unit <- S.check(U32.is_eq(entry_kind(array), 2), "java/lang/IllegalArgumentException")
    return U32.is_eq(bits_of(node_loader), loader) && proxy_slots_equal(entry_values(array), values)

def proxy_cache_lookup_continue(fuel: Nat, +vm: M.VM, +head: U32, +loader: U32, +values: +List<M.Slot>) -> Result<&2, &2, String, Maybe<&2, U32>>:
  match fuel:
    case 0n: Done{None{}}
    case 1n+remaining:
      Bool.pick(Result<&2, &2, String, Maybe<&2, U32>>, U32.is_eq(head, 0), Done{None{}},
        do Result<&2, &2, String, Maybe<&2, U32>>:
          same : Bool <- proxy_cache_node_match(vm, head, loader, values)
          +entry : M.HeapEntry <- H.get(S.heap(vm), head)
          +next_slot : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), 3), "java/lang/IllegalArgumentException")
          +next : U32 = bits_of(next_slot)
          result : Maybe<&2, U32> <- Bool.pick(Result<&2, &2, String, Maybe<&2, U32>>, same, Done{Some{head}}, proxy_cache_lookup_continue(remaining, vm, next, loader, values))
          return result
      )

def proxy_cache_lookup(fuel: Nat, +vm: M.VM, head: U32, +loader: U32, +values: +List<M.Slot>) -> Result<&2, &2, String, Maybe<&2, U32>>:
  match fuel:
    case 0n: Done{None{}}
    case 1n+remaining: proxy_cache_lookup_continue(remaining, vm, head, loader, values)

def proxy_cache_node_result(result: Result<&2, &2, String, H.Allocation>, +class_id_value: U32, key: U32) -> Result<&2, &2, String, ProxyClassResult>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, +reference}}:
      +updated : M.VM = S.with_statics(vm, proxy_binding_set(S.statics(vm), key, M.Slot{3, reference}))
      Done{ProxyClassResult{updated, class_id_value}}

def proxy_catalog_append(+vm: M.VM, +ids: +List<U32>, key: U32, loader: U32, interface_array: U32, head: U32) -> Result<&2, &2, String, ProxyClassResult>:
  do Result<&2, &2, String, ProxyClassResult>:
    +class_id_value : U32 = M.length(M.LoadedClass, S.classes(vm))
    +name : String = "$Proxy" ++ V.int_show(class_id_value)
    +symbol_id : U32 = M.length(String, S.symbols(vm))
    +proxy_class : M.LoadedClass = M.LoadedClass{class_id_value, symbol_id, class_id(vm, "java/lang/reflect/Proxy"), ids, Nil{}, Nil{}, 4294967295, 0, Nil{}}
    +symbols : +List<String> = M.append(String, S.symbols(vm), [name])
    +with_symbols : M.VM = S.with_symbols(vm, symbols)
    +classes : +List<M.LoadedClass> = M.append(M.LoadedClass, S.classes(with_symbols), [proxy_class])
    +with_classes : M.VM = S.with_classes(with_symbols, classes)
    +node : M.HeapEntry = H.object_entry(class_id(vm, "java/lang/reflect/Proxy"), [M.Binding{0, M.Slot{1, loader}}, M.Binding{1, M.Slot{3, interface_array}}, M.Binding{2, M.Slot{1, class_id_value}}, M.Binding{3, M.Slot{3, head}}])
    result : ProxyClassResult <- proxy_cache_node_result(H.allocate(with_classes, node), class_id_value, key)
    return result

def proxy_catalog_uncached(+vm: M.VM, +ids: +List<U32>, key: U32, loader: U32, interface_array: U32, head: U32) -> Result<&2, &2, String, ProxyClassResult>:
  do Result<&2, &2, String, ProxyClassResult>:
    +owners : +List<U32> <- proxy_interface_owners(100000n, ids, S.classes(vm), Nil{})
    method_validation : Unit <- proxy_validate_methods(100000n, S.methods(vm), owners, vm, Nil{})
    result : ProxyClassResult <- proxy_catalog_append(vm, ids, key, loader, interface_array, head)
    return result

def proxy_catalog_found_result(+vm: M.VM, +ids: +List<U32>, key: U32, loader: U32, interface_array: U32, head: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, ProxyClassResult>:
  match found:
    case Some{reference}:
      do Result<&2, &2, String, ProxyClassResult>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        +class_slot : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), 2), "java/lang/IllegalArgumentException")
        return ProxyClassResult{vm, bits_of(class_slot)}
    case None{}: proxy_catalog_uncached(vm, ids, key, loader, interface_array, head)

def proxy_catalog(+vm: M.VM, +loader: U32, +interface_array: U32) -> Result<&2, &2, String, ProxyClassResult>:
  do Result<&2, &2, String, ProxyClassResult>:
    +array : M.HeapEntry <- H.get(S.heap(vm), interface_array)
    checked : Unit <- S.check(U32.is_eq(entry_kind(array), 2), "java/lang/IllegalArgumentException")
    +ids : +List<U32> <- proxy_interface_ids(256n, vm, entry_values(array), Nil{})
    validation : Unit <- proxy_validate_ids(ids, vm, S.metadata(vm), Nil{}, False{}, "")
    +key : U32 = proxy_cache_key(loader, entry_values(array))
    +head : U32 = proxy_cache_slot_bits(H.binding_find(S.statics(vm), key))
    found : Maybe<&2, U32> <- proxy_cache_lookup(100000n, vm, head, loader, entry_values(array))
    result : ProxyClassResult <- proxy_catalog_found_result(vm, ids, key, loader, interface_array, head, found)
    return result

def proxy_mirror_key(class_id_value: U32) -> U32:
  U32.add(1610612736, class_id_value)

def proxy_mirror_result(result: Result<&2, &2, String, H.Allocation>, key: U32, +slot: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, +reference}}:
      +statics : +List<M.Binding> = S.statics(vm)
      +updated : M.VM = S.with_statics(vm, proxy_binding_set(statics, key, M.Slot{3, reference}))
      ref_out(updated, reference)

def proxy_mirror_found(+vm: M.VM, +class_id_value: U32, +interfaces: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{reference}: ref_out(vm, reference)
    case None{}:
      proxy_mirror_result(H.allocate(vm, M.HeapEntry{class_id(vm, "java/lang/Class"), 8, class_id_value, [M.Binding{0, M.Slot{3, interfaces}}], Nil{}, Nil{}}), proxy_mirror_key(class_id_value), M.Slot{3, interfaces})

def proxy_class_mirror_cached(+vm: M.VM, +class_id_value: U32, +interfaces: U32) -> Result<&2, &2, String, O.Outcome>:
  +key : U32 = proxy_mirror_key(class_id_value)
  found : Maybe<&2, M.Slot> = H.binding_find(S.statics(vm), key)
  proxy_mirror_found(vm, class_id_value, interfaces, proxy_catalog_found(found))

def proxy_class_id_found(found: Maybe<&2, M.Slot>, fallback: U32) -> U32:
  match found:
    case None{}: fallback
    case Some{slot}: M.slot_bits(slot)

def proxy_class_id(+vm: M.VM, reference: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    return proxy_class_id_found(H.binding_find(entry_fields(entry), 2), class_id(vm, "java/lang/reflect/Proxy"))

def proxy_class_mirror(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    interfaces : U32 <- proxy_field(vm, reference, 1)
    class_id_value : U32 <- proxy_class_id(vm, reference)
    result : O.Outcome <- proxy_class_mirror_cached(vm, class_id_value, interfaces)
    return result

def proxy_invoke_target(+vm: M.VM, +method: M.LoadedMethod, +values: +List<M.Slot>, +reference: U32, +descriptor: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    handler : U32 <- proxy_field(vm, reference, 0)
    result : O.Outcome <- proxy_call_ready(vm, handler, reference, method, descriptor, values)
    return result

def proxy_invoke(+vm: M.VM, +method: M.LoadedMethod, +values: +List<M.Slot>, +name: String, +desc: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    proxy : M.Slot <- slot0(values)
    +reference : U32 = bits_of(proxy)
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 10), "java/lang/IllegalArgumentException")
    result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>,
      String.eq(name, "getClass") && String.eq(desc, "()Ljava/lang/Class;"),
      proxy_class_mirror(vm, reference),
      proxy_invoke_target(vm, method, values, reference, desc))
    return result

def proxy_instance_alloc(catalog: ProxyClassResult, handler: M.Slot, interfaces: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match catalog:
    case ProxyClassResult{+vm, +classId}:
      alloc_result(H.allocate(vm, M.HeapEntry{classId, 10, 0, [M.Binding{0, handler}, M.Binding{1, interfaces}, M.Binding{2, M.Slot{1, classId}}], Nil{}, Nil{}}), vm2 => reference => ref_out(vm2, reference))

def proxy_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +handler : M.Slot <- slot1(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(handler), 0), npe())
    +reference : U32 = bits_of(receiver)
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    kind_checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 10), "java/lang/IllegalArgumentException")
    result : O.Outcome <- void_out(H.put(vm, reference, M.HeapEntry{H.entry_class(entry), entry_kind(entry), entry_element(entry), proxy_binding_set(entry_fields(entry), 0, handler), entry_values(entry), entry_chars(entry)}))
    return result
def proxy_constructor_clone(method: M.LoadedMethod, owner: U32) -> M.LoadedMethod:
  match method:
    case M.LoadedMethod{id, old_owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}:
      M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}

def proxy_constructor_base(+vm: M.VM) -> Result<&2, &2, String, M.LoadedMethod>:
  S.require(M.LoadedMethod, proxy_own_method(S.methods(vm), S.symbols(vm), class_id(vm, "java/lang/reflect/Proxy"), "<init>", "(Ljava/lang/reflect/InvocationHandler;)V"), "java/lang/NoSuchMethodException")

def proxy_constructor_method(+vm: M.VM, owner: U32) -> Result<&2, &2, String, M.LoadedMethod>:
  do Result<&2, &2, String, M.LoadedMethod>:
    base : M.LoadedMethod <- proxy_constructor_base(vm)
    return proxy_constructor_clone(base, owner)

def proxy_class_parent_proxy(found: Maybe<&2, M.LoadedClass>, proxy: U32) -> Bool:
  match found:
    case None{}: False{}
    case Some{class}: U32.is_eq(M.loaded_class_parent(class), proxy)

def proxy_class_is_synthetic(+vm: M.VM, target: U32) -> Bool:
  proxy_class_parent_proxy(M.nth(M.LoadedClass, S.classes(vm), target), class_id(vm, "java/lang/reflect/Proxy"))
def proxy_constructor_member(+vm: M.VM, +owner: U32, +method: M.LoadedMethod) -> M.LoadedMethod:
  Bool.pick(M.LoadedMethod, proxy_class_is_synthetic(vm, owner), proxy_constructor_clone(method, owner), method)

def proxy_get_class_result(catalog: ProxyClassResult, interfaces: U32) -> Result<&2, &2, String, O.Outcome>:
  match catalog:
    case ProxyClassResult{+vm, classId}: proxy_class_mirror_cached(vm, classId, interfaces)

def proxy_new_instance(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    loader : M.Slot <- slot0(args)
    +interfaces : M.Slot <- slot1(args)
    +handler : M.Slot <- slot2(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(handler), 0), npe())
    catalog : ProxyClassResult <- proxy_catalog(vm, bits_of(loader), bits_of(interfaces))
    result : O.Outcome <- proxy_instance_alloc(catalog, handler, interfaces)
    return result

def proxy_get_proxy_class(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    loader : M.Slot <- slot0(args)
    +interfaces : M.Slot <- slot1(args)
    catalog : ProxyClassResult <- proxy_catalog(vm, bits_of(loader), bits_of(interfaces))
    result : O.Outcome <- proxy_get_class_result(catalog, bits_of(interfaces))
    return result


def proxy_is_proxy_class(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    mirror : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(mirror))
    result : O.Outcome <- bool_out(vm, U32.is_eq(entry_kind(entry), 8) && proxy_class_is_synthetic(vm, entry_element(entry)))
    return result

def proxy_get_invocation_handler(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 10), "java/lang/IllegalArgumentException")
    handler : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), 0), "java/lang/IllegalArgumentException")
    result : O.Outcome <- returned(vm, Some{handler})
    return result
def class_binary_name(+name: String) -> String:
  match name:
    case SNil{}: ""
    case SCon{Chr{46}, rest}: SCon{Chr{47}, class_binary_name(rest)}
    case SCon{unit, rest}: SCon{unit, class_binary_name(rest)}

def class_name_result(+vm: M.VM, +name: String) -> Result<&2, &2, String, O.Outcome>:
  +binary_name = class_binary_name(name)
  +target : U32 = class_id(vm, binary_name)
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(target, 4294967295), throw_name(vm, "java/lang/ClassNotFoundException"), class_mirror_out(vm, target))


type ClassForNameStart is Data:
  ClassForNameReady{vm: M.VM}
  ClassForNameCall{vm: M.VM, target: U32, method: M.LoadedMethod}
  # Another thread is running `class`'s initializer: wait for it (JVMS 5.5 step 2).
  ClassForNameBlocked{vm: M.VM, class: U32}

def system_loader_reference() -> U32:
  14

def bootstrap_name(classes: +List<M.ClassFile>, +name: String) -> Bool:
  match classes:
    case Nil{}: False{}
    case Con{class, rest}: String.eq(CL.class_internal_name(class), name) || bootstrap_name(rest, name)

def class_bootstrap_name(name: String) -> Bool:
  match name:
    case SCon{Chr{91}, rest}:
      match rest:
        case SCon{Chr{91}, tail}: class_bootstrap_name(rest)
        case SCon{Chr{76}, tail}: bootstrap_name(B.classes(), CL.take_until_semicolon(tail, ""))
        case _: True{}
    case _: bootstrap_name(B.classes(), name)

def class_bootstrap_target(+vm: M.VM, target: U32) -> Bool:
  class_bootstrap_name(class_name_text(vm, target))

def class_loader_allowed(+vm: M.VM, +target: U32, +loader: U32) -> Bool:
  U32.is_eq(loader, system_loader_reference()) || (U32.is_eq(loader, 0) && class_bootstrap_target(vm, target))

def class_for_name_args(+args: +List<M.Slot>) -> Result<&2, &2, String, ClassForNameArgs>:
  match args:
    case Con{name, Con{flag, Con{loader, rest}}}: Done{ClassForNameArgs{name, U32.is_ne(bits_of(flag), 0), bits_of(loader)}}
    case Con{name, Nil{}}: Done{ClassForNameArgs{name, True{}, system_loader_reference()}}
    case _: Fail{"InvalidState: intrinsic argument count"}

@unsafe def internal_to_binary(name: String) -> String:
  class_display_name(name)

def init_failed(+vm: M.VM, id: U32) -> String:
  "java/lang/NoClassDefFoundError: Could not initialize class " ++ internal_to_binary(class_name_text(vm, id))

# Interface methods that are neither abstract nor static are default methods.
def default_method(found: Maybe<&2, M.LoadedMethod>) -> Bool:
  match found:
    case None{}: False{}
    case Some{method}: U32.is_eq(U32.and(M.loaded_method_flags(method), 1032), 0)

@unsafe def declares_default_hit(hit: Bool, +methods: +List<M.LoadedMethod>, ids: +List<U32>) -> Bool:
  match hit:
    case True{}: True{}
    case False{}: declares_default(methods, ids)

@unsafe def declares_default(+methods: +List<M.LoadedMethod>, ids: +List<U32>) -> Bool:
  match ids:
    case Nil{}: False{}
    case Con{id, rest}: declares_default_hit(default_method(M.nth(M.LoadedMethod, methods, id)), methods, rest)

def default_self(declares: Bool, id: U32) -> +List<U32>:
  match declares:
    case True{}: Con{id, Nil{}}
    case False{}: Nil{}

@unsafe def default_interface(fuel: Nat, +vm: M.VM, found: Maybe<&2, M.LoadedClass>) -> +List<U32>:
  match found:
    case None{}: Nil{}
    case Some{M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods}}:
      M.append(U32, default_interfaces(fuel, vm, interfaces), default_self(declares_default(S.methods(vm), methods), id))

# For each direct superinterface in declaration order: its own qualifying
# superinterfaces, then itself when it declares a default method (HotSpot's
# initialize_super_interfaces, JDK 8u40 and later).
@unsafe def default_interfaces(fuel: Nat, +vm: M.VM, ids: +List<U32>) -> +List<U32>:
  match fuel ids:
    case 0n _: Nil{}
    case 1n+p Nil{}: Nil{}
    case 1n+ +p Con{id, rest}: M.append(U32, default_interface(p, vm, M.nth(M.LoadedClass, S.classes(vm), id)), default_interfaces(p, vm, rest))

# Classes initialized before a class: its superclass, then superinterfaces that
# declare default methods. Interfaces (no superclass here) initialize alone.
def init_supers(fuel: Nat, +vm: M.VM, parent: U32, interfaces: +List<U32>) -> +List<U32>:
  match parent:
    case 4294967295: Nil{}
    case value: Con{value, default_interfaces(fuel, vm, interfaces)}

def init_walk_self(+vm: M.VM, id: U32, initializer: U32) -> Result<&2, &2, String, ClassForNameStart>:
  match initializer:
    case 4294967295: Done{ClassForNameReady{S.set_class_state(vm, id, 2)}}
    case method_id:
      do Result<&2, &2, String, ClassForNameStart>:
        method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), method_id), "java/lang/NoSuchMethodError: <clinit>")
        return ClassForNameCall{vm, id, method}

@unsafe def init_walk_step(result: Result<&2, &2, String, ClassForNameStart>, +fuel: Nat, id: U32, initializer: U32, supers: +List<U32>) -> Result<&2, &2, String, ClassForNameStart>:
  match result:
    case Fail{error}: Fail{error}
    case Done{ClassForNameCall{+vm, target, +method}}: Done{ClassForNameCall{vm, target, method}}
    case Done{ClassForNameBlocked{+vm, class}}: Done{ClassForNameBlocked{vm, class}}
    case Done{ClassForNameReady{+vm}}: init_walk_supers(fuel, vm, id, initializer, supers)

@unsafe def init_walk_supers(+fuel: Nat, +vm: M.VM, id: U32, initializer: U32, supers: +List<U32>) -> Result<&2, &2, String, ClassForNameStart>:
  match supers:
    case Nil{}: init_walk_self(vm, id, initializer)
    case Con{super, rest}: init_walk_step(class_for_name_walk(fuel, vm, super), fuel, id, initializer, rest)

# A user-defined class is verified when it is first linked (JVMS 5.4.1).
@unsafe def init_walk_verified(result: Result<&2, &2, String, M.VM>, +fuel: Nat, id: U32, initializer: U32, parent: U32, interfaces: +List<U32>) -> Result<&2, &2, String, ClassForNameStart>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+vm}: init_walk_supers(fuel, vm, id, initializer, init_supers(fuel, vm, parent, interfaces))

# State 1 (initializing): a recursive request from the initializing thread
# proceeds and observes default values (JVMS 5.5 step 3); any other thread
# waits until the initializer finishes or fails (step 2).
def init_walk_initializing(+vm: M.VM, +id: U32, +owner: U32) -> Result<&2, &2, String, ClassForNameStart>:
  Bool.pick(Result<&2, &2, String, ClassForNameStart>, U32.is_eq(owner, Th.current(vm)) || U32.is_eq(owner, 0), Done{ClassForNameReady{vm}}, Done{ClassForNameBlocked{vm, id}})

@unsafe def init_walk_class(+fuel: Nat, +vm: M.VM, found: Maybe<&2, M.LoadedClass>) -> Result<&2, &2, String, ClassForNameStart>:
  match found:
    case None{}: Fail{"java/lang/ClassNotFoundException"}
    case Some{M.LoadedClass{+id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods}}:
      match state:
        case 0: init_walk_verified(LS.verify_pending(vm, id), fuel, id, initializer, parent, interfaces)
        case 3: Fail{init_failed(vm, id)}
        case 1: init_walk_initializing(vm, id, S.init_owner(vm, id))
        case _: Done{ClassForNameReady{vm}}

# JVMS 5.5: the next initializer that must run before `target` is initialized,
# or Ready once every superclass, qualifying superinterface and the class itself
# are initialized. Callers run the returned <clinit> and re-execute their trigger.
@unsafe def class_for_name_walk(fuel: Nat, +vm: M.VM, +target: U32) -> Result<&2, &2, String, ClassForNameStart>:
  match fuel target:
    case _ 4294967295: Done{ClassForNameReady{vm}}
    case 0n _: Fail{"java/lang/NoClassDefFoundError"}
    case 1n+remaining id: init_walk_class(remaining, vm, M.nth(M.LoadedClass, S.classes(vm), id))

# Starts the next <clinit> as a Java callback; `cont` resumes the requester
# when that initializer returns.
@unsafe def init_call(+vm: M.VM, owner: U32, method: M.LoadedMethod, cont: M.Cont) -> O.Outcome:
  O.Call{push_cont(S.set_class_state(vm, owner, 1), cont), method, Nil{}}

@unsafe def class_for_name_initialized(start: ClassForNameStart, target: U32) -> Result<&2, &2, String, O.Outcome>:
  match start:
    case ClassForNameReady{+vm}: class_mirror_out(vm, target)
    case ClassForNameCall{+vm, owner, +method}: Done{init_call(vm, owner, method, M.NeedClassMirror{target})}
    case ClassForNameBlocked{+vm, class}: Done{init_park(vm, class, M.NeedClassMirror{target})}

# Class.forName with initialize=true runs every pending initializer in JVMS 5.5
# order (one callback each) before returning the mirror.
@unsafe def class_for_name_init(+vm: M.VM, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    start : ClassForNameStart <- class_for_name_walk(256n, vm, target)
    result : O.Outcome <- class_for_name_initialized(start, target)
    return result

def class_for_name_loaded_state(+vm: M.VM, shouldInit: Bool, +id: U32) -> Result<&2, &2, String, O.Outcome>:
  match shouldInit:
    case True{}: class_for_name_init(vm, id)
    case False{}: class_mirror_out(vm, id)

def class_for_name_loaded(+vm: M.VM, +shouldInit: Bool, +class: M.LoadedClass) -> Result<&2, &2, String, O.Outcome>:
  class_for_name_loaded_state(vm, shouldInit, M.loaded_class_id(class))

def class_for_name_target(+vm: M.VM, target: U32, shouldInit: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), target), "java/lang/ClassNotFoundException")
    result : O.Outcome <- class_for_name_loaded(vm, shouldInit, class)
    return result

def binary_segments(text: String, +segment: Bool) -> Bool:
  match text:
    case SNil{}: segment
    case SCon{Chr{46}, rest}: segment && binary_segments(rest, False{})
    case SCon{Chr{47}, rest}: False{}
    case SCon{Chr{59}, rest}: False{}
    case SCon{Chr{91}, rest}: False{}
    case SCon{unit, rest}: binary_segments(rest, True{})

def valid_array_object(text: String, +acc: String) -> Bool:
  match text:
    case SCon{Chr{59}, SNil{}}: binary_segments(acc, False{})
    case SNil{}: False{}
    case SCon{unit, rest}: valid_array_object(rest, acc ++ Char.show(unit))

def valid_array_name(text: String) -> Bool:
  match text:
    case SCon{Chr{91}, rest}: valid_array_name(rest)
    case SCon{Chr{76}, rest}: valid_array_object(rest, "")
    case "Z": True{}
    case "B": True{}
    case "C": True{}
    case "S": True{}
    case "I": True{}
    case "J": True{}
    case "F": True{}
    case "D": True{}
    case _: False{}

def valid_for_name(+text: String) -> Bool:
  match text:
    case SCon{Chr{91}, rest}: valid_array_name(rest)
    case "boolean": False{}
    case "byte": False{}
    case "char": False{}
    case "short": False{}
    case "int": False{}
    case "long": False{}
    case "float": False{}
    case "double": False{}
    case "void": False{}
    case _: binary_segments(text, False{})

def ensure_array_class(+vm: M.VM, +name: String) -> Result<&2, &2, String, M.VM>:
  CL.ensure_array_class(vm, name)

# The bootstrap and system loaders never see classes user loaders defined.
@unsafe def system_visible(+vm: M.VM, +id: U32) -> Bool:
  U32.is_ne(id, 4294967295) && system_defined(LS.defining_loader_of(vm, id))

@unsafe def system_defined(found: Maybe<&2, U32>) -> Bool:
  match found:
    case None{}: True{}
    case Some{loader}: U32.is_eq(loader, system_loader_reference())

@unsafe def class_resolve_runtime(+vm: M.VM, +name: String, +shouldInit: Bool, +loader: U32) -> Result<&2, &2, String, O.Outcome>:
  +component : String = CL.loadable_name(name)
  +missing : Bool = Bool.not(String.is_empty(component)) && Bool.not(system_visible(vm, class_id(vm, component)))
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(U32.is_eq(loader, system_loader_reference()) || (U32.is_eq(loader, 0) && class_bootstrap_name(name)), "java/lang/ClassNotFoundException")
    result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, missing,
      Done{O.Suspend{S.with_status(S.with_effect(vm, M.RuntimeClass{name, shouldInit, loader}), 5), M.RuntimeClass{name, shouldInit, loader}}},
      do Result<&2, &2, String, O.Outcome>:
        +ready : M.VM <- ensure_array_class(vm, name)
        result : O.Outcome <- class_for_name_target(ready, class_id(ready, name), shouldInit && Bool.not(String.starts_with(name, "[")))
        return result)
    return result

def class_for_name_ready(+vm: M.VM, result: Result<&2, &2, String, ClassForNameArgs>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{ClassForNameArgs{+name, shouldInit, loader}}:
      do Result<&2, &2, String, O.Outcome>:
        +name_text : String <- string_text(vm, bits_of(name))
        checked : Unit <- S.check(valid_for_name(name_text), "java/lang/ClassNotFoundException")
        result : O.Outcome <- class_resolve_runtime(vm, class_binary_name(name_text), shouldInit, loader)
        return result

def class_for_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  class_for_name_ready(vm, class_for_name_args(args))

def class_loader_system(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  ref_out(vm, system_loader_reference())

def class_loader_load(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- slot1(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(receiver), 0), "java/lang/ClassNotFoundException")
    +name : String <- string_text(vm, bits_of(value))
    checked_name : Unit <- S.check(valid_for_name(name) && Bool.not(String.starts_with(name, "[")), "java/lang/ClassNotFoundException")
    result : O.Outcome <- class_resolve_runtime(vm, class_binary_name(name), False{}, bits_of(receiver))
    return result

# A user-defined class reports its defining loader; otherwise bootstrap
# classes report null and application classes the system loader.
@unsafe def class_loader_of_target(found: Maybe<&2, U32>, +vm: M.VM, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{loader}: ref_out(vm, loader)
    case None{}: Bool.pick(Result<&2, &2, String, O.Outcome>, class_bootstrap_target(vm, target), ref_out(vm, 0), ref_out(vm, system_loader_reference()))

@unsafe def class_get_loader(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    mirror : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(mirror))
    checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 8), "java/lang/IllegalArgumentException")
    +target : U32 = entry_element(entry)
    result : O.Outcome <- class_loader_of_target(LS.defining_loader_of(vm, target), vm, target)
    return result
def resource_match_name(+resource: M.Resource, +name: String) -> Bool:
  M.Resource{+resource_name, +origin} = resource
  String.eq(resource_name, name)

def resource_match_exact(resource: M.Resource, +name: String, +origin: String) -> Bool:
  M.Resource{resource_name, resource_origin} = resource
  String.eq(resource_name, name) && String.eq(resource_origin, origin)

def resource_find_name(resources: +List<M.Resource>, +name: String) -> Maybe<&2, M.Resource>:
  match resources:
    case Nil{}: None{}
    case Con{+resource, rest}:
      Bool.pick(Maybe<&2, M.Resource>, resource_match_name(resource, name), Some{resource}, resource_find_name(rest, name))

def resource_find_exact(resources: +List<M.Resource>, +name: String, +origin: String) -> Maybe<&2, M.Resource>:
  match resources:
    case Nil{}: None{}
    case Con{+resource, rest}:
      Bool.pick(Maybe<&2, M.Resource>, resource_match_exact(resource, name, origin), Some{resource}, resource_find_exact(rest, name, origin))

def resource_url_object(+vm: M.VM, +name: String, +origin: String, +name_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  +url_class : U32 = class_id(vm, "java/net/URL")
  alloc_result(H.allocate(vm, H.string_entry(class_id(vm, "java/lang/String"), units_from_string(origin))), vm2 => origin_ref => alloc_result(H.allocate(vm2, H.object_entry(url_class, [M.Binding{0, M.Slot{3, name_ref}}, M.Binding{1, M.Slot{3, origin_ref}}])), vm3 => reference => ref_out(vm3, reference)))
def resource_alloc_ok(allocation: H.Allocation, cont: M.VM -> U32 -> Result<&2, &2, String, ResourceRefs>) -> Result<&2, &2, String, ResourceRefs>:
  match allocation:
    case H.Allocation{vm, reference}: cont(vm, reference)

def resource_alloc_result(result: Result<&2, &2, String, H.Allocation>, cont: M.VM -> U32 -> Result<&2, &2, String, ResourceRefs>) -> Result<&2, &2, String, ResourceRefs>:
  match result:
    case Fail{error}: Fail{error}
    case Done{allocation}: resource_alloc_ok(allocation, cont)

def resource_url_reference(+vm: M.VM, +name: String, +origin: String, cont: M.VM -> U32 -> Result<&2, &2, String, ResourceRefs>) -> Result<&2, &2, String, ResourceRefs>:
  resource_alloc_result(H.allocate(vm, H.string_entry(class_id(vm, "java/lang/String"), units_from_string(name))), +vm2 => name_ref => resource_alloc_result(H.allocate(vm2, H.string_entry(class_id(vm2, "java/lang/String"), units_from_string(origin))), +vm3 => origin_ref => resource_alloc_result(H.allocate(vm3, H.object_entry(class_id(vm3, "java/net/URL"), [M.Binding{0, M.Slot{3, name_ref}}, M.Binding{1, M.Slot{3, origin_ref}}])), +vm4 => reference => cont(vm4, reference))))
def resource_url_refs_select(matched: Bool, yes: Unit -> Result<&2, &2, String, ResourceRefs>, no: Unit -> Result<&2, &2, String, ResourceRefs>) -> Result<&2, &2, String, ResourceRefs>:
  match matched:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})


@unsafe def resource_url_refs(fuel: Nat, +vm: M.VM, +resources: +List<M.Resource>, +acc: +List<U32>, +name: String) -> Result<&2, &2, String, ResourceRefs>:
  match fuel resources:
    case 0n _:
      Done{ResourceRefs{vm, M.reverse(U32, acc)}}
    case 1n+ +p Nil{}:
      Done{ResourceRefs{vm, M.reverse(U32, acc)}}
    case 1n+ +p Con{+resource, rest}:
      match resource:
        case M.Resource{+resource_name, +origin}:
          +matched : Bool = String.eq(resource_name, name)
          resource_url_refs_select(matched,
            unit => resource_url_reference(vm, resource_name, origin, +vm2 => reference => resource_url_refs(p, vm2, rest, Con{reference, acc}, name)),
            unit => resource_url_refs(p, vm, rest, acc, name))
def resource_ref_slots(refs: +List<U32>) -> +List<M.Slot>:
  match refs:
    case Nil{}: Nil{}
    case Con{reference, rest}: Con{M.Slot{3, reference}, resource_ref_slots(rest)}

def resource_refs_enumeration(value: ResourceRefs) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case ResourceRefs{+vm, +refs}:
      +count : U32 = M.length(U32, refs)
      alloc_result(H.allocate(vm, H.list_entry(class_id(vm, "java/util/ArrayList"), resource_ref_slots(refs), count, 0)), +vm2 => list_ref => alloc_result(H.allocate(vm2, H.object_entry(class_id(vm2, "java/util/ResourceEnumeration"), [M.Binding{0, M.Slot{3, list_ref}}, M.Binding{1, M.Slot{1, 0}}])), +vm3 => reference => ref_out(vm3, reference)))

def resource_url_found(+vm: M.VM, found: Maybe<&2, M.Resource>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: returned(vm, Some{M.Slot{3, 0}})
    case Some{resource}:
      match resource:
        case M.Resource{+resource_name, +origin}:
          alloc_result(H.allocate(vm, H.string_entry(class_id(vm, "java/lang/String"), units_from_string(resource_name))), vm2 => name_ref => resource_url_object(vm2, resource_name, origin, name_ref))

def class_loader_resource(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot0(args)
    name : String <- string_text(vm, bits_of(value))
    result : O.Outcome <- resource_url_found(vm, resource_find_name(S.resources(vm), name))
    return result
def resource_enumeration(+vm: M.VM, +name: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    refs : ResourceRefs <- resource_url_refs(100000n, vm, S.resources(vm), Nil{}, name)
    result : O.Outcome <- resource_refs_enumeration(refs)
    return result

def class_loader_resources(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot0(args)
    name : String <- string_text(vm, bits_of(value))
    result : O.Outcome <- resource_enumeration(vm, name)
    return result

def class_loader_instance_resources(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot1(args)
    name : String <- string_text(vm, bits_of(value))
    result : O.Outcome <- resource_enumeration(vm, name)
    return result


def resource_stream_found(+vm: M.VM, found: Maybe<&2, M.Resource>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: returned(vm, Some{M.Slot{3, 0}})
    case Some{resource}:
      match resource:
        case M.Resource{+resource_name, +origin}:
          Done{O.Suspend{S.with_status(S.with_effect(vm, M.ReadResource{resource_name, origin}), 5), M.ReadResource{resource_name, origin}}}
def resource_segment_pop(+acc: +List<String>) -> +List<String>:
  match acc:
    case Nil{}: Nil{}
    case Con{head, rest}: rest

def resource_segment_add(segment: +List<Char>, +acc: +List<String>) -> +List<String>:
  +value = String.from_list(M.reverse(Char, segment))
  Bool.pick(+List<String>, String.is_empty(value) || String.eq(value, "."), acc,
    Bool.pick(+List<String>, String.eq(value, ".."), resource_segment_pop(acc), Con{value, acc}))

def resource_segments(chars: +List<Char>, segment: +List<Char>, +acc: +List<String>) -> +List<String>:
  match chars:
    case Nil{}: resource_segment_add(segment, acc)
    case Con{Chr{47}, tail}: resource_segments(tail, Nil{}, resource_segment_add(segment, acc))
    case Con{head, tail}: resource_segments(tail, Con{head, segment}, acc)

def resource_join_segments(+segments: +List<String>) -> String:
  match segments:
    case Nil{}: ""
    case Con{head, Nil{}}: head
    case Con{head, Con{next, rest}}: head ++ "/" ++ resource_join_segments(Con{next, rest})

def resource_normalize_path(+name: String) -> String:
  resource_join_segments(M.reverse(String, resource_segments(String.to_list(name), Nil{}, Nil{})))

def resource_package(+name: String) -> String:
  binary_package(name)

def class_resource_path(+vm: M.VM, target: U32, +name: String) -> String:
  match name:
    case SCon{Chr{47}, tail}: resource_normalize_path(tail)
    case _:
      +package : String = resource_package(class_name_text(vm, target))
      resource_normalize_path(package ++ name)
def class_resource_target(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    return entry_element(entry)

def class_resource_stream(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_resource_target(vm, args)
    value : M.Slot <- slot1(args)
    name : String <- string_text(vm, bits_of(value))
    result : O.Outcome <- resource_stream_found(vm, resource_find_name(S.resources(vm), class_resource_path(vm, target, name)))
    return result

def class_resource_url(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_resource_target(vm, args)
    value : M.Slot <- slot1(args)
    name : String <- string_text(vm, bits_of(value))
    result : O.Outcome <- resource_url_found(vm, resource_find_name(S.resources(vm), class_resource_path(vm, target, name)))
    return result

def loader_absolute_name(name: String) -> Maybe<&2, String>:
  match name:
    case SCon{Chr{47}, tail}: None{}
    case _: Some{resource_normalize_path(name)}

def loader_absolute_url(+vm: M.VM, found: Maybe<&2, String>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: returned(vm, Some{M.Slot{3, 0}})
    case Some{name}: resource_url_found(vm, resource_find_name(S.resources(vm), name))

def loader_absolute_stream(+vm: M.VM, found: Maybe<&2, String>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: returned(vm, Some{M.Slot{3, 0}})
    case Some{name}: resource_stream_found(vm, resource_find_name(S.resources(vm), name))


def class_loader_resource_stream(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot1(args)
    name : String <- string_text(vm, bits_of(value))
    result : O.Outcome <- loader_absolute_stream(vm, loader_absolute_name(name))
    return result

def class_loader_resource_url(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot1(args)
    name : String <- string_text(vm, bits_of(value))
    result : O.Outcome <- loader_absolute_url(vm, loader_absolute_name(name))
    return result
def url_field(+entry: M.HeapEntry, id: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    value : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), id), "java/net/MalformedURLException")
    return bits_of(value)

def url_open_stream(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    name_ref : U32 <- url_field(entry, 0)
    origin_ref : U32 <- url_field(entry, 1)
    name : String <- string_text(vm, name_ref)
    origin : String <- string_text(vm, origin_ref)
    result : O.Outcome <- resource_stream_found(vm, resource_find_exact(S.resources(vm), name, origin))
    return result

# URL.getPath: the escaped part after the protocol ("/dir/name", or
# "file:/archive.jar!/name" for a jar URL).
@unsafe def url_path_info(info: UrlOrigin) -> String:
  match info:
    case UrlOrigin{True{}, +text}: "file:" ++ url_escape_text(String.to_list(text))
    case UrlOrigin{False{}, +text}: url_escape_text(String.to_list(text))

@unsafe def url_get_path(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    origin_ref : U32 <- url_field(entry, 1)
    origin : String <- string_text(vm, origin_ref)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(url_path_info(url_origin_info(origin))))
    return result
def url_origin_scan(chars: +List<Char>, +acc: +List<Char>, archive: Bool) -> UrlOrigin:
  match chars:
    case Nil{}: UrlOrigin{archive, String.from_list(M.reverse(Char, acc))}
    case Con{Chr{33}, Con{Chr{47}, tail}}: url_origin_scan(tail, Con{Chr{47}, Con{Chr{33}, acc}}, True{})
    case Con{head, tail}: url_origin_scan(tail, Con{head, acc}, archive)

def url_origin_info(+origin: String) -> UrlOrigin:
  url_origin_scan(String.to_list(origin), Nil{}, False{})

def url_hex_digit(+value: U32) -> Char:
  Bool.pick(Char, U32.is_lt(value, 10), Chr{U32.add(48, value)}, Chr{U32.add(87, value)})

def url_percent_byte(+value: U32) -> String:
  "%" ++ String.from_list([url_hex_digit(U32.shrn(value, 4n)), url_hex_digit(U32.and(value, 15))])

# sun.net.www.ParseUtil.encodePath: these ASCII characters are escaped; letters,
# digits and !$&'()*+,-./:@_~ are kept.
def url_ascii_encoded(+value: U32) -> Bool:
  U32.is_le(value, 32) || U32.is_eq(value, 127) ||
  U32.is_eq(value, 34) || U32.is_eq(value, 35) || U32.is_eq(value, 37) || U32.is_eq(value, 59) ||
  U32.is_eq(value, 60) || U32.is_eq(value, 61) || U32.is_eq(value, 62) || U32.is_eq(value, 63) ||
  U32.is_eq(value, 91) || U32.is_eq(value, 92) || U32.is_eq(value, 93) || U32.is_eq(value, 94) ||
  U32.is_eq(value, 96) || U32.is_eq(value, 123) || U32.is_eq(value, 124) || U32.is_eq(value, 125)

# Each UTF-16 unit is escaped on its own (surrogates become three bytes each),
# with lowercase hex digits, as ParseUtil.escape does.
def url_escape_unit(+value: U32) -> String:
  Bool.pick(String, U32.is_le(value, 127) && Bool.not(url_ascii_encoded(value)), String.from_list([Chr{value}]),
    Bool.pick(String, U32.is_le(value, 127), url_percent_byte(value),
      Bool.pick(String, U32.is_le(value, 2047),
        url_percent_byte(U32.or(192, U32.shrn(value, 6n))) ++ url_percent_byte(U32.or(128, U32.and(value, 63))),
        url_percent_byte(U32.or(224, U32.shrn(value, 12n))) ++ url_percent_byte(U32.or(128, U32.and(U32.shrn(value, 6n), 63))) ++ url_percent_byte(U32.or(128, U32.and(value, 63))))))

def url_escape_units(units: +List<U32>) -> String:
  match units:
    case Nil{}: ""
    case Con{head, tail}: url_escape_unit(head) ++ url_escape_units(tail)

def url_escape_text(chars: +List<Char>) -> String:
  url_escape_units(units_from_list(chars))

def url_external_info(info: UrlOrigin) -> String:
  match info:
    case UrlOrigin{True{}, +text}: "jar:file:" ++ url_escape_text(String.to_list(text))
    case UrlOrigin{False{}, +text}: "file:" ++ url_escape_text(String.to_list(text))

def url_protocol_info(info: UrlOrigin) -> String:
  match info:
    case UrlOrigin{archive, text}:
      match archive:
        case True{}: "jar"
        case False{}: "file"

def url_get_protocol(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    origin_ref : U32 <- url_field(entry, 1)
    origin : String <- string_text(vm, origin_ref)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(url_protocol_info(url_origin_info(origin))))
    return result

def url_to_external_form(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    origin_ref : U32 <- url_field(entry, 1)
    origin : String <- string_text(vm, origin_ref)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(url_external_info(url_origin_info(origin))))
    return result

def url_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  url_to_external_form(vm, args)


def object_get_class(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +reference : U32 = bits_of(receiver)
    checked : Unit <- S.check(U32.is_ne(reference, 0), npe())
    entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    result : O.Outcome <- class_mirror_out(vm, H.entry_class(entry))
    return result

def drop_descriptor_end(+chars: +List<Char>, acc: +List<Char>) -> +List<Char>:
  match chars:
    case Nil{}: M.reverse(Char, acc)
    case Con{Chr{59}, Nil{}}: M.reverse(Char, acc)
    case Con{+head, tail}: drop_descriptor_end(tail, Con{head, acc})

def component_descriptor(+chars: +List<Char>) -> String:
  match chars:
    case Con{Chr{76}, tail}: String.from_list(drop_descriptor_end(tail, Nil{}))
    case Con{Chr{73}, Nil{}}: "int"
    case Con{Chr{90}, Nil{}}: "boolean"
    case Con{Chr{66}, Nil{}}: "byte"
    case Con{Chr{83}, Nil{}}: "short"
    case Con{Chr{67}, Nil{}}: "char"
    case Con{Chr{70}, Nil{}}: "float"
    case Con{Chr{74}, Nil{}}: "long"
    case Con{Chr{68}, Nil{}}: "double"
    case Con{Chr{91}, tail}: "[" ++ String.from_list(tail)
    case _: ""

def array_component_chars(chars: +List<Char>) -> String:
  match chars:
    case Con{Chr{91}, tail}: component_descriptor(tail)
    case _: ""

def array_component_name(+name: String) -> String:
  array_component_chars(String.to_list(name))
def descriptor_class_chars(chars: +List<Char>) -> String:
  match chars:
    case Con{Chr{91}, tail}: "[" ++ String.from_list(tail)
    case Con{Chr{76}, tail}: String.from_list(drop_descriptor_end(tail, Nil{}))
    case Con{Chr{73}, Nil{}}: "int"
    case Con{Chr{90}, Nil{}}: "boolean"
    case Con{Chr{66}, Nil{}}: "byte"
    case Con{Chr{83}, Nil{}}: "short"
    case Con{Chr{67}, Nil{}}: "char"
    case Con{Chr{70}, Nil{}}: "float"
    case Con{Chr{74}, Nil{}}: "long"
    case Con{Chr{68}, Nil{}}: "double"
    case Con{Chr{86}, Nil{}}: "void"
    case _: ""

def descriptor_class_name(+descriptor: String) -> String:
  descriptor_class_chars(String.to_list(descriptor))

def return_descriptor_chars(chars: +List<Char>) -> String:
  match chars:
    case Nil{}: ""
    case Con{Chr{41}, tail}: String.from_list(tail)
    case Con{head, tail}: return_descriptor_chars(tail)

def method_return_name(+descriptor: String) -> String:
  descriptor_class_name(return_descriptor_chars(String.to_list(descriptor)))

def loaded_mirror(+vm: M.VM, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(target, 4294967295), throw_name(vm, "java/lang/NoClassDefFoundError"), class_mirror_out(vm, target))

# Mirrors by name create array classes on first use, as the JVM does.
def class_name_mirror(+vm: M.VM, +name: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ready : M.VM <- ensure_array_class(vm, name)
    result : O.Outcome <- loaded_mirror(ready, class_id(ready, name))
    return result

def descriptor_mirror(+vm: M.VM, +descriptor: String) -> Result<&2, &2, String, O.Outcome>:
  class_name_mirror(vm, descriptor_class_name(descriptor))

def class_component_result(+vm: M.VM, +name: String) -> Result<&2, &2, String, O.Outcome>:
  +component : String = array_component_name(name)
  +target : U32 = class_id(vm, component)
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(target, 4294967295), ref_out(vm, 0), class_mirror_out(vm, target))


def class_metadata_found(found: Maybe<&2, M.ClassMetadata>) -> U32:
  match found:
    case None{}: 0
    case Some{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, pool, signature, nesting, source}}: flags

def class_flags_from_metadata(metadata: M.Metadata, +target: U32) -> U32:
  match metadata:
    case M.Metadata{classes, fields, methods}:
      class_metadata_found(M.nth(M.ClassMetadata, classes, target))
def annotation_name_present(+names: +List<String>, +target: String) -> Bool:
  match names:
    case Nil{}: False{}
    case Con{+name, rest}: Bool.or(String.eq(name, target), annotation_name_present(rest, target))

def class_annotation_names_found(found: Maybe<&2, M.ClassMetadata>) -> +List<String>:
  match found:
    case None{}: Nil{}
    case Some{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, pool, signature, nesting, source}}: visibleAnnotations

def class_annotation_names_from_metadata(metadata: M.Metadata, +target: U32) -> +List<String>:
  match metadata:
    case M.Metadata{classes, fields, methods}:
      class_annotation_names_found(M.nth(M.ClassMetadata, classes, target))

def class_annotation_names(+vm: M.VM, +target: U32) -> +List<String>:
  +metadata : M.Metadata = S.metadata(vm)
  class_annotation_names_from_metadata(metadata, target)

def class_flags(+vm: M.VM, +target: U32) -> U32:
  class_flags_from_metadata(S.metadata(vm), target)
def class_metadata_from_metadata(metadata: M.Metadata, +target: U32) -> Result<&2, &2, String, M.ClassMetadata>:
  match metadata:
    case M.Metadata{classes, fields, methods}:
      S.require(M.ClassMetadata, M.nth(M.ClassMetadata, classes, target), "InvalidState: missing class metadata")

def class_metadata_value(+vm: M.VM, +target: U32) -> Result<&2, &2, String, M.ClassMetadata>:
  class_metadata_from_metadata(S.metadata(vm), target)

def metadata_annotations(value: M.AnnotationMetadata) -> +List<M.Annotation>:
  match value:
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue, ia, ip, it}: annotations

def metadata_parameters(value: M.AnnotationMetadata) -> +List<+List<M.Annotation>>:
  match value:
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue, ia, ip, it}: parameterAnnotations
def metadata_type_annotations(value: M.AnnotationMetadata) -> +List<M.TypeAnnotation>:
  match value:
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue, ia, ip, it}: typeAnnotations
def metadata_exceptions(value: M.AnnotationMetadata) -> +List<U32>:
  match value:
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue, ia, ip, it}: exceptions



def metadata_default(value: M.AnnotationMetadata) -> Maybe<&2, M.AnnotationValue>:
  match value:
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue, ia, ip, it}: defaultValue

def annotation_pool_name_result(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Fail{error}: ""
    case Done{value}: descriptor_class_name(value)

def annotation_pool_name(+pool: +List<M.Constant>, +index: U32) -> String:
  annotation_pool_name_result(CP.utf(pool, index))

def annotation_pool_text_result(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Fail{error}: ""
    case Done{value}: value

def annotation_pool_text(+pool: +List<M.Constant>, +index: U32) -> String:
  annotation_pool_text_result(CP.utf(pool, index))

def annotation_find(+annotations: +List<M.Annotation>, +pool: +List<M.Constant>, +name: String) -> Maybe<&2, M.Annotation>:
  match annotations:
    case Nil{}: None{}
    case Con{+annotation, rest}:
      match annotation:
        case M.Annotation{typeIndex, elements}:
          Bool.pick(Maybe<&2, M.Annotation>, String.eq(annotation_pool_name(pool, typeIndex), name), Some{annotation}, annotation_find(rest, pool, name))

def annotation_element_find(+elements: +List<M.AnnotationElement>, +pool: +List<M.Constant>, +name: String) -> Maybe<&2, M.AnnotationValue>:
  match elements:
    case Nil{}: None{}
    case Con{M.AnnotationElement{nameIndex, value}, rest}:
      Bool.pick(Maybe<&2, M.AnnotationValue>, String.eq(annotation_pool_text(pool, nameIndex), name), Some{value}, annotation_element_find(rest, pool, name))

def annotation_element_result(found: Maybe<&2, M.AnnotationValue>) -> Result<&2, &2, String, M.AnnotationValue>:
  match found:
    case None{}: Fail{"java/lang/annotation/AnnotationFormatError"}
    case Some{value}: Done{value}

def annotation_nested_element_find(+elements: +List<M.AnnotationValue>, +pool: +List<M.Constant>, +name: String) -> Maybe<&2, M.AnnotationValue>:
  match elements:
    case Nil{}: None{}
    case Con{value, rest}:
      match value:
        case M.AnnotationElementValue{nameIndex, value}:
          Bool.pick(Maybe<&2, M.AnnotationValue>, String.eq(annotation_pool_text(pool, nameIndex), name), Some{value}, annotation_nested_element_find(rest, pool, name))
        case _: annotation_nested_element_find(rest, pool, name)

def annotation_method_name(+vm: M.VM, +method: M.LoadedMethod) -> String:
  Sy.text(S.symbols(vm), M.loaded_method_name(method))

def annotation_method_descriptor(+vm: M.VM, +method: M.LoadedMethod) -> String:
  Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))

def annotation_method_find(methods: +List<M.LoadedMethod>, +owner: U32, +name: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      +method_name : String = Sy.text(symbols, M.loaded_method_name(method))
      +ordinary : Bool = Bool.not(String.eq(method_name, "<init>")) && Bool.not(String.eq(method_name, "<clinit>"))
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), owner) && ordinary && String.eq(method_name, name), Some{method}, annotation_method_find(rest, owner, name, symbols))

def annotation_outcome_value(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, AnnotationValueRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{outcome}:
      match outcome:
        case O.Returned{vm, Some{slot}}: Done{AnnotationValueRef{vm, slot}}
        case O.Returned{vm, None{}}: Fail{"VmError.InvalidAnnotation: expected reference value"}
        case O.ThrownName{vm, name}: Fail{name}
        case O.ThrownRef{vm, reference}: Fail{"VmError.InvalidAnnotation: annotation value threw"}
        case O.Suspend{vm, effect}: Fail{"VmError.InvalidAnnotation: suspended annotation value"}
        case O.Call{vm, method, args}: Fail{"VmError.InvalidAnnotation: callback annotation value"}

def annotation_runtime_ref(value: AR.Value) -> AnnotationValueRef:
  match value:
    case AR.Value{vm, slot}: AnnotationValueRef{vm, slot}

@unsafe def annotation_value(+vm: M.VM, pool: +List<M.Constant>, value: M.AnnotationValue, descriptor: String) -> Result<&2, &2, String, AnnotationValueRef>:
  do Result<&2, &2, String, AnnotationValueRef>:
    result : AR.Value <- AR.value(vm, pool, value, descriptor, 0)
    return annotation_runtime_ref(result)

@unsafe def annotation_object(vm: M.VM, pool: +List<M.Constant>, value: M.Annotation) -> Result<&2, &2, String, AnnotationValueRef>:
  do Result<&2, &2, String, AnnotationValueRef>:
    result : AR.Value <- AR.object(vm, pool, value)
    return annotation_runtime_ref(result)

def annotation_refs_continue(first: AnnotationValueRef, +pool: +List<M.Constant>, +rest: +List<M.Annotation>, +acc: +List<M.Slot>, next: M.VM -> M.Slot -> Result<&2, &2, String, AnnotationValueRefs>) -> Result<&2, &2, String, AnnotationValueRefs>:
  match first:
    case AnnotationValueRef{+vm, slot}: next(vm, slot)

@unsafe def annotation_refs(+values: +List<M.Annotation>, +vm: M.VM, +pool: +List<M.Constant>, +acc: +List<M.Slot>) -> Result<&2, &2, String, AnnotationValueRefs>:
  match values:
    case Nil{}: Done{AnnotationValueRefs{vm, M.reverse(M.Slot, acc)}}
    case Con{+value, rest}:
      do Result<&2, &2, String, AnnotationValueRefs>:
        first : AnnotationValueRef <- annotation_object(vm, pool, value)
        result : AnnotationValueRefs <- annotation_refs_continue(first, pool, rest, acc, next_vm => slot => annotation_refs(rest, next_vm, pool, Con{slot, acc}))
        return result

def annotation_array_alloc_outcome(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}: ref_out(vm, reference)

def annotation_array_result(value: AnnotationValueRefs) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case AnnotationValueRefs{+vm, +slots}:
      do Result<&2, &2, String, O.Outcome>:
        +array_class : U32 = class_id(vm, "[Ljava/lang/annotation/Annotation;")
        +component : U32 = class_id(vm, "java/lang/annotation/Annotation")
        checked : Unit <- S.check(U32.is_ne(array_class, 4294967295) && U32.is_ne(component, 4294967295), "UnsupportedFeature: declaration annotation array class")
        result : O.Outcome <- annotation_array_alloc_outcome(H.allocate(vm, H.reference_array_entry(array_class, component, slots)))
        return result

def annotation_array_result_type(+vm: M.VM, component: U32, +slots: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +component_name : String = class_name_text(vm, component)
    +component_id_value : U32 = class_id(vm, component_name)
    +array_name : String = "[L" ++ component_name ++ ";"
    +array_class : U32 = class_id(vm, array_name)
    checked : Unit <- S.check(U32.is_ne(array_class, 4294967295) && U32.is_ne(component_id_value, 4294967295), "UnsupportedFeature: annotation type array class")
    result : O.Outcome <- annotation_array_alloc_outcome(H.allocate(vm, H.reference_array_entry(array_class, component_id_value, slots)))
    return result

def class_annotation_values_from(+vm: M.VM, metadata: M.ClassMetadata) -> AnnotationMetadataRef:
  match metadata:
    case M.ClassMetadata{owner, flags, metadata, visibleAnnotations, +pool, signature, nesting, source}: AnnotationMetadataRef{vm, pool, metadata}

def class_annotation_values_after(+vm: M.VM, result: Result<&2, &2, String, M.ClassMetadata>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{metadata}: Done{class_annotation_values_from(vm, metadata)}

def class_annotation_values(+vm: M.VM, +target: U32) -> Result<&2, &2, String, AnnotationMetadataRef>:
  class_annotation_values_after(vm, class_metadata_value(vm, target))

def repeatable_container_name_value(+pool: +List<M.Constant>, value: M.AnnotationValue) -> Result<&2, &2, String, Maybe<&2, String>>:
  match value:
    case M.AnnotationClass{descriptorIndex}:
      do Result<&2, &2, String, Maybe<&2, String>>:
        +descriptor : String <- CP.utf(pool, descriptorIndex)
        return Some{descriptor_class_name(descriptor)}
    case _: Done{None{}}

def repeatable_container_name_found(+pool: +List<M.Constant>, found: Maybe<&2, M.AnnotationValue>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match found:
    case None{}: Done{None{}}
    case Some{value}: repeatable_container_name_value(pool, value)

def annotation_elements_of(found: Maybe<&2, M.Annotation>) -> +List<M.AnnotationElement>:
  match found:
    case None{}: Nil{}
    case Some{annotation}:
      match annotation:
        case M.Annotation{typeIndex, elements}: elements

def repeatable_container_name_source(source: AnnotationMetadataRef) -> Result<&2, &2, String, Maybe<&2, String>>:
  match source:
    case AnnotationMetadataRef{vm, +pool, metadata}:
      repeatable_container_name_found(pool, annotation_element_find(annotation_elements_of(annotation_find(metadata_annotations(metadata), pool, "java/lang/annotation/Repeatable")), pool, "value"))

def repeatable_container_name(+vm: M.VM, annotation_type: U32) -> Result<&2, &2, String, Maybe<&2, String>>:
  do Result<&2, &2, String, Maybe<&2, String>>:
    source : AnnotationMetadataRef <- class_annotation_values(vm, annotation_type)
    result : Maybe<&2, String> <- repeatable_container_name_source(source)
    return result

def class_annotation_result_from(source: AnnotationMetadataRef, +name: String) -> Maybe<&2, M.Annotation>:
  match source:
    case AnnotationMetadataRef{vm, pool, metadata}: annotation_find(metadata_annotations(metadata), pool, name)

def class_annotation_result(+vm: M.VM, +target: U32, +name: String) -> Result<&2, &2, String, Maybe<&2, M.Annotation>>:
  do Result<&2, &2, String, Maybe<&2, M.Annotation>>:
    source : AnnotationMetadataRef <- class_annotation_values(vm, target)
    result : Maybe<&2, M.Annotation> = class_annotation_result_from(source, name)
    return result

def annotation_object_outcome(result: Result<&2, &2, String, AnnotationValueRef>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{AnnotationValueRef{+vm, slot}}: returned(vm, Some{slot})
def class_annotation_one_found(+vm: M.VM, +pool: +List<M.Constant>, found: Maybe<&2, M.Annotation>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: ref_out(vm, 0)
    case Some{annotation}: annotation_object_outcome(annotation_object(vm, pool, annotation))

def class_annotation_one_from(source: AnnotationMetadataRef, +name: String) -> Result<&2, &2, String, O.Outcome>:
  match source:
    case AnnotationMetadataRef{+vm, +pool, metadata}:
      class_annotation_one_found(vm, pool, annotation_find(metadata_annotations(metadata), pool, name))


def class_annotation_one(+vm: M.VM, +target: U32, +name: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- class_annotation_values(vm, target)
    result : O.Outcome <- class_annotation_one_from(source, name)
    return result

def class_annotations_array_from(source: AnnotationMetadataRef) -> Result<&2, &2, String, O.Outcome>:
  match source:
    case AnnotationMetadataRef{+vm, +pool, metadata}:
      do Result<&2, &2, String, O.Outcome>:
        refs : AnnotationValueRefs <- annotation_refs(metadata_annotations(metadata), vm, pool, Nil{})
        result : O.Outcome <- annotation_array_result(refs)
        return result

def annotation_one_array_value(value: AnnotationValueRef, component: U32) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case AnnotationValueRef{+vm, slot}: annotation_array_result_type(vm, component, [slot])

def annotation_one_array_found(+vm: M.VM, +pool: +List<M.Constant>, component: U32, found: Maybe<&2, M.Annotation>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: annotation_array_result_type(vm, component, Nil{})
    case Some{annotation}:
      do Result<&2, &2, String, O.Outcome>:
        value : AnnotationValueRef <- annotation_object(vm, pool, annotation)
        result : O.Outcome <- annotation_one_array_value(value, component)
        return result

def annotation_value_ref_outcome(value: AnnotationValueRef) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case AnnotationValueRef{+vm, slot}: returned(vm, Some{slot})

@unsafe def annotation_repeatable_value(+vm: M.VM, +pool: +List<M.Constant>, +name: String, value: M.AnnotationValue) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case M.AnnotationArray{values}:
      do Result<&2, &2, String, O.Outcome>:
        result : AR.Value <- AR.value(vm, pool, M.AnnotationArray{values}, "[L" ++ name ++ ";", 0)
        outcome : O.Outcome <- AR.outcome(result)
        return outcome
    case _: Fail{"java/lang/annotation/AnnotationFormatError"}

def annotation_repeatable_container_found(+vm: M.VM, +pool: +List<M.Constant>, +name: String, found: Maybe<&2, M.Annotation>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: annotation_array_result_type(vm, class_id(vm, name), Nil{})
    case Some{annotation}:
      match annotation:
        case M.Annotation{typeIndex, elements}:
          do Result<&2, &2, String, O.Outcome>:
            value : M.AnnotationValue <- annotation_element_result(annotation_element_find(elements, pool, "value"))
            result : O.Outcome <- annotation_repeatable_value(vm, pool, name, value)
            return result

def repeatable_container_name_text(container: Maybe<&2, String>) -> String:
  match container:
    case None{}: ""
    case Some{+name}: name

def annotation_ref_vm(value: AnnotationValueRef) -> M.VM:
  match value:
    case AnnotationValueRef{vm, slot}: vm

type ScanJob is Data:
  SRefs{name: String, container: String, annotations: +List<M.Annotation>, acc: +List<M.Slot>}
  SDirect{annotation: M.Annotation, name: String, container: String, rest: +List<M.Annotation>, acc: +List<M.Slot>}
  SDirectAfter{value: AnnotationValueRef, name: String, container: String, rest: +List<M.Annotation>, acc: +List<M.Slot>}
  SContainer{annotation: M.Annotation, name: String, container: String, rest: +List<M.Annotation>, acc: +List<M.Slot>}
  SContainerAfter{value: AnnotationValueRef, name: String, container: String, rest: +List<M.Annotation>, acc: +List<M.Slot>}
def scan_job_container_select(matched: Bool, yes: Unit -> Result<&2, &2, String, AnnotationValueRefs>, no: Unit -> Result<&2, &2, String, AnnotationValueRefs>) -> Result<&2, &2, String, AnnotationValueRefs>:
  match matched:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def scan_job_select(direct: Bool, container: Bool, direct_job: Unit -> Result<&2, &2, String, AnnotationValueRefs>, container_job: Unit -> Result<&2, &2, String, AnnotationValueRefs>, rest_job: Unit -> Result<&2, &2, String, AnnotationValueRefs>) -> Result<&2, &2, String, AnnotationValueRefs>:
  match direct:
    case True{}: direct_job(Unit{})
    case False{}: scan_job_container_select(container, container_job, rest_job)


@unsafe def scan_job(+vm: M.VM, +pool: +List<M.Constant>, job: ScanJob) -> Result<&2, &2, String, AnnotationValueRefs>:
  match job:
    case SRefs{name, container, Nil{}, acc}: Done{AnnotationValueRefs{vm, acc}}
    case SRefs{+name, +container, Con{+annotation, +rest}, +acc}:
      match annotation:
        case M.Annotation{typeIndex, elements}:
          +annotationName : String = annotation_pool_name(pool, typeIndex)
          scan_job_select(String.eq(annotationName, name),
            Bool.not(String.is_empty(container)) && String.eq(annotationName, container),
            unit => scan_job(vm, pool, SDirect{annotation, name, container, rest, acc}),
            unit => scan_job(vm, pool, SContainer{annotation, name, container, rest, acc}),
            unit => scan_job(vm, pool, SRefs{name, container, rest, acc}))
    case SDirect{annotation, +name, +container, rest, acc}:
      do Result<&2, &2, String, AnnotationValueRefs>:
        +value : AnnotationValueRef <- annotation_object(vm, pool, annotation)
        result : AnnotationValueRefs <- scan_job(annotation_ref_vm(value), pool, SDirectAfter{value, name, container, rest, acc})
        return result
    case SDirectAfter{AnnotationValueRef{vm, slot}, name, container, rest, acc}: scan_job(vm, pool, SRefs{name, container, rest, M.append(M.Slot, acc, [slot])})
    case SContainer{annotation, +name, +container, rest, acc}:
      do Result<&2, &2, String, AnnotationValueRefs>:
        +value : AnnotationValueRef <- annotation_outcome_value(annotation_repeatable_container_found(vm, pool, name, Some{annotation}))
        result : AnnotationValueRefs <- scan_job(annotation_ref_vm(value), pool, SContainerAfter{value, name, container, rest, acc})
        return result
    case SContainerAfter{AnnotationValueRef{+vm, slot}, +name, +container, rest, acc}:
      do Result<&2, &2, String, AnnotationValueRefs>:
        entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(slot))
        result : AnnotationValueRefs <- scan_job(vm, pool, SRefs{name, container, rest, M.append(M.Slot, acc, entry_values(entry))})
        return result

def annotation_scan_array(value: AnnotationValueRefs, name: String) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case AnnotationValueRefs{+vm, slots}: annotation_array_result_type(vm, class_id(vm, name), slots)
@unsafe def annotation_scan(+vm: M.VM, +pool: +List<M.Constant>, +name: String, container_name: String, annotations: +List<M.Annotation>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    refs : AnnotationValueRefs <- scan_job(vm, pool, SRefs{name, container_name, annotations, Nil{}})
    result : O.Outcome <- annotation_scan_array(refs, name)
    return result


def annotation_arrays_by_type_from(source: AnnotationMetadataRef, +name: String) -> Result<&2, &2, String, O.Outcome>:
  match source:
    case AnnotationMetadataRef{+vm, +pool, metadata}:
      do Result<&2, &2, String, O.Outcome>:
        container : Maybe<&2, String> <- repeatable_container_name(vm, class_id(vm, name))
        result : O.Outcome <- annotation_scan(vm, pool, name, repeatable_container_name_text(container), metadata_annotations(metadata))
        return result


def class_annotations_by_type(+vm: M.VM, +target: U32, +name: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- class_annotation_values(vm, target)
    result : O.Outcome <- annotation_arrays_by_type_from(source, name)
    return result

def class_annotations_array(+vm: M.VM, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- class_annotation_values(vm, target)
    result : O.Outcome <- class_annotations_array_from(source)
    return result



def class_entry(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, M.HeapEntry>:
  do Result<&2, &2, String, M.HeapEntry>:
    receiver : M.Slot <- slot0(args)
    +reference : U32 = bits_of(receiver)
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 8), "java/lang/IllegalArgumentException")
    return entry

def class_target(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    entry : M.HeapEntry <- class_entry(vm, args)
    return entry_element(entry)
def class_parent_id(+vm: M.VM, target: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), target), "java/lang/NoClassDefFoundError")
    return M.loaded_class_parent(class)

def class_annotation_parent_result(+vm: M.VM, name: String, has_parent: Bool, parent: U32) -> Result<&2, &2, String, O.Outcome>:
  match has_parent:
    case True{}: class_annotation_one(vm, parent, name)
    case False{}: ref_out(vm, 0)

def class_annotation_present_parent(+vm: M.VM, parent: U32, name: String, has_parent: Bool) -> Result<&2, &2, String, Bool>:
  match has_parent:
    case True{}: Done{annotation_name_present(class_annotation_names(vm, parent), name)}
    case False{}: Done{False{}}

def class_annotation_present_walk(+vm: M.VM, target: U32, name: String, annotation_type: U32, direct: Bool) -> Result<&2, &2, String, Bool>:
  match direct:
    case True{}: Done{True{}}
    case False{}:
      do Result<&2, &2, String, Bool>:
        +inherited : Bool = annotation_name_present(class_annotation_names(vm, annotation_type), "java/lang/annotation/Inherited")
        +parent : U32 <- class_parent_id(vm, target)
        result : Bool <- class_annotation_present_parent(vm, parent, name, inherited && U32.is_ne(parent, 4294967295))
        return result
def class_annotation_direct_result(+vm: M.VM, target: U32, +name: String) -> Result<&2, &2, String, Maybe<&2, M.Annotation>>:
  match target:
    case 4294967295: Done{None{}}
    case _:
      do Result<&2, &2, String, Maybe<&2, M.Annotation>>:
        source : AnnotationMetadataRef <- class_annotation_values(vm, target)
        return class_annotation_result_from(source, name)

def class_annotation_direct_present(+vm: M.VM, target: U32, +name: String) -> Result<&2, &2, String, Bool>:
  match target:
    case 4294967295: Done{False{}}
    case target_id: Done{annotation_name_present(class_annotation_names(vm, target_id), name)}

def class_annotation_present_inherited_result(fuel: Nat, +vm: M.VM, target: U32, +name: String, +annotation_type: U32, direct: Bool) -> Result<&2, &2, String, Bool>:
  match fuel target direct:
    case 0n _ _:
      Fail{"UnsupportedFeature: annotation inheritance depth"}
    case 1n+remaining _ True{}:
      Done{True{}}
    case 1n+remaining 4294967295 _:
      Done{False{}}
    case 1n+remaining target_id False{}:
      do Result<&2, &2, String, Bool>:
        +inherited : Bool = annotation_name_present(class_annotation_names(vm, annotation_type), "java/lang/annotation/Inherited")
        +parent : U32 <- class_parent_id(vm, target_id)
        +next_target : U32 = Bool.pick(U32, inherited && U32.is_ne(parent, 4294967295), parent, 4294967295)
        parent_direct : Bool <- class_annotation_direct_present(vm, next_target, name)
        result : Bool <- class_annotation_present_inherited_result(remaining, vm, next_target, name, annotation_type, parent_direct)
        return result

def class_annotation_inherited_result(fuel: Nat, +vm: M.VM, target: U32, +name: String, +annotation_type: U32, found: Maybe<&2, M.Annotation>) -> Result<&2, &2, String, O.Outcome>:
  match fuel target found:
    case 0n _ _:
      Fail{"UnsupportedFeature: annotation inheritance depth"}
    case 1n+remaining 4294967295 _:
      ref_out(vm, 0)
    case 1n+remaining target_id Some{annotation}:
      class_annotation_one(vm, target_id, name)
    case 1n+remaining target_id None{}:
      do Result<&2, &2, String, O.Outcome>:
        +inherited : Bool = annotation_name_present(class_annotation_names(vm, annotation_type), "java/lang/annotation/Inherited")
        +parent : U32 <- class_parent_id(vm, target_id)
        parent_found : Maybe<&2, M.Annotation> <- class_annotation_direct_result(vm, parent, name)
        +next_target : U32 = Bool.pick(U32, inherited && U32.is_ne(parent, 4294967295), parent, 4294967295)
        result : O.Outcome <- class_annotation_inherited_result(remaining, vm, next_target, name, annotation_type, parent_found)
        return result

def class_get_annotation(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    annotation : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(annotation))
    +name : String = class_name_text(vm, entry_element(entry))
    source : AnnotationMetadataRef <- class_annotation_values(vm, target)
    found : Maybe<&2, M.Annotation> = class_annotation_result_from(source, name)
    result : O.Outcome <- class_annotation_inherited_result(64n, vm, target, name, entry_element(entry), found)
    return result

def class_get_declared_annotation(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    annotation : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(annotation))
    +name : String = class_name_text(vm, entry_element(entry))
    result : O.Outcome <- class_annotation_one(vm, target, name)
    return result


type ByTypeJob is Data:
  BWalk{fuel: Nat, target: U32, name: String}
  BAfter{value: AnnotationValueRef, fuel: Nat, target: U32, name: String}

@unsafe def by_type_job(+vm: M.VM, job: ByTypeJob) -> Result<&2, &2, String, O.Outcome>:
  match job:
    case BWalk{fuel, target, +name}:
      match fuel:
        case 0n: Fail{"UnsupportedFeature: annotation inheritance depth"}
        case 1n+remaining:
          match target:
            case 4294967295: annotation_array_result_type(vm, class_id(vm, name), Nil{})
            case +current:
              do Result<&2, &2, String, O.Outcome>:
                +value : AnnotationValueRef <- annotation_outcome_value(class_annotations_by_type(vm, current, name))
                result : O.Outcome <- by_type_job(annotation_ref_vm(value), BAfter{value, remaining, current, name})
                return result
    case BAfter{AnnotationValueRef{+vm, +slot}, fuel, target, +name}:
      do Result<&2, &2, String, O.Outcome>:
        entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(slot))
        +empty : Bool = U32.is_eq(M.length(M.Slot, entry_values(entry)), 0)
        +inherited : Bool = annotation_name_present(class_annotation_names(vm, class_id(vm, name)), "java/lang/annotation/Inherited")
        parent : U32 <- class_parent_id(vm, target)
        result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, empty && inherited, by_type_job(vm, BWalk{fuel, parent, name}), returned(vm, Some{slot}))
        return result

@unsafe def annotations_by_type_inherited(fuel: Nat, +vm: M.VM, target: U32, name: String) -> Result<&2, &2, String, O.Outcome>:
  by_type_job(vm, BWalk{fuel, target, name})

type InheritedAnnotationRefs is Data:
  InheritedAnnotationRefs{vm: M.VM, slots: +List<M.Slot>, names: +List<String>}

type InheritJob is Data:
  IEntries{annotations: +List<M.Annotation>, direct: Bool, slots: +List<M.Slot>, names: +List<String>}
  IAdd{annotation: M.Annotation, rest: +List<M.Annotation>, direct: Bool, slots: +List<M.Slot>, names: +List<String>, name: String}
  IAdded{value: AnnotationValueRef, rest: +List<M.Annotation>, direct: Bool, slots: +List<M.Slot>, names: +List<String>, name: String}
def inherit_job_select(add: Bool, yes: Unit -> Result<&2, &2, String, InheritedAnnotationRefs>, no: Unit -> Result<&2, &2, String, InheritedAnnotationRefs>) -> Result<&2, &2, String, InheritedAnnotationRefs>:
  match add:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})


@unsafe def inherit_job(+vm: M.VM, +pool: +List<M.Constant>, job: InheritJob) -> Result<&2, &2, String, InheritedAnnotationRefs>:
  match job:
    case IEntries{Nil{}, direct, slots, names}: Done{InheritedAnnotationRefs{vm, slots, names}}
    case IEntries{Con{+annotation, +rest}, +direct, +slots, +names}:
      match annotation:
        case M.Annotation{typeIndex, elements}:
          +name : String = annotation_pool_name(pool, typeIndex)
          +eligible : Bool = direct || annotation_name_present(class_annotation_names(vm, class_id(vm, name)), "java/lang/annotation/Inherited")
          inherit_job_select(eligible && Bool.not(annotation_name_present(names, name)),
            unit => inherit_job(vm, pool, IAdd{annotation, rest, direct, slots, names, name}),
            unit => inherit_job(vm, pool, IEntries{rest, direct, slots, names}))
    case IAdd{annotation, rest, direct, slots, names, +name}:
      do Result<&2, &2, String, InheritedAnnotationRefs>:
        +value : AnnotationValueRef <- annotation_object(vm, pool, annotation)
        result : InheritedAnnotationRefs <- inherit_job(annotation_ref_vm(value), pool, IAdded{value, rest, direct, slots, names, name})
        return result
    case IAdded{AnnotationValueRef{vm, slot}, rest, direct, slots, names, name}: inherit_job(vm, pool, IEntries{rest, direct, M.append(M.Slot, slots, [slot]), Con{name, names}})

@unsafe def inherited_annotation_entries(+vm: M.VM, +pool: +List<M.Constant>, annotations: +List<M.Annotation>, direct: Bool, slots: +List<M.Slot>, names: +List<String>) -> Result<&2, &2, String, InheritedAnnotationRefs>:
  inherit_job(vm, pool, IEntries{annotations, direct, slots, names})

def inherited_refs_vm(refs: InheritedAnnotationRefs) -> M.VM:
  match refs:
    case InheritedAnnotationRefs{vm, slots, names}: vm

type InheritWalk is Data:
  WFuel{fuel: Nat, target: U32, direct: Bool, slots: +List<M.Slot>, names: +List<String>}
  WSource{source: AnnotationMetadataRef, fuel: Nat, target: U32, direct: Bool, slots: +List<M.Slot>, names: +List<String>}
  WNext{refs: InheritedAnnotationRefs, fuel: Nat, target: U32}

@unsafe def inherit_walk(+vm: M.VM, job: InheritWalk) -> Result<&2, &2, String, O.Outcome>:
  match job:
    case WFuel{fuel, target, direct, slots, names}:
      match fuel:
        case 0n: Fail{"UnsupportedFeature: annotation inheritance depth"}
        case 1n+remaining:
          match target:
            case 4294967295: annotation_array_result(AnnotationValueRefs{vm, slots})
            case +current:
              do Result<&2, &2, String, O.Outcome>:
                source : AnnotationMetadataRef <- class_annotation_values(vm, current)
                result : O.Outcome <- inherit_walk(vm, WSource{source, remaining, current, direct, slots, names})
                return result
    case WSource{AnnotationMetadataRef{+vm, +pool, metadata}, fuel, target, direct, +slots, +names}:
      do Result<&2, &2, String, O.Outcome>:
        +refs : InheritedAnnotationRefs <- inherited_annotation_entries(vm, pool, metadata_annotations(metadata), direct, slots, names)
        result : O.Outcome <- inherit_walk(inherited_refs_vm(refs), WNext{refs, fuel, target})
        return result
    case WNext{InheritedAnnotationRefs{+vm, slots, names}, fuel, target}:
      do Result<&2, &2, String, O.Outcome>:
        parent : U32 <- class_parent_id(vm, target)
        result : O.Outcome <- inherit_walk(vm, WFuel{fuel, parent, False{}, slots, names})
        return result

@unsafe def inherited_annotations_walk(fuel: Nat, +vm: M.VM, target: U32, direct: Bool, slots: +List<M.Slot>, names: +List<String>) -> Result<&2, &2, String, O.Outcome>:
  inherit_walk(vm, WFuel{fuel, target, direct, slots, names})

def class_get_annotations_by_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    annotation : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(annotation))
    +name : String = class_name_text(vm, entry_element(entry))
    result : O.Outcome <- annotations_by_type_inherited(4096n, vm, target, name)
    return result

def class_get_annotations(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    result : O.Outcome <- inherited_annotations_walk(4096n, vm, target, True{}, Nil{}, Nil{})
    return result

def class_get_declared_annotations(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- class_annotations_array(vm, target)
    return result
def field_metadata_from_metadata(metadata: M.Metadata, +id: U32) -> Result<&2, &2, String, M.FieldMetadata>:
  match metadata:
    case M.Metadata{classes, fields, methods}:
      S.require(M.FieldMetadata, M.nth(M.FieldMetadata, fields, id), "InvalidState: missing field metadata")

def field_metadata_value(+vm: M.VM, +id: U32) -> Result<&2, &2, String, M.FieldMetadata>:
  field_metadata_from_metadata(S.metadata(vm), id)

def class_metadata_pool(value: M.ClassMetadata) -> +List<M.Constant>:
  match value:
    case M.ClassMetadata{owner, flags, metadata, visibleAnnotations, +pool, signature, nesting, source}: pool

def field_metadata_annotations(value: M.FieldMetadata) -> M.AnnotationMetadata:
  match value:
    case M.FieldMetadata{owner, field, metadata, signature}: metadata


def method_metadata_from_metadata(metadata: M.Metadata, +id: U32) -> Result<&2, &2, String, M.MethodMetadata>:
  match metadata:
    case M.Metadata{classes, fields, methods}:
      S.require(M.MethodMetadata, M.nth(M.MethodMetadata, methods, id), "InvalidState: missing method metadata")

def method_metadata_value(+vm: M.VM, +id: U32) -> Result<&2, &2, String, M.MethodMetadata>:
  method_metadata_from_metadata(S.metadata(vm), id)
def method_metadata_annotations(value: M.MethodMetadata) -> M.AnnotationMetadata:
  match value:
    case M.MethodMetadata{owner, method, metadata, signature, parameters, lines}: metadata

def method_signature_found(found: Result<&2, &2, String, M.MethodMetadata>) -> String:
  match found:
    case Fail{error}: ""
    case Done{M.MethodMetadata{owner, method, metadata, signature, parameters, lines}}: signature

def method_signature(+vm: M.VM, method: M.LoadedMethod) -> String:
  method_signature_found(method_metadata_value(vm, M.loaded_method_id(method)))

# ---- Generic declaration scopes (the JDK's CoreReflectionFactory chain) ----
# A method's own type parameters come first, then its class's, then the class's
# enclosing method (EnclosingMethod) or enclosing class.

def method_scope_kind(+vm: M.VM, method: M.LoadedMethod) -> U32:
  Bool.pick(U32, String.eq(Sy.text(S.symbols(vm), M.loaded_method_name(method)), "<init>"), 3, 2)

@unsafe def method_scopes(fuel: Nat, +vm: M.VM, +method: M.LoadedMethod) -> +List<G.Scope>:
  Con{G.Scope{method_scope_kind(vm, method), M.loaded_method_id(method), G.method_variables(method_signature(vm, method))}, class_scopes(fuel, vm, M.loaded_method_owner(method))}

@unsafe def scope_enclosing_class(empty: Bool, fuel: Nat, +vm: M.VM, +name: String) -> +List<G.Scope>:
  match empty:
    case True{}: Nil{}
    case False{}: class_scopes(fuel, vm, class_id(vm, name))

@unsafe def scope_from_method(found: Maybe<&2, M.LoadedMethod>, fuel: Nat, +vm: M.VM, +id: U32) -> +List<G.Scope>:
  match found:
    case Some{method}: method_scopes(fuel, vm, method)
    case None{}:
      +enclosing : String = enclosing_name(vm, id)
      scope_enclosing_class(String.is_empty(enclosing), fuel, vm, enclosing)

@unsafe def scope_enclosing_method(named: Bool, fuel: Nat, +vm: M.VM, +id: U32, +nesting: M.Nesting) -> +List<G.Scope>:
  match named:
    case True{}: scope_from_method(method_named(vm, S.methods(vm), class_id(vm, nesting_enclosing_class(nesting)), nesting_method(nesting), nesting_descriptor(nesting)), fuel, vm, id)
    case False{}: scope_from_method(None{}, fuel, vm, id)

@unsafe def class_scopes(fuel: Nat, +vm: M.VM, +id: U32) -> +List<G.Scope>:
  match fuel id:
    case 0n _: Nil{}
    case _ 4294967295: Nil{}
    case 1n+p _:
      +nesting : M.Nesting = class_nesting_of(vm, id)
      Con{G.Scope{1, id, G.class_variables(class_signature(vm, id))}, scope_enclosing_method(Bool.not(String.is_empty(nesting_method(nesting))), p, vm, id, nesting)}

@unsafe def ensure_arrays(+vm: M.VM, names: +List<String>) -> Result<&2, &2, String, M.VM>:
  match names:
    case Nil{}: Done{vm}
    case Con{name, rest}:
      do Result<&2, &2, String, M.VM>:
        +next : M.VM <- ensure_array_class(vm, name)
        result : M.VM <- ensure_arrays(next, rest)
        return result

@unsafe def method_generic_return(+vm: M.VM, +method: M.LoadedMethod, +text: String) -> Result<&2, &2, String, G.TypeRef>:
  do Result<&2, &2, String, G.TypeRef>:
    +ready : M.VM <- ensure_arrays(vm, G.method_arrays(text))
    result : G.TypeRef <- G.return_ref(ready, text, method_scope_kind(ready, method), M.loaded_method_id(method), class_scopes(64n, ready, M.loaded_method_owner(method)))
    return result

@unsafe def method_generic_parameters(+vm: M.VM, +method: M.LoadedMethod, +text: String) -> Result<&2, &2, String, G.TypeRefs>:
  do Result<&2, &2, String, G.TypeRefs>:
    +ready : M.VM <- ensure_arrays(vm, G.method_arrays(text))
    result : G.TypeRefs <- G.parameter_refs(ready, text, method_scope_kind(ready, method), M.loaded_method_id(method), class_scopes(64n, ready, M.loaded_method_owner(method)))
    return result

@unsafe def method_generic_thrown(+vm: M.VM, +method: M.LoadedMethod, +text: String) -> Result<&2, &2, String, G.TypeRefs>:
  do Result<&2, &2, String, G.TypeRefs>:
    +ready : M.VM <- ensure_arrays(vm, G.method_arrays(text))
    result : G.TypeRefs <- G.thrown_refs(ready, text, method_scope_kind(ready, method), M.loaded_method_id(method), class_scopes(64n, ready, M.loaded_method_owner(method)))
    return result

@unsafe def method_generic_return_id(+vm: M.VM, +method_id: U32, +text: String) -> Result<&2, &2, String, G.TypeRef>:
  do Result<&2, &2, String, G.TypeRef>:
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), method_id), "InvalidState: method id")
    result : G.TypeRef <- method_generic_return(vm, method, text)
    return result

@unsafe def field_generic(+vm: M.VM, +owner: U32, +text: String) -> Result<&2, &2, String, G.TypeRef>:
  do Result<&2, &2, String, G.TypeRef>:
    +ready : M.VM <- ensure_arrays(vm, G.method_arrays("()" ++ text))
    result : G.TypeRef <- G.field_ref(ready, text, class_scopes(64n, ready, owner))
    return result

@unsafe def field_generic_id(+vm: M.VM, +field_id: U32, +text: String) -> Result<&2, &2, String, G.TypeRef>:
  do Result<&2, &2, String, G.TypeRef>:
    +field : M.LoadedField <- S.require(M.LoadedField, M.nth(M.LoadedField, S.fields(vm), field_id), "InvalidState: field id")
    result : G.TypeRef <- field_generic(vm, M.loaded_field_owner(field), text)
    return result

@unsafe def class_generic_super(+vm: M.VM, +target: U32, +text: String) -> Result<&2, &2, String, G.TypeRef>:
  do Result<&2, &2, String, G.TypeRef>:
    +ready : M.VM <- ensure_arrays(vm, G.class_arrays(text))
    result : G.TypeRef <- G.superclass_ref(ready, text, class_scopes(64n, ready, target))
    return result

@unsafe def class_generic_interfaces(+vm: M.VM, +target: U32, +text: String) -> Result<&2, &2, String, G.TypeRefs>:
  do Result<&2, &2, String, G.TypeRefs>:
    +ready : M.VM <- ensure_arrays(vm, G.class_arrays(text))
    result : G.TypeRefs <- G.interface_refs(ready, text, class_scopes(64n, ready, target))
    return result
def field_signature_found(found: Result<&2, &2, String, M.FieldMetadata>) -> String:
  match found:
    case Fail{error}: ""
    case Done{M.FieldMetadata{owner, field, metadata, signature}}: signature

def field_signature(+vm: M.VM, field: M.LoadedField) -> String:
  field_signature_found(field_metadata_value(vm, M.loaded_field_id(field)))

def forget_pool(pool: +List<M.Constant>, signature: String) -> String:
  match pool:
    case Nil{}: signature
    case Con{head, tail}: forget_pool(tail, signature)

def class_signature_found(found: Result<&2, &2, String, M.ClassMetadata>) -> String:
  match found:
    case Fail{error}: ""
    case Done{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, pool, signature, nesting, source}}: forget_pool(pool, signature)

def class_signature(+vm: M.VM, +target: U32) -> String:
  class_signature_found(class_metadata_value(vm, target))


def pack_path(path: +List<U32>) -> +List<U32>:
  match path:
    case Nil{}: Nil{}
    case Con{kind, Con{index, rest}}: Con{(kind * 256 + index : U32), pack_path(rest)}
    case Con{kind, Nil{}}: Nil{}

def path_equal(left: +List<U32>, right: +List<U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{left_head, left_tail} Con{right_head, right_tail}: U32.is_eq(left_head, right_head) && path_equal(left_tail, right_tail)
    case _ _: False{}

def slot_bits(values: +List<M.Slot>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}: Con{bits_of(head), slot_bits(tail)}

def field_annotation_source(+vm: M.VM, +field: M.LoadedField) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    class_metadata : M.ClassMetadata <- class_metadata_value(vm, M.loaded_field_owner(field))
    field_metadata : M.FieldMetadata <- field_metadata_value(vm, M.loaded_field_id(field))
    result : AnnotationMetadataRef = AnnotationMetadataRef{vm, class_metadata_pool(class_metadata), field_metadata_annotations(field_metadata)}
    return result

def method_annotation_source(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    class_metadata : M.ClassMetadata <- class_metadata_value(vm, M.loaded_method_owner(method))
    method_metadata : M.MethodMetadata <- method_metadata_value(vm, M.loaded_method_id(method))
    result : AnnotationMetadataRef = AnnotationMetadataRef{vm, class_metadata_pool(class_metadata), method_metadata_annotations(method_metadata)}
    return result

def annotation_value_outcome(value: AnnotationValueRef) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case AnnotationValueRef{vm, slot}: AR.outcome(AR.Value{vm, slot})

@unsafe def annotation_initialization_target(vm: M.VM, reference: U32) -> Result<&2, &2, String, U32>:
  AR.initialization_target(vm, reference)

def annotation_element_invoke(+vm: M.VM, +args: +List<M.Slot>, +owner: U32, +name: String, +descriptor: String, fields: +List<M.Binding>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, annotation_method_find(S.methods(vm), owner, name, S.symbols(vm)), "java/lang/NoSuchMethodError: annotation element " ++ name)
    value : AR.Value <- AR.effective(vm, method, H.binding_find(fields, M.loaded_method_id(method)))
    result : O.Outcome <- AR.outcome(value)
    return result


@unsafe def annotation_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    left : M.Slot <- slot0(args)
    right : M.Slot <- slot1(args)
    value : AR.Value <- AR.equal_ref(vm, bits_of(left), bits_of(right), "")
    result : O.Outcome <- AR.outcome(value)
    return result

@unsafe def annotation_hash(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    value : AR.Value <- AR.hash_ref(vm, bits_of(receiver), "")
    result : O.Outcome <- AR.outcome(value)
    return result

def annotation_receiver(args: +List<M.Slot>) -> M.Slot:
  match args:
    case Con{slot, rest}: slot
    case Nil{}: M.Slot{3, 0}

@unsafe def annotation_invoke_name(+vm: M.VM, +args: +List<M.Slot>, +name: String, +descriptor: String, +element: U32, +fields: +List<M.Binding>) -> Result<&2, &2, String, O.Outcome>:
  match name:
    case "annotationType": class_mirror_out(vm, element)
    case "equals": annotation_equals(vm, args)
    case "hashCode": annotation_hash(vm, args)

    case "toString": annotation_to_string(vm, bits_of(annotation_receiver(args)))
    case _: annotation_element_invoke(vm, args, element, name, descriptor, fields)

def annotation_invoke_entry(+vm: M.VM, +args: +List<M.Slot>, +name: String, +descriptor: String, entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}:
      annotation_invoke_name(vm, args, name, descriptor, element, fields)

def annotation_invoke(+vm: M.VM, +args: +List<M.Slot>, +name: String, +descriptor: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- annotation_invoke_entry(vm, args, name, descriptor, entry)
    return result
def reflect_annotation_binding_found(found: Maybe<&2, M.Slot>) -> Result<&2, &2, String, M.Slot>:
  match found:
    case None{}: Fail{"java/lang/IllegalArgumentException"}
    case Some{value}: Done{value}

def reflect_annotation_binding(entry: M.HeapEntry, id: U32) -> Result<&2, &2, String, M.Slot>:
  reflect_annotation_binding_found(H.binding_find(entry_fields(entry), id))


def reflect_field_from_args(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, M.LoadedField>:
  do Result<&2, &2, String, M.LoadedField>:
    receiver : M.Slot <- slot0(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    member : M.Slot <- reflect_annotation_binding(entry, 1)
    field : M.LoadedField <- S.require(M.LoadedField, M.nth(M.LoadedField, S.fields(vm), bits_of(member)), "java/lang/NoSuchFieldException")
    return field

def reflect_method_from_args(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, M.LoadedMethod>:
  do Result<&2, &2, String, M.LoadedMethod>:
    receiver : M.Slot <- slot0(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    member : M.Slot <- reflect_annotation_binding(entry, 1)
    method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), bits_of(member)), "java/lang/NoSuchMethodException")
    return method

def reflect_annotation_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    annotation : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(annotation))
    checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 8), "java/lang/IllegalArgumentException")
    return class_name_text(vm, entry_element(entry))

def reflect_annotation_present_found(+vm: M.VM, found: Maybe<&2, M.Annotation>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: bool_out(vm, False{})
    case Some{annotation}: bool_out(vm, True{})

def reflect_annotation_present_source(+vm: M.VM, source: AnnotationMetadataRef, +name: String) -> Result<&2, &2, String, O.Outcome>:
  reflect_annotation_present_found(vm, class_annotation_result_from(source, name))

def reflect_field_source(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    field : M.LoadedField <- reflect_field_from_args(vm, args)
    result : AnnotationMetadataRef <- field_annotation_source(vm, field)
    return result

def reflect_method_source(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    result : AnnotationMetadataRef <- method_annotation_source(vm, method)
    return result

def reflect_field_is_annotation_present(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_field_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    result : O.Outcome <- reflect_annotation_present_source(vm, source, name)
    return result

def reflect_method_is_annotation_present(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_method_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    result : O.Outcome <- reflect_annotation_present_source(vm, source, name)
    return result

def reflect_field_get_annotation(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_field_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    result : O.Outcome <- class_annotation_one_from(source, name)
    return result

def reflect_method_get_annotation(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_method_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    result : O.Outcome <- class_annotation_one_from(source, name)
    return result

def reflect_field_get_annotations_by_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_field_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    result : O.Outcome <- annotation_arrays_by_type_from(source, name)
    return result

def reflect_method_get_annotations_by_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_method_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    result : O.Outcome <- annotation_arrays_by_type_from(source, name)
    return result

def reflect_constructor_get_annotations_by_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_method_get_annotations_by_type(vm, args)

def reflect_field_get_annotations(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_field_source(vm, args)
    result : O.Outcome <- class_annotations_array_from(source)
    return result

def reflect_method_get_annotations(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_method_source(vm, args)
    result : O.Outcome <- class_annotations_array_from(source)
    return result


def annotation_nested_alloc_result(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, AnnotationValueRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{vm, reference}}: Done{AnnotationValueRef{vm, M.Slot{3, reference}}}

def annotation_array_ref(value: AnnotationValueRefs) -> Result<&2, &2, String, AnnotationValueRef>:
  match value:
    case AnnotationValueRefs{+vm, +slots}:
      do Result<&2, &2, String, AnnotationValueRef>:
        +array_class : U32 = class_id(vm, "[Ljava/lang/annotation/Annotation;")
        +component : U32 = class_id(vm, "java/lang/annotation/Annotation")
        array_checked : Unit <- S.check(U32.is_ne(array_class, 4294967295), "UnsupportedFeature: parameter annotation array class")
        component_checked : Unit <- S.check(U32.is_ne(component, 4294967295), "UnsupportedFeature: parameter annotation component")
        result : AnnotationValueRef <- annotation_nested_alloc_result(H.allocate(vm, H.reference_array_entry(array_class, component, slots)))
        return result

def parameter_annotation_continue(value_ref: AnnotationValueRef, +rest: +List<+List<M.Annotation>>, +pool: +List<M.Constant>, +acc: +List<M.Slot>, next: M.VM -> M.Slot -> Result<&2, &2, String, ParameterAnnotationRefs>) -> Result<&2, &2, String, ParameterAnnotationRefs>:
  match value_ref:
    case AnnotationValueRef{+vm, slot}: next(vm, slot)

@unsafe def parameter_annotation_arrays(+values: +List<+List<M.Annotation>>, +vm: M.VM, +pool: +List<M.Constant>, +acc: +List<M.Slot>) -> Result<&2, &2, String, ParameterAnnotationRefs>:
  match values:
    case Nil{}: Done{ParameterAnnotationRefs{vm, M.reverse(M.Slot, acc)}}
    case Con{+annotations, rest}:
      do Result<&2, &2, String, ParameterAnnotationRefs>:
        refs : AnnotationValueRefs <- annotation_refs(annotations, vm, pool, Nil{})
        array_ref : AnnotationValueRef <- annotation_array_ref(refs)
        result : ParameterAnnotationRefs <- parameter_annotation_continue(array_ref, rest, pool, acc, next_vm => slot => parameter_annotation_arrays(rest, next_vm, pool, Con{slot, acc}))
        return result

def parameter_annotation_array_result(value: ParameterAnnotationRefs) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case ParameterAnnotationRefs{+vm, +slots}:
      do Result<&2, &2, String, O.Outcome>:
        +array_class : U32 = class_id(vm, "[[Ljava/lang/annotation/Annotation;")
        +component : U32 = class_id(vm, "[Ljava/lang/annotation/Annotation;")
        checked : Unit <- S.check(U32.is_ne(array_class, 4294967295) && U32.is_ne(component, 4294967295), "UnsupportedFeature: parameter annotation array class")
        result : O.Outcome <- annotation_array_alloc_outcome(H.allocate(vm, H.reference_array_entry(array_class, component, slots)))
        return result

def method_parameter_annotations(source: AnnotationMetadataRef) -> Result<&2, &2, String, O.Outcome>:
  match source:
    case AnnotationMetadataRef{+vm, +pool, metadata}:
      do Result<&2, &2, String, O.Outcome>:
        arrays : ParameterAnnotationRefs <- parameter_annotation_arrays(metadata_parameters(metadata), vm, pool, Nil{})
        result : O.Outcome <- parameter_annotation_array_result(arrays)
        return result

def annotation_default_optional_from_maybe(+vm: M.VM, +pool: +List<M.Constant>, found: Maybe<&2, M.AnnotationValue>, +descriptor: String) -> Result<&2, &2, String, Maybe<&2, AnnotationValueRef>>:
  match found:
    case None{}: Done{None{}}
    case Some{value}:
      do Result<&2, &2, String, Maybe<&2, AnnotationValueRef>>:
        result : AnnotationValueRef <- annotation_value(vm, pool, value, AR.result_descriptor(String.to_list(descriptor)))
        return Some{result}

def annotation_default_optional_method(+vm: M.VM, +pool: +List<M.Constant>, method_metadata: M.MethodMetadata, +descriptor: String) -> Result<&2, &2, String, Maybe<&2, AnnotationValueRef>>:
  match method_metadata:
    case M.MethodMetadata{owner, method, metadata, signature, parameters, lines}: annotation_default_optional_from_maybe(vm, pool, metadata_default(metadata), descriptor)

def annotation_default_optional_source(source: AnnotationMetadataRef, +method_id: U32, +descriptor: String) -> Result<&2, &2, String, Maybe<&2, AnnotationValueRef>>:
  match source:
    case AnnotationMetadataRef{+vm, +pool, metadata}:
      do Result<&2, &2, String, Maybe<&2, AnnotationValueRef>>:
        method_metadata : M.MethodMetadata <- method_metadata_value(vm, method_id)
        result : Maybe<&2, AnnotationValueRef> <- annotation_default_optional_method(vm, pool, method_metadata, descriptor)
        return result

def annotation_optional_outcome(+vm: M.VM, found: Maybe<&2, AnnotationValueRef>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: ref_out(vm, 0)
    case Some{value}: annotation_value_outcome(value)

def boolean_singleton_out(+vm: M.VM, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  returned(vm, Some{M.Slot{3, Bool.pick(U32, U32.is_ne(bits_of(value), 0), 3, 4)}})
def annotation_default_box_alloc(+vm: M.VM, +name: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, name), [M.Binding{0, value}])), vm2 => reference => ref_out(vm2, reference))

def annotation_default_wide_box(+vm: M.VM, +name: String, +descriptor: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    field : U32 <- wrapper_value_field_id(vm, name, descriptor)
    result : O.Outcome <- alloc_result(H.allocate(vm, H.object_entry(class_id(vm, name), [M.Binding{field, value}])), vm2 => reference => ref_out(vm2, reference))
    return result

def annotation_default_reflect_slot(+vm: M.VM, name: String, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match name:
    case "long": annotation_default_wide_box(vm, "java/lang/Long", "J", value)
    case "double": annotation_default_wide_box(vm, "java/lang/Double", "D", value)
    case "int": annotation_default_box_alloc(vm, "java/lang/Integer", value)
    case "boolean": boolean_singleton_out(vm, value)
    case "byte": annotation_default_box_alloc(vm, "java/lang/Byte", value)
    case "short": annotation_default_box_alloc(vm, "java/lang/Short", value)
    case "char": annotation_default_box_alloc(vm, "java/lang/Character", value)
    case "float": annotation_default_box_alloc(vm, "java/lang/Float", value)
    case _: annotation_value_outcome(AnnotationValueRef{vm, value})

def annotation_default_reflect_outcome(+vm: M.VM, +descriptor: String, found: Maybe<&2, AnnotationValueRef>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: ref_out(vm, 0)
    case Some{AnnotationValueRef{+vm, slot}}: annotation_default_reflect_slot(vm, method_return_name(descriptor), slot)

def reflect_method_get_parameter_annotations(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_method_source(vm, args)
    result : O.Outcome <- method_parameter_annotations(source)
    return result

def reflect_method_get_default_value(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    source : AnnotationMetadataRef <- class_annotation_values(vm, M.loaded_method_owner(method))
    +descriptor : String = annotation_method_descriptor(vm, method)
    found : Maybe<&2, AnnotationValueRef> <- annotation_default_optional_source(source, M.loaded_method_id(method), descriptor)
    result : O.Outcome <- annotation_default_reflect_outcome(vm, descriptor, found)
    return result


def field_cons(found: Maybe<&2, M.LoadedField>, acc: +List<M.LoadedField>) -> +List<M.LoadedField>:
  match found:
    case None{}: acc
    case Some{field}: Con{field, acc}

def method_cons(found: Maybe<&2, M.LoadedMethod>, acc: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match found:
    case None{}: acc
    case Some{method}: Con{method, acc}
def declared_fields(fields: +List<M.LoadedField>, +owner: U32, +acc: +List<M.LoadedField>) -> +List<M.LoadedField>:

  match fields:
    case Nil{}: M.reverse(M.LoadedField, acc)
    case Con{+field, +rest}:
      field_cons(Bool.pick(Maybe<&2, M.LoadedField>, U32.is_eq(M.loaded_field_owner(field), owner), Some{field}, None{}), declared_fields(rest, owner, acc))
def class_component(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    +name : String = class_name_text(vm, target)
    result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, String.starts_with(name, "["), class_component_result(vm, name), ref_out(vm, 0))
    return result

def declared_methods(methods: +List<M.LoadedMethod>, +owner: U32, +symbols: +List<String>, +acc: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match methods:
    case Nil{}: M.reverse(M.LoadedMethod, acc)
    case Con{+method, +rest}:
      +name = Sy.text(symbols, M.loaded_method_name(method))
      method_cons(Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), owner) && Bool.not(String.eq(name, "<init>")) && Bool.not(String.eq(name, "<clinit>")), Some{method}, None{}), declared_methods(rest, owner, symbols, acc))

def declared_constructors(methods: +List<M.LoadedMethod>, +owner: U32, +symbols: +List<String>, +acc: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match methods:
    case Nil{}: M.reverse(M.LoadedMethod, acc)
    case Con{+method, +rest}:
      method_cons(Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), owner) && String.eq(Sy.text(symbols, M.loaded_method_name(method)), "<init>"), Some{method}, None{}), declared_constructors(rest, owner, symbols, acc))
def proxy_declared_constructor_proxy(+vm: M.VM, owner: U32) -> Result<&2, &2, String, +List<M.LoadedMethod>>:
  do Result<&2, &2, String, +List<M.LoadedMethod>>:
    method : M.LoadedMethod <- proxy_constructor_method(vm, owner)
    return [method]

def proxy_declared_constructors(+vm: M.VM, +owner: U32, +ordinary: +List<M.LoadedMethod>) -> Result<&2, &2, String, +List<M.LoadedMethod>>:
  Bool.pick(Result<&2, &2, String, +List<M.LoadedMethod>>, proxy_class_is_synthetic(vm, owner), proxy_declared_constructor_proxy(vm, owner), Done{ordinary})

def reflect_alloc_found(allocation: H.Allocation, cont: M.VM -> U32 -> Result<&2, &2, String, ReflectRefs>) -> Result<&2, &2, String, ReflectRefs>:
  match allocation:
    case H.Allocation{vm, reference}: cont(vm, reference)

def reflect_alloc_result(result: Result<&2, &2, String, H.Allocation>, cont: M.VM -> U32 -> Result<&2, &2, String, ReflectRefs>) -> Result<&2, &2, String, ReflectRefs>:
  match result:
    case Fail{error}: Fail{error}
    case Done{allocation}: reflect_alloc_found(allocation, cont)
def primitive_descriptor(tag: U32) -> String:
  match tag:
    case 66: "B"
    case 67: "C"
    case 68: "D"
    case 70: "F"
    case 73: "I"
    case 74: "J"
    case 83: "S"
    case 90: "Z"
    case 86: "V"
    case _: ""
def type_annotation_info_index(info: +List<U32>) -> U32:
  match info:
    case Nil{}: 4294967295
    case Con{value, rest}: value

# The index a target names: none for fields and returns, parameter and bound
# index together (parameter * 256 + bound) for type parameter bounds, else the
# first target_info value (parameter, type parameter or supertype index).
def type_annotation_site_index(+target: U32, +info: +List<U32>) -> U32:
  match info:
    case Con{+first, Con{+second, rest}}: Bool.pick(U32, U32.is_eq(target, 17) || U32.is_eq(target, 18), U32.add(U32.mul(first, 256), second), first)
    case _: type_annotation_info_index(info)

def type_annotation_matches(value: M.TypeAnnotation, +target: U32, +index: U32, +expected: +List<U32>) -> Bool:
  match value:
    case M.TypeAnnotation{targetType, +targetInfo, +path, annotation}:
      U32.is_eq(targetType, target) && Bool.or(U32.is_eq(target, 20), Bool.or(U32.is_eq(target, 19), U32.is_eq(type_annotation_site_index(target, targetInfo), index))) && path_equal(pack_path(path), expected)

def type_annotation_values(+values: +List<M.TypeAnnotation>, +target: U32, +index: U32, +expected: +List<U32>, +acc: +List<M.Annotation>) -> +List<M.Annotation>:
  match values:
    case Nil{}: M.reverse(M.Annotation, acc)
    case Con{+value, rest}:
      match value:
        case M.TypeAnnotation{targetType, targetInfo, path, annotation}:
          type_annotation_values(rest, target, index, expected, Bool.pick(+List<M.Annotation>, type_annotation_matches(value, target, index, expected), Con{annotation, acc}, acc))

def method_type_annotation_source(+vm: M.VM, +method: M.LoadedMethod, +target: U32, +index: U32, +expected: +List<U32>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    class_metadata : M.ClassMetadata <- class_metadata_value(vm, M.loaded_method_owner(method))
    method_metadata : M.MethodMetadata <- method_metadata_value(vm, M.loaded_method_id(method))
    metadata : M.AnnotationMetadata = method_metadata_annotations(method_metadata)
    +annotations : +List<M.Annotation> = type_annotation_values(metadata_type_annotations(metadata), target, index, expected, Nil{})
    result : AnnotationMetadataRef = AnnotationMetadataRef{vm, class_metadata_pool(class_metadata), M.AnnotationMetadata{0, Nil{}, annotations, Nil{}, Nil{}, None{}, Nil{}, Nil{}, Nil{}}}
    return result
def field_type_annotation_source(+vm: M.VM, +field_id: U32, +target: U32, +index: U32, +expected: +List<U32>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    field : M.LoadedField <- S.require(M.LoadedField, M.nth(M.LoadedField, S.fields(vm), field_id), "java/lang/NoSuchFieldException")
    class_metadata : M.ClassMetadata <- class_metadata_value(vm, M.loaded_field_owner(field))
    field_metadata : M.FieldMetadata <- field_metadata_value(vm, field_id)
    metadata : M.AnnotationMetadata = field_metadata_annotations(field_metadata)
    +annotations : +List<M.Annotation> = type_annotation_values(metadata_type_annotations(metadata), target, index, expected, Nil{})
    result : AnnotationMetadataRef = AnnotationMetadataRef{vm, class_metadata_pool(class_metadata), M.AnnotationMetadata{0, Nil{}, annotations, Nil{}, Nil{}, None{}, Nil{}, Nil{}, Nil{}}}
    return result


def annotated_ref_slots(refs: +List<U32>) -> +List<M.Slot>:
  match refs:
    case Nil{}: Nil{}
    case Con{reference, rest}: Con{M.Slot{3, reference}, annotated_ref_slots(rest)}

def annotated_type_refs_array(value: ReflectRefs) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case ReflectRefs{+vm, +refs}:
      alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/reflect/AnnotatedType;"), class_id(vm, "java/lang/reflect/AnnotatedType"), annotated_ref_slots(refs))), vm2 => reference => ref_out(vm2, reference))

@unsafe def reflect_annotated_type_alloc(+vm: M.VM, +method_id: U32, +target: U32, +index: U32, count: Nat, +refs: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match count:
    case 0n: Done{ReflectRefs{vm, M.reverse(U32, refs)}}
    case 1n+p:
      reflect_alloc_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/AnnotatedType"), [M.Binding{0, M.Slot{1, method_id}}, M.Binding{1, M.Slot{1, target}}, M.Binding{2, M.Slot{1, index}}])), vm2 => reference => reflect_annotated_type_alloc(vm2, method_id, target, (index + 1 : U32), p, Con{reference, refs}))

def reflect_annotated_type_one(+vm: M.VM, method_id: U32, target: U32) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/AnnotatedType"), [M.Binding{0, M.Slot{1, method_id}}, M.Binding{1, M.Slot{1, target}}, M.Binding{2, M.Slot{1, 0}}])), vm2 => reference => ref_out(vm2, reference))

def reflect_method_get_annotated_parameter_types(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    +descriptor : String = annotation_method_descriptor(vm, method)
    parsed : M.Descriptor <- D.parse_method(descriptor)
    refs : ReflectRefs <- reflect_annotated_type_alloc(vm, M.loaded_method_id(method), 22, 0, U32.to_nat(D.parameter_count(parsed)), Nil{})
    result : O.Outcome <- annotated_type_refs_array(refs)
    return result

def annotated_type_name(parameterized: Bool) -> String:
  match parameterized:
    case True{}: "java/lang/reflect/AnnotatedParameterizedType"
    case False{}: "java/lang/reflect/AnnotatedType"

def annotated_type_stored(+vm: M.VM, method_id: U32, target: U32, type_ref: U32, parameterized: Bool) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, annotated_type_name(parameterized)), [M.Binding{0, M.Slot{1, method_id}}, M.Binding{1, M.Slot{1, target}}, M.Binding{2, M.Slot{1, 0}}, M.Binding{3, M.Slot{3, 0}}, M.Binding{4, M.Slot{3, type_ref}}])), vm2 => reference => ref_out(vm2, reference))

def annotated_type_from_ref(+vm: M.VM, method_id: U32, target: U32, +reference: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    result : O.Outcome <- annotated_type_stored(vm, method_id, target, reference, String.eq(class_name_text(vm, H.entry_class(entry)), "sun/reflect/generics/reflectiveObjects/ParameterizedTypeImpl"))
    return result

def annotated_return_parsed(parsed: Result<&2, &2, String, G.TypeRef>, +vm: M.VM, method_id: U32) -> Result<&2, &2, String, O.Outcome>:
  match parsed:
    case Fail{error}: reflect_annotated_type_one(vm, method_id, 20)
    case Done{G.TypeRef{next, reference}}: annotated_type_from_ref(next, method_id, 20, reference)

def annotated_return_text(+vm: M.VM, +method_id: U32, +text: String, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: reflect_annotated_type_one(vm, method_id, 20)
    case False{}: annotated_return_parsed(method_generic_return_id(vm, method_id, text), vm, method_id)

def reflect_method_get_annotated_return_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    +text : String = method_signature(vm, method)
    result : O.Outcome <- annotated_return_text(vm, M.loaded_method_id(method), text, String.is_empty(text))
    return result

def path_bits_slot(+vm: M.VM, slot: M.Slot) -> Result<&2, &2, String, +List<U32>>:
  match slot:
    case M.Slot{tag, 0}: Done{Nil{}}
    case M.Slot{tag, reference}:
      do Result<&2, &2, String, +List<U32>>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        return slot_bits(entry_values(entry))
    case M.Wide{tag, high, low}: Fail{"java/lang/IllegalArgumentException"}
    case M.Unusable{}: Fail{"java/lang/IllegalArgumentException"}
def path_bits_found(+vm: M.VM, found: Maybe<&2, M.Slot>) -> Result<&2, &2, String, +List<U32>>:
  match found:
    case None{}: Done{Nil{}}
    case Some{slot}: path_bits_slot(vm, slot)

def reflect_annotated_type_source_kind(+vm: M.VM, entry: M.HeapEntry, member: M.Slot, +target: U32, +index: U32, +expected: +List<U32>, field_site: Bool) -> Result<&2, &2, String, AnnotationMetadataRef>:
  match field_site:
    case True{}: field_type_annotation_source(vm, bits_of(member), target, index, expected)
    case False{}:
      do Result<&2, &2, String, AnnotationMetadataRef>:
        +method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), bits_of(member)), "java/lang/NoSuchMethodException")
        result : AnnotationMetadataRef <- method_type_annotation_source(vm, method, target, index, expected)
        return result

@unsafe def reflect_annotated_type_source(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    member : M.Slot <- reflect_annotation_binding(entry, 0)
    target_slot : M.Slot <- reflect_annotation_binding(entry, 1)
    index_slot : M.Slot <- reflect_annotation_binding(entry, 2)
    +expected : +List<U32> <- path_bits_found(vm, H.binding_find(entry_fields(entry), 3))
    +target : U32 = bits_of(target_slot)
    result : AnnotationMetadataRef <- annotated_source(vm, bits_of(member), target, bits_of(index_slot), expected)
    return result

def reflect_annotated_type_is_annotation_present(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_annotated_type_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    result : O.Outcome <- reflect_annotation_present_source(vm, source, name)
    return result

def reflect_annotated_type_get_annotation(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_annotated_type_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    result : O.Outcome <- class_annotation_one_from(source, name)
    return result

def reflect_annotated_type_get_annotations(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- reflect_annotated_type_source(vm, args)
    result : O.Outcome <- class_annotations_array_from(source)
    return result

def primitive_class_name(tag: U32) -> String:
  match tag:
    case 66: "byte"
    case 67: "char"
    case 68: "double"
    case 70: "float"
    case 73: "int"
    case 74: "long"
    case 83: "short"
    case 90: "boolean"
    case 86: "void"
    case _: ""

def jvm_type_descriptor(value: M.JvmType) -> String:
  match value:
    case M.Primitive{tag}: primitive_descriptor(tag)
    case M.ObjectType{name}: "L" ++ name ++ ";"
    case M.ArrayType{element}: "[" ++ jvm_type_descriptor(element)

def jvm_type_class_name(value: M.JvmType) -> String:
  match value:
    case M.Primitive{tag}: primitive_class_name(tag)
    case M.ObjectType{name}: name
    case M.ArrayType{element}: "[" ++ jvm_type_descriptor(element)
def annotated_type_value(parsed: M.Descriptor, target: U32, index: U32) -> Result<&2, &2, String, M.JvmType>:
  match target:
    case 20: Done{D.result_type(parsed)}
    case 22: S.require(M.JvmType, M.nth(M.JvmType, D.parameter_types(parsed), index), "java/lang/NoSuchMethodException")
    case _: Fail{"java/lang/NoSuchMethodException"}

def binding_bits(found: Maybe<&2, M.Slot>) -> U32:
  match found:
    case None{}: 0
    case Some{slot}: M.slot_bits(slot)

def reflect_annotated_field_erased(+vm: M.VM, +field_id: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    field : M.LoadedField <- S.require(M.LoadedField, M.nth(M.LoadedField, S.fields(vm), field_id), "java/lang/NoSuchFieldException")
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))
    result : O.Outcome <- descriptor_mirror(vm, descriptor)
    return result

def reflect_annotated_type_erased_kind(+vm: M.VM, member: M.Slot, +target: U32, +index: U32, field_site: Bool) -> Result<&2, &2, String, O.Outcome>:
  match field_site:
    case True{}: reflect_annotated_field_erased(vm, bits_of(member))
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), bits_of(member)), "java/lang/NoSuchMethodException")
        descriptor : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
        parsed : M.Descriptor <- D.parse_method(descriptor)
        typ : M.JvmType <- annotated_type_value(parsed, target, index)
        +class_target : U32 = class_id(vm, jvm_type_class_name(typ))
        checked : Unit <- S.check(U32.is_ne(class_target, 4294967295), "java/lang/NoClassDefFoundError")
        result : O.Outcome <- class_mirror_out(vm, class_target)
        return result

def reflect_annotated_type_erased(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    member : M.Slot <- reflect_annotation_binding(entry, 0)
    target_slot : M.Slot <- reflect_annotation_binding(entry, 1)
    index_slot : M.Slot <- reflect_annotation_binding(entry, 2)
    +target : U32 = bits_of(target_slot)
    result : O.Outcome <- reflect_annotated_type_erased_kind(vm, member, target, bits_of(index_slot), U32.is_eq(target, 19))
    return result

def stored_or_erased(+vm: M.VM, +args: +List<M.Slot>, stored: U32, missing: Bool) -> Result<&2, &2, String, O.Outcome>:
  match missing:
    case False{}: ref_out(vm, stored)
    case True{}: reflect_annotated_type_erased(vm, args)

def reflect_annotated_type_get_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +stored : U32 = binding_bits(H.binding_find(entry_fields(entry), 4))
    result : O.Outcome <- stored_or_erased(vm, args, stored, U32.is_eq(stored, 0))
    return result
def reflect_annotated_type_get_owner(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  ref_out(vm, 0)

def empty_annotated_array(+vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/reflect/AnnotatedType;"), class_id(vm, "java/lang/reflect/AnnotatedType"), Nil{})), vm2 => reference => ref_out(vm2, reference))

def step_path(+vm: M.VM, index: U32) -> Result<&2, &2, String, G.TypeRef>:
  G.alloc_ref(H.allocate(vm, H.primitive_array_entry(class_id(vm, "[I"), 1, [M.Slot{1, (768 + index : U32)}])))

def child_annotated(+vm: M.VM, method_id: U32, target: U32, index: U32, type_ref: U32, path_ref: U32, parameterized: Bool) -> Result<&2, &2, String, G.TypeRef>:
  G.alloc_ref(H.allocate(vm, H.object_entry(class_id(vm, annotated_type_name(parameterized)), [M.Binding{0, M.Slot{1, method_id}}, M.Binding{1, M.Slot{1, target}}, M.Binding{2, M.Slot{1, index}}, M.Binding{3, M.Slot{3, path_ref}}, M.Binding{4, M.Slot{3, type_ref}}])))

def child_from_type(+vm: M.VM, method_id: U32, target: U32, index: U32, +type_ref: U32, path_ref: U32) -> Result<&2, &2, String, G.TypeRef>:
  do Result<&2, &2, String, G.TypeRef>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), type_ref)
    result : G.TypeRef <- child_annotated(vm, method_id, target, index, type_ref, path_ref, String.eq(class_name_text(vm, H.entry_class(entry)), "sun/reflect/generics/reflectiveObjects/ParameterizedTypeImpl"))
    return result

def child_from_path(parsed: Result<&2, &2, String, G.TypeRef>, +vm: M.VM, method_id: U32, target: U32, index: U32, type_ref: U32) -> Result<&2, &2, String, G.TypeRef>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{G.TypeRef{next, path_ref}}: child_from_type(next, method_id, target, index, type_ref, path_ref)

type ExpandStep is Data:
  ExpandNext{vm: M.VM, method_id: U32, target: U32, refs: +List<U32>, index: U32, acc: +List<U32>}
  ExpandGot{parsed: Result<&2, &2, String, G.TypeRef>, vm: M.VM, method_id: U32, target: U32, refs: +List<U32>, index: U32, acc: +List<U32>}

@unsafe def expand_run(fuel: Nat, step: ExpandStep) -> Result<&2, &2, String, ReflectRefs>:
  match fuel step:
    case 0n _: Fail{"VmError.InvalidSignature: truncated annotated types"}
    case 1n+p ExpandNext{vm, method_id, target, Nil{}, index, acc}: Done{ReflectRefs{vm, M.reverse(U32, acc)}}
    case 1n+p ExpandNext{+vm, +method_id, +target, Con{type_ref, rest}, +index, acc}:
      expand_run(p, ExpandGot{child_from_path(step_path(vm, index), vm, method_id, target, index, type_ref), vm, method_id, target, rest, index, acc})
    case 1n+p ExpandGot{Fail{error}, vm, method_id, target, refs, index, acc}: Fail{error}
    case 1n+p ExpandGot{Done{G.TypeRef{next, reference}}, vm, method_id, target, refs, index, acc}:
      expand_run(p, ExpandNext{next, method_id, target, refs, (index + 1 : U32), Con{reference, acc}})

def expand_actuals(+vm: M.VM, method_id: U32, target: U32, refs: +List<U32>, index: U32, +acc: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  expand_run(256n, ExpandNext{vm, method_id, target, refs, index, acc})

def actuals_from_array(+vm: M.VM, method_id: U32, target: U32, array_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +array : M.HeapEntry <- H.get(S.heap(vm), array_ref)
    refs : ReflectRefs <- expand_actuals(vm, method_id, target, slot_bits(entry_values(array)), 0, Nil{})
    result : O.Outcome <- annotated_type_refs_array(refs)
    return result

def actuals_if_parameterized(+vm: M.VM, method_id: U32, target: U32, +type_ref: U32, parameterized: Bool) -> Result<&2, &2, String, O.Outcome>:
  match parameterized:
    case False{}: empty_annotated_array(vm)
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), type_ref)
        array_slot : M.Slot <- reflect_annotation_binding(entry, 1)
        result : O.Outcome <- actuals_from_array(vm, method_id, target, bits_of(array_slot))
        return result

def actuals_of_stored(+vm: M.VM, method_id: U32, target: U32, +type_ref: U32, missing: Bool) -> Result<&2, &2, String, O.Outcome>:
  match missing:
    case True{}: empty_annotated_array(vm)
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), type_ref)
        result : O.Outcome <- actuals_if_parameterized(vm, method_id, target, type_ref, String.eq(class_name_text(vm, H.entry_class(entry)), "sun/reflect/generics/reflectiveObjects/ParameterizedTypeImpl"))
        return result

def reflect_annotated_type_get_actuals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    method_slot : M.Slot <- reflect_annotation_binding(entry, 0)
    target_slot : M.Slot <- reflect_annotation_binding(entry, 1)
    +stored : U32 = binding_bits(H.binding_find(entry_fields(entry), 4))
    result : O.Outcome <- actuals_of_stored(vm, bits_of(method_slot), bits_of(target_slot), stored, U32.is_eq(stored, 0))
    return result


def parameter_class_ids(+vm: M.VM, +types: +List<M.JvmType>, +acc: +List<U32>) -> Result<&2, &2, String, +List<U32>>:
  match types:
    case Nil{}: Done{M.reverse(U32, acc)}
    case Con{+value, rest}:
      do Result<&2, &2, String, +List<U32>>:
        +target : U32 = class_id(vm, jvm_type_class_name(value))
        checked : Unit <- S.check(U32.is_ne(target, 4294967295), "java/lang/NoClassDefFoundError")
        +ids : +List<U32> <- parameter_class_ids(vm, rest, Con{target, acc})
        return ids

def parameter_mirror_result(result: Result<&2, &2, String, O.Outcome>, cont: M.VM -> U32 -> Result<&2, &2, String, ReflectRefs>) -> Result<&2, &2, String, ReflectRefs>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{vm, Some{M.Slot{tag, reference}}}}: cont(vm, reference)
    case Done{outcome}: Fail{"java/lang/NoClassDefFoundError"}

@unsafe def parameter_mirror_alloc(+vm: M.VM, +ids: +List<U32>, +refs: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match ids:
    case Nil{}: Done{ReflectRefs{vm, M.reverse(U32, refs)}}
    case Con{target, rest}:
      parameter_mirror_result(class_mirror_out(vm, target), vm2 => reference => parameter_mirror_alloc(vm2, rest, Con{reference, refs}))
@unsafe def exception_class_ids(+indices: +List<U32>, +vm: M.VM, +pool: +List<M.Constant>, +acc: +List<U32>) -> Result<&2, &2, String, +List<U32>>:
  match indices:
    case Nil{}: Done{M.reverse(U32, acc)}
    case Con{index, rest}:
      do Result<&2, &2, String, +List<U32>>:
        +name : String <- CP.class_name(pool, index)
        +target : U32 = class_id(vm, name)
        checked : Unit <- S.check(U32.is_ne(target, 4294967295), "java/lang/NoClassDefFoundError")
        result : +List<U32> <- exception_class_ids(rest, vm, pool, Con{target, acc})
        return result

def exception_ref_slots(refs: +List<U32>) -> +List<M.Slot>:
  match refs:
    case Nil{}: Nil{}
    case Con{reference, rest}: Con{M.Slot{3, reference}, exception_ref_slots(rest)}

def exception_array_result_kind(value: ReflectRefs, array_name: String, component_name: String) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case ReflectRefs{+vm, +refs}:
      alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, array_name), class_id(vm, component_name), exception_ref_slots(refs))), vm2 => reference => ref_out(vm2, reference))

def exception_array_result(value: ReflectRefs) -> Result<&2, &2, String, O.Outcome>:
  exception_array_result_kind(value, "[Ljava/lang/Class;", "java/lang/Class")

def method_exception_types(source: AnnotationMetadataRef) -> Result<&2, &2, String, O.Outcome>:
  match source:
    case AnnotationMetadataRef{+vm, +pool, metadata}:
      do Result<&2, &2, String, O.Outcome>:
        ids : +List<U32> <- exception_class_ids(metadata_exceptions(metadata), vm, pool, Nil{})
        refs : ReflectRefs <- parameter_mirror_alloc(vm, ids, Nil{})
        result : O.Outcome <- exception_array_result(refs)
        return result
def method_generic_exception_types(source: AnnotationMetadataRef) -> Result<&2, &2, String, O.Outcome>:
  match source:
    case AnnotationMetadataRef{+vm, +pool, metadata}:
      do Result<&2, &2, String, O.Outcome>:
        ids : +List<U32> <- exception_class_ids(metadata_exceptions(metadata), vm, pool, Nil{})
        refs : ReflectRefs <- parameter_mirror_alloc(vm, ids, Nil{})
        result : O.Outcome <- exception_array_result_kind(refs, "[Ljava/lang/reflect/Type;", "java/lang/reflect/Type")
        return result

def generic_exceptions_refs(+vm: M.VM, +method: M.LoadedMethod, refs: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  match refs:
    case Nil{}:
      do Result<&2, &2, String, O.Outcome>:
        source : AnnotationMetadataRef <- method_annotation_source(vm, method)
        result : O.Outcome <- method_generic_exception_types(source)
        return result
    case _:
      alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/reflect/Type;"), class_id(vm, "java/lang/reflect/Type"), exception_ref_slots(refs))), vm2 => reference => ref_out(vm2, reference))

def generic_exceptions_parsed(parsed: Result<&2, &2, String, G.TypeRefs>, +vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{G.TypeRefs{next, refs}}: generic_exceptions_refs(next, method, refs)

def generic_exceptions_text(+vm: M.VM, +method: M.LoadedMethod, text: String, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case False{}: generic_exceptions_parsed(method_generic_thrown(vm, method, text), vm, method)
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        source : AnnotationMetadataRef <- method_annotation_source(vm, method)
        result : O.Outcome <- method_generic_exception_types(source)
        return result

def reflect_method_get_generic_exception_types(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    +text : String = method_signature(vm, method)
    result : O.Outcome <- generic_exceptions_text(vm, method, text, String.is_empty(text))
    return result


def reflect_method_get_exception_types(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    source : AnnotationMetadataRef <- method_annotation_source(vm, method)
    result : O.Outcome <- method_exception_types(source)
    return result

@unsafe def reflect_field_alloc(+vm: M.VM, +owner: U32, fields: +List<M.LoadedField>, +refs: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match fields:
    case Nil{}: Done{ReflectRefs{vm, M.reverse(U32, refs)}}
    case Con{+field, rest}:
      reflect_alloc_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/Field"), [M.Binding{0, M.Slot{1, M.loaded_field_owner(field)}}, M.Binding{1, M.Slot{1, M.loaded_field_id(field)}}, M.Binding{2, M.Slot{1, 0}}])), vm2 => reference => reflect_field_alloc(vm2, owner, rest, Con{reference, refs}))
@unsafe def reflect_method_alloc(+vm: M.VM, +owner: U32, methods: +List<M.LoadedMethod>, +refs: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match methods:
    case Nil{}: Done{ReflectRefs{vm, M.reverse(U32, refs)}}
    case Con{+method, rest}:
      reflect_alloc_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/Method"), [M.Binding{0, M.Slot{1, M.loaded_method_owner(method)}}, M.Binding{1, M.Slot{1, M.loaded_method_id(method)}}, M.Binding{2, M.Slot{1, 0}}])), vm2 => reference => reflect_method_alloc(vm2, owner, rest, Con{reference, refs}))
@unsafe def reflect_constructor_alloc(+vm: M.VM, +owner: U32, methods: +List<M.LoadedMethod>, +refs: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match methods:
    case Nil{}: Done{ReflectRefs{vm, M.reverse(U32, refs)}}
    case Con{+method, rest}:
      reflect_alloc_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/Constructor"), [M.Binding{0, M.Slot{1, owner}}, M.Binding{1, M.Slot{1, M.loaded_method_id(method)}}, M.Binding{2, M.Slot{1, 0}}])), vm2 => reference => reflect_constructor_alloc(vm2, owner, rest, Con{reference, refs}))

def ref_slots(refs: +List<U32>) -> +List<M.Slot>:
  match refs:
    case Nil{}: Nil{}
    case Con{reference, rest}: Con{M.Slot{3, reference}, ref_slots(rest)}
def reflect_array_result(+vm: M.VM, +refs: +List<U32>, array_name: String, element_name: String) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, array_name), class_id(vm, element_name), ref_slots(refs))), vm2 => reference => ref_out(vm2, reference))

def reflect_refs_array(value: ReflectRefs, array_name: String, element_name: String) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case ReflectRefs{vm, refs}: reflect_array_result(vm, refs, array_name, element_name)

def class_declared_fields(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    refs : ReflectRefs <- reflect_field_alloc(vm, target, declared_fields(S.fields(vm), target, Nil{}), Nil{})
    result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/reflect/Field;", "java/lang/reflect/Field")
    return result

def class_declared_methods(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    refs : ReflectRefs <- reflect_method_alloc(vm, target, declared_methods(S.methods(vm), target, S.symbols(vm), Nil{}), Nil{})
    result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/reflect/Method;", "java/lang/reflect/Method")
    return result

def class_declared_constructors_ready(+vm: M.VM, target: U32, methods: Result<&2, &2, String, +List<M.LoadedMethod>>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +selected : +List<M.LoadedMethod> <- methods
    refs : ReflectRefs <- reflect_constructor_alloc(vm, target, selected, Nil{})
    result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/reflect/Constructor;", "java/lang/reflect/Constructor")
    return result

def class_declared_constructors(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    methods : Result<&2, &2, String, +List<M.LoadedMethod>> = proxy_declared_constructors(vm, target, declared_constructors(S.methods(vm), target, S.symbols(vm), Nil{}))
    result : O.Outcome <- class_declared_constructors_ready(vm, target, methods)
    return result

def public_field_cons(found: Maybe<&2, M.LoadedField>, acc: +List<M.LoadedField>) -> +List<M.LoadedField>:
  match found:
    case None{}: acc
    case Some{field}: Con{field, acc}

def public_method_cons(found: Maybe<&2, M.LoadedMethod>, acc: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match found:
    case None{}: acc
    case Some{method}: Con{method, acc}

def public_fields(fields: +List<M.LoadedField>, +classes: +List<M.LoadedClass>, +target: U32, +symbols: +List<String>, +acc: +List<M.LoadedField>) -> +List<M.LoadedField>:
  match fields:
    case Nil{}: M.reverse(M.LoadedField, acc)
    case Con{+field, rest}:
      +public : Bool = U32.is_ne(U32.and(M.loaded_field_flags(field), 1), 0)
      +belongs : Bool = H.hierarchy(classes, target, M.loaded_field_owner(field))
      public_fields(rest, classes, target, symbols, public_field_cons(Bool.pick(Maybe<&2, M.LoadedField>, public && belongs, Some{field}, None{}), acc))

def method_is_public_ordinary(+method: M.LoadedMethod, +symbols: +List<String>) -> Bool:
  +name : String = Sy.text(symbols, M.loaded_method_name(method))
  Bool.and(U32.is_ne(U32.and(M.loaded_method_flags(method), 1), 0), Bool.not(String.eq(name, "<init>")) && Bool.not(String.eq(name, "<clinit>")))

def reflection_interface_found(found: Maybe<&2, M.LoadedClass>) -> Bool:
  match found:
    case None{}: False{}
    case Some{class}: U32.is_eq(M.loaded_class_parent(class), 4294967295)

def reflection_interface(classes: +List<M.LoadedClass>, owner: U32) -> Bool:
  reflection_interface_found(M.nth(M.LoadedClass, classes, owner))

def public_method_inherited(+method: M.LoadedMethod, +classes: +List<M.LoadedClass>, +target: U32) -> Bool:
  +owner : U32 = M.loaded_method_owner(method)
  H.hierarchy(classes, target, owner) &&
    Bool.not(U32.is_ne(owner, target) && reflection_interface(classes, owner) && U32.is_ne(U32.and(M.loaded_method_flags(method), 8), 0))

def public_method_shadowed(+method: M.LoadedMethod, methods: +List<M.LoadedMethod>, +classes: +List<M.LoadedClass>, +target: U32, +symbols: +List<String>) -> Bool:
  match methods:
    case Nil{}: False{}
    case Con{+candidate, rest}:
      +same : Bool = U32.is_eq(M.loaded_method_name(method), M.loaded_method_name(candidate)) && U32.is_eq(M.loaded_method_descriptor(method), M.loaded_method_descriptor(candidate))
      +more : Bool = U32.is_ne(M.loaded_method_owner(method), M.loaded_method_owner(candidate)) && H.hierarchy(classes, M.loaded_method_owner(candidate), M.loaded_method_owner(method))
      (same && more && public_method_inherited(candidate, classes, target) && method_is_public_ordinary(candidate, symbols)) || public_method_shadowed(method, rest, classes, target, symbols)

def public_methods_scan(methods: +List<M.LoadedMethod>, +all: +List<M.LoadedMethod>, +classes: +List<M.LoadedClass>, +target: U32, +symbols: +List<String>, +acc: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match methods:
    case Nil{}: M.reverse(M.LoadedMethod, acc)
    case Con{+method, rest}:
      +selected : Bool = method_is_public_ordinary(method, symbols) && public_method_inherited(method, classes, target) && Bool.not(public_method_shadowed(method, all, classes, target, symbols))
      public_methods_scan(rest, all, classes, target, symbols, public_method_cons(Bool.pick(Maybe<&2, M.LoadedMethod>, selected, Some{method}, None{}), acc))

def public_methods(+methods: +List<M.LoadedMethod>, classes: +List<M.LoadedClass>, target: U32, symbols: +List<String>, acc: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  public_methods_scan(methods, methods, classes, target, symbols, acc)


def find_declared_field(fields: +List<M.LoadedField>, +owner: U32, +name: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedField>:
  match fields:
    case Nil{}: None{}
    case Con{+field, rest}:
      +field_name : String = Sy.text(symbols, M.loaded_field_name(field))
      Bool.pick(Maybe<&2, M.LoadedField>, U32.is_eq(M.loaded_field_owner(field), owner) && String.eq(field_name, name), Some{field}, find_declared_field(rest, owner, name, symbols))

def find_declared_method(methods: +List<M.LoadedMethod>, +owner: U32, +name: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      +method_name : String = Sy.text(symbols, M.loaded_method_name(method))
      +ordinary : Bool = Bool.not(String.eq(method_name, "<init>")) && Bool.not(String.eq(method_name, "<clinit>"))
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), owner) && ordinary && String.eq(method_name, name), Some{method}, find_declared_method(rest, owner, name, symbols))

def find_declared_constructor(methods: +List<M.LoadedMethod>, +owner: U32, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      +method_name : String = Sy.text(symbols, M.loaded_method_name(method))
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), owner) && String.eq(method_name, "<init>"), Some{method}, find_declared_constructor(rest, owner, symbols))
def find_own_public_field(fields: +List<M.LoadedField>, +owner: U32, +name: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedField>:
  match fields:
    case Nil{}: None{}
    case Con{+field, rest}:
      +selected : Bool = U32.is_eq(M.loaded_field_owner(field), owner) && U32.is_ne(U32.and(M.loaded_field_flags(field), 1), 0) && String.eq(Sy.text(symbols, M.loaded_field_name(field)), name)
      Bool.pick(Maybe<&2, M.LoadedField>, selected, Some{field}, find_own_public_field(rest, owner, name, symbols))

type FieldWalk is Data:
  FFuel{fuel: Nat, owner: U32}
  FMissing{found: Maybe<&2, M.LoadedField>, fuel: Nat, owner: U32}
  FClass{found: Maybe<&2, M.LoadedClass>, fuel: Nat}
  FParent{found: Maybe<&2, M.LoadedField>, fuel: Nat, parent: U32}
  FInterfaces{fuel: Nat, ids: +List<U32>}
  FInterfaceFound{found: Maybe<&2, M.LoadedField>, fuel: Nat, ids: +List<U32>}

@unsafe def field_walk(+fields: +List<M.LoadedField>, +classes: +List<M.LoadedClass>, +name: String, +symbols: +List<String>, job: FieldWalk) -> Maybe<&2, M.LoadedField>:
  match job:
    case FFuel{0n, owner}: None{}
    case FFuel{1n+remaining, +owner}: field_walk(fields, classes, name, symbols, FMissing{find_own_public_field(fields, owner, name, symbols), remaining, owner})
    case FMissing{Some{field}, fuel, owner}: Some{field}
    case FMissing{None{}, fuel, owner}: field_walk(fields, classes, name, symbols, FClass{M.nth(M.LoadedClass, classes, owner), fuel})
    case FClass{None{}, fuel}: None{}
    case FClass{Some{+class}, +fuel}: field_walk(fields, classes, name, symbols, FParent{field_walk(fields, classes, name, symbols, FInterfaces{fuel, M.loaded_class_interfaces(class)}), fuel, M.loaded_class_parent(class)})
    case FParent{Some{field}, fuel, parent}: Some{field}
    case FParent{None{}, fuel, parent}: field_walk(fields, classes, name, symbols, FFuel{fuel, parent})
    case FInterfaces{fuel, Nil{}}: None{}
    case FInterfaces{+fuel, Con{id, rest}}: field_walk(fields, classes, name, symbols, FInterfaceFound{field_walk(fields, classes, name, symbols, FFuel{fuel, id}), fuel, rest})
    case FInterfaceFound{Some{field}, fuel, ids}: Some{field}
    case FInterfaceFound{None{}, fuel, ids}: field_walk(fields, classes, name, symbols, FInterfaces{fuel, ids})

def public_field_walk(fuel: Nat, +fields: +List<M.LoadedField>, +classes: +List<M.LoadedClass>, +owner: U32, +name: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedField>:
  field_walk(fields, classes, name, symbols, FFuel{fuel, owner})

def find_public_field(fields: +List<M.LoadedField>, classes: +List<M.LoadedClass>, owner: U32, name: String, symbols: +List<String>) -> Maybe<&2, M.LoadedField>:
  public_field_walk(256n, fields, classes, owner, name, symbols)

def find_public_method(methods: +List<M.LoadedMethod>, +classes: +List<M.LoadedClass>, +owner: U32, +name: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      +method_name : String = Sy.text(symbols, M.loaded_method_name(method))
      +public : Bool = method_is_public_ordinary(method, symbols)
      +belongs : Bool = H.hierarchy(classes, owner, M.loaded_method_owner(method))
      Bool.pick(Maybe<&2, M.LoadedMethod>, public && belongs && String.eq(method_name, name), Some{method}, find_public_method(rest, classes, owner, name, symbols))
def type_descriptor_from_class_name(+name: String) -> String:
  Bool.pick(String, String.starts_with(name, "["), name,
    Bool.pick(String, String.eq(name, "boolean"), "Z",
      Bool.pick(String, String.eq(name, "byte"), "B",
        Bool.pick(String, String.eq(name, "char"), "C",
          Bool.pick(String, String.eq(name, "short"), "S",
            Bool.pick(String, String.eq(name, "int"), "I",
              Bool.pick(String, String.eq(name, "long"), "J",
                Bool.pick(String, String.eq(name, "float"), "F",
                  Bool.pick(String, String.eq(name, "double"), "D",
                    Bool.pick(String, String.eq(name, "void"), "V", "L" ++ name ++ ";"))))))))))

def parameter_descriptor(+names: +List<String>) -> String:
  match names:
    case Nil{}: ""
    case Con{+name, rest}: type_descriptor_from_class_name(name) ++ parameter_descriptor(rest)

def parameter_prefix(+names: +List<String>) -> String:
  "(" ++ parameter_descriptor(names) ++ ")"

def reflect_parameter_name_checked(+vm: M.VM, tag: U32, reference: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    checked : Unit <- S.check(U32.is_eq(tag, 3), "java/lang/IllegalArgumentException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    valid : Unit <- S.check(U32.is_eq(entry_kind(entry), 8), "java/lang/IllegalArgumentException")
    return class_name_text(vm, entry_element(entry))

def reflect_parameter_name(+vm: M.VM, +value: M.Slot) -> Result<&2, &2, String, String>:
  reflect_parameter_name_checked(vm, M.slot_tag(value), M.slot_bits(value))

def reflect_parameter_names(+vm: M.VM, +values: +List<M.Slot>, +acc: +List<String>) -> Result<&2, &2, String, +List<String>>:
  match values:
    case Nil{}: Done{M.reverse(String, acc)}
    case Con{+value, rest}:
      do Result<&2, &2, String, +List<String>>:
        +name : String <- reflect_parameter_name(vm, value)
        +next : +List<String> <- reflect_parameter_names(vm, rest, Con{name, acc})
        return next
def reflect_parameter_array_names(+vm: M.VM, reference: U32) -> Result<&2, &2, String, +List<String>>:
  match reference:
    case 0: Done{Nil{}}
    case _:
      do Result<&2, &2, String, +List<String>>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        valid : Unit <- S.check(U32.is_eq(entry_kind(entry), 2), "java/lang/IllegalArgumentException")
        +names : +List<String> <- reflect_parameter_names(vm, entry_values(entry), Nil{})
        return names
def method_matches_prefix(+method: M.LoadedMethod, +prefix: String, +symbols: +List<String>) -> Bool:
  String.starts_with(Sy.text(symbols, M.loaded_method_descriptor(method)), prefix)

def reflection_method_prefer(+candidate: M.LoadedMethod, found: Maybe<&2, M.LoadedMethod>, +classes: +List<M.LoadedClass>, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: Some{candidate}
    case Some{+previous}:
      +candidate_owner : U32 = M.loaded_method_owner(candidate)
      +previous_owner : U32 = M.loaded_method_owner(previous)
      +candidate_return : String = proxy_descriptor_return(String.to_list(Sy.text(symbols, M.loaded_method_descriptor(candidate))))
      +previous_return : String = proxy_descriptor_return(String.to_list(Sy.text(symbols, M.loaded_method_descriptor(previous))))
      +same_owner : Bool = U32.is_eq(candidate_owner, previous_owner)
      +more_owner : Bool = U32.is_ne(candidate_owner, previous_owner) && (H.hierarchy(classes, candidate_owner, previous_owner) || (Bool.not(reflection_interface(classes, candidate_owner)) && reflection_interface(classes, previous_owner)))
      +more_return : Bool = Bool.not(String.eq(candidate_return, previous_return)) && H.descriptor_assignable(candidate_return, previous_return, classes, symbols)
      Bool.pick(Maybe<&2, M.LoadedMethod>, more_owner || (same_owner && more_return), Some{candidate}, Some{previous})

def method_is_public_name(+method: M.LoadedMethod, +symbols: +List<String>, +name: String) -> Bool:
  Bool.not(String.eq(name, "<init>")) && Bool.not(String.eq(name, "<clinit>")) && String.eq(Sy.text(symbols, M.loaded_method_name(method)), name)
def find_declared_method_exact(methods: +List<M.LoadedMethod>, +classes: +List<M.LoadedClass>, +owner: U32, +name: String, +prefix: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      +selected : Bool = U32.is_eq(M.loaded_method_owner(method), owner) && method_is_public_name(method, symbols, name) && method_matches_prefix(method, prefix, symbols)
      +found : Maybe<&2, M.LoadedMethod> = find_declared_method_exact(rest, classes, owner, name, prefix, symbols)
      Bool.pick(Maybe<&2, M.LoadedMethod>, selected, reflection_method_prefer(method, found, classes, symbols), found)


def find_declared_constructor_exact(methods: +List<M.LoadedMethod>, +owner: U32, +prefix: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      +method_name : String = Sy.text(symbols, M.loaded_method_name(method))
      +selected : Bool = U32.is_eq(M.loaded_method_owner(method), owner) && String.eq(method_name, "<init>") && method_matches_prefix(method, prefix, symbols)
      Bool.pick(Maybe<&2, M.LoadedMethod>, selected, Some{method}, find_declared_constructor_exact(rest, owner, prefix, symbols))

def find_public_method_exact(methods: +List<M.LoadedMethod>, +classes: +List<M.LoadedClass>, +owner: U32, +name: String, +prefix: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      +method_name : String = Sy.text(symbols, M.loaded_method_name(method))
      +public : Bool = method_is_public_ordinary(method, symbols)
      +belongs : Bool = public_method_inherited(method, classes, owner)
      +selected : Bool = public && belongs && String.eq(method_name, name) && method_matches_prefix(method, prefix, symbols)
      +found : Maybe<&2, M.LoadedMethod> = find_public_method_exact(rest, classes, owner, name, prefix, symbols)
      Bool.pick(Maybe<&2, M.LoadedMethod>, selected, reflection_method_prefer(method, found, classes, symbols), found)

def find_public_constructor_exact(methods: +List<M.LoadedMethod>, +owner: U32, +prefix: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      +method_name : String = Sy.text(symbols, M.loaded_method_name(method))
      +selected : Bool = U32.is_eq(M.loaded_method_owner(method), owner) && String.eq(method_name, "<init>") && U32.is_ne(U32.and(M.loaded_method_flags(method), 1), 0) && method_matches_prefix(method, prefix, symbols)
      Bool.pick(Maybe<&2, M.LoadedMethod>, selected, Some{method}, find_public_constructor_exact(rest, owner, prefix, symbols))


def proxy_declared_constructor_exact(+vm: M.VM, +target: U32, +prefix: String) -> Result<&2, &2, String, M.LoadedMethod>:
  Bool.pick(Result<&2, &2, String, M.LoadedMethod>, proxy_class_is_synthetic(vm, target) && String.eq(prefix, "(Ljava/lang/reflect/InvocationHandler;)"), proxy_constructor_method(vm, target), S.require(M.LoadedMethod, find_declared_constructor_exact(S.methods(vm), target, prefix, S.symbols(vm)), "java/lang/NoSuchMethodException"))
def proxy_public_constructor_exact(+vm: M.VM, +target: U32, +prefix: String) -> Result<&2, &2, String, M.LoadedMethod>:
  Bool.pick(Result<&2, &2, String, M.LoadedMethod>, proxy_class_is_synthetic(vm, target) && String.eq(prefix, "(Ljava/lang/reflect/InvocationHandler;)"), proxy_constructor_method(vm, target), S.require(M.LoadedMethod, find_public_constructor_exact(S.methods(vm), target, prefix, S.symbols(vm)), "java/lang/NoSuchMethodException"))


def reflect_field_one(+vm: M.VM, owner: U32, +field: M.LoadedField) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/Field"), [M.Binding{0, M.Slot{1, M.loaded_field_owner(field)}}, M.Binding{1, M.Slot{1, M.loaded_field_id(field)}}, M.Binding{2, M.Slot{1, 0}}])), vm2 => reference => ref_out(vm2, reference))

def reflect_method_one(+vm: M.VM, owner: U32, +method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/Method"), [M.Binding{0, M.Slot{1, M.loaded_method_owner(method)}}, M.Binding{1, M.Slot{1, M.loaded_method_id(method)}}, M.Binding{2, M.Slot{1, 0}}])), vm2 => reference => ref_out(vm2, reference))
def reflect_constructor_one(+vm: M.VM, owner: U32, method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/Constructor"), [M.Binding{0, M.Slot{1, owner}}, M.Binding{1, M.Slot{1, M.loaded_method_id(method)}}, M.Binding{2, M.Slot{1, 0}}])), vm2 => reference => ref_out(vm2, reference))

def class_declared_field(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    value : M.Slot <- slot1(args)
    name : String <- string_text(vm, bits_of(value))
    field : M.LoadedField <- S.require(M.LoadedField, find_declared_field(S.fields(vm), target, name, S.symbols(vm)), "java/lang/NoSuchFieldException")
    result : O.Outcome <- reflect_field_one(vm, target, field)
    return result

def class_declared_method(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    value : M.Slot <- slot1(args)
    name : String <- string_text(vm, bits_of(value))
    parameter_array : M.Slot <- slot2(args)
    +parameter_names : +List<String> <- reflect_parameter_array_names(vm, bits_of(parameter_array))
    +prefix : String = parameter_prefix(parameter_names)
    method : M.LoadedMethod <- S.require(M.LoadedMethod, find_declared_method_exact(S.methods(vm), S.classes(vm), target, name, prefix, S.symbols(vm)), "java/lang/NoSuchMethodException")
    result : O.Outcome <- reflect_method_one(vm, target, method)
    return result
def class_declared_constructor(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    parameter_array : M.Slot <- slot1(args)
    +parameter_names : +List<String> <- reflect_parameter_array_names(vm, bits_of(parameter_array))
    +prefix : String = parameter_prefix(parameter_names)
    method : M.LoadedMethod <- proxy_declared_constructor_exact(vm, target, prefix)
    result : O.Outcome <- reflect_constructor_one(vm, target, method)
    return result


def class_public_fields(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    refs : ReflectRefs <- reflect_field_alloc(vm, target, public_fields(S.fields(vm), S.classes(vm), target, S.symbols(vm), Nil{}), Nil{})
    result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/reflect/Field;", "java/lang/reflect/Field")
    return result

def class_public_methods(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    refs : ReflectRefs <- reflect_method_alloc(vm, target, public_methods(S.methods(vm), S.classes(vm), target, S.symbols(vm), Nil{}), Nil{})
    result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/reflect/Method;", "java/lang/reflect/Method")
    return result

def public_constructor_found(found: Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case Some{+method}: Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_ne(U32.and(M.loaded_method_flags(method), 1), 0), Some{method}, None{})
    case None{}: None{}

def find_public_constructor(methods: +List<M.LoadedMethod>, +owner: U32, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  public_constructor_found(find_declared_constructor(methods, owner, symbols))


def public_constructors(methods: +List<M.LoadedMethod>, +owner: U32, +symbols: +List<String>, +acc: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match methods:
    case Nil{}: M.reverse(M.LoadedMethod, acc)
    case Con{+method, rest}:
      +name : String = Sy.text(symbols, M.loaded_method_name(method))
      +selected : Bool = U32.is_eq(M.loaded_method_owner(method), owner) && String.eq(name, "<init>") && U32.is_ne(U32.and(M.loaded_method_flags(method), 1), 0)
      public_constructors(rest, owner, symbols, public_method_cons(Bool.pick(Maybe<&2, M.LoadedMethod>, selected, Some{method}, None{}), acc))
def class_public_constructors_ready(+vm: M.VM, target: U32, methods: Result<&2, &2, String, +List<M.LoadedMethod>>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +selected : +List<M.LoadedMethod> <- methods
    refs : ReflectRefs <- reflect_constructor_alloc(vm, target, selected, Nil{})
    result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/reflect/Constructor;", "java/lang/reflect/Constructor")
    return result

def class_public_constructors(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    methods : Result<&2, &2, String, +List<M.LoadedMethod>> = proxy_declared_constructors(vm, target, public_constructors(S.methods(vm), target, S.symbols(vm), Nil{}))
    result : O.Outcome <- class_public_constructors_ready(vm, target, methods)
    return result


def class_public_field(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    value : M.Slot <- slot1(args)
    name : String <- string_text(vm, bits_of(value))
    field : M.LoadedField <- S.require(M.LoadedField, find_public_field(S.fields(vm), S.classes(vm), target, name, S.symbols(vm)), "java/lang/NoSuchFieldException")
    result : O.Outcome <- reflect_field_one(vm, target, field)
    return result

def class_public_method(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    value : M.Slot <- slot1(args)
    name : String <- string_text(vm, bits_of(value))
    parameter_array : M.Slot <- slot2(args)
    +parameter_names : +List<String> <- reflect_parameter_array_names(vm, bits_of(parameter_array))
    +prefix : String = parameter_prefix(parameter_names)
    method : M.LoadedMethod <- S.require(M.LoadedMethod, find_public_method_exact(S.methods(vm), S.classes(vm), target, name, prefix, S.symbols(vm)), "java/lang/NoSuchMethodException")
    result : O.Outcome <- reflect_method_one(vm, target, method)
    return result
def class_public_constructor(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    parameter_array : M.Slot <- slot1(args)
    +parameter_names : +List<String> <- reflect_parameter_array_names(vm, bits_of(parameter_array))
    +prefix : String = parameter_prefix(parameter_names)
    method : M.LoadedMethod <- proxy_public_constructor_exact(vm, target, prefix)
    result : O.Outcome <- reflect_constructor_one(vm, target, method)
    return result

# U+E000 k (or U+E000 -k) marks a class defined (or unresolvable) in loader
# namespace k (see java/loaders.bend) and is not part of its name.
@unsafe def class_display_name(name: String) -> String:
  match name:
    case SNil{}: ""
    case SCon{Chr{47}, rest}: SCon{Chr{46}, class_display_name(rest)}
    case SCon{Chr{57344}, rest}: class_display_name(skip_namespace(rest))
    case SCon{head, rest}: SCon{head, class_display_name(rest)}

def skip_namespace(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{59}, rest}: text
    case SCon{head, rest}: skip_namespace(rest)

def class_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(class_display_name(class_name_text(vm, target))))
    return result
def array_element_type_name(descriptor: String) -> String:
  match descriptor:
    case SCon{Chr{91}, rest}: array_element_type_name(rest) ++ "[]"
    case SCon{Chr{76}, rest}: internal_to_binary(CL.take_until_semicolon(rest, ""))
    case "Z": "boolean"
    case "B": "byte"
    case "C": "char"
    case "S": "short"
    case "I": "int"
    case "J": "long"
    case "F": "float"
    case "D": "double"
    case other: other

# Class.getTypeName: arrays print as the element name followed by [] per dimension.
def class_type_name(+name: String) -> String:
  match name:
    case SCon{Chr{91}, rest}: array_element_type_name(rest) ++ "[]"
    case _: class_display_name(name)

def class_type_name_out(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(class_type_name(class_name_text(vm, target))))
    return result

def type_name_named(+vm: M.VM, entry: M.HeapEntry, +name: String, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match name:
    case "sun/reflect/generics/reflectiveObjects/ParameterizedTypeImpl": ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 3)))
    case "sun/reflect/generics/reflectiveObjects/TypeVariableImpl": ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 0)))
    case "sun/reflect/generics/reflectiveObjects/WildcardTypeImpl": ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 2)))
    case "sun/reflect/generics/reflectiveObjects/GenericArrayTypeImpl": ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 1)))
    case _: class_type_name_out(vm, args)

def type_get_type_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- type_name_named(vm, entry, class_name_text(vm, H.entry_class(entry)), args)
    return result

def parameterized_arguments(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 1)))
    return result

def parameterized_raw(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- class_mirror_out(vm, binding_bits(H.binding_find(entry_fields(entry), 0)))
    return result

def parameterized_owner(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 2)))
    return result

def type_variable_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 0)))
    return result

def type_variable_bounds(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 1)))
    return result

def wildcard_upper(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 0)))
    return result

def wildcard_lower(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 1)))
    return result

def generic_array_component(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, binding_bits(H.binding_find(entry_fields(entry), 0)))
    return result

def class_superclass_parent(+vm: M.VM, +parent: U32) -> Result<&2, &2, String, O.Outcome>:
  match parent:
    case 4294967295:
      ref_out(vm, 0)
    case value:
      class_mirror_out(vm, value)
def reflect_binding_found(found: Maybe<&2, M.Slot>) -> Result<&2, &2, String, M.Slot>:
  match found:
    case None{}: Fail{"java/lang/IllegalArgumentException"}
    case Some{value}: Done{value}

def reflect_binding(entry: M.HeapEntry, id: U32) -> Result<&2, &2, String, M.Slot>:
  reflect_binding_found(H.binding_find(entry_fields(entry), id))
def reflect_member_equal_nonnull(+vm: M.VM, left: U32, right: U32, expected: U32) -> Result<&2, &2, String, Bool>:
  do Result<&2, &2, String, Bool>:
    +left_entry : M.HeapEntry <- H.get(S.heap(vm), left)
    +right_entry : M.HeapEntry <- H.get(S.heap(vm), right)
    return U32.is_eq(H.entry_class(right_entry), expected) &&
      U32.is_eq(binding_bits(H.binding_find(entry_fields(left_entry), 0)), binding_bits(H.binding_find(entry_fields(right_entry), 0))) &&
      U32.is_eq(binding_bits(H.binding_find(entry_fields(left_entry), 1)), binding_bits(H.binding_find(entry_fields(right_entry), 1)))

def reflect_member_equal_choice(+vm: M.VM, left: U32, right: U32, expected: U32, right_null: Bool) -> Result<&2, &2, String, Bool>:
  match right_null:
    case True{}: Done{False{}}
    case False{}: reflect_member_equal_nonnull(vm, left, right, expected)

def reflect_member_equals(+vm: M.VM, +args: +List<M.Slot>, +expected: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    left : M.Slot <- slot0(args)
    right : M.Slot <- slot1(args)
    +left_ref : U32 = bits_of(left)
    +right_ref : U32 = bits_of(right)
    result : Bool <- reflect_member_equal_choice(vm, left_ref, right_ref, expected, U32.is_eq(right_ref, 0))
    outcome : O.Outcome <- bool_out(vm, result)
    return outcome

def reflect_field_hash_name(+vm: M.VM, found: Maybe<&2, M.LoadedField>) -> String:
  match found:
    case None{}: ""
    case Some{field}: Sy.text(S.symbols(vm), M.loaded_field_name(field))

def reflect_method_hash_name(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>) -> String:
  match found:
    case None{}: ""
    case Some{method}: Sy.text(S.symbols(vm), M.loaded_method_name(method))
def reflect_hash_name(+vm: M.VM, +expected: U32, +id: U32) -> String:
  Bool.pick(String, U32.is_eq(expected, class_id(vm, "java/lang/reflect/Field")),
    reflect_field_hash_name(vm, M.nth(M.LoadedField, S.fields(vm), id)),
    reflect_method_hash_name(vm, M.nth(M.LoadedMethod, S.methods(vm), id)))


def string_hash_go(chars: +List<U32>, acc: U32) -> U32:
  match chars:
    case Nil{}: acc
    case Con{c, rest}: string_hash_go(rest, (U32.mul(31, acc) + c : U32))
def reflect_member_hash(+vm: M.VM, +args: +List<M.Slot>, +expected: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    owner : M.Slot <- reflect_binding(entry, 0)
    id : M.Slot <- reflect_binding(entry, 1)
    +owner_hash : U32 = string_hash_go(units_from_string(class_display_name(class_name_text(vm, bits_of(owner)))), 0)
    +name_hash : U32 = string_hash_go(units_from_string(reflect_hash_name(vm, expected, bits_of(id))), 0)
    result : O.Outcome <- int_out(vm, Bool.pick(U32, U32.is_eq(expected, class_id(vm, "java/lang/reflect/Constructor")), owner_hash, U32.xor(owner_hash, name_hash)))
    return result

def reflect_field_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_member_equals(vm, args, class_id(vm, "java/lang/reflect/Field"))

def reflect_field_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_member_hash(vm, args, class_id(vm, "java/lang/reflect/Field"))

def reflect_method_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_member_equals(vm, args, class_id(vm, "java/lang/reflect/Method"))

def reflect_method_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_member_hash(vm, args, class_id(vm, "java/lang/reflect/Method"))

def reflect_constructor_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_member_equals(vm, args, class_id(vm, "java/lang/reflect/Constructor"))

def reflect_constructor_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_member_hash(vm, args, class_id(vm, "java/lang/reflect/Constructor"))

def reflect_field_member(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, M.LoadedField>:
  do Result<&2, &2, String, M.LoadedField>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    member : M.Slot <- reflect_binding(entry, 1)
    field : M.LoadedField <- S.require(M.LoadedField, M.nth(M.LoadedField, S.fields(vm), bits_of(member)), "java/lang/NoSuchFieldException")
    return field

def reflect_method_member(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, M.LoadedMethod>:
  do Result<&2, &2, String, M.LoadedMethod>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    member : M.Slot <- reflect_binding(entry, 1)
    method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), bits_of(member)), "java/lang/NoSuchMethodException")
    return method

def accessible_override_found(found: Maybe<&2, M.Slot>) -> Bool:
  match found:
    case None{}: False{}
    case Some{slot}: U32.is_ne(M.slot_bits(slot), 0)

def accessible_override(entry: M.HeapEntry) -> Bool:
  accessible_override_found(H.binding_find(entry_fields(entry), 2))
def caller_owner_found(found: Maybe<&2, M.LoadedMethod>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{+method}: M.loaded_method_owner(method)

def caller_owner_method(+vm: M.VM, id: U32) -> U32:
  +found : Maybe<&2, M.LoadedMethod> = M.nth(M.LoadedMethod, S.methods(vm), id)
  caller_owner_found(found)

def caller_owner_found_frame(+vm: M.VM, found: Maybe<&2, M.Frame>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{+frame}: caller_owner_method(vm, S.method_id(frame))

def caller_owner(+vm: M.VM) -> U32:
  +found : Maybe<&2, M.Frame> = M.nth(M.Frame, S.frames(vm), 0)
  caller_owner_found_frame(vm, found)

# A runtime package is a package name together with a defining loader (JVMS 5.3).
@unsafe def same_package(+vm: M.VM, +left: U32, +right: U32) -> Bool:
  String.eq(resource_package(class_name_text(vm, left)), resource_package(class_name_text(vm, right))) &&
    U32.is_eq(defining_loader_id(LS.defining_loader_of(vm, left)), defining_loader_id(LS.defining_loader_of(vm, right)))

@unsafe def defining_loader_id(found: Maybe<&2, U32>) -> U32:
  match found:
    case None{}: 0
    case Some{loader}: loader

def class_public(+vm: M.VM, target: U32) -> Bool:
  U32.is_ne(U32.and(class_flags(vm, target), 1), 0)

# JVMS 5.4.4 member access for linkage. Class accessibility is checked when the
# symbolic class reference resolves, so an inherited public member is reachable
# through an accessible subclass even when its declaring class is not.
def member_accessible(+vm: M.VM, +caller: U32, +owner: U32, +flags: U32) -> Bool:
  +public : Bool = U32.is_ne(U32.and(flags, 1), 0)
  +private : Bool = U32.is_ne(U32.and(flags, 2), 0)
  +protected : Bool = U32.is_ne(U32.and(flags, 4), 0)
  +package : Bool = same_package(vm, caller, owner)
  U32.is_eq(caller, owner) ||
    Bool.pick(Bool, public, True{},
      Bool.pick(Bool, private, False{},
        Bool.pick(Bool, protected, package || H.hierarchy(S.classes(vm), caller, owner), package)))

# jdk.internal.reflect.Reflection.verifyMemberAccess: the member's class must be
# public or in the caller's package; private members are reachable only from
# their own class (Java 8 class files have no nestmates); a protected instance
# member or constructor reached from a subclass in another package also needs a
# target that is the caller's class or a subclass of it. `target` 0 means none.
def protected_target_ok(+vm: M.VM, +current: U32, +target: U32, +package: Bool) -> Bool:
  U32.is_eq(target, 0) || U32.is_eq(target, current) || package || H.hierarchy(S.classes(vm), target, current)

def verify_member_access(+vm: M.VM, +current: U32, +member: U32, +target: U32, +flags: U32) -> Bool:
  +public : Bool = U32.is_ne(U32.and(flags, 1), 0)
  +private : Bool = U32.is_ne(U32.and(flags, 2), 0)
  +protected : Bool = U32.is_ne(U32.and(flags, 4), 0)
  +package : Bool = same_package(vm, current, member)
  +class_ok : Bool = class_public(vm, member) || package
  +granted : Bool = Bool.pick(Bool, private, False{},
    Bool.pick(Bool, protected, (package || H.hierarchy(S.classes(vm), current, member)) && protected_target_ok(vm, current, target, package), package))
  U32.is_eq(current, member) || U32.is_eq(current, 4294967295) || (class_ok && (public || granted))

# Class.toString: "class X", "interface X", or the bare name of a primitive.
@unsafe def class_to_string_text(+vm: M.VM, +target: U32) -> String:
  +name : String = class_name_text(vm, target)
  +display : String = class_display_name(name)
  Bool.pick(String, primitive_name(name), display,
    Bool.pick(String, U32.is_ne(U32.and(class_flags(vm, target), 512), 0), "interface " ++ display, "class " ++ display))

@unsafe def class_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(class_to_string_text(vm, target)))
    return result

@unsafe def access_denied_message(+vm: M.VM, +current: U32, +member: U32, +flags: U32) -> String:
  +package_access : Bool = U32.is_eq(U32.and(flags, 7), 0)
  "java/lang/IllegalAccessException: " ++ class_to_string_text(vm, current) ++ " cannot access a member of " ++ class_to_string_text(vm, member) ++
    Bool.pick(String, package_access, " with package access", " with modifiers \"" ++ modifier_text(flags) ++ "\"")

@unsafe def access_verdict(allowed: Bool, +vm: M.VM, +current: U32, +member: U32, +flags: U32) -> Result<&2, &2, String, Unit>:
  match allowed:
    case True{}: Done{Unit{}}
    case False{}: Fail{access_denied_message(vm, current, member, flags)}

def access_target_class(+vm: M.VM, +static: Bool, +target: U32) -> Result<&2, &2, String, U32>:
  match static:
    case True{}: Done{0}
    case False{}:
      do Result<&2, &2, String, U32>:
        checked : Unit <- S.check(U32.is_ne(target, 0), npe())
        +entry : M.HeapEntry <- H.get(S.heap(vm), target)
        return H.entry_class(entry)

@unsafe def access_check_target(+vm: M.VM, +owner: U32, +flags: U32, +target_class: U32) -> Result<&2, &2, String, Unit>:
  +current : U32 = caller_owner(vm)
  access_verdict(verify_member_access(vm, current, owner, target_class, flags), vm, current, owner, flags)

@unsafe def access_check_member(override: Bool, +vm: M.VM, +owner: U32, +flags: U32, +target: U32) -> Result<&2, &2, String, Unit>:
  match override:
    case True{}: Done{Unit{}}
    case False{}:
      do Result<&2, &2, String, Unit>:
        target_class : U32 <- access_target_class(vm, U32.is_ne(U32.and(flags, 8), 0), target)
        checked : Unit <- access_check_target(vm, owner, flags, target_class)
        return Unit{}

# Field.get/set and Method.invoke: the target class is the receiver's class for
# instance members and none for static ones (JDK AccessibleObject.checkAccess).
@unsafe def reflect_access_check(+vm: M.VM, +entry: M.HeapEntry, +owner: U32, +flags: U32, +target: U32) -> Result<&2, &2, String, Unit>:
  access_check_member(accessible_override(entry), vm, owner, flags, target)

# Constructor.newInstance and Class.newInstance check with the declaring class as target.
@unsafe def reflect_constructor_access(+vm: M.VM, override: Bool, +owner: U32, +flags: U32) -> Result<&2, &2, String, Unit>:
  match override:
    case True{}: Done{Unit{}}
    case False{}: access_check_target(vm, owner, flags, owner)



def accessible_update(entry: M.HeapEntry, value: M.Slot) -> M.HeapEntry:
  M.HeapEntry{+class, kind, element, +fields, values, chars} = entry
  M.HeapEntry{class, kind, element, H.binding_set(fields, 2, value), values, chars}

def accessible_set(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +value : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +owner : U32 = binding_bits(H.binding_find(entry_fields(entry), 0))
    restricted : Unit <- S.check(Bool.not(U32.is_ne(bits_of(value), 0) && U32.is_eq(H.entry_class(entry), class_id(vm, "java/lang/reflect/Constructor")) && U32.is_eq(owner, class_id(vm, "java/lang/Class"))), "java/lang/SecurityException")
    updated : M.HeapEntry = accessible_update(entry, value)
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), updated))
    return result

def accessible_is(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- bool_out(vm, accessible_override(entry))
    return result

def reflect_declaring_class(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    owner : M.Slot <- reflect_binding(entry, 0)
    result : O.Outcome <- class_mirror_out(vm, bits_of(owner))
    return result

def reflect_field_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    field : M.LoadedField <- reflect_field_member(vm, args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(Sy.text(S.symbols(vm), M.loaded_field_name(field))))
    return result

def reflect_field_modifiers(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    field : M.LoadedField <- reflect_field_member(vm, args)
    result : O.Outcome <- int_out(vm, M.loaded_field_flags(field))
    return result
def reflect_flag_value(+vm: M.VM, flags: U32, mask: U32) -> Result<&2, &2, String, O.Outcome>:
  bool_out(vm, U32.is_ne(U32.and(flags, mask), 0))

def reflect_field_is_synthetic(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    field : M.LoadedField <- reflect_field_member(vm, args)
    result : O.Outcome <- reflect_flag_value(vm, M.loaded_field_flags(field), 4096)
    return result

def reflect_field_is_enum_constant(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    field : M.LoadedField <- reflect_field_member(vm, args)
    result : O.Outcome <- reflect_flag_value(vm, M.loaded_field_flags(field), 16384)
    return result

def reflect_field_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    field : M.LoadedField <- reflect_field_member(vm, args)
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))
    result : O.Outcome <- descriptor_mirror(vm, descriptor)
    return result

def field_generic_parsed(parsed: Result<&2, &2, String, G.TypeRef>, +vm: M.VM, +descriptor: String) -> Result<&2, &2, String, O.Outcome>:
  match parsed:
    case Fail{error}: descriptor_mirror(vm, descriptor)
    case Done{G.TypeRef{next, reference}}: ref_out(next, reference)

def field_generic_text(+vm: M.VM, +owner: U32, +descriptor: String, +text: String, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: descriptor_mirror(vm, descriptor)
    case False{}: field_generic_parsed(field_generic(vm, owner, text), vm, descriptor)

def reflect_field_generic_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))
    +text : String = field_signature(vm, field)
    result : O.Outcome <- field_generic_text(vm, M.loaded_field_owner(field), descriptor, text, String.is_empty(text))
    return result

def field_annotated_plain(+vm: M.VM, field_id: U32) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/AnnotatedType"), [M.Binding{0, M.Slot{1, field_id}}, M.Binding{1, M.Slot{1, 19}}, M.Binding{2, M.Slot{1, 0}}])), vm2 => reference => ref_out(vm2, reference))

def field_annotated_parsed(parsed: Result<&2, &2, String, G.TypeRef>, +vm: M.VM, field_id: U32) -> Result<&2, &2, String, O.Outcome>:
  match parsed:
    case Fail{error}: field_annotated_plain(vm, field_id)
    case Done{G.TypeRef{next, reference}}: annotated_type_from_ref(next, field_id, 19, reference)

def field_annotated_text(+vm: M.VM, +field_id: U32, +text: String, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: field_annotated_plain(vm, field_id)
    case False{}: field_annotated_parsed(field_generic_id(vm, field_id, text), vm, field_id)

def reflect_field_annotated_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +text : String = field_signature(vm, field)
    result : O.Outcome <- field_annotated_text(vm, M.loaded_field_id(field), text, String.is_empty(text))
    return result

def class_generic_parsed(parsed: Result<&2, &2, String, G.TypeRef>, +vm: M.VM, +parent: U32) -> Result<&2, &2, String, O.Outcome>:
  match parsed:
    case Fail{error}: class_superclass_parent(vm, parent)
    case Done{G.TypeRef{next, reference}}: ref_out(next, reference)

def class_generic_text(+vm: M.VM, +target: U32, +parent: U32, +text: String, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: class_superclass_parent(vm, parent)
    case False{}: class_generic_parsed(class_generic_super(vm, target, text), vm, parent)

def class_generic_superclass_parent(+vm: M.VM, +target: U32, +parent: U32, missing: Bool) -> Result<&2, &2, String, O.Outcome>:
  match missing:
    case True{}: ref_out(vm, 0)
    case False{}:
      +text : String = class_signature(vm, target)
      class_generic_text(vm, target, parent, text, String.is_empty(text))

def class_generic_superclass(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), target), "java/lang/NoClassDefFoundError")
    +parent : U32 = M.loaded_class_parent(class)
    result : O.Outcome <- class_generic_superclass_parent(vm, target, parent, U32.is_eq(parent, 4294967295))
    return result
def reflect_static_field_value(+vm: M.VM, field: M.LoadedField) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- S.require(M.Slot, H.binding_find(S.statics(vm), M.loaded_field_id(field)), "java/lang/NoSuchFieldException")
    result : O.Outcome <- returned(vm, Some{value})
    return result

@unsafe def reflect_instance_field_value(+vm: M.VM, field: M.LoadedField, target: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field_ref : M.LoadedField = field
    +target_ref : U32 = target
    belongs : Unit <- field_receiver_check(vm, field_ref, target_ref)
    +entry : M.HeapEntry <- H.get(S.heap(vm), target_ref)
    value : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), M.loaded_field_id(field_ref)), "java/lang/NoSuchFieldException")
    result : O.Outcome <- returned(vm, Some{value})
    return result
def reflect_field_value(+vm: M.VM, field: M.LoadedField, target: U32) -> Result<&2, &2, String, O.Outcome>:
  +field_ref : M.LoadedField = field
  +target_ref : U32 = target
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_ne(U32.and(M.loaded_field_flags(field_ref), 8), 0), reflect_static_field_value(vm, field_ref), reflect_instance_field_value(vm, field_ref, target_ref))

def reflect_field_get_raw(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +handle : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +target : M.Slot <- slot1(args)
    checked : Unit <- reflect_access_check(vm, handle, M.loaded_field_owner(field), M.loaded_field_flags(field), bits_of(target))
    result : O.Outcome <- reflect_field_value(vm, field, bits_of(target))
    return result

def reflect_box_alloc(+vm: M.VM, +name: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, name), [M.Binding{0, value}])), vm2 => reference => ref_out(vm2, reference))

def reflect_box_wide(+vm: M.VM, +name: String, +descriptor: String, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +tag : U32 = Bool.pick(U32, String.eq(descriptor, "J"), 4, 5)
    checked : Unit <- S.check(U32.is_eq(M.slot_tag(value), tag), "java/lang/IllegalArgumentException")
    field : U32 <- wrapper_value_field_id(vm, name, descriptor)
    result : O.Outcome <- alloc_result(H.allocate(vm, H.object_entry(class_id(vm, name), [M.Binding{field, value}])), vm2 => reference => ref_out(vm2, reference))
    return result

# The single primitive boxer (reflection, method handles, lambdas); non-primitive names pass through.
def reflect_box_value(+vm: M.VM, name: String, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match name:
    case "boolean": reflect_box_alloc(vm, "java/lang/Boolean", value)
    case "float": reflect_box_alloc(vm, "java/lang/Float", value)
    case "char": reflect_box_alloc(vm, "java/lang/Character", value)
    case "byte": reflect_box_alloc(vm, "java/lang/Byte", value)
    case "short": reflect_box_alloc(vm, "java/lang/Short", value)
    case "int": reflect_box_alloc(vm, "java/lang/Integer", value)
    case "long": reflect_box_wide(vm, "java/lang/Long", "J", value)
    case "double": reflect_box_wide(vm, "java/lang/Double", "D", value)
    case _: returned(vm, Some{value})
def reflect_field_get_boxed(result: Result<&2, &2, String, O.Outcome>, name: String) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Done{O.Returned{vm, Some{value}}}: reflect_box_value(vm, name, value)
    case _: result

def reflect_field_get(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    field : M.LoadedField <- reflect_field_member(vm, args)
    result : O.Outcome <- reflect_field_get_boxed(reflect_field_get_raw(vm, args), descriptor_class_name(Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))))
    return result

@unsafe def reflect_field_get_int(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))
    raw : O.Outcome <- reflect_field_get_raw(vm, args)
    result : O.Outcome <- field_get_conversion(field_type_gate(String.eq(descriptor, "B") || String.eq(descriptor, "S") || String.eq(descriptor, "C") || String.eq(descriptor, "I"), raw), vm, field, 73)
    return result

def reflect_static_field_set(+vm: M.VM, field: M.LoadedField, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  void_out(S.with_statics(vm, H.binding_set(S.statics(vm), M.loaded_field_id(field), value)))

def reflect_instance_field_set(+vm: M.VM, field: M.LoadedField, target: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field_ref : M.LoadedField = field
    +target_ref : U32 = target
    checked : Unit <- S.check(U32.is_ne(target_ref, 0), npe())
    +entry : M.HeapEntry <- H.get(S.heap(vm), target_ref)
    belongs : Unit <- S.check(H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), M.loaded_field_owner(field_ref)), "java/lang/IllegalArgumentException")
    result : O.Outcome <- void_out(H.put(vm, target_ref, H.object_entry(H.entry_class(entry), H.binding_set(entry_fields(entry), M.loaded_field_id(field_ref), value))))
    return result

def reflect_field_set_value(+vm: M.VM, field: M.LoadedField, target: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  +field_ref : M.LoadedField = field
  +target_ref : U32 = target
  +value_ref : M.Slot = value
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_ne(U32.and(M.loaded_field_flags(field_ref), 8), 0), reflect_static_field_set(vm, field_ref, value_ref), reflect_instance_field_set(vm, field_ref, target_ref, value_ref))

def reflect_field_set_allowed(entry: M.HeapEntry, field: M.LoadedField) -> Bool:
  +flags : U32 = M.loaded_field_flags(field)
  +static : Bool = U32.is_ne(U32.and(flags, 8), 0)
  +final : Bool = U32.is_ne(U32.and(flags, 16), 0)
  Bool.pick(Bool, static, Bool.not(final), Bool.or(Bool.not(final), accessible_override(entry)))

def reflect_widen_allowed(+source: U32, +target: U32) -> Bool:
  U32.is_eq(source, target) ||
    (U32.is_eq(source, 66) && (U32.is_eq(target, 83) || U32.is_eq(target, 73) || U32.is_eq(target, 70) || U32.is_eq(target, 74) || U32.is_eq(target, 68))) ||
    ((U32.is_eq(source, 83) || U32.is_eq(source, 67)) && (U32.is_eq(target, 73) || U32.is_eq(target, 70) || U32.is_eq(target, 74) || U32.is_eq(target, 68))) ||
    (U32.is_eq(source, 73) && (U32.is_eq(target, 70) || U32.is_eq(target, 74) || U32.is_eq(target, 68))) ||
    (U32.is_eq(source, 74) && (U32.is_eq(target, 70) || U32.is_eq(target, 68))) ||
    (U32.is_eq(source, 70) && U32.is_eq(target, 68))

def reflect_int_to_long_value(value: W.Words) -> Result<&2, &2, String, M.Slot>:
  match value:
    case W.Words{high, low}: Done{M.Wide{4, high, low}}


def reflect_wide_slot(tag: U32, +words: W.Words) -> M.Slot:
  match words:
    case W.Words{high, low}: M.Wide{tag, high, low}

def reflect_widen_value(target: U32, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  match target:
    case 74:
      match value:
        case M.Wide{4, high, low}: Done{value}
        case M.Slot{tag, bits}: reflect_int_to_long_value(W.int_to_long(bits))
        case _: Fail{"java/lang/IllegalArgumentException"}
    case 68:
      match value:
        case M.Wide{4, high, low}:
          +converted : W.Words = B64.long_to_double(W.Words{high, low})
          Done{reflect_wide_slot(5, converted)}
        case M.Wide{5, high, low}: Done{value}
        case M.Slot{2, bits}:
          +converted : W.Words = B64.f32_bits_to_double(bits)
          Done{reflect_wide_slot(5, converted)}
        case M.Slot{tag, bits}:
          +converted : W.Words = B64.int_to_double(bits)
          Done{reflect_wide_slot(5, converted)}
        case _: Fail{"java/lang/IllegalArgumentException"}
    case 70:
      match value:
        case M.Wide{4, high, low}: Done{M.Slot{2, B64.long_to_float(W.Words{high, low})}}
        case M.Wide{5, high, low}: Done{M.Slot{2, B64.double_to_f32(W.Words{high, low})}}
        case M.Slot{2, bits}: Done{value}
        case M.Slot{tag, bits}: Done{M.Slot{2, V.int_float(bits)}}
        case _: Fail{"java/lang/IllegalArgumentException"}
    case _: Done{value}

def reflect_widen(+source: U32, +target: U32, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    checked : Unit <- S.check(reflect_widen_allowed(source, target), "java/lang/IllegalArgumentException")
    result : M.Slot <- reflect_widen_value(target, value)
    return result
def reflect_set_int_value(jvm_type: M.JvmType, value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  match jvm_type:
    case M.Primitive{tag}: reflect_widen(73, tag, value)
    case _: Fail{"java/lang/IllegalArgumentException"}


def reflect_method_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_method_member(vm, args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(Sy.text(S.symbols(vm), M.loaded_method_name(method))))
    return result
def reflect_binding_slot(found: Maybe<&2, M.Slot>) -> M.Slot:
  match found:
    case None{}: M.Slot{0, 0}
    case Some{value}: value

def reflect_wrapper_tag(name: String) -> U32:
  match name:
    case "java/lang/Boolean": 90
    case "java/lang/Byte": 66
    case "java/lang/Short": 83
    case "java/lang/Character": 67
    case "java/lang/Integer": 73
    case "java/lang/Float": 70
    case "java/lang/Long": 74
    case "java/lang/Double": 68
    case _: 0
def wide_wrapper_field(+vm: M.VM, tag: U32) -> Result<&2, &2, String, U32>:
  match tag:
    case 74: wrapper_value_field_id(vm, "java/lang/Long", "J")
    case 68: wrapper_value_field_id(vm, "java/lang/Double", "D")
    case _: Done{0}


def wrapper_value_slot(+vm: M.VM, entry: M.HeapEntry, tag: U32) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    field : U32 <- wide_wrapper_field(vm, tag)
    slot : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), field), "java/lang/IllegalArgumentException")
    return slot

def wrapper_value_slot_tag(+tag: U32) -> U32:
  Bool.pick(U32, U32.is_eq(tag, 70), 2,
    Bool.pick(U32, U32.is_eq(tag, 74), 4,
      Bool.pick(U32, U32.is_eq(tag, 68), 5, 1)))

def reflect_convert_primitive(+vm: M.VM, +target: U32, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    checked : Unit <- S.check(U32.is_eq(V.slot_tag(value), 3) && U32.is_ne(bits_of(value), 0), "java/lang/IllegalArgumentException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(value))
    +source : U32 = reflect_wrapper_tag(class_name_text(vm, H.entry_class(entry)))
    primitive : Unit <- S.check(U32.is_ne(source, 0), "java/lang/IllegalArgumentException")
    +unboxed : M.Slot <- wrapper_value_slot(vm, entry, source)
    result : M.Slot <- reflect_widen(source, target, unboxed)
    return result

def reflect_reference_entry(result: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM, +descriptor: String) -> Bool:
  match result:
    case Fail{error}: False{}
    case Done{entry}: H.descriptor_assignable(type_descriptor_from_class_name(class_name_text(vm, H.entry_class(entry))), descriptor, S.classes(vm), S.symbols(vm))

def reflect_reference_ok(+vm: M.VM, reference: U32, +descriptor: String) -> Bool:
  match reference:
    case 0: True{}
    case _: reflect_reference_entry(H.get(S.heap(vm), reference), vm, descriptor)

def reflect_convert_reference(+vm: M.VM, +descriptor: String, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    checked : Unit <- S.check(U32.is_eq(V.slot_tag(value), 3), "java/lang/IllegalArgumentException")
    belongs : Unit <- S.check(reflect_reference_ok(vm, bits_of(value), descriptor), "java/lang/IllegalArgumentException")
    return value

def reflect_convert(+vm: M.VM, +jvm_type: M.JvmType, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  match jvm_type:
    case M.Primitive{tag}: reflect_convert_primitive(vm, tag, value)
    case _: reflect_convert_reference(vm, type_descriptor_from_class_name(jvm_type_class_name(jvm_type)), value)
@unsafe def reflect_field_set_mode(+vm: M.VM, +args: +List<M.Slot>, +boxed: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +handle : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +target : M.Slot <- slot1(args)
    checked : Unit <- reflect_access_check(vm, handle, M.loaded_field_owner(field), M.loaded_field_flags(field), bits_of(target))
    belongs : Unit <- field_receiver_check(vm, field, bits_of(target))
    +value : M.Slot <- slot2(args)
    +attempted_type : String = Bool.pick(String, boxed, object_type_name(vm, bits_of(value)), "int")
    +attempted_value : String = Bool.pick(String, boxed, "", V.int_show(bits_of(value)))
    final_checked : Unit <- field_final_verdict(reflect_field_set_allowed(handle, field), vm, field, attempted_type, attempted_value)
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))
    +parsed : M.JvmType <- D.parse_field(descriptor)
    converted : M.Slot <- field_convert_message(Bool.pick(Result<&2, &2, String, M.Slot>, boxed, reflect_convert(vm, parsed, value), reflect_set_int_value(parsed, value)), vm, field, attempted_type, attempted_value)
    result : O.Outcome <- reflect_field_set_value(vm, field, bits_of(target), converted)
    return result
def reflect_field_set(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_field_set_mode(vm, args, True{})

def reflect_field_set_int(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_field_set_mode(vm, args, False{})
def reflect_field_get_typed_value(result: Result<&2, &2, String, O.Outcome>, source: U32, target: U32) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{vm, Some{value}}}:
      do Result<&2, &2, String, O.Outcome>:
        +converted : M.Slot <- reflect_widen(source, target, value)
        result : O.Outcome <- returned(vm, Some{converted})
        return result
    case _: Fail{"java/lang/IllegalArgumentException"}

def reflect_primitive_tag(parsed: M.JvmType) -> Result<&2, &2, String, U32>:
  match parsed:
    case M.Primitive{tag}: Done{tag}
    case _: Fail{"java/lang/IllegalArgumentException"}


def reflect_field_get_typed_primitive(source: Result<&2, &2, String, U32>, raw: O.Outcome, target: U32) -> Result<&2, &2, String, O.Outcome>:
  match source:
    case Fail{error}: Fail{error}
    case Done{tag}: reflect_field_get_typed_value(Done{raw}, tag, target)

@unsafe def reflect_field_get_typed(+vm: M.VM, +args: +List<M.Slot>, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))
    +parsed : M.JvmType <- D.parse_field(descriptor)
    raw : O.Outcome <- reflect_field_get_raw(vm, args)
    result : O.Outcome <- field_get_conversion(reflect_field_get_typed_primitive(reflect_primitive_tag(parsed), raw, target), vm, field, target)
    return result

def reflect_widen_primitive(source: U32, parsed: M.JvmType, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  match parsed:
    case M.Primitive{tag}: reflect_widen(source, tag, value)
    case _: Fail{"java/lang/IllegalArgumentException"}



@unsafe def reflect_field_set_typed(+vm: M.VM, +args: +List<M.Slot>, +source: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +handle : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +target : M.Slot <- slot1(args)
    checked : Unit <- reflect_access_check(vm, handle, M.loaded_field_owner(field), M.loaded_field_flags(field), bits_of(target))
    belongs : Unit <- field_receiver_check(vm, field, bits_of(target))
    +value : M.Slot <- slot2(args)
    +attempted_value : String = wide_attempt_value(value, source)
    final_checked : Unit <- field_final_verdict(reflect_field_set_allowed(handle, field), vm, field, source_type_name(source), attempted_value)
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))
    +parsed : M.JvmType <- D.parse_field(descriptor)
    +converted : M.Slot <- field_convert_message(reflect_widen_primitive(source, parsed, value), vm, field, source_type_name(source), attempted_value)
    result : O.Outcome <- reflect_field_set_value(vm, field, bits_of(target), converted)
    return result

def reflect_field_get_long(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_field_get_typed(vm, args, 74)
def reflect_field_get_double(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_field_get_typed(vm, args, 68)
def reflect_field_set_long(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_field_set_typed(vm, args, 74)
def reflect_field_set_double(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reflect_field_set_typed(vm, args, 68)



def reflect_convert_values(+vm: M.VM, types: +List<M.JvmType>, values: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  match types values:
    case Nil{} Nil{}: Done{Nil{}}
    case Con{jvm_type, rest} Con{value, tail}:
      do Result<&2, &2, String, +List<M.Slot>>:
        converted : M.Slot <- reflect_convert(vm, jvm_type, value)
        remaining : +List<M.Slot> <- reflect_convert_values(vm, rest, tail)
        return Con{converted, remaining}
    case _ _: Fail{"java/lang/IllegalArgumentException"}

def reflect_method_values(+vm: M.VM, method: M.LoadedMethod, values: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  do Result<&2, &2, String, +List<M.Slot>>:
    parsed : M.Descriptor <- D.parse_method(Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)))
    result : +List<M.Slot> <- reflect_convert_values(vm, D.parameter_types(parsed), values)
    return result

def reflect_argument_values(+vm: M.VM, array_ref: U32) -> Result<&2, &2, String, +List<M.Slot>>:
  match array_ref:
    case 0: Done{Nil{}}
    case reference:
      do Result<&2, &2, String, +List<M.Slot>>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 2), "java/lang/IllegalArgumentException")
        return entry_values(entry)


def reflect_method_direct(method: M.LoadedMethod) -> Bool:
  +flags : U32 = M.loaded_method_flags(method)
  U32.is_ne(U32.and(flags, 8), 0) || U32.is_ne(U32.and(flags, 2), 0) || U32.is_ne(U32.and(flags, 16), 0)

def own_method(methods: +List<M.LoadedMethod>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+value, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(value), owner) && U32.is_eq(M.loaded_method_name(value), name) && U32.is_eq(M.loaded_method_descriptor(value), descriptor), Some{value}, own_method(rest, owner, name, descriptor))

def class_parent_found(found: Maybe<&2, M.LoadedClass>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{value}: M.loaded_class_parent(value)

def method_continue(found: Maybe<&2, M.LoadedMethod>, parent: U32, next: U32 -> Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case Some{value}: Some{value}
    case None{}:
      match parent:
        case 4294967295: None{}
        case value: next(value)

def method_hierarchy(fuel: Nat, +classes: +List<M.LoadedClass>, +methods: +List<M.LoadedMethod>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      method_continue(own_method(methods, owner, name, descriptor), class_parent_found(M.nth(M.LoadedClass, classes, owner)), parent => method_hierarchy(p, classes, methods, parent, name, descriptor))

def virtual_on_entry(result: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM, +name: String, +desc: String) -> Maybe<&2, M.LoadedMethod>:
  match result:
    case Fail{error}: None{}
    case Done{entry}: method_hierarchy(256n, S.classes(vm), S.methods(vm), H.entry_class(entry), Sy.find(S.symbols(vm), name), Sy.find(S.symbols(vm), desc))

def virtual_on(+vm: M.VM, +receiver: U32, name: String, desc: String) -> Maybe<&2, M.LoadedMethod>:
  virtual_on_entry(H.get(S.heap(vm), receiver), vm, name, desc)
def reflect_method_dispatch(+vm: M.VM, method: M.LoadedMethod, target: U32) -> Result<&2, &2, String, M.LoadedMethod>:
  +method_ref : M.LoadedMethod = method
  Bool.pick(Result<&2, &2, String, M.LoadedMethod>, reflect_method_direct(method_ref), Done{method_ref},
    S.require(M.LoadedMethod, virtual_on(vm, target, Sy.text(S.symbols(vm), M.loaded_method_name(method_ref)), Sy.text(S.symbols(vm), M.loaded_method_descriptor(method_ref))), "java/lang/NoSuchMethodException"))

def reflect_method_call(+vm: M.VM, +method: M.LoadedMethod, target: M.Slot, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target_ref : M.Slot = target
    +static : Bool = U32.is_ne(U32.and(M.loaded_method_flags(method), 8), 0)
    checked : Unit <- S.check(static || U32.is_ne(bits_of(target_ref), 0), npe())
    belongs : Unit <- S.check(static || reflect_reference_ok(vm, bits_of(target_ref), "L" ++ class_name_text(vm, M.loaded_method_owner(method)) ++ ";"), "java/lang/IllegalArgumentException")
    +converted : +List<M.Slot> <- reflect_method_values(vm, method, values)
    +selected : M.LoadedMethod <- reflect_method_dispatch(vm, method, bits_of(target_ref))
    invoke_args : +List<M.Slot> = Bool.pick(+List<M.Slot>, static, converted, Con{target_ref, converted})
    return O.Call{S.with_effect(vm, M.ReflectCall{}), selected, invoke_args}


def reflect_method_invoke(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +handle : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +method : M.LoadedMethod <- reflect_method_member(vm, args)
    +target : M.Slot <- slot1(args)
    checked : Unit <- reflect_access_check(vm, handle, M.loaded_method_owner(method), M.loaded_method_flags(method), bits_of(target))
    argument_array : M.Slot <- slot2(args)
    +values : +List<M.Slot> <- reflect_argument_values(vm, bits_of(argument_array))
    result : O.Outcome <- reflect_method_call(vm, method, target, values)
    return result

def reflect_method_modifiers(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_method_member(vm, args)
    result : O.Outcome <- int_out(vm, M.loaded_method_flags(method))
    return result
def reflect_method_is_bridge(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_method_member(vm, args)
    result : O.Outcome <- reflect_flag_value(vm, M.loaded_method_flags(method), 64)
    return result

def reflect_method_is_synthetic(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_method_member(vm, args)
    result : O.Outcome <- reflect_flag_value(vm, M.loaded_method_flags(method), 4096)
    return result

def reflect_method_is_varargs(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_method_member(vm, args)
    result : O.Outcome <- reflect_flag_value(vm, M.loaded_method_flags(method), 128)
    return result
def reflect_method_is_default(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_member(vm, args)
    owner : U32 = M.loaded_method_owner(method)
    interface : Bool = U32.is_ne(U32.and(class_flags(vm, owner), 512), 0)
    concrete : Bool = U32.is_eq(U32.and(M.loaded_method_flags(method), 1024), 0)
    result : O.Outcome <- bool_out(vm, Bool.and(interface, concrete))
    return result

def generic_type_array(parsed: Result<&2, &2, String, G.TypeRefs>) -> Result<&2, &2, String, O.Outcome>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{G.TypeRefs{+vm, refs}}:
      alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/reflect/Type;"), class_id(vm, "java/lang/reflect/Type"), exception_ref_slots(refs))), vm2 => reference => ref_out(vm2, reference))

def generic_return_parsed(parsed: Result<&2, &2, String, G.TypeRef>, +vm: M.VM, +descriptor: String) -> Result<&2, &2, String, O.Outcome>:
  match parsed:
    case Fail{error}: class_name_mirror(vm, method_return_name(descriptor))
    case Done{G.TypeRef{next, reference}}: ref_out(next, reference)

def generic_return_text(+vm: M.VM, +method: M.LoadedMethod, +descriptor: String, +text: String, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: class_name_mirror(vm, method_return_name(descriptor))
    case False{}: generic_return_parsed(method_generic_return(vm, method, text), vm, descriptor)

def reflect_method_generic_return(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_member(vm, args)
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
    +text : String = method_signature(vm, method)
    result : O.Outcome <- generic_return_text(vm, method, descriptor, text, String.is_empty(text))
    return result

def reflect_method_return_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_method_member(vm, args)
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
    result : O.Outcome <- class_name_mirror(vm, method_return_name(descriptor))
    return result

def reflect_empty_parameter_types(+vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/Class;"), class_id(vm, "java/lang/Class"), Nil{})), vm2 => reference => ref_out(vm2, reference))

def reflect_member_parameter_types(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
    parsed : M.Descriptor <- D.parse_method(descriptor)
    +ids : +List<U32> <- parameter_class_ids(vm, D.parameter_types(parsed), Nil{})
    refs : ReflectRefs <- parameter_mirror_alloc(vm, ids, Nil{})
    result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/Class;", "java/lang/Class")
    return result
def generic_parameters_text(+vm: M.VM, +method: M.LoadedMethod, text: String, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case False{}: generic_type_array(method_generic_parameters(vm, method, text))
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +descriptor : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
        parsed : M.Descriptor <- D.parse_method(descriptor)
        +ids : +List<U32> <- parameter_class_ids(vm, D.parameter_types(parsed), Nil{})
        refs : ReflectRefs <- parameter_mirror_alloc(vm, ids, Nil{})
        result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/reflect/Type;", "java/lang/reflect/Type")
        return result

def reflect_member_generic_parameter_types(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  +text : String = method_signature(vm, method)
  generic_parameters_text(vm, method, text, String.is_empty(text))

def reflect_method_generic_parameter_types(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_method_member(vm, args)
    result : O.Outcome <- reflect_member_generic_parameter_types(vm, method)
    return result


def reflect_method_parameter_types(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_method_member(vm, args)
    result : O.Outcome <- reflect_member_parameter_types(vm, method)
    return result
def reflect_instance_fields(fields: +List<M.LoadedField>, +classes: +List<M.LoadedClass>, +owner: U32) -> +List<M.Binding>:
  match fields:
    case Nil{}: Nil{}
    case Con{+field, rest}:
      +tail = reflect_instance_fields(rest, classes, owner)
      +is_instance = U32.is_eq(U32.and(M.loaded_field_flags(field), 8), 0)
      +belongs = H.hierarchy(classes, owner, M.loaded_field_owner(field))
      Bool.pick(+List<M.Binding>, Bool.and(is_instance, belongs), Con{M.Binding{M.loaded_field_id(field), M.Slot{M.loaded_field_tag(field), 0}}, tail}, tail)

def reflect_constructor_member(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, M.LoadedMethod>:
  do Result<&2, &2, String, M.LoadedMethod>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    member : M.Slot <- reflect_binding(entry, 1)
    +base : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), bits_of(member)), "java/lang/NoSuchMethodException")
    owner : M.Slot <- reflect_binding(entry, 0)
    method : M.LoadedMethod = proxy_constructor_member(vm, bits_of(owner), base)
    return method

def proxy_constructor_interface_array_result(refs: ReflectRefs) -> Result<&2, &2, String, H.Allocation>:
  match refs:
    case ReflectRefs{+vm, +ids}: H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/Class;"), class_id(vm, "java/lang/Class"), ref_slots(ids)))

def primitive_name(+name: String) -> Bool:
  String.eq(name, "int") || String.eq(name, "boolean") || String.eq(name, "byte") || String.eq(name, "short") || String.eq(name, "char") || String.eq(name, "float") || String.eq(name, "long") || String.eq(name, "double") || String.eq(name, "void")
@unsafe def interface_mirror_alloc(+vm: M.VM, ids: +List<U32>, +refs: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match ids:
    case Nil{}:
      Done{ReflectRefs{vm, M.reverse(U32, refs)}}
    case Con{target, rest}:
      reflect_alloc_result(H.allocate(vm, H.class_mirror_entry(class_id(vm, "java/lang/Class"), target)), vm2 => reference => interface_mirror_alloc(vm2, rest, Con{reference, refs}))
def reflect_constructor_call(+vm: M.VM, method: M.LoadedMethod, target: M.Slot, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method_ref : M.LoadedMethod = method
    +target_ref : M.Slot = target
    invoke_args : +List<M.Slot> = Con{target_ref, values}
    return O.Call{S.with_effect(vm, M.ReflectConstructor{bits_of(target_ref)}), method_ref, invoke_args}

def proxy_constructor_interface_array(+vm: M.VM, owner: U32) -> Result<&2, &2, String, H.Allocation>:
  do Result<&2, &2, String, H.Allocation>:
    +class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), owner), "java/lang/NoClassDefFoundError")
    refs : ReflectRefs <- interface_mirror_alloc(vm, M.loaded_class_interfaces(class), Nil{})
    result : H.Allocation <- proxy_constructor_interface_array_result(refs)
    return result

def proxy_constructor_object_result(result: Result<&2, &2, String, H.Allocation>, +owner: U32, method: M.LoadedMethod, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, +reference}}:
      alloc_result(H.allocate(vm, M.HeapEntry{owner, 10, 0, [M.Binding{0, M.Slot{3, 0}}, M.Binding{1, M.Slot{3, reference}}, M.Binding{2, M.Slot{1, owner}}], Nil{}, Nil{}}), vm2 => object_ref => reflect_constructor_call(vm2, method, M.Slot{3, object_ref}, values))

def proxy_constructor_alloc(+vm: M.VM, +owner: U32, method: M.LoadedMethod, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  proxy_constructor_object_result(proxy_constructor_interface_array(vm, owner), owner, method, values)

def reflect_constructor_instance_alloc(+vm: M.VM, +method: M.LoadedMethod, +owner: U32, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, proxy_class_is_synthetic(vm, owner), proxy_constructor_alloc(vm, owner, method, values),
    alloc_result(H.allocate(vm, H.object_entry(owner, reflect_instance_fields(S.fields(vm), S.classes(vm), owner))), vm2 => reference => reflect_constructor_call(vm2, method, M.Slot{3, reference}, values)))

def constructor_instantiable(+vm: M.VM, +owner: U32) -> Bool:
  +flags : U32 = class_flags(vm, owner)
  Bool.not(U32.is_eq(owner, class_id(vm, "java/lang/Class")) ||
    U32.is_ne(U32.and(flags, 512), 0) ||
    U32.is_ne(U32.and(flags, 1024), 0) ||
    U32.is_ne(U32.and(flags, 16384), 0))

def reflect_constructor_new_instance(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +handle : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +args_ref : +List<M.Slot> = args
    +method : M.LoadedMethod <- reflect_constructor_member(vm, args_ref)
    checked : Unit <- reflect_constructor_access(vm, accessible_override(handle), M.loaded_method_owner(method), M.loaded_method_flags(method))
    instantiable : Unit <- S.check(constructor_instantiable(vm, M.loaded_method_owner(method)), "java/lang/InstantiationException")
    argument_array : M.Slot <- slot1(args_ref)
    +values : +List<M.Slot> <- reflect_argument_values(vm, bits_of(argument_array))
    +converted : +List<M.Slot> <- reflect_method_values(vm, method, values)
    result : O.Outcome <- reflect_constructor_instance_alloc(vm, method, M.loaded_method_owner(method), converted)
    return result

def reflect_constructor_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_constructor_member(vm, args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(class_display_name(class_name_text(vm, M.loaded_method_owner(method)))))
    return result

def reflect_constructor_modifiers(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_constructor_member(vm, args)
    result : O.Outcome <- int_out(vm, M.loaded_method_flags(method))
    return result
def method_exception_types_from_method(+vm: M.VM, method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    source : AnnotationMetadataRef <- method_annotation_source(vm, method)
    result : O.Outcome <- method_exception_types(source)
    return result
def constructor_exception_types_result(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, proxy_class_is_synthetic(vm, M.loaded_method_owner(method)), reflect_empty_parameter_types(vm), method_exception_types_from_method(vm, method))


def reflect_constructor_get_exception_types(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_constructor_member(vm, args)
    result : O.Outcome <- constructor_exception_types_result(vm, method)
    return result

def reflect_constructor_is_synthetic(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_constructor_member(vm, args)
    result : O.Outcome <- reflect_flag_value(vm, M.loaded_method_flags(method), 4096)
    return result

def reflect_constructor_is_varargs(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_constructor_member(vm, args)
    result : O.Outcome <- reflect_flag_value(vm, M.loaded_method_flags(method), 128)
    return result

def reflect_constructor_parameter_types(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_constructor_member(vm, args)
    result : O.Outcome <- reflect_member_parameter_types(vm, method)
    return result

def class_superclass(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), target), "java/lang/NoClassDefFoundError")
    parent : U32 = M.loaded_class_parent(class)
    result : O.Outcome <- class_superclass_parent(vm, parent)
    return result
def class_get_modifiers(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- int_out(vm, class_flags(vm, target))
    return result


def class_interfaces_found(+vm: M.VM, target: U32, found: Maybe<&2, M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{interfaces}: returned(vm, Some{interfaces})
    case None{}:
      do Result<&2, &2, String, O.Outcome>:
        class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), target), "java/lang/NoClassDefFoundError")
        refs : ReflectRefs <- interface_mirror_alloc(vm, M.loaded_class_interfaces(class), Nil{})
        result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/Class;", "java/lang/Class")
        return result

def class_interfaces_entry(+vm: M.VM, entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  match entry:
    case M.HeapEntry{class_value, kind, target, +fields, values, chars}:
      class_interfaces_found(vm, target, H.binding_find(fields, 0))

def class_get_interfaces(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    entry : M.HeapEntry <- class_entry(vm, args)
    result : O.Outcome <- class_interfaces_entry(vm, entry)
    return result

def class_is_primitive(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    +name : String = class_name_text(vm, target)
    result : O.Outcome <- bool_out(vm, primitive_name(name))
    return result

def class_is_array(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- bool_out(vm, String.starts_with(class_name_text(vm, target), "["))
    return result

def class_is_interface(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- bool_out(vm, U32.is_ne(U32.and(class_flags(vm, target), 512), 0))
    return result

def class_is_annotation(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- bool_out(vm, U32.is_ne(U32.and(class_flags(vm, target), 8192), 0))
    return result

def class_is_annotation_present(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    annotation : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(annotation))
    checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 8), "java/lang/IllegalArgumentException")
    +annotation_type : U32 = entry_element(entry)
    +name : String = class_name_text(vm, annotation_type)
    direct : Bool <- class_annotation_direct_present(vm, target, name)
    present : Bool <- class_annotation_present_inherited_result(64n, vm, target, name, annotation_type, direct)
    result : O.Outcome <- bool_out(vm, present)
    return result

def class_is_enum(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- bool_out(vm, U32.is_ne(U32.and(class_flags(vm, target), 16384), 0))
    return result

def proxy_interface_scan(+vm: M.VM, +values: +List<M.Slot>, +target: U32) -> Result<&2, &2, String, Bool>:
  match values:
    case Nil{}: Done{False{}}
    case Con{slot, rest}:
      do Result<&2, &2, String, Bool>:
        +mirror : M.HeapEntry <- H.get(S.heap(vm), bits_of(slot))
        found : Bool = U32.is_eq(entry_kind(mirror), 8) && U32.is_eq(entry_element(mirror), target)
        result : Bool <- Bool.pick(Result<&2, &2, String, Bool>, found, Done{True{}}, proxy_interface_scan(vm, rest, target))
        return result
def proxy_assignable_value(+vm: M.VM, +proxy: U32, +target: U32) -> Result<&2, &2, String, Bool>:
  do Result<&2, &2, String, Bool>:
    interfaces : U32 <- proxy_field(vm, proxy, 1)
    array : M.HeapEntry <- H.get(S.heap(vm), interfaces)
    found : Bool <- proxy_interface_scan(vm, entry_values(array), target)
    return Bool.or(found, U32.is_eq(target, class_id(vm, "java/lang/reflect/Proxy")))
def class_assignable_source(+vm: M.VM, kind: U32, target: U32, source: M.HeapEntry, reference: U32) -> Result<&2, &2, String, Bool>:
  match kind:
    case 10: proxy_assignable_value(vm, reference, target)
    case _: Done{H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(source), target)}

def class_mirror_assignable_fields(+vm: M.VM, source: U32, target: U32, +fields: +List<M.Binding>) -> Result<&2, &2, String, Bool>:
  Done{H.assignable(S.classes(vm), S.symbols(vm), source, target)}

def class_assignable_mirror(+vm: M.VM, target: U32, entry: M.HeapEntry) -> Result<&2, &2, String, Bool>:
  match entry:
    case M.HeapEntry{class_value, kind, element, +fields, values, chars}:
      match kind:
        case 8: class_mirror_assignable_fields(vm, element, target, fields)
        case _: Done{False{}}
def class_assignable_from(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    other : M.Slot <- slot1(args)

    +source_entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(other))
    valid : Bool <- class_assignable_mirror(vm, target, source_entry)
    result : O.Outcome <- bool_out(vm, valid)
    return result

def proxy_instance_of(+vm: M.VM, +proxy: U32, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    interfaces : U32 <- proxy_field(vm, proxy, 1)
    array : M.HeapEntry <- H.get(S.heap(vm), interfaces)
    result : Bool <- proxy_interface_scan(vm, entry_values(array), target)
    outcome : O.Outcome <- bool_out(vm, result || U32.is_eq(target, class_id(vm, "java/lang/reflect/Proxy")))
    return outcome


def proxy_instance_of_fields(+vm: M.VM, +fields: +List<M.Binding>, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    interfaces_slot : M.Slot <- S.require(M.Slot, H.binding_find(fields, 1), "java/lang/IllegalStateException")
    array : M.HeapEntry <- H.get(S.heap(vm), bits_of(interfaces_slot))
    result : Bool <- proxy_interface_scan(vm, entry_values(array), target)
    outcome : O.Outcome <- bool_out(vm, result || U32.is_eq(target, class_id(vm, "java/lang/reflect/Proxy")))
    return outcome

def class_is_instance_kind(kind: U32, +vm: M.VM, target: U32, class_value: U32, +fields: +List<M.Binding>) -> Result<&2, &2, String, O.Outcome>:
  match kind:
    case 10: proxy_instance_of_fields(vm, fields, target)
    case _: bool_out(vm, H.assignable(S.classes(vm), S.symbols(vm), class_value, target))

def class_is_instance_entry(+vm: M.VM, target: U32, entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  match entry:
    case M.HeapEntry{class_value, kind, element, +fields, values, chars}:
      class_is_instance_kind(kind, vm, target, class_value, fields)

def class_is_instance_nonnull(+vm: M.VM, target: U32, reference: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    result : O.Outcome <- class_is_instance_entry(vm, target, entry)
    return result

def class_is_instance_value(+vm: M.VM, target: U32, bits: U32) -> Result<&2, &2, String, O.Outcome>:
  match bits:
    case 0: bool_out(vm, False{})
    case reference: class_is_instance_nonnull(vm, target, reference)


def class_is_instance(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    +value : M.Slot <- slot1(args)
    result : O.Outcome <- class_is_instance_value(vm, target, bits_of(value))
    return result



def class_assignable_entry(kind: U32, +vm: M.VM, target: U32, +entry: M.HeapEntry, reference: U32) -> Result<&2, &2, String, Bool>:
  match kind:
    case 10: proxy_assignable_value(vm, reference, target)
    case _: Done{H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), target)}
def class_cast_entry_result(valid: Result<&2, &2, String, Bool>, +vm: M.VM, reference: U32) -> Result<&2, &2, String, O.Outcome>:
  match valid:
    case Fail{error}: Fail{error}
    case Done{ok}: Bool.pick(Result<&2, &2, String, O.Outcome>, ok, ref_out(vm, reference), throw_name(vm, "java/lang/ClassCastException"))


def class_cast_value(+vm: M.VM, +target: U32, +value: M.Slot, +bits: U32) -> Result<&2, &2, String, O.Outcome>:
  match bits:
    case 0:
      ref_out(vm, 0)
    case +reference:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        valid : Result<&2, &2, String, Bool> = class_assignable_entry(entry_kind(entry), vm, target, entry, reference)
        result : O.Outcome <- class_cast_entry_result(valid, vm, reference)
        return result

def class_cast(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    +value : M.Slot <- slot1(args)
    result : O.Outcome <- class_cast_value(vm, target, value, bits_of(value))
    return result


def nth_char(chars: +List<U32>, n: Nat) -> Maybe<&2, U32>:
  match chars n:
    case Nil{} _: None{}
    case Con{h, t} 0n: Some{h}
    case Con{h, t} 1n+p: nth_char(t, p)

def chars_len(chars: +List<U32>) -> U32:
  M.length(U32, chars)

def concat_chars(xs: +List<U32>, ys: +List<U32>) -> +List<U32>:
  M.append(U32, xs, ys)

def string_chars_entry(entry: M.HeapEntry) -> Result<&2, &2, String, +List<U32>>:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}:
      do Result<&2, &2, String, +List<U32>>:
        checked : Unit <- S.check(U32.is_eq(kind, 3), "InvalidState: expected String")
        return chars

def string_chars(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    chars : +List<U32> <- string_chars_entry(entry)
    return chars

def object_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  void_out(vm)

def object_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +left : M.Slot <- slot0(args)
    +right : M.Slot <- slot1(args)
    result : O.Outcome <- bool_out(vm, U32.is_eq(bits_of(left), bits_of(right)))
    return result

def identity_hash_entry(found: Result<&2, &2, String, M.HeapEntry>, +reference: U32) -> U32:
  match found:
    case Done{+entry}: Bool.pick(U32, U32.is_eq(entry_kind(entry), 8), entry_element(entry), reference)
    case Fail{error}: reference

# Object.hashCode identity: the reference, except that a Class mirror hashes as
# the class it mirrors so generic Type hashes need no mirror allocation.
def object_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    result : O.Outcome <- int_out(vm, identity_hash_entry(H.get(S.heap(vm), bits_of(receiver)), bits_of(receiver)))
    return result

def slash_to_dot(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{Chr{47}, t}: SCon{Chr{46}, slash_to_dot(t)}
    case SCon{h, t}: SCon{h, slash_to_dot(t)}

def hex_digit(+n: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(n, 10), U32.add(48, n), U32.add(87, n))}

def hex_go(n: Nat, +value: U32, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+p:
      hex_go(p, U32.shrn(value, 4n), SCon{hex_digit(U32.and(value, 15)), acc})

def object_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +ref : U32 = bits_of(receiver)
    checked : Unit <- S.check(U32.is_ne(ref, 0), npe())
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    text : String = slash_to_dot(class_name_text(vm, H.entry_class(entry))) ++ "@" ++ hex_go(8n, ref, "")
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(text))
    return result

def require_non_null(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(value), 0), npe())
    result : O.Outcome <- returned(vm, Some{value})
    return result

def objects_equals_refs(+vm: M.VM, +a: U32, +b: U32) -> Result<&2, &2, String, O.Outcome>:
  bool_out(vm, U32.is_eq(a, b))

def objects_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +left : M.Slot <- slot0(args)
    +right : M.Slot <- slot1(args)
    result : O.Outcome <- objects_equals_refs(vm, bits_of(left), bits_of(right))
    return result



def call_virtual(+vm: M.VM, method: Maybe<&2, M.LoadedMethod>, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match method:
    case None{}: Fail{"java/lang/NoSuchMethodError"}
    case Some{+value}:
      # The interpreter dispatches intrinsic and bytecode targets alike, so every
      # MiniJRE override (for example StringBuilder.toString) is reachable here.
      Done{O.Call{vm, value, args}}

# Host continuations resume when the callback started at the current frame
# depth returns; the depth marker keeps nested returns from consuming them.
def push_cont(+vm: M.VM, item: M.Cont) -> M.VM:
  S.with_cont(vm, Con{M.HostCallback{M.length(M.Frame, S.frames(vm))}, Con{item, S.host_cont_of(S.host(vm))}})

# An intrinsic that needs a class another thread is initializing parks; when
# the initializer finishes, `cont` resumes like a returned <clinit> callback.
def monitor_park(+vm: M.VM, +object: U32, cont: M.Cont) -> O.Outcome:
  O.Suspend{S.with_status(S.with_effect(Th.park(push_cont(vm, cont), M.MonitorPark{object}, False{}, M.Clock{0, 0}), M.Park{}), 5), M.Park{}}

def init_park(+vm: M.VM, +class: U32, cont: M.Cont) -> O.Outcome:
  O.Suspend{S.with_status(S.with_effect(Th.park(push_cont(vm, cont), M.InitPark{class}, False{}, M.Clock{0, 0}), M.Park{}), 5), M.Park{}}

def objects_equals_dispatch(+vm: M.VM, +a: U32, +b: U32) -> Result<&2, &2, String, O.Outcome>:
  call_virtual(push_cont(vm, M.NeedEquals{0, a, b}), virtual_on(vm, a, "equals", "(Ljava/lang/Object;)Z"), [M.Slot{3, a}, M.Slot{3, b}])

def string_length(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    chars : +List<U32> <- string_chars(vm, bits_of(receiver))
    result : O.Outcome <- int_out(vm, chars_len(chars))
    return result

def string_empty(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    chars : +List<U32> <- string_chars(vm, bits_of(receiver))
    result : O.Outcome <- bool_out(vm, U32.is_eq(chars_len(chars), 0))
    return result

def string_char_at(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +index : M.Slot <- slot1(args)
    +chars : +List<U32> <- string_chars(vm, bits_of(receiver))
    +i : U32 = bits_of(index)
    checked : Unit <- S.check(Bool.not(V.negative(i)) && U32.is_lt(i, chars_len(chars)), sioob())
    unit : U32 <- S.require(U32, nth_char(chars, U32.to_nat(i)), sioob())
    result : O.Outcome <- int_out(vm, unit)
    return result

def string_equals_chars(+vm: M.VM, +a: U32, +right: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    left : +List<U32> <- string_chars(vm, a)
    result : O.Outcome <- bool_out(vm, H.units_equal(left, right))
    return result

def string_equals_entry(+vm: M.VM, +a: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, values, chars}:
          Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(kind, 3), string_equals_chars(vm, a, chars), bool_out(vm, False{}))

def string_equals_refs(+vm: M.VM, +a: U32, +b: U32) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(a, b), bool_out(vm, True{}),
    Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(b, 0), bool_out(vm, False{}), string_equals_entry(vm, a, H.get(S.heap(vm), b))))

def string_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +left : M.Slot <- slot0(args)
    +right : M.Slot <- slot1(args)
    result : O.Outcome <- string_equals_refs(vm, bits_of(left), bits_of(right))
    return result

def string_hashcode(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    chars : +List<U32> <- string_chars(vm, bits_of(receiver))
    result : O.Outcome <- int_out(vm, string_hash_go(chars, 0))
    return result

def substring_range(+vm: M.VM, +chars: +List<U32>, +begin: U32, +end: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +len : U32 = chars_len(chars)
    checked : Unit <- S.check(Bool.not(V.negative(begin)) && Bool.not(V.negative(end)) && U32.is_le(begin, end) && U32.is_le(end, len), sioob())
    sliced : +List<U32> = H.slice_chars(H.drop_chars(chars, U32.to_nat(begin)), U32.to_nat(U32.sub(end, begin)))
    result : O.Outcome <- intern_or_alloc(vm, sliced)
    return result

def string_substring1(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +begin : M.Slot <- slot1(args)
    +chars : +List<U32> <- string_chars(vm, bits_of(receiver))
    result : O.Outcome <- substring_range(vm, chars, bits_of(begin), chars_len(chars))
    return result

def string_substring2(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +begin : M.Slot <- slot1(args)
    +end : M.Slot <- slot2(args)
    chars : +List<U32> <- string_chars(vm, bits_of(receiver))
    result : O.Outcome <- substring_range(vm, chars, bits_of(begin), bits_of(end))
    return result

def string_concat(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +left : M.Slot <- slot0(args)
    +right : M.Slot <- slot1(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(right), 0), npe())
    a : +List<U32> <- string_chars(vm, bits_of(left))
    b : +List<U32> <- string_chars(vm, bits_of(right))
    result : O.Outcome <- intern_or_alloc(vm, concat_chars(a, b))
    return result

def chars_nonempty(values: +List<U32>) -> Bool:
  match values:
    case Nil{}: False{}
    case _: True{}

def starts_with_units(text: +List<U32>, prefix: +List<U32>) -> Bool:
  match text prefix:
    case _ Nil{}: True{}
    case Con{+unit, rest} Con{+expected, more}: U32.is_eq(unit, expected) && starts_with_units(rest, more)
    case Nil{} _: False{}

def contains_units(text: +List<U32>, +needle: +List<U32>) -> Bool:
  match text:
    case Nil{}: Bool.not(chars_nonempty(needle))
    case Con{+unit, +rest}: starts_with_units(Con{unit, rest}, needle) || contains_units(rest, needle)

# CharSequence contents for the MiniJRE implementations (String and StringBuilder);
# user-defined CharSequence classes would need a Java callback and are rejected.
def char_sequence_entry(entry: M.HeapEntry) -> Result<&2, &2, String, +List<U32>>:
  match entry:
    case M.HeapEntry{class, +kind, element, fields, values, chars}:
      do Result<&2, &2, String, +List<U32>>:
        checked : Unit <- S.check(U32.is_eq(kind, 3) || U32.is_eq(kind, 7), "UnsupportedFeature: user-defined CharSequence")
        return chars

def char_sequence_chars(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    checked : Unit <- S.check(U32.is_ne(reference, 0), npe())
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    chars : +List<U32> <- char_sequence_entry(entry)
    return chars

def string_contains(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +needle : M.Slot <- slot1(args)
    text : +List<U32> <- string_chars(vm, bits_of(receiver))
    target : +List<U32> <- char_sequence_chars(vm, bits_of(needle))
    result : O.Outcome <- bool_out(vm, contains_units(text, target))
    return result

def string_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    result : O.Outcome <- returned(vm, Some{receiver})
    return result

def string_value_of_int(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(V.int_show(bits_of(value))))
    return result

def string_value_of_bool(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(Bool.pick(String, U32.is_eq(bits_of(value), 0), "false", "true")))
    return result

def string_value_of_object_ref(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, O.Outcome>:
  match reference:
    case 0: intern_or_alloc(vm, units_from_string("null"))
    case +value: call_virtual(push_cont(vm, M.NeedToString{0, value}), virtual_on(vm, value, "toString", "()Ljava/lang/String;"), [M.Slot{3, value}])

def string_value_of_object(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    result : O.Outcome <- string_value_of_object_ref(vm, bits_of(value))
    return result

def builder_chars_entry(entry: M.HeapEntry) -> Result<&2, &2, String, +List<U32>>:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}:
      do Result<&2, &2, String, +List<U32>>:
        checked : Unit <- S.check(U32.is_eq(kind, 7), "InvalidState: expected StringBuilder")
        return chars

def builder_get(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    chars : +List<U32> <- builder_chars_entry(entry)
    return chars

def builder_put(+vm: M.VM, +reference: U32, chars: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 7, 0, Nil{}, Nil{}, chars}
    result : O.Outcome <- ref_out(H.put(vm, reference, updated), reference)
    return result

def builder_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), M.HeapEntry{H.entry_class(entry), 7, 0, Nil{}, Nil{}, Nil{}}))
    return result

def builder_init_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +value : M.Slot <- slot1(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(value), 0), npe())
    chars : +List<U32> <- string_chars(vm, bits_of(value))
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), M.HeapEntry{H.entry_class(entry), 7, 0, Nil{}, Nil{}, chars}))
    return result

def builder_append_chars(+vm: M.VM, +receiver: U32, extra: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    chars : +List<U32> <- builder_get(vm, receiver)
    result : O.Outcome <- builder_put(vm, receiver, concat_chars(chars, extra))
    return result

def builder_append_string_ref(+vm: M.VM, +receiver: U32, +value: U32) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case 0: builder_append_chars(vm, receiver, units_from_string("null"))
    case +v:
      do Result<&2, &2, String, O.Outcome>:
        chars : +List<U32> <- string_chars(vm, v)
        result : O.Outcome <- builder_append_chars(vm, receiver, chars)
        return result

def builder_append_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +value : M.Slot <- slot1(args)
    result : O.Outcome <- builder_append_string_ref(vm, bits_of(receiver), bits_of(value))
    return result

def builder_append_object_ref(+vm: M.VM, +receiver: U32, +value: U32) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case 0: builder_append_chars(vm, receiver, units_from_string("null"))
    case +v: call_virtual(push_cont(vm, M.NeedToString{1, receiver}), virtual_on(vm, v, "toString", "()Ljava/lang/String;"), [M.Slot{3, v}])

def builder_append_object(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +value : M.Slot <- slot1(args)
    result : O.Outcome <- builder_append_object_ref(vm, bits_of(receiver), bits_of(value))
    return result

def builder_append_int(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +value : M.Slot <- slot1(args)
    result : O.Outcome <- builder_append_chars(vm, bits_of(receiver), units_from_string(V.int_show(bits_of(value))))
    return result

def builder_append_char(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +value : M.Slot <- slot1(args)
    result : O.Outcome <- builder_append_chars(vm, bits_of(receiver), [U32.and(bits_of(value), 65535)])
    return result

def builder_append_bool(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +value : M.Slot <- slot1(args)
    result : O.Outcome <- builder_append_chars(vm, bits_of(receiver), units_from_string(Bool.pick(String, U32.is_eq(bits_of(value), 0), "false", "true")))
    return result

def builder_length(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    chars : +List<U32> <- builder_get(vm, bits_of(receiver))
    result : O.Outcome <- int_out(vm, chars_len(chars))
    return result

def builder_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    chars : +List<U32> <- builder_get(vm, bits_of(receiver))
    result : O.Outcome <- intern_or_alloc(vm, chars)
    return result

def boxed_range(+bits: U32) -> Bool:
  Bool.not(V.signed_lt(bits, 4294967168)) && Bool.not(V.signed_lt(127, bits))

def integer_box_cached(+vm: M.VM, +bits: U32, cached: Bool, found: Maybe<&2, U32>) -> Result<&2, &2, String, O.Outcome>:
  match cached found:
    case True{} Some{reference}: ref_out(vm, reference)
    case _ _:
      alloc_result(H.allocate(vm, M.HeapEntry{class_id(vm, "java/lang/Integer"), 0, 0, [M.Binding{0, M.Slot{1, bits}}], Nil{}, Nil{}}), vm2 => reference => ref_out(vm2, reference))

def integer_box(+vm: M.VM, +bits: U32) -> Result<&2, &2, String, O.Outcome>:
  integer_box_cached(vm, bits, boxed_range(bits), H.integer_intern(S.heap(vm), class_id(vm, "java/lang/Integer"), bits))

def integer_value_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    result : O.Outcome <- integer_box(vm, bits_of(value))
    return result

def integer_int_value(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- int_out(vm, H.integer_value(entry_fields(entry)))
    return result
def wide_value_from_binding(+vm: M.VM, +receiver: M.Slot, +tag: U32) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    checked : Unit <- S.check(U32.is_ne(bits_of(receiver), 0), npe())
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +class_name : String = Bool.pick(String, U32.is_eq(tag, 4), "java/lang/Long", "java/lang/Double")
    +descriptor : String = Bool.pick(String, U32.is_eq(tag, 4), "J", "D")
    +field : U32 <- wrapper_value_field_id(vm, class_name, descriptor)
    +value : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), field), "java/lang/IllegalArgumentException")
    checked_tag : Unit <- S.check(U32.is_eq(M.slot_tag(value), tag), "java/lang/IllegalArgumentException")
    return value


def long_cache_range(+value: W.Words) -> Bool:
  Bool.not(W.signed_less(value, W.Words{4294967295, 4294967168})) &&
    Bool.not(W.signed_less(W.Words{0, 127}, value))

def wide_binding_matches(found: Maybe<&2, M.Slot>, high: U32, low: U32) -> Bool:
  match found:
    case Some{M.Wide{4, actual_high, actual_low}}:
      U32.is_eq(actual_high, high) && U32.is_eq(actual_low, low)
    case _: False{}

@unsafe def long_intern_scan(entries: +List<M.HeapEntry>, +class: U32, +field: U32, +high: U32, +low: U32, +reference: U32) -> Maybe<&2, U32>:
  match entries:
    case Nil{}: None{}
    case Con{entry, rest}:
      match entry:
        case M.HeapEntry{object_class, kind, element, fields, values, chars}:
          selected : Bool = U32.is_eq(object_class, class) && U32.is_eq(kind, 0) &&
            wide_binding_matches(H.binding_find(fields, field), high, low)
          Bool.pick(Maybe<&2, U32>, selected, Some{reference}, long_intern_scan(rest, class, field, high, low, (reference + 1 : U32)))

def long_intern(heap: +List<M.HeapEntry>, class: U32, field: U32, high: U32, low: U32) -> Maybe<&2, U32>:
  long_intern_scan(heap, class, field, high, low, 1)

def wide_box_allocate(+vm: M.VM, +class_name: String, +field: U32, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, class_name), [M.Binding{field, value}])), vm2 => reference => ref_out(vm2, reference))

def wide_box_cached(vm: M.VM, class_name: String, field: U32, value: M.Slot, found: Maybe<&2, U32>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{reference}: ref_out(vm, reference)
    case None{}: wide_box_allocate(vm, class_name, field, value)
def wide_box_long_range(+vm: M.VM, +class_name: String, +field: U32, +value: M.Slot, +high: U32, +low: U32, cached: Bool) -> Result<&2, &2, String, O.Outcome>:
  match cached:
    case True{}:
      wide_box_cached(vm, class_name, field, value,
        long_intern(S.heap(vm), class_id(vm, class_name), field, high, low))
    case False{}:
      wide_box_allocate(vm, class_name, field, value)
def wide_box_with_field(+vm: M.VM, +class_name: String, field: U32, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case M.Wide{4, high, low}:
      wide_box_long_range(vm, class_name, field, value, high, low, long_cache_range(W.Words{high, low}))
    case _:
      wide_box_allocate(vm, class_name, field, value)
def wide_box(+vm: M.VM, +args: +List<M.Slot>, +class_name: String, +tag: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    checked : Unit <- S.check(U32.is_eq(M.slot_tag(value), tag), "java/lang/IllegalArgumentException")
    +descriptor : String = Bool.pick(String, U32.is_eq(tag, 4), "J", "D")
    +field : U32 <- wrapper_value_field_id(vm, class_name, descriptor)
    result : O.Outcome <- wide_box_with_field(vm, class_name, field, value)
    return result

def wide_value(+vm: M.VM, +args: +List<M.Slot>, +tag: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, tag)
    result : O.Outcome <- returned(vm, Some{value})
    return result

def wide_words(value: M.Slot, expected: U32) -> Result<&2, &2, String, W.Words>:
  match value:
    case M.Wide{tag, high, low}:
      do Result<&2, &2, String, W.Words>:
        checked : Unit <- S.check(U32.is_eq(tag, expected), "java/lang/IllegalArgumentException")
        return W.Words{high, low}
    case _: Fail{"java/lang/IllegalArgumentException"}


def wide_text(tag: U32, words: W.Words) -> Result<&2, &2, String, String>:
  match tag:
    case 4: Done{W.long_show(words)}
    case 5: B64.double_to_string(words)
    case _: Fail{"java/lang/IllegalArgumentException"}
def long_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, 4)
    +words : W.Words <- wide_words(value, 4)
    text : String = W.long_show(words)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(text))
    return result
def double_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, 5)
    +words : W.Words <- wide_words(value, 5)
    text : String <- B64.double_to_string(words)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(text))
    return result
def string_value_of_wide(+vm: M.VM, +args: +List<M.Slot>, +tag: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot0(args)
    +words : W.Words <- wide_words(value, tag)
    text : String <- wide_text(tag, words)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(text))
    return result

def builder_append_wide(+vm: M.VM, +args: +List<M.Slot>, +tag: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- slot1(args)
    +words : W.Words <- wide_words(value, tag)
    text : String <- wide_text(tag, words)
    result : O.Outcome <- builder_append_chars(vm, bits_of(receiver), units_from_string(text))
    return result



# Character.digit for ASCII digits and letters in the given radix.
def parse_digit(+c: U32, +radix: U32) -> Maybe<&2, U32>:
  +value : U32 = Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), U32.sub(c, 48),
    Bool.pick(U32, U32.is_ge(c, 97) && U32.is_le(c, 122), U32.sub(c, 87),
      Bool.pick(U32, U32.is_ge(c, 65) && U32.is_le(c, 90), U32.sub(c, 55), 99)))
  Bool.pick(Maybe<&2, U32>, U32.is_lt(value, radix), Some{value}, None{})

# acc * radix + d, unless it passes Integer.MAX_VALUE (or -MIN_VALUE).
def parse_acc(+acc: U32, +d: U32, +neg: Bool, +radix: U32) -> Maybe<&2, U32>:
  +limit = Bool.pick(U32, neg, 2147483648, 2147483647)
  Bool.pick(Maybe<&2, U32>, U32.is_gt(acc, U32.div(U32.sub(limit, d), radix)), None{}, Some{U32.add(U32.mul(acc, radix), d)})

def require_digit(found: Maybe<&2, U32>) -> Result<&2, &2, String, U32>:
  match found:
    case None{}: Fail{nfe()}
    case Some{d}: Done{d}

def parse_digit_result(c: U32) -> Result<&2, &2, String, U32>:
  require_digit(parse_digit(c, 10))

def require_acc(found: Maybe<&2, U32>) -> Result<&2, &2, String, U32>:
  match found:
    case None{}: Fail{nfe()}
    case Some{d}: Done{d}

@unsafe def parse_go(chars: +List<U32>, +acc: U32, seen: Bool, +neg: Bool, +radix: U32) -> Result<&2, &2, String, U32>:
  match chars:
    case Nil{}:
      Bool.pick(Result<&2, &2, String, U32>, seen, Done{Bool.pick(U32, neg, V.negate(acc), acc)}, Fail{nfe()})
    case Con{c, rest}:
      do Result<&2, &2, String, U32>:
        d : U32 <- require_digit(parse_digit(c, radix))
        next : U32 <- require_acc(parse_acc(acc, d, neg, radix))
        result : U32 <- parse_go(rest, next, True{}, neg, radix)
        return result

def parse_sign(chars: +List<U32>, +radix: U32) -> Result<&2, &2, String, U32>:
  match chars:
    case Nil{}: Fail{nfe()}
    case Con{43, rest}: parse_go(rest, 0, False{}, False{}, radix)
    case Con{45, rest}: parse_go(rest, 0, False{}, True{}, radix)
    case _: parse_go(chars, 0, False{}, False{}, radix)

@unsafe def integer_parse(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  integer_parse_in(vm, args, 10)

# Integer.parseInt(String, int): Character.MIN_RADIX to MAX_RADIX.
@unsafe def integer_parse_radix(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +radix : M.Slot <- slot1(args)
    +value : U32 = bits_of(radix)
    low : Unit <- S.check(Bool.not(V.negative(value)) && U32.is_ge(value, 2), "java/lang/NumberFormatException: radix " ++ V.int_show(value) ++ " less than Character.MIN_RADIX")
    high : Unit <- S.check(U32.is_le(value, 36), "java/lang/NumberFormatException: radix " ++ V.int_show(value) ++ " greater than Character.MAX_RADIX")
    result : O.Outcome <- integer_parse_in(vm, args, value)
    return result

def integer_parse_in(+vm: M.VM, +args: +List<M.Slot>, +radix: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(value), 0), npe())
    chars : +List<U32> <- string_chars(vm, bits_of(value))
    bits : U32 <- parse_sign(chars, radix)
    result : O.Outcome <- int_out(vm, bits)
    return result

def integer_equals_values(+vm: M.VM, +a: U32, +right: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    left : M.HeapEntry <- H.get(S.heap(vm), a)
    result : O.Outcome <- bool_out(vm, U32.is_eq(H.integer_value(entry_fields(left)), H.integer_value(entry_fields(right))))
    return result

def integer_equals_entry(+vm: M.VM, +a: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+entry}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(H.entry_class(entry), class_id(vm, "java/lang/Integer")),
        integer_equals_values(vm, a, entry), bool_out(vm, False{}))

def integer_equals_ref(+vm: M.VM, +a: U32, +b: U32) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(b, 0), bool_out(vm, False{}), integer_equals_entry(vm, a, H.get(S.heap(vm), b)))

def integer_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +left : M.Slot <- slot0(args)
    +right : M.Slot <- slot1(args)
    result : O.Outcome <- integer_equals_ref(vm, bits_of(left), bits_of(right))
    return result
def wide_words_equal(a: W.Words, b: W.Words) -> Bool:
  match a b:
    case W.Words{ah, al} W.Words{bh, bl}: U32.is_eq(ah, bh) && U32.is_eq(al, bl)

@unsafe def long_parse_digit(+chars: +List<U32>, +acc: W.Words, seen: Bool, neg: Bool, +limit_q: W.Words, +limit_r: W.Words) -> Result<&2, &2, String, W.Words>:
  match chars:
    case Nil{}: Bool.pick(Result<&2, &2, String, W.Words>, seen, Done{Bool.pick(W.Words, neg, W.neg(acc), acc)}, Fail{nfe()})
    case Con{c, rest}:
      do Result<&2, &2, String, W.Words>:
        +digit : U32 <- parse_digit_result(c)
        +at_limit : Bool = wide_words_equal(acc, limit_q)
        within : Unit <- S.check(Bool.not(W.unsigned_less(limit_q, acc)) && (Bool.not(at_limit) || U32.is_le(digit, W.long_to_int(limit_r))), nfe())
        next : W.Words = W.add(W.mul(acc, W.Words{0, 10}), W.Words{0, digit})
        result : W.Words <- long_parse_digit(rest, next, True{}, neg, limit_q, limit_r)
        return result

def long_parse_division(chars: +List<U32>, neg: Bool, division: W.Division) -> Result<&2, &2, String, W.Words>:
  match division:
    case W.Division{quotient, remainder}: long_parse_digit(chars, W.Words{0, 0}, False{}, neg, quotient, remainder)
def long_parse_go(chars: +List<U32>, +neg: Bool) -> Result<&2, &2, String, W.Words>:
  +limit : W.Words = Bool.pick(W.Words, neg, W.Words{2147483648, 0}, W.Words{2147483647, 4294967295})
  long_parse_division(chars, neg, W.unsigned_divide(limit, W.Words{0, 10}))

def long_parse_sign(chars: +List<U32>) -> Result<&2, &2, String, W.Words>:
  match chars:
    case Nil{}: Fail{nfe()}
    case Con{43, rest}: long_parse_go(rest, False{})
    case Con{45, rest}: long_parse_go(rest, True{})
    case _: long_parse_go(chars, False{})

def long_parse(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(value), 0), npe())
    chars : +List<U32> <- string_chars(vm, bits_of(value))
    +words : W.Words <- long_parse_sign(chars)
    result : O.Outcome <- returned(vm, Some{reflect_wide_slot(4, words)})
    return result

def wide_values_equal(+vm: M.VM, left: U32, right: U32, +tag: U32) -> Result<&2, &2, String, Bool>:
  do Result<&2, &2, String, Bool>:
    +left_entry : M.HeapEntry <- H.get(S.heap(vm), left)
    +right_entry : M.HeapEntry <- H.get(S.heap(vm), right)
    +class : U32 = class_id(vm, Bool.pick(String, U32.is_eq(tag, 4), "java/lang/Long", "java/lang/Double"))
    same_class : Bool = U32.is_eq(H.entry_class(right_entry), class)
    result : Bool <- Bool.pick(Result<&2, &2, String, Bool>, same_class,
      do Result<&2, &2, String, Bool>:
        +source : U32 = Bool.pick(U32, U32.is_eq(tag, 4), 74, 68)
        +left_value : M.Slot <- wrapper_value_slot(vm, left_entry, source)
        +right_value : M.Slot <- wrapper_value_slot(vm, right_entry, source)
        +left_words : W.Words <- wide_words(left_value, tag)
        +right_words : W.Words <- wide_words(right_value, tag)
        +same_words : Bool = wide_words_equal(left_words, right_words)
        return Bool.pick(Bool, U32.is_eq(tag, 5) && B64.double_is_nan(left_words) && B64.double_is_nan(right_words), True{}, same_words),
      Done{False{}})
    return result

def long_equals(+vm: M.VM, +args: +List<M.Slot>, +tag: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +left : M.Slot <- slot0(args)
    +right : M.Slot <- slot1(args)
    equal : Bool <- Bool.pick(Result<&2, &2, String, Bool>, U32.is_eq(bits_of(right), 0),
      Done{False{}}, wide_values_equal(vm, bits_of(left), bits_of(right), tag))
    result : O.Outcome <- bool_out(vm, equal)
    return result
def wide_low_word(words: W.Words) -> U32:
  match words:
    case W.Words{high, low}: low

def wide_word_xor(words: W.Words) -> U32:
  match words:
    case W.Words{high, low}: U32.xor(high, low)

def wide_low_value(+vm: M.VM, +args: +List<M.Slot>, +tag: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, tag)
    +words : W.Words <- wide_words(value, tag)
    result : O.Outcome <- int_out(vm, wide_low_word(words))
    return result

def long_bits_to_double(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot0(args)
    +words : W.Words <- wide_words(value, 4)
    result : O.Outcome <- returned(vm, Some{reflect_wide_slot(5, words)})
    return result

def double_raw_bits(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot0(args)
    +words : W.Words <- wide_words(value, 5)
    result : O.Outcome <- returned(vm, Some{reflect_wide_slot(4, words)})
    return result
def double_canonical_bits(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot0(args)
    +words : W.Words <- wide_words(value, 5)
    +canonical : W.Words = Bool.pick(W.Words, B64.double_is_nan(words), W.Words{2146959360, 0}, words)
    result : O.Outcome <- returned(vm, Some{reflect_wide_slot(4, canonical)})
    return result

def double_classify(+vm: M.VM, +args: +List<M.Slot>, infinite: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot0(args)
    +words : W.Words <- wide_words(value, 5)
    result : O.Outcome <- bool_out(vm, Bool.pick(Bool, infinite, B64.double_is_infinite(words), B64.double_is_nan(words)))
    return result
def long_double_value(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, 4)
    +words : W.Words <- wide_words(value, 4)
    +converted : W.Words = B64.long_to_double(words)
    result : O.Outcome <- returned(vm, Some{reflect_wide_slot(5, converted)})
    return result

def long_float_value(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, 4)
    +words : W.Words <- wide_words(value, 4)
    result : O.Outcome <- returned(vm, Some{M.Slot{2, B64.long_to_float(words)}})
    return result

def double_int_value(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, 5)
    +words : W.Words <- wide_words(value, 5)
    result : O.Outcome <- int_out(vm, B64.double_to_int(words))
    return result

def double_long_value(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, 5)
    +words : W.Words <- wide_words(value, 5)
    +converted : W.Words = B64.double_to_long(words)
    result : O.Outcome <- returned(vm, Some{reflect_wide_slot(4, converted)})
    return result

def double_float_value(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, 5)
    +words : W.Words <- wide_words(value, 5)
    result : O.Outcome <- returned(vm, Some{M.Slot{2, B64.double_to_f32(words)}})
    return result

def wide_hash_code(+vm: M.VM, +args: +List<M.Slot>, +tag: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- wide_value_from_binding(vm, receiver, tag)
    +words : W.Words <- wide_words(value, tag)
    +hash_words : W.Words = Bool.pick(W.Words, U32.is_eq(tag, 5) && B64.double_is_nan(words), W.Words{2146959360, 0}, words)
    result : O.Outcome <- int_out(vm, wide_word_xor(hash_words))
    return result

def integer_hashcode(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  integer_int_value(vm, args)

def integer_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(V.int_show(H.integer_value(entry_fields(entry)))))
    return result

def math_abs(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    result : O.Outcome <- int_out(vm, V.magnitude(bits_of(value)))
    return result

def math_min(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +a : M.Slot <- slot0(args)
    +b : M.Slot <- slot1(args)
    result : O.Outcome <- int_out(vm, Bool.pick(U32, V.signed_lt(bits_of(a), bits_of(b)), bits_of(a), bits_of(b)))
    return result

def math_max(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +a : M.Slot <- slot0(args)
    +b : M.Slot <- slot1(args)
    result : O.Outcome <- int_out(vm, Bool.pick(U32, V.signed_lt(bits_of(a), bits_of(b)), bits_of(b), bits_of(a)))
    return result







def replace_slot(xs: +List<M.Slot>, n: Nat, value: M.Slot) -> +List<M.Slot>:
  M.replace(M.Slot, xs, n, value)

def arraycopy_assignable_entry(+vm: M.VM, dest_entry: M.HeapEntry, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}:
      S.check(H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), entry_element(dest_entry)), ase())

def arraycopy_assignable_ref(+vm: M.VM, dest_entry: M.HeapEntry, +value: M.Slot) -> Result<&2, &2, String, Unit>:
  Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(bits_of(value), 0), Done{Unit{}}, arraycopy_assignable_entry(vm, dest_entry, H.get(S.heap(vm), bits_of(value))))

def arraycopy_assignable(+vm: M.VM, +dest_entry: M.HeapEntry, value: M.Slot) -> Result<&2, &2, String, Unit>:
  Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(entry_kind(dest_entry), 1), Done{Unit{}}, arraycopy_assignable_ref(vm, dest_entry, value))

@unsafe def arraycopy_walk(done: Bool, +vm: M.VM, +src: U32, +src_pos: U32, +dest: U32, +dest_pos: U32, +length: U32, +reverse: Bool) -> Result<&2, &2, String, O.Outcome>:
  match done:
    case True{}: void_out(vm)
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +src_entry : M.HeapEntry <- H.get(S.heap(vm), src)
        +dest_entry : M.HeapEntry <- H.get(S.heap(vm), dest)
        +i : U32 = Bool.pick(U32, reverse, U32.sub(length, 1), 0)
        +si : U32 = U32.add(src_pos, i)
        +di : U32 = U32.add(dest_pos, i)
        +value : M.Slot <- S.require(M.Slot, M.nth(M.Slot, entry_values(src_entry), si), oob())
        checked : Unit <- arraycopy_assignable(vm, dest_entry, value)
        updated_dest : M.HeapEntry = M.HeapEntry{H.entry_class(dest_entry), entry_kind(dest_entry), entry_element(dest_entry), Nil{}, replace_slot(entry_values(dest_entry), U32.to_nat(di), value), Nil{}}
        next_vm : M.VM = H.put(vm, dest, updated_dest)
        +next_len : U32 = U32.sub(length, 1)
        result : O.Outcome <- arraycopy_walk(U32.is_eq(next_len, 0), next_vm, src, Bool.pick(U32, reverse, src_pos, U32.add(src_pos, 1)), dest, Bool.pick(U32, reverse, dest_pos, U32.add(dest_pos, 1)), next_len, reverse)
        return result

@unsafe def arraycopy_loop(+vm: M.VM, +src: U32, +src_pos: U32, +dest: U32, +dest_pos: U32, +length: U32, reverse: Bool) -> Result<&2, &2, String, O.Outcome>:
  arraycopy_walk(U32.is_eq(length, 0), vm, src, src_pos, dest, dest_pos, length, reverse)

def arraycopy_overlap(+vm: M.VM, +src: U32, src_entry: M.HeapEntry, +src_pos: U32, +dest: U32, dest_entry: M.HeapEntry, +dest_pos: U32, +length: U32, reverse: Bool) -> Result<&2, &2, String, O.Outcome>:
  arraycopy_loop(vm, src, src_pos, dest, dest_pos, length, reverse)


def arraycopy_one(+vm: M.VM, +src: U32, +src_entry: M.HeapEntry, +si: U32, +dest: U32, +dest_entry: M.HeapEntry, +di: U32, +src_pos: U32, +dest_pos: U32, +length: U32, +reverse: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- S.require(M.Slot, M.nth(M.Slot, entry_values(src_entry), si), oob())
    checked : Unit <- arraycopy_assignable(vm, dest_entry, value)
    updated_dest : M.HeapEntry = M.HeapEntry{H.entry_class(dest_entry), entry_kind(dest_entry), entry_element(dest_entry), Nil{}, replace_slot(entry_values(dest_entry), U32.to_nat(di), value), Nil{}}
    next_vm : M.VM = H.put(vm, dest, updated_dest)
    result : O.Outcome <- arraycopy_loop(next_vm, src, Bool.pick(U32, reverse, src_pos, U32.add(src_pos, 1)), dest, Bool.pick(U32, reverse, dest_pos, U32.add(dest_pos, 1)), U32.sub(length, 1), reverse)
    return result

def arraycopy_bounds(+vm: M.VM, +src: U32, +src_entry: M.HeapEntry, +src_pos: U32, +dest: U32, +dest_entry: M.HeapEntry, +dest_pos: U32, +length: U32, mismatch: Bool) -> Result<&2, &2, String, O.Outcome>:
  match mismatch:
    case True{}: throw_name(vm, ase())
    case False{}:
      +src_len = M.length(M.Slot, entry_values(src_entry))
      +dest_len = M.length(M.Slot, entry_values(dest_entry))
      Bool.pick(Result<&2, &2, String, O.Outcome>,
        V.negative(src_pos) || V.negative(dest_pos) || V.negative(length) || U32.is_gt(U32.add(src_pos, length), src_len) || U32.is_gt(U32.add(dest_pos, length), dest_len),
        throw_name(vm, oob()),
        arraycopy_overlap(vm, src, src_entry, src_pos, dest, dest_entry, dest_pos, length, U32.is_eq(src, dest) && U32.is_lt(dest_pos, src_pos) && U32.is_lt(src_pos, U32.add(dest_pos, length))))

def arraycopy_kind(+vm: M.VM, +src: U32, +src_entry: M.HeapEntry, +src_pos: U32, +dest: U32, +dest_entry: M.HeapEntry, +dest_pos: U32, +length: U32) -> Result<&2, &2, String, O.Outcome>:
  +sk = entry_kind(src_entry)
  +dk = entry_kind(dest_entry)
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(sk, 1) || U32.is_eq(sk, 2),
    Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(dk, 1) || U32.is_eq(dk, 2),
      arraycopy_bounds(vm, src, src_entry, src_pos, dest, dest_entry, dest_pos, length, U32.is_ne(sk, dk)),
      throw_name(vm, ase())),
    throw_name(vm, ase()))

def arraycopy_entries(+vm: M.VM, +src: U32, +src_pos: U32, +dest: U32, +dest_pos: U32, +length: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +src_entry : M.HeapEntry <- H.get(S.heap(vm), src)
    +dest_entry : M.HeapEntry <- H.get(S.heap(vm), dest)
    result : O.Outcome <- arraycopy_kind(vm, src, src_entry, src_pos, dest, dest_entry, dest_pos, length)
    return result

def arraycopy(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +src : M.Slot <- slot0(args)
    +src_pos : M.Slot <- slot1(args)
    +dest : M.Slot <- slot2(args)
    +dest_pos : M.Slot <- slot3(args)
    +length : M.Slot <- slot4(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(src), 0) && U32.is_ne(bits_of(dest), 0), npe())
    result : O.Outcome <- arraycopy_entries(vm, bits_of(src), bits_of(src_pos), bits_of(dest), bits_of(dest_pos), bits_of(length))
    return result


def field_bits(fields: +List<M.Binding>, id: U32) -> U32:
  H.integer_value_found(H.binding_find(fields, id))

def list_mod(fields: +List<M.Binding>) -> U32:
  field_bits(fields, 0)

def do_put_list(+vm: M.VM, +reference: U32, result: Result<&2, &2, String, M.HeapEntry>, values: +List<M.Slot>, size: U32, mod: U32) -> M.VM:
  match result:
    case Fail{error}: vm
    case Done{entry}:
      H.put(vm, reference, H.list_entry(H.entry_class(entry), values, size, mod))

def put_list(+vm: M.VM, +reference: U32, values: +List<M.Slot>, size: U32, mod: U32) -> M.VM:
  do_put_list(vm, reference, H.get(S.heap(vm), reference), values, size, mod)

def do_put_map(+vm: M.VM, +reference: U32, result: Result<&2, &2, String, M.HeapEntry>, values: +List<M.Slot>, size: U32, mod: U32) -> M.VM:
  match result:
    case Fail{error}: vm
    case Done{entry}:
      H.put(vm, reference, H.map_entry(H.entry_class(entry), values, size, mod))

def put_map(+vm: M.VM, +reference: U32, values: +List<M.Slot>, size: U32, mod: U32) -> M.VM:
  do_put_map(vm, reference, H.get(S.heap(vm), reference), values, size, mod)


def list_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    result : O.Outcome <- void_out(put_list(vm, bits_of(receiver), Nil{}, 0, 0))
    return result

def list_init_cap(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +cap : M.Slot <- slot1(args)
    checked : Unit <- S.check(Bool.not(V.negative(bits_of(cap))), iae())
    result : O.Outcome <- list_init(vm, [receiver])
    return result

def list_size_of(entry: M.HeapEntry) -> U32:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  element

def list_values_of(entry: M.HeapEntry) -> +List<M.Slot>:
  entry_values(entry)

def list_entry_of(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, M.HeapEntry>:
  H.get(S.heap(vm), reference)

def coll_size(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- list_entry_of(vm, bits_of(receiver))
    result : O.Outcome <- int_out(vm, list_size_of(entry))
    return result

def coll_empty(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- list_entry_of(vm, bits_of(receiver))
    result : O.Outcome <- bool_out(vm, U32.is_eq(list_size_of(entry), 0))
    return result

def list_add(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +value : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- list_entry_of(vm, bits_of(receiver))
    +size : U32 = list_size_of(entry)
    updated : M.VM = put_list(vm, bits_of(receiver), M.append(M.Slot, list_values_of(entry), [value]), U32.add(size, 1), U32.add(list_mod(entry_fields(entry)), 1))
    result : O.Outcome <- bool_out(updated, True{})
    return result

def insert_at(xs: +List<M.Slot>, n: Nat, value: M.Slot) -> +List<M.Slot>:
  match xs n:
    case rest 0n: Con{value, rest}
    case Nil{} _: Con{value, Nil{}}
    case Con{h, t} 1n+p: Con{h, insert_at(t, p, value)}

def remove_at(xs: +List<M.Slot>, n: Nat) -> +List<M.Slot>:
  match xs n:
    case Nil{} _: Nil{}
    case Con{h, t} 0n: t
    case Con{h, t} 1n+p: Con{h, remove_at(t, p)}

def list_add_at(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +index : M.Slot <- slot1(args)
    +value : M.Slot <- slot2(args)
    +entry : M.HeapEntry <- list_entry_of(vm, bits_of(receiver))
    +i : U32 = bits_of(index)
    +size : U32 = list_size_of(entry)
    checked : Unit <- S.check(Bool.not(V.negative(i)) && U32.is_le(i, size), oob())
    updated : M.VM = put_list(vm, bits_of(receiver), insert_at(list_values_of(entry), U32.to_nat(i), value), U32.add(size, 1), U32.add(list_mod(entry_fields(entry)), 1))
    result : O.Outcome <- void_out(updated)
    return result

def list_get(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +index : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- list_entry_of(vm, bits_of(receiver))
    +i : U32 = bits_of(index)
    checked : Unit <- S.check(Bool.not(V.negative(i)) && U32.is_lt(i, list_size_of(entry)), oob())
    +value : M.Slot <- S.require(M.Slot, M.nth(M.Slot, list_values_of(entry), i), oob())
    result : O.Outcome <- returned(vm, Some{value})
    return result

def list_set(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +index : M.Slot <- slot1(args)
    +value : M.Slot <- slot2(args)
    +entry : M.HeapEntry <- list_entry_of(vm, bits_of(receiver))
    +i : U32 = bits_of(index)
    checked : Unit <- S.check(Bool.not(V.negative(i)) && U32.is_lt(i, list_size_of(entry)), oob())
    +old : M.Slot <- S.require(M.Slot, M.nth(M.Slot, list_values_of(entry), i), oob())
    updated : M.VM = put_list(vm, bits_of(receiver), replace_slot(list_values_of(entry), U32.to_nat(i), value), list_size_of(entry), list_mod(entry_fields(entry)))
    result : O.Outcome <- returned(updated, Some{old})
    return result

def list_remove(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +index : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- list_entry_of(vm, bits_of(receiver))
    +i : U32 = bits_of(index)
    checked : Unit <- S.check(Bool.not(V.negative(i)) && U32.is_lt(i, list_size_of(entry)), oob())
    +old : M.Slot <- S.require(M.Slot, M.nth(M.Slot, list_values_of(entry), i), oob())
    updated : M.VM = put_list(vm, bits_of(receiver), remove_at(list_values_of(entry), U32.to_nat(i)), U32.sub(list_size_of(entry), 1), U32.add(list_mod(entry_fields(entry)), 1))
    result : O.Outcome <- returned(updated, Some{old})
    return result

def list_clear(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- list_entry_of(vm, bits_of(receiver))
    updated : M.VM = Bool.pick(M.VM, U32.is_eq(entry_kind(entry), 6), put_map(vm, bits_of(receiver), Nil{}, 0, U32.add(list_mod(entry_fields(entry)), 1)), put_list(vm, bits_of(receiver), Nil{}, 0, U32.add(list_mod(entry_fields(entry)), 1)))
    result : O.Outcome <- void_out(updated)
    return result

def slot_or_zero(found: Maybe<&2, M.Slot>) -> M.Slot:
  match found:
    case None{}: M.Slot{0, 0}
    case Some{value}: value

@unsafe def list_contains_walk(mode: U32, +vm: M.VM, +list: U32, +query: U32, +index: U32, +entry: M.HeapEntry, +got: Result<&2, &2, String, M.HeapEntry>, +found: Maybe<&2, M.Slot>, +value: M.Slot, +same: Bool, +isnull: Bool) -> Result<&2, &2, String, O.Outcome>:
  match mode:
    case 0:
      match got:
        case Fail{error}: Fail{error}
        case Done{+got_entry}:
          list_contains_walk(1, vm, list, query, index, got_entry, got, None{}, value, U32.is_ge(index, list_size_of(got_entry)), False{})
    case 1:
      match same:
        case True{}: bool_out(vm, False{})
        case False{}:
          list_contains_walk(2, vm, list, query, index, entry, got, M.nth(M.Slot, list_values_of(entry), index), value, False{}, False{})
    case 2:
      match found:
        case None{}: Fail{oob()}
        case Some{+next}:
          +bits = bits_of(next)
          list_contains_walk(3, vm, list, query, index, entry, got, found, next, U32.is_eq(query, bits), U32.is_eq(query, 0) || U32.is_eq(bits, 0))
    case 3:
      match same:
        case True{}: bool_out(vm, True{})
        case False{}: list_contains_walk(4, vm, list, query, index, entry, got, found, value, same, isnull)
    case 4:
      match isnull:
        case True{}: list_contains_walk(1, vm, list, query, U32.add(index, 1), entry, got, None{}, value, U32.is_ge(U32.add(index, 1), list_size_of(entry)), False{})
        case False{}:
          call_virtual(push_cont(vm, M.NeedListEq{list, query, index, 0}), virtual_on(vm, query, "equals", "(Ljava/lang/Object;)Z"), [M.Slot{3, query}, value])
    case _: Fail{"VmError.Internal: list contains"}

def list_contains_at(+vm: M.VM, +list: U32, +query: U32, +index: U32) -> Result<&2, &2, String, O.Outcome>:
  list_contains_walk(0, vm, list, query, index, H.object_entry(0, Nil{}), list_entry_of(vm, list), None{}, M.Slot{0, 0}, False{}, False{})


def list_contains(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +query : M.Slot <- slot1(args)
    result : O.Outcome <- list_contains_at(vm, bits_of(receiver), bits_of(query), 0)
    return result




def resource_enum_has_more(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +enumeration : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +array_ref : U32 = field_bits(entry_fields(enumeration), 0)
    +array : M.HeapEntry <- H.get(S.heap(vm), array_ref)
    result : O.Outcome <- bool_out(vm, U32.is_lt(field_bits(entry_fields(enumeration), 1), M.length(M.Slot, entry_values(array))))
    return result

def resource_enum_next(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +enumeration : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +array_ref : U32 = field_bits(entry_fields(enumeration), 0)
    +array : M.HeapEntry <- H.get(S.heap(vm), array_ref)
    +cursor : U32 = field_bits(entry_fields(enumeration), 1)
    ready : Unit <- S.check(U32.is_lt(cursor, M.length(M.Slot, entry_values(array))), nsee())
    +value : M.Slot <- S.require(M.Slot, M.nth(M.Slot, entry_values(array), cursor), nsee())
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(enumeration), 0, 0, [M.Binding{0, M.Slot{3, array_ref}}, M.Binding{1, M.Slot{1, U32.add(cursor, 1)}}], Nil{}, Nil{}}
    result : O.Outcome <- returned(H.put(vm, bits_of(receiver), updated), Some{value})
    return result

def list_iterator(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- list_entry_of(vm, bits_of(receiver))
    result : O.Outcome <- alloc_result(H.allocate(vm, M.HeapEntry{class_id(vm, "java/util/ArrayList$Itr"), 0, 0, [M.Binding{0, receiver}, M.Binding{1, M.Slot{1, 0}}, M.Binding{2, M.Slot{1, 4294967295}}, M.Binding{3, M.Slot{1, list_mod(entry_fields(entry))}}], Nil{}, Nil{}}), vm2 => reference => ref_out(vm2, reference))
    return result

def itr_check(+vm: M.VM, +itr: M.HeapEntry) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    +list_ref : U32 = field_bits(entry_fields(itr), 0)
    +entry : M.HeapEntry <- list_entry_of(vm, list_ref)
    checked : Unit <- S.check(U32.is_eq(field_bits(entry_fields(itr), 3), list_mod(entry_fields(entry))), cme())
    return checked

def itr_has_next(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +itr : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    checked : Unit <- itr_check(vm, itr)
    +list_ref : U32 = field_bits(entry_fields(itr), 0)
    +entry : M.HeapEntry <- list_entry_of(vm, list_ref)
    result : O.Outcome <- bool_out(vm, U32.is_lt(field_bits(entry_fields(itr), 1), list_size_of(entry)))
    return result

def itr_next(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +itr : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    checked : Unit <- itr_check(vm, itr)
    +list_ref : U32 = field_bits(entry_fields(itr), 0)
    +entry : M.HeapEntry <- list_entry_of(vm, list_ref)
    +cursor : U32 = field_bits(entry_fields(itr), 1)
    ready : Unit <- S.check(U32.is_lt(cursor, list_size_of(entry)), nsee())
    +value : M.Slot <- S.require(M.Slot, M.nth(M.Slot, list_values_of(entry), cursor), nsee())
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(itr), 0, 0, [M.Binding{0, M.Slot{3, list_ref}}, M.Binding{1, M.Slot{1, U32.add(cursor, 1)}}, M.Binding{2, M.Slot{1, cursor}}, M.Binding{3, M.Slot{1, field_bits(entry_fields(itr), 3)}}], Nil{}, Nil{}}
    result : O.Outcome <- returned(H.put(vm, bits_of(receiver), updated), Some{value})
    return result

def itr_remove(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +itr : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    checked : Unit <- itr_check(vm, itr)
    +last : U32 = field_bits(entry_fields(itr), 2)
    ready : Unit <- S.check(U32.is_ne(last, 4294967295), ise())
    +list_ref : U32 = field_bits(entry_fields(itr), 0)
    +entry : M.HeapEntry <- list_entry_of(vm, list_ref)
    next_list : M.VM = put_list(vm, list_ref, remove_at(list_values_of(entry), U32.to_nat(last)), U32.sub(list_size_of(entry), 1), U32.add(list_mod(entry_fields(entry)), 1))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(itr), 0, 0, [M.Binding{0, M.Slot{3, list_ref}}, M.Binding{1, M.Slot{1, last}}, M.Binding{2, M.Slot{1, 4294967295}}, M.Binding{3, M.Slot{1, U32.add(list_mod(entry_fields(entry)), 1)}}], Nil{}, Nil{}}
    result : O.Outcome <- void_out(H.put(next_list, bits_of(receiver), updated))
    return result


def map_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    result : O.Outcome <- void_out(put_map(vm, bits_of(receiver), Nil{}, 0, 0))
    return result

def map_pairs(entry: M.HeapEntry) -> +List<M.Slot>:
  entry_values(entry)

def map_find(pairs: +List<M.Slot>, +key: U32, +index: U32) -> Maybe<&2, U32>:
  match pairs:
    case Nil{}: None{}
    case Con{k, Con{v, rest}}:
      Bool.pick(Maybe<&2, U32>, U32.is_eq(bits_of(k), key), Some{index}, map_find(rest, key, U32.add(index, 1)))
    case Con{k, rest}: None{}

def drop_pairs(xs: +List<M.Slot>, n: Nat) -> +List<M.Slot>:
  match xs n:
    case rest 0n: rest
    case Nil{} _: Nil{}
    case Con{k, Con{v, rest}} 1n+p: drop_pairs(rest, p)
    case Con{k, rest} 1n+p: Nil{}

def replace_pair(xs: +List<M.Slot>, n: Nat, key: M.Slot, value: M.Slot) -> +List<M.Slot>:
  match xs n:
    case Nil{} _: [key, value]
    case Con{k, Con{v, rest}} 0n: Con{key, Con{value, rest}}
    case Con{k, Con{v, rest}} 1n+p: Con{k, Con{v, replace_pair(rest, p, key, value)}}
    case Con{k, rest} _: Con{key, Con{value, rest}}

def remove_pair(xs: +List<M.Slot>, n: Nat) -> +List<M.Slot>:
  match xs n:
    case Nil{} _: Nil{}
    case Con{k, Con{v, rest}} 0n: rest
    case Con{k, Con{v, rest}} 1n+p: Con{k, Con{v, remove_pair(rest, p)}}
    case Con{k, rest} _: rest

def map_remove_at(+vm: M.VM, +map: U32, +index: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- list_entry_of(vm, map)
    updated : M.VM = put_map(vm, map, remove_pair(map_pairs(entry), U32.to_nat(index)), U32.sub(list_size_of(entry), 1), U32.add(list_mod(entry_fields(entry)), 1))
    result : O.Outcome <- returned(updated, Some{value})
    return result

# put on an equal existing key keeps the original key, replaces the value, and
# returns the previous value (modCount is unchanged).
def map_put_existing(+vm: M.VM, +map: U32, +index: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- list_entry_of(vm, map)
    +pairs : +List<M.Slot> = map_pairs(entry)
    existing : M.Slot <- S.require(M.Slot, M.nth(M.Slot, pairs, U32.mul(index, 2)), "InvalidState: map index")
    old : M.Slot <- S.require(M.Slot, M.nth(M.Slot, pairs, U32.add(U32.mul(index, 2), 1)), "InvalidState: map index")
    updated : M.VM = put_map(vm, map, replace_pair(pairs, U32.to_nat(index), existing, value), list_size_of(entry), list_mod(entry_fields(entry)))
    result : O.Outcome <- returned(updated, Some{old})
    return result

# op: 0 get, 2 containsKey, 3 remove, 4 put (1 is unused and behaves like get).
def map_hit(+vm: M.VM, +map: U32, +key: U32, +index: U32, +op: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match op:
    case 0: returned(vm, Some{value})
    case 1: returned(vm, Some{value})
    case 2: bool_out(vm, True{})
    case 3: map_remove_at(vm, map, index, value)
    case 4: map_put_existing(vm, map, index, value)
    case _: returned(vm, Some{value})

@unsafe def map_lookup_dropped(dropped: +List<M.Slot>, +vm: M.VM, +map: U32, +key: U32, +index: U32, +op: U32) -> Result<&2, &2, String, O.Outcome>:
  match dropped:
    case Nil{}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(op, 2), bool_out(vm, False{}), ref_out(vm, 0))
    case Con{k, Con{+v, rest}}:
      +found = bits_of(k)
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(key, found), map_hit(vm, map, key, index, op, v),
        Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(key, 0) || U32.is_eq(found, 0), map_lookup_dropped(rest, vm, map, key, U32.add(index, 1), op),
          call_virtual(push_cont(vm, M.NeedEq{map, key, 0, index, op, v}), virtual_on(vm, key, "equals", "(Ljava/lang/Object;)Z"), [M.Slot{3, key}, M.Slot{3, found}])))
    case _:
      ref_out(vm, 0)

def map_lookup(+vm: M.VM, +map: U32, +key: U32, +index: U32, +op: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- list_entry_of(vm, map)
    result : O.Outcome <- map_lookup_dropped(drop_pairs(map_pairs(entry), U32.to_nat(index)), vm, map, key, index, op)
    return result

def map_get(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +key : M.Slot <- slot1(args)
    result : O.Outcome <- map_lookup(vm, bits_of(receiver), bits_of(key), 0, 0)
    return result

def map_put_new(+vm: M.VM, +map: U32, +key: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- list_entry_of(vm, map)
    updated : M.VM = put_map(vm, map, M.append(M.Slot, map_pairs(entry), [M.Slot{3, key}, value]), U32.add(list_size_of(entry), 1), U32.add(list_mod(entry_fields(entry)), 1))
    result : O.Outcome <- ref_out(updated, 0)
    return result

def map_put_replace(+vm: M.VM, +map: U32, +key: U32, value: M.Slot, +index: U32, old: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- list_entry_of(vm, map)
    updated : M.VM = put_map(vm, map, replace_pair(map_pairs(entry), U32.to_nat(index), M.Slot{3, key}, value), list_size_of(entry), list_mod(entry_fields(entry)))
    result : O.Outcome <- returned(updated, Some{old})
    return result

@unsafe def map_put_dropped(dropped: +List<M.Slot>, +vm: M.VM, +map: U32, +key: U32, +value: M.Slot, +index: U32) -> Result<&2, &2, String, O.Outcome>:
  match dropped:
    case Nil{}: map_put_new(vm, map, key, value)
    case Con{k, Con{+v, rest}}:
      +found = bits_of(k)
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(key, found), map_put_replace(vm, map, key, value, index, v),
        Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(key, 0) || U32.is_eq(found, 0), map_put_dropped(rest, vm, map, key, value, U32.add(index, 1)),
          call_virtual(push_cont(vm, M.NeedEq{map, key, 0, index, 4, value}), virtual_on(vm, key, "equals", "(Ljava/lang/Object;)Z"), [M.Slot{3, key}, M.Slot{3, found}])))
    case _: map_put_new(vm, map, key, value)

def map_put_lookup(+vm: M.VM, +map: U32, +key: U32, value: M.Slot, +index: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- list_entry_of(vm, map)
    result : O.Outcome <- map_put_dropped(drop_pairs(map_pairs(entry), U32.to_nat(index)), vm, map, key, value, index)
    return result

def map_put(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +key : M.Slot <- slot1(args)
    +value : M.Slot <- slot2(args)
    result : O.Outcome <- map_put_lookup(vm, bits_of(receiver), bits_of(key), value, 0)
    return result

def map_contains(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +key : M.Slot <- slot1(args)
    result : O.Outcome <- map_lookup(vm, bits_of(receiver), bits_of(key), 0, 2)
    return result

def map_remove(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +key : M.Slot <- slot1(args)
    result : O.Outcome <- map_lookup(vm, bits_of(receiver), bits_of(key), 0, 3)
    return result


def throwable_init(+vm: M.VM, +args: +List<M.Slot>, message: U32, cause: U32, flags: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    # Like fillInStackTrace in the Throwable constructor: the creating call stack.
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, M.Slot{3, message}}, M.Binding{1, M.Slot{3, cause}}, M.Binding{2, M.Slot{3, 0}}, M.Binding{3, M.Slot{1, flags}}], Tr.capture(vm), Nil{}}
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), updated))
    return result

def throwable_init0(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  throwable_init(vm, args, 0, 0, 0)

def throwable_init_s(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +message : M.Slot <- slot1(args)
    result : O.Outcome <- throwable_init(vm, args, bits_of(message), 0, 0)
    return result

def throwable_init_t_dispatch(+vm: M.VM, receiver: U32, +cause: U32) -> Result<&2, &2, String, O.Outcome>:
  match cause:
    case 0: throwable_init(vm, [M.Slot{3, receiver}, M.Slot{3, 0}], 0, 0, 0)
    case +cause_ref: call_virtual(push_cont(vm, M.NeedThrowableMessage{receiver, cause_ref}), virtual_on(vm, cause_ref, "toString", "()Ljava/lang/String;"), [M.Slot{3, cause_ref}])

def throwable_init_t(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +cause : M.Slot <- slot1(args)
    result : O.Outcome <- throwable_init_t_dispatch(vm, bits_of(receiver), bits_of(cause))
    return result

def assertion_null_alloc(+receiver: U32, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, message}}: throwable_init(updated, [M.Slot{3, receiver}], message, 0, 0)

@unsafe def assertion_detail_ref(+vm: M.VM, +receiver: U32, +detail: U32) -> Result<&2, &2, String, O.Outcome>:
  match detail:
    case 0: assertion_null_alloc(receiver, H.allocate(vm, H.string_entry(class_id(vm, "java/lang/String"), units_from_string("null"))))
    case _:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), detail)
        result : O.Outcome <- assertion_detail(vm, receiver, detail, entry)
        return result

def assertion_object(throwable: Bool, +vm: M.VM, +receiver: U32, +detail: U32) -> Result<&2, &2, String, O.Outcome>:
  match throwable:
    case True{}: throwable_init_t_dispatch(vm, receiver, detail)
    case False{}: call_virtual(push_cont(vm, M.NeedThrowableMessage{receiver, 0}), virtual_on(vm, detail, "toString", "()Ljava/lang/String;"), [M.Slot{3, detail}])

def assertion_detail_kind(string: Bool, +vm: M.VM, +receiver: U32, +detail: U32, class: U32) -> Result<&2, &2, String, O.Outcome>:
  match string:
    case True{}: throwable_init(vm, [M.Slot{3, receiver}], detail, 0, 0)
    case False{}: assertion_object(H.hierarchy(S.classes(vm), class, class_id(vm, "java/lang/Throwable")), vm, receiver, detail)

def assertion_detail(+vm: M.VM, +receiver: U32, +detail: U32, +entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  assertion_detail_kind(U32.is_eq(entry_kind(entry), 3), vm, receiver, detail, H.entry_class(entry))

# AssertionError(Object): the message is String.valueOf(detail), and a
# Throwable detail also becomes the cause.
def assertion_error_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +detail : M.Slot <- slot1(args)
    result : O.Outcome <- assertion_detail_ref(vm, bits_of(receiver), bits_of(detail))
    return result

def throwable_init_st(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +message : M.Slot <- slot1(args)
    +cause : M.Slot <- slot2(args)
    result : O.Outcome <- throwable_init(vm, args, bits_of(message), bits_of(cause), 1)
    return result

def throwable_get_message(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, field_bits(entry_fields(entry), 0))
    return result

def throwable_get_cause(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, field_bits(entry_fields(entry), 1))
    return result

def throwable_init_cause(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +cause : M.Slot <- slot1(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(cause), bits_of(receiver)), iae())
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    ready : Unit <- S.check(U32.is_eq(U32.and(field_bits(entry_fields(entry), 3), 1), 0), ise())
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, M.Slot{3, field_bits(entry_fields(entry), 0)}}, M.Binding{1, cause}, M.Binding{2, M.Slot{3, field_bits(entry_fields(entry), 2)}}, M.Binding{3, M.Slot{1, U32.or(field_bits(entry_fields(entry), 3), 1)}}], Nil{}, Nil{}}
    result : O.Outcome <- ref_out(H.put(vm, bits_of(receiver), updated), bits_of(receiver))
    return result

def throwable_put_fields(+vm: M.VM, +receiver: U32, +entry: M.HeapEntry, fields: +List<M.Binding>) -> M.VM:
  M.HeapEntry{class, kind, element, old, values, chars} = entry
  H.put(vm, receiver, M.HeapEntry{class, kind, element, fields, values, chars})

def throwable_add_existing(+vm: M.VM, +array_ref: U32, +other: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +array : M.HeapEntry <- H.get(S.heap(vm), array_ref)
    grown : M.HeapEntry = H.reference_array_entry(H.entry_class(array), entry_element(array), M.append(M.Slot, entry_values(array), [M.Slot{3, other}]))
    result : O.Outcome <- void_out(H.put(vm, array_ref, grown))
    return result

def throwable_store_suppressed(+vm: M.VM, +receiver: U32, +array_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +latest : M.HeapEntry <- H.get(S.heap(vm), receiver)
    result : O.Outcome <- void_out(throwable_put_fields(vm, receiver, latest, H.binding_set(entry_fields(latest), 2, M.Slot{3, array_ref})))
    return result

def throwable_add_new(+vm: M.VM, +receiver: U32, +other: U32) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/Throwable;"), class_id(vm, "java/lang/Throwable"), [M.Slot{3, other}])), vm2 => reference => throwable_store_suppressed(vm2, receiver, reference))

def throwable_add_list(+vm: M.VM, +receiver: U32, +other: U32, +list: U32) -> Result<&2, &2, String, O.Outcome>:
  match list:
    case 0: throwable_add_new(vm, receiver, other)
    case array_ref: throwable_add_existing(vm, array_ref, other)

def throwable_add_suppressed(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +other : M.Slot <- slot1(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(other), 0), npe())
    self : Unit <- S.check(U32.is_ne(bits_of(other), bits_of(receiver)), iae())
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- throwable_add_list(vm, bits_of(receiver), bits_of(other), field_bits(entry_fields(entry), 2))
    return result

def throwable_copy_suppressed(+vm: M.VM, +array_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +array : M.HeapEntry <- H.get(S.heap(vm), array_ref)
    result : O.Outcome <- alloc_result(H.allocate(vm, H.reference_array_entry(H.entry_class(array), entry_element(array), entry_values(array))), vm2 => reference => ref_out(vm2, reference))
    return result

def throwable_empty_suppressed(+vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/Throwable;"), class_id(vm, "java/lang/Throwable"), Nil{})), vm2 => reference => ref_out(vm2, reference))

def property_units(+values: +List<M.Slot>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{slot, rest}: Con{M.slot_bits(slot), property_units(rest)}


def property_chars(units: +List<U32>) -> +List<Char>:
  match units:
    case Nil{}: Nil{}
    case Con{unit, rest}: Con{Chr{unit}, property_chars(rest)}

def property_hex_digit(+unit: U32) -> U32:
  Bool.pick(U32, U32.is_ge(unit, 48) && U32.is_le(unit, 57), U32.sub(unit, 48),
    Bool.pick(U32, U32.is_ge(unit, 65) && U32.is_le(unit, 70), U32.sub(unit, 55),
      U32.sub(unit, 87)))
def property_hex_ok(unit: U32) -> Bool:
  +unit_ref : U32 = unit
  (U32.is_ge(unit_ref, 48) && U32.is_le(unit_ref, 57)) || (U32.is_ge(unit_ref, 65) && U32.is_le(unit_ref, 70)) || (U32.is_ge(unit_ref, 97) && U32.is_le(unit_ref, 102))

def property_valid_unicode(units: +List<U32>) -> Bool:
  match units:
    case Nil{}: True{}
    case Con{92, Con{117, Con{a, Con{b, Con{c, Con{d, rest}}}}}}:
      property_hex_ok(a) && property_hex_ok(b) && property_hex_ok(c) && property_hex_ok(d) && property_valid_unicode(rest)
    case Con{92, Con{117, rest}}: False{}
    case Con{unit, rest}: property_valid_unicode(rest)


def property_unicode(a: U32, b: U32, c: U32, d: U32) -> U32:
  U32.add(U32.add(U32.mul(property_hex_digit(a), 4096), U32.mul(property_hex_digit(b), 256)), U32.add(U32.mul(property_hex_digit(c), 16), property_hex_digit(d)))

def property_decode(+units: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match units:
    case Nil{}: M.reverse(U32, acc)
    case Con{92, Con{117, Con{a, Con{b, Con{c, Con{d, rest}}}}}}:
      property_decode(rest, Con{property_unicode(a, b, c, d), acc})
    case Con{92, Con{116, rest}}:
      property_decode(rest, Con{9, acc})
    case Con{92, Con{110, rest}}:
      property_decode(rest, Con{10, acc})
    case Con{92, Con{114, rest}}:
      property_decode(rest, Con{13, acc})
    case Con{92, Con{102, rest}}:
      property_decode(rest, Con{12, acc})
    case Con{92, Con{escaped, rest}}:
      property_decode(rest, Con{escaped, acc})
    case Con{unit, rest}:
      property_decode(rest, Con{unit, acc})

def property_pair_finish(+key: +List<U32>, +value: +List<U32>) -> PropPair:
  PropPair{String.from_list(property_chars(property_decode(M.reverse(U32, key), Nil{}))), String.from_list(property_chars(property_decode(M.reverse(U32, value), Nil{})))}

def property_pair_value(line: +List<U32>, +key: +List<U32>, +value: +List<U32>) -> PropPair:
  match line:
    case Nil{}: property_pair_finish(key, value)
    case Con{head, tail}: property_pair_value(tail, key, Con{head, value})

def property_value_start(line: +List<U32>, +key: +List<U32>, +value: +List<U32>) -> PropPair:
  match line:
    case Con{32, tail}: property_value_start(tail, key, value)
    case Con{9, tail}: property_value_start(tail, key, value)
    case _: property_pair_value(line, key, value)

def property_pair_go(line: +List<U32>, +key: +List<U32>, +value: +List<U32>, escaped: Bool) -> PropPair:
  match line escaped:
    case Nil{} _:
      property_pair_finish(key, value)
    case Con{unit, tail} True{}:
      property_pair_go(tail, Con{unit, key}, value, False{})
    case Con{92, tail} False{}:
      property_pair_go(tail, Con{92, key}, value, True{})
    case Con{61, tail} False{}:
      property_value_start(tail, key, value)
    case Con{58, tail} False{}:
      property_value_start(tail, key, value)
    case Con{32, tail} False{}:
      property_value_start(tail, key, value)
    case Con{9, tail} False{}:
      property_value_start(tail, key, value)
    case Con{unit, tail} False{}:
      property_pair_go(tail, Con{unit, key}, value, False{})

def property_trim_start(line: +List<U32>) -> +List<U32>:
  match line:
    case Con{32, tail}: property_trim_start(tail)
    case Con{9, tail}: property_trim_start(tail)
    case _: line

def property_pair(+line: +List<U32>) -> PropPair:
  property_pair_go(property_trim_start(line), Nil{}, Nil{}, False{})

def property_line_ignored(line: +List<U32>) -> Bool:
  match line:
    case Nil{}: True{}
    case Con{32, tail}: property_line_ignored(tail)
    case Con{9, tail}: property_line_ignored(tail)
    case Con{35, tail}: True{}
    case Con{33, tail}: True{}
    case _: False{}

def property_parse_line(+line: +List<U32>, +pairs: +List<PropPair>) -> +List<PropPair>:
  Bool.pick(+List<PropPair>, property_line_ignored(line), pairs, Con{property_pair(line), pairs})

def property_continued_go(line: +List<U32>, odd: Bool) -> Bool:
  match line:
    case Con{92, rest}: property_continued_go(rest, Bool.not(odd))
    case _: odd

def property_continued(line: +List<U32>) -> Bool:
  property_continued_go(line, False{})

def property_drop_continuation(line: +List<U32>) -> +List<U32>:
  match line:
    case Con{92, rest}: rest
    case _: line

@unsafe def property_parse(mode: Nat, +units: +List<U32>, +line: +List<U32>, +pairs: +List<PropPair>) -> +List<PropPair>:
  match mode:
    case 0n:
      match units:
        case Nil{}: property_parse_line(M.reverse(U32, line), pairs)
        case Con{unit, rest}:
          match unit:
            case 10: property_parse(1n, rest, line, pairs)
            case 13: property_parse(0n, rest, line, pairs)
            case _: property_parse(0n, rest, Con{unit, line}, pairs)
    case 1n:
      Bool.pick(+List<PropPair>, property_continued(line), property_parse(2n, units, property_drop_continuation(line), pairs), property_parse(0n, units, Nil{}, property_parse_line(M.reverse(U32, line), pairs)))
    case 2n+p:
      match units:
        case Nil{}: property_parse(0n, Nil{}, line, pairs)
        case Con{32, rest}: property_parse(2n, rest, line, pairs)
        case Con{9, rest}: property_parse(2n, rest, line, pairs)
        case Con{unit, rest}: property_parse(0n, Con{unit, rest}, line, pairs)

def property_alloc_found(allocation: H.Allocation, cont: M.VM -> U32 -> Result<&2, &2, String, PropSlots>) -> Result<&2, &2, String, PropSlots>:
  match allocation:
    case H.Allocation{vm, reference}: cont(vm, reference)

def property_alloc_result(result: Result<&2, &2, String, H.Allocation>, cont: M.VM -> U32 -> Result<&2, &2, String, PropSlots>) -> Result<&2, &2, String, PropSlots>:
  match result:
    case Fail{error}: Fail{error}
    case Done{allocation}: property_alloc_found(allocation, cont)

@unsafe def property_slots(fuel: Nat, +vm: M.VM, +pairs: +List<PropPair>, +acc: +List<M.Slot>, count: U32, props: U32) -> Result<&2, &2, String, PropSlots>:
  match fuel pairs:
    case 0n _:
      Done{PropSlots{vm, acc, count, props}}
    case 1n+p Nil{}:
      Done{PropSlots{vm, acc, count, props}}
    case 1n+p Con{PropPair{+key, +value}, rest}:
      property_alloc_result(H.allocate(vm, H.string_entry(class_id(vm, "java/lang/String"), units_from_string(key))), +vm2 => key_ref => property_alloc_result(H.allocate(vm2, H.string_entry(class_id(vm2, "java/lang/String"), units_from_string(value))), +vm3 => value_ref => property_slots(p, vm3, rest, Con{M.Slot{3, key_ref}, Con{M.Slot{3, value_ref}, acc}}, U32.add(count, 1), props)))

def properties_store_class(+vm: M.VM, props: U32, +slots: +List<M.Slot>, count: U32) -> Result<&2, &2, String, O.Outcome>:
  class : U32 = class_id(vm, "java/util/Properties")
  void_out(H.put(vm, props, H.map_entry(class, slots, count, 0)))

def properties_store(value: PropSlots) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case PropSlots{vm, +slots, count, props}:
      properties_store_class(vm, props, slots, count)

def throwable_get_list(+vm: M.VM, +list: U32) -> Result<&2, &2, String, O.Outcome>:
  match list:
    case 0: throwable_empty_suppressed(vm)
    case array_ref: throwable_copy_suppressed(vm, array_ref)

def throwable_get_suppressed(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- throwable_get_list(vm, field_bits(entry_fields(entry), 2))
    return result

def throwable_to_string_msg(+vm: M.VM, name: String, message: U32) -> Result<&2, &2, String, O.Outcome>:
  match message:
    case 0: intern_or_alloc(vm, units_from_string(name))
    case _:
      do Result<&2, &2, String, O.Outcome>:
        chars : +List<U32> <- string_chars(vm, message)
        result : O.Outcome <- intern_or_alloc(vm, concat_chars(units_from_string(name ++ ": "), chars))
        return result

def throwable_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +name : String = slash_to_dot(class_name_text(vm, H.entry_class(entry)))
    +msg : U32 = field_bits(entry_fields(entry), 0)
    result : O.Outcome <- throwable_to_string_msg(vm, name, msg)
    return result

def bais_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +bytes : M.Slot <- slot1(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(bytes), 0), npe())
    array : M.HeapEntry <- H.get(S.heap(vm), bits_of(bytes))
    recv : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(recv), 4, 0, [M.Binding{0, M.Slot{1, 0}}], entry_values(array), Nil{}}
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), updated))
    return result

def baos_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 4, 0, [M.Binding{0, M.Slot{1, 0}}], Nil{}, Nil{}}
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), updated))
    return result

def baos_to_array(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- alloc_result(H.allocate(vm, H.primitive_array_entry(class_id(vm, "[B"), 8, entry_values(entry))), vm2 => reference => ref_out(vm2, reference))
    return result

def baos_size(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- int_out(vm, M.length(M.Slot, entry_values(entry)))
    return result

def baos_reset(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 4, 0, entry_fields(entry), Nil{}, Nil{}}
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), updated))
    return result

# String.valueOf semantics for printing: null prints "null".
def printed_reference(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, String>:
  match reference:
    case 0: Done{"null"}
    case _:
      do Result<&2, &2, String, String>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 3), "java/lang/ClassCastException")
        return utf16(entry_chars(entry), 0)

# PrintStream.println(Object) prints String.valueOf(value), calling the
# receiver's virtual toString() for every non-null, non-String object.
def emit_text(+vm: M.VM, newline: Bool, +text: String) -> M.VM:
  Bool.pick(M.VM, newline, S.emit(vm, text), S.emit_raw(vm, text))

# PrintStream.print/println(Object): String.valueOf(value), calling the
# receiver's virtual toString() for every non-null, non-String object.
# System.err's PrintStream (heap reference 15, see class_loader.bootstrap_heap).
def err_stream() -> U32:
  15

def emit_text_err(err: Bool, +vm: M.VM, +newline: Bool, +text: String) -> M.VM:
  match err:
    case True{}: S.emit_error(vm, Bool.pick(String, newline, text ++ "\n", text))
    case False{}: emit_text(vm, newline, text)

# NeedToString ops: 2/3 println/print to System.out, 4/5 to System.err.
def print_op(+newline: Bool, +err: Bool) -> U32:
  Bool.pick(U32, err, Bool.pick(U32, newline, 4, 5), Bool.pick(U32, newline, 2, 3))

def print_object_to(+vm: M.VM, +reference: U32, +newline: Bool, +err: Bool) -> Result<&2, &2, String, O.Outcome>:
  match reference:
    case 0: void_out(emit_text_err(err, vm, newline, "null"))
    case +value:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), value)
        result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(entry_kind(entry), 3),
          void_out(emit_text_err(err, vm, newline, utf16(entry_chars(entry), 0))),
          call_virtual(push_cont(vm, M.NeedToString{print_op(newline, err), 0}), virtual_on(vm, value, "toString", "()Ljava/lang/String;"), [M.Slot{3, value}]))
        return result

def print_object_ref(+vm: M.VM, +reference: U32, +newline: Bool) -> Result<&2, &2, String, O.Outcome>:
  print_object_to(vm, reference, newline, False{})

def println_object_ref(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, O.Outcome>:
  print_object_ref(vm, reference, True{})

def continue_to_string(+vm: M.VM, +op: U32, +extra: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match op:
    case 1:
      do Result<&2, &2, String, O.Outcome>:
        chars : +List<U32> <- string_chars(vm, bits_of(value))
        result : O.Outcome <- builder_append_chars(vm, extra, chars)
        return result
    case 2:
      do Result<&2, &2, String, O.Outcome>:
        text : String <- printed_reference(vm, bits_of(value))
        result : O.Outcome <- void_out(S.emit(vm, text))
        return result
    case 3:
      do Result<&2, &2, String, O.Outcome>:
        text : String <- printed_reference(vm, bits_of(value))
        result : O.Outcome <- void_out(S.emit_raw(vm, text))
        return result
    case 4:
      do Result<&2, &2, String, O.Outcome>:
        text : String <- printed_reference(vm, bits_of(value))
        result : O.Outcome <- void_out(S.emit_error(vm, text ++ "\n"))
        return result
    case 5:
      do Result<&2, &2, String, O.Outcome>:
        text : String <- printed_reference(vm, bits_of(value))
        result : O.Outcome <- void_out(S.emit_error(vm, text))
        return result
    case _:
      returned(vm, Some{value})


def proxy_wrapper_name(+name: String) -> String:
  match name:
    case "boolean": "java/lang/Boolean"
    case "byte": "java/lang/Byte"
    case "short": "java/lang/Short"
    case "char": "java/lang/Character"
    case "int": "java/lang/Integer"
    case "float": "java/lang/Float"
    case "long": "java/lang/Long"
    case "double": "java/lang/Double"
    case _: ""

def proxy_return_primitive(+vm: M.VM, +name: String, value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  match value:
    case M.Slot{+tag, +reference}:
      do Result<&2, &2, String, M.Slot>:
        checked_tag : Unit <- S.check(U32.is_eq(tag, 3), "java/lang/NullPointerException")
        checked_null : Unit <- S.check(U32.is_ne(reference, 0), "java/lang/NullPointerException")
        +wrapper : String = proxy_wrapper_name(name)
        +wrapper_id : U32 = class_id(vm, wrapper)
        wrapper_checked : Unit <- S.check(U32.is_ne(wrapper_id, 4294967295), "java/lang/ClassCastException")
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        checked_type : Unit <- S.check(U32.is_eq(H.entry_class(entry), wrapper_id), "java/lang/ClassCastException")
        +primitive : M.Slot <- wrapper_value_slot(vm, entry, reflect_wrapper_tag(wrapper))
        checked_value : Unit <- S.check(U32.is_eq(M.slot_tag(primitive), wrapper_value_slot_tag(reflect_wrapper_tag(wrapper))), "java/lang/ClassCastException")
        return primitive
    case _: Fail{"java/lang/ClassCastException"}

def proxy_return_reference_slot(+vm: M.VM, +name: String, value: M.Slot, tag: U32, reference: U32) -> Result<&2, &2, String, M.Slot>:
  match reference:
    case 0:
      do Result<&2, &2, String, M.Slot>:
        checked_tag : Unit <- S.check(U32.is_eq(tag, 3), "java/lang/ClassCastException")
        return value
    case _:
      do Result<&2, &2, String, M.Slot>:
        checked_tag : Unit <- S.check(U32.is_eq(tag, 3), "java/lang/ClassCastException")
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        +expected : U32 = class_id(vm, name)
        checked_expected : Unit <- S.check(U32.is_ne(expected, 4294967295), "java/lang/ClassCastException")
        checked_type : Unit <- S.check(H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), expected), "java/lang/ClassCastException")
        return value

def proxy_return_reference(+vm: M.VM, +name: String, value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  match value:
    case M.Slot{+tag, +reference}: proxy_return_reference_slot(vm, name, value, tag, reference)
    case _: Fail{"java/lang/ClassCastException"}

def proxy_return_value(+vm: M.VM, +descriptor: String, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  +name : String = method_return_name(descriptor)
  Bool.pick(Result<&2, &2, String, M.Slot>, String.eq(name, "void"), Done{value}, Bool.pick(Result<&2, &2, String, M.Slot>, primitive_name(name), proxy_return_primitive(vm, name, value), proxy_return_reference(vm, name, value)))

def reflect_box_return(+vm: M.VM, descriptor: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  reflect_box_value(vm, method_return_name(descriptor), value)


def continue_throwable_message(+vm: M.VM, +receiver: U32, +cause: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), receiver)
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, M.Slot{3, bits_of(value)}}, M.Binding{1, M.Slot{3, cause}}, M.Binding{2, M.Slot{3, 0}}, M.Binding{3, M.Slot{1, Bool.to_u32(U32.is_ne(cause, 0))}}], Nil{}, Nil{}}
    result : O.Outcome <- void_out(H.put(vm, receiver, updated))
    return result

@unsafe def continue_java(+vm: M.VM, cont: M.Cont, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match cont:
    case M.NeedThrowableMessage{+receiver, +cause}:
      continue_throwable_message(vm, receiver, cause, value)
    case M.NeedToString{op, extra}:
      continue_to_string(vm, op, extra, value)
    case M.NeedEquals{op, left, right}:
      bool_out(vm, U32.is_ne(bits_of(value), 0))
    case M.NeedListEq{list, query, index, op}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_ne(bits_of(value), 0), bool_out(vm, True{}), list_contains_at(vm, list, query, U32.add(index, 1)))
    case M.NeedEq{+map, +key, hash, +index, +op, +extra}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_ne(bits_of(value), 0), map_hit(vm, map, key, index, op, extra),
        Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(op, 4), map_put_lookup(vm, map, key, extra, U32.add(index, 1)), map_lookup(vm, map, key, U32.add(index, 1), op)))
    case M.NeedHash{map, key, op, extra}:
      map_lookup(vm, map, key, 0, op)
    case M.CallBoundary{depth, effect, descriptor}: returned(vm, Some{value})
    case M.NeedClassMirror{target}: class_for_name_init(vm, target)
    case M.NeedTextJoin{+acc, +items}: continue_text_join(vm, acc, items, value)
    case _: Fail{"InvalidState: runtime continuation passed to Java intrinsic"}

def static_member_owner(flags: U32, owner: U32) -> U32:
  Bool.pick(U32, U32.is_ne(U32.and(flags, 8), 0), owner, 4294967295)

# The class an intrinsic must see initialized before it runs (JVMS 5.5):
# reflective static field access and static method invocation initialize the
# declaring class, Constructor.newInstance the constructed class, and the
# annotation enum lookups their enum types. 4294967295 means none.
def initialization_target(+vm: M.VM, +values: +List<M.Slot>, kind: U32) -> Result<&2, &2, String, U32>:
  match kind:
    case 179:
      do Result<&2, &2, String, U32>:
        +field : M.LoadedField <- reflect_field_member(vm, values)
        return static_member_owner(M.loaded_field_flags(field), M.loaded_field_owner(field))
    case 180:
      do Result<&2, &2, String, U32>:
        +field : M.LoadedField <- reflect_field_member(vm, values)
        return static_member_owner(M.loaded_field_flags(field), M.loaded_field_owner(field))
    case 181:
      do Result<&2, &2, String, U32>:
        +field : M.LoadedField <- reflect_field_member(vm, values)
        return static_member_owner(M.loaded_field_flags(field), M.loaded_field_owner(field))
    case 182:
      do Result<&2, &2, String, U32>:
        +field : M.LoadedField <- reflect_field_member(vm, values)
        return static_member_owner(M.loaded_field_flags(field), M.loaded_field_owner(field))
    case 183:
      do Result<&2, &2, String, U32>:
        +member : M.LoadedMethod <- reflect_method_member(vm, values)
        return static_member_owner(M.loaded_method_flags(member), M.loaded_method_owner(member))
    case 184:
      do Result<&2, &2, String, U32>:
        member : M.LoadedMethod <- reflect_constructor_member(vm, values)
        return M.loaded_method_owner(member)
    case 558: class_target(vm, values)
    case 310: Done{class_id(vm, "java/lang/annotation/RetentionPolicy")}
    case 311: Done{class_id(vm, "java/lang/annotation/RetentionPolicy")}
    case 312: Done{class_id(vm, "java/lang/annotation/ElementType")}
    case 313: Done{class_id(vm, "java/lang/annotation/ElementType")}
    case _: Done{4294967295}

@unsafe def property_utf8_decode(mode: U32, pending: U32, +bytes: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match mode bytes:
    case 0 Nil{}: M.reverse(U32, acc)
    case 0 Con{+unit, rest}:
      Bool.pick(+List<U32>, U32.is_le(unit, 127), property_utf8_decode(0, 0, rest, Con{unit, acc}),
        Bool.pick(+List<U32>, U32.is_le(unit, 223), property_utf8_decode(1, unit, rest, acc),
          Bool.pick(+List<U32>, U32.is_le(unit, 239), property_utf8_decode(2, unit, rest, acc), property_utf8_decode(3, unit, rest, acc))))
    case 1 Con{continuation, rest}:
      property_utf8_decode(0, 0, rest, Con{U32.or(U32.shln(U32.and(pending, 31), 6n), U32.and(continuation, 63)), acc})
    case 2 Con{first, Con{second, rest}}:
      property_utf8_decode(0, 0, rest, Con{U32.or(U32.shln(U32.and(pending, 15), 12n), U32.or(U32.shln(U32.and(first, 63), 6n), U32.and(second, 63))), acc})
    case 3 Con{first, Con{second, Con{third, rest}}}:
      property_utf8_decode(0, 0, rest, Con{U32.or(U32.shln(U32.and(pending, 7), 18n), U32.or(U32.shln(U32.and(first, 63), 12n), U32.or(U32.shln(U32.and(second, 63), 6n), U32.and(third, 63)))), acc})
    case _ _: property_utf8_decode(0, 0, Nil{}, Con{65533, acc})

def properties_reader_units(+vm: M.VM, +reader: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    +reader_entry : M.HeapEntry <- H.get(S.heap(vm), reader)
    +stream : U32 = field_bits(entry_fields(reader_entry), 0)
    +stream_entry : M.HeapEntry <- H.get(S.heap(vm), stream)
    checked : Unit <- S.check(U32.is_eq(entry_kind(stream_entry), 4), "java/io/IOException")
    units : +List<U32> = property_utf8_decode(0, 0, property_units(entry_values(stream_entry)), Nil{})
    return units

def properties_store_units(+vm: M.VM, props: U32, +units: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    pairs : +List<PropPair> = property_parse(0n, units, Nil{}, Nil{})
    slots : PropSlots <- property_slots(100000n, vm, pairs, Nil{}, 0, props)
    result : O.Outcome <- properties_store(slots)
    return result

def properties_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), H.map_entry(class_id(vm, "java/util/Properties"), Nil{}, 0, 0)))
    return result


def properties_load(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    input : M.Slot <- slot1(args)
    +stream : M.HeapEntry <- H.get(S.heap(vm), bits_of(input))
    +units : +List<U32> = property_units(entry_values(stream))
    +valid_units : +List<U32> = units
    valid : Bool = property_valid_unicode(valid_units)
    result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, valid, properties_store_units(vm, bits_of(receiver), units), throw_name(vm, "java/lang/IllegalArgumentException"))
    return result

def properties_load_reader(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    reader : M.Slot <- slot1(args)
    +units : +List<U32> <- properties_reader_units(vm, bits_of(reader))
    result : O.Outcome <- properties_store_units(vm, bits_of(receiver), units)
    return result


def property_lookup_last_slot(+vm: M.VM, current: M.Slot, found: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case M.Slot{tag, 0}: returned(vm, Some{current})
    case M.Slot{tag, bits}: returned(vm, Some{M.Slot{tag, bits}})
    case M.Wide{tag, high, low}: Fail{"java/lang/ClassCastException"}
    case M.Unusable{}: Fail{"java/lang/ClassCastException"}

def property_lookup_last_result(+vm: M.VM, current: M.Slot, result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{vm, Some{found}}}: property_lookup_last_slot(vm, current, found)
    case Done{O.Returned{vm, None{}}}: returned(vm, Some{current})
    case Done{outcome}: Done{outcome}

def property_lookup_choose(+vm: M.VM, current: M.Slot, same: Bool, rest: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, O.Outcome>:
  match same:
    case True{}: property_lookup_last_result(vm, current, rest)
    case False{}: rest

def property_lookup_pairs(+vm: M.VM, +pairs: +List<M.Slot>, +key: U32) -> Result<&2, &2, String, O.Outcome>:
  match pairs:
    case Nil{}: ref_out(vm, 0)
    case Con{key_slot, Con{+value, rest}}:
      do Result<&2, &2, String, O.Outcome>:
        stored : String <- string_text(vm, bits_of(key_slot))
        wanted : String <- string_text(vm, key)
        result : O.Outcome <- property_lookup_choose(vm, value, String.eq(stored, wanted), property_lookup_pairs(vm, rest, key))
        return result
    case _: ref_out(vm, 0)

def property_lookup(+vm: M.VM, +map: U32, +key: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- list_entry_of(vm, map)
    result : O.Outcome <- property_lookup_pairs(vm, map_pairs(entry), key)
    return result

def property_default_outcome(+vm: M.VM, default: M.Slot, result: O.Outcome) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case O.Returned{vm, Some{found}}: property_lookup_last_slot(vm, default, found)
    case O.Returned{vm, None{}}: returned(vm, Some{default})
    case _: Done{result}

def property_lookup_default(+vm: M.VM, +map: U32, +key: U32, +default: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    result : O.Outcome <- property_lookup(vm, map, key)
    fallback : O.Outcome <- property_default_outcome(vm, default, result)
    return fallback
def properties_get(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    key : M.Slot <- slot1(args)
    result : O.Outcome <- property_lookup(vm, bits_of(receiver), bits_of(key))
    return result


def properties_get_default(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    key : M.Slot <- slot1(args)
    default : M.Slot <- slot2(args)
    result : O.Outcome <- property_lookup_default(vm, bits_of(receiver), bits_of(key), default)
    return result

def properties_set(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  map_put(vm, args)
def boolean_value_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot0(args)
    result : O.Outcome <- boolean_singleton_out(vm, value)
    return result

def boolean_value(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- bool_out(vm, U32.is_ne(field_bits(entry_fields(entry), 0), 0))
    return result

def boolean_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(Bool.pick(String, U32.is_eq(field_bits(entry_fields(entry), 0), 0), "false", "true")))
    return result

def enum_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    name : M.Slot <- slot1(args)
    ordinal : M.Slot <- slot2(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, name}, M.Binding{1, ordinal}], Nil{}, Nil{}}))
    return result

def enum_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- ref_out(vm, field_bits(entry_fields(entry), 0))
    return result

def enum_ordinal(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- int_out(vm, field_bits(entry_fields(entry), 1))
    return result

def standard_enum_value_result(value: AR.Value) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case AR.Value{vm, M.Slot{99, error}}: throw_name(vm, "java/lang/IllegalArgumentException")
    case other: AR.outcome(other)
def standard_enum_value_of(+vm: M.VM, args: +List<M.Slot>, owner: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +name : M.Slot <- slot0(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(name), 0), "java/lang/NullPointerException")
    value : AR.Value <- AR.enum_lookup(vm, owner, name)
    result : O.Outcome <- standard_enum_value_result(value)
    return result

def enum_value_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    enumType : M.Slot <- slot0(args)
    name : M.Slot <- slot1(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(enumType))
    result : O.Outcome <- standard_enum_value_of(vm, [name], entry_element(entry))
    return result

def standard_enum_clinit(+vm: M.VM, args: +List<M.Slot>, +owner: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    initialized : M.VM <- AR.initialize_enum(vm, AR.enum_fields(S.fields(vm), owner), owner, 0)
    result : O.Outcome <- void_out(initialized)
    return result

def standard_enum_values(vm: M.VM, args: +List<M.Slot>, owner: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : AR.Value <- AR.enum_values(vm, owner)
    result : O.Outcome <- AR.outcome(value)
    return result


def annotation_exception_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    first : M.Slot <- slot1(args)
    second : M.Slot <- slot2(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- void_out(H.put(vm, bits_of(receiver), H.object_entry(H.entry_class(entry), [M.Binding{0, M.Slot{3, 0}}, M.Binding{1, M.Slot{3, 0}}, M.Binding{4, first}, M.Binding{5, second}])))
    return result

def annotation_exception_field(+vm: M.VM, args: +List<M.Slot>, field: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    value : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), field), "InvalidState: annotation exception")
    result : O.Outcome <- returned(vm, Some{value})
    return result

def annotation_exception_first(vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  annotation_exception_field(vm, args, 4)

def annotation_exception_second(vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  annotation_exception_field(vm, args, 5)
def primitive_box(+vm: M.VM, +args: +List<M.Slot>, +name: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- slot0(args)
    result : O.Outcome <- alloc_result(H.allocate(vm, H.object_entry(class_id(vm, name), [M.Binding{0, value}])), vm2 => reference => ref_out(vm2, reference))
    return result

def primitive_unbox(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- int_out(vm, field_bits(entry_fields(entry), 0))
    return result

def primitive_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(V.int_show(field_bits(entry_fields(entry), 0))))
    return result

def byte_value_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  primitive_box(vm, args, "java/lang/Byte")
def short_value_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  primitive_box(vm, args, "java/lang/Short")
def character_value_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  primitive_box(vm, args, "java/lang/Character")
def float_value_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  primitive_box(vm, args, "java/lang/Float")
def float_unbox(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- returned(vm, Some{M.Slot{2, field_bits(entry_fields(entry), 0)}})
    return result

# ---- java.lang.reflect.Executable parameters and Parameter (JDK 8) ----
# A Parameter object keeps its executable in binding 0 and its index in binding 1.

def executable_kind(+constructor: Bool, +vm: M.VM, +executable: U32) -> Result<&2, &2, String, M.LoadedMethod>:
  match constructor:
    case True{}: reflect_constructor_member(vm, [M.Slot{3, executable}])
    case False{}: reflect_method_member(vm, [M.Slot{3, executable}])

def executable_is_constructor(+vm: M.VM, entry: M.HeapEntry) -> Bool:
  String.eq(class_name_text(vm, H.entry_class(entry)), "java/lang/reflect/Constructor")

def executable_method(+vm: M.VM, +executable: U32) -> Result<&2, &2, String, M.LoadedMethod>:
  do Result<&2, &2, String, M.LoadedMethod>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), executable)
    method : M.LoadedMethod <- executable_kind(executable_is_constructor(vm, entry), vm, executable)
    return method

def method_parameter_count(+method: M.LoadedMethod) -> U32:
  match method:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}: parameters

def method_parameter_records_found(found: Result<&2, &2, String, M.MethodMetadata>) -> +List<M.MethodParameter>:
  match found:
    case Fail{error}: Nil{}
    case Done{M.MethodMetadata{owner, method, metadata, signature, parameters, lines}}: parameters

def method_parameter_records(+vm: M.VM, +method: M.LoadedMethod) -> +List<M.MethodParameter>:
  method_parameter_records_found(method_metadata_value(vm, M.loaded_method_id(method)))

def parameter_name_valid(+name: String) -> Bool:
  match name:
    case SNil{}: True{}
    case SCon{Chr{46}, rest}: False{}
    case SCon{Chr{59}, rest}: False{}
    case SCon{Chr{91}, rest}: False{}
    case SCon{Chr{47}, rest}: False{}
    case SCon{unit, rest}: parameter_name_valid(rest)

def parameter_records_valid(+records: +List<M.MethodParameter>) -> Bool:
  match records:
    case Nil{}: True{}
    case Con{M.MethodParameter{name, flags}, rest}: parameter_name_valid(name) && parameter_records_valid(rest)

# Executable.getParameters validates MethodParameters the way the JDK does:
# a wrong entry count or a name with . ; [ / is MalformedParametersException.
def parameter_records_check(+records: +List<M.MethodParameter>, +count: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    +length : U32 = M.length(M.MethodParameter, records)
    sized : Unit <- S.check(U32.is_eq(length, 0) || U32.is_eq(length, count), "java/lang/reflect/MalformedParametersException: Wrong number of parameters in MethodParameters attribute")
    named : Unit <- S.check(parameter_records_valid(records), "java/lang/reflect/MalformedParametersException: Invalid parameter name")
    return Unit{}

@unsafe def parameter_objects_next(allocation: Result<&2, &2, String, H.Allocation>, fuel: Nat, +class: U32, +executable: U32, +index: U32, +acc: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}: parameter_objects(fuel, updated, class, executable, U32.add(index, 1), Con{reference, acc})

@unsafe def parameter_objects(fuel: Nat, +vm: M.VM, +class: U32, +executable: U32, +index: U32, +acc: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match fuel:
    case 0n: Done{ReflectRefs{vm, M.reverse(U32, acc)}}
    case 1n+p: parameter_objects_next(H.allocate(vm, H.object_entry(class, [M.Binding{0, M.Slot{3, executable}}, M.Binding{1, M.Slot{1, index}}])), p, class, executable, index, acc)

def reference_slots(+refs: +List<U32>) -> +List<M.Slot>:
  match refs:
    case Nil{}: Nil{}
    case Con{reference, rest}: Con{M.Slot{3, reference}, reference_slots(rest)}

def parameter_array_out(refs: ReflectRefs) -> Result<&2, &2, String, O.Outcome>:
  match refs:
    case ReflectRefs{+vm, refs}:
      alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/reflect/Parameter;"), class_id(vm, "java/lang/reflect/Parameter"), reference_slots(refs))), vm2 => reference => ref_out(vm2, reference))

def executable_parameters(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +executable : U32 = bits_of(receiver)
    +method : M.LoadedMethod <- executable_method(vm, executable)
    +count : U32 = method_parameter_count(method)
    checked : Unit <- parameter_records_check(method_parameter_records(vm, method), count)
    +ready : M.VM <- ensure_array_class(vm, "[Ljava/lang/reflect/Parameter;")
    refs : ReflectRefs <- parameter_objects(U32.to_nat(count), ready, class_id(ready, "java/lang/reflect/Parameter"), executable, 0, Nil{})
    result : O.Outcome <- parameter_array_out(refs)
    return result

def executable_parameter_count(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    method : M.LoadedMethod <- executable_method(vm, bits_of(receiver))
    result : O.Outcome <- int_out(vm, method_parameter_count(method))
    return result

type ParameterParts is Data:
  ParameterParts{executable: U32, index: U32}

def parameter_parts(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, ParameterParts>:
  do Result<&2, &2, String, ParameterParts>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    executable : M.Slot <- reflect_binding(entry, 0)
    index : M.Slot <- reflect_binding(entry, 1)
    return ParameterParts{bits_of(executable), bits_of(index)}

def parameter_record_name(found: Maybe<&2, M.MethodParameter>) -> String:
  match found:
    case None{}: ""
    case Some{M.MethodParameter{name, flags}}: name

def parameter_record_flags(found: Maybe<&2, M.MethodParameter>) -> U32:
  match found:
    case None{}: 0
    case Some{M.MethodParameter{name, flags}}: flags

# Without a recorded name the JDK synthesizes argN.
def parameter_display_name(+recorded: String, +index: U32) -> String:
  Bool.pick(String, String.is_empty(recorded), "arg" ++ U32.show(index), recorded)

def parameter_name(+vm: M.VM, +method: M.LoadedMethod, +index: U32) -> String:
  parameter_display_name(parameter_record_name(M.nth(M.MethodParameter, method_parameter_records(vm, method), index)), index)

def parameter_flags(+vm: M.VM, +method: M.LoadedMethod, +index: U32) -> U32:
  parameter_record_flags(M.nth(M.MethodParameter, method_parameter_records(vm, method), index))

def parameter_element(+index: U32, result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{+vm, Some{array}}}:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(array))
        slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, entry_values(entry), index), "java/lang/ArrayIndexOutOfBoundsException")
        result : O.Outcome <- returned(vm, Some{slot})
        return result
    case Done{other}: Done{other}

def annotations_or_empty(found: Maybe<&2, +List<M.Annotation>>) -> +List<M.Annotation>:
  match found:
    case None{}: Nil{}
    case Some{values}: values

# Parameter annotations are aligned to the end of the parameter list, as the
# JDK does when javac omits entries for implicit leading parameters.
def parameter_annotation_list(+lists: +List<+List<M.Annotation>>, +index: U32, +count: U32) -> +List<M.Annotation>:
  +length : U32 = M.length(+List<M.Annotation>, lists)
  +offset : U32 = Bool.pick(U32, U32.is_lt(length, count), U32.sub(count, length), 0)
  Bool.pick(+List<M.Annotation>, U32.is_lt(index, offset), Nil{},
    annotations_or_empty(M.nth(+List<M.Annotation>, lists, U32.sub(index, offset))))

def parameter_scope(source: AnnotationMetadataRef, +index: U32, +count: U32) -> AnnotationMetadataRef:
  match source:
    case AnnotationMetadataRef{vm, pool, metadata}:
      AnnotationMetadataRef{vm, pool, M.AnnotationMetadata{0, Nil{}, parameter_annotation_list(metadata_parameters(metadata), index, count), Nil{}, Nil{}, None{}, Nil{}, Nil{}, Nil{}}}

def parameter_annotations(+vm: M.VM, +method: M.LoadedMethod, +index: U32) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    source : AnnotationMetadataRef <- method_annotation_source(vm, method)
    return parameter_scope(source, index, method_parameter_count(method))

def parameter_hash(+index: U32, result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Done{O.Returned{+vm, Some{hash}}}: int_out(vm, U32.xor(bits_of(hash), index))
    case other: other

def executable_hash(+constructor: Bool, +vm: M.VM, +executable: U32) -> Result<&2, &2, String, O.Outcome>:
  match constructor:
    case True{}: reflect_constructor_hash(vm, [M.Slot{3, executable}])
    case False{}: reflect_method_hash(vm, [M.Slot{3, executable}])

def parameter_member(entry: M.HeapEntry) -> U32:
  bits_of(reflect_binding_slot(H.binding_find(entry_fields(entry), 1)))

def parameter_owner(entry: M.HeapEntry) -> U32:
  bits_of(reflect_binding_slot(H.binding_find(entry_fields(entry), 0)))

# Parameter.equals: same executable (same member of the same reflection kind)
# and same index.
def executables_equal_entries(mine: Result<&2, &2, String, M.HeapEntry>, theirs: Result<&2, &2, String, M.HeapEntry>) -> Bool:
  match mine theirs:
    case Done{+a} Done{+b}:
      U32.is_eq(H.entry_class(a), H.entry_class(b)) && U32.is_eq(parameter_member(a), parameter_member(b)) && U32.is_eq(parameter_owner(a), parameter_owner(b))
    case _ _: False{}

def executables_equal(+vm: M.VM, +executable: U32, +other: U32) -> Bool:
  executables_equal_entries(H.get(S.heap(vm), executable), H.get(S.heap(vm), other))

def parameter_equal_entry(found: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM, +executable: U32, +index: U32) -> Bool:
  match found:
    case Fail{error}: False{}
    case Done{+entry}:
      U32.is_eq(H.entry_class(entry), class_id(vm, "java/lang/reflect/Parameter")) &&
        U32.is_eq(parameter_member(entry), index) &&
          executables_equal(vm, executable, parameter_owner(entry))

def parameter_equal(+vm: M.VM, +executable: U32, +index: U32, +other: U32) -> Bool:
  parameter_equal_entry(H.get(S.heap(vm), other), vm, executable, index)

type TextAt is Data:
  TextAt{vm: M.VM, text: String}

def outcome_text(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, TextAt>:
  match result:
    case Done{O.Returned{+vm, Some{reference}}}:
      do Result<&2, &2, String, TextAt>:
        text : String <- string_text(vm, bits_of(reference))
        return TextAt{vm, text}
    case Done{other}: Fail{"InvalidState: expected a String result"}
    case Fail{error}: Fail{error}

def outcome_reference(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, ReflectRefs>:
  match result:
    case Done{O.Returned{+vm, Some{reference}}}: Done{ReflectRefs{vm, [bits_of(reference)]}}
    case Done{other}: Fail{"InvalidState: expected a reference result"}
    case Fail{error}: Fail{error}

def first_ref(+refs: +List<U32>) -> U32:
  match refs:
    case Con{reference, rest}: reference
    case Nil{}: 0

def drop_two(text: String) -> String:
  match text:
    case SCon{a, SCon{b, rest}}: rest
    case _: text

# A varargs parameter prints its last "[]" as "...".
def varargs_type_name(+name: String) -> String:
  Bool.pick(String, String.ends_with(name, "[]"), String.reverse(drop_two(String.reverse(name))) ++ "...", name)

def modifier_prefix(+flags: U32) -> String:
  Bool.pick(String, U32.is_ne(U32.and(flags, 16), 0), "final", "") ++ Bool.pick(String, U32.is_ne(flags, 0), " ", "")

def parameter_text(+vm: M.VM, +method: M.LoadedMethod, +index: U32, +type_name: String) -> Result<&2, &2, String, O.Outcome>:
  +flags : U32 = parameter_flags(vm, method, index)
  +varargs : Bool = U32.is_ne(U32.and(M.loaded_method_flags(method), 128), 0) && U32.is_eq(index, U32.sub(method_parameter_count(method), 1))
  +text : String = modifier_prefix(flags) ++ Bool.pick(String, varargs, varargs_type_name(type_name), type_name) ++ " " ++ parameter_name(vm, method, index)
  intern_or_alloc(vm, units_from_string(text))

def parameter_text_named(found: Result<&2, &2, String, TextAt>, +method: M.LoadedMethod, +index: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Fail{error}: Fail{error}
    case Done{TextAt{+vm, +type_name}}: parameter_text(vm, method, index, type_name)

def parameter_text_typed(found: Result<&2, &2, String, ReflectRefs>, +method: M.LoadedMethod, +index: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Fail{error}: Fail{error}
    case Done{ReflectRefs{+vm, refs}}: parameter_text_named(outcome_text(type_get_type_name(vm, [M.Slot{3, first_ref(refs)}])), method, index)

# Parameter.toString: modifiers, the generic type name (varargs as "..."), and the name.
def parameter_to_string(+vm: M.VM, +method: M.LoadedMethod, +index: U32) -> Result<&2, &2, String, O.Outcome>:
  parameter_text_typed(outcome_reference(parameter_element(index, reflect_member_generic_parameter_types(vm, method))), method, index)

def parameter_query(+op: U32, +vm: M.VM, +executable: U32, +index: U32, +method: M.LoadedMethod, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match op:
    case 466: intern_or_alloc(vm, units_from_string(parameter_name(vm, method, index)))
    case 467: bool_out(vm, Bool.not(String.is_empty(parameter_record_name(M.nth(M.MethodParameter, method_parameter_records(vm, method), index)))))
    case 468: int_out(vm, parameter_flags(vm, method, index))
    case 469: bool_out(vm, U32.is_ne(U32.and(parameter_flags(vm, method, index), 32768), 0))
    case 470: bool_out(vm, U32.is_ne(U32.and(parameter_flags(vm, method, index), 4096), 0))
    case 471: bool_out(vm, U32.is_ne(U32.and(M.loaded_method_flags(method), 128), 0) && U32.is_eq(index, U32.sub(method_parameter_count(method), 1)))
    case 472: parameter_element(index, reflect_member_parameter_types(vm, method))
    case 473: parameter_element(index, reflect_member_generic_parameter_types(vm, method))
    case 474: ref_out(vm, executable)
    case 475:
      do Result<&2, &2, String, O.Outcome>:
        source : AnnotationMetadataRef <- parameter_annotations(vm, method, index)
        result : O.Outcome <- class_annotations_array_from(source)
        return result
    case 476:
      do Result<&2, &2, String, O.Outcome>:
        source : AnnotationMetadataRef <- parameter_annotations(vm, method, index)
        result : O.Outcome <- class_annotations_array_from(source)
        return result
    case 477:
      do Result<&2, &2, String, O.Outcome>:
        +name : String <- reflect_annotation_name(vm, args)
        source : AnnotationMetadataRef <- parameter_annotations(vm, method, index)
        result : O.Outcome <- class_annotation_one_from(source, name)
        return result
    case 478:
      do Result<&2, &2, String, O.Outcome>:
        +name : String <- reflect_annotation_name(vm, args)
        source : AnnotationMetadataRef <- parameter_annotations(vm, method, index)
        result : O.Outcome <- class_annotation_one_from(source, name)
        return result
    case 479:
      do Result<&2, &2, String, O.Outcome>:
        +name : String <- reflect_annotation_name(vm, args)
        source : AnnotationMetadataRef <- parameter_annotations(vm, method, index)
        result : O.Outcome <- reflect_annotation_present_source(vm, source, name)
        return result
    case 480:
      do Result<&2, &2, String, O.Outcome>:
        +name : String <- reflect_annotation_name(vm, args)
        source : AnnotationMetadataRef <- parameter_annotations(vm, method, index)
        result : O.Outcome <- annotation_arrays_by_type_from(source, name)
        return result
    case 481:
      do Result<&2, &2, String, O.Outcome>:
        +name : String <- reflect_annotation_name(vm, args)
        source : AnnotationMetadataRef <- parameter_annotations(vm, method, index)
        result : O.Outcome <- annotation_arrays_by_type_from(source, name)
        return result
    case 482:
      do Result<&2, &2, String, O.Outcome>:
        +other : M.Slot <- slot1(args)
        result : O.Outcome <- bool_out(vm, U32.is_ne(bits_of(other), 0) && parameter_equal(vm, executable, index, bits_of(other)))
        return result
    case 483:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), executable)
        result : O.Outcome <- parameter_hash(index, executable_hash(executable_is_constructor(vm, entry), vm, executable))
        return result
    case 484: parameter_to_string(vm, method, index)
    case _: Fail{"InvalidState: unknown Parameter operation"}

def parameter_dispatch(+op: U32, +vm: M.VM, parts: ParameterParts, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match parts:
    case ParameterParts{+executable, +index}:
      do Result<&2, &2, String, O.Outcome>:
        +method : M.LoadedMethod <- executable_method(vm, executable)
        result : O.Outcome <- parameter_query(op, vm, executable, index, method, args)
        return result

def parameter_intrinsic(+op: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    parts : ParameterParts <- parameter_parts(vm, args)
    result : O.Outcome <- parameter_dispatch(op, vm, parts, args)
    return result

# ---- Comparable.compareTo and the static compare methods (JDK semantics) ----

def int_signed_less(+a: U32, +b: U32) -> Bool:
  U32.is_lt(U32.xor(a, 2147483648), U32.xor(b, 2147483648))

def int_compare(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, int_signed_less(a, b), 4294967295, Bool.pick(U32, U32.is_eq(a, b), 0, 1))

# Float.compare: numeric order with -0.0 < 0.0 and NaN above everything.
def float_key(+bits: U32) -> U32:
  +magnitude : U32 = U32.and(bits, 2147483647)
  Bool.pick(U32, U32.is_ne(U32.and(bits, 2147483648), 0), U32.sub(0, magnitude), magnitude)

def float_canonical(+bits: U32) -> U32:
  Bool.pick(U32, U32.is_lt(2139095040, U32.and(bits, 2147483647)), 2143289344, bits)

def float_compare(+a: U32, +b: U32) -> U32:
  +ka : U32 = float_canonical(a)
  +kb : U32 = float_canonical(b)
  +nan : Bool = U32.is_lt(2139095040, U32.and(a, 2147483647)) || U32.is_lt(2139095040, U32.and(b, 2147483647))
  +ordered : U32 = int_compare(float_key(a), float_key(b))
  Bool.pick(U32, nan || U32.is_eq(ordered, 0), int_compare(ka, kb), ordered)

def double_canonical(+value: W.Words) -> W.Words:
  Bool.pick(W.Words, B64.double_is_nan(value), W.Words{2146959360, 0}, value)

# Double.compare: as Float.compare, on doubleToLongBits after numeric order.
def double_compare(+a: W.Words, +b: W.Words) -> U32:
  +nan : Bool = B64.double_is_nan(a) || B64.double_is_nan(b)
  +ordered : U32 = B64.compare_ordered(a, b)
  Bool.pick(U32, nan || U32.is_eq(ordered, 0), W.long_cmp(double_canonical(a), double_canonical(b)), ordered)

@unsafe def units_compare_hit(+same: Bool, +x: U32, +y: U32, +xs: +List<U32>, +ys: +List<U32>) -> U32:
  match same:
    case True{}: units_compare(xs, ys)
    case False{}: U32.sub(x, y)

# String.compareTo: the first differing UTF-16 unit, else the length difference.
@unsafe def units_compare(+a: +List<U32>, +b: +List<U32>) -> U32:
  match a b:
    case Nil{} Nil{}: 0
    case Nil{} rest: U32.sub(0, M.length(U32, rest))
    case rest Nil{}: M.length(U32, rest)
    case Con{x, xs} Con{y, ys}: units_compare_hit(U32.is_eq(x, y), x, y, xs, ys)

def compare_class_name(+kind: U32) -> String:
  match kind:
    case 485: "java/lang/Integer"
    case 486: "java/lang/Short"
    case 487: "java/lang/Byte"
    case 488: "java/lang/Character"
    case 489: "java/lang/Boolean"
    case 490: "java/lang/Long"
    case 491: "java/lang/Double"
    case 492: "java/lang/Float"
    case _: "java/lang/String"

def compare_source(+kind: U32) -> U32:
  match kind:
    case 490: 74
    case 491: 68
    case 492: 70
    case _: 73

def compare_slots(+kind: U32, +vm: M.VM, +left: M.Slot, +right: M.Slot) -> Result<&2, &2, String, U32>:
  match kind:
    case 490:
      do Result<&2, &2, String, U32>:
        +a : W.Words <- wide_words(left, 4)
        +b : W.Words <- wide_words(right, 4)
        return W.long_cmp(a, b)
    case 491:
      do Result<&2, &2, String, U32>:
        +a : W.Words <- wide_words(left, 5)
        +b : W.Words <- wide_words(right, 5)
        return double_compare(a, b)
    case 492: Done{float_compare(bits_of(left), bits_of(right))}
    case 485: Done{int_compare(bits_of(left), bits_of(right))}
    case 489: Done{int_compare(bits_of(left), bits_of(right))}
    case _: Done{U32.sub(bits_of(left), bits_of(right))}

def compare_wrappers(+kind: U32, +vm: M.VM, +left: M.HeapEntry, +right: M.HeapEntry) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +a : M.Slot <- wrapper_value_slot(vm, left, compare_source(kind))
    +b : M.Slot <- wrapper_value_slot(vm, right, compare_source(kind))
    result : U32 <- compare_slots(kind, vm, a, b)
    return result

def compare_entries(+string: Bool, +kind: U32, +vm: M.VM, +left: M.HeapEntry, +right: M.HeapEntry) -> Result<&2, &2, String, U32>:
  match string:
    case True{}:
      do Result<&2, &2, String, U32>:
        +a : +List<U32> <- string_chars_entry(left)
        +b : +List<U32> <- string_chars_entry(right)
        return units_compare(a, b)
    case False{}: compare_wrappers(kind, vm, left, right)

# compareTo(T) and its compareTo(Object) bridge: null throws NullPointerException,
# another class throws ClassCastException (the bridge's checkcast).
def comparable_compare(+vm: M.VM, +args: +List<M.Slot>, +kind: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +other : M.Slot <- slot1(args)
    present : Unit <- S.check(U32.is_ne(bits_of(other), 0), npe())
    +left : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +right : M.HeapEntry <- H.get(S.heap(vm), bits_of(other))
    +expected : String = compare_class_name(kind)
    same : Unit <- S.check(U32.is_eq(H.entry_class(right), class_id(vm, expected)), "java/lang/ClassCastException: " ++ internal_to_binary(class_name_text(vm, H.entry_class(right))) ++ " cannot be cast to " ++ internal_to_binary(expected))
    value : U32 <- compare_entries(U32.is_eq(kind, 493), kind, vm, left, right)
    result : O.Outcome <- int_out(vm, value)
    return result

# Integer/Long/Double/Float.compare(x, y).
def static_compare(+vm: M.VM, +args: +List<M.Slot>, +kind: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +left : M.Slot <- slot0(args)
    +right : M.Slot <- slot1(args)
    value : U32 <- compare_slots(Bool.pick(U32, U32.is_eq(kind, 494), 485, Bool.pick(U32, U32.is_eq(kind, 495), 490, Bool.pick(U32, U32.is_eq(kind, 496), 491, 492))), vm, left, right)
    result : O.Outcome <- int_out(vm, value)
    return result

# ---- Nested-class reflection: InnerClasses and EnclosingMethod (JDK 8 Class) ----

def nesting_found(found: Result<&2, &2, String, M.ClassMetadata>) -> M.Nesting:
  match found:
    case Fail{error}: M.empty_nesting()
    case Done{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, pool, signature, nesting, source}}: nesting

def class_nesting_of(+vm: M.VM, +id: U32) -> M.Nesting:
  nesting_found(class_metadata_value(vm, id))

def nesting_entries(+value: M.Nesting) -> +List<M.InnerClass>:
  match value:
    case M.Nesting{inner, enclosingClass, method, descriptor}: inner

def nesting_enclosing_class(+value: M.Nesting) -> String:
  match value:
    case M.Nesting{inner, enclosingClass, method, descriptor}: enclosingClass

def nesting_method(+value: M.Nesting) -> String:
  match value:
    case M.Nesting{inner, enclosingClass, method, descriptor}: method

def nesting_descriptor(+value: M.Nesting) -> String:
  match value:
    case M.Nesting{inner, enclosingClass, method, descriptor}: descriptor

def own_outer(+entries: +List<M.InnerClass>, +name: String) -> String:
  match entries:
    case Nil{}: ""
    case Con{M.InnerClass{inner, outer, simple, flags}, rest}:
      Bool.pick(String, String.eq(inner, name), outer, own_outer(rest, name))

# Class.getDeclaringClass: the outer class recorded for a member class.
def declaring_name(+vm: M.VM, +id: U32) -> String:
  own_outer(nesting_entries(class_nesting_of(vm, id)), class_name_text(vm, id))

def local_or_anonymous(+vm: M.VM, +id: U32) -> Bool:
  Bool.not(String.is_empty(nesting_enclosing_class(class_nesting_of(vm, id))))

# Class.getEnclosingClass: the EnclosingMethod class, else the declaring class.
def enclosing_name(+vm: M.VM, +id: U32) -> String:
  +declared : String = nesting_enclosing_class(class_nesting_of(vm, id))
  Bool.pick(String, String.is_empty(declared), declaring_name(vm, id), declared)

def drop_prefix_length(+text: String, +prefix: String) -> String:
  match text prefix:
    case SCon{a, rest} SCon{b, more}: drop_prefix_length(rest, more)
    case rest _: rest

def drop_digits(+text: String) -> String:
  match text:
    case SCon{c, rest}: Bool.pick(String, U32.is_le(48, Char.to_u32(c)) && U32.is_le(Char.to_u32(c), 57), drop_digits(rest), text)
    case SNil{}: ""

def strip_binary_prefix(+simple: String) -> String:
  match simple:
    case SCon{Chr{36}, rest}: drop_digits(rest)
    case other: other

def last_segment(+text: String, +acc: String) -> String:
  match text:
    case SNil{}: acc
    case SCon{Chr{47}, rest}: last_segment(rest, "")
    case SCon{c, rest}: last_segment(rest, acc ++ Char.show(c))

def primitive_descriptor_name(+descriptor: String) -> String:
  match descriptor:
    case "Z": "boolean"
    case "B": "byte"
    case "C": "char"
    case "S": "short"
    case "I": "int"
    case "J": "long"
    case "F": "float"
    case "D": "double"
    case "V": "void"
    case other: ""

# Class.getSimpleName (JDK 8): arrays add "[]"; top-level classes keep the
# last name segment; nested classes drop the enclosing class name and any
# leading "$digits" (so anonymous classes have an empty simple name).
@unsafe def simple_name(+fuel: Nat, +vm: M.VM, +name: String) -> String:
  match fuel name:
    case 0n _: ""
    case 1n+p SCon{Chr{91}, rest}: simple_component(p, vm, rest) ++ "[]"
    case 1n+p _: simple_named(vm, name, enclosing_name(vm, class_id(vm, name)))

def simple_named(+vm: M.VM, +name: String, +enclosing: String) -> String:
  Bool.pick(String, String.is_empty(enclosing), last_segment(name, ""), strip_binary_prefix(drop_prefix_length(name, enclosing)))

@unsafe def simple_component(+fuel: Nat, +vm: M.VM, +descriptor: String) -> String:
  match descriptor:
    case SCon{Chr{76}, rest}: simple_name(fuel, vm, CL.take_until_semicolon(rest, ""))
    case SCon{Chr{91}, rest}: simple_name(fuel, vm, descriptor)
    case other: primitive_descriptor_name(other)

# Class.getCanonicalName: None for local and anonymous classes (and arrays of them).
@unsafe def canonical_name(+fuel: Nat, +vm: M.VM, +name: String) -> Maybe<&2, String>:
  match fuel name:
    case 0n _: None{}
    case 1n+p SCon{Chr{91}, rest}: canonical_suffix(canonical_component(p, vm, rest))
    case 1n+p _: canonical_class(p, vm, name, class_id(vm, name))

def canonical_suffix(found: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case None{}: None{}
    case Some{text}: Some{text ++ "[]"}

@unsafe def canonical_component(+fuel: Nat, +vm: M.VM, +descriptor: String) -> Maybe<&2, String>:
  match descriptor:
    case SCon{Chr{76}, rest}: canonical_name(fuel, vm, CL.take_until_semicolon(rest, ""))
    case SCon{Chr{91}, rest}: canonical_name(fuel, vm, descriptor)
    case other: Some{primitive_descriptor_name(other)}

@unsafe def canonical_local(local: Bool, +fuel: Nat, +vm: M.VM, +name: String, +id: U32) -> Maybe<&2, String>:
  match local:
    case True{}: None{}
    case False{}: canonical_enclosed(fuel, vm, name, enclosing_name(vm, id))

@unsafe def canonical_class(+fuel: Nat, +vm: M.VM, +name: String, +id: U32) -> Maybe<&2, String>:
  canonical_local(local_or_anonymous(vm, id), fuel, vm, name, id)

@unsafe def canonical_top(top: Bool, +fuel: Nat, +vm: M.VM, +name: String, +enclosing: String) -> Maybe<&2, String>:
  match top:
    case True{}: Some{internal_to_binary(name)}
    case False{}: canonical_join(canonical_name(fuel, vm, enclosing), simple_name(fuel, vm, name))

@unsafe def canonical_enclosed(+fuel: Nat, +vm: M.VM, +name: String, +enclosing: String) -> Maybe<&2, String>:
  canonical_top(String.is_empty(enclosing), fuel, vm, name, enclosing)

def canonical_join(found: Maybe<&2, String>, +simple: String) -> Maybe<&2, String>:
  match found:
    case None{}: None{}
    case Some{text}: Some{text ++ "." ++ simple}

def optional_string_out(+vm: M.VM, found: Maybe<&2, String>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: ref_out(vm, 0)
    case Some{text}: intern_or_alloc(vm, units_from_string(text))

def class_named_out(+vm: M.VM, +name: String) -> Result<&2, &2, String, O.Outcome>:
  +id : U32 = class_id(vm, name)
  Bool.pick(Result<&2, &2, String, O.Outcome>, String.is_empty(name) || U32.is_eq(id, 4294967295), ref_out(vm, 0), class_mirror_out(vm, id))

def method_named(+vm: M.VM, +values: +List<M.LoadedMethod>, +owner: U32, +name: String, +descriptor: String) -> Maybe<&2, M.LoadedMethod>:
  match values:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>,
        U32.is_eq(M.loaded_method_owner(method), owner) && String.eq(Sy.text(S.symbols(vm), M.loaded_method_name(method)), name) && String.eq(Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)), descriptor),
        Some{method}, method_named(vm, rest, owner, name, descriptor))

def enclosing_member_out(+vm: M.VM, +constructor: Bool, found: Maybe<&2, M.LoadedMethod>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: ref_out(vm, 0)
    case Some{+method}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, constructor, reflect_constructor_one(vm, M.loaded_method_owner(method), method), reflect_method_one(vm, M.loaded_method_owner(method), method))

# Class.getEnclosingMethod/getEnclosingConstructor from EnclosingMethod.
def enclosing_member(+vm: M.VM, +id: U32, +constructor: Bool) -> Result<&2, &2, String, O.Outcome>:
  +nesting : M.Nesting = class_nesting_of(vm, id)
  +method : String = nesting_method(nesting)
  +wanted : Bool = Bool.not(String.is_empty(method)) && U32.is_eq(Bool.to_u32(String.eq(method, "<init>")), Bool.to_u32(constructor))
  +owner : U32 = class_id(vm, nesting_enclosing_class(nesting))
  Bool.pick(Result<&2, &2, String, O.Outcome>, wanted && U32.is_ne(owner, 4294967295),
    enclosing_member_out(vm, constructor, method_named(vm, S.methods(vm), owner, method, nesting_descriptor(nesting))),
    ref_out(vm, 0))

def member_names(+entries: +List<M.InnerClass>, +owner: String) -> +List<String>:
  match entries:
    case Nil{}: Nil{}
    case Con{M.InnerClass{inner, outer, simple, flags}, rest}:
      +tail = member_names(rest, owner)
      Bool.pick(+List<String>, String.eq(outer, owner) && Bool.not(String.eq(inner, owner)), Con{inner, tail}, tail)

def loaded_ids(+vm: M.VM, +names: +List<String>) -> +List<U32>:
  match names:
    case Nil{}: Nil{}
    case Con{name, rest}:
      +id : U32 = class_id(vm, name)
      +tail = loaded_ids(vm, rest)
      Bool.pick(+List<U32>, U32.is_eq(id, 4294967295), tail, Con{id, tail})

def declared_class_ids(+vm: M.VM, +id: U32) -> +List<U32>:
  loaded_ids(vm, member_names(nesting_entries(class_nesting_of(vm, id)), class_name_text(vm, id)))

def inner_flags(+entries: +List<M.InnerClass>, +name: String) -> U32:
  match entries:
    case Nil{}: 0
    case Con{M.InnerClass{inner, outer, simple, flags}, rest}:
      Bool.pick(U32, String.eq(inner, name), flags, inner_flags(rest, name))

def public_member_ids(+vm: M.VM, +ids: +List<U32>, +owner: U32) -> +List<U32>:
  match ids:
    case Nil{}: Nil{}
    case Con{+id, rest}:
      +tail = public_member_ids(vm, rest, owner)
      +flags : U32 = inner_flags(nesting_entries(class_nesting_of(vm, owner)), class_name_text(vm, id))
      Bool.pick(+List<U32>, U32.is_ne(U32.and(flags, 1), 0), Con{id, tail}, tail)

def class_parent_of(found: Maybe<&2, M.LoadedClass>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{class}: M.loaded_class_parent(class)

def loaded_parent_id(+vm: M.VM, +id: U32) -> U32:
  class_parent_of(M.nth(M.LoadedClass, S.classes(vm), id))

# Class.getClasses: public member classes of the class and its superclasses.
@unsafe def public_classes(+fuel: Nat, +vm: M.VM, +id: U32) -> +List<U32>:
  match fuel id:
    case 0n _: Nil{}
    case _ 4294967295: Nil{}
    case 1n+p _: M.append(U32, public_member_ids(vm, declared_class_ids(vm, id), id), public_classes(p, vm, loaded_parent_id(vm, id)))

@unsafe def mirror_refs(+vm: M.VM, +ids: +List<U32>, +acc: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match ids:
    case Nil{}: Done{ReflectRefs{vm, M.reverse(U32, acc)}}
    case Con{id, rest}: mirror_refs_next(class_mirror_out(vm, id), rest, acc)

@unsafe def mirror_refs_next(result: Result<&2, &2, String, O.Outcome>, +ids: +List<U32>, +acc: +List<U32>) -> Result<&2, &2, String, ReflectRefs>:
  match result:
    case Done{O.Returned{+vm, Some{mirror}}}: mirror_refs(vm, ids, Con{bits_of(mirror), acc})
    case Done{other}: Fail{"InvalidState: class mirror"}
    case Fail{error}: Fail{error}

def class_array_out(result: Result<&2, &2, String, ReflectRefs>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{refs}: reflect_refs_array(refs, "[Ljava/lang/Class;", "java/lang/Class")

def nested_query(+op: U32, +vm: M.VM, +id: U32, +name: String) -> Result<&2, &2, String, O.Outcome>:
  match op:
    case 498: intern_or_alloc(vm, units_from_string(simple_name(64n, vm, name)))
    case 499: optional_string_out(vm, canonical_name(64n, vm, name))
    case 500: class_named_out(vm, enclosing_name(vm, id))
    case 501: class_named_out(vm, declaring_name(vm, id))
    case 502: enclosing_member(vm, id, False{})
    case 503: enclosing_member(vm, id, True{})
    case 504: bool_out(vm, Bool.not(String.is_empty(enclosing_name(vm, id))) && Bool.not(local_or_anonymous(vm, id)))
    case 505: bool_out(vm, local_or_anonymous(vm, id) && Bool.not(String.is_empty(simple_name(64n, vm, name))))
    case 506: bool_out(vm, String.is_empty(simple_name(64n, vm, name)) && Bool.not(String.starts_with(name, "[")))
    case 507: class_array_out(mirror_refs(vm, declared_class_ids(vm, id), Nil{}))
    case 508: class_array_out(mirror_refs(vm, public_classes(64n, vm, id), Nil{}))
    case _: Fail{"InvalidState: unknown nested-class operation"}

def nested_class_intrinsic(+op: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    result : O.Outcome <- nested_query(op, vm, target, class_name_text(vm, target))
    return result

# ---- Generic declarations: type parameters, bounds, equality (JDK 8 + oracle format) ----

@unsafe def tv_class_name() -> String:
  "sun/reflect/generics/reflectiveObjects/TypeVariableImpl"

@unsafe def type_kind_name(+name: String) -> U32:
  match name:
    case "java/lang/Class": 1
    case "sun/reflect/generics/reflectiveObjects/ParameterizedTypeImpl": 2
    case "sun/reflect/generics/reflectiveObjects/TypeVariableImpl": 3
    case "sun/reflect/generics/reflectiveObjects/WildcardTypeImpl": 4
    case "sun/reflect/generics/reflectiveObjects/GenericArrayTypeImpl": 5
    case _: 9

@unsafe def binding_ref(+entry: M.HeapEntry, +index: U32) -> U32:
  binding_bits(H.binding_find(entry_fields(entry), index))

@unsafe def heap_or_empty(found: Result<&2, &2, String, M.HeapEntry>) -> M.HeapEntry:
  match found:
    case Fail{error}: M.HeapEntry{4294967295, 0, 0, Nil{}, Nil{}, Nil{}}
    case Done{entry}: entry

@unsafe def entry_at(+vm: M.VM, +reference: U32) -> M.HeapEntry:
  heap_or_empty(H.get(S.heap(vm), reference))

@unsafe def type_kind_at(+vm: M.VM, +reference: U32) -> U32:
  Bool.pick(U32, U32.is_eq(reference, 0), 0, type_kind_name(class_name_text(vm, H.entry_class(entry_at(vm, reference)))))

@unsafe def chars_at(+vm: M.VM, +reference: U32) -> +List<U32>:
  entry_chars(entry_at(vm, reference))

@unsafe def units_equal(+a: +List<U32>, +b: +List<U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x, xs} Con{y, ys}: U32.is_eq(x, y) && units_equal(xs, ys)
    case _ _: False{}

# Arrays.equals / Arrays.hashCode over Type[] arrays, and the JDK impl classes'
# structural equals/hashCode (ParameterizedTypeImpl, WildcardTypeImpl,
# GenericArrayTypeImpl, TypeVariableImpl); Class compares by identity.
@unsafe def slots_equal(+fuel: Nat, +vm: M.VM, +a: +List<M.Slot>, +b: +List<M.Slot>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x, xs} Con{y, ys}: type_equal(fuel, vm, bits_of(x), bits_of(y)) && slots_equal(fuel, vm, xs, ys)
    case _ _: False{}

@unsafe def arrays_equal(+fuel: Nat, +vm: M.VM, +a: U32, +b: U32) -> Bool:
  slots_equal(fuel, vm, entry_values(entry_at(vm, a)), entry_values(entry_at(vm, b)))

@unsafe def type_equal_kind(+kind: U32, +fuel: Nat, +vm: M.VM, +a: U32, +b: U32, +left: M.HeapEntry, +right: M.HeapEntry) -> Bool:
  match kind:
    case 2: U32.is_eq(binding_ref(left, 0), binding_ref(right, 0)) && type_equal(fuel, vm, binding_ref(left, 2), binding_ref(right, 2)) && arrays_equal(fuel, vm, binding_ref(left, 1), binding_ref(right, 1))
    case 3: U32.is_eq(binding_ref(left, 1), binding_ref(right, 1)) && U32.is_eq(binding_ref(left, 2), binding_ref(right, 2)) && units_equal(chars_at(vm, binding_ref(left, 0)), chars_at(vm, binding_ref(right, 0)))
    case 4: arrays_equal(fuel, vm, binding_ref(left, 0), binding_ref(right, 0)) && arrays_equal(fuel, vm, binding_ref(left, 1), binding_ref(right, 1))
    case 5: type_equal(fuel, vm, binding_ref(left, 0), binding_ref(right, 0))
    case _: U32.is_eq(a, b)

@unsafe def type_equal_go(+same: Bool, +fuel: Nat, +vm: M.VM, +a: U32, +b: U32) -> Bool:
  match same:
    case True{}: True{}
    case False{}:
      +kind : U32 = type_kind_at(vm, a)
      U32.is_eq(kind, type_kind_at(vm, b)) && U32.is_ne(kind, 0) && U32.is_ne(kind, 1) && type_equal_kind(kind, fuel, vm, a, b, entry_at(vm, a), entry_at(vm, b))

@unsafe def type_equal(+fuel: Nat, +vm: M.VM, +a: U32, +b: U32) -> Bool:
  match fuel:
    case 0n: False{}
    case 1n+p: type_equal_go(U32.is_eq(a, b), p, vm, a, b)

@unsafe def units_hash(+units: +List<U32>) -> U32:
  string_hash_go(units, 0)

@unsafe def slots_hash(+fuel: Nat, +vm: M.VM, +slots: +List<M.Slot>, +acc: U32) -> U32:
  match slots:
    case Nil{}: acc
    case Con{x, xs}: slots_hash(fuel, vm, xs, U32.add(U32.mul(31, acc), type_hash(fuel, vm, bits_of(x))))

@unsafe def array_hash(+fuel: Nat, +vm: M.VM, +array: U32) -> U32:
  Bool.pick(U32, U32.is_eq(array, 0), 0, slots_hash(fuel, vm, entry_values(entry_at(vm, array)), 1))

@unsafe def binary_units(+vm: M.VM, +id: U32) -> +List<U32>:
  units_from_string(internal_to_binary(class_name_text(vm, id)))

# Class.hashCode of a declaration's class, Method.hashCode, or Constructor.hashCode.
@unsafe def declaration_hash(+vm: M.VM, +kind: U32, +id: U32) -> U32:
  match kind:
    case 1: class_identity_hash(vm, id)
    case _: method_declaration_hash(vm, kind, M.nth(M.LoadedMethod, S.methods(vm), id))

@unsafe def method_declaration_hash(+vm: M.VM, +kind: U32, found: Maybe<&2, M.LoadedMethod>) -> U32:
  match found:
    case None{}: 0
    case Some{+method}:
      +owner_hash : U32 = units_hash(binary_units(vm, M.loaded_method_owner(method)))
      Bool.pick(U32, U32.is_eq(kind, 3), owner_hash, U32.xor(owner_hash, units_hash(units_from_string(Sy.text(S.symbols(vm), M.loaded_method_name(method))))))

# Class mirrors hash by the class they mirror (stable without allocating one).
@unsafe def class_identity_hash(+vm: M.VM, +id: U32) -> U32:
  id

@unsafe def type_hash_kind(+kind: U32, +fuel: Nat, +vm: M.VM, +reference: U32, +entry: M.HeapEntry) -> U32:
  match kind:
    case 0: 0
    case 1: class_identity_hash(vm, entry_element(entry))
    case 2: U32.xor(U32.xor(array_hash(fuel, vm, binding_ref(entry, 1)), type_hash(fuel, vm, binding_ref(entry, 2))), class_identity_hash(vm, binding_ref(entry, 0)))
    case 3: U32.xor(declaration_hash(vm, binding_ref(entry, 1), binding_ref(entry, 2)), units_hash(chars_at(vm, binding_ref(entry, 0))))
    case 4: U32.xor(array_hash(fuel, vm, binding_ref(entry, 1)), array_hash(fuel, vm, binding_ref(entry, 0)))
    case 5: type_hash(fuel, vm, binding_ref(entry, 0))
    case _: reference

@unsafe def type_hash(+fuel: Nat, +vm: M.VM, +reference: U32) -> U32:
  match fuel:
    case 0n: 0
    case 1n+p: type_hash_kind(type_kind_at(vm, reference), p, vm, reference, entry_at(vm, reference))

@unsafe def type_equals_intrinsic(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +other : M.Slot <- slot1(args)
    +result : O.Outcome <- bool_out(vm, U32.is_ne(bits_of(other), 0) && type_equal(64n, vm, bits_of(receiver), bits_of(other)))
    return result

@unsafe def type_hash_intrinsic(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +result : O.Outcome <- int_out(vm, type_hash(64n, vm, bits_of(receiver)))
    return result

@unsafe def type_variable_array(result: Result<&2, &2, String, G.TypeRefs>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{G.TypeRefs{+vm, refs}}:
      alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/reflect/TypeVariable;"), class_id(vm, "java/lang/reflect/TypeVariable"), exception_ref_slots(refs))), vm2 => reference => ref_out(vm2, reference))

@unsafe def declaration_parameters(+vm: M.VM, +params: +List<Sig.TypeParam>, +kind: U32, +id: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ready : M.VM <- ensure_array_class(vm, "[Ljava/lang/reflect/TypeVariable;")
    +result : O.Outcome <- type_variable_array(G.type_parameters(ready, params, kind, id))
    return result

@unsafe def class_type_parameters(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    +result : O.Outcome <- declaration_parameters(vm, G.class_variables(class_signature(vm, target)), 1, target)
    return result

@unsafe def executable_type_parameters(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +method : M.LoadedMethod <- executable_method(vm, bits_of(receiver))
    +result : O.Outcome <- declaration_parameters(vm, G.method_variables(method_signature(vm, method)), method_scope_kind(vm, method), M.loaded_method_id(method))
    return result

@unsafe def class_generic_interfaces_text(+vm: M.VM, +args: +List<M.Slot>, +target: U32, +text: String) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, String.is_empty(text), class_get_interfaces(vm, args), generic_type_array(class_generic_interfaces(vm, target, text)))

@unsafe def class_generic_interfaces_out(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    +result : O.Outcome <- class_generic_interfaces_text(vm, args, target, class_signature(vm, target))
    return result

@unsafe def type_variable_parts(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, M.HeapEntry>:
  do Result<&2, &2, String, M.HeapEntry>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    return entry

@unsafe def declaration_member(+vm: M.VM, +kind: U32, found: Maybe<&2, M.LoadedMethod>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: Fail{"InvalidState: generic declaration"}
    case Some{+method}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(kind, 3), reflect_constructor_one(vm, M.loaded_method_owner(method), method), reflect_method_one(vm, M.loaded_method_owner(method), method))

# TypeVariable.getGenericDeclaration: the Class, Method or Constructor declaring it.
@unsafe def type_variable_declaration(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- type_variable_parts(vm, args)
    +kind : U32 = binding_ref(entry, 1)
    +id : U32 = binding_ref(entry, 2)
    +result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(kind, 1), class_mirror_out(vm, id), declaration_member(vm, kind, M.nth(M.LoadedMethod, S.methods(vm), id)))
    return result

@unsafe def bounds_in_method(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>, +name: String) -> Result<&2, &2, String, G.TypeRefs>:
  match found:
    case None{}: Fail{"InvalidState: generic declaration"}
    case Some{+method}:
      +params = G.method_variables(method_signature(vm, method))
      do Result<&2, &2, String, G.TypeRefs>:
        +ready : M.VM <- ensure_arrays(vm, G.params_arrays(params))
        +result : G.TypeRefs <- G.bounds_refs(ready, params, name, method_scopes(64n, ready, method))
        return result

@unsafe def bounds_in_class(+vm: M.VM, +id: U32, +name: String) -> Result<&2, &2, String, G.TypeRefs>:
  +params = G.class_variables(class_signature(vm, id))
  do Result<&2, &2, String, G.TypeRefs>:
    +ready : M.VM <- ensure_arrays(vm, G.params_arrays(params))
    +result : G.TypeRefs <- G.bounds_refs(ready, params, name, class_scopes(64n, ready, id))
    return result

@unsafe def type_variable_bounds_of(+vm: M.VM, +entry: M.HeapEntry) -> Result<&2, &2, String, G.TypeRefs>:
  do Result<&2, &2, String, G.TypeRefs>:
    +name : String <- string_text(vm, binding_ref(entry, 0))
    +kind : U32 = binding_ref(entry, 1)
    +id : U32 = binding_ref(entry, 2)
    +result : G.TypeRefs <- Bool.pick(Result<&2, &2, String, G.TypeRefs>, U32.is_eq(kind, 1), bounds_in_class(vm, id, name), bounds_in_method(vm, M.nth(M.LoadedMethod, S.methods(vm), id), name))
    return result

# TypeVariable.getBounds, computed on each call from the declaring signature.
@unsafe def type_variable_bounds_lazy(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- type_variable_parts(vm, args)
    +result : O.Outcome <- generic_type_array(type_variable_bounds_of(vm, entry))
    return result

# ---- Modifier and the reflection toString/toGenericString renderers ----

@unsafe def modifier_word(+flags: U32, +bit: U32, +word: String) -> String:
  Bool.pick(String, U32.is_ne(U32.and(flags, bit), 0), word ++ " ", "")

@unsafe def trim_last_space(+text: String) -> String:
  String.reverse(drop_leading_space(String.reverse(text)))

@unsafe def drop_leading_space(+text: String) -> String:
  match text:
    case SCon{Chr{32}, rest}: rest
    case other: other

# java.lang.reflect.Modifier.toString order.
@unsafe def modifier_text(+flags: U32) -> String:
  trim_last_space(modifier_word(flags, 1, "public") ++ modifier_word(flags, 4, "protected") ++ modifier_word(flags, 2, "private") ++
    modifier_word(flags, 1024, "abstract") ++ modifier_word(flags, 8, "static") ++ modifier_word(flags, 16, "final") ++
    modifier_word(flags, 128, "transient") ++ modifier_word(flags, 64, "volatile") ++ modifier_word(flags, 32, "synchronized") ++
    modifier_word(flags, 256, "native") ++ modifier_word(flags, 2048, "strictfp") ++ modifier_word(flags, 512, "interface"))

@unsafe def modifier_prefix_text(+flags: U32) -> String:
  +text : String = modifier_text(flags)
  Bool.pick(String, String.is_empty(text), "", text ++ " ")

@unsafe def jvm_type_name(+value: M.JvmType) -> String:
  match value:
    case M.Primitive{tag}: primitive_descriptor_name(Char.show(Chr{tag}))
    case M.ObjectType{name}: internal_to_binary(name)
    case M.ArrayType{element}: jvm_type_name(element) ++ "[]"

@unsafe def joined_type_names(+values: +List<M.JvmType>) -> String:
  match values:
    case Nil{}: ""
    case Con{value, Nil{}}: jvm_type_name(value)
    case Con{value, rest}: jvm_type_name(value) ++ "," ++ joined_type_names(rest)

@unsafe def varargs_names(+varargs: Bool, +names: +List<String>) -> +List<String>:
  match varargs:
    case False{}: names
    case True{}: varargs_last(names)

@unsafe def varargs_last(+names: +List<String>) -> +List<String>:
  match names:
    case Nil{}: Nil{}
    case Con{name, Nil{}}: [varargs_type_name(name)]
    case Con{name, rest}: Con{name, varargs_last(rest)}

@unsafe def join_names(+names: +List<String>, +separator: String) -> String:
  match names:
    case Nil{}: ""
    case Con{name, Nil{}}: name
    case Con{name, rest}: name ++ separator ++ join_names(rest, separator)

type TextsAt is Data:
  TextsAt{vm: M.VM, texts: +List<String>}

@unsafe def ref_names(+vm: M.VM, +refs: +List<U32>, +acc: +List<String>) -> Result<&2, &2, String, TextsAt>:
  match refs:
    case Nil{}: Done{TextsAt{vm, M.reverse(String, acc)}}
    case Con{reference, rest}: ref_names_next(outcome_text(type_get_type_name(vm, [M.Slot{3, reference}])), rest, acc)

@unsafe def ref_names_next(found: Result<&2, &2, String, TextAt>, +refs: +List<U32>, +acc: +List<String>) -> Result<&2, &2, String, TextsAt>:
  match found:
    case Fail{error}: Fail{error}
    case Done{TextAt{vm, text}}: ref_names(vm, refs, Con{text, acc})

@unsafe def slot_refs(+values: +List<M.Slot>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: Con{bits_of(value), slot_refs(rest)}

# The type names of a Type[] produced by an intrinsic.
@unsafe def array_names(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, TextsAt>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{+vm, Some{array}}}: ref_names(vm, slot_refs(entry_values(entry_at(vm, bits_of(array)))), Nil{})
    case Done{other}: Fail{"InvalidState: expected a Type[]"}

@unsafe def class_name_texts(+vm: M.VM, +ids: +List<U32>) -> +List<String>:
  match ids:
    case Nil{}: Nil{}
    case Con{id, rest}: Con{internal_to_binary(class_name_text(vm, id)), class_name_texts(vm, rest)}

@unsafe def throws_text(+names: +List<String>) -> String:
  Bool.pick(String, U32.is_eq(M.length(String, names), 0), "", " throws " ++ join_names(names, ","))

@unsafe def method_interface_default(+vm: M.VM, +method: M.LoadedMethod) -> Bool:
  U32.is_ne(U32.and(class_flags(vm, M.loaded_method_owner(method)), 512), 0) && U32.is_eq(U32.and(M.loaded_method_flags(method), 1032), 0)

@unsafe def executable_prefix(+vm: M.VM, +method: M.LoadedMethod, +constructor: Bool) -> String:
  +mask : U32 = Bool.pick(U32, constructor, 7, 3391)
  modifier_prefix_text(U32.and(M.loaded_method_flags(method), mask)) ++ Bool.pick(String, constructor, "", Bool.pick(String, method_interface_default(vm, method), "default ", ""))

@unsafe def executable_owner_name(+vm: M.VM, +method: M.LoadedMethod) -> String:
  internal_to_binary(class_name_text(vm, M.loaded_method_owner(method)))

@unsafe def executable_exceptions(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, TextsAt>:
  do Result<&2, &2, String, TextsAt>:
    +source : AnnotationMetadataRef <- method_annotation_source(vm, method)
    +result : TextsAt <- array_names(method_exception_types(source))
    return result

@unsafe def plain_string_finish(found: Result<&2, &2, String, TextsAt>, +method: M.LoadedMethod, +constructor: Bool, +descriptor: M.Descriptor) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Fail{error}: Fail{error}
    case Done{TextsAt{+vm, exceptions}}:
      +owner_name : String = executable_owner_name(vm, method)
      +head : String = Bool.pick(String, constructor, owner_name, jvm_type_name(D.result_type(descriptor)) ++ " " ++ owner_name ++ "." ++ Sy.text(S.symbols(vm), M.loaded_method_name(method)))
      intern_or_alloc(vm, units_from_string(executable_prefix(vm, method, constructor) ++ head ++ "(" ++ joined_type_names(D.parameter_types(descriptor)) ++ ")" ++ throws_text(exceptions)))

# Method.toString / Constructor.toString: erased types, as the JDK prints them.
@unsafe def executable_plain_string(+vm: M.VM, +method: M.LoadedMethod, +constructor: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +parsed : M.Descriptor <- D.parse_method(Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)))
    +result : O.Outcome <- plain_string_finish(executable_exceptions(vm, method), method, constructor, parsed)
    return result

@unsafe def executable_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +method : M.LoadedMethod <- executable_method(vm, bits_of(receiver))
    +result : O.Outcome <- executable_plain_string(vm, method, executable_is_constructor(vm, entry))
    return result

@unsafe def field_plain_string(+vm: M.VM, +field: M.LoadedField, +type_name: String) -> Result<&2, &2, String, O.Outcome>:
  +prefix : String = modifier_prefix_text(U32.and(M.loaded_field_flags(field), 223))
  +owner_name : String = internal_to_binary(class_name_text(vm, M.loaded_field_owner(field)))
  intern_or_alloc(vm, units_from_string(prefix ++ type_name ++ " " ++ owner_name ++ "." ++ Sy.text(S.symbols(vm), M.loaded_field_name(field))))

@unsafe def field_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +value : M.JvmType <- D.parse_field(Sy.text(S.symbols(vm), M.loaded_field_descriptor(field)))
    +result : O.Outcome <- field_plain_string(vm, field, jvm_type_name(value))
    return result

@unsafe def field_generic_named(found: Result<&2, &2, String, TextsAt>, +field: M.LoadedField) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Fail{error}: Fail{error}
    case Done{TextsAt{+vm, texts}}: field_plain_string(vm, field, join_names(texts, ""))

@unsafe def field_to_generic_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +result : O.Outcome <- field_generic_named(outcome_reference_names(reflect_field_generic_type(vm, args)), field)
    return result

@unsafe def outcome_reference_names(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, TextsAt>:
  match result:
    case Done{O.Returned{+vm, Some{reference}}}: ref_names(vm, [bits_of(reference)], Nil{})
    case Done{other}: Fail{"InvalidState: expected a Type"}
    case Fail{error}: Fail{error}

# typeVarBounds: a type parameter prints its bounds unless the only bound is Object.
@unsafe def bound_clause(+name: String, +bounds: +List<String>) -> String:
  Bool.pick(String, String.eq(join_names(bounds, " & "), "java.lang.Object"), name, name ++ " extends " ++ join_names(bounds, " & "))

@unsafe def type_parameter_texts(+vm: M.VM, +refs: +List<U32>, +acc: +List<String>) -> Result<&2, &2, String, TextsAt>:
  match refs:
    case Nil{}: Done{TextsAt{vm, M.reverse(String, acc)}}
    case Con{reference, rest}:
      do Result<&2, &2, String, TextsAt>:
        +name : String <- string_text(vm, binding_ref(entry_at(vm, reference), 0))
        +result : TextsAt <- type_parameter_next(array_names(generic_type_array(type_variable_bounds_of(vm, entry_at(vm, reference)))), name, rest, acc)
        return result

@unsafe def type_parameter_next(named: Result<&2, &2, String, TextsAt>, +name: String, +refs: +List<U32>, +acc: +List<String>) -> Result<&2, &2, String, TextsAt>:
  match named:
    case Fail{error}: Fail{error}
    case Done{TextsAt{vm, bounds}}: type_parameter_texts(vm, refs, Con{bound_clause(name, bounds), acc})

@unsafe def type_parameter_block(+names: +List<String>) -> String:
  Bool.pick(String, U32.is_eq(M.length(String, names), 0), "", "<" ++ join_names(names, ",") ++ "> ")

@unsafe def generic_string_finish(+vm: M.VM, +prefix: String, +header: String, +params: +List<String>, +varargs: Bool, +exceptions: +List<String>) -> Result<&2, &2, String, O.Outcome>:
  intern_or_alloc(vm, units_from_string(prefix ++ header ++ "(" ++ join_names(varargs_names(varargs, params), ",") ++ ")" ++ throws_text(exceptions)))

@unsafe def generic_exception_names(result: Result<&2, &2, String, TextsAt>) -> Result<&2, &2, String, TextsAt>:
  result

@unsafe def generic_signature_parameters(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  +text : String = method_signature(vm, method)
  generic_parameters_text(vm, method, text, String.is_empty(text))

@unsafe def generic_signature_exceptions(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  +text : String = method_signature(vm, method)
  generic_exceptions_text(vm, method, text, String.is_empty(text))

@unsafe def generic_signature_return(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  +text : String = method_signature(vm, method)
  generic_return_text(vm, method, Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)), text, String.is_empty(text))

@unsafe def executable_generic_parameters(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +method : M.LoadedMethod <- executable_method(vm, bits_of(receiver))
    +result : O.Outcome <- generic_signature_parameters(vm, method)
    return result

@unsafe def executable_generic_exceptions(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +method : M.LoadedMethod <- executable_method(vm, bits_of(receiver))
    +result : O.Outcome <- generic_signature_exceptions(vm, method)
    return result

@unsafe def array_refs_of(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, ReflectRefs>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{+vm, Some{array}}}: Done{ReflectRefs{vm, slot_refs(entry_values(entry_at(vm, bits_of(array))))}}
    case Done{other}: Fail{"InvalidState: expected an array"}

@unsafe def type_parameter_names(found: Result<&2, &2, String, ReflectRefs>) -> Result<&2, &2, String, TextsAt>:
  match found:
    case Fail{error}: Fail{error}
    case Done{ReflectRefs{+vm, refs}}: type_parameter_texts(vm, refs, Nil{})

@unsafe def generic_stage_finish(found: Result<&2, &2, String, TextsAt>, +method: M.LoadedMethod, +constructor: Bool, +prefix: String, +params: +List<String>, +exceptions: +List<String>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Fail{error}: Fail{error}
    case Done{TextsAt{+vm, returned}}:
      +owner_name : String = executable_owner_name(vm, method)
      +header : String = Bool.pick(String, constructor, owner_name, join_names(returned, "") ++ " " ++ owner_name ++ "." ++ Sy.text(S.symbols(vm), M.loaded_method_name(method)))
      intern_or_alloc(vm, units_from_string(prefix ++ header ++ "(" ++ join_names(varargs_names(U32.is_ne(U32.and(M.loaded_method_flags(method), 128), 0), params), ",") ++ ")" ++ throws_text(exceptions)))

@unsafe def generic_return_texts(+vm: M.VM, +method: M.LoadedMethod, +constructor: Bool) -> Result<&2, &2, String, TextsAt>:
  Bool.pick(Result<&2, &2, String, TextsAt>, constructor, Done{TextsAt{vm, Nil{}}}, outcome_reference_names(generic_signature_return(vm, method)))

@unsafe def generic_stage_exceptions(found: Result<&2, &2, String, TextsAt>, +method: M.LoadedMethod, +constructor: Bool, +prefix: String, +params: +List<String>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Fail{error}: Fail{error}
    case Done{TextsAt{+vm, exceptions}}: generic_stage_finish(generic_return_texts(vm, method, constructor), method, constructor, prefix, params, exceptions)

@unsafe def generic_stage_parameters(found: Result<&2, &2, String, TextsAt>, +method: M.LoadedMethod, +constructor: Bool, +prefix: String) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Fail{error}: Fail{error}
    case Done{TextsAt{+vm, params}}: generic_stage_exceptions(array_names(generic_signature_exceptions(vm, method)), method, constructor, prefix, params)

@unsafe def generic_stage_types(found: Result<&2, &2, String, TextsAt>, +method: M.LoadedMethod, +constructor: Bool) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Fail{error}: Fail{error}
    case Done{TextsAt{+vm, types}}: generic_stage_parameters(array_names(generic_signature_parameters(vm, method)), method, constructor, executable_prefix(vm, method, constructor) ++ type_parameter_block(types))

# toGenericString in the oracle JDK's format: modifiers, "<T extends B> ", the
# generic return type and qualified name, generic parameters (varargs as ...),
# and generic exceptions.
@unsafe def executable_to_generic_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +method : M.LoadedMethod <- executable_method(vm, bits_of(receiver))
    +result : O.Outcome <- generic_stage_types(type_parameter_names(array_refs_of(executable_type_parameters(vm, args))), method, executable_is_constructor(vm, entry))
    return result

def modifier_test(+vm: M.VM, +args: +List<M.Slot>, +bit: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +flags : M.Slot <- slot0(args)
    result : O.Outcome <- bool_out(vm, U32.is_ne(U32.and(bits_of(flags), bit), 0))
    return result

def modifier_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +flags : M.Slot <- slot0(args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(modifier_text(bits_of(flags))))
    return result

# --- Security manager and privileged actions (plan 03, C11) ---
# There is no security manager, as on JDK 24+ and in an unrestricted Java 8 VM,
# so privileged actions simply run on the caller's stack.

def security_manager(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  ref_out(vm, 0)

def privileged_run(+vm: M.VM, +action: U32) -> Result<&2, &2, String, M.LoadedMethod>:
  do Result<&2, &2, String, M.LoadedMethod>:
    checked : Unit <- S.check(U32.is_ne(action, 0), npe())
    method : M.LoadedMethod <- S.require(M.LoadedMethod, virtual_on(vm, action, "run", "()Ljava/lang/Object;"), "java/lang/AbstractMethodError")
    return method

# doPrivileged(PrivilegedAction[, context]): the action's exceptions propagate unchanged.
def do_privileged(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +action : M.Slot <- slot0(args)
    method : M.LoadedMethod <- privileged_run(vm, bits_of(action))
    return O.Call{vm, method, [M.Slot{3, bits_of(action)}]}

# doPrivileged(PrivilegedExceptionAction[, context]): a checked exception leaving
# run() is wrapped in PrivilegedActionException at the PrivilegedCall boundary.
def do_privileged_exception(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +action : M.Slot <- slot0(args)
    method : M.LoadedMethod <- privileged_run(vm, bits_of(action))
    return O.Call{S.with_effect(vm, M.PrivilegedCall{}), method, [M.Slot{3, bits_of(action)}]}

def access_control_context_alloc(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}: ref_out(updated, reference)

def access_control_context(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  access_control_context_alloc(H.allocate(vm, H.object_entry(class_id(vm, "java/security/AccessControlContext"), Nil{})))

# PrivilegedActionException(Exception) has a null message and the exception as its cause.
def privileged_exception_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +cause : M.Slot <- slot1(args)
    result : O.Outcome <- throwable_init(vm, args, 0, bits_of(cause), 1)
    return result

# --- JDK field accessor messages (plan 03, C4) ---

# Field.getType().getName() from a field descriptor.
@unsafe def field_type_get_name(+descriptor: String) -> String:
  match descriptor:
    case SCon{Chr{91}, rest}: class_display_name(descriptor)
    case SCon{Chr{76}, rest}: internal_to_binary(CL.take_until_semicolon(rest, ""))
    case other: primitive_descriptor_name(other)

@unsafe def attempted_text(+attempted_type: String, +attempted_value: String) -> String:
  Bool.pick(String, Bool.not(String.is_empty(attempted_value)), "(" ++ attempted_type ++ ")" ++ attempted_value,
    Bool.pick(String, Bool.not(String.is_empty(attempted_type)), attempted_type, "null value"))

@unsafe def field_qualified_name(+vm: M.VM, +field: M.LoadedField) -> String:
  class_display_name(class_name_text(vm, M.loaded_field_owner(field))) ++ "." ++ Sy.text(S.symbols(vm), M.loaded_field_name(field))

# FieldAccessorImpl.getSetMessage.
@unsafe def field_set_message(+vm: M.VM, +field: M.LoadedField, +attempted_type: String, +attempted_value: String) -> String:
  +flags : U32 = M.loaded_field_flags(field)
  "Can not set" ++ Bool.pick(String, U32.is_ne(U32.and(flags, 8), 0), " static", "") ++ Bool.pick(String, U32.is_ne(U32.and(flags, 16), 0), " final", "") ++
    " " ++ field_type_get_name(Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))) ++ " field " ++ field_qualified_name(vm, field) ++ " to " ++
    attempted_text(attempted_type, attempted_value)

@unsafe def object_type_name_entry(+vm: M.VM, result: Result<&2, &2, String, M.HeapEntry>) -> String:
  match result:
    case Fail{error}: ""
    case Done{entry}: class_display_name(class_name_text(vm, H.entry_class(entry)))

# The attempted type of a reference value: its class name, or "" for null.
@unsafe def object_type_name(+vm: M.VM, +reference: U32) -> String:
  match reference:
    case 0: ""
    case +ref: object_type_name_entry(vm, H.get(S.heap(vm), ref))

# ensureObj: an instance field needs a receiver of its declaring class.
@unsafe def field_receiver_verdict(belongs: Bool, +vm: M.VM, +field: M.LoadedField, +target: U32) -> Result<&2, &2, String, Unit>:
  match belongs:
    case True{}: Done{Unit{}}
    case False{}: Fail{"java/lang/IllegalArgumentException: " ++ field_set_message(vm, field, object_type_name(vm, target), "")}

@unsafe def field_receiver_entry(+vm: M.VM, +field: M.LoadedField, +target: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}: field_receiver_verdict(H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), M.loaded_field_owner(field)), vm, field, target)

@unsafe def field_receiver_instance(+vm: M.VM, +field: M.LoadedField, +target: U32) -> Result<&2, &2, String, Unit>:
  match target:
    case 0: Fail{npe()}
    case +ref: field_receiver_entry(vm, field, ref, H.get(S.heap(vm), ref))

@unsafe def field_receiver_static(static: Bool, +vm: M.VM, +field: M.LoadedField, +target: U32) -> Result<&2, &2, String, Unit>:
  match static:
    case True{}: Done{Unit{}}
    case False{}: field_receiver_instance(vm, field, target)

@unsafe def field_receiver_check(+vm: M.VM, +field: M.LoadedField, +target: U32) -> Result<&2, &2, String, Unit>:
  field_receiver_static(U32.is_ne(U32.and(M.loaded_field_flags(field), 8), 0), vm, field, target)

@unsafe def field_final_verdict(allowed: Bool, +vm: M.VM, +field: M.LoadedField, +attempted_type: String, +attempted_value: String) -> Result<&2, &2, String, Unit>:
  match allowed:
    case True{}: Done{Unit{}}
    case False{}: Fail{"java/lang/IllegalAccessException: " ++ field_set_message(vm, field, attempted_type, attempted_value)}

# Conversion failures carry the JDK's set message.
@unsafe def field_convert_message(result: Result<&2, &2, String, M.Slot>, +vm: M.VM, +field: M.LoadedField, +attempted_type: String, +attempted_value: String) -> Result<&2, &2, String, M.Slot>:
  match result:
    case Done{value}: Done{value}
    case Fail{+error}:
      Bool.pick(Result<&2, &2, String, M.Slot>, String.eq(error, "java/lang/IllegalArgumentException"),
        Fail{"java/lang/IllegalArgumentException: " ++ field_set_message(vm, field, attempted_type, attempted_value)}, Fail{error})

@unsafe def wide_attempt_value(+value: M.Slot, +source: U32) -> String:
  match source:
    case 74: wide_long_text(wide_words(value, 4))
    case 68: wide_double_text(wide_words(value, 5))
    case _: ""

@unsafe def wide_long_text(result: Result<&2, &2, String, W.Words>) -> String:
  match result:
    case Fail{error}: ""
    case Done{words}: W.long_show(words)

@unsafe def wide_double_text(result: Result<&2, &2, String, W.Words>) -> String:
  match result:
    case Fail{error}: ""
    case Done{words}: wide_double_show(B64.double_to_string(words))

@unsafe def wide_double_show(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Fail{error}: ""
    case Done{text}: text

@unsafe def source_type_name(+source: U32) -> String:
  match source:
    case 74: "long"
    case 68: "double"
    case 73: "int"
    case _: ""

@unsafe def field_type_gate(ok: Bool, raw: O.Outcome) -> Result<&2, &2, String, O.Outcome>:
  match ok:
    case True{}: Done{raw}
    case False{}: Fail{"java/lang/IllegalArgumentException"}

# FieldAccessorImpl.newGetIllegalArgumentException.
@unsafe def field_get_conversion(result: Result<&2, &2, String, O.Outcome>, +vm: M.VM, +field: M.LoadedField, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Done{outcome}: Done{outcome}
    case Fail{+error}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(error, "java/lang/IllegalArgumentException"),
        Fail{"java/lang/IllegalArgumentException: Attempt to get " ++ field_type_get_name(Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))) ++ " field \"" ++ field_qualified_name(vm, field) ++ "\" with illegal data type conversion to " ++ source_type_name(target)}, Fail{error})

# Class.newInstance (Java 8): the nullary declared constructor, checked like
# Constructor.newInstance, but exceptions from the constructor propagate
# unwrapped (the HandleConstructor boundary does not wrap them).
@unsafe def class_new_instance_invoke(+vm: M.VM, +method: M.LoadedMethod, +reference: U32) -> Result<&2, &2, String, O.Outcome>:
  Done{O.Call{S.with_effect(vm, M.HandleConstructor{reference}), method, [M.Slot{3, reference}]}}

@unsafe def class_new_instance_call(+vm: M.VM, +method: M.LoadedMethod, +owner: U32) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(owner, reflect_instance_fields(S.fields(vm), S.classes(vm), owner))), vm2 => reference => class_new_instance_invoke(vm2, method, reference))

@unsafe def class_new_instance(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    not_class : Unit <- S.check(U32.is_ne(target, class_id(vm, "java/lang/Class")), "java/lang/IllegalAccessException: Can not call newInstance() on the Class for java.lang.Class")
    +name : String = class_display_name(class_name_text(vm, target))
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, own_method(S.methods(vm), target, Sy.find(S.symbols(vm), "<init>"), Sy.find(S.symbols(vm), "()V")), "java/lang/InstantiationException: " ++ name)
    instantiable : Unit <- S.check(constructor_instantiable(vm, target) && Bool.not(primitive_name(class_name_text(vm, target))) && Bool.not(String.starts_with(class_name_text(vm, target), "[")), "java/lang/InstantiationException: " ++ name)
    checked : Unit <- reflect_constructor_access(vm, False{}, target, M.loaded_method_flags(method))
    result : O.Outcome <- class_new_instance_call(vm, method, target)
    return result

def take_until_semicolon_text(+text: String) -> String:
  CL.take_until_semicolon(text, "")

# The binary name of the outermost class enclosing `target` (by '$' nesting in
# InnerClasses), used by Java 8 Lookup.in for same-top-level private access.
@unsafe def outermost_name(+vm: M.VM, +target: U32) -> String:
  outermost_from(64n, vm, class_name_text(vm, target))

@unsafe def outermost_from(+fuel: Nat, +vm: M.VM, +name: String) -> String:
  match fuel:
    case 0n: name
    case 1n+p:
      +enclosing : String = enclosing_name(vm, class_id(vm, name))
      Bool.pick(String, String.is_empty(enclosing), name, outermost_from(p, vm, enclosing))

@unsafe def cast_failure(+vm: M.VM, +reference: U32, +target: String) -> String:
  "java/lang/ClassCastException: Cannot cast " ++ object_type_name(vm, reference) ++ " to " ++ field_type_get_name(target)

# --- Text joining with Java toString callbacks ---
# A rendered text is a list of literal units and references whose toString() is
# user code; text_join concatenates them, calling toString through NeedTextJoin.

@unsafe def text_join(+vm: M.VM, +acc: +List<U32>, +items: +List<M.TextItem>) -> Result<&2, &2, String, O.Outcome>:
  match items:
    case Nil{}: intern_or_alloc(vm, acc)
    case Con{M.TextUnits{units}, rest}: text_join(vm, M.append(U32, acc, units), rest)
    case Con{M.TextCall{reference}, rest}: text_join_call(vm, acc, reference, rest)
    case Con{M.TextThrow{reference}, rest}: throw_ref(vm, reference)

@unsafe def text_join_call(+vm: M.VM, +acc: +List<U32>, +reference: U32, +rest: +List<M.TextItem>) -> Result<&2, &2, String, O.Outcome>:
  match reference:
    case 0: text_join(vm, M.append(U32, acc, units_from_string("null")), rest)
    case +ref: call_virtual(push_cont(vm, M.NeedTextJoin{acc, rest}), virtual_on(vm, ref, "toString", "()Ljava/lang/String;"), [M.Slot{3, ref}])

@unsafe def continue_text_join(+vm: M.VM, +acc: +List<U32>, +items: +List<M.TextItem>, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  continue_text_join_ref(vm, acc, items, bits_of(value))

@unsafe def continue_text_join_ref(+vm: M.VM, +acc: +List<U32>, +items: +List<M.TextItem>, +reference: U32) -> Result<&2, &2, String, O.Outcome>:
  match reference:
    case 0: text_join(vm, M.append(U32, acc, units_from_string("null")), items)
    case +ref:
      do Result<&2, &2, String, O.Outcome>:
        +chars : +List<U32> <- string_chars(vm, ref)
        result : O.Outcome <- text_join(vm, M.append(U32, acc, chars), items)
        return result

# --- Annotation toString (JDK AnnotationInvocationHandler.toStringImpl) ---

type Rendered is Data:
  Rendered{vm: M.VM, items: +List<M.TextItem>}

@unsafe def text_of(+text: String) -> M.TextItem:
  M.TextUnits{units_from_string(text)}

@unsafe def lower_hex_digit(+value: U32) -> String:
  String.from_list([Chr{Bool.pick(U32, U32.is_lt(value, 10), U32.add(48, value), U32.add(87, value))}])

@unsafe def lower_hex(+value: U32, +digits: Nat) -> String:
  match digits:
    case 0n: ""
    case 1n+p: lower_hex(U32.shrn(value, 4n), p) ++ lower_hex_digit(U32.and(value, 15))

# quote(char): Java escapes; an apostrophe is escaped only as a char literal.
@unsafe def quote_unit(+unit: U32, +in_string: Bool) -> String:
  match unit:
    case 8: "\\b"
    case 12: "\\f"
    case 10: "\\n"
    case 13: "\\r"
    case 9: "\\t"
    case 34: "\\\""
    case 92: "\\\\"
    case 39: Bool.pick(String, in_string, "'", "\\'")
    case +other: Bool.pick(String, U32.is_ge(other, 32) && U32.is_le(other, 126), String.from_list([Chr{other}]), "\\u" ++ lower_hex(other, 4n))

@unsafe def quoted_units(+units: +List<U32>) -> String:
  match units:
    case Nil{}: ""
    case Con{+unit, rest}: quote_unit(unit, True{}) ++ quoted_units(rest)

@unsafe def float_source(+bits: U32) -> String:
  +special : Bool = U32.is_eq(U32.and(bits, 2139095040), 2139095040)
  +nan : Bool = special && U32.is_ne(U32.and(bits, 8388607), 0)
  Bool.pick(String, nan, "0.0f/0.0f",
    Bool.pick(String, special, Bool.pick(String, V.negative(bits), "-1.0f/0.0f", "1.0f/0.0f"), float_text(bits) ++ "f"))

@unsafe def double_source(+words: W.Words) -> String:
  match words:
    case W.Words{+high, +low}:
      +special : Bool = U32.is_eq(U32.and(high, 2146435072), 2146435072)
      +nan : Bool = special && (U32.is_ne(U32.and(high, 1048575), 0) || U32.is_ne(low, 0))
      Bool.pick(String, nan, "0.0/0.0",
        Bool.pick(String, special, Bool.pick(String, V.negative(high), "-1.0/0.0", "1.0/0.0"), wide_double_show(B64.double_to_string(W.Words{high, low}))))

@unsafe def class_source_component(+vm: M.VM, +descriptor: String, +brackets: String) -> String:
  match descriptor:
    case SCon{Chr{91}, rest}: class_source_component(vm, rest, brackets ++ "[]")
    case SCon{Chr{76}, rest}: class_source_named(vm, take_until_semicolon_text(rest)) ++ brackets ++ ".class"
    case other: primitive_descriptor_name(other) ++ brackets ++ ".class"

@unsafe def class_source_named(+vm: M.VM, +name: String) -> String:
  class_source_found(canonical_name(64n, vm, name))

@unsafe def class_source_found(found: Maybe<&2, String>) -> String:
  match found:
    case Some{text}: text
    case None{}: "<no canonical name>"

# toSourceString(Class): canonical name, array brackets, then ".class".
@unsafe def class_source(+vm: M.VM, +target: U32) -> String:
  +name : String = class_name_text(vm, target)
  Bool.pick(String, String.starts_with(name, "["), class_source_component(vm, name, ""),
    Bool.pick(String, primitive_name(name), name ++ ".class", class_source_named(vm, name) ++ ".class"))

@unsafe def mirror_source(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    return class_source(vm, entry_element(entry))

@unsafe def enum_constant_name(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    +name : String <- string_text(vm, field_bits(entry_fields(entry), 0))
    return name

@unsafe def enum_overrides_to_string(+vm: M.VM, +reference: U32) -> Bool:
  enum_override_found(virtual_on(vm, reference, "toString", "()Ljava/lang/String;"), class_id(vm, "java/lang/Enum"))

@unsafe def enum_override_found(found: Maybe<&2, M.LoadedMethod>, +enum_class: U32) -> Bool:
  match found:
    case None{}: False{}
    case Some{method}: U32.is_ne(M.loaded_method_owner(method), enum_class)

@unsafe def rendered_text(+vm: M.VM, +text: Result<&2, &2, String, String>) -> Result<&2, &2, String, Rendered>:
  match text:
    case Fail{error}: Fail{error}
    case Done{value}: Done{Rendered{vm, [text_of(value)]}}

# A non-array enum member prints its toString(); array elements print name().
@unsafe def render_enum(+vm: M.VM, +reference: U32, +in_array: Bool) -> Result<&2, &2, String, Rendered>:
  render_enum_select(Bool.not(in_array) && enum_overrides_to_string(vm, reference), vm, reference)

@unsafe def render_enum_select(call: Bool, +vm: M.VM, +reference: U32) -> Result<&2, &2, String, Rendered>:
  match call:
    case True{}: Done{Rendered{vm, [M.TextCall{reference}]}}
    case False{}: rendered_text(vm, enum_constant_name(vm, reference))

@unsafe def render_reference(+vm: M.VM, +descriptor: String, +reference: U32, +in_array: Bool) -> Result<&2, &2, String, Rendered>:
  match descriptor:
    case "Ljava/lang/String;":
      do Result<&2, &2, String, Rendered>:
        +units : +List<U32> <- string_chars(vm, reference)
        return Rendered{vm, [text_of("\"" ++ quoted_units(units) ++ "\"")]}
    case "Ljava/lang/Class;": rendered_text(vm, mirror_source(vm, reference))
    case _: render_object(vm, reference, in_array)

@unsafe def render_object_entry(+vm: M.VM, +reference: U32, +in_array: Bool, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, Rendered>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+entry}: render_object_kind(entry_kind(entry), vm, reference, in_array)

@unsafe def render_object_kind(kind: U32, +vm: M.VM, +reference: U32, +in_array: Bool) -> Result<&2, &2, String, Rendered>:
  match kind:
    case 9: annotation_render(vm, reference)
    case _: render_enum(vm, reference, in_array)

@unsafe def render_object(+vm: M.VM, +reference: U32, +in_array: Bool) -> Result<&2, &2, String, Rendered>:
  render_object_entry(vm, reference, in_array, H.get(S.heap(vm), reference))

@unsafe def render_wide(+descriptor: String, +slot: M.Slot) -> Result<&2, &2, String, String>:
  match descriptor:
    case "J":
      do Result<&2, &2, String, String>:
        +words : W.Words <- wide_words(slot, 4)
        return W.long_show(words) ++ "L"
    case _:
      do Result<&2, &2, String, String>:
        +words : W.Words <- wide_words(slot, 5)
        return double_source(words)

@unsafe def render_scalar(+descriptor: String, +bits: U32) -> String:
  match descriptor:
    case "Z": Bool.pick(String, U32.is_ne(bits, 0), "true", "false")
    case "B": "(byte)0x" ++ lower_hex(U32.and(bits, 255), 2n)
    case "C": "'" ++ quote_unit(U32.and(bits, 65535), False{}) ++ "'"
    case "F": float_source(bits)
    case _: V.int_show(bits)

@unsafe def render_value(+vm: M.VM, +descriptor: String, +slot: M.Slot, +in_array: Bool) -> Result<&2, &2, String, Rendered>:
  match descriptor:
    case SCon{Chr{91}, +component}: render_array(vm, component, bits_of(slot))
    case SCon{Chr{76}, rest}: render_reference(vm, descriptor, bits_of(slot), in_array)
    case "J": rendered_text(vm, render_wide("J", slot))
    case "D": rendered_text(vm, render_wide("D", slot))
    case +other: Done{Rendered{vm, [text_of(render_scalar(other, bits_of(slot)))]}}

@unsafe def render_array(+vm: M.VM, +component: String, +reference: U32) -> Result<&2, &2, String, Rendered>:
  do Result<&2, &2, String, Rendered>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    +inner : Rendered <- render_elements(vm, component, entry_values(entry), True{})
    return rendered_wrap(inner, "{", "}")

@unsafe def rendered_wrap(+inner: Rendered, +open: String, +close: String) -> Rendered:
  match inner:
    case Rendered{+vm, +items}: Rendered{vm, Con{text_of(open), M.append(M.TextItem, items, [text_of(close)])}}

@unsafe def rendered_append(+first: Rendered, +rest: Result<&2, &2, String, Rendered>) -> Result<&2, &2, String, Rendered>:
  match first rest:
    case _ Fail{error}: Fail{error}
    case Rendered{_, head} Done{Rendered{vm, tail}}: Done{Rendered{vm, M.append(M.TextItem, head, tail)}}

@unsafe def render_elements(+vm: M.VM, +component: String, +values: +List<M.Slot>, +first: Bool) -> Result<&2, &2, String, Rendered>:
  match values:
    case Nil{}: Done{Rendered{vm, Nil{}}}
    case Con{+slot, rest}:
      do Result<&2, &2, String, Rendered>:
        +rendered : Rendered <- render_value(vm, component, slot, True{})
        +separated : Rendered = rendered_prefix(rendered, Bool.pick(String, first, "", ", "))
        +result : Rendered <- rendered_append(separated, render_elements(rendered_vm(separated), component, rest, False{}))
        return result

@unsafe def rendered_vm(+value: Rendered) -> M.VM:
  match value:
    case Rendered{+vm, +items}: vm

@unsafe def rendered_prefix(+value: Rendered, +prefix: String) -> Rendered:
  match value:
    case Rendered{+vm, +items}: Rendered{vm, Con{text_of(prefix), items}}

# HashMap iteration order of the member defaults (AnnotationType.memberDefaults,
# a HashMap(0)), which LinkedHashMap(memberDefaults) preserves in memberValues.
@unsafe def hash_capacity(+count: U32, +capacity: U32) -> U32:
  hash_capacity_fits(U32.is_le(U32.mul(count, 4), U32.mul(capacity, 3)), count, capacity)

@unsafe def hash_capacity_fits(fits: Bool, +count: U32, +capacity: U32) -> U32:
  match fits:
    case True{}: capacity
    case False{}: hash_capacity(count, U32.mul(capacity, 2))

@unsafe def member_bucket(+vm: M.VM, +method: M.LoadedMethod, +capacity: U32) -> U32:
  +hash : U32 = units_hash(units_from_string(Sy.text(S.symbols(vm), M.loaded_method_name(method))))
  U32.and(U32.xor(hash, U32.shrn(hash, 16n)), U32.sub(capacity, 1))

type Bucketed is Data:
  Bucketed{bucket: U32, method: M.LoadedMethod}

@unsafe def bucketed_insert(+item: Bucketed, +sorted: +List<Bucketed>) -> +List<Bucketed>:
  match sorted:
    case Nil{}: [item]
    case Con{+head, rest}: bucketed_insert_step(U32.is_lt(bucketed_key(item), bucketed_key(head)), item, head, rest)

@unsafe def bucketed_insert_step(before: Bool, +item: Bucketed, +head: Bucketed, +rest: +List<Bucketed>) -> +List<Bucketed>:
  match before:
    case True{}: Con{item, Con{head, rest}}
    case False{}: Con{head, bucketed_insert(item, rest)}

@unsafe def bucketed_key(+item: Bucketed) -> U32:
  match item:
    case Bucketed{bucket, method}: bucket

@unsafe def bucketed_method(+item: Bucketed) -> M.LoadedMethod:
  match item:
    case Bucketed{bucket, method}: method

@unsafe def bucketed_methods(+items: +List<Bucketed>) -> +List<M.LoadedMethod>:
  match items:
    case Nil{}: Nil{}
    case Con{+item, rest}: Con{bucketed_method(item), bucketed_methods(rest)}

# Insertion keeps declaration order within a bucket (a stable sort).
@unsafe def bucket_sort(+vm: M.VM, +methods: +List<M.LoadedMethod>, +capacity: U32, +sorted: +List<Bucketed>) -> +List<M.LoadedMethod>:
  match methods:
    case Nil{}: bucketed_methods(sorted)
    case Con{+method, rest}: bucket_sort(vm, rest, capacity, bucketed_insert_last(Bucketed{member_bucket(vm, method, capacity), method}, sorted))

@unsafe def bucketed_insert_last(+item: Bucketed, +sorted: +List<Bucketed>) -> +List<Bucketed>:
  M.reverse(Bucketed, bucketed_insert_reversed(item, M.reverse(Bucketed, sorted)))

# Insert into a list sorted descending (the reversed ascending list) after every
# element with a smaller-or-equal bucket, so equal buckets keep insertion order.
@unsafe def bucketed_insert_reversed(+item: Bucketed, +sorted: +List<Bucketed>) -> +List<Bucketed>:
  match sorted:
    case Nil{}: [item]
    case Con{+head, rest}: bucketed_reversed_step(U32.is_ge(bucketed_key(item), bucketed_key(head)), item, head, rest)

@unsafe def bucketed_reversed_step(stop: Bool, +item: Bucketed, +head: Bucketed, +rest: +List<Bucketed>) -> +List<Bucketed>:
  match stop:
    case True{}: Con{item, Con{head, rest}}
    case False{}: Con{head, bucketed_insert_reversed(item, rest)}

@unsafe def member_has_default(+vm: M.VM, +method: M.LoadedMethod) -> Bool:
  default_present(AR.default_metadata(S.metadata(vm), M.loaded_method_id(method)))

@unsafe def default_present(found: Maybe<&2, M.AnnotationValue>) -> Bool:
  match found:
    case Some{value}: True{}
    case None{}: False{}

@unsafe def default_members(+vm: M.VM, +methods: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match methods:
    case Nil{}: Nil{}
    case Con{+method, rest}: default_member_step(member_has_default(vm, method), method, default_members(vm, rest))

@unsafe def default_member_step(keep: Bool, +method: M.LoadedMethod, +rest: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match keep:
    case True{}: Con{method, rest}
    case False{}: rest

# Explicit members without a default, in the order the class file lists them.
@unsafe def explicit_members(+vm: M.VM, +bindings: +List<M.Binding>) -> +List<M.LoadedMethod>:
  match bindings:
    case Nil{}: Nil{}
    case Con{M.Binding{id, slot}, rest}: explicit_member_step(M.nth(M.LoadedMethod, S.methods(vm), id), vm, explicit_members(vm, rest))

@unsafe def explicit_member_step(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +rest: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match found:
    case None{}: rest
    case Some{+method}: default_member_step(Bool.not(member_has_default(vm, method)), method, rest)

@unsafe def annotation_member_order(+vm: M.VM, +owner: U32, +bindings: +List<M.Binding>) -> +List<M.LoadedMethod>:
  +defaults : +List<M.LoadedMethod> = default_members(vm, AR.member_methods(S.methods(vm), owner, S.symbols(vm)))
  +capacity : U32 = hash_capacity(M.length(M.LoadedMethod, defaults), 2)
  M.append(M.LoadedMethod, bucket_sort(vm, defaults, capacity, Nil{}), explicit_members(vm, bindings))

@unsafe def render_member_value(value: AR.Value, +descriptor: String) -> Result<&2, &2, String, Rendered>:
  match value:
    case AR.Value{vm, M.Slot{99, reference}}: Done{Rendered{vm, [M.TextThrow{reference}]}}
    case AR.Value{+vm, +slot}: render_value(vm, descriptor, slot, False{})

@unsafe def render_members(+vm: M.VM, +members: +List<M.LoadedMethod>, +bindings: +List<M.Binding>, +lone: Bool, +first: Bool) -> Result<&2, &2, String, Rendered>:
  match members:
    case Nil{}: Done{Rendered{vm, Nil{}}}
    case Con{+method, rest}:
      do Result<&2, &2, String, Rendered>:
        +name : String = Sy.text(S.symbols(vm), M.loaded_method_name(method))
        +value : AR.Value <- AR.effective(vm, method, H.binding_find(bindings, M.loaded_method_id(method)))
        +rendered : Rendered <- render_member_value(value, AR.descriptor(AR.value_vm(value), method))
        +label : String = Bool.pick(String, first, "", ", ") ++ Bool.pick(String, lone && String.eq(name, "value"), "", name ++ "=")
        +labeled : Rendered = rendered_prefix(rendered, label)
        +result : Rendered <- rendered_append(labeled, render_members(rendered_vm(labeled), rest, bindings, False{}, False{}))
        return result

@unsafe def annotation_render(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, Rendered>:
  do Result<&2, &2, String, Rendered>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    +owner : U32 = entry_element(entry)
    +bindings : +List<M.Binding> = entry_fields(entry)
    +members : +List<M.LoadedMethod> = annotation_member_order(vm, owner, bindings)
    +lone : Bool = U32.is_eq(M.length(M.LoadedMethod, members), 1)
    +inner : Rendered <- render_members(vm, members, bindings, lone, True{})
    return rendered_wrap(inner, "@" ++ class_source_named(vm, class_name_text(vm, owner)) ++ "(", ")")

@unsafe def annotation_to_string_rendered(result: Result<&2, &2, String, Rendered>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Rendered{+vm, +items}}: text_join(vm, Nil{}, items)

@unsafe def annotation_to_string(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, O.Outcome>:
  annotation_to_string_rendered(annotation_render(vm, reference))

@unsafe def float_text(+bits: U32) -> String:
  float_text_special(bits, U32.is_eq(U32.and(bits, 2139095040), 2139095040))

@unsafe def float_text_special(+bits: U32, special: Bool) -> String:
  match special:
    case False{}: float_text_decimal(F32.show(V.from_bits(bits)))
    case True{}: Bool.pick(String, U32.is_ne(U32.and(bits, 8388607), 0), "NaN", Bool.pick(String, V.negative(bits), "-Infinity", "Infinity"))

@unsafe def float_text_decimal(+text: String) -> String:
  Bool.pick(String, String.contains(text, ".") || String.contains(text, "e") || String.contains(text, "E"), text, text ++ ".0")

# --- java.lang.Enum: compareTo and getDeclaringClass ---

# getDeclaringClass: a constant with a body is an anonymous subclass of its enum.
@unsafe def enum_declaring_id(+vm: M.VM, +class: U32) -> U32:
  +parent : U32 = enum_parent_id(vm, class)
  Bool.pick(U32, U32.is_eq(parent, class_id(vm, "java/lang/Enum")), class, parent)

@unsafe def enum_parent_id(+vm: M.VM, +class: U32) -> U32:
  class_parent_found(M.nth(M.LoadedClass, S.classes(vm), class))

@unsafe def enum_declaring_class(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    result : O.Outcome <- class_mirror_out(vm, enum_declaring_id(vm, H.entry_class(entry)))
    return result

@unsafe def enum_compare(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +other : M.Slot <- slot1(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(other), 0), npe())
    +left : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +right : M.HeapEntry <- H.get(S.heap(vm), bits_of(other))
    same : Unit <- S.check(U32.is_eq(enum_declaring_id(vm, H.entry_class(left)), enum_declaring_id(vm, H.entry_class(right))), "java/lang/ClassCastException")
    result : O.Outcome <- int_out(vm, U32.sub(field_bits(entry_fields(left), 1), field_bits(entry_fields(right), 1)))
    return result

# Array clone(): a shallow copy with the same class and element type.
@unsafe def array_clone(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(receiver), 0), npe())
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +result : O.Outcome <- alloc_result(H.allocate(vm, entry), vm2 => reference => ref_out(vm2, reference))
    return result

# AbstractCollection.toString for the MiniJRE lists: "[a, b]", elements by
# their toString(), "(this Collection)" for the list itself, "null" for null.
@unsafe def list_element_items(+vm: M.VM, +list: U32, +values: +List<M.Slot>, +first: Bool) -> +List<M.TextItem>:
  match values:
    case Nil{}: [M.TextUnits{units_from_string("]")}]
    case Con{+slot, rest}:
      Con{M.TextUnits{units_from_string(Bool.pick(String, first, "", ", "))}, Con{list_element_item(vm, list, bits_of(slot)), list_element_items(vm, list, rest, False{})}}

@unsafe def list_element_item(+vm: M.VM, +list: U32, +reference: U32) -> M.TextItem:
  Bool.pick(M.TextItem, U32.is_eq(reference, list), M.TextUnits{units_from_string("(this Collection)")}, string_or_call(vm, reference, H.get(S.heap(vm), reference)))

@unsafe def string_or_call(+vm: M.VM, +reference: U32, found: Result<&2, &2, String, M.HeapEntry>) -> M.TextItem:
  match found:
    case Done{+entry}: Bool.pick(M.TextItem, U32.is_eq(entry_kind(entry), 3), M.TextUnits{entry_chars(entry)}, M.TextCall{reference})
    case Fail{error}: M.TextCall{reference}

@unsafe def list_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +values : +List<M.Slot> = M.take(M.Slot, entry_values(entry), U32.to_nat(entry_element(entry)))
    +result : O.Outcome <- text_join(vm, units_from_string("["), list_element_items(vm, bits_of(receiver), values, True{}))
    return result

# --- AnnotatedType family (plan 03, C3) ---
# An annotated type is an instance of one of the JDK's AnnotatedTypeFactory
# impl classes with bindings 0 member (field, method or class id), 1 site (the
# type annotation target type), 2 site index, 3 type path (int[] of packed
# steps, or null) and 4 the Type it annotates. Its annotations are the member's
# type annotations at that site, index and path.

@unsafe def annotated_impl_for(+vm: M.VM, +type_ref: U32) -> String:
  annotated_impl_entry(H.get(S.heap(vm), type_ref), vm)

@unsafe def annotated_impl_entry(found: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM) -> String:
  match found:
    case Fail{error}: "sun/reflect/annotation/AnnotatedTypeFactory$AnnotatedTypeBaseImpl"
    case Done{+entry}: annotated_impl_named(class_name_text(vm, H.entry_class(entry)), U32.is_eq(entry_kind(entry), 8) && String.starts_with(class_name_text(vm, entry_element(entry)), "["))

@unsafe def annotated_impl_named(+name: String, +array_class: Bool) -> String:
  Bool.pick(String, String.eq(name, "sun/reflect/generics/reflectiveObjects/ParameterizedTypeImpl"), "sun/reflect/annotation/AnnotatedTypeFactory$AnnotatedParameterizedTypeImpl",
    Bool.pick(String, String.eq(name, "sun/reflect/generics/reflectiveObjects/WildcardTypeImpl"), "sun/reflect/annotation/AnnotatedTypeFactory$AnnotatedWildcardTypeImpl",
      Bool.pick(String, String.eq(name, "sun/reflect/generics/reflectiveObjects/TypeVariableImpl"), "sun/reflect/annotation/AnnotatedTypeFactory$AnnotatedTypeVariableImpl",
        Bool.pick(String, String.eq(name, "sun/reflect/generics/reflectiveObjects/GenericArrayTypeImpl") || array_class, "sun/reflect/annotation/AnnotatedTypeFactory$AnnotatedArrayTypeImpl",
          "sun/reflect/annotation/AnnotatedTypeFactory$AnnotatedTypeBaseImpl"))))

@unsafe def new_annotated(+vm: M.VM, +member: U32, +site: U32, +index: U32, +path: U32, +type_ref: U32) -> Result<&2, &2, String, G.TypeRef>:
  G.alloc_ref(H.allocate(vm, H.object_entry(class_id(vm, annotated_impl_for(vm, type_ref)), [M.Binding{0, M.Slot{1, member}}, M.Binding{1, M.Slot{1, site}}, M.Binding{2, M.Slot{1, index}}, M.Binding{3, M.Slot{3, path}}, M.Binding{4, M.Slot{3, type_ref}}])))

@unsafe def type_ref_out(result: Result<&2, &2, String, G.TypeRef>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{G.TypeRef{vm, reference}}: ref_out(vm, reference)

# The reference an intrinsic returned, with its VM.
@unsafe def returned_ref(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, G.TypeRef>:
  match result:
    case Done{O.Returned{vm, Some{slot}}}: Done{G.TypeRef{vm, M.slot_bits(slot)}}
    case Done{O.ThrownName{vm, name}}: Fail{name}
    case Done{_}: Fail{"InvalidState: generic type query did not return"}
    case Fail{error}: Fail{error}

@unsafe def annotated_array(+vm: M.VM, +refs: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/reflect/AnnotatedType;"), class_id(vm, "java/lang/reflect/AnnotatedType"), annotated_ref_slots(refs))), vm2 => reference => ref_out(vm2, reference))

# One annotated type per Type in `types`; `step` is the path step to append
# (none for declaration sites whose index varies instead).
type AnnotatedSpec is Data:
  AnnotatedSpec{member: U32, site: U32, index: U32, indexStep: U32, path: U32, step: U32, stepStride: U32}

@unsafe def annotated_each(+vm: M.VM, +spec: AnnotatedSpec, +types: +List<U32>, +position: U32, +acc: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  match types:
    case Nil{}: annotated_array(vm, M.reverse(U32, acc))
    case Con{+type_ref, rest}:
      do Result<&2, &2, String, O.Outcome>:
        +child_path : G.TypeRef <- spec_path(vm, spec, position)
        +child : G.TypeRef <- spec_child(child_path, spec, position, type_ref)
        +result : O.Outcome <- annotated_each_next(child, spec, rest, position, acc)
        return result

@unsafe def annotated_each_next(+child: G.TypeRef, +spec: AnnotatedSpec, +rest: +List<U32>, +position: U32, +acc: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  match child:
    case G.TypeRef{+vm, +reference}: annotated_each(vm, spec, rest, U32.add(position, 1), Con{reference, acc})

@unsafe def spec_child(+path: G.TypeRef, +spec: AnnotatedSpec, +position: U32, +type_ref: U32) -> Result<&2, &2, String, G.TypeRef>:
  match path spec:
    case G.TypeRef{+vm, +path_ref} AnnotatedSpec{member, site, index, indexStep, old_path, step, stride}:
      new_annotated(vm, member, site, U32.add(index, U32.mul(position, indexStep)), path_ref, type_ref)

# The child's path: the parent's steps plus step + position * stride (or the
# parent's path when there is no step).
@unsafe def spec_path(+vm: M.VM, +spec: AnnotatedSpec, +position: U32) -> Result<&2, &2, String, G.TypeRef>:
  match spec:
    case AnnotatedSpec{member, site, index, indexStep, path, step, stride}:
      Bool.pick(Result<&2, &2, String, G.TypeRef>, U32.is_eq(step, 4294967295), Done{G.TypeRef{vm, path}}, path_append(vm, path, U32.add(step, U32.mul(position, stride))))

@unsafe def path_values(+vm: M.VM, +path: U32) -> +List<M.Slot>:
  match path:
    case 0: Nil{}
    case +ref: path_entry_values(H.get(S.heap(vm), ref))

@unsafe def path_entry_values(found: Result<&2, &2, String, M.HeapEntry>) -> +List<M.Slot>:
  match found:
    case Fail{error}: Nil{}
    case Done{+entry}: entry_values(entry)

@unsafe def path_append(+vm: M.VM, +path: U32, +step: U32) -> Result<&2, &2, String, G.TypeRef>:
  G.alloc_ref(H.allocate(vm, H.primitive_array_entry(class_id(vm, "[I"), 10, M.append(M.Slot, path_values(vm, path), [M.Slot{1, step}]))))

@unsafe def annotated_receiver(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, M.HeapEntry>:
  do Result<&2, &2, String, M.HeapEntry>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    return entry

@unsafe def annotated_spec(+entry: M.HeapEntry, +step: U32, +stride: U32) -> AnnotatedSpec:
  +fields : +List<M.Binding> = entry_fields(entry)
  AnnotatedSpec{field_bits(fields, 0), field_bits(fields, 1), field_bits(fields, 2), 0, field_bits(fields, 3), step, stride}

@unsafe def array_refs(+vm: M.VM, +array: U32) -> +List<U32>:
  slot_bits(path_values(vm, array))

@unsafe def type_binding(+vm: M.VM, +type_ref: U32, +index: U32) -> U32:
  type_binding_entry(H.get(S.heap(vm), type_ref), index)

@unsafe def type_binding_entry(found: Result<&2, &2, String, M.HeapEntry>, +index: U32) -> U32:
  match found:
    case Fail{error}: 0
    case Done{+entry}: field_bits(entry_fields(entry), index)

# getAnnotatedActualTypeArguments: TYPE_ARGUMENT steps (kind 3, argument index).
@unsafe def annotated_actuals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- annotated_receiver(vm, args)
    +type_ref : U32 = field_bits(entry_fields(entry), 4)
    +result : O.Outcome <- annotated_each(vm, annotated_spec(entry, 768, 1), array_refs(vm, type_binding(vm, type_ref, 1)), 0, Nil{})
    return result

# getAnnotatedGenericComponentType: one ARRAY step (kind 0).
@unsafe def annotated_component(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- annotated_receiver(vm, args)
    +type_ref : U32 = field_bits(entry_fields(entry), 4)
    +component : G.TypeRef <- component_type(vm, type_ref)
    +path : G.TypeRef <- path_append(type_ref_vm(component), field_bits(entry_fields(entry), 3), 0)
    +child : G.TypeRef <- spec_child(path, annotated_spec(entry, 0, 0), 0, type_ref_reference(component))
    +result : O.Outcome <- type_ref_out(Done{child})
    return result

@unsafe def type_ref_vm(+value: G.TypeRef) -> M.VM:
  match value:
    case G.TypeRef{+vm, +reference}: vm

@unsafe def type_ref_reference(+value: G.TypeRef) -> U32:
  match value:
    case G.TypeRef{+vm, +reference}: reference

# A GenericArrayType's component, or an array class's component mirror.
@unsafe def component_type(+vm: M.VM, +type_ref: U32) -> Result<&2, &2, String, G.TypeRef>:
  do Result<&2, &2, String, G.TypeRef>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), type_ref)
    +result : G.TypeRef <- Bool.pick(Result<&2, &2, String, G.TypeRef>, U32.is_eq(entry_kind(entry), 8),
      returned_ref(class_mirror_out(vm, array_component_id(vm, class_name_text(vm, entry_element(entry))))),
      Done{G.TypeRef{vm, field_bits(entry_fields(entry), 0)}})
    return result

@unsafe def array_component_id(+vm: M.VM, +name: String) -> U32:
  match name:
    case SCon{Chr{91}, +rest}: class_id(vm, Bool.pick(String, String.starts_with(rest, "L"), take_until_semicolon_text(drop_first(rest)), Bool.pick(String, String.starts_with(rest, "["), rest, primitive_descriptor_name(rest))))
    case _: 4294967295

@unsafe def drop_first(+text: String) -> String:
  match text:
    case SCon{head, rest}: rest
    case SNil{}: ""

# getAnnotatedUpperBounds/getAnnotatedLowerBounds: one WILDCARD step (kind 2);
# an unbounded wildcard's upper bound is Object.
@unsafe def annotated_wildcard(+vm: M.VM, +args: +List<M.Slot>, +upper: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- annotated_receiver(vm, args)
    +type_ref : U32 = field_bits(entry_fields(entry), 4)
    +bounds : +List<U32> = array_refs(vm, type_binding(vm, type_ref, Bool.pick(U32, upper, 0, 1)))
    +lower : +List<U32> = array_refs(vm, type_binding(vm, type_ref, 1))
    +object : G.TypeRef <- returned_ref(class_mirror_out(vm, class_id(vm, "java/lang/Object")))
    +result : O.Outcome <- wildcard_bounds(object, entry, bounds, upper && chars_nonempty(lower))
    return result

# AnnotatedWildcardTypeImpl: the upper bound is implicit (Object, unannotated)
# whenever the wildcard has lower bounds.
@unsafe def wildcard_bounds(+object: G.TypeRef, +entry: M.HeapEntry, +bounds: +List<U32>, +implicit: Bool) -> Result<&2, &2, String, O.Outcome>:
  match object:
    case G.TypeRef{+vm, +reference}:
      implicit_or_bounds(implicit, vm, entry, reference, bounds)

# An unbounded wildcard's implicit Object bound carries no annotations (the
# JDK builds it at the base location with none), so it gets the empty site.
@unsafe def implicit_or_bounds(implicit: Bool, +vm: M.VM, +entry: M.HeapEntry, +object: U32, +bounds: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  match implicit:
    case True{}: annotated_each(vm, AnnotatedSpec{0, 4294967295, 0, 0, 0, 4294967295, 0}, [object], 0, Nil{})
    case False{}: annotated_each(vm, annotated_spec(entry, 512, 0), bounds, 0, Nil{})

# A type variable's annotated bounds come from its declaration: bound
# annotations (CLASS/METHOD_TYPE_PARAMETER_BOUND) at the variable's index; the
# class bound slot is skipped when the first bound is an interface.
@unsafe def variable_declaration(+vm: M.VM, +variable: U32) -> Result<&2, &2, String, VariableSite>:
  do Result<&2, &2, String, VariableSite>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), variable)
    +fields : +List<M.Binding> = entry_fields(entry)
    +label : String <- string_text(vm, field_bits(fields, 0))
    +kind : U32 = field_bits(fields, 1)
    +id : U32 = field_bits(fields, 2)
    +params : +List<Sig.TypeParam> <- variable_params(vm, kind, id)
    return VariableSite{kind, id, param_index(params, label, 0)}

type VariableSite is Data:
  VariableSite{kind: U32, id: U32, index: U32}

@unsafe def variable_params(+vm: M.VM, +kind: U32, +id: U32) -> Result<&2, &2, String, +List<Sig.TypeParam>>:
  match kind:
    case 1: Done{G.class_variables(class_signature(vm, id))}
    case _:
      do Result<&2, &2, String, +List<Sig.TypeParam>>:
        +method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), id), "java/lang/NoSuchMethodException")
        return G.method_variables(method_signature(vm, method))

@unsafe def param_index(+params: +List<Sig.TypeParam>, +label: String, +index: U32) -> U32:
  match params:
    case Nil{}: 0
    case Con{Sig.TypeParam{+name, bounds}, rest}: Bool.pick(U32, String.eq(name, label), index, param_index(rest, label, U32.add(index, 1)))

@unsafe def first_bound_interface(+vm: M.VM, +bounds: +List<U32>) -> Bool:
  match bounds:
    case Nil{}: False{}
    case Con{+first, rest}: bound_is_interface(vm, first)

@unsafe def bound_is_interface(+vm: M.VM, +bound: U32) -> Bool:
  bound_entry_interface(vm, H.get(S.heap(vm), bound))

# A bound is a Class (kind 8) or a ParameterizedType whose binding 0 is its raw class.
@unsafe def bound_entry_interface(+vm: M.VM, found: Result<&2, &2, String, M.HeapEntry>) -> Bool:
  match found:
    case Fail{error}: False{}
    case Done{+entry}: U32.is_ne(U32.and(class_flags(vm, Bool.pick(U32, U32.is_eq(entry_kind(entry), 8), entry_element(entry), field_bits(entry_fields(entry), 0))), 512), 0)

@unsafe def variable_annotated_bounds(+vm: M.VM, +variable: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +site : VariableSite <- variable_declaration(vm, variable)
    +bounds_array : G.TypeRef <- returned_ref(type_variable_bounds_lazy(vm, [M.Slot{3, variable}]))
    +result : O.Outcome <- variable_bounds_each(bounds_array, site)
    return result

@unsafe def variable_bounds_each(+bounds_array: G.TypeRef, +site: VariableSite) -> Result<&2, &2, String, O.Outcome>:
  match bounds_array site:
    case G.TypeRef{+vm, +array} VariableSite{+kind, +id, +index}:
      +bounds : +List<U32> = array_refs(vm, array)
      +start : U32 = Bool.pick(U32, first_bound_interface(vm, bounds), 1, 0)
      annotated_each(vm, AnnotatedSpec{id, Bool.pick(U32, U32.is_eq(kind, 1), 17, 18), U32.add(U32.mul(index, 256), start), 1, 0, 4294967295, 0}, bounds, 0, Nil{})

@unsafe def type_variable_annotated_bounds(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +result : O.Outcome <- variable_annotated_bounds(vm, bits_of(receiver))
    return result

@unsafe def annotated_variable_bounds(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- annotated_receiver(vm, args)
    +result : O.Outcome <- variable_annotated_bounds(vm, field_bits(entry_fields(entry), 4))
    return result

# Field.getAnnotatedType, Method.getAnnotatedReturnType/ParameterTypes and
# Class.getAnnotatedSuperclass/Interfaces start at their declaration sites.
@unsafe def field_annotated(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field : M.LoadedField <- reflect_field_member(vm, args)
    +type_ref : G.TypeRef <- returned_ref(reflect_field_generic_type(vm, args))
    +result : O.Outcome <- type_ref_out(site_annotated(type_ref, M.loaded_field_id(field), 19, 0))
    return result

@unsafe def site_annotated(+type_ref: G.TypeRef, +member: U32, +site: U32, +index: U32) -> Result<&2, &2, String, G.TypeRef>:
  match type_ref:
    case G.TypeRef{+vm, +reference}: new_annotated(vm, member, site, index, 0, reference)

@unsafe def method_annotated_return(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    +type_ref : G.TypeRef <- returned_ref(reflect_method_generic_return(vm, args))
    +result : O.Outcome <- type_ref_out(site_annotated(type_ref, M.loaded_method_id(method), 20, 0))
    return result

@unsafe def method_annotated_parameters(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    +types : G.TypeRef <- returned_ref(reflect_method_generic_parameter_types(vm, args))
    +result : O.Outcome <- site_each(types, M.loaded_method_id(method), 22)
    return result

@unsafe def site_each(+types: G.TypeRef, +member: U32, +site: U32) -> Result<&2, &2, String, O.Outcome>:
  match types:
    case G.TypeRef{+vm, +array}: annotated_each(vm, AnnotatedSpec{member, site, 0, 1, 0, 4294967295, 0}, array_refs(vm, array), 0, Nil{})

# Type annotations on a type variable's declaration (TypeVariable is an
# AnnotatedElement): CLASS_TYPE_PARAMETER or METHOD_TYPE_PARAMETER at its index.
@unsafe def variable_annotation_source(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    +receiver : M.Slot <- slot0(args)
    +site : VariableSite <- variable_declaration(vm, bits_of(receiver))
    +result : AnnotationMetadataRef <- variable_site_source(vm, site)
    return result

@unsafe def variable_site_source(+vm: M.VM, +site: VariableSite) -> Result<&2, &2, String, AnnotationMetadataRef>:
  match site:
    case VariableSite{+kind, +id, +index}: annotated_source(vm, id, Bool.pick(U32, U32.is_eq(kind, 1), 0, 1), index, Nil{})

@unsafe def class_type_annotation_source(+vm: M.VM, +class: U32, +target: U32, +index: U32, +expected: +List<U32>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    +class_metadata : M.ClassMetadata <- class_metadata_value(vm, class)
    +metadata : M.AnnotationMetadata = class_metadata_annotation_data(class_metadata)
    +annotations : +List<M.Annotation> = type_annotation_values(metadata_type_annotations(metadata), target, index, expected, Nil{})
    return AnnotationMetadataRef{vm, class_metadata_pool(class_metadata), M.AnnotationMetadata{0, Nil{}, annotations, Nil{}, Nil{}, None{}, Nil{}, Nil{}, Nil{}}}

@unsafe def class_metadata_annotation_data(+value: M.ClassMetadata) -> M.AnnotationMetadata:
  match value:
    case M.ClassMetadata{owner, flags, annotations, visible, pool, signature, nesting, source}: annotations

# The annotations of a site: fields (19), class sites (type parameters 0,
# supertypes 16, bounds 17), method sites (everything else).
@unsafe def annotated_source(+vm: M.VM, +member: U32, +target: U32, +index: U32, +expected: +List<U32>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  match target:
    case 4294967295: Done{AnnotationMetadataRef{vm, Nil{}, M.AnnotationMetadata{0, Nil{}, Nil{}, Nil{}, Nil{}, None{}, Nil{}, Nil{}, Nil{}}}}
    case 19: field_type_annotation_source(vm, member, target, index, expected)
    case 0: class_type_annotation_source(vm, member, target, index, expected)
    case 16: class_type_annotation_source(vm, member, target, index, expected)
    case 17: class_type_annotation_source(vm, member, target, index, expected)
    case _:
      do Result<&2, &2, String, AnnotationMetadataRef>:
        +method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), member), "java/lang/NoSuchMethodException")
        +result : AnnotationMetadataRef <- method_type_annotation_source(vm, method, target, index, expected)
        return result

@unsafe def variable_annotations(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +source : AnnotationMetadataRef <- variable_annotation_source(vm, args)
    +result : O.Outcome <- class_annotations_array_from(source)
    return result

@unsafe def variable_annotation(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +source : AnnotationMetadataRef <- variable_annotation_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    +result : O.Outcome <- class_annotation_one_from(source, name)
    return result

@unsafe def variable_annotation_present(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +source : AnnotationMetadataRef <- variable_annotation_source(vm, args)
    +name : String <- reflect_annotation_name(vm, args)
    +result : O.Outcome <- reflect_annotation_present_source(vm, source, name)
    return result
