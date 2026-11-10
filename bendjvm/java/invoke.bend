import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ./library.bend as L
import ./outcome.bend as O
import ../classfile/descriptor.bend as D

type RefList is Data:
  RefList{vm: M.VM, refs: +List<U32>}

def alloc_ref(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{vm, reference}}: L.ref_out(vm, reference)

def receiver(args: +List<M.Slot>) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +slot : M.Slot <- L.slot0(args)
    checked : Unit <- S.check(U32.is_ne(M.slot_bits(slot), 0), "java/lang/NullPointerException")
    return M.slot_bits(slot)
def arg(args: +List<M.Slot>, index: U32) -> Result<&2, &2, String, M.Slot>:
  S.require(M.Slot, M.nth(M.Slot, args, index), "java/lang/IllegalArgumentException")

def bits(slot: M.Slot) -> U32:
  M.slot_bits(slot)

def text(vm: M.VM, reference: U32) -> Result<&2, &2, String, String>:
  L.string_text(vm, reference)

def class_id(+vm: M.VM, name: String) -> U32:
  H.named_class(S.classes(vm), S.symbols(vm), name)

def class_mirror(vm: M.VM, class_id: U32) -> Result<&2, &2, String, O.Outcome>:
  L.class_mirror_out(vm, class_id)

def type_entry(class: U32, descriptor: U32) -> M.HeapEntry:
  M.HeapEntry{class, H.kind_method_type(), descriptor, Nil{}, Nil{}, Nil{}}

# Bindings: 0 owner, 1 name, 2 descriptor, 3 specialCaller, 4 adapter mode,
# 5-8 adapter state, 9+ insertArguments values, 0xFFFFFFFF varargs-collector flag.
def handle_entry(class: U32, kind: U32, owner: U32, name: U32, desc: U32, special: U32) -> M.HeapEntry:
  M.HeapEntry{class, H.kind_method_handle(), kind,
    [M.Binding{0, M.Slot{1, owner}}, M.Binding{1, M.Slot{1, name}}, M.Binding{2, M.Slot{1, desc}},
     M.Binding{3, M.Slot{1, special}}, M.Binding{4, M.Slot{1, 0}}, M.Binding{5, M.Slot{3, 0}},
     M.Binding{6, M.Slot{1, 0}}, M.Binding{7, M.Slot{1, 0}}, M.Binding{8, M.Slot{3, 0}},
     M.Binding{4294967295, M.Slot{1, 0}}], Nil{}, Nil{}}

def bindings_with_target(fields: +List<M.Binding>, target: M.Slot) -> +List<M.Binding>:
  H.binding_set(fields, 0, target)

def callsite_entry(class: U32, kind: U32, target: M.Slot) -> M.HeapEntry:
  M.HeapEntry{class, H.kind_call_site(), kind, [M.Binding{0, target}], Nil{}, Nil{}}

def lookup_entry(class: U32, owner: U32, modes: U32) -> M.HeapEntry:
  M.HeapEntry{class, H.kind_lookup(), 0, [M.Binding{0, M.Slot{1, owner}}, M.Binding{1, M.Slot{1, modes}}], Nil{}, Nil{}}

def interned_id(value: Sy.Interned) -> U32:
  match value:
    case Sy.Interned{symbols, id}: id

def alloc_type(+vm: M.VM, +desc: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +interned : Sy.Interned = Sy.intern(S.symbols(vm), desc)
    +vm2 : M.VM = S.with_symbols(vm, Sy.interned_symbols(interned))
    id : U32 = interned_id(interned)
    result : O.Outcome <- alloc_ref(H.allocate(vm2, type_entry(class_id(vm2, "java/lang/invoke/MethodType"), id)))
    return result

# `mirror` is the heap reference of a java.lang.Class object, not a class id.
def class_descriptor(+vm: M.VM, mirror: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), mirror)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), 8), "java/lang/IllegalArgumentException")
    target : U32 = L.entry_element(entry)
    target_class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), target), "java/lang/IllegalArgumentException")
    +name : String = L.class_name_text(vm, M.loaded_class_id(target_class))
    descriptor : String = Bool.pick(String, String.starts_with(name, "["), name,
      Bool.pick(String, String.eq(name, "boolean"), "Z", Bool.pick(String, String.eq(name, "byte"), "B",
      Bool.pick(String, String.eq(name, "char"), "C", Bool.pick(String, String.eq(name, "short"), "S",
      Bool.pick(String, String.eq(name, "int"), "I", Bool.pick(String, String.eq(name, "long"), "J",
      Bool.pick(String, String.eq(name, "float"), "F", Bool.pick(String, String.eq(name, "double"), "D",
      Bool.pick(String, String.eq(name, "void"), "V", "L" ++ name ++ ";"))))))))))
    return descriptor

def parameter_descriptors(+vm: M.VM, +params: +List<M.Slot>) -> Result<&2, &2, String, String>:
  match params:
    case Nil{}: Done{""}
    case Con{slot, rest}:
      do Result<&2, &2, String, String>:
        +desc : String <- class_descriptor(vm, bits(slot))
        checked : Unit <- S.check(Bool.not(String.eq(desc, "V")), "java/lang/IllegalArgumentException")
        tail : String <- parameter_descriptors(vm, rest)
        return desc ++ tail
def descriptor_from_classes(+vm: M.VM, +params: +List<M.Slot>, result: M.Slot) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    ret : String <- class_descriptor(vm, bits(result))
    +prefix : String <- parameter_descriptors(vm, params)
    return "(" ++ prefix ++ ")" ++ ret


