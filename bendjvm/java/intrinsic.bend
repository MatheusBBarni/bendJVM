import Base
import ../model.bend as M
import ../runtime/value.bend as V
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ./outcome.bend as O
import ./library.bend as L



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

def string_entry(+entry: M.HeapEntry) -> Result<&2, &2, String, String>:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  do Result<&2, &2, String, String>:
    checked : Unit <- S.check(U32.is_eq(kind, 3), "InvalidState: println(String) requires String")
    return utf16(chars, 0)

def string_value(heap: +List<M.HeapEntry>, +reference: U32, null: Bool) -> Result<&2, &2, String, String>:
  match null:
    case True{}:
      Done{"null"}
    case False{}:
      do Result<&2, &2, String, String>:
        +entry : M.HeapEntry <- H.get(heap, reference)
        string_entry(entry)

def float_decimal(+text: String) -> String:
  Bool.pick(String, Bool.or(String.contains(text, "."), Bool.or(String.contains(text, "e"), String.contains(text, "E"))), text, text ++ ".0")

def float_special(+bits: U32, special: Bool) -> String:
  match special:
    case False{}:
      float_decimal(F32.show(V.from_bits(bits)))
    case True{}:
      Bool.pick(String, U32.is_ne(U32.and(bits, 8388607), 0), "NaN", Bool.pick(String, V.negative(bits), "-Infinity", "Infinity"))

def float_show(+bits: U32) -> String:
  float_special(bits, U32.is_eq(U32.and(bits, 2139095040), 2139095040))

def argument(args: +List<M.Slot>, tag: U32) -> Result<&2, &2, String, U32>:
  match args:
    case Con{receiver, Con{M.Slot{actual, bits}, Nil{}}}:
      do Result<&2, &2, String, U32>:
        checked : Unit <- S.check(U32.is_eq(actual, tag), "InvalidState: intrinsic argument tag")
        return bits
    case _:
      Fail{"InvalidState: intrinsic argument count"}

def static_argument(args: +List<M.Slot>, tag: U32) -> Result<&2, &2, String, U32>:
  match args:
    case Con{M.Slot{actual, bits}, Nil{}}:
      do Result<&2, &2, String, U32>:
        checked : Unit <- S.check(U32.is_eq(actual, tag), "InvalidState: intrinsic argument tag")
        return bits
    case _:
      Fail{"InvalidState: intrinsic argument count"}

def string_intrinsic(+heap: +List<M.HeapEntry>, +bits: U32) -> Result<&2, &2, String, Maybe<&2, String>>:
  do Result<&2, &2, String, Maybe<&2, String>>:
    +text : String <- string_value(heap, bits, U32.is_eq(bits, 0))
    return Some{text}

def execute(id: U32, +heap: +List<M.HeapEntry>, +args: +List<M.Slot>) -> Result<&2, &2, String, Maybe<&2, String>>:
  match id:
    case 1:
      Done{None{}}
    case 2:
      do Result<&2, &2, String, Maybe<&2, String>>:
        bits : U32 <- argument(args, 1)
        return Some{V.int_show(bits)}
    case 3:
      do Result<&2, &2, String, Maybe<&2, String>>:
        bits : U32 <- argument(args, 3)
        result : Maybe<&2, String> <- string_intrinsic(heap, bits)
        return result
    case 4:
      Done{Some{""}}
    case 5:
      do Result<&2, &2, String, Maybe<&2, String>>:
        bits : U32 <- argument(args, 2)
        return Some{float_show(bits)}
    case 6:
      do Result<&2, &2, String, Maybe<&2, String>>:
        bits : U32 <- argument(args, 1)
        return Some{Bool.pick(String, U32.is_eq(bits, 0), "false", "true")}
    case _:
      Fail{"MissingMethod: unknown intrinsic"}

def resource_match(resource: M.Resource, +name: String) -> Bool:
  M.Resource{resource_name, bytes} = resource
  String.eq(resource_name, name)

def resource_find(resources: +List<M.Resource>, +name: String) -> Maybe<&2, M.Resource>:
  match resources:
    case Nil{}: None{}
    case Con{+resource, rest}:
      Bool.pick(Maybe<&2, M.Resource>, resource_match(resource, name), Some{resource}, resource_find(rest, name))

def class_id_find(classes: +List<M.LoadedClass>, +symbols: +List<String>, +name: String) -> U32:
  match classes:
    case Nil{}: 0
    case Con{+class, rest}:
      Bool.pick(U32, String.eq(Sy.text(symbols, M.loaded_class_name(class)), name), M.loaded_class_id(class), class_id_find(rest, symbols, name))

