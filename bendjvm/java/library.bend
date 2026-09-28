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
  ProxyCallPlan{allocation: H.Allocation, exceptions: +List<U32>}

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
  M.Slot{tag, bits} = slot
  bits

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

def proxy_box_primitive(+vm: M.VM, value: M.Slot, tag: U32) -> Result<&2, &2, String, ProxyBoxedValue>:
  match tag:
    case 90: proxy_box_alloc(vm, value, "java/lang/Boolean")
    case 66: proxy_box_alloc(vm, value, "java/lang/Byte")
    case 83: proxy_box_alloc(vm, value, "java/lang/Short")
    case 67: proxy_box_alloc(vm, value, "java/lang/Character")
    case 73: proxy_box_alloc(vm, value, "java/lang/Integer")
    case 70: proxy_box_alloc(vm, value, "java/lang/Float")
    case 74: Fail{"UnsupportedFeature: proxy long argument boxing"}
    case 68: Fail{"UnsupportedFeature: proxy double argument boxing"}
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
    case Some{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, +pool}}: Done{pool}

def proxy_class_pool(metadata: M.Metadata, owner: U32) -> Result<&2, &2, String, +List<M.Constant>>:
  match metadata:
    case M.Metadata{+classes, fields, methods}: proxy_class_pool_found(M.nth(M.ClassMetadata, classes, owner))

def proxy_annotation_exceptions(value: M.AnnotationMetadata) -> +List<U32>:
  match value:
    case M.AnnotationMetadata{+flags, +exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue}: exceptions

def proxy_method_exceptions_found(found: Maybe<&2, M.MethodMetadata>) -> Result<&2, &2, String, +List<U32>>:
  match found:
    case None{}: Fail{"InvalidState: missing method metadata"}
    case Some{M.MethodMetadata{owner, method, metadata}}: Done{proxy_annotation_exceptions(metadata)}

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