def methodtype_from_class_args(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ret : M.Slot <- arg(args, 0)
    array_slot : M.Slot <- arg(args, 1)
    +array : M.HeapEntry <- H.get(S.heap(vm), bits(array_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(array), 2), "java/lang/IllegalArgumentException")
    desc : String <- descriptor_from_classes(vm, L.entry_values(array), ret)
    result : O.Outcome <- alloc_type(vm, desc)
    return result

def methodtype_from_return(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ret : M.Slot <- arg(args, 0)
    desc : String <- descriptor_from_classes(vm, Nil{}, ret)
    result : O.Outcome <- alloc_type(vm, desc)
    return result

def methodtype_from_return_param(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ret : M.Slot <- arg(args, 0)
    param : M.Slot <- arg(args, 1)
    desc : String <- descriptor_from_classes(vm, [param], ret)
    result : O.Outcome <- alloc_type(vm, desc)
    return result

# methodType(Class rtype, Class ptype0, Class... ptypes).
def methodtype_from_first_rest(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ret : M.Slot <- arg(args, 0)
    +first : M.Slot <- arg(args, 1)
    +array_slot : M.Slot <- arg(args, 2)
    checked : Unit <- S.check(U32.is_ne(bits(array_slot), 0), "java/lang/NullPointerException")
    +array : M.HeapEntry <- H.get(S.heap(vm), bits(array_slot))
    kind_ok : Unit <- S.check(U32.is_eq(L.entry_kind(array), 2), "java/lang/IllegalArgumentException")
    +desc : String <- descriptor_from_classes(vm, Con{first, L.entry_values(array)}, ret)
    result : O.Outcome <- alloc_type(vm, desc)
    return result

# methodType(Class rtype, MethodType ptypes): the parameters of another type.
@unsafe def methodtype_from_type(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ret : M.Slot <- arg(args, 0)
    +other : M.Slot <- arg(args, 1)
    checked : Unit <- S.check(U32.is_ne(bits(other), 0), "java/lang/NullPointerException")
    +other_desc : String <- type_desc(vm, bits(other))
    +ret_desc : String <- class_descriptor(vm, bits(ret))
    result : O.Outcome <- alloc_type(vm, "(" ++ String.from_list(chars_before(chars_after(String.to_list(other_desc), 40, False{}), 41)) ++ ")" ++ ret_desc)
    return result

def type_desc(+vm: M.VM, reference: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_method_type()), "java/lang/IllegalArgumentException: not a MethodType")
    return Sy.text(S.symbols(vm), L.entry_element(entry))

def chars_after(chars: +List<Char>, +marker: U32, found: Bool) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{+c}, +rest}:
      Bool.pick(+List<Char>, found, Con{Chr{c}, rest}, chars_after(rest, marker, U32.is_eq(c, marker)))

def chars_before(chars: +List<Char>, +marker: U32) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{+c}, rest}:
      Bool.pick(+List<Char>, U32.is_eq(c, marker), Nil{}, Con{Chr{c}, chars_before(rest, marker)})



def descriptor_object_body(chars: +List<Char>) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{59}, rest}: Nil{}
    case Con{c, rest}: Con{c, descriptor_object_body(rest)}

# "Lpkg/Name;" -> "pkg/Name": only the leading tag is removed, so names that
# contain 'L' (for example java/lang/Long) are preserved.
def descriptor_object_name(chars: +List<Char>) -> +List<Char>:
  match chars:
    case Con{Chr{76}, rest}: descriptor_object_body(rest)
    case other: descriptor_object_body(other)

def primitive_name(+desc: String) -> String:
  Bool.pick(String, String.eq(desc, "Z"), "boolean", Bool.pick(String, String.eq(desc, "B"), "byte", Bool.pick(String, String.eq(desc, "C"), "char", Bool.pick(String, String.eq(desc, "S"), "short", Bool.pick(String, String.eq(desc, "I"), "int", Bool.pick(String, String.eq(desc, "J"), "long", Bool.pick(String, String.eq(desc, "F"), "float", Bool.pick(String, String.eq(desc, "D"), "double", Bool.pick(String, String.eq(desc, "V"), "void", desc)))))))))
def descriptor_name(+desc: String) -> String:
  Bool.pick(String, String.starts_with(desc, "L"),
    String.from_list(descriptor_object_name(String.to_list(desc))),
    Bool.pick(String, String.starts_with(desc, "["), desc, primitive_name(desc)))
def descriptor_class(vm: M.VM, desc: String) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +name : String = descriptor_name(desc)
    +id : U32 = class_id(vm, name)
    checked : Unit <- S.check(U32.is_ne(id, 4294967295), "java/lang/IllegalArgumentException: type not loaded: " ++ name)
    return id
def type_return(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    desc : String <- type_desc(vm, ref)
    result_desc : String = String.from_list(chars_after(String.to_list(desc), 41, False{}))
    target : U32 <- descriptor_class(vm, result_desc)
    result : O.Outcome <- class_mirror(vm, target)
    return result


def descriptor_count(chars: +List<Char>, count: U32, in_object: Bool) -> U32:
  match chars in_object:
    case Nil{} _: count
    case Con{Chr{76}, rest} False{}: descriptor_count(rest, count, True{})
    case Con{Chr{59}, rest} True{}: descriptor_count(rest, U32.add(count, 1), False{})
    case Con{Chr{91}, rest} False{}: descriptor_count(rest, count, False{})
    case Con{c, rest} True{}: descriptor_count(rest, count, True{})
    case Con{c, rest} False{}: descriptor_count(rest, U32.add(count, 1), False{})

def count_descriptor_parameters(desc: String) -> U32:
  descriptor_count(chars_before(chars_after(String.to_list(desc), 40, False{}), 41), 0, False{})

def methodtype_count(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    desc : String <- type_desc(vm, ref)
    result : O.Outcome <- L.int_out(vm, count_descriptor_parameters(desc))
    return result
def descriptor_params(desc: String) -> +List<Char>:
  chars_before(chars_after(String.to_list(desc), 40, False{}), 41)

type DescriptorParameters is Data:
  DescriptorParameters{vm: M.VM, values: +List<M.Slot>}
def descriptor_parameters_vm(value: DescriptorParameters) -> M.VM:
  DescriptorParameters{vm, values} = value
  vm
def descriptor_parameters_values(value: DescriptorParameters) -> +List<M.Slot>:
  DescriptorParameters{vm, values} = value
  values

type DescriptorMirror is Data:
  DescriptorMirror{vm: M.VM, reference: U32}
def descriptor_parameter_mirror(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, DescriptorMirror>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{vm, Some{M.Slot{3, reference}}}}: Done{DescriptorMirror{vm, reference}}
    case Done{_}: Fail{"InvalidState: MethodType mirror allocation"}
def descriptor_mirror_vm(value: DescriptorMirror) -> M.VM:
  DescriptorMirror{vm, reference} = value
  vm
def descriptor_mirror_reference(value: DescriptorMirror) -> U32:
  DescriptorMirror{vm, reference} = value
  reference

@unsafe def descriptor_parameter_mirrors(+vm: M.VM, chars: +List<Char>, +acc: +List<M.Slot>, +pending: String) -> Result<&2, &2, String, DescriptorParameters>:
  match chars:
    case Nil{}:
      Bool.pick(Result<&2, &2, String, DescriptorParameters>, String.is_empty(pending), Done{DescriptorParameters{vm, M.reverse(M.Slot, acc)}}, Fail{"java/lang/IllegalArgumentException"})
    case Con{Chr{91}, +rest}:
      descriptor_parameter_mirrors(vm, rest, acc, pending ++ "[")
    case Con{Chr{76}, +rest}:
      descriptor_parameter_mirrors(vm, rest, acc, pending ++ "L")
    case Con{Chr{59}, +rest}:
      do Result<&2, &2, String, DescriptorParameters>:
        checked : Unit <- S.check(String.starts_with(pending, "L") || String.starts_with(pending, "[L"), "java/lang/IllegalArgumentException")
        id : U32 <- descriptor_class(vm, pending ++ ";")
        +mirror : DescriptorMirror <- descriptor_parameter_mirror(class_mirror(vm, id))
        result : DescriptorParameters <- descriptor_parameter_mirrors(descriptor_mirror_vm(mirror), rest, Con{M.Slot{3, descriptor_mirror_reference(mirror)}, acc}, "")
        return result
    case Con{Chr{+c}, +rest}:
      Bool.pick(Result<&2, &2, String, DescriptorParameters>, String.is_empty(pending),
        do Result<&2, &2, String, DescriptorParameters>:
          checked : Unit <- S.check(Bool.not(U32.is_eq(c, 86)), "java/lang/IllegalArgumentException")
          id : U32 <- descriptor_class(vm, Char.show(Chr{c}))
          +mirror : DescriptorMirror <- descriptor_parameter_mirror(class_mirror(vm, id))
          result : DescriptorParameters <- descriptor_parameter_mirrors(descriptor_mirror_vm(mirror), rest, Con{M.Slot{3, descriptor_mirror_reference(mirror)}, acc}, "")
          return result
        Bool.pick(Result<&2, &2, String, DescriptorParameters>, String.starts_with(pending, "["),
          do Result<&2, &2, String, DescriptorParameters>:
            id : U32 <- descriptor_class(vm, pending ++ Char.show(Chr{c}))
            +mirror : DescriptorMirror <- descriptor_parameter_mirror(class_mirror(vm, id))
            result : DescriptorParameters <- descriptor_parameter_mirrors(descriptor_mirror_vm(mirror), rest, Con{M.Slot{3, descriptor_mirror_reference(mirror)}, acc}, "")
            return result
          descriptor_parameter_mirrors(vm, rest, acc, pending ++ Char.show(Chr{c}))))
def array_classes(vm: M.VM, desc: String) -> Result<&2, &2, String, DescriptorParameters>:
  descriptor_parameter_mirrors(vm, descriptor_params(desc), Nil{}, "")

def methodtype_parameter_array(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ref : U32 <- receiver(args)
    desc : String <- type_desc(vm, ref)
    +params : DescriptorParameters <- array_classes(vm, desc)
    array_class_id : U32 = class_id(descriptor_parameters_vm(params), "[Ljava/lang/Class;")
    result : O.Outcome <- alloc_ref(H.allocate(descriptor_parameters_vm(params), H.reference_array_entry(array_class_id, class_id(descriptor_parameters_vm(params), "java/lang/Class"), descriptor_parameters_values(params))))
    return result

def methodtype_param(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ref : U32 <- receiver(args)
    +index : M.Slot <- arg(args, 1)
    desc : String <- type_desc(vm, ref)
    +params : DescriptorParameters <- array_classes(vm, desc)
    value : M.Slot <- S.require(M.Slot, M.nth(M.Slot, descriptor_parameters_values(params), bits(index)), "java/lang/IndexOutOfBoundsException")
    result : O.Outcome <- L.ref_out(descriptor_parameters_vm(params), bits(value))
    return result


def units_from_chars(chars: +List<Char>) -> +List<U32>:
  match chars:
    case Nil{}: Nil{}
    case Con{c, rest}: Con{Char.to_u32(c), units_from_chars(rest)}

def units_from_text(text: String) -> +List<U32>:
  units_from_chars(String.to_list(text))
def methodtype_string(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ref : U32 <- receiver(args)
    desc : String <- type_desc(vm, ref)
    result : O.Outcome <- L.intern_or_alloc(vm, units_from_text(desc))
    return result

def type_entry_at(heap: +List<M.HeapEntry>, reference: U32) -> Result<&2, &2, String, M.HeapEntry>:
  H.get(heap, reference)

def type_entries_equal(left: M.HeapEntry, right: M.HeapEntry) -> Bool:
  match left right:
    case M.HeapEntry{a, +ak, ad, af, av, ac} M.HeapEntry{b, +bk, bd, bf, bv, bc}:
      U32.is_eq(ak, H.kind_method_type()) && U32.is_eq(bk, H.kind_method_type()) && U32.is_eq(ad, bd)
def type_entries_equal_result(left: M.HeapEntry, result: Result<&2, &2, String, M.HeapEntry>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{right}: type_entries_equal(left, right)
def type_entries_equal_left(result: Result<&2, &2, String, M.HeapEntry>, +heap: +List<M.HeapEntry>, right: U32) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{left}: type_entries_equal_result(left, type_entry_at(heap, right))
def type_equals_entries(+heap: +List<M.HeapEntry>, left: U32, right: U32) -> Bool:
  type_entries_equal_left(type_entry_at(heap, left), heap, right)

def type_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +left : U32 <- receiver(args)
    +right_slot : M.Slot <- arg(args, 1)
    +right : U32 = bits(right_slot)
    answer : Bool = Bool.and(U32.is_ne(right, 0), type_equals_entries(S.heap(vm), left, right))
    result : O.Outcome <- L.bool_out(vm, answer)
    return result

def class_package(+vm: M.VM, class_id: U32) -> String:
  L.proxy_class_package(vm, class_id)

# Java 8 Lookup member access by the member's own access flag and lookup modes
# (PUBLIC 1, PRIVATE 2, PROTECTED 4, PACKAGE 8).
def member_access(+vm: M.VM, +owner: U32, +flags: U32, +lookup_class: U32, +modes: U32) -> Bool:
  +same = U32.is_eq(owner, lookup_class)
  +same_package = String.eq(class_package(vm, owner), class_package(vm, lookup_class))
  +is_public = U32.is_ne(U32.and(flags, 1), 0)
  +is_private = U32.is_ne(U32.and(flags, 2), 0)
  +is_protected = U32.is_ne(U32.and(flags, 4), 0)
  +public = is_public && U32.is_ne(U32.and(modes, 1), 0)
  +private = is_private && same && U32.is_ne(U32.and(modes, 2), 0)
  +package = Bool.not(is_public) && Bool.not(is_private) && same_package && U32.is_ne(U32.and(modes, 8), 0)
  +protected = is_protected && U32.is_ne(U32.and(modes, 4), 0) && H.assignable(S.classes(vm), S.symbols(vm), lookup_class, owner)
  Bool.or(public, Bool.or(private, Bool.or(package, protected)))

# --- Lookup access checks (Java 8 MethodHandles.Lookup and VerifyAccess) ---
# Mode bits: PUBLIC 1, PRIVATE 2, PROTECTED 4, PACKAGE 8.

def mode_has(+modes: U32, +bit: U32) -> Bool:
  U32.is_ne(U32.and(modes, bit), 0)

def is_subclass(+vm: M.VM, +sub: U32, +base: U32) -> Bool:
  H.hierarchy(S.classes(vm), sub, base)

# VerifyAccess.isClassAccessible.
def lookup_class_accessible(+vm: M.VM, +refc: U32, +lookup_class: U32, +modes: U32) -> Bool:
  U32.is_ne(modes, 0) && (L.class_public(vm, refc) || (mode_has(modes, 8) && L.same_package(vm, lookup_class, refc)))

def lookup_protected_accessible(+vm: M.VM, +refc: U32, +defc: U32, +mods: U32, +lookup_class: U32, +modes: U32) -> Bool:
  +related : Bool = U32.is_eq(refc, lookup_class) || is_subclass(vm, refc, lookup_class) || is_subclass(vm, lookup_class, refc)
  ((mode_has(modes, 4) || mode_has(modes, 8)) && L.same_package(vm, defc, lookup_class)) ||
    (mode_has(modes, 4) && (Bool.not(mode_has(mods, 8)) || related) && is_subclass(vm, lookup_class, defc))

# VerifyAccess.isMemberAccessible (Java 8: no nestmate access for privates).
def lookup_member_accessible(+vm: M.VM, +refc: U32, +defc: U32, +mods: U32, +lookup_class: U32, +modes: U32) -> Bool:
  +access : U32 = U32.and(mods, 7)
  lookup_class_accessible(vm, refc, lookup_class, modes) &&
    ((U32.is_eq(defc, lookup_class) && mode_has(modes, 2)) ||
      Bool.pick(Bool, U32.is_eq(access, 1), True{},
        Bool.pick(Bool, U32.is_eq(access, 4), lookup_protected_accessible(vm, refc, defc, mods, lookup_class, modes),
          Bool.pick(Bool, U32.is_eq(access, 0), mode_has(modes, 8) && L.same_package(vm, defc, lookup_class), False{}))))

# Lookup.checkAccess: a protected constructor cannot be "new"ed from another package.
def lookup_access_allowed(+vm: M.VM, +kind: U32, +refc: U32, +defc: U32, +flags: U32, +lookup_class: U32, +modes: U32) -> Bool:
  +mods : U32 = Bool.pick(U32, U32.is_eq(kind, 8) && mode_has(flags, 4), U32.xor(flags, 4), flags)
  +requested : U32 = Bool.pick(U32, U32.is_eq(U32.and(mods, 7), 0), 8, U32.and(mods, 7))
  # The common case: a public member of a public class with any access.
  (mode_has(mods, 1) && L.class_public(vm, refc) && U32.is_ne(modes, 0)) ||
    Bool.pick(Bool, U32.is_ne(U32.and(requested, modes), 0), lookup_member_accessible(vm, refc, defc, mods, lookup_class, modes),
      mode_has(requested, 4) && mode_has(modes, 8) && L.same_package(vm, defc, lookup_class))

def full_class_accessible(+vm: M.VM, +target: U32, +lookup_class: U32) -> Bool:
  L.class_public(vm, target) || L.same_package(vm, lookup_class, target)

# Lookup.accessFailedMessage.
def access_failed_message(+vm: M.VM, +refc: U32, +defc: U32, +flags: U32, +lookup_class: U32, +modes: U32) -> String:
  +class_ok : Bool = (L.class_public(vm, defc) && (U32.is_eq(defc, refc) || L.class_public(vm, refc))) ||
    (mode_has(modes, 8) && full_class_accessible(vm, defc, lookup_class) && (U32.is_eq(defc, refc) || full_class_accessible(vm, refc, lookup_class)))
  Bool.pick(String, Bool.not(class_ok), "class is not public",
    Bool.pick(String, mode_has(flags, 1), "access to public member failed",
      Bool.pick(String, mode_has(flags, 2), "member is private",
        Bool.pick(String, mode_has(flags, 4), "member is protected", "member is private to package"))))

def ref_kind_name(kind: U32) -> String:
  match kind:
    case 1: "getField"
    case 2: "getStatic"
    case 3: "putField"
    case 4: "putStatic"
    case 5: "invokeVirtual"
    case 6: "invokeStatic"
    case 7: "invokeSpecial"
    case 8: "newInvokeSpecial"
    case 9: "invokeInterface"
    case _: ""

@unsafe def type_simple_text(+vm: M.VM, +descriptor: String) -> String:
  match descriptor:
    case SCon{Chr{91}, rest}: type_simple_text(vm, rest) ++ "[]"
    case SCon{Chr{76}, rest}: L.simple_name(64n, vm, L.take_until_semicolon_text(rest))
    case other: L.primitive_descriptor_name(other)

@unsafe def joined_simple_texts(+vm: M.VM, +tokens: +List<String>, +first: Bool) -> String:
  match tokens:
    case Nil{}: ""
    case Con{+token, rest}: Bool.pick(String, first, "", ",") ++ type_simple_text(vm, token) ++ joined_simple_texts(vm, rest, False{})

# MethodType.toString: simple names, comma separated, no spaces.
@unsafe def method_type_text(+vm: M.VM, +desc: String) -> String:
  +chars : +List<Char> = String.to_list(desc)
  "(" ++ joined_simple_texts(vm, descriptor_tokens(chars_after(chars, 40, False{}), Nil{}), True{}) ++ ")" ++ type_simple_text(vm, String.from_list(chars_after(chars, 41, False{})))

@unsafe def methodtype_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    desc : String <- type_desc(vm, ref)
    result : O.Outcome <- L.intern_or_alloc(vm, L.units_from_string(method_type_text(vm, desc)))
    return result

# MemberName.toString for methods and fields.
@unsafe def method_member_text(+vm: M.VM, +owner: U32, +name: String, +desc: String, +kind: U32) -> String:
  L.class_display_name(L.class_name_text(vm, owner)) ++ "." ++ name ++ method_type_text(vm, desc) ++ "/" ++ ref_kind_name(kind)

@unsafe def field_member_text(+vm: M.VM, +owner: U32, +name: String, +desc: String, +kind: U32) -> String:
  L.class_display_name(L.class_name_text(vm, owner)) ++ "." ++ name ++ "/" ++ L.field_type_get_name(desc) ++ "/" ++ ref_kind_name(kind)

@unsafe def lookup_fail(ok: Bool, +message: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{message}

# checkSymbolicClass.
@unsafe def symbolic_class_check(ok: Bool, +vm: M.VM, +refc: U32) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{"java/lang/IllegalAccessException: symbolic reference class is not accessible: " ++ L.class_to_string_text(vm, refc)}

@unsafe def method_access_check(ok: Bool, +vm: M.VM, +refc: U32, +defc: U32, +flags: U32, +lookup_class: U32, +modes: U32, +name: String, +desc: String, +kind: U32) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{"java/lang/IllegalAccessException: " ++ access_failed_message(vm, refc, defc, flags, lookup_class, modes) ++ ": " ++ method_member_text(vm, defc, name, desc, kind)}

@unsafe def field_access_check(ok: Bool, +vm: M.VM, +refc: U32, +defc: U32, +flags: U32, +lookup_class: U32, +modes: U32, +name: String, +desc: String, +kind: U32) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{"java/lang/IllegalAccessException: " ++ access_failed_message(vm, refc, defc, flags, lookup_class, modes) ++ ": " ++ field_member_text(vm, defc, name, desc, kind)}

@unsafe def resolution_check(ok: Bool, +vm: M.VM, +label: String, +refc: U32, +name: String, +desc: String, +kind: U32) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{"java/lang/IllegalAccessException: " ++ label ++ ": " ++ method_member_text(vm, refc, name, desc, kind)}

@unsafe def resolved_method(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +label: String, +refc: U32, +name: String, +desc: String, +kind: U32) -> Result<&2, &2, String, M.LoadedMethod>:
  match found:
    case Some{method}: Done{method}
    case None{}: Fail{"java/lang/NoSuchMethodException: " ++ label ++ ": " ++ method_member_text(vm, refc, name, desc, kind)}

# restrictProtectedReceiver: a protected instance member reached from a
# subclass in another package only accepts receivers of the lookup class.
def restrict_receiver(+vm: M.VM, +flags: U32, +defc: U32, +lookup_class: U32) -> Bool:
  mode_has(flags, 4) && Bool.not(mode_has(flags, 8)) && U32.is_ne(defc, lookup_class) && Bool.not(L.same_package(vm, defc, lookup_class))

def lookup_state(+vm: M.VM, +lookup_ref: U32) -> Result<&2, &2, String, LookupState>:
  do Result<&2, &2, String, LookupState>:
    +lookup : M.HeapEntry <- H.get(S.heap(vm), lookup_ref)
    lookup_class : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(lookup), 0), "java/lang/IllegalStateException")
    lookup_modes : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(lookup), 1), "java/lang/IllegalStateException")
    return LookupState{bits(lookup_class), bits(lookup_modes)}

type LookupState is Data:
  LookupState{lookup_class: U32, modes: U32}

def lookup_state_class(state: LookupState) -> U32:
  match state:
    case LookupState{c, m}: c

def lookup_state_modes(state: LookupState) -> U32:
  match state:
    case LookupState{c, m}: m

def find_method(methods: +List<M.LoadedMethod>, +owner: U32, +name: U32, +desc: U32) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+m, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(m), owner) && U32.is_eq(M.loaded_method_name(m), name) && U32.is_eq(M.loaded_method_descriptor(m), desc), Some{m}, find_method(rest, owner, name, desc))
@unsafe def direct_handle(+vm: M.VM, +args: +List<M.Slot>, +kind: U32, +static: Bool, constructor: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    lookup_ref : U32 <- receiver(args)
    owner_slot : M.Slot <- arg(args, 1)
    name_slot : M.Slot <- arg(args, 2)
    type_slot : M.Slot <- arg(args, 3)
    +owner_entry : M.HeapEntry <- H.get(S.heap(vm), bits(owner_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(owner_entry), 8), "java/lang/IllegalArgumentException")
    +owner : U32 = L.entry_element(owner_entry)
    +name : String <- text(vm, bits(name_slot))
    +desc : String <- type_desc(vm, bits(type_slot))
    +state : LookupState <- lookup_state(vm, lookup_ref)
    +lookup_class : U32 = lookup_state_class(state)
    +modes : U32 = lookup_state_modes(state)
    owner_flags : U32 = L.class_flags_from_metadata(S.metadata(vm), owner)
    is_interface : Bool = U32.is_ne(U32.and(owner_flags, 512), 0)
    +reference_kind : U32 = Bool.pick(U32, U32.is_eq(kind, 5) && is_interface, 9, kind)
    symbolic : Unit <- symbolic_class_check(lookup_class_accessible(vm, owner, lookup_class, modes), vm, owner)
    +symbol_name : U32 = Sy.find(S.symbols(vm), name)
    +symbol_desc : U32 = Sy.find(S.symbols(vm), desc)
    +method : M.LoadedMethod <- resolved_method(L.method_hierarchy(256n, S.classes(vm), S.methods(vm), owner, symbol_name, symbol_desc), vm, "no such method", owner, name, desc, reference_kind)
    +flags : U32 = M.loaded_method_flags(method)
    +defc : U32 = M.loaded_method_owner(method)
    # The VM resolves with the lookup class (JVMS 5.4.4) and rejects a static mismatch.
    linked : Unit <- resolution_check(Bool.pick(Bool, U32.is_ne(U32.and(flags, 8), 0), static, Bool.not(static)) && L.member_accessible(vm, lookup_class, defc, flags), vm, "no such method", owner, name, desc, reference_kind)
    allowed : Unit <- method_access_check(lookup_access_allowed(vm, reference_kind, owner, defc, flags, lookup_class, modes), vm, owner, defc, flags, lookup_class, modes, name, desc, reference_kind)
    handle_class : U32 = class_id(vm, "java/lang/invoke/MethodHandle")
    restricted : Bool = U32.is_eq(reference_kind, 5) && restrict_receiver(vm, flags, defc, lookup_class)
    +entry : M.HeapEntry = handle_entry(handle_class, reference_kind, defc, symbol_name, symbol_desc, Bool.pick(U32, restricted, lookup_class, 4294967295))
    is_varargs : Bool = U32.is_ne(U32.and(flags, 128), 0)
    fields : +List<M.Binding> = H.binding_set(L.entry_fields(entry), 4294967295, M.Slot{1, Bool.pick(U32, is_varargs, 1, 0)})
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), L.entry_kind(entry), L.entry_element(entry), fields, L.entry_values(entry), L.entry_chars(entry)}
    result : O.Outcome <- alloc_ref(H.allocate(vm, updated))
    return result

def lookup_owner_binding(binding: Maybe<&2, M.Slot>) -> U32:
  match binding:
    case None{}: 0
    case Some{slot}: bits(slot)
def lookup_owner(fields: +List<M.Binding>) -> U32:
  lookup_owner_binding(H.binding_find(fields, 0))


def find_field(fields: +List<M.LoadedField>, +owner: U32, +name: U32) -> Maybe<&2, M.LoadedField>:
  match fields:
    case Nil{}: None{}
    case Con{+field, rest}:
      Bool.pick(Maybe<&2, M.LoadedField>, U32.is_eq(M.loaded_field_owner(field), owner) && U32.is_eq(M.loaded_field_name(field), name), Some{field}, find_field(rest, owner, name))

@unsafe def field_kind_check(ok: Bool, +vm: M.VM, +want_static: Bool, +defc: U32, +name: String, +desc: String, +kind: U32) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{"java/lang/IllegalAccessException: " ++ Bool.pick(String, want_static, "expected a static field", "expected a non-static field") ++ ": " ++ field_member_text(vm, defc, name, desc, kind)}

@unsafe def resolved_field(found: Maybe<&2, M.LoadedField>, +vm: M.VM, +refc: U32, +name: String, +desc: String, +kind: U32) -> Result<&2, &2, String, M.LoadedField>:
  match found:
    case Some{field}: Done{field}
    case None{}: Fail{"java/lang/NoSuchFieldException: no such field: " ++ field_member_text(vm, refc, name, desc, kind)}

@unsafe def lookup_field_handle(+vm: M.VM, +args: +List<M.Slot>, +reference_kind: U32, +is_static: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    lookup_ref : U32 <- receiver(args)
    owner_slot : M.Slot <- arg(args, 1)
    name_slot : M.Slot <- arg(args, 2)
    type_slot : M.Slot <- arg(args, 3)
    +owner_entry : M.HeapEntry <- H.get(S.heap(vm), bits(owner_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(owner_entry), 8), "java/lang/IllegalArgumentException")
    +owner : U32 = L.entry_element(owner_entry)
    +name : String <- text(vm, bits(name_slot))
    +expected_desc : String <- class_descriptor(vm, bits(type_slot))
    +state : LookupState <- lookup_state(vm, lookup_ref)
    +lookup_class : U32 = lookup_state_class(state)
    +modes : U32 = lookup_state_modes(state)
    symbolic : Unit <- symbolic_class_check(lookup_class_accessible(vm, owner, lookup_class, modes), vm, owner)
    +field : M.LoadedField <- resolved_field(H.resolve_field(S.classes(vm), S.fields(vm), owner, Sy.find(S.symbols(vm), name), Sy.find(S.symbols(vm), expected_desc)), vm, owner, name, expected_desc, reference_kind)
    +flags : U32 = M.loaded_field_flags(field)
    +defc : U32 = M.loaded_field_owner(field)
    +field_static : Bool = U32.is_ne(U32.and(flags, 8), 0)
    +setter : Bool = U32.is_eq(reference_kind, 3) || U32.is_eq(reference_kind, 4)
    +resolved_kind : U32 = Bool.pick(U32, setter, Bool.pick(U32, field_static, 4, 3), Bool.pick(U32, field_static, 2, 1))
    kind_ok : Unit <- field_kind_check(Bool.pick(Bool, field_static, is_static, Bool.not(is_static)), vm, is_static, defc, name, expected_desc, resolved_kind)
    final_ok : Unit <- lookup_fail(Bool.not(setter && mode_has(flags, 16)), "java/lang/IllegalAccessException: unexpected set of a final field: " ++ field_member_text(vm, defc, name, expected_desc, resolved_kind))
    allowed : Unit <- field_access_check(lookup_access_allowed(vm, reference_kind, owner, defc, flags, lookup_class, modes), vm, owner, defc, flags, lookup_class, modes, name, expected_desc, resolved_kind)
    restricted : Bool = Bool.not(is_static) && restrict_receiver(vm, flags, defc, lookup_class)
    handle : M.HeapEntry = handle_entry(class_id(vm, "java/lang/invoke/MethodHandle"), reference_kind, defc, M.loaded_field_name(field), M.loaded_field_descriptor(field), Bool.pick(U32, restricted, lookup_class, 4294967295))
    result : O.Outcome <- alloc_ref(H.allocate(vm, handle))
    return result

def find_special_result(result: O.Outcome, special_entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case O.Returned{+vm2, Some{M.Slot{3, +reference}}}:
      do Result<&2, &2, String, O.Outcome>:
        +handle : M.HeapEntry <- H.get(S.heap(vm2), reference)
        updated : M.HeapEntry = M.HeapEntry{H.entry_class(handle), H.kind_method_handle(), L.entry_element(handle), H.binding_set(L.entry_fields(handle), 3, M.Slot{1, L.entry_element(special_entry)}), Nil{}, Nil{}}
        outcome : O.Outcome <- L.ref_out(H.put(vm2, reference, updated), reference)
        return outcome
    case _: Fail{"java/lang/IllegalStateException"}

def find_special(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    result : O.Outcome <- direct_handle(vm, args, 7, False{}, False{})
    special_slot : M.Slot <- arg(args, 4)
    +special_entry : M.HeapEntry <- H.get(S.heap(vm), bits(special_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(special_entry), 8), "java/lang/IllegalArgumentException")
    outcome : O.Outcome <- find_special_result(result, special_entry)
    return outcome

@unsafe def find_constructor(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    lookup_ref : U32 <- receiver(args)
    owner_slot : M.Slot <- arg(args, 1)
    type_slot : M.Slot <- arg(args, 2)
    +owner_entry : M.HeapEntry <- H.get(S.heap(vm), bits(owner_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(owner_entry), 8), "java/lang/IllegalArgumentException")
    +owner : U32 = L.entry_element(owner_entry)
    +desc : String <- type_desc(vm, bits(type_slot))
    checked : Unit <- S.check(String.ends_with(desc, ")V"), "java/lang/invoke/WrongMethodTypeException")
    +state : LookupState <- lookup_state(vm, lookup_ref)
    +lookup_class : U32 = lookup_state_class(state)
    +modes : U32 = lookup_state_modes(state)
    symbolic : Unit <- symbolic_class_check(lookup_class_accessible(vm, owner, lookup_class, modes), vm, owner)
    +name_id : U32 = Sy.find(S.symbols(vm), "<init>")
    +desc_id : U32 = Sy.find(S.symbols(vm), desc)
    +method : M.LoadedMethod <- resolved_method(find_method(S.methods(vm), owner, name_id, desc_id), vm, "no such constructor", owner, "<init>", desc, 8)
    +flags : U32 = M.loaded_method_flags(method)
    linked : Unit <- resolution_check(L.member_accessible(vm, lookup_class, owner, flags), vm, "no such constructor", owner, "<init>", desc, 8)
    allowed : Unit <- method_access_check(lookup_access_allowed(vm, 8, owner, owner, flags, lookup_class, modes), vm, owner, owner, flags, lookup_class, modes, "<init>", desc, 7)
    +handle : M.HeapEntry = handle_entry(class_id(vm, "java/lang/invoke/MethodHandle"), 8, owner, name_id, desc_id, 4294967295)
    is_varargs : Bool = U32.is_ne(U32.and(flags, 128), 0)
    fields : +List<M.Binding> = H.binding_set(L.entry_fields(handle), 4294967295, M.Slot{1, Bool.pick(U32, is_varargs, 1, 0)})
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(handle), L.entry_kind(handle), L.entry_element(handle), fields, L.entry_values(handle), L.entry_chars(handle)}
    result : O.Outcome <- alloc_ref(H.allocate(vm, updated))
    return result


# Java 8 Lookup.in: PROTECTED is always dropped; another package also drops
# PACKAGE and PRIVATE; another top-level class drops PRIVATE; an inaccessible
# requested class leaves no access at all.
@unsafe def lookup_in_modes(+vm: M.VM, +old_class: U32, +requested: U32, +old_modes: U32) -> U32:
  +dropped : U32 = U32.and(old_modes, 11)
  +package_ok : U32 = Bool.pick(U32, mode_has(dropped, 8) && Bool.not(L.same_package(vm, old_class, requested)), U32.and(dropped, 1), dropped)
  +private_ok : U32 = Bool.pick(U32, mode_has(package_ok, 2) && Bool.not(String.eq(L.outermost_name(vm, old_class), L.outermost_name(vm, requested))), U32.and(package_ok, 13), package_ok)
  +accessible : Bool = lookup_class_accessible(vm, requested, old_class, old_modes)
  Bool.pick(U32, U32.is_eq(old_class, requested), old_modes, Bool.pick(U32, mode_has(private_ok, 1) && Bool.not(accessible), 0, private_ok))

@unsafe def lookup_in(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    lookup_ref : U32 <- receiver(args)
    class_slot : M.Slot <- arg(args, 1)
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits(class_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), 8), "java/lang/IllegalArgumentException")
    +lookup : M.HeapEntry <- H.get(S.heap(vm), lookup_ref)
    old_class : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(lookup), 0), "java/lang/IllegalStateException")
    +old_modes : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(lookup), 1), "java/lang/IllegalStateException")
    modes : U32 = lookup_in_modes(vm, bits(old_class), L.entry_element(entry), bits(old_modes))
    result : O.Outcome <- alloc_ref(H.allocate(vm, lookup_entry(class_id(vm, "java/lang/invoke/MethodHandles$Lookup"), L.entry_element(entry), modes)))
    return result