def receiver(args: +List<M.Slot>) -> Result<&2, &2, String, U32>:
  match args:
    case Con{M.Slot{tag, bits}, rest}:
      do Result<&2, &2, String, U32>:
        checked : Unit <- S.check(U32.is_eq(tag, 3), "InvalidState: intrinsic receiver tag")
        return bits
    case _:
      Fail{"InvalidState: intrinsic argument count"}

def open_resource_allocation(+vm: M.VM, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{allocation_value}:
      match allocation_value:
        case H.Allocation{updated, reference}:
          Done{O.Returned{updated, Some{M.Slot{3, reference}}}}

def open_resource_found(+vm: M.VM, found: Maybe<&2, M.Resource>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}:
      Done{O.Returned{vm, Some{M.Slot{3, 0}}}}
    case Some{resource}:
      match resource:
        case M.Resource{resource_name, +bytes}:
          open_resource_allocation(vm, H.allocate(vm, H.stream_entry(class_id_find(S.classes(vm), S.symbols(vm), "java/io/InputStream"), bytes)))

def open_resource(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +bits : U32 <- static_argument(args, 3)
    +name : String <- string_value(S.heap(vm), bits, U32.is_eq(bits, 0))
    result : O.Outcome <- open_resource_found(vm, resource_find(S.resources(vm), name))
    return result

def stream_read_byte(+vm: M.VM, +reference: U32, class: U32, +position: U32, fields: +List<M.Binding>, +values: +List<M.Slot>, chars: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, position), "InvalidState: stream position")
    updated : M.HeapEntry = M.HeapEntry{class, 4, U32.add(position, 1), fields, values, chars}
    return O.Returned{H.put(vm, reference, updated), Some{value}}

def stream_eof(+vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  Done{O.Returned{vm, Some{M.Slot{1, 4294967295}}}}

def stream_read_state(+vm: M.VM, +reference: U32, class: U32, +position: U32, fields: +List<M.Binding>, +values: +List<M.Slot>, chars: +List<U32>, closed: Bool) -> Result<&2, &2, String, O.Outcome>:
  match closed:
    case True{}:
      stream_eof(vm)
    case False{}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_ge(position, M.length(M.Slot, values)), stream_eof(vm), stream_read_byte(vm, reference, class, position, fields, values, chars))

def class_text(+vm: M.VM, id: U32) -> String:
  Sy.text(S.symbols(vm), L.loaded_class_name_at(id, S.classes(vm)))



def path_text(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, String>:
  string_value(S.heap(vm), reference, U32.is_eq(reference, 0))

def resolve_path(+vm: M.VM, +path: String) -> String:
  Bool.pick(String, String.starts_with(path, "/"), path, S.host_cwd_of(S.host(vm)) ++ "/" ++ path)

def cap_files(+vm: M.VM) -> Bool:
  U32.is_ne(U32.and(S.host_caps_of(S.host(vm)), 1), 0)

def cap_net(+vm: M.VM) -> Bool:
  U32.is_ne(U32.and(S.host_caps_of(S.host(vm)), 2), 0)

def suspend_effect(+vm: M.VM, +effect: M.Effect) -> Result<&2, &2, String, O.Outcome>:
  Done{O.Suspend{S.with_status(S.with_effect(vm, effect), 5), effect}}


def file_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +path : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(path), 0), "java/lang/NullPointerException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, path}], Nil{}, Nil{}}
    result : O.Outcome <- L.void_out(H.put(vm, L.bits_of(recv), updated))
    return result

def file_path_ref(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    result : O.Outcome <- L.ref_out(vm, L.field_bits(L.entry_fields(entry), 0))
    return result

def file_stat(+vm: M.VM, +args: +List<M.Slot>, op: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(cap_files(vm), "java/io/IOException")
    +recv : M.Slot <- L.slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    +path_ref : U32 = L.field_bits(L.entry_fields(entry), 0)
    path : String <- path_text(vm, path_ref)
    out : O.Outcome <- suspend_effect(vm, M.StatPath{resolve_path(vm, path), op})
    return out

def fis_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(cap_files(vm), "java/io/IOException")
    +recv : M.Slot <- L.slot0(args)
    +path : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(path), 0), "java/lang/NullPointerException")
    +text : String <- path_text(vm, L.bits_of(path))
    out : O.Outcome <- suspend_effect(vm, M.OpenFile{resolve_path(vm, text), 0, L.bits_of(recv)})
    return out

def fos_init(+vm: M.VM, +args: +List<M.Slot>, append: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(cap_files(vm), "java/io/IOException")
    +recv : M.Slot <- L.slot0(args)
    +path : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(path), 0), "java/lang/NullPointerException")
    +text : String <- path_text(vm, L.bits_of(path))
    out : O.Outcome <- suspend_effect(vm, M.OpenFile{resolve_path(vm, text), Bool.pick(U32, U32.is_eq(append, 0), 1, 2), L.bits_of(recv)})
    return out