def proxy_call_plan(+vm: M.VM, method: M.LoadedMethod) -> Result<&2, &2, String, ProxyCallPlan>:
  match method:
    case M.LoadedMethod{+id, +owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      do Result<&2, &2, String, ProxyCallPlan>:
        pool : +List<M.Constant> <- proxy_class_pool(S.metadata(vm), owner)
        raw : +List<U32> <- proxy_metadata_exceptions(S.metadata(vm), id)
        exceptions : +List<U32> <- proxy_exception_ids(vm, pool, raw, Nil{})
        allocation : H.Allocation <- H.allocate(vm, H.object_entry(class_id(vm, "java/lang/reflect/Method"), [M.Binding{0, M.Slot{1, owner}}, M.Binding{1, M.Slot{1, id}}, M.Binding{2, M.Slot{1, 0}}]))
        return ProxyCallPlan{allocation, exceptions}

def proxy_call_array_after(boxed: ProxyBoxedArgs, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, method_ref: U32, +descriptor: String, +exceptions: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  match boxed:
    case ProxyBoxedArgs{+vm, +values}:
      alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/Object;"), class_id(vm, "java/lang/Object"), values)),
        array_vm => array_ref => Done{O.Call{S.with_effect(array_vm, M.ProxyCall{descriptor, exceptions}), handler_method, [M.Slot{3, handler}, M.Slot{3, proxy}, M.Slot{3, method_ref}, M.Slot{3, array_ref}]}})

def proxy_call_array_values(+vm: M.VM, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, method_ref: U32, +descriptor: String, +exceptions: +List<U32>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    parsed : M.Descriptor <- D.parse_method(descriptor)
    boxed : ProxyBoxedArgs <- proxy_box_args(D.parameter_types(parsed), values, vm, Nil{})
    result : O.Outcome <- proxy_call_array_after(boxed, handler, proxy, handler_method, method_ref, descriptor, exceptions)
    return result

def proxy_call_array(+vm: M.VM, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, method_ref: U32, +descriptor: String, +exceptions: +List<U32>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  proxy_call_array_values(vm, handler, proxy, handler_method, method_ref, descriptor, exceptions, M.drop(M.Slot, values, 1n))

def proxy_call_method_alloc(allocation: H.Allocation, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, +descriptor: String, +exceptions: +List<U32>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case H.Allocation{+vm, reference}: proxy_call_array(vm, handler, proxy, handler_method, reference, descriptor, exceptions, values)

def proxy_call_plan_ready(plan: ProxyCallPlan, +handler: U32, +proxy: U32, handler_method: M.LoadedMethod, +descriptor: String, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match plan:
    case ProxyCallPlan{+allocation, +exceptions}: proxy_call_method_alloc(allocation, handler, proxy, handler_method, descriptor, exceptions, values)

def proxy_call_ready(+vm: M.VM, +handler: U32, +proxy: U32, method: M.LoadedMethod, +descriptor: String, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    handler_method : M.LoadedMethod <- proxy_handler_method(vm, handler)
    plan : ProxyCallPlan <- proxy_call_plan(vm, method)
    result : O.Outcome <- proxy_call_plan_ready(plan, handler, proxy, handler_method, descriptor, values)
    return result

def proxy_binding_set(xs: +List<M.Binding>, +id: U32, +value: M.Slot) -> +List<M.Binding>:
  match xs:
    case Nil{}: [M.Binding{id, value}]
    case Con{M.Binding{+binding_id, old}, rest}:
      Con{M.Binding{binding_id, Bool.pick(M.Slot, U32.is_eq(binding_id, id), value, old)}, proxy_binding_set(rest, id, value)}

def proxy_hash_slots(values: +List<M.Slot>, acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case Con{M.Slot{tag, bits}, rest}: proxy_hash_slots(rest, U32.add(U32.mul(31, acc), U32.add(tag, bits)))

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
    case Some{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, pool}}: flags

def proxy_class_flags(metadata: M.Metadata, target: U32) -> U32:
  match metadata:
    case M.Metadata{classes, fields, methods}: proxy_class_flags_found(M.nth(M.ClassMetadata, classes, target))

def proxy_id_seen(ids: +List<U32>, +target: U32) -> Bool:
  match ids:
    case Nil{}: False{}
    case Con{head, rest}: Bool.or(U32.is_eq(head, target), proxy_id_seen(rest, target))

def proxy_package_scan(chars: +List<Char>, +before: String, +segment: +List<Char>) -> String:
  match chars:
    case Nil{}: before
    case Con{Chr{47}, tail}: proxy_package_scan(tail, before ++ String.from_list(M.reverse(Char, segment)) ++ "/", Nil{})
    case Con{head, tail}: proxy_package_scan(tail, before, Con{head, segment})

def proxy_class_package(+vm: M.VM, target: U32) -> String:
  proxy_package_scan(String.to_list(class_name_text(vm, target)), "", Nil{})

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
    case M.LoadedMethod{id, owner, +name, +descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
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

def proxy_validate_methods(fuel: Nat, +methods: +List<M.LoadedMethod>, +ids: +List<U32>, +vm: M.VM, +sigs: +List<ProxyMethodSig>) -> Result<&2, &2, String, Unit>:
  match fuel methods:
    case 0n _: Fail{"java/lang/IllegalArgumentException"}
    case 1n+remaining Nil{}: Done{Unit{}}
    case 1n+remaining Con{+method, rest}:
      match method:
        case M.LoadedMethod{+id, +owner, +name, +descriptor, +flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
          do Result<&2, &2, String, Unit>:
            +method_name : String = Sy.text(S.symbols(vm), name)
            +descriptor_text : String = Sy.text(S.symbols(vm), descriptor)
            +ordinary : Bool = Bool.not(String.eq(method_name, "<init>")) && Bool.not(String.eq(method_name, "<clinit>"))
            +object_owner : Bool = U32.is_eq(owner, class_id(vm, "java/lang/Object"))
            +candidate : Bool = ordinary && Bool.not(object_owner) && U32.is_ne(U32.and(flags, 1), 0) && proxy_method_owner_ids(ids, S.classes(vm), owner)
            +sig : ProxyMethodSig = ProxyMethodSig{method_name, proxy_descriptor_parameters(String.to_list(descriptor_text), Nil{}), proxy_descriptor_return(String.to_list(descriptor_text))}
            checked : Unit <- Bool.pick(Result<&2, &2, String, Unit>, candidate, proxy_sig_check(vm, sig, sigs), Done{Unit{}})
            +next_sigs : +List<ProxyMethodSig> = Bool.pick(+List<ProxyMethodSig>, candidate, Con{sig, sigs}, sigs)
            result : Unit <- proxy_validate_methods(remaining, rest, ids, vm, next_sigs)
            return result

def proxy_cache_slot_bits(found: Maybe<&2, M.Slot>) -> U32:
  match found:
    case None{}: 0
    case Some{M.Slot{tag, bits}}: bits
def proxy_catalog_found(found: Maybe<&2, M.Slot>) -> Maybe<&2, U32>:
  match found:
    case None{}: None{}
    case Some{M.Slot{tag, bits}}: Some{bits}


def proxy_slots_equal(left: +List<M.Slot>, right: +List<M.Slot>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{M.Slot{left_tag, left_bits}, left_rest} Con{M.Slot{right_tag, right_bits}, right_rest}:
      U32.is_eq(left_tag, right_tag) && U32.is_eq(left_bits, right_bits) && proxy_slots_equal(left_rest, right_rest)
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
    +proxy_class : M.LoadedClass = M.LoadedClass{class_id_value, symbol_id, class_id(vm, "java/lang/reflect/Proxy"), ids, Nil{}, Nil{}, 4294967295, 0}
    +symbols : +List<String> = M.append(String, S.symbols(vm), [name])
    +with_symbols : M.VM = S.with_symbols(vm, symbols)
    +classes : +List<M.LoadedClass> = M.append(M.LoadedClass, S.classes(with_symbols), [proxy_class])
    +with_classes : M.VM = S.with_classes(with_symbols, classes)
    +node : M.HeapEntry = H.object_entry(class_id(vm, "java/lang/reflect/Proxy"), [M.Binding{0, M.Slot{1, loader}}, M.Binding{1, M.Slot{3, interface_array}}, M.Binding{2, M.Slot{1, class_id_value}}, M.Binding{3, M.Slot{3, head}}])
    result : ProxyClassResult <- proxy_cache_node_result(H.allocate(with_classes, node), class_id_value, key)
    return result

def proxy_catalog_found_result(+vm: M.VM, +ids: +List<U32>, key: U32, loader: U32, interface_array: U32, head: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, ProxyClassResult>:
  match found:
    case Some{reference}:
      do Result<&2, &2, String, ProxyClassResult>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        +class_slot : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), 2), "java/lang/IllegalArgumentException")
        return ProxyClassResult{vm, bits_of(class_slot)}
    case None{}: proxy_catalog_append(vm, ids, key, loader, interface_array, head)

def proxy_catalog(+vm: M.VM, +loader: U32, +interface_array: U32) -> Result<&2, &2, String, ProxyClassResult>:
  do Result<&2, &2, String, ProxyClassResult>:
    +array : M.HeapEntry <- H.get(S.heap(vm), interface_array)
    checked : Unit <- S.check(U32.is_eq(entry_kind(array), 2), "java/lang/IllegalArgumentException")
    +ids : +List<U32> <- proxy_interface_ids(256n, vm, entry_values(array), Nil{})
    validation : Unit <- proxy_validate_ids(ids, vm, S.metadata(vm), Nil{}, False{}, "")
    method_validation : Unit <- proxy_validate_methods(100000n, S.methods(vm), ids, vm, Nil{})
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
    case Some{M.Slot{tag, bits}}: bits

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
    case M.LoadedMethod{id, old_owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}

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

def system_loader_reference() -> U32:
  14

def class_bootstrap_target(+vm: M.VM, +target: U32) -> Bool:
  +object_id : U32 = class_id(vm, "java/lang/Object")
  U32.is_ge(target, object_id) && Bool.not(String.starts_with(class_name_text(vm, target), "$Proxy"))

def class_loader_allowed(+vm: M.VM, +target: U32, +loader: U32) -> Bool:
  Bool.or(U32.is_eq(loader, system_loader_reference()), Bool.and(U32.is_ne(loader, 0), Bool.not(class_bootstrap_target(vm, target))))

def class_for_name_args(+args: +List<M.Slot>) -> Result<&2, &2, String, ClassForNameArgs>:
  match args:
    case Con{name, Con{flag, Con{loader, rest}}}: Done{ClassForNameArgs{name, U32.is_ne(bits_of(flag), 0), bits_of(loader)}}
    case Con{name, Nil{}}: Done{ClassForNameArgs{name, True{}, system_loader_reference()}}
    case _: Fail{"InvalidState: intrinsic argument count"}

def class_for_name_call(+vm: M.VM, +target: U32, method: M.LoadedMethod) -> O.Outcome:
  O.Call{S.with_effect(S.set_class_state(vm, target, 1), M.ClassForName{target}), method, Nil{}}

def class_for_name_start_outcome(start: ClassForNameStart, target: U32) -> Result<&2, &2, String, O.Outcome>:
  match start:
    case ClassForNameReady{+vm}: class_mirror_out(vm, target)
    case ClassForNameCall{+vm, owner, +method}: Done{class_for_name_call(vm, owner, method)}

def class_for_name_parent_ready(parent_result: ClassForNameStart, +vm: M.VM, id: U32, initializer: U32) -> Result<&2, &2, String, ClassForNameStart>:
  match parent_result:
    case ClassForNameCall{+vm, target, +method}: Done{ClassForNameCall{vm, target, method}}
    case ClassForNameReady{+vm}:
      match initializer:
        case 4294967295: Done{ClassForNameReady{S.set_class_state(vm, id, 2)}}
        case method_id:
          do Result<&2, &2, String, ClassForNameStart>:
            method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), method_id), "java/lang/NoSuchMethodError")
            return ClassForNameCall{vm, id, method}

def class_for_name_walk(fuel: Nat, +vm: M.VM, +target: U32) -> Result<&2, &2, String, ClassForNameStart>:
  match fuel:
    case 0n: Fail{"java/lang/NoClassDefFoundError"}
    case 1n+remaining:
      +root : Bool = U32.is_eq(target, 4294967295)
      Bool.pick(Result<&2, &2, String, ClassForNameStart>,
        root,
        Done{ClassForNameReady{vm}},
        Result.bind(&2, &2, String, M.LoadedClass, ClassForNameStart,
          S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), target), "java/lang/ClassNotFoundException"),
          +class => do Result<&2, &2, String, ClassForNameStart>:
            +id : U32 = M.loaded_class_id(class)
            +parent : U32 = M.loaded_class_parent(class)
            initializer : U32 = M.loaded_class_initializer(class)
            +state : U32 = M.loaded_class_state(class)
            +failed : Bool = U32.is_eq(state, 3)
            +ready : Bool = U32.is_eq(state, 1) || U32.is_eq(state, 2)
            +fresh : Bool = U32.is_eq(state, 0)
            Bool.pick(Result<&2, &2, String, ClassForNameStart>,
              failed,
              Fail{"java/lang/NoClassDefFoundError"},
              Bool.pick(Result<&2, &2, String, ClassForNameStart>,
                ready,
                Done{ClassForNameReady{vm}},
                Bool.pick(Result<&2, &2, String, ClassForNameStart>,
                  fresh,
                  do Result<&2, &2, String, ClassForNameStart>:
                    parent_result : ClassForNameStart <- class_for_name_walk(remaining, vm, parent)
                    next : ClassForNameStart <- class_for_name_parent_ready(parent_result, vm, id, initializer)
                    return next,
                  Fail{"java/lang/NoClassDefFoundError"})))))
def class_for_name_initial(+vm: M.VM, +target: U32, initializer: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    start : ClassForNameStart <- class_for_name_walk(256n, vm, target)
    result : O.Outcome <- class_for_name_start_outcome(start, target)
    return result

def class_for_name_continue(+vm: M.VM, +target: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    start : ClassForNameStart <- class_for_name_walk(256n, vm, target)
    result : O.Outcome <- class_for_name_start_outcome(start, target)
    return result

def class_for_name_loaded_state(+vm: M.VM, +shouldInit: Bool, +id: U32, initializer: U32, state: U32) -> Result<&2, &2, String, O.Outcome>:
  match state:
    case 3: throw_name(vm, "java/lang/NoClassDefFoundError")
    case 0: Bool.pick(Result<&2, &2, String, O.Outcome>, shouldInit, class_for_name_initial(vm, id, initializer), class_mirror_out(vm, id))
    case _: class_mirror_out(vm, id)

def class_for_name_loaded(+vm: M.VM, +shouldInit: Bool, +class: M.LoadedClass) -> Result<&2, &2, String, O.Outcome>:
  +id : U32 = M.loaded_class_id(class)
  initializer : U32 = M.loaded_class_initializer(class)
  state : U32 = M.loaded_class_state(class)
  class_for_name_loaded_state(vm, shouldInit, id, initializer, state)

def class_for_name_target(+vm: M.VM, target: U32, shouldInit: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), target), "java/lang/ClassNotFoundException")
    result : O.Outcome <- class_for_name_loaded(vm, shouldInit, class)
    return result

def class_for_name_ready(+vm: M.VM, result: Result<&2, &2, String, ClassForNameArgs>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{ClassForNameArgs{+name, shouldInit, loader}}:
      do Result<&2, &2, String, O.Outcome>:
        name_text : String <- string_text(vm, bits_of(name))
        text : String = class_binary_name(name_text)
        +target : U32 = class_id(vm, text)
        checked : Unit <- S.check(U32.is_ne(target, 4294967295) && class_loader_allowed(vm, target, loader), "java/lang/ClassNotFoundException")
        result : O.Outcome <- class_for_name_target(vm, target, shouldInit)
        return result

def class_for_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  class_for_name_ready(vm, class_for_name_args(args))

def class_loader_system(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  ref_out(vm, system_loader_reference())

def class_loader_load(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    value : M.Slot <- slot1(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(receiver), 0), "java/lang/ClassNotFoundException")
    name : String <- string_text(vm, bits_of(value))
    +binary_name : String = class_binary_name(name)
    +target : U32 = class_id(vm, binary_name)
    target_checked : Unit <- S.check(U32.is_ne(target, 4294967295), "java/lang/ClassNotFoundException")
    result : O.Outcome <- class_mirror_out(vm, target)
    return result

def class_get_loader(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    mirror : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(mirror))
    checked : Unit <- S.check(U32.is_eq(entry_kind(entry), 8), "java/lang/IllegalArgumentException")
    target : U32 = entry_element(entry)
    result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, class_bootstrap_target(vm, target), ref_out(vm, 0), ref_out(vm, system_loader_reference()))
    return result
def resource_match_name(+resource: M.Resource, +name: String) -> Bool:
  M.Resource{+resource_name, +bytes, +origin} = resource
  String.eq(resource_name, name)

def resource_match_exact(resource: M.Resource, +name: String, +origin: String) -> Bool:
  M.Resource{resource_name, bytes, resource_origin} = resource
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

@unsafe def resource_url_refs(fuel: Nat, +vm: M.VM, +resources: +List<M.Resource>, +acc: +List<U32>, +name: String) -> Result<&2, &2, String, ResourceRefs>:
  match fuel resources:
    case 0n _:
      Done{ResourceRefs{vm, M.reverse(U32, acc)}}
    case 1n+ +p Nil{}:
      Done{ResourceRefs{vm, M.reverse(U32, acc)}}
    case 1n+ +p Con{+resource, rest}:
      match resource:
        case M.Resource{+resource_name, bytes, +origin}:
          +matched : Bool = String.eq(resource_name, name)
          Bool.pick(Result<&2, &2, String, ResourceRefs>, matched, resource_url_reference(vm, resource_name, origin, +vm2 => reference => resource_url_refs(p, vm2, rest, Con{reference, acc}, name)), resource_url_refs(p, vm, rest, acc, name))
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
        case M.Resource{+resource_name, bytes, +origin}:
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
        case M.Resource{resource_name, +bytes, origin}:
          alloc_result(H.allocate(vm, H.stream_entry(class_id(vm, "java/io/InputStream"), bytes)), vm2 => reference => ref_out(vm2, reference))
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

def resource_package_scan(chars: +List<Char>, +before: String, +segment: +List<Char>) -> String:
  match chars:
    case Nil{}: before
    case Con{Chr{47}, tail}: resource_package_scan(tail, before ++ String.from_list(M.reverse(Char, segment)) ++ "/", Nil{})
    case Con{head, tail}: resource_package_scan(tail, before, Con{head, segment})

def resource_package(+name: String) -> String:
  resource_package_scan(String.to_list(name), "", Nil{})

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

def class_loader_resource_stream(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  class_resource_stream(vm, args)

def class_loader_resource_url(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  class_resource_url(vm, args)
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

def url_get_path(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    name_ref : U32 <- url_field(entry, 0)
    name : String <- string_text(vm, name_ref)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(name))
    return result
def url_origin_scan(chars: +List<Char>, +acc: +List<Char>, archive: Bool) -> UrlOrigin:
  match chars:
    case Nil{}: UrlOrigin{archive, String.from_list(M.reverse(Char, acc))}
    case Con{Chr{33}, Con{Chr{47}, tail}}: url_origin_scan(tail, Con{Chr{47}, Con{Chr{33}, acc}}, True{})
    case Con{head, tail}: url_origin_scan(tail, Con{head, acc}, archive)

def url_origin_info(+origin: String) -> UrlOrigin:
  url_origin_scan(String.to_list(origin), Nil{}, False{})

def url_hex_digit(+value: U32) -> Char:
  Bool.pick(Char, U32.is_lt(value, 10), Chr{U32.add(48, value)}, Chr{U32.add(55, value)})

def url_percent_byte(+value: U32) -> String:
  "%" ++ String.from_list([url_hex_digit(U32.shrn(value, 4n)), url_hex_digit(U32.and(value, 15))])

def url_ascii_safe(+value: U32) -> Bool:
  (U32.is_ge(value, 65) && U32.is_le(value, 90)) ||
  (U32.is_ge(value, 97) && U32.is_le(value, 122)) ||
  (U32.is_ge(value, 48) && U32.is_le(value, 57)) ||
  U32.is_eq(value, 45) || U32.is_eq(value, 46) || U32.is_eq(value, 95) || U32.is_eq(value, 126) ||
  U32.is_eq(value, 33) || U32.is_eq(value, 36) || U32.is_eq(value, 38) || U32.is_eq(value, 39) || U32.is_eq(value, 40) ||
  U32.is_eq(value, 41) || U32.is_eq(value, 42) || U32.is_eq(value, 43) || U32.is_eq(value, 44) || U32.is_eq(value, 47) ||
  U32.is_eq(value, 58) || U32.is_eq(value, 59) || U32.is_eq(value, 61) || U32.is_eq(value, 64)

def url_escape_codepoint(+value: U32) -> String:
  Bool.pick(String, U32.is_le(value, 127) && url_ascii_safe(value), String.from_list([Chr{value}]),
    Bool.pick(String, U32.is_le(value, 127), url_percent_byte(value),
      Bool.pick(String, U32.is_le(value, 2047),
        url_percent_byte(U32.or(192, U32.shrn(value, 6n))) ++ url_percent_byte(U32.or(128, U32.and(value, 63))),
        Bool.pick(String, U32.is_le(value, 65535),
          url_percent_byte(U32.or(224, U32.shrn(value, 12n))) ++ url_percent_byte(U32.or(128, U32.and(U32.shrn(value, 6n), 63))) ++ url_percent_byte(U32.or(128, U32.and(value, 63))),
          url_percent_byte(U32.or(240, U32.shrn(value, 18n))) ++ url_percent_byte(U32.or(128, U32.and(U32.shrn(value, 12n), 63))) ++ url_percent_byte(U32.or(128, U32.and(U32.shrn(value, 6n), 63))) ++ url_percent_byte(U32.or(128, U32.and(value, 63)))))))

def url_escape_text(chars: +List<Char>) -> String:
  match chars:
    case Nil{}: ""
    case Con{head, tail}: url_escape_codepoint(Char.to_u32(head)) ++ url_escape_text(tail)

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

def class_name_mirror(+vm: M.VM, +name: String) -> Result<&2, &2, String, O.Outcome>:
  +target : U32 = class_id(vm, name)
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(target, 4294967295), throw_name(vm, "java/lang/NoClassDefFoundError"), class_mirror_out(vm, target))

def descriptor_mirror(+vm: M.VM, +descriptor: String) -> Result<&2, &2, String, O.Outcome>:
  +name : String = descriptor_class_name(descriptor)
  +target : U32 = class_id(vm, name)
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(target, 4294967295), throw_name(vm, "java/lang/NoClassDefFoundError"), class_mirror_out(vm, target))

def class_component_result(+vm: M.VM, +name: String) -> Result<&2, &2, String, O.Outcome>:
  +component : String = array_component_name(name)
  +target : U32 = class_id(vm, component)
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(target, 4294967295), ref_out(vm, 0), class_mirror_out(vm, target))


def class_metadata_found(found: Maybe<&2, M.ClassMetadata>) -> U32:
  match found:
    case None{}: 0
    case Some{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, pool}}: flags

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
    case Some{M.ClassMetadata{owner, flags, metadata, visibleAnnotations, pool}}: visibleAnnotations

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
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue}: annotations