def owner_descriptor(vm: M.VM, owner: U32) -> String:
  +name = L.class_name_text(vm, owner)
  Bool.pick(String, String.starts_with(name, "["), name, "L" ++ name ++ ";")

def prepend_receiver(owner: String, desc: String) -> String:
  +chars = String.to_list(desc)
  "(" ++ owner ++ String.from_list(chars_before(chars_after(chars, 40, False{}), 41)) ++ ")" ++ String.from_list(chars_after(chars, 41, False{}))

def replace_return(owner: String, desc: String) -> String:
  "(" ++ String.from_list(chars_before(chars_after(String.to_list(desc), 40, False{}), 41)) ++ ")" ++ owner
def handle_descriptor_kind(kind: U32, owner: String, desc: String) -> String:
  match kind:
    case 1: "(" ++ owner ++ ")" ++ desc
    case 2: "()" ++ desc
    case 3: "(" ++ owner ++ desc ++ ")V"
    case 4: "(" ++ desc ++ ")V"
    case 5: prepend_receiver(owner, desc)
    case 6: desc
    case 7: prepend_receiver(owner, desc)
    case 8: replace_return(owner, desc)
    case 9: prepend_receiver(owner, desc)
    case _: desc

def handle_method_descriptor(+vm: M.VM, +entry: M.HeapEntry) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +kind : U32 = L.entry_element(entry)
    +owner_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 0), "java/lang/IllegalStateException")
    desc_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 2), "java/lang/IllegalStateException")
    mode_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 4), "java/lang/IllegalStateException")
    +special_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 3), "java/lang/IllegalStateException")
    # findSpecial handles take the specialCaller (binding 3) as their receiver type.
    # Binding 3 narrows the receiver: findSpecial's specialCaller, or the lookup
    # class of a restricted protected member (restrictProtectedReceiver).
    +receiver_class : U32 = Bool.pick(U32, U32.is_ne(bits(special_slot), 4294967295) && (U32.is_eq(kind, 7) || U32.is_eq(kind, 5) || U32.is_eq(kind, 1) || U32.is_eq(kind, 3)), bits(special_slot), bits(owner_slot))
    owner : String = owner_descriptor(vm, receiver_class)
    +desc : String = Sy.text(S.symbols(vm), bits(desc_slot))
    mode_is_set : Bool = U32.is_ne(bits(mode_slot), 0)
    return Bool.pick(String, mode_is_set, desc, handle_descriptor_kind(kind, owner, desc))

def mutable_callsite_values_valid(+vm: M.VM, values: +List<M.Slot>) -> Result<&2, &2, String, Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case Con{M.Slot{3, +reference}, rest}:
      do Result<&2, &2, String, Unit>:
        checked : Unit <- S.check(U32.is_ne(reference, 0), "java/lang/NullPointerException")
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_call_site()) && U32.is_eq(L.entry_element(entry), 1), "java/lang/IllegalArgumentException: not a CallSite")
        result : Unit <- mutable_callsite_values_valid(vm, rest)
        return result
    case _:
      Fail{"java/lang/IllegalArgumentException"}

# MutableCallSite.syncAll: every thread already observes each setTarget, since
# all threads share one sequentially consistent heap (plan 05's memory model);
# what remains is the JDK's argument validation.
def mutable_callsite_sync_all(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +sites_slot : M.Slot <- arg(args, 0)
    checked : Unit <- S.check(U32.is_ne(bits(sites_slot), 0), "java/lang/NullPointerException")
    +sites : M.HeapEntry <- H.get(S.heap(vm), bits(sites_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(sites), 2), "java/lang/IllegalArgumentException")
    valid : Unit <- mutable_callsite_values_valid(vm, L.entry_values(sites))
    result : O.Outcome <- L.void_out(vm)
    return result
def callsite_get(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_call_site()), "java/lang/IllegalArgumentException: not a CallSite")
    target : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 0), "java/lang/IllegalStateException")
    result : O.Outcome <- L.ref_out(vm, bits(target))
    return result

def handle_descriptor(+vm: M.VM, reference: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_method_handle()), "java/lang/IllegalArgumentException: not a MethodHandle")
    descriptor : String <- handle_method_descriptor(vm, entry)
    return descriptor
def callsite_descriptor_target(+vm: M.VM, entry: M.HeapEntry, +target: M.Slot) -> Result<&2, &2, String, String>:
  Bool.pick(Result<&2, &2, String, String>, U32.is_eq(bits(target), 0),
    do Result<&2, &2, String, String>:
      type_ref : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 1), "java/lang/IllegalStateException")
      +type_entry : M.HeapEntry <- H.get(S.heap(vm), bits(type_ref))
      checked : Unit <- S.check(U32.is_eq(L.entry_kind(type_entry), H.kind_method_type()), "java/lang/IllegalStateException")
      return Sy.text(S.symbols(vm), L.entry_element(type_entry)),
    handle_descriptor(vm, bits(target)))

def callsite_descriptor(vm: M.VM, +entry: M.HeapEntry) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    target : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 0), "java/lang/IllegalStateException")
    descriptor : String <- callsite_descriptor_target(vm, entry, target)
    return descriptor

def callsite_set(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ref : U32 <- receiver(args)
    +target : M.Slot <- arg(args, 1)
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_call_site()), "java/lang/IllegalArgumentException: not a CallSite")
    checked : Unit <- S.check(U32.is_ne(M.slot_bits(target), 0), "java/lang/NullPointerException")
    checked : Unit <- S.check(U32.is_ne(L.entry_element(entry), 0), "java/lang/UnsupportedOperationException")
    expected : String <- callsite_descriptor(vm, entry)
    actual : String <- handle_descriptor(vm, M.slot_bits(target))
    checked : Unit <- S.check(String.eq(expected, actual), "java/lang/invoke/WrongMethodTypeException")
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), H.kind_call_site(), L.entry_element(entry), H.binding_set(L.entry_fields(entry), 0, target), Nil{}, Nil{}}
    result : O.Outcome <- L.void_out(H.put(vm, ref, updated))
    return result

def callsite_dynamic_invoker(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ref : U32 <- receiver(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_call_site()), "java/lang/IllegalArgumentException: not a CallSite")
    descriptor : String <- callsite_descriptor(vm, entry)
    +interned : Sy.Interned = Sy.intern(S.symbols(vm), descriptor)
    +vm2 : M.VM = S.with_symbols(vm, Sy.interned_symbols(interned))
    +base : M.HeapEntry = handle_entry(class_id(vm2, "java/lang/invoke/MethodHandle"), 6, 0, 0, interned_id(interned), 4294967295)
    fields : +List<M.Binding> = H.binding_set(H.binding_set(L.entry_fields(base), 4, M.Slot{1, 5}), 5, M.Slot{3, ref})
    handle : M.HeapEntry = M.HeapEntry{H.entry_class(base), H.kind_method_handle(), L.entry_element(base), fields, Nil{}, Nil{}}
    result : O.Outcome <- alloc_ref(H.allocate(vm2, handle))
    return result

def callsite_type_target(+vm: M.VM, entry: M.HeapEntry, +target: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(bits(target), 0),
    do Result<&2, &2, String, O.Outcome>:
      type_ref : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 1), "java/lang/IllegalStateException")
      result : O.Outcome <- L.ref_out(vm, bits(type_ref))
      return result
    do Result<&2, &2, String, O.Outcome>:
      descriptor : String <- handle_descriptor(vm, bits(target))
      result : O.Outcome <- alloc_type(vm, descriptor)
      return result)

def callsite_type(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_call_site()), "java/lang/IllegalArgumentException: not a CallSite")
    target : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 0), "java/lang/IllegalStateException")
    result : O.Outcome <- callsite_type_target(vm, entry, target)
    return result

def callsite_init(+vm: M.VM, +args: +List<M.Slot>, kind: U32, +from_type: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver_ref : U32 <- receiver(args)
    +value : M.Slot <- arg(args, 1)
    +entry : M.HeapEntry <- H.get(S.heap(vm), receiver_ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), 0), "java/lang/IllegalArgumentException")
    target : M.Slot = Bool.pick(M.Slot, from_type, M.Slot{3, 0}, value)
    type_binding : +List<M.Binding> = Bool.pick(+List<M.Binding>, from_type, [M.Binding{1, value}], Nil{})
    fields : +List<M.Binding> = Con{M.Binding{0, target}, type_binding}
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), H.kind_call_site(), kind, fields, Nil{}, Nil{}}
    result : O.Outcome <- L.void_out(H.put(vm, receiver_ref, updated))
    return result

def string_hash(chars: +List<Char>, hash: U32) -> U32:
  match chars:
    case Nil{}: hash
    case Con{Chr{c}, rest}: string_hash(rest, U32.add(U32.mul(hash, 31), c))
def methodtype_hash(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    desc : String <- type_desc(vm, ref)
    result : O.Outcome <- L.int_out(vm, string_hash(String.to_list(desc), 0))
    return result


def method_descriptor_result_valid(result: Result<&2, &2, String, M.Descriptor>) -> Bool:
  match result:
    case Done{descriptor}: True{}
    case _: False{}

def method_descriptor_valid(desc: String) -> Bool:
  method_descriptor_result_valid(D.parse_method(desc))

def methodtype_from_descriptor(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    descriptor_ref : M.Slot <- arg(args, 0)
    +descriptor : String <- text(vm, bits(descriptor_ref))
    checked : Unit <- S.check(method_descriptor_valid(descriptor), "java/lang/IllegalArgumentException")
    result : O.Outcome <- alloc_type(vm, descriptor)
    return result

def skip_object(chars: +List<Char>) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{59}, rest}: rest
    case Con{c, rest}: skip_object(rest)

def drop_descriptor_type(chars: +List<Char>) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{91}, rest}: drop_descriptor_type(rest)
    case Con{Chr{76}, rest}: skip_object(rest)
    case Con{c, rest}: rest

def char_prefix(chars: +List<Char>, +count: U32) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{c, rest}:
      Bool.pick(+List<Char>, U32.is_eq(count, 0), Nil{}, Con{c, char_prefix(rest, U32.sub(count, 1))})

@unsafe def insert_parameter_descriptor(+chars: +List<Char>, +position: U32, +count: U32, +index: U32, +output: +List<Char>) -> +List<Char>:
  match chars:
    case Nil{}: output
    case Con{Chr{41}, rest}: M.append(Char, output, Con{Chr{41}, rest})
    case _:
      +rest = drop_descriptor_type(chars)
      size = U32.sub(M.length(Char, chars), M.length(Char, rest))
      token = char_prefix(chars, size)
      skipped = U32.is_ge(index, position) && U32.is_lt(index, U32.add(position, count))
      next_output = Bool.pick(+List<Char>, skipped, output, M.append(Char, output, token))
      insert_parameter_descriptor(rest, position, count, U32.add(index, 1), next_output)

@unsafe def insert_bound_fields(+fields: +List<M.Binding>, values: +List<M.Slot>, +index: U32) -> +List<M.Binding>:
  match values:
    case Nil{}: fields
    case Con{slot, rest}:
      insert_bound_fields(H.binding_set(fields, U32.add(index, 9), slot), rest, U32.add(index, 1))

def bind_descriptor(desc: String) -> String:
  +chars = String.to_list(desc)
  params = chars_after(chars, 40, False{})
  remaining = drop_descriptor_type(params)
  "(" ++ String.from_list(chars_before(remaining, 41)) ++ ")" ++ String.from_list(chars_after(chars, 41, False{}))

def is_reference_type(chars: +List<Char>) -> Bool:
  match chars:
    case Con{Chr{76}, rest}: True{}
    case Con{Chr{91}, rest}: True{}
    case _: False{}
def bind_to(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ref : U32 <- receiver(args)
    +bound : M.Slot <- arg(args, 1)
    checked : Unit <- S.check(U32.is_eq(M.slot_tag(bound), 3), "java/lang/IllegalArgumentException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_method_handle()), "java/lang/IllegalArgumentException: not a MethodHandle")
    # bindTo drops the first parameter of the handle's type (receiver included).
    +desc : String <- handle_method_descriptor(vm, entry)
    first : +List<Char> = chars_after(String.to_list(desc), 40, False{})
    checked : Unit <- S.check(is_reference_type(first), "java/lang/invoke/WrongMethodTypeException")
    +interned : Sy.Interned = Sy.intern(S.symbols(vm), bind_descriptor(desc))
    vm2 : M.VM = S.with_symbols(vm, Sy.interned_symbols(interned))
    fields0 : +List<M.Binding> = H.binding_set(L.entry_fields(entry), 2, M.Slot{1, interned_id(interned)})
    fields1 : +List<M.Binding> = H.binding_set(fields0, 4, M.Slot{1, 2})
    fields2 : +List<M.Binding> = H.binding_set(fields1, 5, M.Slot{3, ref})
    # Binding 6 holds the bound receiver slot itself (reference tag), as constant handles do.
    fields3 : +List<M.Binding> = H.binding_set(fields2, 6, bound)
    fields4 : +List<M.Binding> = H.binding_set(fields3, 7, M.Slot{1, M.slot_tag(bound)})
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), H.kind_method_handle(), L.entry_element(entry), fields4, Nil{}, Nil{}}
    result : O.Outcome <- alloc_ref(H.allocate(vm2, updated))
    return result



