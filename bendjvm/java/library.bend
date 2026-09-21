import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../runtime/value.bend as V
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ./outcome.bend as O

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

def throwable_init_t(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +cause : M.Slot <- slot1(args)
    result : O.Outcome <- throwable_init(vm, args, 0, bits_of(cause), 1)
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

def continue_java(+vm: M.VM, cont: M.Cont, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match cont:
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