def fos_init_append(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +flag : M.Slot <- L.slot2(args)
    result : O.Outcome <- fos_init(vm, args, L.bits_of(flag))
    return result

def host_handle(+entry: M.HeapEntry) -> U32:
  L.field_bits(L.entry_fields(entry), 1)

def host_closed(+entry: M.HeapEntry) -> Bool:
  U32.is_ne(L.field_bits(L.entry_fields(entry), 0), 0)

def host_read_ref(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    closed : Unit <- S.check(Bool.not(host_closed(entry)), "java/io/IOException")
    out : O.Outcome <- suspend_effect(vm, M.ReadBytes{host_handle(entry), 1, L.field_bits(L.entry_fields(entry), 2)})
    return out

def host_read(+vm: M.VM, +reference: U32, +entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  host_read_ref(vm, reference)

def stream_read_kind(+vm: M.VM, +reference: U32, +class: U32, +position: U32, +fields: +List<M.Binding>, +values: +List<M.Slot>, +chars: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  +name = class_text(vm, class)
  Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name, "java/io/ByteArrayInputStream"), stream_read_state(vm, reference, class, position, fields, values, chars, False{}),
    Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name, "java/io/InputStream"), stream_read_state(vm, reference, class, position, fields, values, chars, H.stream_closed(fields)),
      host_read_ref(vm, reference)))