def handle_type(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_method_handle()), "java/lang/IllegalArgumentException: not a MethodHandle")
    desc : String <- handle_method_descriptor(vm, entry)
    result : O.Outcome <- alloc_type(vm, desc)
    return result
def handle_adapt(+vm: M.VM, +args: +List<M.Slot>, mode: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver_ref : U32 <- receiver(args)
    type_slot : M.Slot <- arg(args, 1)
    +target_type : M.HeapEntry <- H.get(S.heap(vm), bits(type_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(target_type), H.kind_method_type()), "java/lang/IllegalArgumentException: not a MethodType")
    +source : M.HeapEntry <- H.get(S.heap(vm), receiver_ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(source), H.kind_method_handle()), "java/lang/IllegalArgumentException: not a MethodHandle")
    source_descriptor : String <- handle_method_descriptor(vm, source)
    target_descriptor : String = Sy.text(S.symbols(vm), L.entry_element(target_type))
    checked : Unit <- S.check(U32.is_eq(count_descriptor_parameters(source_descriptor), count_descriptor_parameters(target_descriptor)), "java/lang/invoke/WrongMethodTypeException")
    fields0 : +List<M.Binding> = H.binding_set(L.entry_fields(source), 2, M.Slot{1, L.entry_element(target_type)})
    fields1 : +List<M.Binding> = H.binding_set(fields0, 4, M.Slot{1, mode})
    fields2 : +List<M.Binding> = H.binding_set(fields1, 5, M.Slot{3, receiver_ref})
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(source), H.kind_method_handle(), L.entry_element(source), fields2, Nil{}, Nil{}}
    result : O.Outcome <- alloc_ref(H.allocate(vm, updated))
    return result

def handle_as_type(vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  handle_adapt(vm, args, 1)

def invoke_type_descriptor(value: M.JvmType) -> String:
  match value:
    case M.Primitive{tag}: Char.show(Chr{tag})
    case M.ObjectType{name}: "L" ++ name ++ ";"
    case M.ArrayType{element}: "[" ++ invoke_type_descriptor(element)
def handle_fixed(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    +source : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(source), H.kind_method_handle()), "java/lang/IllegalArgumentException: not a MethodHandle")
    fields : +List<M.Binding> = H.binding_set(L.entry_fields(source), 4294967295, M.Slot{1, 0})
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(source), H.kind_method_handle(), L.entry_element(source), fields, L.entry_values(source), L.entry_chars(source)}
    result : O.Outcome <- alloc_ref(H.allocate(vm, updated))
    return result

def handle_varargs(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ref : U32 <- receiver(args)
    +array_class : M.Slot <- arg(args, 1)
    checked : Unit <- S.check(U32.is_ne(M.slot_bits(array_class), 0), "java/lang/IllegalArgumentException")
    +descriptor : String <- class_descriptor(vm, M.slot_bits(array_class))
    checked : Unit <- S.check(String.starts_with(descriptor, "["), "java/lang/IllegalArgumentException")
    source_descriptor : String <- handle_descriptor(vm, ref)
    parsed : M.Descriptor <- D.parse_method(source_descriptor)
    +parameters : +List<M.JvmType> = D.parameter_types(parsed)
    +parameter_count : U32 = M.length(M.JvmType, parameters)
    checked : Unit <- S.check(U32.is_gt(parameter_count, 0), "java/lang/IllegalArgumentException")
    last : M.JvmType <- S.require(M.JvmType, M.nth(M.JvmType, parameters, U32.sub(parameter_count, 1)), "java/lang/IllegalArgumentException")
    checked : Unit <- S.check(String.eq(descriptor, invoke_type_descriptor(last)), "java/lang/IllegalArgumentException")
    +source : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(source), H.kind_method_handle()), "java/lang/IllegalArgumentException: not a MethodHandle")
    fields0 : +List<M.Binding> = H.binding_set(L.entry_fields(source), 4294967295, M.Slot{1, 1})
    fields1 : +List<M.Binding> = H.binding_set(fields0, 8, array_class)
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(source), H.kind_method_handle(), L.entry_element(source), fields1, L.entry_values(source), L.entry_chars(source)}
    result : O.Outcome <- alloc_ref(H.allocate(vm, updated))
    return result


def handle_varargs_binding(binding: Maybe<&2, M.Slot>) -> Bool:
  match binding:
    case None{}: False{}
    case Some{slot}: U32.is_ne(M.slot_bits(slot), 0)

def handle_varargs_flag(fields: +List<M.Binding>) -> Bool:
  handle_varargs_binding(H.binding_find(fields, 4294967295))

def handle_is_varargs(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    +source : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(source), H.kind_method_handle()), "java/lang/IllegalArgumentException: not a MethodHandle")
    result : O.Outcome <- L.bool_out(vm, handle_varargs_flag(L.entry_fields(source)))
    return result

def current_method(methods: +List<M.LoadedMethod>, method_id: U32) -> Maybe<&2, M.LoadedMethod>:
  M.nth(M.LoadedMethod, methods, method_id)

def current_class_method(method: Maybe<&2, M.LoadedMethod>) -> U32:
  match method:
    case None{}: 0
    case Some{value}: M.loaded_method_owner(value)

def current_class_frames(frames: +List<M.Frame>, methods: +List<M.LoadedMethod>) -> U32:
  match frames:
    case Nil{}: 0
    case Con{frame, rest}:
      current_class_method(current_method(methods, S.method_id(frame)))

def current_class(+vm: M.VM) -> U32:
  current_class_frames(S.frames(vm), S.methods(vm))
def primitive_wrapper(vm: M.VM, +descriptor: String) -> U32:
  class_id(vm, Bool.pick(String, String.eq(descriptor, "Z"), "java/lang/Boolean",
    Bool.pick(String, String.eq(descriptor, "B"), "java/lang/Byte",
    Bool.pick(String, String.eq(descriptor, "C"), "java/lang/Character",
    Bool.pick(String, String.eq(descriptor, "S"), "java/lang/Short",
    Bool.pick(String, String.eq(descriptor, "I"), "java/lang/Integer",
    Bool.pick(String, String.eq(descriptor, "J"), "java/lang/Long",
    Bool.pick(String, String.eq(descriptor, "F"), "java/lang/Float", "java/lang/Double"))))))))

def constant_descriptor_code_chars(chars: +List<Char>) -> U32:
  match chars:
    case Con{Chr{code}, rest}: code
    case Nil{}: 0
def constant_descriptor_code(descriptor: String) -> U32:
  constant_descriptor_code_chars(String.to_list(descriptor))

def constant_object_result_valid(+vm: M.VM, owner: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Bool:
  match result:
    case Done{entry}: H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), owner)
    case _: False{}

def constant_object_valid(+vm: M.VM, owner: U32, value: M.Slot) -> Bool:
  constant_object_result_valid(vm, owner, H.get(S.heap(vm), M.slot_bits(value)))

def constant_reference_valid(vm: M.VM, owner: U32, +value: M.Slot) -> Bool:
  U32.is_eq(M.slot_tag(value), 3) &&
    Bool.pick(Bool, U32.is_eq(M.slot_bits(value), 0), True{}, constant_object_valid(vm, owner, value))

def constant_primitive_value(+vm: M.VM, +descriptor: String, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    checked : Unit <- S.check(Bool.not(String.eq(descriptor, "V")), "java/lang/IllegalArgumentException")
    checked : Unit <- S.check(U32.is_eq(M.slot_tag(value), 3), "java/lang/IllegalArgumentException")
    checked : Unit <- S.check(U32.is_ne(M.slot_bits(value), 0), "java/lang/NullPointerException")
    entry : M.HeapEntry <- H.get(S.heap(vm), M.slot_bits(value))
    wrapper_id : U32 = primitive_wrapper(vm, descriptor)
    checked : Unit <- S.check(U32.is_eq(H.entry_class(entry), wrapper_id), "java/lang/ClassCastException")
    converted : M.Slot <- L.reflect_convert_primitive(vm, constant_descriptor_code(descriptor), value)
    return converted

def constant_handle_value(+vm: M.VM, +descriptor: String, +owner: U32, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  Bool.pick(Result<&2, &2, String, M.Slot>, String.starts_with(descriptor, "L") || String.starts_with(descriptor, "["),
    do Result<&2, &2, String, M.Slot>:
      checked : Unit <- S.check(constant_reference_valid(vm, owner, value), "java/lang/ClassCastException")
      return value,
    constant_primitive_value(vm, descriptor, value))
@unsafe def descriptor_tokens(+chars: +List<Char>, +acc: +List<String>) -> +List<String>:
  match chars:
    case Nil{}: M.reverse(String, acc)
    case Con{Chr{41}, rest}: M.reverse(String, acc)
    case _:
      +rest = drop_descriptor_type(chars)
      size = U32.sub(M.length(Char, chars), M.length(Char, rest))
      token = String.from_list(char_prefix(chars, size))
      descriptor_tokens(rest, Con{token, acc})

def insertion_object_result(+vm: M.VM, expected: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, Bool>:
  match result:
    case Done{entry}: Done{H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), expected)}
    case Fail{error}: Fail{error}

def insertion_object_assignable(+vm: M.VM, reference: U32, expected: U32) -> Result<&2, &2, String, Bool>:
  insertion_object_result(vm, expected, H.get(S.heap(vm), reference))

def insertion_value_assignable(vm: M.VM, +reference: U32, expected: U32) -> Result<&2, &2, String, Bool>:
  Bool.pick(Result<&2, &2, String, Bool>, U32.is_eq(reference, 0),
    Done{True{}}, insertion_object_assignable(vm, reference, expected))

def insertion_reference_matches(+vm: M.VM, descriptor: String, value: M.Slot) -> Result<&2, &2, String, Bool>:
  do Result<&2, &2, String, Bool>:
    expected : U32 <- descriptor_class(vm, descriptor)
    matches : Bool <- insertion_value_assignable(vm, M.slot_bits(value), expected)
    return matches

def insertion_primitive_matches(+vm: M.VM, descriptor: String, +value: M.Slot) -> Result<&2, &2, String, Bool>:
  Bool.pick(Result<&2, &2, String, Bool>, U32.is_eq(M.slot_bits(value), 0),
    Done{False{}}, insertion_value_assignable(vm, M.slot_bits(value), primitive_wrapper(vm, descriptor)))

def insertion_value_matches(+vm: M.VM, +descriptor: String, +value: M.Slot) -> Result<&2, &2, String, Bool>:
  Bool.pick(Result<&2, &2, String, Bool>, String.starts_with(descriptor, "L") || String.starts_with(descriptor, "["),
    insertion_reference_matches(vm, descriptor, value), insertion_primitive_matches(vm, descriptor, value))
def insertion_value_convert(+vm: M.VM, +descriptor: String, +value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  Bool.pick(Result<&2, &2, String, M.Slot>, String.starts_with(descriptor, "L") || String.starts_with(descriptor, "["),
    Done{value}, L.reflect_convert_primitive(vm, constant_descriptor_code(descriptor), value))

def insertion_values_convert(+vm: M.VM, descriptors: +List<String>, values: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  match descriptors values:
    case Nil{} Nil{}: Done{Nil{}}
    case Con{descriptor, descriptor_rest} Con{value, value_rest}:
      do Result<&2, &2, String, +List<M.Slot>>:
        converted : M.Slot <- insertion_value_convert(vm, descriptor, value)
        rest : +List<M.Slot> <- insertion_values_convert(vm, descriptor_rest, value_rest)
        return Con{converted, rest}
    case _ _: Fail{"java/lang/IllegalArgumentException"}
def insertion_values_valid(+vm: M.VM, descriptors: +List<String>, values: +List<M.Slot>) -> Result<&2, &2, String, Bool>:
  match descriptors values:
    case Nil{} Nil{}: Done{True{}}
    case Con{descriptor, descriptor_rest} Con{value, value_rest}:
      do Result<&2, &2, String, Bool>:
        valid_current : Bool <- insertion_value_matches(vm, descriptor, value)
        valid_rest : Bool <- insertion_values_valid(vm, descriptor_rest, value_rest)
        return valid_current && valid_rest
    case _ _: Done{False{}}

def handle_insert_type_at(parameters: +List<M.JvmType>, index: U32) -> Maybe<&2, M.JvmType>:
  M.nth(M.JvmType, parameters, index)

def handle_insert_array_binding(fields: +List<M.Binding>) -> Maybe<&2, M.Slot>:
  H.binding_find(fields, 8)

def handle_insert_last_descriptor(vm: M.VM, result: Result<&2, &2, String, String>, last: M.JvmType) -> Bool:
  match result:
    case Done{descriptor}: String.eq(descriptor, invoke_type_descriptor(last))
    case _: False{}

def handle_insert_last_array(+vm: M.VM, binding: Maybe<&2, M.Slot>, last: M.JvmType) -> Bool:
  match binding:
    case None{}: False{}
    case Some{array_class}: handle_insert_last_descriptor(vm, class_descriptor(vm, M.slot_bits(array_class)), last)

def handle_insert_last_binding(vm: M.VM, fields: +List<M.Binding>, last_type: Maybe<&2, M.JvmType>) -> Bool:
  match last_type:
    case None{}: False{}
    case Some{last}: handle_insert_last_array(vm, handle_insert_array_binding(fields), last)

def handle_insert_last_type(vm: M.VM, fields: +List<M.Binding>, parameters: +List<M.JvmType>, count: U32) -> Bool:
  handle_insert_last_binding(vm, fields, handle_insert_type_at(parameters, U32.sub(count, 1)))

def handle_insert_parameters(vm: M.VM, fields: +List<M.Binding>, +parameters: +List<M.JvmType>) -> Bool:
  +count : U32 = M.length(M.JvmType, parameters)
  Bool.pick(Bool, U32.is_gt(count, 0), handle_insert_last_type(vm, fields, parameters, count), False{})

def handle_insert_varargs_parsed(vm: M.VM, fields: +List<M.Binding>, parsed: Result<&2, &2, String, M.Descriptor>) -> Bool:
  match parsed:
    case Fail{_}: False{}
    case Done{signature}: handle_insert_parameters(vm, fields, D.parameter_types(signature))

def handle_insert_varargs_flag(varargs: Bool, vm: M.VM, fields: +List<M.Binding>, descriptor: String) -> Bool:
  match varargs:
    case False{}: False{}
    case True{}: handle_insert_varargs_parsed(vm, fields, D.parse_method(descriptor))

def handle_insert_varargs(vm: M.VM, +fields: +List<M.Binding>, descriptor: String) -> Bool:
  handle_insert_varargs_flag(handle_varargs_flag(fields), vm, fields, descriptor)

def methodhandles_insert_arguments(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : M.Slot <- arg(args, 0)
    +position : M.Slot <- arg(args, 1)
    values_slot : M.Slot <- arg(args, 2)
    +target_entry : M.HeapEntry <- H.get(S.heap(vm), bits(target))
    checked : Unit <- S.check(U32.is_ne(bits(target), 0) && U32.is_eq(L.entry_kind(target_entry), H.kind_method_handle()), "java/lang/IllegalArgumentException")
    +values_entry : M.HeapEntry <- H.get(S.heap(vm), bits(values_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(values_entry), 2), "java/lang/IllegalArgumentException")
    +values : +List<M.Slot> = L.entry_values(values_entry)
    +descriptor : String <- handle_method_descriptor(vm, target_entry)
    +params : +List<Char> = descriptor_params(descriptor)
    +value_count : U32 = M.length(M.Slot, values)
    +param_count : U32 = count_descriptor_parameters(descriptor)
    checked : Unit <- S.check(U32.is_le(bits(position), param_count) && U32.is_le(value_count, U32.sub(param_count, bits(position))), "java/lang/IndexOutOfBoundsException")
    tokens : +List<String> = descriptor_tokens(params, Nil{})
    selected : +List<String> = M.drop(String, tokens, U32.to_nat(bits(position)))
    +values_descriptors : +List<String> = M.take(String, selected, U32.to_nat(value_count))
    valid : Bool <- insertion_values_valid(vm, values_descriptors, values)
    checked : Unit <- S.check(valid, "java/lang/IllegalArgumentException")
    converted_values : +List<M.Slot> <- insertion_values_convert(vm, values_descriptors, values)
    param_text : String = String.from_list(insert_parameter_descriptor(params, bits(position), value_count, 0, Nil{}))
    +new_descriptor : String = "(" ++ param_text ++ ")" ++ String.from_list(chars_after(String.to_list(descriptor), 41, False{}))
    +interned : Sy.Interned = Sy.intern(S.symbols(vm), new_descriptor)
    +vm2 : M.VM = S.with_symbols(vm, Sy.interned_symbols(interned))
    owner_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(target_entry), 0), "java/lang/IllegalStateException")
    name_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(target_entry), 1), "java/lang/IllegalStateException")
    special_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(target_entry), 3), "java/lang/IllegalStateException")
    +base : M.HeapEntry = handle_entry(class_id(vm2, "java/lang/invoke/MethodHandle"), L.entry_element(target_entry),
      M.slot_bits(owner_slot), M.slot_bits(name_slot), interned_id(interned), M.slot_bits(special_slot))
    fields0 : +List<M.Binding> = H.binding_set(L.entry_fields(base), 4, M.Slot{1, 6})
    fields1 : +List<M.Binding> = H.binding_set(fields0, 5, target)
    fields2 : +List<M.Binding> = H.binding_set(fields1, 6, position)
    fields3 : +List<M.Binding> = H.binding_set(fields2, 7, M.Slot{1, value_count})
    fields : +List<M.Binding> = insert_bound_fields(fields3, converted_values, 0)
    collector : Bool = handle_insert_varargs(vm, L.entry_fields(target_entry), new_descriptor)
    collector_fields : +List<M.Binding> = H.binding_set(fields, 4294967295, M.Slot{1, Bool.pick(U32, collector, 1, 0)})
    handle : M.HeapEntry = M.HeapEntry{H.entry_class(base), H.kind_method_handle(), L.entry_element(base), collector_fields, Nil{}, Nil{}}
    result : O.Outcome <- alloc_ref(H.allocate(vm2, handle))
    return result