def metadata_parameters(value: M.AnnotationMetadata) -> +List<+List<M.Annotation>>:
  match value:
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue}: parameterAnnotations
def metadata_type_annotations(value: M.AnnotationMetadata) -> +List<M.TypeAnnotation>:
  match value:
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue}: typeAnnotations
def metadata_exceptions(value: M.AnnotationMetadata) -> +List<U32>:
  match value:
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue}: exceptions



def metadata_default(value: M.AnnotationMetadata) -> Maybe<&2, M.AnnotationValue>:
  match value:
    case M.AnnotationMetadata{flags, exceptions, annotations, parameterAnnotations, typeAnnotations, defaultValue}: defaultValue

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
    case None{}: Fail{"java/lang/IncompleteAnnotationException"}
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

def annotation_string_value(+vm: M.VM, +pool: +List<M.Constant>, +index: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  do Result<&2, &2, String, AnnotationValueRef>:
    +text : String <- CP.utf(pool, index)
    value : AnnotationValueRef <- annotation_outcome_value(intern_or_alloc(vm, units_from_string(text)))
    return value

def annotation_class_value(+vm: M.VM, +pool: +List<M.Constant>, +index: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  do Result<&2, &2, String, AnnotationValueRef>:
    +descriptor : String <- CP.utf(pool, index)
    +name : String = descriptor_class_name(descriptor)
    +target : U32 = class_id(vm, name)
    checked : Unit <- S.check(U32.is_ne(target, 4294967295), "java/lang/NoClassDefFoundError")
    value : AnnotationValueRef <- annotation_outcome_value(class_mirror_out(vm, target))
    return value

def annotation_enum_alloc_result(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, AnnotationValueRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}: Done{AnnotationValueRef{vm, M.Slot{3, reference}}}

def annotation_enum_alloc_ordinal(+enum_class: U32, value: AnnotationValueRef, ordinal: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  match value:
    case AnnotationValueRef{+vm, slot}:
      annotation_enum_alloc_result(H.allocate(vm, H.object_entry(enum_class, [M.Binding{0, slot}, M.Binding{1, M.Slot{1, ordinal}}])))

def annotation_enum_cache_set(xs: +List<M.Binding>, +id: U32, +value: M.Slot) -> +List<M.Binding>:
  match xs:
    case Nil{}: [M.Binding{id, value}]
    case Con{M.Binding{+binding_id, old}, rest}:
      Con{M.Binding{binding_id, Bool.pick(M.Slot, U32.is_eq(binding_id, id), value, old)}, annotation_enum_cache_set(rest, id, value)}

def annotation_enum_cache_slot_bits(found: Maybe<&2, M.Slot>) -> U32:
  match found:
    case None{}: 0
    case Some{M.Slot{tag, bits}}: bits

def annotation_enum_cache_name_match(+vm: M.VM, found: Maybe<&2, M.Slot>, +name: String) -> Result<&2, &2, String, Bool>:
  match found:
    case None{}: Done{False{}}
    case Some{M.Slot{tag, bits}}:
      do Result<&2, &2, String, Bool>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), bits)
        result : Bool = U32.is_eq(tag, 3) && H.units_equal(entry_chars(entry), units_from_string(name))
        return result

def annotation_enum_cache_lookup(fuel: Nat, +vm: M.VM, head: U32, +name: String) -> Result<&2, &2, String, Maybe<&2, U32>>:
  match fuel head:
    case 0n _: Done{None{}}
    case 1n+remaining 0: Done{None{}}
    case 1n+remaining reference:
      do Result<&2, &2, String, Maybe<&2, U32>>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        name_found : Maybe<&2, M.Slot> = H.binding_find(entry_fields(entry), 0)
        same_name : Bool <- annotation_enum_cache_name_match(vm, name_found, name)
        enum_found : Maybe<&2, M.Slot> = H.binding_find(entry_fields(entry), 1)
        +enum_reference : U32 = annotation_enum_cache_slot_bits(enum_found)
        next_found : Maybe<&2, M.Slot> = H.binding_find(entry_fields(entry), 2)
        +next : U32 = annotation_enum_cache_slot_bits(next_found)
        result : Maybe<&2, U32> <- Bool.pick(Result<&2, &2, String, Maybe<&2, U32>>, same_name, Done{Some{enum_reference}}, annotation_enum_cache_lookup(remaining, vm, next, name))
        return result

def annotation_enum_field_ordinal(fuel: Nat, fields: +List<M.LoadedField>, +symbols: +List<String>, +owner: U32, +name: String, +ordinal: U32) -> Maybe<&2, U32>:
  match fuel fields:
    case 0n _: None{}
    case 1n+remaining Nil{}: None{}
    case 1n+remaining Con{field, rest}:
      +field_ref : M.LoadedField = field
      +field_owner : Bool = U32.is_eq(M.loaded_field_owner(field_ref), owner)
      +enum_constant : Bool = U32.is_ne(U32.and(M.loaded_field_flags(field_ref), 16384), 0)
      +field_name : String = Sy.text(symbols, M.loaded_field_name(field_ref))
      +matches : Bool = field_owner && enum_constant && String.eq(field_name, name)
      +next_ordinal : U32 = Bool.pick(U32, enum_constant, U32.add(ordinal, 1), ordinal)
      Bool.pick(Maybe<&2, U32>, matches, Some{ordinal}, annotation_enum_field_ordinal(remaining, rest, symbols, owner, name, next_ordinal))

def annotation_enum_known_ordinal(+owner: String, +name: String) -> U32:
  Bool.pick(U32, String.eq(owner, "java/lang/annotation/RetentionPolicy") && String.eq(name, "SOURCE"), 0,
    Bool.pick(U32, String.eq(owner, "java/lang/annotation/RetentionPolicy") && String.eq(name, "CLASS"), 1,
      Bool.pick(U32, String.eq(owner, "java/lang/annotation/RetentionPolicy") && String.eq(name, "RUNTIME"), 2, 0)))

def annotation_enum_ordinal_found(found: Maybe<&2, U32>, +owner_name: String, +name: String) -> U32:
  match found:
    case Some{ordinal}: ordinal
    case None{}: annotation_enum_known_ordinal(owner_name, name)

def annotation_enum_ordinal(+vm: M.VM, owner: U32, +owner_name: String, +name: String) -> U32:
  annotation_enum_ordinal_found(annotation_enum_field_ordinal(256n, S.fields(vm), S.symbols(vm), owner, name, 0), owner_name, name)

def annotation_enum_cache_node_result(result: Result<&2, &2, String, H.Allocation>, slot: M.Slot, key: U32, head: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}:
      +statics : +List<M.Binding> = S.statics(vm)
      +updated : M.VM = S.with_statics(vm, annotation_enum_cache_set(statics, key, M.Slot{3, reference}))
      Done{AnnotationValueRef{updated, slot}}

def annotation_enum_cache_new(value: AnnotationValueRef, name_slot: M.Slot, key: U32, +head: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  match value:
    case AnnotationValueRef{+vm, +slot}:
      annotation_enum_cache_node_result(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/AnnotationEnumCache"), [M.Binding{0, name_slot}, M.Binding{1, slot}, M.Binding{2, M.Slot{3, head}}])), slot, key, head)

def annotation_enum_cached_result(+vm: M.VM, enum_class: U32, name_slot: M.Slot, cached: Maybe<&2, U32>, ordinal: U32, key: U32, head: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  match cached:
    case Some{reference}: Done{AnnotationValueRef{vm, M.Slot{3, reference}}}
    case None{}:
      do Result<&2, &2, String, AnnotationValueRef>:
        +name_ref : M.Slot = name_slot
        allocated : AnnotationValueRef <- annotation_enum_alloc_ordinal(enum_class, AnnotationValueRef{vm, name_ref}, ordinal)
        result : AnnotationValueRef <- annotation_enum_cache_new(allocated, name_ref, key, head)
        return result

def annotation_enum_cached(+vm: M.VM, +enum_class: U32, +name: String, value: AnnotationValueRef, ordinal: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  match value:
    case AnnotationValueRef{+vm, slot}:
      do Result<&2, &2, String, AnnotationValueRef>:
        +key : U32 = U32.add(2147483648, enum_class)
        found : Maybe<&2, M.Slot> = H.binding_find(S.statics(vm), key)
        +head : U32 = annotation_enum_cache_slot_bits(found)
        cached : Maybe<&2, U32> <- annotation_enum_cache_lookup(64n, vm, head, name)
        result : AnnotationValueRef <- annotation_enum_cached_result(vm, enum_class, slot, cached, ordinal, key, head)
        return result

def annotation_enum_value(+vm: M.VM, +pool: +List<M.Constant>, +typeIndex: U32, +nameIndex: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  do Result<&2, &2, String, AnnotationValueRef>:
    +descriptor : String <- CP.utf(pool, typeIndex)
    +name : String <- CP.utf(pool, nameIndex)
    +enum_name : String = descriptor_class_name(descriptor)
    +enum_class : U32 = class_id(vm, enum_name)
    checked : Unit <- S.check(U32.is_ne(enum_class, 4294967295), "java/lang/NoClassDefFoundError")
    +ordinal : U32 = annotation_enum_ordinal(vm, enum_class, enum_name, name)
    name_value : AnnotationValueRef <- annotation_string_value(vm, pool, nameIndex)
    result : AnnotationValueRef <- annotation_enum_cached(vm, enum_class, name, name_value, ordinal)
    return result

def annotation_value_array_component_chars(chars: +List<Char>) -> String:
  match chars:
    case Con{Chr{91}, tail}: String.from_list(tail)
    case _: "Ljava/lang/Object;"

def annotation_value_array_component(+descriptor: String) -> String:
  annotation_value_array_component_chars(String.to_list(descriptor))


def annotation_nested_alloc_result(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, AnnotationValueRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}: Done{AnnotationValueRef{vm, M.Slot{3, reference}}}

def annotation_nested_value(+vm: M.VM, +pool: +List<M.Constant>, value: M.AnnotationValue, +descriptor: String) -> Result<&2, &2, String, AnnotationValueRef>:
  match value:
    case M.AnnotationConst{115, index}: annotation_string_value(vm, pool, index)
    case _: Fail{"UnsupportedFeature: nested annotation value"}

def annotation_nested_binding_continue(value_ref: AnnotationValueRef, +pool: +List<M.Constant>, +owner: U32, +rest: +List<M.AnnotationValue>, +method: M.LoadedMethod, +acc: +List<M.Binding>, next: M.VM -> M.Slot -> Result<&2, &2, String, AnnotationBindings>) -> Result<&2, &2, String, AnnotationBindings>:
  match value_ref:
    case AnnotationValueRef{+vm, slot}: next(vm, slot)

def annotation_nested_bindings(+elements: +List<M.AnnotationValue>, +vm: M.VM, +pool: +List<M.Constant>, +owner: U32, +acc: +List<M.Binding>) -> Result<&2, &2, String, AnnotationBindings>:
  match elements:
    case Nil{}: Done{AnnotationBindings{vm, M.reverse(M.Binding, acc)}}
    case Con{value, rest}:
      match value:
        case M.AnnotationElementValue{nameIndex, value}:
          do Result<&2, &2, String, AnnotationBindings>:
            +name : String <- CP.utf(pool, nameIndex)
            +method : M.LoadedMethod <- S.require(M.LoadedMethod, annotation_method_find(S.methods(vm), owner, name, S.symbols(vm)), "VmError.InvalidAnnotation: unknown nested element")
            +descriptor : String = annotation_method_descriptor(vm, method)
            value_ref : AnnotationValueRef <- annotation_nested_value(vm, pool, value, method_return_name(descriptor))
            result : AnnotationBindings <- annotation_nested_binding_continue(value_ref, pool, owner, rest, method, acc, next_vm => slot => annotation_nested_bindings(rest, next_vm, pool, owner, Con{M.Binding{M.loaded_method_id(method), slot}, acc}))
            return result
        case _: annotation_nested_bindings(rest, vm, pool, owner, acc)

def annotation_nested_object_alloc(+owner: U32, bindings: AnnotationBindings) -> Result<&2, &2, String, AnnotationValueRef>:
  match bindings:
    case AnnotationBindings{+vm, +bindings}: annotation_nested_alloc_result(H.allocate(vm, M.HeapEntry{owner, 9, owner, bindings, Nil{}, Nil{}}))

def annotation_nested_object(+vm: M.VM, +pool: +List<M.Constant>, +typeIndex: U32, +elements: +List<M.AnnotationValue>) -> Result<&2, &2, String, AnnotationValueRef>:
  do Result<&2, &2, String, AnnotationValueRef>:
    +descriptor : String <- CP.utf(pool, typeIndex)
    +owner : U32 = class_id(vm, descriptor_class_name(descriptor))
    checked : Unit <- S.check(U32.is_ne(owner, 4294967295), "java/lang/NoClassDefFoundError")
    bindings : AnnotationBindings <- annotation_nested_bindings(elements, vm, pool, owner, Nil{})
    result : AnnotationValueRef <- annotation_nested_object_alloc(owner, bindings)
    return result

def annotation_float_constant(+vm: M.VM, result: Result<&2, &2, String, M.Constant>) -> Result<&2, &2, String, AnnotationValueRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{M.Number{kind, bits}}: Done{AnnotationValueRef{vm, M.Slot{2, bits}}}
    case Done{other}: Fail{"VmError.InvalidAnnotation: expected float constant"}

def annotation_numeric_constant(+vm: M.VM, result: Result<&2, &2, String, M.Constant>) -> Result<&2, &2, String, AnnotationValueRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{M.Number{kind, bits}}: Done{AnnotationValueRef{vm, M.Slot{1, bits}}}
    case Done{other}: Fail{"VmError.InvalidAnnotation: expected numeric constant"}
def annotation_wide_box(+vm: M.VM, +wrapper: String, high: U32, low: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  do Result<&2, &2, String, AnnotationValueRef>:
    +owner : U32 = class_id(vm, wrapper)
    checked : Unit <- S.check(U32.is_ne(owner, 4294967295), "UnsupportedFeature: wide annotation wrapper " ++ wrapper)
    result : AnnotationValueRef <- annotation_nested_alloc_result(H.allocate(vm, H.object_entry(owner, [M.Binding{0, M.Slot{1, high}}, M.Binding{1, M.Slot{1, low}}])))
    return result

def annotation_wide_pair(+vm: M.VM, result: Result<&2, &2, String, M.Constant>, expected: U32, wrapper: String) -> Result<&2, &2, String, AnnotationValueRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{M.PairIndex{kind, high, low}}:
      do Result<&2, &2, String, AnnotationValueRef>:
        checked : Unit <- S.check(U32.is_eq(kind, expected), "VmError.InvalidAnnotation: expected wide constant")
        value : AnnotationValueRef <- annotation_wide_box(vm, wrapper, high, low)
        return value
    case Done{other}: Fail{"VmError.InvalidAnnotation: expected wide constant"}

def annotation_wide_constant(+vm: M.VM, result: Result<&2, &2, String, M.Constant>, tag: U32) -> Result<&2, &2, String, AnnotationValueRef>:
  match tag:
    case 74: annotation_wide_pair(vm, result, 5, "java/lang/Long")
    case 68: annotation_wide_pair(vm, result, 6, "java/lang/Double")
    case _: Fail{"VmError.InvalidAnnotation: unsupported wide annotation tag"}


def annotation_array_simple_value(+vm: M.VM, +pool: +List<M.Constant>, value: M.AnnotationValue) -> Result<&2, &2, String, AnnotationValueRef>:
  match value:
    case M.AnnotationConst{115, index}: annotation_string_value(vm, pool, index)
    case M.AnnotationConst{70, index}: annotation_float_constant(vm, CP.get(pool, index))
    case M.AnnotationConst{74, index}: annotation_wide_constant(vm, CP.get(pool, index), 74)
    case M.AnnotationConst{68, index}: annotation_wide_constant(vm, CP.get(pool, index), 68)
    case M.AnnotationConst{tag, index}: annotation_numeric_constant(vm, CP.get(pool, index))
    case M.AnnotationClass{descriptorIndex}: annotation_class_value(vm, pool, descriptorIndex)
    case M.AnnotationEnum{typeIndex, nameIndex}: annotation_enum_value(vm, pool, typeIndex, nameIndex)
    case M.AnnotationNested{typeIndex, elements}: annotation_nested_object(vm, pool, typeIndex, elements)
    case _: Fail{"UnsupportedFeature: annotation array value"}

def annotation_array_simple_continue(value_ref: AnnotationValueRef, +pool: +List<M.Constant>, +rest: +List<M.AnnotationValue>, +acc: +List<M.Slot>, next: M.VM -> M.Slot -> Result<&2, &2, String, AnnotationValueRefs>) -> Result<&2, &2, String, AnnotationValueRefs>:
  match value_ref:
    case AnnotationValueRef{+vm, slot}: next(vm, slot)

@unsafe def annotation_array_simple(+values: +List<M.AnnotationValue>, +vm: M.VM, +pool: +List<M.Constant>, +acc: +List<M.Slot>) -> Result<&2, &2, String, AnnotationValueRefs>:
  match values:
    case Nil{}: Done{AnnotationValueRefs{vm, M.reverse(M.Slot, acc)}}
    case Con{+value, rest}:
      do Result<&2, &2, String, AnnotationValueRefs>:
        value_ref : AnnotationValueRef <- annotation_array_simple_value(vm, pool, value)
        result : AnnotationValueRefs <- annotation_array_simple_continue(value_ref, pool, rest, acc, next_vm => slot => annotation_array_simple(rest, next_vm, pool, Con{slot, acc}))
        return result

def annotation_array_primitive_tag(+descriptor: String) -> U32:
  Bool.pick(U32, String.eq(descriptor, "[Z"), 4,
    Bool.pick(U32, String.eq(descriptor, "[C"), 5,
      Bool.pick(U32, String.eq(descriptor, "[F"), 6,
        Bool.pick(U32, String.eq(descriptor, "[D"), 7,
          Bool.pick(U32, String.eq(descriptor, "[B"), 8,
            Bool.pick(U32, String.eq(descriptor, "[S"), 9,
              Bool.pick(U32, String.eq(descriptor, "[I"), 10,
                Bool.pick(U32, String.eq(descriptor, "[J"), 11, 0))))))))

def annotation_array_alloc_kind(kind: U32, +vm: M.VM, array_class: U32, component_class: U32, +slots: +List<M.Slot>) -> Result<&2, &2, String, H.Allocation>:
  match kind:
    case 7: H.allocate(vm, H.reference_array_entry(array_class, class_id(vm, "java/lang/Double"), slots))
    case 11: H.allocate(vm, H.reference_array_entry(array_class, class_id(vm, "java/lang/Long"), slots))
    case 0: H.allocate(vm, H.reference_array_entry(array_class, component_class, slots))
    case _: H.allocate(vm, H.primitive_array_entry(array_class, kind, slots))

def annotation_array_simple_alloc(value: AnnotationValueRefs, +descriptor: String) -> Result<&2, &2, String, AnnotationValueRef>:
  match value:
    case AnnotationValueRefs{+vm, +slots}:
      do Result<&2, &2, String, AnnotationValueRef>:
        +component_name : String = descriptor_class_name(annotation_value_array_component(descriptor))
        +array_class : U32 = class_id(vm, descriptor)
        +component_class : U32 = class_id(vm, component_name)
        checked : Unit <- S.check(U32.is_ne(array_class, 4294967295), "UnsupportedFeature: annotation array class " ++ descriptor)
        component_checked : Unit <- S.check(U32.is_ne(component_class, 4294967295), "UnsupportedFeature: annotation array component " ++ component_name)
        result : AnnotationValueRef <- annotation_nested_alloc_result(annotation_array_alloc_kind(annotation_array_primitive_tag(descriptor), vm, array_class, component_class, slots))
        return result


@unsafe def annotation_value(+vm: M.VM, +pool: +List<M.Constant>, value: M.AnnotationValue, +descriptor: String) -> Result<&2, &2, String, AnnotationValueRef>:
  match value:
    case M.AnnotationConst{tag, index}:
      match tag:
        case 115: annotation_string_value(vm, pool, index)
        case 70: annotation_float_constant(vm, CP.get(pool, index))
        case 74: annotation_wide_constant(vm, CP.get(pool, index), 74)
        case 68: annotation_wide_constant(vm, CP.get(pool, index), 68)
        case _: annotation_numeric_constant(vm, CP.get(pool, index))
    case M.AnnotationClass{descriptorIndex}: annotation_class_value(vm, pool, descriptorIndex)
    case M.AnnotationEnum{typeIndex, nameIndex}: annotation_enum_value(vm, pool, typeIndex, nameIndex)
    case M.AnnotationNested{typeIndex, elements}: annotation_nested_object(vm, pool, typeIndex, elements)
    case M.AnnotationArray{values}:
      do Result<&2, &2, String, AnnotationValueRef>:
        refs : AnnotationValueRefs <- annotation_array_simple(values, vm, pool, Nil{})
        result : AnnotationValueRef <- annotation_array_simple_alloc(refs, descriptor)
        return result
    case M.AnnotationElementValue{nameIndex, value}: Fail{"VmError.InvalidAnnotation: invalid element value"}

def annotation_nested_elements_to_top(+values: +List<M.AnnotationValue>, +acc: +List<M.AnnotationElement>) -> +List<M.AnnotationElement>:
  match values:
    case Nil{}: M.reverse(M.AnnotationElement, acc)
    case Con{value, rest}:
      match value:
        case M.AnnotationElementValue{nameIndex, value}: annotation_nested_elements_to_top(rest, Con{M.AnnotationElement{nameIndex, value}, acc})
        case _: annotation_nested_elements_to_top(rest, acc)

def annotation_value_vm(value: AnnotationValueRef) -> M.VM:
  match value:
    case AnnotationValueRef{vm, slot}: vm

def annotation_value_slot(value: AnnotationValueRef) -> M.Slot:
  match value:
    case AnnotationValueRef{vm, slot}: slot

def annotation_binding_continue(value_ref: AnnotationValueRef, +pool: +List<M.Constant>, +owner: U32, +rest: +List<M.AnnotationElement>, +method: M.LoadedMethod, +acc: +List<M.Binding>, next: M.VM -> M.Slot -> Result<&2, &2, String, AnnotationBindings>) -> Result<&2, &2, String, AnnotationBindings>:
  match value_ref:
    case AnnotationValueRef{+vm, slot}: next(vm, slot)

def annotation_bindings(+elements: +List<M.AnnotationElement>, +vm: M.VM, +pool: +List<M.Constant>, +owner: U32, +acc: +List<M.Binding>) -> Result<&2, &2, String, AnnotationBindings>:
  match elements:
    case Nil{}: Done{AnnotationBindings{vm, M.reverse(M.Binding, acc)}}
    case Con{M.AnnotationElement{nameIndex, value}, rest}:
      do Result<&2, &2, String, AnnotationBindings>:
        +name : String <- CP.utf(pool, nameIndex)
        +method : M.LoadedMethod <- S.require(M.LoadedMethod, annotation_method_find(S.methods(vm), owner, name, S.symbols(vm)), "VmError.InvalidAnnotation: unknown element")
        +descriptor : String = annotation_method_descriptor(vm, method)
        value_ref : AnnotationValueRef <- annotation_value(vm, pool, value, method_return_name(descriptor))
        result : AnnotationBindings <- annotation_binding_continue(value_ref, pool, owner, rest, method, acc, next_vm => slot => annotation_bindings(rest, next_vm, pool, owner, Con{M.Binding{M.loaded_method_id(method), slot}, acc}))
        return result

def annotation_object_alloc(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, AnnotationValueRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}: Done{AnnotationValueRef{vm, M.Slot{3, reference}}}

def annotation_object_alloc_bindings(+owner: U32, bindings: AnnotationBindings) -> Result<&2, &2, String, AnnotationValueRef>:
  match bindings:
    case AnnotationBindings{+vm, +bindings}: annotation_object_alloc(H.allocate(vm, M.HeapEntry{owner, 9, owner, bindings, Nil{}, Nil{}}))

def annotation_object(+vm: M.VM, +pool: +List<M.Constant>, value: M.Annotation) -> Result<&2, &2, String, AnnotationValueRef>:
  match value:
    case M.Annotation{typeIndex, elements}:
      do Result<&2, &2, String, AnnotationValueRef>:
        +annotation_name : String = annotation_pool_name(pool, typeIndex)
        +owner : U32 = class_id(vm, annotation_name)
        checked : Unit <- S.check(U32.is_ne(owner, 4294967295), "java/lang/NoClassDefFoundError")
        bindings : AnnotationBindings <- annotation_bindings(elements, vm, pool, owner, Nil{})
        result : AnnotationValueRef <- annotation_object_alloc_bindings(owner, bindings)
        return result

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
    case M.ClassMetadata{owner, flags, metadata, visibleAnnotations, +pool}: AnnotationMetadataRef{vm, pool, metadata}

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

def annotation_repeatable_value(+vm: M.VM, +pool: +List<M.Constant>, +name: String, value: M.AnnotationValue) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case M.AnnotationArray{values}:
      do Result<&2, &2, String, O.Outcome>:
        refs : AnnotationValueRefs <- annotation_array_simple(values, vm, pool, Nil{})
        +descriptor : String = "[L" ++ name ++ ";"
        array_ref : AnnotationValueRef <- annotation_array_simple_alloc(refs, descriptor)
        result : O.Outcome <- annotation_value_ref_outcome(array_ref)
        return result
    case _: annotation_array_result_type(vm, class_id(vm, name), Nil{})

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

def annotation_scan(+vm: M.VM, +pool: +List<M.Constant>, +name: String, +container_name: String, +annotations: +List<M.Annotation>) -> Result<&2, &2, String, O.Outcome>:
  match annotations:
    case Nil{}: annotation_array_result_type(vm, class_id(vm, name), Nil{})
    case Con{+annotation, rest}:
      match annotation:
        case M.Annotation{typeIndex, elements}:
          Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(annotation_pool_name(pool, typeIndex), name), annotation_one_array_found(vm, pool, class_id(vm, name), Some{annotation}), Bool.pick(Result<&2, &2, String, O.Outcome>, Bool.not(String.eq(annotation_pool_name(pool, typeIndex), "")) && String.eq(annotation_pool_name(pool, typeIndex), container_name), annotation_repeatable_container_found(vm, pool, name, Some{annotation}), annotation_scan(vm, pool, name, container_name, rest)))

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
      Done{False{}}
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
      ref_out(vm, 0)
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


def class_get_annotations_by_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    annotation : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(annotation))
    +name : String = class_name_text(vm, entry_element(entry))
    result : O.Outcome <- class_annotations_by_type(vm, target, name)
    return result

def class_get_annotations(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- class_target(vm, args)
    result : O.Outcome <- class_annotations_array(vm, target)
    return result

def class_get_declared_annotations(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  class_get_annotations(vm, args)
def field_metadata_from_metadata(metadata: M.Metadata, +id: U32) -> Result<&2, &2, String, M.FieldMetadata>:
  match metadata:
    case M.Metadata{classes, fields, methods}:
      S.require(M.FieldMetadata, M.nth(M.FieldMetadata, fields, id), "InvalidState: missing field metadata")

def field_metadata_value(+vm: M.VM, +id: U32) -> Result<&2, &2, String, M.FieldMetadata>:
  field_metadata_from_metadata(S.metadata(vm), id)

def class_metadata_pool(value: M.ClassMetadata) -> +List<M.Constant>:
  match value:
    case M.ClassMetadata{owner, flags, metadata, visibleAnnotations, +pool}: pool

def field_metadata_annotations(value: M.FieldMetadata) -> M.AnnotationMetadata:
  match value:
    case M.FieldMetadata{owner, field, metadata}: metadata


def method_metadata_from_metadata(metadata: M.Metadata, +id: U32) -> Result<&2, &2, String, M.MethodMetadata>:
  match metadata:
    case M.Metadata{classes, fields, methods}:
      S.require(M.MethodMetadata, M.nth(M.MethodMetadata, methods, id), "InvalidState: missing method metadata")

def method_metadata_value(+vm: M.VM, +id: U32) -> Result<&2, &2, String, M.MethodMetadata>:
  method_metadata_from_metadata(S.metadata(vm), id)
def method_metadata_annotations(value: M.MethodMetadata) -> M.AnnotationMetadata:
  match value:
    case M.MethodMetadata{owner, method, metadata}: metadata

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

def annotation_default_from_maybe(+vm: M.VM, +pool: +List<M.Constant>, found: Maybe<&2, M.AnnotationValue>, +descriptor: String) -> Result<&2, &2, String, AnnotationValueRef>:
  match found:
    case None{}: Fail{"VmError.InvalidAnnotation: missing annotation element"}
    case Some{value}: annotation_value(vm, pool, value, method_return_name(descriptor))

def annotation_default_method(+vm: M.VM, +pool: +List<M.Constant>, method_metadata: M.MethodMetadata, +descriptor: String) -> Result<&2, &2, String, AnnotationValueRef>:
  match method_metadata:
    case M.MethodMetadata{owner, method, metadata}: annotation_default_from_maybe(vm, pool, metadata_default(metadata), descriptor)

def annotation_default_source(source: AnnotationMetadataRef, +method_id: U32, +descriptor: String) -> Result<&2, &2, String, AnnotationValueRef>:
  match source:
    case AnnotationMetadataRef{+vm, +pool, metadata}:
      do Result<&2, &2, String, AnnotationValueRef>:
        method_metadata : M.MethodMetadata <- method_metadata_value(vm, method_id)
        result : AnnotationValueRef <- annotation_default_method(vm, pool, method_metadata, descriptor)
        return result
def annotation_value_outcome(value: AnnotationValueRef) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case AnnotationValueRef{+vm, slot}: returned(vm, Some{slot})

def annotation_default(+vm: M.VM, +owner: U32, +method_id: U32, +descriptor: String) -> Result<&2, &2, String, AnnotationValueRef>:
  do Result<&2, &2, String, AnnotationValueRef>:
    source : AnnotationMetadataRef <- class_annotation_values(vm, owner)
    result : AnnotationValueRef <- annotation_default_source(source, method_id, descriptor)
    return result

def annotation_bound(found: Maybe<&2, M.Slot>, +vm: M.VM, +owner: U32, +method_id: U32, +descriptor: String) -> Result<&2, &2, String, AnnotationValueRef>:
  match found:
    case Some{slot}: Done{AnnotationValueRef{vm, slot}}
    case None{}: annotation_default(vm, owner, method_id, descriptor)



def annotation_element_invoke(+vm: M.VM, +args: +List<M.Slot>, +owner: U32, +name: String, +descriptor: String, fields: +List<M.Binding>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, annotation_method_find(S.methods(vm), owner, name, S.symbols(vm)), "java/lang/NoSuchMethodError: annotation element " ++ name)
    value : AnnotationValueRef <- annotation_bound(H.binding_find(fields, M.loaded_method_id(method)), vm, owner, M.loaded_method_id(method), descriptor)
    result : O.Outcome <- annotation_value_outcome(value)
    return result


type AnnotationCompareTask is Data:
  CompareRef{left: U32, right: U32}
  CompareEntries{left: M.HeapEntry, right: M.HeapEntry, leftKind: U32, rightKind: U32}
  CompareSlots{left: +List<M.Slot>, right: +List<M.Slot>}
  CompareBindings{left: +List<M.Binding>, right: +List<M.Binding>}
  CompareTrue{}
  CompareFalse{}

type AnnotationCompareFrame is Data:
  CompareSlotsRest{left: +List<M.Slot>, right: +List<M.Slot>}
  CompareBindingsRest{left: +List<M.Binding>, right: +List<M.Binding>}

def annotation_compare_ref_task(+vm: M.VM, left: U32, right: U32, both_null: Bool, one_null: Bool) -> Result<&2, &2, String, AnnotationCompareTask>:
  match both_null one_null:
    case True{} _:
      Done{CompareTrue{}}
    case False{} True{}:
      Done{CompareFalse{}}
    case False{} False{}:
      do Result<&2, &2, String, AnnotationCompareTask>:
        +left_entry : M.HeapEntry <- H.get(S.heap(vm), left)
        +right_entry : M.HeapEntry <- H.get(S.heap(vm), right)
        result : AnnotationCompareTask <- Done{CompareEntries{left_entry, right_entry, entry_kind(left_entry), entry_kind(right_entry)}}
        return result

def annotation_compare_entry_task(left: M.HeapEntry, right: M.HeapEntry, kind: U32) -> AnnotationCompareTask:
  match kind:
    case 1: CompareSlots{entry_values(left), entry_values(right)}
    case 2: CompareSlots{entry_values(left), entry_values(right)}
    case 3: Bool.pick(AnnotationCompareTask, H.units_equal(entry_chars(left), entry_chars(right)), CompareTrue{}, CompareFalse{})
    case 8: Bool.pick(AnnotationCompareTask, U32.is_eq(entry_element(left), entry_element(right)), CompareTrue{}, CompareFalse{})
    case 9: CompareBindings{entry_fields(left), entry_fields(right)}
    case _: CompareBindings{entry_fields(left), entry_fields(right)}

def annotation_compare(fuel: Nat, +vm: M.VM, task: AnnotationCompareTask, +frames: +List<AnnotationCompareFrame>) -> Result<&2, &2, String, Bool>:
  match fuel task frames:
    case 0n _ _:
      Done{False{}}
    case 1n+remaining CompareFalse{} _:
      Done{False{}}
    case 1n+remaining CompareTrue{} Nil{}:
      Done{True{}}
    case 1n+remaining CompareTrue{} Con{CompareSlotsRest{left, right}, rest}:
      annotation_compare(remaining, vm, CompareSlots{left, right}, rest)
    case 1n+remaining CompareTrue{} Con{CompareBindingsRest{left, right}, rest}:
      annotation_compare(remaining, vm, CompareBindings{left, right}, rest)
    case 1n+remaining CompareRef{left, right} frames_ref:
      do Result<&2, &2, String, Bool>:
        +left_ref : U32 = left
        +right_ref : U32 = right
        +both_null : Bool = U32.is_eq(left_ref, 0) && U32.is_eq(right_ref, 0)
        +one_null : Bool = U32.is_eq(left_ref, 0) || U32.is_eq(right_ref, 0)
        next : AnnotationCompareTask <- annotation_compare_ref_task(vm, left_ref, right_ref, both_null, one_null)
        result : Bool <- annotation_compare(remaining, vm, next, frames_ref)
        return result
    case 1n+remaining CompareEntries{left, right, leftKind, rightKind} frames_ref:
      do Result<&2, &2, String, Bool>:
        +left_entry : M.HeapEntry = left
        +right_entry : M.HeapEntry = right
        +kind_left : U32 = leftKind
        +kind_right : U32 = rightKind
        +same_kind : Bool = U32.is_eq(kind_left, kind_right)
        +same_class : Bool = U32.is_eq(H.entry_class(left_entry), H.entry_class(right_entry))
        +same_element : Bool = Bool.pick(Bool, U32.is_eq(kind_left, 8), U32.is_eq(entry_element(left_entry), entry_element(right_entry)), True{})
        +compatible : Bool = same_kind && same_class && same_element
        +next : AnnotationCompareTask = Bool.pick(AnnotationCompareTask, compatible, annotation_compare_entry_task(left_entry, right_entry, kind_left), CompareFalse{})
        result : Bool <- annotation_compare(remaining, vm, next, frames_ref)
        return result
    case 1n+remaining CompareSlots{Nil{}, Nil{}} frames_ref:
      annotation_compare(remaining, vm, CompareTrue{}, frames_ref)
    case 1n+remaining CompareSlots{Nil{}, _} _:
      Done{False{}}
    case 1n+remaining CompareSlots{Con{_, _}, Nil{}} _:
      Done{False{}}
    case 1n+remaining CompareSlots{Con{M.Slot{tag, bits}, tail}, Con{M.Slot{otherTag, otherBits}, rest}} frames_ref:
      +tag_ref : U32 = tag
      +bits_ref : U32 = bits
      +other_tag_ref : U32 = otherTag
      +other_bits_ref : U32 = otherBits
      +reference : Bool = U32.is_eq(tag_ref, 3) && U32.is_eq(other_tag_ref, 3)
      +same_value : Bool = U32.is_eq(tag_ref, other_tag_ref) && U32.is_eq(bits_ref, other_bits_ref)
      +next : AnnotationCompareTask = Bool.pick(AnnotationCompareTask, reference, CompareRef{bits_ref, other_bits_ref}, Bool.pick(AnnotationCompareTask, same_value, CompareTrue{}, CompareFalse{}))
      annotation_compare(remaining, vm, next, Con{CompareSlotsRest{tail, rest}, frames_ref})
    case 1n+remaining CompareBindings{Nil{}, Nil{}} frames_ref:
      annotation_compare(remaining, vm, CompareTrue{}, frames_ref)
    case 1n+remaining CompareBindings{Nil{}, _} _:
      Done{False{}}
    case 1n+remaining CompareBindings{Con{M.Binding{id, value}, tail}, Nil{}} _:
      Done{False{}}
    case 1n+remaining CompareBindings{Con{M.Binding{id, value}, tail}, Con{M.Binding{otherId, otherValue}, rest}} frames_ref:
      +same_id : Bool = U32.is_eq(id, otherId)
      +next : AnnotationCompareTask = Bool.pick(AnnotationCompareTask, same_id, CompareSlots{[value], [otherValue]}, CompareFalse{})
      annotation_compare(remaining, vm, next, Con{CompareBindingsRest{tail, rest}, frames_ref})
    case _ _ _:
      Done{False{}}

def annotation_value_ref_equal(+vm: M.VM, left: U32, right: U32) -> Result<&2, &2, String, Bool>:
  annotation_compare(64n, vm, CompareRef{left, right}, Nil{})

def annotation_equals_bits(+vm: M.VM, left: U32, right: U32) -> Result<&2, &2, String, Bool>:
  annotation_value_ref_equal(vm, left, right)

def annotation_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    left : M.Slot <- slot0(args)
    right : M.Slot <- slot1(args)
    result : Bool <- annotation_equals_bits(vm, bits_of(left), bits_of(right))
    outcome : O.Outcome <- bool_out(vm, result)
    return outcome

def annotation_units_hash(chars: +List<U32>, acc: U32) -> U32:
  match chars:
    case Nil{}: acc
    case Con{c, rest}: annotation_units_hash(rest, (U32.mul(31, acc) + c : U32))

def annotation_hash_entry_kind(entry: M.HeapEntry, kind: U32) -> U32:
  match kind:
    case 3: annotation_units_hash(entry_chars(entry), 0)
    case 1: M.length(M.Slot, entry_values(entry))
    case 2: M.length(M.Slot, entry_values(entry))
    case _: H.entry_class(entry)

def annotation_ref_hash_nonnull(+vm: M.VM, reference: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    result : U32 = annotation_hash_entry_kind(entry, entry_kind(entry))
    return result

def annotation_ref_hash(+vm: M.VM, reference: U32) -> Result<&2, &2, String, U32>:
  match reference:
    case 0: Done{0}
    case _: annotation_ref_hash_nonnull(vm, reference)

def annotation_slot_hash(+vm: M.VM, slot: M.Slot) -> Result<&2, &2, String, U32>:
  M.Slot{tag, bits} = slot
  match tag:
    case 3: annotation_ref_hash(vm, bits)
    case _: Done{bits}

def annotation_bindings_hash(+vm: M.VM, bindings: +List<M.Binding>, acc: U32) -> Result<&2, &2, String, U32>:
  match bindings:
    case Nil{}: Done{acc}
    case Con{M.Binding{id, value}, rest}:
      do Result<&2, &2, String, U32>:
        value_hash : U32 <- annotation_slot_hash(vm, value)
        next : U32 = U32.add(U32.mul(31, acc), U32.add(id, value_hash))
        annotation_bindings_hash(vm, rest, next)

def annotation_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    hash : U32 <- annotation_bindings_hash(vm, entry_fields(entry), 0)
    result : O.Outcome <- int_out(vm, hash)
    return result

def annotation_invoke_name(+vm: M.VM, +args: +List<M.Slot>, +name: String, +descriptor: String, +element: U32, +fields: +List<M.Binding>) -> Result<&2, &2, String, O.Outcome>:
  match name:
    case "annotationType": class_mirror_out(vm, element)
    case "equals": annotation_equals(vm, args)
    case "hashCode": annotation_hash(vm, args)

    case "toString": intern_or_alloc(vm, units_from_string("@" ++ class_name_text(vm, element)))
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
        result : AnnotationValueRef <- annotation_value(vm, pool, value, method_return_name(descriptor))
        return Some{result}

def annotation_default_optional_method(+vm: M.VM, +pool: +List<M.Constant>, method_metadata: M.MethodMetadata, +descriptor: String) -> Result<&2, &2, String, Maybe<&2, AnnotationValueRef>>:
  match method_metadata:
    case M.MethodMetadata{owner, method, metadata}: annotation_default_optional_from_maybe(vm, pool, metadata_default(metadata), descriptor)

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

def annotation_default_reflect_slot(+vm: M.VM, +name: String, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name, "int"), annotation_default_box_alloc(vm, "java/lang/Integer", value),
    Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name, "boolean"), boolean_singleton_out(vm, value),
      annotation_value_outcome(AnnotationValueRef{vm, value})))

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

def type_annotation_matches(value: M.TypeAnnotation, +target: U32, +index: U32) -> Bool:
  match value:
    case M.TypeAnnotation{targetType, +targetInfo, path, annotation}: U32.is_eq(targetType, target) && Bool.or(U32.is_eq(target, 20), U32.is_eq(type_annotation_info_index(targetInfo), index))

def type_annotation_values(+values: +List<M.TypeAnnotation>, +target: U32, +index: U32, +acc: +List<M.Annotation>) -> +List<M.Annotation>:
  match values:
    case Nil{}: M.reverse(M.Annotation, acc)
    case Con{+value, rest}:
      match value:
        case M.TypeAnnotation{targetType, targetInfo, path, annotation}:
          type_annotation_values(rest, target, index, Bool.pick(+List<M.Annotation>, type_annotation_matches(value, target, index), Con{annotation, acc}, acc))

def method_type_annotation_source(+vm: M.VM, +method: M.LoadedMethod, +target: U32, +index: U32) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    class_metadata : M.ClassMetadata <- class_metadata_value(vm, M.loaded_method_owner(method))
    method_metadata : M.MethodMetadata <- method_metadata_value(vm, M.loaded_method_id(method))
    metadata : M.AnnotationMetadata = method_metadata_annotations(method_metadata)
    +annotations : +List<M.Annotation> = type_annotation_values(metadata_type_annotations(metadata), target, index, Nil{})
    result : AnnotationMetadataRef = AnnotationMetadataRef{vm, class_metadata_pool(class_metadata), M.AnnotationMetadata{0, Nil{}, annotations, Nil{}, Nil{}, None{}}}
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

def reflect_method_get_annotated_return_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    result : O.Outcome <- reflect_annotated_type_one(vm, M.loaded_method_id(method), 20)
    return result

def reflect_annotated_type_source(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, AnnotationMetadataRef>:
  do Result<&2, &2, String, AnnotationMetadataRef>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    method_slot : M.Slot <- reflect_annotation_binding(entry, 0)
    target_slot : M.Slot <- reflect_annotation_binding(entry, 1)
    index_slot : M.Slot <- reflect_annotation_binding(entry, 2)
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), bits_of(method_slot)), "java/lang/NoSuchMethodException")
    result : AnnotationMetadataRef <- method_type_annotation_source(vm, method, bits_of(target_slot), bits_of(index_slot))
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

def reflect_annotated_type_get_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    method_slot : M.Slot <- reflect_annotation_binding(entry, 0)
    target_slot : M.Slot <- reflect_annotation_binding(entry, 1)
    index_slot : M.Slot <- reflect_annotation_binding(entry, 2)
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), bits_of(method_slot)), "java/lang/NoSuchMethodException")
    descriptor : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
    parsed : M.Descriptor <- D.parse_method(descriptor)
    typ : M.JvmType <- annotated_type_value(parsed, bits_of(target_slot), bits_of(index_slot))
    +target : U32 = class_id(vm, jvm_type_class_name(typ))
    checked : Unit <- S.check(U32.is_ne(target, 4294967295), "java/lang/NoClassDefFoundError")
    result : O.Outcome <- class_mirror_out(vm, target)
    return result