def stream_read_entry(+vm: M.VM, +reference: U32, +entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  match entry:
    case M.HeapEntry{class, 4, position, +fields, +values, chars}:
      stream_read_kind(vm, reference, class, position, fields, values, chars)
    case M.HeapEntry{class, kind, element, fields, values, chars}:
      host_read(vm, reference, entry)

def read_stream(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +reference : U32 <- receiver(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    result : O.Outcome <- stream_read_entry(vm, reference, entry)
    return result


def host_close_state(closed: Bool, +vm: M.VM, +reference: U32, +entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  match closed:
    case True{}: Done{O.Returned{vm, None{}}}
    case False{}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, values, chars}:
          suspend_effect(H.put(vm, reference, M.HeapEntry{class, kind, element, H.binding_set(fields, 0, M.Slot{1, 1}), values, chars}), M.CloseHandle{host_handle(entry)})

def host_close(+vm: M.VM, +reference: U32, +entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  host_close_state(host_closed(entry), vm, reference, entry)

def close_memory(+vm: M.VM, +reference: U32, +entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  match entry:
    case M.HeapEntry{class, 4, position, +fields, values, chars}:
      +name = class_text(vm, class)
      Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name, "java/io/ByteArrayInputStream") || String.eq(name, "java/io/ByteArrayOutputStream"), Done{O.Returned{vm, None{}}},
        Done{O.Returned{H.put(vm, reference, M.HeapEntry{class, 4, position, H.binding_set(fields, 0, M.Slot{1, 1}), values, chars}), None{}}})
    case _:
      host_close(vm, reference, entry)

def close_owned(+vm: M.VM, +inner: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +owned : M.HeapEntry <- H.get(S.heap(vm), inner)
    result : O.Outcome <- close_memory(vm, inner, owned)
    return result

def close_wrapper_open(+vm: M.VM, +reference: U32, class: U32, kind: U32, element: U32, fields: +List<M.Binding>, values: +List<M.Slot>, chars: +List<U32>, +inner: U32) -> Result<&2, &2, String, O.Outcome>:
  match inner:
    case 0: L.void_out(H.put(vm, reference, M.HeapEntry{class, kind, element, H.binding_set(fields, 1, M.Slot{1, 1}), values, chars}))
    case owned:
      close_owned(H.put(vm, reference, M.HeapEntry{class, kind, element, H.binding_set(fields, 1, M.Slot{1, 1}), values, chars}), owned)

def close_wrapper_state(+vm: M.VM, +reference: U32, class: U32, kind: U32, element: U32, fields: +List<M.Binding>, values: +List<M.Slot>, chars: +List<U32>, +closed: U32, +inner: U32) -> Result<&2, &2, String, O.Outcome>:
  match closed:
    case 0: close_wrapper_open(vm, reference, class, kind, element, fields, values, chars, inner)
    case _: L.void_out(vm)

def close_wrapper(+vm: M.VM, +reference: U32, +entry: M.HeapEntry) -> Result<&2, &2, String, O.Outcome>:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}:
      close_wrapper_state(vm, reference, class, kind, element, fields, values, chars, L.field_bits(fields, 1), L.field_bits(fields, 0))

def wrapper_flag(+name: String) -> U32:
  Bool.pick(U32, String.eq(name, "java/io/BufferedReader"), 1,
    Bool.pick(U32, String.eq(name, "java/io/InputStreamReader"), 1,
      Bool.pick(U32, String.eq(name, "java/io/OutputStreamWriter"), 1, 0)))

def close_by_flag(+vm: M.VM, +reference: U32, +entry: M.HeapEntry, flag: U32) -> Result<&2, &2, String, O.Outcome>:
  match flag:
    case 1: close_wrapper(vm, reference, entry)
    case _: close_memory(vm, reference, entry)

def close_named(+vm: M.VM, +reference: U32, +entry: M.HeapEntry, +name: String) -> Result<&2, &2, String, O.Outcome>:
  close_by_flag(vm, reference, entry, wrapper_flag(name))

def close_stream(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +reference : U32 <- receiver(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    result : O.Outcome <- close_named(vm, reference, entry, class_text(vm, H.entry_class(entry)))
    return result


def host_write(+vm: M.VM, +reference: U32, bytes: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    closed : Unit <- S.check(Bool.not(host_closed(entry)), "java/io/IOException")
    out : O.Outcome <- suspend_effect(vm, M.WriteBytes{host_handle(entry), bytes})
    return out

def write_memory_named(+vm: M.VM, +reference: U32, +entry: M.HeapEntry, +byte: U32, name: String) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name, "java/io/ByteArrayOutputStream"),
    L.void_out(H.put(vm, reference, M.HeapEntry{H.entry_class(entry), 4, 0, L.entry_fields(entry), M.append(M.Slot, L.entry_values(entry), [M.Slot{1, U32.and(byte, 255)}]), Nil{}})),
    host_write(vm, reference, [U32.and(byte, 255)]))

def write_memory(+vm: M.VM, +reference: U32, +byte: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    +name : String = class_text(vm, H.entry_class(entry))
    result : O.Outcome <- write_memory_named(vm, reference, entry, byte, name)
    return result

def write_int(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +value : M.Slot <- L.slot1(args)
    result : O.Outcome <- write_memory(vm, L.bits_of(recv), L.bits_of(value))
    return result

def slots_to_bytes(xs: +List<M.Slot>, n: Nat) -> +List<U32>:
  match xs n:
    case _ 0n: Nil{}
    case Nil{} _: Nil{}
    case Con{M.Slot{tag, bits}, rest} 1n+p: Con{U32.and(bits, 255), slots_to_bytes(rest, p)}

@unsafe def append_bytes(values: +List<M.Slot>, bytes: +List<U32>) -> +List<M.Slot>:
  match bytes:
    case Nil{}: values
    case Con{b, rest}: append_bytes(M.append(M.Slot, values, [M.Slot{1, b}]), rest)

def write_memory_bytes_named(+vm: M.VM, +reference: U32, +entry: M.HeapEntry, +bytes: +List<U32>, name: String) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, String.eq(name, "java/io/ByteArrayOutputStream"),
    L.void_out(H.put(vm, reference, M.HeapEntry{H.entry_class(entry), 4, 0, L.entry_fields(entry), append_bytes(L.entry_values(entry), bytes), Nil{}})),
    host_write(vm, reference, bytes))

def write_memory_bytes(+vm: M.VM, +reference: U32, bytes: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    +name : String = class_text(vm, H.entry_class(entry))
    result : O.Outcome <- write_memory_bytes_named(vm, reference, entry, bytes, name)
    return result

def write_bulk_len(+vm: M.VM, +reference: U32, values: +List<M.Slot>, off: U32, len: U32, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: L.void_out(vm)
    case False{}:
      write_memory_bytes(vm, reference, slots_to_bytes(H.drop_slots(values, U32.to_nat(off)), U32.to_nat(len)))

def write_bulk(+vm: M.VM, +reference: U32, +values: +List<M.Slot>, +off: U32, +len: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    checked : Unit <- S.check(Bool.not(V.negative(off)) && Bool.not(V.negative(len)) && U32.is_le(U32.add(off, len), M.length(M.Slot, values)), "java/lang/IndexOutOfBoundsException")
    empty : Unit <- S.check(U32.is_ne(len, 0) || True{}, "java/lang/IndexOutOfBoundsException")
    result : O.Outcome <- write_bulk_len(vm, reference, values, off, len, U32.is_eq(len, 0))
    return result

def write_bytes(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +array : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(array), 0), "java/lang/NullPointerException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(array))
    result : O.Outcome <- write_bulk(vm, L.bits_of(recv), L.entry_values(entry), 0, M.length(M.Slot, L.entry_values(entry)))
    return result

def write_bytes_off(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +array : M.Slot <- L.slot1(args)
    +off : M.Slot <- L.slot2(args)
    +len : M.Slot <- L.slot3(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(array), 0), "java/lang/NullPointerException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(array))
    result : O.Outcome <- write_bulk(vm, L.bits_of(recv), L.entry_values(entry), L.bits_of(off), L.bits_of(len))
    return result

def flush_stream(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.void_out(vm)

def read_bulk_one(+vm: M.VM, +reference: U32, array: U32, off: U32, len: U32, got: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    result : O.Outcome <- stream_read_entry(vm, reference, entry)
    return result

def read_bulk_loop(+vm: M.VM, +reference: U32, +array: U32, +off: U32, +len: U32, +got: U32) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(got, len), L.int_out(vm, got), read_bulk_one(vm, reference, array, off, len, got))

def read_bulk_empty(+vm: M.VM, +reference: U32, array: U32, off: U32, len: U32, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: L.int_out(vm, 0)
    case False{}: read_bulk_loop(vm, reference, array, off, len, 0)

def read_bulk_off(+vm: M.VM, +reference: U32, +array: U32, +off: U32, +len: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +dest : M.HeapEntry <- H.get(S.heap(vm), array)
    checked : Unit <- S.check(Bool.not(V.negative(off)) && Bool.not(V.negative(len)) && U32.is_le(U32.add(off, len), M.length(M.Slot, L.entry_values(dest))), "java/lang/IndexOutOfBoundsException")
    result : O.Outcome <- read_bulk_empty(vm, reference, array, off, len, U32.is_eq(len, 0))
    return result

def read_bulk(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +array : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(array), 0), "java/lang/NullPointerException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(array))
    result : O.Outcome <- read_bulk_off(vm, L.bits_of(recv), L.bits_of(array), 0, M.length(M.Slot, L.entry_values(entry)))
    return result

def read_bulk_args(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +array : M.Slot <- L.slot1(args)
    +off : M.Slot <- L.slot2(args)
    +len : M.Slot <- L.slot3(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(array), 0), "java/lang/NullPointerException")
    result : O.Outcome <- read_bulk_off(vm, L.bits_of(recv), L.bits_of(array), L.bits_of(off), L.bits_of(len))
    return result

def inet_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +host : M.Slot <- L.slot1(args)
    +port : M.Slot <- L.slot2(args)
    checked : Unit <- S.check(U32.is_le(L.bits_of(port), 65535) && Bool.not(V.negative(L.bits_of(port))), "java/lang/IllegalArgumentException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, host}, M.Binding{1, port}], Nil{}, Nil{}}
    result : O.Outcome <- L.void_out(H.put(vm, L.bits_of(recv), updated))
    return result

def socket_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, M.Slot{1, 0}}, M.Binding{1, M.Slot{1, 0}}, M.Binding{2, M.Slot{1, 0}}], Nil{}, Nil{}}
    result : O.Outcome <- L.void_out(H.put(vm, L.bits_of(recv), updated))
    return result

def socket_connect_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(cap_net(vm), "java/io/IOException")
    +recv : M.Slot <- L.slot0(args)
    +host : M.Slot <- L.slot1(args)
    +port : M.Slot <- L.slot2(args)
    +text : String <- path_text(vm, L.bits_of(host))
    out : O.Outcome <- suspend_effect(vm, M.ConnectTcp{text, L.bits_of(port), 0, L.bits_of(recv)})
    return out

def socket_connect(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(cap_net(vm), "java/io/IOException")
    +recv : M.Slot <- L.slot0(args)
    addr : M.Slot <- L.slot1(args)
    timeout : M.Slot <- L.slot2(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(addr))
    host_ref : U32 = L.field_bits(L.entry_fields(entry), 0)
    port : U32 = L.field_bits(L.entry_fields(entry), 1)
    +text : String <- path_text(vm, host_ref)
    out : O.Outcome <- suspend_effect(vm, M.ConnectTcp{text, port, L.bits_of(timeout), L.bits_of(recv)})
    return out

def socket_wrap(+vm: M.VM, +args: +List<M.Slot>, name: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +sock : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    result : O.Outcome <- L.alloc_result(H.allocate(vm, M.HeapEntry{L.class_id(vm, name), 0, 0, [M.Binding{0, M.Slot{1, 0}}, M.Binding{1, M.Slot{1, host_handle(sock)}}, M.Binding{2, M.Slot{1, L.field_bits(L.entry_fields(sock), 2)}}], Nil{}, Nil{}}), vm2 => reference => L.ref_out(vm2, reference))
    return result

def socket_get_in(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  socket_wrap(vm, args, "java/io/SocketInputStream")

def socket_get_out(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  socket_wrap(vm, args, "java/io/SocketOutputStream")

def socket_timeout(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +value : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(Bool.not(V.negative(L.bits_of(value))), "java/lang/IllegalArgumentException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, H.binding_set(L.entry_fields(entry), 2, value), Nil{}, Nil{}}
    result : O.Outcome <- L.void_out(H.put(vm, L.bits_of(recv), updated))
    return result

def socket_close(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    result : O.Outcome <- host_close(vm, L.bits_of(recv), entry)
    return result

def server_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(cap_net(vm), "java/io/IOException")
    +recv : M.Slot <- L.slot0(args)
    +port : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(U32.is_le(L.bits_of(port), 65535) && Bool.not(V.negative(L.bits_of(port))), "java/lang/IllegalArgumentException")
    out : O.Outcome <- suspend_effect(vm, M.BindTcp{L.bits_of(port), L.bits_of(recv)})
    return out

def server_port(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    result : O.Outcome <- L.int_out(vm, L.field_bits(L.entry_fields(entry), 2))
    return result

def server_accept(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(cap_net(vm), "java/io/IOException")
    +recv : M.Slot <- L.slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    out : O.Outcome <- suspend_effect(vm, M.AcceptTcp{host_handle(entry), L.field_bits(L.entry_fields(entry), 2), L.bits_of(recv)})
    return out

def charset_ok(+name: String) -> Bool:
  String.eq(String.to_upper(name), "UTF-8") || String.eq(String.to_upper(name), "UTF8")

def reader_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +stream : M.Slot <- L.slot1(args)
    +cs : M.Slot <- L.slot2(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(stream), 0) && U32.is_ne(L.bits_of(cs), 0), "java/lang/NullPointerException")
    +name : String <- path_text(vm, L.bits_of(cs))
    supported : Unit <- S.check(charset_ok(name), "java/io/UnsupportedEncodingException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, stream}, M.Binding{1, M.Slot{1, 0}}], Nil{}, Nil{}}
    result : O.Outcome <- L.void_out(H.put(vm, L.bits_of(recv), updated))
    return result

def writer_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  reader_init(vm, args)

def buffered_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +inner : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(inner), 0), "java/lang/NullPointerException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, [M.Binding{0, inner}, M.Binding{1, M.Slot{1, 0}}], Nil{}, Nil{}}
    result : O.Outcome <- L.void_out(H.put(vm, L.bits_of(recv), updated))
    return result

def reader_read(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    +stream : U32 = L.field_bits(L.entry_fields(entry), 0)
    +inner : M.HeapEntry <- H.get(S.heap(vm), stream)
    result : O.Outcome <- stream_read_entry(vm, stream, inner)
    return result

def writer_write_int(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +value : M.Slot <- L.slot1(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    +stream : U32 = L.field_bits(L.entry_fields(entry), 0)
    result : O.Outcome <- write_memory(vm, stream, L.bits_of(value))
    return result

def utf8_char(+c: U32, +rest: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_le(c, 127), Con{c, rest},
    Bool.pick(+List<U32>, U32.is_le(c, 2047), Con{U32.or(192, U32.shrn(c, 6n)), Con{U32.or(128, U32.and(c, 63)), rest}},
      Con{U32.or(224, U32.shrn(c, 12n)), Con{U32.or(128, U32.and(U32.shrn(c, 6n), 63)), Con{U32.or(128, U32.and(c, 63)), rest}}}))

def utf8_encode(chars: +List<U32>) -> +List<U32>:
  match chars:
    case Nil{}: Nil{}
    case Con{c, rest}: utf8_char(c, utf8_encode(rest))

def writer_write_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +text : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(text), 0), "java/lang/NullPointerException")
    chars : +List<U32> <- L.string_chars(vm, L.bits_of(text))
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    +stream : U32 = L.field_bits(L.entry_fields(entry), 0)
    result : O.Outcome <- write_memory_bytes(vm, stream, utf8_encode(chars))
    return result

def get_force_found(result: Result<&2, &2, String, M.HeapEntry>) -> M.HeapEntry:
  match result:
    case Done{entry}: entry
    case Fail{error}: M.HeapEntry{0, 0, 0, Nil{}, Nil{}, Nil{}}

def get_force(heap: +List<M.HeapEntry>, +reference: U32) -> M.HeapEntry:
  get_force_found(H.get(heap, reference))

def writer_write_chars(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +array : M.Slot <- L.slot1(args)
    +off : M.Slot <- L.slot2(args)
    +len : M.Slot <- L.slot3(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(array), 0), "java/lang/NullPointerException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(array))
    result : O.Outcome <- write_bulk(vm, L.field_bits(L.entry_fields(get_force(S.heap(vm), L.bits_of(recv))), 0), L.entry_values(entry), L.bits_of(off), L.bits_of(len))
    return result

def reader_read_chars(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_bulk_args(vm, args)

def acc_empty(acc: +List<U32>) -> Bool:
  match acc:
    case Nil{}: True{}
    case Con{h, t}: False{}

@unsafe def read_line_walk(fuel: Nat, mode: U32, +vm: M.VM, +stream: U32, +acc: +List<U32>, one: O.Outcome) -> Result<&2, &2, String, O.Outcome>:
  match fuel:
    case 0n: L.ref_out(vm, 0)
    case 1n+p:
      match mode:
        case 0:
          do Result<&2, &2, String, O.Outcome>:
            +inner : M.HeapEntry <- H.get(S.heap(vm), stream)
            next : O.Outcome <- stream_read_entry(vm, stream, inner)
            result : O.Outcome <- read_line_walk(p, 1, vm, stream, acc, next)
            return result
        case _:
          match one:
            case O.Returned{+next_vm, Some{M.Slot{tag, +bits}}}:
              Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(bits, 10) || U32.is_eq(bits, 13), L.intern_or_alloc(next_vm, M.reverse(U32, acc)),
                Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(bits, 4294967295),
                  Bool.pick(Result<&2, &2, String, O.Outcome>, acc_empty(acc), L.ref_out(next_vm, 0), L.intern_or_alloc(next_vm, M.reverse(U32, acc))),
                  read_line_walk(p, 0, next_vm, stream, Con{bits, acc}, one)))
            case O.Returned{+next_vm, None{}}:
              Bool.pick(Result<&2, &2, String, O.Outcome>, acc_empty(acc), L.ref_out(next_vm, 0), L.intern_or_alloc(next_vm, M.reverse(U32, acc)))
            case other: Done{other}

def read_line(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(recv))
    +reader : U32 = L.field_bits(L.entry_fields(entry), 0)
    +reader_entry : M.HeapEntry <- H.get(S.heap(vm), reader)
    +stream : U32 = L.field_bits(L.entry_fields(reader_entry), 0)
    result : O.Outcome <- read_line_walk(256n, 0, vm, stream, Nil{}, O.Returned{vm, None{}})
    return result

def println_emit(+vm: M.VM, output: Maybe<&2, String>) -> Result<&2, &2, String, O.Outcome>:
  match output:
    case None{}: L.void_out(vm)
    case Some{text}: L.void_out(S.emit(vm, text))

def println_out(+vm: M.VM, +args: +List<M.Slot>, id: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    output : Maybe<&2, String> <- execute(id, S.heap(vm), args)
    result : O.Outcome <- println_emit(vm, output)
    return result

def execute_vm(id: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 1: L.object_init(vm, args)
    case 2: println_out(vm, args, 2)
    case 3: println_out(vm, args, 3)
    case 4: println_out(vm, args, 4)
    case 5: println_out(vm, args, 5)
    case 6: println_out(vm, args, 6)
    case 9: open_resource(vm, args)
    case 10: read_stream(vm, args)
    case 11: close_stream(vm, args)
    case 12: L.object_equals(vm, args)
    case 13: L.object_hash(vm, args)
    case 14: L.object_to_string(vm, args)
    case 15: L.require_non_null(vm, args)
    case 16: L.objects_equals(vm, args)
    case 17: L.string_length(vm, args)
    case 18: L.string_empty(vm, args)
    case 19: L.string_char_at(vm, args)
    case 20: L.string_equals(vm, args)
    case 21: L.string_hashcode(vm, args)
    case 22: L.string_substring1(vm, args)
    case 23: L.string_substring2(vm, args)
    case 24: L.string_concat(vm, args)
    case 25: L.string_to_string(vm, args)
    case 26: L.string_value_of_int(vm, args)
    case 27: L.string_value_of_bool(vm, args)
    case 28: L.string_value_of_object(vm, args)
    case 29: L.builder_init(vm, args)
    case 30: L.builder_init_string(vm, args)
    case 31: L.builder_append_string(vm, args)
    case 32: L.builder_append_object(vm, args)
    case 33: L.builder_append_int(vm, args)
    case 34: L.builder_append_char(vm, args)
    case 35: L.builder_append_bool(vm, args)
    case 36: L.builder_length(vm, args)
    case 37: L.builder_to_string(vm, args)
    case 38: L.integer_value_of(vm, args)
    case 39: L.integer_int_value(vm, args)
    case 40: L.integer_parse(vm, args)
    case 41: L.integer_equals(vm, args)
    case 42: L.integer_hashcode(vm, args)
    case 43: L.integer_to_string(vm, args)
    case 44: L.math_abs(vm, args)
    case 45: L.math_min(vm, args)
    case 46: L.math_max(vm, args)
    case 47: L.arraycopy(vm, args)
    case 48: L.list_init(vm, args)
    case 49: L.list_init_cap(vm, args)
    case 50: L.coll_size(vm, args)
    case 51: L.coll_empty(vm, args)
    case 52: L.list_add(vm, args)
    case 53: L.list_add_at(vm, args)
    case 54: L.list_get(vm, args)
    case 55: L.list_set(vm, args)
    case 56: L.list_remove(vm, args)
    case 57: L.list_contains(vm, args)
    case 58: L.list_clear(vm, args)
    case 59: L.list_iterator(vm, args)
    case 60: L.itr_has_next(vm, args)
    case 61: L.itr_next(vm, args)
    case 62: L.itr_remove(vm, args)
    case 63: L.map_init(vm, args)
    case 64: L.map_put(vm, args)
    case 65: L.map_get(vm, args)
    case 66: L.map_contains(vm, args)
    case 67: L.map_remove(vm, args)
    case 68: L.bais_init(vm, args)
    case 69: L.baos_init(vm, args)
    case 70: L.baos_to_array(vm, args)
    case 71: L.baos_size(vm, args)
    case 72: L.baos_reset(vm, args)
    case 73: read_bulk(vm, args)
    case 74: read_bulk_args(vm, args)
    case 75: write_int(vm, args)
    case 76: write_bytes(vm, args)
    case 77: write_bytes_off(vm, args)
    case 78: flush_stream(vm, args)
    case 79: file_init(vm, args)
    case 80: file_stat(vm, args, 0)
    case 81: file_stat(vm, args, 1)
    case 82: file_stat(vm, args, 2)
    case 83: file_path_ref(vm, args)
    case 84: fis_init(vm, args)
    case 85: fos_init(vm, args, 0)
    case 86: fos_init_append(vm, args)
    case 87: reader_read(vm, args)
    case 88: reader_read_chars(vm, args)
    case 89: writer_write_int(vm, args)
    case 90: writer_write_string(vm, args)
    case 91: writer_write_chars(vm, args)
    case 92: reader_init(vm, args)
    case 93: writer_init(vm, args)
    case 94: buffered_init(vm, args)
    case 95: read_line(vm, args)
    case 96: inet_init(vm, args)
    case 97: socket_init(vm, args)
    case 98: socket_connect_init(vm, args)
    case 99: socket_connect(vm, args)
    case 100: socket_get_in(vm, args)
    case 101: socket_get_out(vm, args)
    case 102: socket_timeout(vm, args)
    case 103: socket_close(vm, args)
    case 104: server_init(vm, args)
    case 105: server_port(vm, args)
    case 106: server_accept(vm, args)
    case 107: socket_timeout(vm, args)
    case 108: socket_close(vm, args)
    case 109: L.throwable_get_message(vm, args)
    case 110: L.throwable_get_cause(vm, args)
    case 111: L.throwable_init_cause(vm, args)
    case 112: L.throwable_add_suppressed(vm, args)
    case 113: L.throwable_get_suppressed(vm, args)
    case 114: L.throwable_to_string(vm, args)
    case 211: L.throwable_init0(vm, args)
    case 212: L.throwable_init_s(vm, args)
    case 213: L.throwable_init_t(vm, args)
    case 214: L.throwable_init_st(vm, args)
    case _: Fail{"MissingMethod: unknown intrinsic"}

def continue_java(+vm: M.VM, cont: M.Cont, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  L.continue_java(vm, cont, value)