def methodhandles_constant(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +type_slot : M.Slot <- arg(args, 0)
    value : M.Slot <- arg(args, 1)
    +class_entry : M.HeapEntry <- H.get(S.heap(vm), bits(type_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(class_entry), 8), "java/lang/IllegalArgumentException")
    +owner : U32 = L.entry_element(class_entry)
    +descriptor : String <- class_descriptor(vm, bits(type_slot))
    +stored_value : M.Slot <- constant_handle_value(vm, descriptor, owner, value)
    +interned : Sy.Interned = Sy.intern(S.symbols(vm), "()" ++ descriptor)
    +vm2 : M.VM = S.with_symbols(vm, Sy.interned_symbols(interned))
    +base : M.HeapEntry = handle_entry(class_id(vm2, "java/lang/invoke/MethodHandle"), 6, 0, 0, interned_id(interned), 4294967295)
    fields0 : +List<M.Binding> = H.binding_set(L.entry_fields(base), 4, M.Slot{1, 7})
    fields1 : +List<M.Binding> = H.binding_set(fields0, 6, stored_value)
    fields2 : +List<M.Binding> = H.binding_set(fields1, 7, M.Slot{1, M.slot_tag(stored_value)})
    handle : M.HeapEntry = M.HeapEntry{H.entry_class(base), H.kind_method_handle(), L.entry_element(base), fields2, Nil{}, Nil{}}
    result : O.Outcome <- alloc_ref(H.allocate(vm2, handle))
    return result

def methodhandles_identity(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +type_slot : M.Slot <- arg(args, 0)
    +class_entry : M.HeapEntry <- H.get(S.heap(vm), bits(type_slot))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(class_entry), 8), "java/lang/IllegalArgumentException")
    +descriptor : String <- class_descriptor(vm, bits(type_slot))
    checked : Unit <- S.check(Bool.not(String.eq(descriptor, "V")), "java/lang/IllegalArgumentException")
    +interned : Sy.Interned = Sy.intern(S.symbols(vm), "(" ++ descriptor ++ ")" ++ descriptor)
    +vm2 : M.VM = S.with_symbols(vm, Sy.interned_symbols(interned))
    +base : M.HeapEntry = handle_entry(class_id(vm2, "java/lang/invoke/MethodHandle"), 6, 0, 0, interned_id(interned), 4294967295)
    fields : +List<M.Binding> = H.binding_set(L.entry_fields(base), 4, M.Slot{1, 8})
    handle : M.HeapEntry = M.HeapEntry{H.entry_class(base), H.kind_method_handle(), L.entry_element(base), fields, Nil{}, Nil{}}
    result : O.Outcome <- alloc_ref(H.allocate(vm2, handle))
    return result
def lookup_factory(+vm: M.VM, +public: Bool) -> Result<&2, &2, String, O.Outcome>:
  class = class_id(vm, "java/lang/invoke/MethodHandles$Lookup")
  owner = Bool.pick(U32, public, 0, current_class(vm))
  alloc_ref(H.allocate(vm, lookup_entry(class, owner, Bool.pick(U32, public, 1, 15))))

def lookup_class(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_lookup()), "java/lang/IllegalArgumentException: not a Lookup")
    owner : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 0), "java/lang/IllegalStateException")
    result : O.Outcome <- class_mirror(vm, bits(owner))
    return result

def lookup_modes(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    ref : U32 <- receiver(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_lookup()), "java/lang/IllegalArgumentException: not a Lookup")
    modes : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 1), "java/lang/IllegalStateException")
    result : O.Outcome <- L.int_out(vm, bits(modes))
    return result

def lambda_plan_entry(class: U32, sam_name: U32, sam_desc: U32, instantiated_desc: U32, impl: U32, captures: U32, markers: U32, bridges: U32, iface: U32, factory_desc: U32, capturing_class: U32, flags: U32) -> M.HeapEntry:
  M.HeapEntry{class, H.kind_lambda_plan(), 0,
    [M.Binding{0, M.Slot{1, sam_name}}, M.Binding{1, M.Slot{1, sam_desc}},
     M.Binding{2, M.Slot{1, instantiated_desc}}, M.Binding{3, M.Slot{3, impl}},
     M.Binding{4, M.Slot{1, captures}}, M.Binding{5, M.Slot{3, markers}},
     M.Binding{6, M.Slot{3, bridges}}, M.Binding{7, M.Slot{1, iface}},
     M.Binding{8, M.Slot{1, factory_desc}}, M.Binding{9, M.Slot{1, 0}},
     M.Binding{10, M.Slot{1, capturing_class}}, M.Binding{11, M.Slot{1, flags}}], Nil{}, Nil{}}

def lambda_interface_descriptor(desc: String) -> String:
  String.from_list(chars_after(String.to_list(desc), 41, False{}))

def lambda_interface_id(vm: M.VM, call_desc: String) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +result_desc : String = lambda_interface_descriptor(call_desc)
    checked : Unit <- S.check(String.starts_with(result_desc, "L"), "java/lang/invoke/LambdaConversionException")
    interface_id : U32 <- descriptor_class(vm, result_desc)
    return interface_id

def lambda_lookup_valid(vm: M.VM, lookup_ref: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), lookup_ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_lookup()), "java/lang/invoke/LambdaConversionException")
    modes : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 1), "java/lang/IllegalStateException")
    checked : Unit <- S.check(U32.is_eq(bits(modes), 15), "java/lang/invoke/LambdaConversionException")
    return Unit{}

def lambda_count_agrees(+vm: M.VM, factory_desc: String, sam_desc: String, impl_ref: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    +impl : M.HeapEntry <- H.get(S.heap(vm), impl_ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(impl), H.kind_method_handle()), "java/lang/invoke/LambdaConversionException")
    +kind : U32 = L.entry_element(impl)
    checked : Unit <- S.check(U32.is_ge(kind, 5) && U32.is_le(kind, 9), "java/lang/invoke/LambdaConversionException")
    impl_desc : String <- handle_method_descriptor(vm, impl)
    factory_count : U32 = count_descriptor_parameters(factory_desc)
    sam_count : U32 = count_descriptor_parameters(sam_desc)
    impl_count : U32 = count_descriptor_parameters(impl_desc)
    checked : Unit <- S.check(U32.is_eq(impl_count, U32.add(factory_count, sam_count)), "java/lang/invoke/LambdaConversionException")
    return Unit{}

def lambda_array_slots(vm: M.VM, ref: U32) -> Result<&2, &2, String, +List<M.Slot>>:
  do Result<&2, &2, String, +List<M.Slot>>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), 2), "java/lang/invoke/LambdaConversionException")
    return L.entry_values(entry)

def lambda_lookup_class_id(vm: M.VM, lookup_ref: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    entry : M.HeapEntry <- H.get(S.heap(vm), lookup_ref)
    owner : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 0), "java/lang/IllegalStateException")
    return bits(owner)

def lambda_string_seen(+values: +List<String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{head, rest}: String.eq(head, value) || lambda_string_seen(rest, value)

def lambda_add_abstract_signatures(methods: +List<M.LoadedMethod>, +owner: U32, +symbols: +List<String>, +seen: +List<String>) -> +List<String>:
  match methods:
    case Nil{}: seen
    case Con{+method, rest}:
      +flags = M.loaded_method_flags(method)
      descriptor = Sy.text(symbols, M.loaded_method_descriptor(method))
      +signature = Sy.text(symbols, M.loaded_method_name(method)) ++ descriptor
      eligible = U32.is_eq(M.loaded_method_owner(method), owner) && U32.is_ne(U32.and(flags, 1024), 0) && U32.is_eq(U32.and(flags, 10), 0) && U32.is_ne(U32.and(flags, 1), 0)
      next = Bool.pick(+List<String>, eligible && Bool.not(lambda_string_seen(seen, signature)), Con{signature, seen}, seen)
      lambda_add_abstract_signatures(rest, owner, symbols, next)


def lambda_conversion_code_chars(characters: +List<Char>) -> U32:
  match characters:
    case Con{Chr{code}, rest}: code
    case _: 0

def lambda_conversion_code(descriptor: String) -> U32:
  lambda_conversion_code_chars(String.to_list(descriptor))

def lambda_conversion_types(+vm: M.VM, source_reference: Bool, target_reference: Bool, +source: String, +target: String) -> Bool:
  match source_reference target_reference:
    case True{} True{}: True{}
    case True{} False{}: True{}
    case False{} True{}:
      wrapper = primitive_wrapper(vm, source)
      wrapper_descriptor = owner_descriptor(vm, wrapper)
      H.descriptor_assignable(wrapper_descriptor, target, S.classes(vm), S.symbols(vm))
    case False{} False{}: L.reflect_widen_allowed(lambda_conversion_code(source), lambda_conversion_code(target))

def lambda_nonvoid_types(vm: M.VM, +source: String, +target: String) -> Bool:
  source_reference = String.starts_with(source, "L") || String.starts_with(source, "[")
  target_reference = String.starts_with(target, "L") || String.starts_with(target, "[")
  lambda_conversion_types(vm, source_reference, target_reference, source, target)

def lambda_nonvoid_conversion(vm: M.VM, +source: String, +target: String) -> Bool:
  source_void = String.eq(source, "V")
  +target_void = String.eq(target, "V")
  Bool.pick(Bool, source_void,
    Bool.pick(Bool, target_void, True{}, False{}),
    Bool.pick(Bool, target_void, True{}, lambda_nonvoid_types(vm, source, target)))

def lambda_conversion_possible(vm: M.VM, source: String, target: String) -> Bool:
  lambda_nonvoid_conversion(vm, source, target)

def lambda_conversion_pairs(+vm: M.VM, sources: +List<String>, targets: +List<String>) -> Bool:
  match sources targets:
    case Nil{} Nil{}: True{}
    case Con{source, source_rest} Con{target, target_rest}:
      lambda_conversion_possible(vm, source, target) && lambda_conversion_pairs(vm, source_rest, target_rest)
    case _ _: False{}


def lambda_metafactory_callsite(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}:
      alloc_ref(H.allocate(vm, callsite_entry(class_id(vm, "java/lang/invoke/ConstantCallSite"), 0, M.Slot{3, reference})))

def lambda_metafactory_plan(result: Result<&2, &2, String, H.Allocation>, factory_desc: String) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}:
      +interned = Sy.intern(S.symbols(vm), factory_desc)
      +vm2 = S.with_symbols(vm, Sy.interned_symbols(interned))
      +base = handle_entry(class_id(vm2, "java/lang/invoke/MethodHandle"), 6, 0, 0, interned_id(interned), 4294967295)
      fields0 = H.binding_set(L.entry_fields(base), 4, M.Slot{1, 9})
      fields1 = H.binding_set(fields0, 5, M.Slot{3, reference})
      target : M.HeapEntry = M.HeapEntry{H.entry_class(base), H.kind_method_handle(), 6, fields1, Nil{}, Nil{}}
      lambda_metafactory_callsite(H.allocate(vm2, target))

def lambda_metafactory_bridge_array(result: Result<&2, &2, String, H.Allocation>, method_name_id: U32, sam_symbol: U32, instantiated_symbol: U32, impl_ref: U32, capture_count: U32, marker_ref: U32, iface: U32, +factory_desc: String, capturing_class: U32, flags: U32) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}:
      factory_symbol = Sy.find(S.symbols(vm), factory_desc)
      lambda_metafactory_plan(H.allocate(vm, lambda_plan_entry(class_id(vm, "java/lang/invoke/LambdaMetafactory"), method_name_id, sam_symbol, instantiated_symbol, impl_ref, capture_count, marker_ref, reference, iface, factory_symbol, capturing_class, flags)), factory_desc)

def lambda_metafactory_marker_array(result: Result<&2, &2, String, H.Allocation>, bridges: +List<M.Slot>, method_name_id: U32, sam_symbol: U32, instantiated_symbol: U32, impl_ref: U32, capture_count: U32, iface: U32, factory_desc: String, capturing_class: U32, flags: U32) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}:
      lambda_metafactory_bridge_array(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/invoke/MethodType;"), class_id(vm, "java/lang/invoke/MethodType"), bridges)), method_name_id, sam_symbol, instantiated_symbol, impl_ref, capture_count, reference, iface, factory_desc, capturing_class, flags)
def metafactory_plan(+vm: M.VM, +lookup_ref: U32, name_ref: U32, factory_type_ref: U32, sam_type_ref: U32, +impl_ref: U32, instantiated_type_ref: U32, markers: +List<M.Slot>, bridges: +List<M.Slot>, flags: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    capturing_class : U32 <- lambda_lookup_class_id(vm, lookup_ref)
    privilege : Unit <- lambda_lookup_valid(vm, lookup_ref)
    +factory_desc : String <- type_desc(vm, factory_type_ref)
    +sam_desc : String <- type_desc(vm, sam_type_ref)
    +instantiated_desc : String <- type_desc(vm, instantiated_type_ref)
    checked : Unit <- S.check(U32.is_eq(count_descriptor_parameters(sam_desc), count_descriptor_parameters(instantiated_desc)), "java/lang/invoke/LambdaConversionException")
    count : Unit <- lambda_count_agrees(vm, factory_desc, sam_desc, impl_ref)
    sam_arguments : +List<String> = descriptor_tokens(descriptor_params(sam_desc), Nil{})
    +instantiated_arguments : +List<String> = descriptor_tokens(descriptor_params(instantiated_desc), Nil{})
    checked : Unit <- S.check(lambda_conversion_pairs(vm, sam_arguments, instantiated_arguments), "java/lang/invoke/LambdaConversionException")
    impl_entry : M.HeapEntry <- H.get(S.heap(vm), impl_ref)
    +implementation_desc : String <- handle_method_descriptor(vm, impl_entry)
    implementation_sources : +List<String> = M.append(String, descriptor_tokens(descriptor_params(factory_desc), Nil{}), instantiated_arguments)
    implementation_targets : +List<String> = descriptor_tokens(descriptor_params(implementation_desc), Nil{})
    checked : Unit <- S.check(lambda_conversion_pairs(vm, implementation_sources, implementation_targets), "java/lang/invoke/LambdaConversionException")
    +implementation_return : String = lambda_interface_descriptor(implementation_desc)
    +instantiated_return : String = lambda_interface_descriptor(instantiated_desc)
    sam_return : String = lambda_interface_descriptor(sam_desc)
    checked : Unit <- S.check(lambda_conversion_possible(vm, implementation_return, instantiated_return) && lambda_conversion_possible(vm, instantiated_return, sam_return), "java/lang/invoke/LambdaConversionException")
    +iface : U32 <- lambda_interface_id(vm, factory_desc)
    iface_class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), iface), "java/lang/invoke/LambdaConversionException")
    checked : Unit <- S.check(U32.is_ne(iface, class_id(vm, "java/lang/Object")), "java/lang/invoke/LambdaConversionException")
    interface_flags : U32 = L.class_flags_from_metadata(S.metadata(vm), iface)
    checked : Unit <- S.check(U32.is_ne(U32.and(interface_flags, 512), 0), "java/lang/invoke/LambdaConversionException")
    method_name : String <- text(vm, name_ref)
    +method_name_id : U32 = Sy.find(S.symbols(vm), method_name)
    +sam_symbol : U32 = Sy.find(S.symbols(vm), sam_desc)
    instantiated_symbol : U32 = Sy.find(S.symbols(vm), instantiated_desc)
    interface_method : M.LoadedMethod <- S.require(M.LoadedMethod, find_method(S.methods(vm), iface, method_name_id, sam_symbol), "java/lang/invoke/LambdaConversionException")
    +method_flags : U32 = M.loaded_method_flags(interface_method)
    checked : Unit <- S.check(U32.is_ne(U32.and(method_flags, 1024), 0) && U32.is_eq(U32.and(method_flags, 8), 0), "java/lang/invoke/LambdaConversionException")
    abstract_signatures : +List<String> = lambda_add_abstract_signatures(S.methods(vm), iface, S.symbols(vm), Nil{})
    checked : Unit <- S.check(U32.is_eq(M.length(String, abstract_signatures), 1), "java/lang/invoke/LambdaConversionException")
    capture_count : U32 = count_descriptor_parameters(factory_desc)
    result : O.Outcome <- lambda_metafactory_marker_array(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/Class;"), class_id(vm, "java/lang/Class"), markers)), bridges, method_name_id, sam_symbol, instantiated_symbol, impl_ref, capture_count, iface, factory_desc, capturing_class, flags)
    return result
def lambda_metafactory(vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    lookup : M.Slot <- arg(args, 0)
    name : M.Slot <- arg(args, 1)
    factory : M.Slot <- arg(args, 2)
    sam : M.Slot <- arg(args, 3)
    impl : M.Slot <- arg(args, 4)
    instantiated : M.Slot <- arg(args, 5)
    result : O.Outcome <- metafactory_plan(vm, bits(lookup), bits(name), bits(factory), bits(sam), bits(impl), bits(instantiated), Nil{}, Nil{}, 0)
    return result

type LambdaAlt is Data:
  LambdaAlt{flags: U32, markers: +List<M.Slot>, bridges: +List<M.Slot>}
def lambda_alt_flags(value: LambdaAlt) -> U32:
  LambdaAlt{flags, markers, bridges} = value
  flags
def lambda_alt_markers(value: LambdaAlt) -> +List<M.Slot>:
  LambdaAlt{flags, markers, bridges} = value
  markers
def lambda_alt_bridges(value: LambdaAlt) -> +List<M.Slot>:
  LambdaAlt{flags, markers, bridges} = value
  bridges

def lambda_unbox_integer(+vm: M.VM, +value: M.Slot) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    checked : Unit <- S.check(U32.is_ne(bits(value), 0), "java/lang/invoke/LambdaConversionException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits(value))
    checked : Unit <- S.check(U32.is_eq(H.entry_class(entry), class_id(vm, "java/lang/Integer")), "java/lang/invoke/LambdaConversionException")
    return H.integer_value(L.entry_fields(entry))

def lambda_marker_seen(ids: +List<U32>, +id: U32) -> Bool:
  match ids:
    case Nil{}: False{}
    case Con{head, rest}: U32.is_eq(head, id) || lambda_marker_seen(rest, id)

def lambda_validate_markers(+vm: M.VM, markers: +List<M.Slot>, +seen: +List<U32>) -> Result<&2, &2, String, Unit>:
  match markers:
    case Nil{}: Done{Unit{}}
    case Con{marker, rest}:
      do Result<&2, &2, String, Unit>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), bits(marker))
        checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), 8), "java/lang/invoke/LambdaConversionException")
        +marker_id : U32 = L.entry_element(entry)
        flags : U32 = L.class_flags_from_metadata(S.metadata(vm), marker_id)
        checked : Unit <- S.check(U32.is_ne(U32.and(flags, 512), 0) && Bool.not(lambda_marker_seen(seen, marker_id)), "java/lang/invoke/LambdaConversionException")
        abstract_signatures : +List<String> = lambda_add_abstract_signatures(S.methods(vm), marker_id, S.symbols(vm), Nil{})
        checked : Unit <- S.check(U32.is_eq(M.length(String, abstract_signatures), 0), "java/lang/invoke/LambdaConversionException")
        next : Unit <- lambda_validate_markers(vm, rest, Con{marker_id, seen})
        return next