def reflect_annotated_type_get_owner(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  ref_out(vm, 0)

def reflect_annotated_type_get_actuals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/reflect/AnnotatedType;"), class_id(vm, "java/lang/reflect/AnnotatedType"), Nil{})), vm2 => reference => ref_out(vm2, reference))


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

def reflect_method_get_generic_exception_types(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- reflect_method_from_args(vm, args)
    source : AnnotationMetadataRef <- method_annotation_source(vm, method)
    result : O.Outcome <- method_generic_exception_types(source)
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

def public_methods(methods: +List<M.LoadedMethod>, +classes: +List<M.LoadedClass>, +target: U32, +symbols: +List<String>, +acc: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match methods:
    case Nil{}: M.reverse(M.LoadedMethod, acc)
    case Con{+method, rest}:
      +belongs : Bool = H.hierarchy(classes, target, M.loaded_method_owner(method))
      public_methods(rest, classes, target, symbols, public_method_cons(Bool.pick(Maybe<&2, M.LoadedMethod>, method_is_public_ordinary(method, symbols) && belongs, Some{method}, None{}), acc))


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
def find_public_field(fields: +List<M.LoadedField>, +classes: +List<M.LoadedClass>, +owner: U32, +name: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedField>:
  match fields:
    case Nil{}: None{}
    case Con{+field, rest}:
      +field_name : String = Sy.text(symbols, M.loaded_field_name(field))
      +public : Bool = U32.is_ne(U32.and(M.loaded_field_flags(field), 1), 0)
      +belongs : Bool = H.hierarchy(classes, owner, M.loaded_field_owner(field))
      Bool.pick(Maybe<&2, M.LoadedField>, public && belongs && String.eq(field_name, name), Some{field}, find_public_field(rest, classes, owner, name, symbols))

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
  M.Slot{+tag, +reference} = value
  reflect_parameter_name_checked(vm, tag, reference)

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

def find_declared_method_exact(methods: +List<M.LoadedMethod>, +owner: U32, +name: String, +prefix: String, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      +method_name : String = Sy.text(symbols, M.loaded_method_name(method))
      +ordinary : Bool = Bool.not(String.eq(method_name, "<init>")) && Bool.not(String.eq(method_name, "<clinit>"))
      +selected : Bool = U32.is_eq(M.loaded_method_owner(method), owner) && ordinary && String.eq(method_name, name) && method_matches_prefix(method, prefix, symbols)
      Bool.pick(Maybe<&2, M.LoadedMethod>, selected, Some{method}, find_declared_method_exact(rest, owner, name, prefix, symbols))

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
      +belongs : Bool = H.hierarchy(classes, owner, M.loaded_method_owner(method))
      +selected : Bool = public && belongs && String.eq(method_name, name) && method_matches_prefix(method, prefix, symbols)
      Bool.pick(Maybe<&2, M.LoadedMethod>, selected, Some{method}, find_public_method_exact(rest, classes, owner, name, prefix, symbols))

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
    method : M.LoadedMethod <- S.require(M.LoadedMethod, find_declared_method_exact(S.methods(vm), target, name, prefix, S.symbols(vm)), "java/lang/NoSuchMethodException")
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

def class_display_name(name: String) -> String:
  match name:
    case SNil{}: ""
    case SCon{Chr{47}, rest}: SCon{Chr{46}, class_display_name(rest)}
    case SCon{head, rest}: SCon{head, class_display_name(rest)}

def class_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- class_target(vm, args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(class_display_name(class_name_text(vm, target))))
    return result
def type_get_type_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  class_name(vm, args)

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
    left_owner : M.Slot <- reflect_binding(left_entry, 0)
    right_owner : M.Slot <- reflect_binding(right_entry, 0)
    left_id : M.Slot <- reflect_binding(left_entry, 1)
    right_id : M.Slot <- reflect_binding(right_entry, 1)
    result : Bool = U32.is_eq(H.entry_class(left_entry), H.entry_class(right_entry)) && U32.is_eq(bits_of(left_owner), bits_of(right_owner)) && U32.is_eq(bits_of(left_id), bits_of(right_id))
    return result

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

def reflect_member_hash(+vm: M.VM, +args: +List<M.Slot>, +expected: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    owner : M.Slot <- reflect_binding(entry, 0)
    id : M.Slot <- reflect_binding(entry, 1)
    result : O.Outcome <- int_out(vm, U32.add(U32.mul(bits_of(owner), 31), bits_of(id)))
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
    case Some{M.Slot{tag, bits}}: U32.is_ne(bits, 0)

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

def same_package(+vm: M.VM, left: U32, right: U32) -> Bool:
  String.eq(resource_package(class_name_text(vm, left)), resource_package(class_name_text(vm, right)))

def class_public(+vm: M.VM, target: U32) -> Bool:
  U32.is_ne(U32.and(class_flags(vm, target), 1), 0)
def member_accessible(+vm: M.VM, +caller: U32, +owner: U32, +flags: U32) -> Bool:
  +public : Bool = U32.is_ne(U32.and(flags, 1), 0)
  +private : Bool = U32.is_ne(U32.and(flags, 2), 0)
  +protected : Bool = U32.is_ne(U32.and(flags, 4), 0)
  +package : Bool = same_package(vm, caller, owner)
  +class_ok : Bool = class_public(vm, owner) || package
  Bool.and(class_ok,
    Bool.pick(Bool, public, True{},
      Bool.pick(Bool, private, U32.is_eq(caller, owner),
        Bool.pick(Bool, protected, package || H.hierarchy(S.classes(vm), caller, owner), package))))
def protected_receiver_entry(+vm: M.VM, +target: U32, +caller: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Bool:
  match result:
    case Fail{error}: False{}
    case Done{entry}: H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), caller)

def protected_receiver_target(+vm: M.VM, +target: U32, +caller: U32) -> Bool:
  match target:
    case 0: True{}
    case reference: protected_receiver_entry(vm, target, caller, H.get(S.heap(vm), reference))

def protected_receiver_required(+vm: M.VM, +owner: U32, +flags: U32, +caller: U32) -> Bool:
  U32.is_ne(U32.and(flags, 4), 0) &&
  U32.is_eq(U32.and(flags, 8), 0) &&
  Bool.not(same_package(vm, caller, owner)) &&
  H.hierarchy(S.classes(vm), caller, owner)

def protected_receiver_accessible(+vm: M.VM, +owner: U32, +flags: U32, +target: U32) -> Bool:
  +caller : U32 = caller_owner(vm)
  Bool.pick(Bool, protected_receiver_required(vm, owner, flags, caller), protected_receiver_target(vm, target, caller), True{})



def reflective_access(+vm: M.VM, +entry: M.HeapEntry, owner: U32, flags: U32) -> Bool:
  Bool.or(accessible_override(entry), member_accessible(vm, caller_owner(vm), owner, flags))
def reflective_method_access(+vm: M.VM, +entry: M.HeapEntry, +owner: U32, +flags: U32, target: U32) -> Bool:
  Bool.and(reflective_access(vm, entry, owner, flags), protected_receiver_accessible(vm, owner, flags, target))



def accessible_update(entry: M.HeapEntry, value: M.Slot) -> M.HeapEntry:
  M.HeapEntry{+class, kind, element, +fields, values, chars} = entry
  M.HeapEntry{class, kind, element, H.binding_set(fields, 2, value), values, chars}

def accessible_set(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    value : M.Slot <- slot1(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
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
def reflect_static_field_value(+vm: M.VM, field: M.LoadedField) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- S.require(M.Slot, H.binding_find(S.statics(vm), M.loaded_field_id(field)), "java/lang/NoSuchFieldException")
    result : O.Outcome <- returned(vm, Some{value})
    return result

def reflect_instance_field_value(+vm: M.VM, field: M.LoadedField, target: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +field_ref : M.LoadedField = field
    +target_ref : U32 = target
    checked : Unit <- S.check(U32.is_ne(target_ref, 0), npe())
    +entry : M.HeapEntry <- H.get(S.heap(vm), target_ref)
    belongs : Unit <- S.check(H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), M.loaded_field_owner(field_ref)), "java/lang/IllegalArgumentException")
    value : M.Slot <- S.require(M.Slot, H.binding_find(entry_fields(entry), M.loaded_field_id(field_ref)), "java/lang/NoSuchFieldException")
    result : O.Outcome <- returned(vm, Some{value})
    return result
def reflect_field_value(+vm: M.VM, field: M.LoadedField, target: U32) -> Result<&2, &2, String, O.Outcome>:
  +field_ref : M.LoadedField = field
  +target_ref : U32 = target
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_ne(U32.and(M.loaded_field_flags(field_ref), 8), 0), reflect_static_field_value(vm, field_ref), reflect_instance_field_value(vm, field_ref, target_ref))

def reflect_field_get(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +handle : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +field : M.LoadedField <- reflect_field_member(vm, args)
    checked : Unit <- S.check(reflective_access(vm, handle, M.loaded_field_owner(field), M.loaded_field_flags(field)), "java/lang/IllegalAccessException")
    target : M.Slot <- slot1(args)
    result : O.Outcome <- reflect_field_value(vm, field, bits_of(target))
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

def reflect_field_set(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +handle : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +field : M.LoadedField <- reflect_field_member(vm, args)
    checked : Unit <- S.check(reflective_access(vm, handle, M.loaded_field_owner(field), M.loaded_field_flags(field)), "java/lang/IllegalAccessException")
    final_checked : Unit <- S.check(reflect_field_set_allowed(handle, field), "java/lang/IllegalAccessException")
    target : M.Slot <- slot1(args)
    value : M.Slot <- slot2(args)
    result : O.Outcome <- reflect_field_set_value(vm, field, bits_of(target), value)
    return result

def reflect_method_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_method_member(vm, args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(Sy.text(S.symbols(vm), M.loaded_method_name(method))))
    return result
def reflect_binding_slot(found: Maybe<&2, M.Slot>) -> M.Slot:
  match found:
    case None{}: M.Slot{0, 0}
    case Some{value}: value

def reflect_unbox_wrapper(+name: String, slot: M.Slot, value: M.Slot) -> M.Slot:
  +name_ref : String = name
  wrapper : Bool = String.eq(name_ref, "java/lang/Boolean") || String.eq(name_ref, "java/lang/Byte") || String.eq(name_ref, "java/lang/Character") || String.eq(name_ref, "java/lang/Short") || String.eq(name_ref, "java/lang/Integer") || String.eq(name_ref, "java/lang/Float")
  Bool.pick(M.Slot, wrapper, slot, value)

def reflect_unbox_entry(vm: M.VM, value: M.Slot, result: Result<&2, &2, String, M.HeapEntry>) -> M.Slot:
  match result:
    case Fail{error}: value
    case Done{+entry}: reflect_unbox_wrapper(class_name_text(vm, H.entry_class(entry)), reflect_binding_slot(H.binding_find(entry_fields(entry), 0)), value)

def reflect_unbox_reference(+vm: M.VM, reference: U32, value: M.Slot) -> M.Slot:
  +vm_ref : M.VM = vm
  reflect_unbox_entry(vm, value, H.get(S.heap(vm_ref), reference))

def reflect_unbox_tag(vm: M.VM, tag: U32, reference: U32, value: M.Slot) -> M.Slot:
  match tag:
    case 3:
      match reference:
        case 0: value
        case _: reflect_unbox_reference(vm, reference, value)
    case _: value

def reflect_unbox_value(vm: M.VM, value: M.Slot) -> M.Slot:
  M.Slot{+tag, +bits} = value
  +value_ref : M.Slot = M.Slot{tag, bits}
  reflect_unbox_tag(vm, tag, bits, value_ref)

def reflect_unbox_values(+vm: M.VM, +values: +List<M.Slot>) -> +List<M.Slot>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: Con{reflect_unbox_value(vm, value), reflect_unbox_values(vm, rest)}

def reflect_argument_values(+vm: M.VM, array_ref: U32) -> Result<&2, &2, String, +List<M.Slot>>:
  match array_ref:
    case 0: Done{Nil{}}
    case reference:
      do Result<&2, &2, String, +List<M.Slot>>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        return reflect_unbox_values(vm, entry_values(entry))


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
    +selected : M.LoadedMethod <- reflect_method_dispatch(vm, method, bits_of(target_ref))
    invoke_args : +List<M.Slot> = Bool.pick(+List<M.Slot>, static, values, Con{target_ref, values})
    return O.Call{S.with_effect(vm, M.ReflectCall{}), selected, invoke_args}


def reflect_method_invoke(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- slot0(args)
    +handle : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    +method : M.LoadedMethod <- reflect_method_member(vm, args)
    +target : M.Slot <- slot1(args)
    checked : Unit <- S.check(reflective_method_access(vm, handle, M.loaded_method_owner(method), M.loaded_method_flags(method), bits_of(target)), "java/lang/IllegalAccessException")
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
def reflect_member_generic_parameter_types(+vm: M.VM, +method: M.LoadedMethod) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
    parsed : M.Descriptor <- D.parse_method(descriptor)
    +ids : +List<U32> <- parameter_class_ids(vm, D.parameter_types(parsed), Nil{})
    refs : ReflectRefs <- parameter_mirror_alloc(vm, ids, Nil{})
    result : O.Outcome <- reflect_refs_array(refs, "[Ljava/lang/reflect/Type;", "java/lang/reflect/Type")
    return result

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
    checked : Unit <- S.check(reflective_access(vm, handle, M.loaded_method_owner(method), M.loaded_method_flags(method)), "java/lang/IllegalAccessException")
    instantiable : Unit <- S.check(constructor_instantiable(vm, M.loaded_method_owner(method)), "java/lang/InstantiationException")
    argument_array : M.Slot <- slot1(args_ref)
    +values : +List<M.Slot> <- reflect_argument_values(vm, bits_of(argument_array))
    result : O.Outcome <- reflect_constructor_instance_alloc(vm, method, M.loaded_method_owner(method), values)
    return result

def reflect_constructor_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method : M.LoadedMethod <- reflect_constructor_member(vm, args)
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(class_name_text(vm, M.loaded_method_owner(method))))
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

def string_hash_go(chars: +List<U32>, acc: U32) -> U32:
  match chars:
    case Nil{}: acc
    case Con{c, rest}: string_hash_go(rest, (U32.mul(31, acc) + c : U32))

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

def object_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    result : O.Outcome <- int_out(vm, bits_of(receiver))
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



def execute_known(id: U32, vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 12: object_equals(vm, args)
    case 13: object_hash(vm, args)
    case 14: object_to_string(vm, args)
    case _: Fail{"MissingMethod: unknown intrinsic"}

def call_virtual(+vm: M.VM, method: Maybe<&2, M.LoadedMethod>, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match method:
    case None{}: Fail{"java/lang/NoSuchMethodError"}
    case Some{+value}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_ne(M.loaded_method_intrinsic(value), 0), execute_known(M.loaded_method_intrinsic(value), vm, args), Done{O.Call{vm, value, args}})

def push_cont(+vm: M.VM, item: M.Cont) -> M.VM:
  S.with_cont(vm, Con{item, S.host_cont_of(S.host(vm))})

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
def wide_entry_valid(+entry: M.HeapEntry) -> Bool:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}: U32.is_eq(kind, 9)

def wide_box(+vm: M.VM, +args: +List<M.Slot>, +class_name: String, tag: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(value))
    checked : Unit <- S.check(wide_entry_valid(entry), "java/lang/IllegalArgumentException")
    result : O.Outcome <- alloc_result(H.allocate(vm, H.wide_object_entry(class_id(vm, class_name), tag, H.wide_high(entry), H.wide_low(entry))), vm2 => reference => ref_out(vm2, reference))
    return result

def wide_value_alloc(tag: U32, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}:
      Done{O.Returned{updated, Some{M.Slot{tag, reference}}}}

def wide_value(+vm: M.VM, +args: +List<M.Slot>, +tag: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    checked : Unit <- S.check(wide_entry_valid(entry), "java/lang/IllegalArgumentException")
    result : O.Outcome <- wide_value_alloc(tag, H.allocate(vm, H.wide_entry(tag, H.wide_high(entry), H.wide_low(entry))))
    return result

def long_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    text : String = W.long_show(W.Words{H.wide_high(entry), H.wide_low(entry)})
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(text))
    return result
def double_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits_of(receiver))
    text : String = W.double_show(W.Words{H.wide_high(entry), H.wide_low(entry)})
    result : O.Outcome <- intern_or_alloc(vm, units_from_string(text))
    return result



def parse_digit(+c: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_ge(c, 48) && U32.is_le(c, 57), Some{U32.sub(c, 48)}, None{})

def parse_acc(+acc: U32, +d: U32, +neg: Bool) -> Maybe<&2, U32>:
  +limit = Bool.pick(U32, neg, 2147483648, 2147483647)
  Bool.pick(Maybe<&2, U32>, U32.is_gt(acc, U32.div(limit, 10)), None{},
    Bool.pick(Maybe<&2, U32>, U32.is_gt(U32.mul(acc, 10), U32.sub(limit, d)), None{}, Some{U32.add(U32.mul(acc, 10), d)}))

def require_digit(found: Maybe<&2, U32>) -> Result<&2, &2, String, U32>:
  match found:
    case None{}: Fail{nfe()}
    case Some{d}: Done{d}

def require_acc(found: Maybe<&2, U32>) -> Result<&2, &2, String, U32>:
  match found:
    case None{}: Fail{nfe()}
    case Some{d}: Done{d}

@unsafe def parse_go(chars: +List<U32>, +acc: U32, seen: Bool, +neg: Bool) -> Result<&2, &2, String, U32>:
  match chars:
    case Nil{}:
      Bool.pick(Result<&2, &2, String, U32>, seen, Done{Bool.pick(U32, neg, V.negate(acc), acc)}, Fail{nfe()})
    case Con{c, rest}:
      do Result<&2, &2, String, U32>:
        d : U32 <- require_digit(parse_digit(c))
        next : U32 <- require_acc(parse_acc(acc, d, neg))
        result : U32 <- parse_go(rest, next, True{}, neg)
        return result

def parse_sign(chars: +List<U32>) -> Result<&2, &2, String, U32>:
  match chars:
    case Nil{}: Fail{nfe()}
    case Con{43, rest}: parse_go(rest, 0, False{}, False{})
    case Con{45, rest}: parse_go(rest, 0, False{}, True{})
    case _: parse_go(chars, 0, False{}, False{})

def integer_parse(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- slot0(args)
    checked : Unit <- S.check(U32.is_ne(bits_of(value), 0), npe())
    chars : +List<U32> <- string_chars(vm, bits_of(value))
    bits : U32 <- parse_sign(chars)
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

def map_hit(+vm: M.VM, +map: U32, +key: U32, +index: U32, +op: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match op:
    case 0: returned(vm, Some{value})
    case 1: returned(vm, Some{value})
    case 2: bool_out(vm, True{})
    case 3: map_remove_at(vm, map, index, value)
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
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, M.Slot{3, message}}, M.Binding{1, M.Slot{3, cause}}, M.Binding{2, M.Slot{3, 0}}, M.Binding{3, M.Slot{1, flags}}], Nil{}, Nil{}}
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
    case Con{M.Slot{tag, bits}, rest}: Con{bits, property_units(rest)}


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

def continue_to_string(+vm: M.VM, +op: U32, +extra: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match op:
    case 1:
      do Result<&2, &2, String, O.Outcome>:
        chars : +List<U32> <- string_chars(vm, bits_of(value))
        result : O.Outcome <- builder_append_chars(vm, extra, chars)
        return result
    case _:
      returned(vm, Some{value})

def reflect_box_alloc(+vm: M.VM, +name: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  alloc_result(H.allocate(vm, H.object_entry(class_id(vm, name), [M.Binding{0, value}])), vm2 => reference => ref_out(vm2, reference))

def reflect_box_value(+vm: M.VM, name: String, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  +name_ref : String = name
  +value_ref : M.Slot = value
  Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name_ref, "boolean"), reflect_box_alloc(vm, "java/lang/Boolean", value_ref),
    Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name_ref, "float"), reflect_box_alloc(vm, "java/lang/Float", value_ref),
      Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name_ref, "char"), reflect_box_alloc(vm, "java/lang/Character", value_ref),
        Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name_ref, "byte"), reflect_box_alloc(vm, "java/lang/Byte", value_ref),
          Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name_ref, "short"), reflect_box_alloc(vm, "java/lang/Short", value_ref),
            Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name_ref, "int") || String.eq(name_ref, "long"), reflect_box_alloc(vm, "java/lang/Integer", value_ref), returned(vm, Some{value_ref})))))))

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
        wrapper : String = proxy_wrapper_name(name)
        +wrapper_id : U32 = class_id(vm, wrapper)
        wrapper_checked : Unit <- S.check(U32.is_ne(wrapper_id, 4294967295), "UnsupportedFeature: proxy wide primitive return")
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        checked_type : Unit <- S.check(U32.is_eq(H.entry_class(entry), wrapper_id), "java/lang/ClassCastException")
        return reflect_unbox_value(vm, value)

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

def proxy_return_value(+vm: M.VM, +descriptor: String, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  +name : String = method_return_name(descriptor)
  Bool.pick(Result<&2, &2, String, M.Slot>, String.eq(name, "void"), Done{value}, Bool.pick(Result<&2, &2, String, M.Slot>, primitive_name(name), proxy_return_primitive(vm, name, value), proxy_return_reference(vm, name, value)))

def reflect_box_return(+vm: M.VM, descriptor: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  reflect_box_value(vm, method_return_name(descriptor), value)


def continue_throwable_message(+vm: M.VM, +receiver: U32, +cause: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), receiver)
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, M.Slot{3, bits_of(value)}}, M.Binding{1, M.Slot{3, cause}}, M.Binding{2, M.Slot{3, 0}}, M.Binding{3, M.Slot{1, 1}}], Nil{}, Nil{}}
    result : O.Outcome <- void_out(H.put(vm, receiver, updated))
    return result

def continue_java(+vm: M.VM, cont: M.Cont, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
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

def enum_value_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  ref_out(vm, 0)
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