def lambda_validate_bridges(+vm: M.VM, bridges: +List<M.Slot>, +sam_desc: String, +instantiated_desc: String) -> Result<&2, &2, String, Unit>:
  match bridges:
    case Nil{}: Done{Unit{}}
    case Con{bridge, rest}:
      do Result<&2, &2, String, Unit>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), bits(bridge))
        checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_method_type()), "java/lang/invoke/LambdaConversionException")
        +descriptor : String = Sy.text(S.symbols(vm), L.entry_element(entry))
        checked : Unit <- S.check(U32.is_eq(count_descriptor_parameters(descriptor), count_descriptor_parameters(sam_desc)) && U32.is_eq(count_descriptor_parameters(descriptor), count_descriptor_parameters(instantiated_desc)), "java/lang/invoke/LambdaConversionException")
        bridge_sources : +List<String> = descriptor_tokens(descriptor_params(descriptor), Nil{})
        instantiated_targets : +List<String> = descriptor_tokens(descriptor_params(instantiated_desc), Nil{})
        checked : Unit <- S.check(lambda_conversion_pairs(vm, bridge_sources, instantiated_targets), "java/lang/invoke/LambdaConversionException")
        bridge_result : String = lambda_interface_descriptor(descriptor)
        instantiated_result : String = lambda_interface_descriptor(instantiated_desc)
        checked : Unit <- S.check(lambda_conversion_possible(vm, instantiated_result, bridge_result), "java/lang/invoke/LambdaConversionException")
        next : Unit <- lambda_validate_bridges(vm, rest, sam_desc, instantiated_desc)
        return next

def lambda_marker_count(vm: M.VM, rest: +List<M.Slot>, present: Bool) -> Result<&2, &2, String, U32>:
  match present:
    case False{}: Done{0}
    case True{}:
      do Result<&2, &2, String, U32>:
        count_slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, rest, 0), "java/lang/invoke/LambdaConversionException")
        count : U32 <- lambda_unbox_integer(vm, count_slot)
        return count

def lambda_bridge_count(vm: M.VM, rest: +List<M.Slot>, present: Bool) -> Result<&2, &2, String, U32>:
  lambda_marker_count(vm, rest, present)
def lambda_parse_alt(+vm: M.VM, +values: +List<M.Slot>) -> Result<&2, &2, String, LambdaAlt>:
  do Result<&2, &2, String, LambdaAlt>:
    flags_slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, 3), "java/lang/invoke/LambdaConversionException")
    +flags : U32 <- lambda_unbox_integer(vm, flags_slot)
    checked : Unit <- S.check(U32.is_eq(U32.and(flags, U32.not(7)), 0), "java/lang/invoke/LambdaConversionException")
    +marker_flag : Bool = U32.is_ne(U32.and(flags, 2), 0)
    +bridge_flag : Bool = U32.is_ne(U32.and(flags, 4), 0)
    +rest : +List<M.Slot> = M.drop(M.Slot, values, 4n)
    +marker_count : U32 <- lambda_marker_count(vm, rest, marker_flag)
    +markers : +List<M.Slot> = M.take(M.Slot, M.drop(M.Slot, rest, Bool.pick(Nat, marker_flag, 1n, 0n)), U32.to_nat(marker_count))
    +after_markers : +List<M.Slot> = M.drop(M.Slot, rest, U32.to_nat(U32.add(marker_count, Bool.pick(U32, marker_flag, 1, 0))))
    +bridge_count : U32 <- lambda_bridge_count(vm, after_markers, bridge_flag)
    +bridges : +List<M.Slot> = M.take(M.Slot, M.drop(M.Slot, after_markers, Bool.pick(Nat, bridge_flag, 1n, 0n)), U32.to_nat(bridge_count))
    expected_prefix : U32 = U32.add(4, U32.add(marker_count, Bool.pick(U32, marker_flag, 1, 0)))
    expected : U32 = U32.add(expected_prefix, U32.add(bridge_count, Bool.pick(U32, bridge_flag, 1, 0)))
    checked : Unit <- S.check(U32.is_eq(M.length(M.Slot, values), expected), "java/lang/invoke/LambdaConversionException")
    sam : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, 0), "java/lang/invoke/LambdaConversionException")
    checked : Unit <- lambda_validate_markers(vm, markers, Nil{})
    sam_entry : M.HeapEntry <- H.get(S.heap(vm), bits(sam))
    instantiated_slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, 2), "java/lang/invoke/LambdaConversionException")
    instantiated_entry : M.HeapEntry <- H.get(S.heap(vm), bits(instantiated_slot))
    sam_desc : String = Sy.text(S.symbols(vm), L.entry_element(sam_entry))
    instantiated_desc : String = Sy.text(S.symbols(vm), L.entry_element(instantiated_entry))
    checked : Unit <- lambda_validate_bridges(vm, bridges, sam_desc, instantiated_desc)
    return LambdaAlt{flags, markers, bridges}


def lambda_validate_marker_functional(+vm: M.VM, markers: +List<M.Slot>, +functional: U32) -> Result<&2, &2, String, Unit>:
  match markers:
    case Nil{}: Done{Unit{}}
    case Con{marker, rest}:
      do Result<&2, &2, String, Unit>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), bits(marker))
        checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), 8), "java/lang/invoke/LambdaConversionException")
        checked : Unit <- S.check(U32.is_ne(L.entry_element(entry), functional), "java/lang/invoke/LambdaConversionException")
        next : Unit <- lambda_validate_marker_functional(vm, rest, functional)
        return next

def lambda_alt_metafactory(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    lookup : M.Slot <- arg(args, 0)
    name : M.Slot <- arg(args, 1)
    +factory : M.Slot <- arg(args, 2)
    array : M.Slot <- arg(args, 3)
    +values : +List<M.Slot> <- lambda_array_slots(vm, bits(array))
    sam : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, 0), "java/lang/invoke/LambdaConversionException")
    impl : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, 1), "java/lang/invoke/LambdaConversionException")
    instantiated : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, 2), "java/lang/invoke/LambdaConversionException")
    factory_descriptor : String <- type_desc(vm, bits(factory))
    functional_interface : U32 <- lambda_interface_id(vm, factory_descriptor)
    +alt : LambdaAlt <- lambda_parse_alt(vm, values)
    checked : Unit <- lambda_validate_marker_functional(vm, lambda_alt_markers(alt), functional_interface)
    result : O.Outcome <- metafactory_plan(vm, bits(lookup), bits(name), bits(factory), bits(sam), bits(impl), bits(instantiated), lambda_alt_markers(alt), lambda_alt_bridges(alt), lambda_alt_flags(alt))
    return result

def lambda_loaded_method(id: U32, owner: U32, name: U32, descriptor_id: U32, descriptor: String, flags: U32, intrinsic: U32) -> Result<&2, &2, String, M.LoadedMethod>:
  do Result<&2, &2, String, M.LoadedMethod>:
    +parsed : M.Descriptor <- D.parse_method(descriptor)
    parameters : +List<M.JvmType> = D.parameter_types(parsed)
    max_locals : U32 = U32.add(1, D.parameter_slots(parameters))
    return M.LoadedMethod{id, owner, name, descriptor_id, flags, D.parameter_count(parsed), D.slot_tag(D.result_type(parsed)), 2, max_locals, Nil{}, Nil{}, intrinsic, Nil{}}

def lambda_loaded_method_ids(methods: +List<M.LoadedMethod>, +ids: +List<U32>) -> +List<U32>:
  match methods:
    case Nil{}: M.reverse(U32, ids)
    case Con{+method, rest}: lambda_loaded_method_ids(rest, Con{M.loaded_method_id(method), ids})

def lambda_bridge_methods(+vm: M.VM, bridges: +List<M.Slot>, +owner: U32, +name: U32, +next_id: U32, methods: +List<M.LoadedMethod>) -> Result<&2, &2, String, +List<M.LoadedMethod>>:
  match bridges:
    case Nil{}: Done{M.reverse(M.LoadedMethod, methods)}
    case Con{bridge, rest}:
      do Result<&2, &2, String, +List<M.LoadedMethod>>:
        +type_entry : M.HeapEntry <- H.get(S.heap(vm), bits(bridge))
        checked : Unit <- S.check(U32.is_eq(L.entry_kind(type_entry), H.kind_method_type()), "java/lang/invoke/LambdaConversionException")
        +descriptor_id : U32 = L.entry_element(type_entry)
        descriptor : String = Sy.text(S.symbols(vm), descriptor_id)
        method : M.LoadedMethod <- lambda_loaded_method(next_id, owner, name, descriptor_id, descriptor, 4161, 450)
        generated : +List<M.LoadedMethod> <- lambda_bridge_methods(vm, rest, owner, name, U32.add(next_id, 1), Con{method, methods})
        return generated

def lambda_marker_ids(+vm: M.VM, markers: +List<M.Slot>, ids: +List<U32>) -> Result<&2, &2, String, +List<U32>>:
  match markers:
    case Nil{}: Done{M.reverse(U32, ids)}
    case Con{marker, rest}:
      do Result<&2, &2, String, +List<U32>>:
        +mirror : M.HeapEntry <- H.get(S.heap(vm), bits(marker))
        checked : Unit <- S.check(U32.is_eq(L.entry_kind(mirror), 8), "java/lang/invoke/LambdaConversionException")
        next_ids : +List<U32> <- lambda_marker_ids(vm, rest, Con{L.entry_element(mirror), ids})
        return next_ids

type LambdaDispatch is Data:
  LambdaDispatch{vm: M.VM, handle: U32, targetDescriptor: String, instantiatedDescriptor: String, samDescriptor: String, arguments: +List<M.Slot>}

def lambda_publish_host(vm: M.VM, owner: U32, host: M.Host) -> M.VM:
  match host:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}:
      M.Metadata{classes, fields, methods} = metadata
      class_metadata : M.ClassMetadata = M.ClassMetadata{owner, 4145, M.empty_annotation_metadata(), Nil{}, Nil{}, "", M.empty_nesting(), ""}
      updated : M.Metadata = M.Metadata{M.append(M.ClassMetadata, classes, [class_metadata]), fields, methods}
      S.with_host(vm, M.Host{effect, cwd, caps, maxPayload, cont, updated, dynamicSites, loaders, sched, errors})

def lambda_publish_metadata(+vm: M.VM, owner: U32) -> M.VM:
  lambda_publish_host(vm, owner, S.host(vm))

def lambda_publish_loaded(vm: M.VM, +owner: U32, plan_ref: U32, +plan: M.HeapEntry, generated_class: M.LoadedClass, appended_methods: +List<M.LoadedMethod>) -> Result<&2, &2, String, M.VM>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, status, exception, result, output, error, maxHeap, steps, host, roots} = vm
  vm2 : M.VM = M.VM{M.append(M.LoadedClass, cs, [generated_class]), M.append(M.LoadedMethod, ms, appended_methods), fs, sy, hp, st, rs, fr, status, exception, result, output, error, maxHeap, steps, host, roots}
  published : M.VM = lambda_publish_metadata(vm2, owner)
  updated_plan : M.HeapEntry = M.HeapEntry{H.entry_class(plan), L.entry_kind(plan), L.entry_element(plan), H.binding_set(L.entry_fields(plan), 9, M.Slot{1, owner}), L.entry_values(plan), L.entry_chars(plan)}
  Done{H.put(published, plan_ref, updated_plan)}

def lambda_publish_class_new(+vm: M.VM, plan_ref: U32, +plan: M.HeapEntry) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    iface_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 7), "java/lang/IllegalStateException")
    +name_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 0), "java/lang/IllegalStateException")
    +desc_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 1), "java/lang/IllegalStateException")
    marker_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 5), "java/lang/IllegalStateException")
    bridge_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 6), "java/lang/IllegalStateException")
    marker_array : M.HeapEntry <- H.get(S.heap(vm), bits(marker_slot))
    bridge_array : M.HeapEntry <- H.get(S.heap(vm), bits(bridge_slot))
    +cid : U32 = M.length(M.LoadedClass, S.classes(vm))
    +generated_name : String = "$Lambda$" ++ U32.show(cid)
    +symbol_id : U32 = M.length(String, S.symbols(vm))
    +method_id : U32 = M.length(M.LoadedMethod, S.methods(vm))
    descriptor : String = Sy.text(S.symbols(vm), bits(desc_slot))
    method : M.LoadedMethod <- lambda_loaded_method(method_id, cid, bits(name_slot), bits(desc_slot), descriptor, 4113, 450)
    +markers : +List<U32> <- lambda_marker_ids(vm, L.entry_values(marker_array), Nil{})
    +generated : +List<M.LoadedMethod> <- lambda_bridge_methods(vm, L.entry_values(bridge_array), cid, bits(name_slot), U32.add(method_id, 1), Nil{})
    flags_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 11), "java/lang/IllegalStateException")
    +serializable : Bool = U32.is_ne(U32.and(bits(flags_slot), 1), 0)
    +serializable_id : U32 = class_id(vm, "java/io/Serializable")
    add_serializable : Bool = serializable && Bool.not(lambda_marker_seen(markers, serializable_id))
    serial_interfaces : +List<U32> = Bool.pick(+List<U32>, add_serializable, [serializable_id], Nil{})
    interfaces : +List<U32> = M.append(U32, [bits(iface_slot)], M.append(U32, markers, serial_interfaces))
    +serial_method_id : U32 = U32.add(U32.add(method_id, 1), M.length(M.LoadedMethod, generated))
    # writeReplace()Object reuses the interned symbols, so lookups by name find it.
    +named_symbols : +List<String> = M.append(String, S.symbols(vm), [generated_name])
    +replace_name : Sy.Interned = Sy.intern(named_symbols, "writeReplace")
    +replace_descriptor : Sy.Interned = Sy.intern(Sy.interned_symbols(replace_name), "()Ljava/lang/Object;")
    serial_method : M.LoadedMethod <- lambda_loaded_method(serial_method_id, cid, interned_id(replace_name), interned_id(replace_descriptor), "()Ljava/lang/Object;", 4098, 451)
    method_ids : +List<U32> = M.append(U32, [method_id], M.append(U32, lambda_loaded_method_ids(generated, Nil{}), Bool.pick(+List<U32>, serializable, [serial_method_id], Nil{})))
    generated_class : M.LoadedClass = M.LoadedClass{cid, symbol_id, class_id(vm, "java/lang/Object"), interfaces, Nil{}, method_ids, 4294967295, 0, Nil{}}
    symbols : +List<String> = Bool.pick(+List<String>, serializable, Sy.interned_symbols(replace_descriptor), named_symbols)
    vm1 : M.VM = S.with_symbols(vm, symbols)
    appended_methods : +List<M.LoadedMethod> = M.append(M.LoadedMethod, [method], M.append(M.LoadedMethod, generated, Bool.pick(+List<M.LoadedMethod>, serializable, [serial_method], Nil{})))
    published : M.VM <- lambda_publish_loaded(vm1, cid, plan_ref, plan, generated_class, appended_methods)
    return published

def lambda_publish_class_cached(vm: M.VM, plan_ref: U32, plan: M.HeapEntry, cached: Bool) -> Result<&2, &2, String, M.VM>:
  match cached:
    case True{}: Done{vm}
    case False{}: lambda_publish_class_new(vm, plan_ref, plan)

def lambda_publish_class(+vm: M.VM, +plan_ref: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +plan : M.HeapEntry <- H.get(S.heap(vm), plan_ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(plan), H.kind_lambda_plan()), "java/lang/IllegalArgumentException: not a lambda plan")
    cached : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 9), "java/lang/IllegalStateException")
    cached_nonzero : Bool = U32.is_ne(bits(cached), 0)
    published : M.VM <- lambda_publish_class_cached(vm, plan_ref, plan, cached_nonzero)
    return published

def lambda_capture_fields(args: +List<M.Slot>, +impl: U32, +instantiated: U32, +factory_descriptor: U32, +plan_ref: U32, +index: U32) -> +List<M.Binding>:
  match args:
    case Nil{}: [M.Binding{0, M.Slot{3, impl}}, M.Binding{1, M.Slot{1, instantiated}}, M.Binding{2, M.Slot{1, factory_descriptor}}, M.Binding{3, M.Slot{3, plan_ref}}]
    case Con{value, rest}: Con{M.Binding{U32.add(index, 4), value}, lambda_capture_fields(rest, impl, instantiated, factory_descriptor, plan_ref, U32.add(index, 1))}
def lambda_factory(+vm: M.VM, +plan_ref: U32, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +plan : M.HeapEntry <- H.get(S.heap(vm), plan_ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(plan), H.kind_lambda_plan()), "java/lang/IllegalArgumentException: not a lambda plan")
    capture_count : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 4), "java/lang/IllegalStateException")
    checked : Unit <- S.check(U32.is_eq(M.length(M.Slot, args), bits(capture_count)), "java/lang/invoke/WrongMethodTypeException")
    +published : M.VM <- lambda_publish_class(vm, plan_ref)
    +updated_plan : M.HeapEntry <- H.get(S.heap(published), plan_ref)
    class_id_value : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(updated_plan), 9), "java/lang/IllegalStateException")
    impl : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(updated_plan), 3), "java/lang/IllegalStateException")
    instantiated : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(updated_plan), 2), "java/lang/IllegalStateException")
    factory_descriptor : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(updated_plan), 8), "java/lang/IllegalStateException")
    fields : +List<M.Binding> = lambda_capture_fields(args, bits(impl), bits(instantiated), bits(factory_descriptor), plan_ref, 0)
    allocated : O.Outcome <- alloc_ref(H.allocate(published, H.object_entry(bits(class_id_value), fields)))
    return allocated


type LambdaAdaptedSlot is Data:
  LambdaAdaptedSlot{vm: M.VM, slot: M.Slot}
def lambda_adapt_slot_vm(value: LambdaAdaptedSlot) -> M.VM:
  LambdaAdaptedSlot{vm, slot} = value
  vm
def lambda_adapt_slot_value(value: LambdaAdaptedSlot) -> M.Slot:
  LambdaAdaptedSlot{vm, slot} = value
  slot
type LambdaAdaptedArguments is Data:
  LambdaAdaptedArguments{vm: M.VM, values: +List<M.Slot>}

def lambda_adapted_vm(value: LambdaAdaptedArguments) -> M.VM:
  LambdaAdaptedArguments{vm, values} = value
  vm
def lambda_adapted_values(value: LambdaAdaptedArguments) -> +List<M.Slot>:
  LambdaAdaptedArguments{vm, values} = value
  values

def lambda_descriptor_code(desc: String) -> U32:
  lambda_conversion_code_chars(String.to_list(desc))

def lambda_box_result(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{vm, Some{slot}}}: Done{LambdaAdaptedSlot{vm, slot}}
    case _: Fail{"java/lang/invoke/LambdaConversionException"}
def lambda_box_cast_reference_result(vm: M.VM, result: Result<&2, &2, String, M.Slot>) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  match result:
    case Fail{_}: Fail{"java/lang/ClassCastException"}
    case Done{converted}: Done{LambdaAdaptedSlot{vm, converted}}

def lambda_box_cast_result(result: Result<&2, &2, String, LambdaAdaptedSlot>, target: String) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  match result:
    case Fail{error}: Fail{error}
    case Done{LambdaAdaptedSlot{+vm, slot}}:
      lambda_box_cast_reference_result(vm, L.reflect_convert_reference(vm, target, slot))

def lambda_box_cast(vm: M.VM, source: String, target: String, value: M.Slot) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  lambda_box_cast_result(lambda_box_result(L.reflect_box_value(vm, primitive_name(source), value)), target)

def lambda_adapt_reference_result(vm: M.VM, result: Result<&2, &2, String, M.Slot>) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  match result:
    case Fail{_}: Fail{"java/lang/ClassCastException"}
    case Done{converted}: Done{LambdaAdaptedSlot{vm, converted}}

def lambda_adapt_primitive_result(vm: M.VM, result: Result<&2, &2, String, M.Slot>) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  match result:
    case Fail{_}: Fail{"java/lang/ClassCastException"}
    case Done{converted}: Done{LambdaAdaptedSlot{vm, converted}}

def lambda_adapt_widen_result(vm: M.VM, result: Result<&2, &2, String, M.Slot>) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  match result:
    case Fail{_}: Fail{"java/lang/invoke/WrongMethodTypeException"}
    case Done{converted}: Done{LambdaAdaptedSlot{vm, converted}}

def lambda_adapt_types(+vm: M.VM, +source: String, +target: String, +value: M.Slot, source_ref: Bool, target_ref: Bool) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  match source_ref target_ref:
    case True{} True{}: lambda_adapt_reference_result(vm, L.reflect_convert_reference(vm, target, value))
    case True{} False{}: lambda_adapt_primitive_result(vm, L.reflect_convert_primitive(vm, lambda_descriptor_code(target), value))
    case False{} True{}: lambda_box_cast(vm, source, target, value)
    case False{} False{}: lambda_adapt_widen_result(vm, L.reflect_widen(lambda_descriptor_code(source), lambda_descriptor_code(target), value))

def lambda_adapt_distinct(vm: M.VM, +source: String, +target: String, value: M.Slot) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  source_ref = String.starts_with(source, "L") || String.starts_with(source, "[")
  target_ref = String.starts_with(target, "L") || String.starts_with(target, "[")
  lambda_adapt_types(vm, source, target, value, source_ref, target_ref)

def lambda_adapt_same(vm: M.VM, source: String, target: String, value: M.Slot, same: Bool) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  match same:
    case True{}: Done{LambdaAdaptedSlot{vm, value}}
    case False{}: lambda_adapt_distinct(vm, source, target, value)

def lambda_adapt_slot(vm: M.VM, +source: String, +target: String, value: M.Slot) -> Result<&2, &2, String, LambdaAdaptedSlot>:
  lambda_adapt_same(vm, source, target, value, String.eq(source, target))

@unsafe def lambda_adapt_arguments(vm: M.VM, sources: +List<String>, targets: +List<String>, values: +List<M.Slot>, output: +List<M.Slot>) -> Result<&2, &2, String, LambdaAdaptedArguments>:
  match sources targets values:
    case Nil{} Nil{} Nil{}: Done{LambdaAdaptedArguments{vm, M.reverse(M.Slot, output)}}
    case Con{source, source_rest} Con{target, target_rest} Con{value, value_rest}:
      do Result<&2, &2, String, LambdaAdaptedArguments>:
        +adapted : LambdaAdaptedSlot <- lambda_adapt_slot(vm, source, target, value)
        result : LambdaAdaptedArguments <- lambda_adapt_arguments(lambda_adapt_slot_vm(adapted), source_rest, target_rest, value_rest, Con{lambda_adapt_slot_value(adapted), output})
        return result
    case _ _ _: Fail{"java/lang/invoke/LambdaConversionException"}

@unsafe def lambda_capture_values(fields: +List<M.Binding>, +index: U32, +output: +List<M.Slot>) -> +List<M.Slot>:
  match fields:
    case Nil{}: M.reverse(M.Slot, output)
    case Con{binding, +rest}:
      match binding:
        case M.Binding{key, value}:
          lambda_capture_step(U32.is_ge(key, U32.add(index, 1)), value, rest, index, output)
@unsafe def lambda_capture_step(+captured: Bool, value: M.Slot, +rest: +List<M.Binding>, +index: U32, +output: +List<M.Slot>) -> +List<M.Slot>:
  match captured:
    case True{}: lambda_capture_values(rest, index, Con{value, output})
    case False{}: lambda_capture_values(rest, index, output)
def lambda_dispatch(+vm: M.VM, receiver_ref: U32, +sam_descriptor: String, args: +List<M.Slot>) -> Result<&2, &2, String, LambdaDispatch>:
  do Result<&2, &2, String, LambdaDispatch>:
    +object : M.HeapEntry <- H.get(S.heap(vm), receiver_ref)
    +impl : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(object), 0), "java/lang/IllegalArgumentException")
    instantiated : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(object), 1), "java/lang/IllegalArgumentException")
    factory_type : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(object), 2), "java/lang/IllegalArgumentException")
    +target_desc : String <- handle_descriptor(vm, bits(impl))
    +instantiated_desc : String = Sy.text(S.symbols(vm), bits(instantiated))
    factory_desc : String = Sy.text(S.symbols(vm), bits(factory_type))
    sam_sources : +List<String> = descriptor_tokens(descriptor_params(sam_descriptor), Nil{})
    +sam_targets : +List<String> = descriptor_tokens(descriptor_params(instantiated_desc), Nil{})
    +sam_adapted : LambdaAdaptedArguments <- lambda_adapt_arguments(vm, sam_sources, sam_targets, args, Nil{})
    capture_sources : +List<String> = descriptor_tokens(descriptor_params(factory_desc), Nil{})
    captures : +List<M.Slot> = lambda_capture_values(L.entry_fields(object), 3, Nil{})
    values : +List<M.Slot> = M.append(M.Slot, captures, lambda_adapted_values(sam_adapted))
    sources : +List<String> = M.append(String, capture_sources, sam_targets)
    targets : +List<String> = descriptor_tokens(descriptor_params(target_desc), Nil{})
    +target_adapted : LambdaAdaptedArguments <- lambda_adapt_arguments(lambda_adapted_vm(sam_adapted), sources, targets, values, Nil{})
    return LambdaDispatch{lambda_adapted_vm(target_adapted), bits(impl), target_desc, instantiated_desc, sam_descriptor, lambda_adapted_values(target_adapted)}


def lambda_factory_descriptor(+vm: M.VM, plan_ref: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +plan : M.HeapEntry <- H.get(S.heap(vm), plan_ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(plan), H.kind_lambda_plan()), "java/lang/IllegalArgumentException: not a lambda plan")
    descriptor : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 8), "java/lang/IllegalStateException")
    return Sy.text(S.symbols(vm), bits(descriptor))

def lambda_factory_handle(+vm: M.VM, handle_ref: U32, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +handle : M.HeapEntry <- H.get(S.heap(vm), handle_ref)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(handle), H.kind_method_handle()) && U32.is_eq(L.entry_element(handle), 6), "java/lang/invoke/WrongMethodTypeException")
    mode : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(handle), 4), "java/lang/IllegalStateException")
    checked : Unit <- S.check(U32.is_eq(bits(mode), 9), "java/lang/invoke/WrongMethodTypeException")
    plan : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(handle), 5), "java/lang/IllegalStateException")
    result : O.Outcome <- lambda_factory(vm, bits(plan), args)
    return result


type LambdaAllocatedRef is Data:
  LambdaAllocatedRef{vm: M.VM, reference: U32}
type LambdaAllocatedSlot is Data:
  LambdaAllocatedSlot{vm: M.VM, slot: M.Slot}
type LambdaCaptureTypes is Data:
  LambdaCaptureTypes{sources: +List<String>, targets: +List<String>}
def lambda_allocated_vm(value: LambdaAllocatedRef) -> M.VM:
  LambdaAllocatedRef{vm, reference} = value
  vm
def lambda_allocated_reference(value: LambdaAllocatedRef) -> U32:
  LambdaAllocatedRef{vm, reference} = value
  reference
def lambda_allocated_slot_vm(value: LambdaAllocatedSlot) -> M.VM:
  LambdaAllocatedSlot{vm, slot} = value
  vm
def lambda_allocated_slot(value: LambdaAllocatedSlot) -> M.Slot:
  LambdaAllocatedSlot{vm, slot} = value
  slot

def lambda_outcome_ref(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, LambdaAllocatedRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{vm, Some{M.Slot{3, reference}}}}: Done{LambdaAllocatedRef{vm, reference}}
    case _: Fail{"java/lang/invoke/LambdaConversionException"}

def lambda_string_ref(vm: M.VM, value: String) -> Result<&2, &2, String, LambdaAllocatedRef>:
  lambda_outcome_ref(L.intern_or_alloc(vm, units_from_text(value)))

def lambda_string_slot_result(result: Result<&2, &2, String, LambdaAllocatedRef>) -> Result<&2, &2, String, LambdaAllocatedSlot>:
  match result:
    case Fail{error}: Fail{error}
    case Done{LambdaAllocatedRef{vm, reference}}: Done{LambdaAllocatedSlot{vm, M.Slot{3, reference}}}

def lambda_string_slot(vm: M.VM, value: String) -> Result<&2, &2, String, LambdaAllocatedSlot>:
  lambda_string_slot_result(lambda_string_ref(vm, value))

def lambda_capture_type_lists_state(types: +List<String>, +sources: +List<String>, +targets: +List<String>) -> LambdaCaptureTypes:
  match types:
    case Nil{}: LambdaCaptureTypes{M.reverse(String, sources), M.reverse(String, targets)}
    case Con{source, rest}: lambda_capture_type_lists_state(rest, Con{source, sources}, Con{"Ljava/lang/Object;", targets})

def lambda_capture_type_lists(types: +List<String>) -> LambdaCaptureTypes:
  lambda_capture_type_lists_state(types, Nil{}, Nil{})
def lambda_adapt_capture_type_lists(vm: M.VM, capture_types: LambdaCaptureTypes, captures: +List<M.Slot>) -> Result<&2, &2, String, LambdaAdaptedArguments>:
  LambdaCaptureTypes{sources, targets} = capture_types
  lambda_adapt_arguments(vm, sources, targets, captures, Nil{})

def lambda_adapt_captures(vm: M.VM, factory_desc: String, captures: +List<M.Slot>) -> Result<&2, &2, String, LambdaAdaptedArguments>:
  lambda_adapt_capture_type_lists(vm, lambda_capture_type_lists(descriptor_tokens(descriptor_params(factory_desc), Nil{})), captures)
def lambda_write_replace_capture(capturing_mirror: U32, fi_class: M.Slot, sam_name: M.Slot, sam_desc: M.Slot, impl_kind: U32, impl_class: M.Slot, impl_name: M.Slot, impl_desc: M.Slot, instantiated: M.Slot, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, reference}}:
      fields : +List<M.Binding> = [M.Binding{0, M.Slot{3, capturing_mirror}}, M.Binding{1, fi_class}, M.Binding{2, sam_name}, M.Binding{3, sam_desc}, M.Binding{4, M.Slot{1, impl_kind}}, M.Binding{5, impl_class}, M.Binding{6, impl_name}, M.Binding{7, impl_desc}, M.Binding{8, instantiated}, M.Binding{9, M.Slot{3, reference}}]
      alloc_ref(H.allocate(vm, H.object_entry(class_id(vm, "java/lang/invoke/SerializedLambda"), fields)))
def lambda_write_replace_boxed(capturing_mirror: U32, fi_class: M.Slot, sam_name: M.Slot, sam_desc: M.Slot, impl_kind: U32, impl_class: M.Slot, impl_name: M.Slot, impl_desc: M.Slot, instantiated: M.Slot, boxed: LambdaAdaptedArguments) -> Result<&2, &2, String, O.Outcome>:
  LambdaAdaptedArguments{+vm, values} = boxed
  lambda_write_replace_capture(capturing_mirror, fi_class, sam_name, sam_desc, impl_kind, impl_class, impl_name, impl_desc, instantiated, H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/Object;"), class_id(vm, "java/lang/Object"), values)))

def lambda_write_replace_strings(vm: M.VM, capturing_mirror: U32, interface_name: String, sam_name: M.Slot, sam_desc: M.Slot, instantiated: M.Slot, impl_entry: M.HeapEntry, impl_owner: M.Slot, impl_name: M.Slot, impl_desc: M.Slot, +object: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +fi_class : LambdaAllocatedSlot <- lambda_string_slot(vm, interface_name)
    sam_name_text : String = Sy.text(S.symbols(lambda_allocated_slot_vm(fi_class)), bits(sam_name))
    +sam_name_slot : LambdaAllocatedSlot <- lambda_string_slot(lambda_allocated_slot_vm(fi_class), sam_name_text)
    sam_desc_text : String = Sy.text(S.symbols(lambda_allocated_slot_vm(sam_name_slot)), bits(sam_desc))
    +sam_desc_slot : LambdaAllocatedSlot <- lambda_string_slot(lambda_allocated_slot_vm(sam_name_slot), sam_desc_text)
    impl_class_text : String = L.class_name_text(lambda_allocated_slot_vm(sam_desc_slot), bits(impl_owner))
    +impl_class_slot : LambdaAllocatedSlot <- lambda_string_slot(lambda_allocated_slot_vm(sam_desc_slot), impl_class_text)
    impl_name_text : String = Sy.text(S.symbols(lambda_allocated_slot_vm(impl_class_slot)), bits(impl_name))
    +impl_name_slot : LambdaAllocatedSlot <- lambda_string_slot(lambda_allocated_slot_vm(impl_class_slot), impl_name_text)
    impl_desc_text : String = Sy.text(S.symbols(lambda_allocated_slot_vm(impl_name_slot)), bits(impl_desc))
    +impl_desc_slot : LambdaAllocatedSlot <- lambda_string_slot(lambda_allocated_slot_vm(impl_name_slot), impl_desc_text)
    instantiated_text : String = Sy.text(S.symbols(lambda_allocated_slot_vm(impl_desc_slot)), bits(instantiated))
    +instantiated_slot : LambdaAllocatedSlot <- lambda_string_slot(lambda_allocated_slot_vm(impl_desc_slot), instantiated_text)
    factory_type : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(object), 2), "java/lang/IllegalStateException")
    factory_desc : String = Sy.text(S.symbols(lambda_allocated_slot_vm(instantiated_slot)), bits(factory_type))
    captures : +List<M.Slot> = lambda_capture_values(L.entry_fields(object), 3, Nil{})
    boxed : LambdaAdaptedArguments <- lambda_adapt_captures(lambda_allocated_slot_vm(instantiated_slot), factory_desc, captures)
    result : O.Outcome <- lambda_write_replace_boxed(capturing_mirror, lambda_allocated_slot(fi_class), lambda_allocated_slot(sam_name_slot), lambda_allocated_slot(sam_desc_slot), L.entry_element(impl_entry), lambda_allocated_slot(impl_class_slot), lambda_allocated_slot(impl_name_slot), lambda_allocated_slot(impl_desc_slot), lambda_allocated_slot(instantiated_slot), boxed)
    return result

def lambda_write_replace(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    receiver : M.Slot <- arg(args, 0)
    +object : M.HeapEntry <- H.get(S.heap(vm), bits(receiver))
    plan_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(object), 3), "java/lang/IllegalArgumentException")
    +plan : M.HeapEntry <- H.get(S.heap(vm), bits(plan_slot))
    serial_flags : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 11), "java/lang/IllegalStateException")
    checked : Unit <- S.check(U32.is_ne(U32.and(bits(serial_flags), 1), 0), "java/lang/UnsupportedOperationException")
    capturing : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 10), "java/lang/IllegalStateException")
    iface : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 7), "java/lang/IllegalStateException")
    sam_name : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 0), "java/lang/IllegalStateException")
    sam_desc : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 1), "java/lang/IllegalStateException")
    instantiated : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 2), "java/lang/IllegalStateException")
    impl : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(plan), 3), "java/lang/IllegalStateException")
    +impl_entry : M.HeapEntry <- H.get(S.heap(vm), bits(impl))
    impl_owner : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(impl_entry), 0), "java/lang/IllegalStateException")
    impl_name : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(impl_entry), 1), "java/lang/IllegalStateException")
    impl_desc : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(impl_entry), 2), "java/lang/IllegalStateException")
    +class_mirror : LambdaAllocatedRef <- lambda_outcome_ref(L.class_mirror_out(vm, bits(capturing)))
    interface_name : String = L.class_name_text(lambda_allocated_vm(class_mirror), bits(iface))
    result : O.Outcome <- lambda_write_replace_strings(lambda_allocated_vm(class_mirror), lambda_allocated_reference(class_mirror), interface_name, sam_name, sam_desc, instantiated, impl_entry, impl_owner, impl_name, impl_desc, object)
    return result



def serialized_lambda_get_reference(vm: M.VM, entry: M.HeapEntry, field: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), field), "java/lang/IllegalStateException")
    result : O.Outcome <- L.ref_out(vm, bits(value))
    return result

def serialized_lambda_get_integer(vm: M.VM, entry: M.HeapEntry, field: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), field), "java/lang/IllegalStateException")
    result : O.Outcome <- L.int_out(vm, bits(value))
    return result

def serialized_lambda_get_capture_count(+vm: M.VM, entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    array_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 9), "java/lang/IllegalStateException")
    array : M.HeapEntry <- H.get(S.heap(vm), bits(array_slot))
    result : O.Outcome <- L.int_out(vm, M.length(M.Slot, L.entry_values(array)))
    return result

def serialized_lambda_get_capture(+vm: M.VM, entry: M.HeapEntry, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    index : M.Slot <- arg(args, 0)
    array_slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 9), "java/lang/IllegalStateException")
    array : M.HeapEntry <- H.get(S.heap(vm), bits(array_slot))
    value : M.Slot <- S.require(M.Slot, M.nth(M.Slot, L.entry_values(array), bits(index)), "java/lang/IndexOutOfBoundsException")
    result : O.Outcome <- L.ref_out(vm, bits(value))
    return result
# Java 8 getCapturingClass() returns the capturing class's binary name with '/' separators.
def serialized_lambda_capturing_class(+vm: M.VM, entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    value : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), 0), "java/lang/IllegalStateException")
    +mirror : M.HeapEntry <- H.get(S.heap(vm), bits(value))
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(mirror), 8), "java/lang/IllegalStateException")
    result : O.Outcome <- L.intern_or_alloc(vm, L.units_from_string(L.class_name_text(vm, L.entry_element(mirror))))
    return result

def serialized_lambda_get_value(id: U32, vm: M.VM, entry: M.HeapEntry, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 445: serialized_lambda_capturing_class(vm, entry)
    case 446: serialized_lambda_get_reference(vm, entry, 1)
    case 447: serialized_lambda_get_reference(vm, entry, 2)
    case 448: serialized_lambda_get_reference(vm, entry, 3)
    case 449: serialized_lambda_get_integer(vm, entry, 4)
    case 452: serialized_lambda_get_reference(vm, entry, 5)
    case 453: serialized_lambda_get_reference(vm, entry, 6)
    case 454: serialized_lambda_get_reference(vm, entry, 7)
    case 455: serialized_lambda_get_reference(vm, entry, 8)
    case 456: serialized_lambda_get_capture_count(vm, entry)
    case 457: serialized_lambda_get_capture(vm, entry, args)
    case _: Fail{"java/lang/UnsupportedOperationException"}

def serialized_lambda_get_receiver(id: U32, +vm: M.VM, receiver: M.Slot, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), bits(receiver))
    checked : Unit <- S.check(U32.is_eq(H.entry_class(entry), class_id(vm, "java/lang/invoke/SerializedLambda")), "java/lang/IllegalArgumentException")
    result : O.Outcome <- serialized_lambda_get_value(id, vm, entry, args)
    return result
def serialized_lambda_get(id: U32, +vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Nil{}: Fail{"java/lang/IllegalArgumentException"}
    case Con{receiver, rest}: serialized_lambda_get_receiver(id, vm, receiver, rest)



def serialized_lambda_init_fields(args: +List<M.Slot>, +index: U32, fields: +List<M.Binding>) -> +List<M.Binding>:
  match args:
    case Nil{}: fields
    case Con{value, rest}: Con{M.Binding{index, value}, serialized_lambda_init_fields(rest, U32.add(index, 1), fields)}
def serialized_lambda_init_receiver(+vm: M.VM, +receiver: M.Slot, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +object : M.HeapEntry <- H.get(S.heap(vm), bits(receiver))
    checked : Unit <- S.check(U32.is_eq(H.entry_class(object), class_id(vm, "java/lang/invoke/SerializedLambda")), "java/lang/IllegalArgumentException")
    fields : +List<M.Binding> = serialized_lambda_init_fields(args, 0, Nil{})
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(object), L.entry_kind(object), L.entry_element(object), fields, L.entry_values(object), L.entry_chars(object)}
    result : O.Outcome <- L.void_out(H.put(vm, bits(receiver), updated))
    return result

def serialized_lambda_init(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Nil{}: Fail{"java/lang/IllegalArgumentException"}
    case Con{receiver, rest}: serialized_lambda_init_receiver(vm, receiver, rest)


def serialized_lambda_execute(id: U32, vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 444: serialized_lambda_init(vm, args)
    case _: serialized_lambda_get(id, vm, args)

@unsafe def execute_vm(id: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 444: serialized_lambda_execute(id, vm, args)
    case 445: serialized_lambda_execute(id, vm, args)
    case 446: serialized_lambda_execute(id, vm, args)
    case 447: serialized_lambda_execute(id, vm, args)
    case 448: serialized_lambda_execute(id, vm, args)
    case 449: serialized_lambda_execute(id, vm, args)
    case 451: lambda_write_replace(vm, args)
    case 452: serialized_lambda_execute(id, vm, args)
    case 453: serialized_lambda_execute(id, vm, args)
    case 454: serialized_lambda_execute(id, vm, args)
    case 455: serialized_lambda_execute(id, vm, args)
    case 456: serialized_lambda_execute(id, vm, args)
    case 457: serialized_lambda_execute(id, vm, args)
    case 442: lambda_metafactory(vm, args)
    case 443: lambda_alt_metafactory(vm, args)
    case 458: methodtype_from_return(vm, args)
    case 459: methodtype_from_return_param(vm, args)
    case 400: methodtype_from_class_args(vm, args)
    case 592: methodtype_from_first_rest(vm, args)
    case 593: methodtype_from_type(vm, args)
    case 401: methodtype_count(vm, args)
    case 402: type_return(vm, args)
    case 403: methodtype_parameter_array(vm, args)
    case 404: methodtype_param(vm, args)
    case 405: methodtype_string(vm, args)
    case 406: type_equals(vm, args)
    case 407: lookup_factory(vm, False{})
    case 408: lookup_factory(vm, True{})
    case 409: lookup_in(vm, args)
    case 584: methodtype_to_string(vm, args)
    case 585: lookup_init(vm, args, False{})
    case 586: lookup_init(vm, args, True{})
    case 587: unreflect(vm, args)
    case 588: unreflect_special(vm, args)
    case 589: unreflect_constructor(vm, args)
    case 590: unreflect_field(vm, args, False{})
    case 591: unreflect_field(vm, args, True{})
    case 410: direct_handle(vm, args, 6, True{}, False{})
    case 411: direct_handle(vm, args, 5, False{}, False{})
    case 412: methodtype_from_descriptor(vm, args)
    case 413: methodtype_hash(vm, args)
    case 439: methodhandles_constant(vm, args)
    case 440: methodhandles_identity(vm, args)
    case 441: methodhandles_insert_arguments(vm, args)
    case 414: handle_type(vm, args)
    case 415: handle_as_type(vm, args)
    case 416: handle_fixed(vm, args)
    case 417: handle_varargs(vm, args)
    case 418: handle_is_varargs(vm, args)
    case 419: callsite_dynamic_invoker(vm, args)
    case 420: callsite_type(vm, args)
    case 421: callsite_get(vm, args)
    case 422: callsite_set(vm, args)
    case 423: callsite_init(vm, args, 0, False{})
    case 424: callsite_init(vm, args, 1, False{})
    case 425: callsite_init(vm, args, 1, True{})
    case 426: callsite_init(vm, args, 2, False{})
    case 460: mutable_callsite_sync_all(vm, args)
    # invokeExact/invoke are signature polymorphic: bytecode call sites are
    # intercepted by the interpreter, while reflective Method.invoke throws.
    case 461: Fail{"java/lang/UnsupportedOperationException"}
    case 427: callsite_init(vm, args, 2, True{})
    case 428: lookup_class(vm, args)
    case 429: lookup_modes(vm, args)
    case 432: bind_to(vm, args)
    case 433: find_special(vm, args)
    case 434: find_constructor(vm, args)
    case 435: lookup_field_handle(vm, args, 1, False{})
    case 436: lookup_field_handle(vm, args, 3, False{})
    case 437: lookup_field_handle(vm, args, 2, True{})
    case 438: lookup_field_handle(vm, args, 4, True{})
    case _: Fail{"java/lang/UnsupportedOperationException"}

# --- Private Lookup constructors and unreflect* (plan 03, C5) ---

# Java 8's private Lookup(Class, int) and Lookup(Class) constructors, reached
# reflectively by frameworks to run interface default methods.
@unsafe def lookup_init(+vm: M.VM, +args: +List<M.Slot>, +full: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver_ref : U32 <- receiver(args)
    +class_slot : M.Slot <- arg(args, 1)
    +checked : Unit <- S.check(U32.is_ne(bits(class_slot), 0), "java/lang/NullPointerException")
    +mirror : M.HeapEntry <- H.get(S.heap(vm), bits(class_slot))
    +mirror_ok : Unit <- S.check(U32.is_eq(L.entry_kind(mirror), 8), "java/lang/IllegalArgumentException")
    +modes : U32 <- lookup_init_modes(full, args)
    +result : O.Outcome <- L.void_out(H.put(vm, receiver_ref, lookup_entry(class_id(vm, "java/lang/invoke/MethodHandles$Lookup"), L.entry_element(mirror), U32.and(modes, 15))))
    return result

@unsafe def lookup_init_modes(full: Bool, +args: +List<M.Slot>) -> Result<&2, &2, String, U32>:
  match full:
    case True{}: Done{15}
    case False{}:
      do Result<&2, &2, String, U32>:
        +modes : M.Slot <- arg(args, 2)
        return bits(modes)

@unsafe def handle_with_varargs(+entry: M.HeapEntry, +flags: U32) -> M.HeapEntry:
  +fields : +List<M.Binding> = H.binding_set(L.entry_fields(entry), 4294967295, M.Slot{1, Bool.pick(U32, U32.is_ne(U32.and(flags, 128), 0), 1, 0)})
  M.HeapEntry{H.entry_class(entry), L.entry_kind(entry), L.entry_element(entry), fields, L.entry_values(entry), L.entry_chars(entry)}

@unsafe def accessible_member(+vm: M.VM, +member_ref: U32) -> Result<&2, &2, String, Bool>:
  do Result<&2, &2, String, Bool>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), member_ref)
    return L.accessible_override(entry)

# unreflect(Method): an accessible Method uses the trusted lookup (no checks and
# no receiver restriction); privates bind exactly (invokespecial on their class).
@unsafe def unreflect(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +lookup_ref : U32 <- receiver(args)
    +method_slot : M.Slot <- arg(args, 1)
    +checked : Unit <- S.check(U32.is_ne(bits(method_slot), 0), "java/lang/NullPointerException")
    +method : M.LoadedMethod <- L.reflect_method_member(vm, [method_slot])
    +trusted : Bool <- accessible_member(vm, bits(method_slot))
    +state : LookupState <- lookup_state(vm, lookup_ref)
    +lookup_class : U32 = lookup_state_class(state)
    +modes : U32 = lookup_state_modes(state)
    +flags : U32 = M.loaded_method_flags(method)
    +defc : U32 = M.loaded_method_owner(method)
    +name : String = Sy.text(S.symbols(vm), M.loaded_method_name(method))
    +desc : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
    +is_interface : Bool = U32.is_ne(U32.and(L.class_flags_from_metadata(S.metadata(vm), defc), 512), 0)
    +private : Bool = mode_has(flags, 2)
    +kind : U32 = Bool.pick(U32, mode_has(flags, 8), 6, Bool.pick(U32, private, 7, Bool.pick(U32, is_interface, 9, 5)))
    +allowed : Unit <- method_access_check(trusted || lookup_access_allowed(vm, kind, defc, defc, flags, lookup_class, modes), vm, defc, defc, flags, lookup_class, modes, name, desc, kind)
    +restricted : Bool = Bool.not(trusted) && U32.is_eq(kind, 5) && restrict_receiver(vm, flags, defc, lookup_class)
    +special : U32 = Bool.pick(U32, private, defc, Bool.pick(U32, restricted, lookup_class, 4294967295))
    +entry : M.HeapEntry = handle_entry(class_id(vm, "java/lang/invoke/MethodHandle"), kind, defc, M.loaded_method_name(method), M.loaded_method_descriptor(method), special)
    +result : O.Outcome <- alloc_ref(H.allocate(vm, handle_with_varargs(entry, flags)))
    return result

# unreflectSpecial(Method, specialCaller): needs private access as the special
# caller; the receiver type becomes the special caller (Java 8 rules).
@unsafe def unreflect_special(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +lookup_ref : U32 <- receiver(args)
    +method_slot : M.Slot <- arg(args, 1)
    +caller_slot : M.Slot <- arg(args, 2)
    +checked : Unit <- S.check(U32.is_ne(bits(method_slot), 0) && U32.is_ne(bits(caller_slot), 0), "java/lang/NullPointerException")
    +caller_entry : M.HeapEntry <- H.get(S.heap(vm), bits(caller_slot))
    +special_caller : U32 = L.entry_element(caller_entry)
    +method : M.LoadedMethod <- L.reflect_method_member(vm, [method_slot])
    +state : LookupState <- lookup_state(vm, lookup_ref)
    +lookup_class : U32 = lookup_state_class(state)
    +modes : U32 = lookup_state_modes(state)
    +private_ok : Unit <- lookup_fail(mode_has(modes, 2) && U32.is_eq(special_caller, lookup_class), "java/lang/IllegalAccessException: no private access for invokespecial: " ++ L.class_to_string_text(vm, special_caller))
    +flags : U32 = M.loaded_method_flags(method)
    +defc : U32 = M.loaded_method_owner(method)
    +name : String = Sy.text(S.symbols(vm), M.loaded_method_name(method))
    +desc : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
    +static_ok : Unit <- lookup_fail(Bool.not(mode_has(flags, 8)), "java/lang/IllegalAccessException: expected a non-static method: " ++ method_member_text(vm, defc, name, desc, 6))
    +allowed : Unit <- method_access_check(lookup_access_allowed(vm, 7, defc, defc, flags, special_caller, modes), vm, defc, defc, flags, special_caller, modes, name, desc, 7)
    +entry : M.HeapEntry = handle_entry(class_id(vm, "java/lang/invoke/MethodHandle"), 7, defc, M.loaded_method_name(method), M.loaded_method_descriptor(method), special_caller)
    +result : O.Outcome <- alloc_ref(H.allocate(vm, handle_with_varargs(entry, flags)))
    return result

@unsafe def unreflect_constructor(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +lookup_ref : U32 <- receiver(args)
    +constructor_slot : M.Slot <- arg(args, 1)
    +checked : Unit <- S.check(U32.is_ne(bits(constructor_slot), 0), "java/lang/NullPointerException")
    +method : M.LoadedMethod <- L.reflect_constructor_member(vm, [constructor_slot])
    +trusted : Bool <- accessible_member(vm, bits(constructor_slot))
    +state : LookupState <- lookup_state(vm, lookup_ref)
    +lookup_class : U32 = lookup_state_class(state)
    +modes : U32 = lookup_state_modes(state)
    +flags : U32 = M.loaded_method_flags(method)
    +owner : U32 = M.loaded_method_owner(method)
    +desc : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
    +allowed : Unit <- method_access_check(trusted || lookup_access_allowed(vm, 8, owner, owner, flags, lookup_class, modes), vm, owner, owner, flags, lookup_class, modes, "<init>", desc, 7)
    +entry : M.HeapEntry = handle_entry(class_id(vm, "java/lang/invoke/MethodHandle"), 8, owner, M.loaded_method_name(method), M.loaded_method_descriptor(method), 4294967295)
    +result : O.Outcome <- alloc_ref(H.allocate(vm, handle_with_varargs(entry, flags)))
    return result

@unsafe def unreflect_field(+vm: M.VM, +args: +List<M.Slot>, +setter: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +lookup_ref : U32 <- receiver(args)
    +field_slot : M.Slot <- arg(args, 1)
    +checked : Unit <- S.check(U32.is_ne(bits(field_slot), 0), "java/lang/NullPointerException")
    +field : M.LoadedField <- L.reflect_field_member(vm, [field_slot])
    +trusted : Bool <- accessible_member(vm, bits(field_slot))
    +state : LookupState <- lookup_state(vm, lookup_ref)
    +lookup_class : U32 = lookup_state_class(state)
    +modes : U32 = lookup_state_modes(state)
    +flags : U32 = M.loaded_field_flags(field)
    +defc : U32 = M.loaded_field_owner(field)
    +static : Bool = mode_has(flags, 8)
    +kind : U32 = Bool.pick(U32, setter, Bool.pick(U32, static, 4, 3), Bool.pick(U32, static, 2, 1))
    +name : String = Sy.text(S.symbols(vm), M.loaded_field_name(field))
    +desc : String = Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))
    +final_ok : Unit <- lookup_fail(trusted || Bool.not(setter && mode_has(flags, 16)), "java/lang/IllegalAccessException: unexpected set of a final field: " ++ field_member_text(vm, defc, name, desc, kind))
    +allowed : Unit <- field_access_check(trusted || lookup_access_allowed(vm, kind, defc, defc, flags, lookup_class, modes), vm, defc, defc, flags, lookup_class, modes, name, desc, kind)
    +restricted : Bool = Bool.not(trusted) && Bool.not(static) && restrict_receiver(vm, flags, defc, lookup_class)
    +handle : M.HeapEntry = handle_entry(class_id(vm, "java/lang/invoke/MethodHandle"), kind, defc, M.loaded_field_name(field), M.loaded_field_descriptor(field), Bool.pick(U32, restricted, lookup_class, 4294967295))
    +result : O.Outcome <- alloc_ref(H.allocate(vm, handle))
    return result
