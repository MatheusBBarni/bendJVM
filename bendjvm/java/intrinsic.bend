import Base
import ../model.bend as M
import ../runtime/value.bend as V
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ./outcome.bend as O
import ./library.bend as L
import ../runtime/wide.bend as W
import ../runtime/binary64.bend as B64
import ./invoke.bend as I
import ./strings.bend as Str
import ./files.bend as Fs
import ./loaders.bend as Ld
import ./serial.bend as Se
import ./threads.bend as Tj
import ./hostio.bend as Hio
import ./natives.bend as Nb
import ./charsets.bend as Cs
import ./stacktrace.bend as St




def string_entry(+entry: M.HeapEntry) -> Result<&2, &2, String, String>:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  do Result<&2, &2, String, String>:
    checked : Unit <- S.check(U32.is_eq(kind, 3), "InvalidState: println(String) requires String")
    return L.utf16(chars, 0)

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

def long_show(+args: +List<M.Slot>) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    value : M.Slot <- L.slot1(args)
    +words : W.Words <- L.wide_words(value, 4)
    return W.long_show(words)
def double_show(+args: +List<M.Slot>) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    value : M.Slot <- L.slot1(args)
    +words : W.Words <- L.wide_words(value, 5)
    text : String <- B64.double_to_string(words)
    return text


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
    case 7:
      do Result<&2, &2, String, Maybe<&2, String>>:
        bits : U32 <- argument(args, 1)
        return Some{Char.show(Chr{bits})}
    case 281:
      do Result<&2, &2, String, Maybe<&2, String>>:
        text : String <- long_show(args)
        return Some{text}
    case 282:
      do Result<&2, &2, String, Maybe<&2, String>>:
        text : String <- double_show(args)
        return Some{text}
    case 6:
      do Result<&2, &2, String, Maybe<&2, String>>:
        bits : U32 <- argument(args, 1)
        return Some{Bool.pick(String, U32.is_eq(bits, 0), "false", "true")}
    case _:
      Fail{"MissingMethod: unknown intrinsic"}

def resource_match(resource: M.Resource, +name: String) -> Bool:
  M.Resource{resource_name, origin} = resource
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


def open_resource_found(+vm: M.VM, found: Maybe<&2, M.Resource>) -> Result<&2, &2, String, O.Outcome>:
  L.resource_stream_found(vm, found)

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
    return O.Returned{H.put(vm, reference, updated), Some{M.Slot{1, U32.and(M.slot_bits(value), 255)}}}

def stream_eof(+vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  Done{O.Returned{vm, Some{M.Slot{1, 4294967295}}}}

def stream_read_state(+vm: M.VM, +reference: U32, class: U32, +position: U32, fields: +List<M.Binding>, +values: +List<M.Slot>, chars: +List<U32>, closed: Bool) -> Result<&2, &2, String, O.Outcome>:
  match closed:
    case True{}: Fail{"java/io/IOException"}
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

def slots_to_bytes_list(xs: +List<M.Slot>) -> +List<U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{slot, rest}: Con{U32.and(M.slot_bits(slot), 255), slots_to_bytes_list(rest)}

def slots_to_bytes(xs: +List<M.Slot>, n: Nat) -> +List<U32>:
  slots_to_bytes_list(M.take(M.Slot, xs, n))

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

# InputStream.read(byte[], int, int): ByteArrayInputStream and resource streams
# copy in place; any other stream is read through read(), one byte at a time,
# as the JDK's InputStream default does.
@unsafe def read_bulk_empty(+vm: M.VM, +reference: U32, +array: U32, +off: U32, +len: U32, empty: Bool) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: L.int_out(vm, 0)
    case False{}: read_bulk_source(in_place_stream(vm, reference), vm, reference, array, off, len)

def in_place_entry(+vm: M.VM, found: Result<&2, &2, String, M.HeapEntry>) -> Bool:
  match found:
    case Fail{error}: False{}
    case Done{+entry}:
      +name : String = class_text(vm, H.entry_class(entry))
      U32.is_eq(L.entry_kind(entry), 4) && (String.eq(name, "java/io/ByteArrayInputStream") || String.eq(name, "java/io/InputStream"))

def in_place_stream(+vm: M.VM, +reference: U32) -> Bool:
  in_place_entry(vm, H.get(S.heap(vm), reference))

def signed_byte_slots(+slots: +List<M.Slot>) -> +List<M.Slot>:
  match slots:
    case Nil{}: Nil{}
    case Con{+slot, rest}:
      +b : U32 = U32.and(M.slot_bits(slot), 255)
      Con{M.Slot{1, Bool.pick(U32, U32.is_ge(b, 128), U32.or(b, 4294967040), b)}, signed_byte_slots(rest)}

@unsafe def read_bulk_source(in_place: Bool, +vm: M.VM, +reference: U32, +array: U32, +off: U32, +len: U32) -> Result<&2, &2, String, O.Outcome>:
  match in_place:
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        +class : U32 = H.entry_class(entry)
        open : Unit <- S.check(Bool.not(String.eq(class_text(vm, class), "java/io/InputStream") && H.stream_closed(L.entry_fields(entry))), "java/io/IOException")
        +position : U32 = L.entry_element(entry)
        +values : +List<M.Slot> = L.entry_values(entry)
        +total : U32 = M.length(M.Slot, values)
        +remaining : U32 = Bool.pick(U32, U32.is_ge(position, total), 0, U32.sub(total, position))
        +count : U32 = Bool.pick(U32, U32.is_lt(remaining, len), remaining, len)
        +dest : M.HeapEntry <- H.get(S.heap(vm), array)
        +target : +List<M.Slot> = L.entry_values(dest)
        +copied : +List<M.Slot> = M.append(M.Slot, M.take(M.Slot, target, U32.to_nat(off)), M.append(M.Slot, signed_byte_slots(M.take(M.Slot, M.drop(M.Slot, values, U32.to_nat(position)), U32.to_nat(count))), M.drop(M.Slot, target, U32.to_nat(U32.add(off, count)))))
        +stored : M.VM = H.put(vm, array, M.HeapEntry{H.entry_class(dest), L.entry_kind(dest), L.entry_element(dest), L.entry_fields(dest), copied, L.entry_chars(dest)})
        +moved : M.VM = H.put(stored, reference, M.HeapEntry{class, 4, U32.add(position, count), L.entry_fields(entry), values, L.entry_chars(entry)})
        result : O.Outcome <- L.int_out(Bool.pick(M.VM, U32.is_eq(count, 0), vm, moved), Bool.pick(U32, U32.is_eq(count, 0), 4294967295, count))
        return result
    case False{}: read_bulk_next(vm, reference, array, off, len, 0)

def read_bulk_next(+vm: M.VM, +reference: U32, +array: U32, +off: U32, +len: U32, +got: U32) -> Result<&2, &2, String, O.Outcome>:
  L.call_virtual(L.push_cont(vm, M.NeedBulkRead{reference, array, off, len, got}), L.virtual_on(vm, reference, "read", "()I"), [M.Slot{3, reference}])

# read() returned `value`: store it, or stop at the end of the stream.
@unsafe def continue_bulk_read(+vm: M.VM, +reference: U32, +array: U32, +off: U32, +len: U32, +got: U32, +value: U32) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case 4294967295: L.int_out(vm, Bool.pick(U32, U32.is_eq(got, 0), 4294967295, got))
    case +b:
      do Result<&2, &2, String, O.Outcome>:
        +dest : M.HeapEntry <- H.get(S.heap(vm), array)
        +index : U32 = U32.add(off, got)
        +target : +List<M.Slot> = L.entry_values(dest)
        +stored : +List<M.Slot> = M.append(M.Slot, M.take(M.Slot, target, U32.to_nat(index)), M.append(M.Slot, signed_byte_slots([M.Slot{1, b}]), M.drop(M.Slot, target, U32.to_nat(U32.add(index, 1)))))
        +updated : M.VM = H.put(vm, array, M.HeapEntry{H.entry_class(dest), L.entry_kind(dest), L.entry_element(dest), L.entry_fields(dest), stored, L.entry_chars(dest)})
        +count : U32 = U32.add(got, 1)
        result : O.Outcome <- read_bulk_more(U32.is_eq(count, len), updated, reference, array, off, len, count)
        return result

def read_bulk_more(done: Bool, +vm: M.VM, +reference: U32, +array: U32, +off: U32, +len: U32, +got: U32) -> Result<&2, &2, String, O.Outcome>:
  match done:
    case True{}: L.int_out(vm, got)
    case False{}: read_bulk_next(vm, reference, array, off, len, got)

def read_bulk_off(+vm: M.VM, +reference: U32, +array: U32, +off: U32, +len: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +dest : M.HeapEntry <- H.get(S.heap(vm), array)
    checked : Unit <- S.check(Bool.not(V.negative(off)) && Bool.not(V.negative(len)) && U32.is_le(U32.add(off, len), M.length(M.Slot, L.entry_values(dest))), "java/lang/IndexOutOfBoundsException")
    result : O.Outcome <- read_bulk_empty(vm, reference, array, off, len, U32.is_eq(len, 0))
    return result

@unsafe def read_bulk(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +array : M.Slot <- L.slot1(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(array), 0), "java/lang/NullPointerException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), L.bits_of(array))
    +length : U32 = M.length(M.Slot, L.entry_values(entry))
    +stream : U32 = L.bits_of(recv)
    result : O.Outcome <- read_bulk_dispatch(L.virtual_on(vm, stream, "read", "([BII)I"), vm, stream, L.bits_of(array), length)
    return result

# InputStream.read(byte[]) is read(b, 0, b.length), which a subclass may override.
def read_bulk_dispatch(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +array: U32, +length: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{+method}: Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(M.loaded_method_owner(method), L.class_id(vm, "java/io/InputStream")), read_bulk_off(vm, stream, array, 0, length), L.call_virtual(vm, Some{method}, [M.Slot{3, stream}, M.Slot{3, array}, M.Slot{1, 0}, M.Slot{1, length}]))
    case None{}: read_bulk_off(vm, stream, array, 0, length)

def read_bulk_args(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +recv : M.Slot <- L.slot0(args)
    +array : M.Slot <- L.slot1(args)
    +off : M.Slot <- L.slot2(args)
    +len : M.Slot <- L.slot3(args)
    checked : Unit <- S.check(U32.is_ne(L.bits_of(array), 0), "java/lang/NullPointerException")
    result : O.Outcome <- read_bulk_off(vm, L.bits_of(recv), L.bits_of(array), L.bits_of(off), L.bits_of(len))
    return result

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
              Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(bits, 10) || U32.is_eq(bits, 13), L.string_out(next_vm, M.reverse(U32, acc)),
                Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(bits, 4294967295),
                  Bool.pick(Result<&2, &2, String, O.Outcome>, acc_empty(acc), L.ref_out(next_vm, 0), L.string_out(next_vm, M.reverse(U32, acc))),
                  read_line_walk(p, 0, next_vm, stream, Con{bits, acc}, one)))
            case O.Returned{+next_vm, None{}}:
              Bool.pick(Result<&2, &2, String, O.Outcome>, acc_empty(acc), L.ref_out(next_vm, 0), L.string_out(next_vm, M.reverse(U32, acc)))
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

# PrintStream receivers: System.err (heap reference 15) writes standard error.
def to_err(args: +List<M.Slot>) -> Bool:
  match args:
    case Con{M.Slot{3, reference}, rest}: U32.is_eq(reference, L.err_stream())
    case _: False{}

def println_emit(+vm: M.VM, output: Maybe<&2, String>, err: Bool) -> Result<&2, &2, String, O.Outcome>:
  match output:
    case None{}: L.void_out(vm)
    case Some{text}: L.void_out(L.emit_text_err(err, vm, True{}, text))

def println_out(+vm: M.VM, +args: +List<M.Slot>, id: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    output : Maybe<&2, String> <- execute(id, S.heap(vm), args)
    result : O.Outcome <- println_emit(vm, output, to_err(args))
    return result


def print_emit(+vm: M.VM, output: Maybe<&2, String>, err: Bool) -> Result<&2, &2, String, O.Outcome>:
  match output:
    case None{}: L.void_out(vm)
    case Some{text}: L.void_out(L.emit_text_err(err, vm, False{}, text))

def print_out(+vm: M.VM, +args: +List<M.Slot>, id: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    output : Maybe<&2, String> <- execute(id, S.heap(vm), args)
    result : O.Outcome <- print_emit(vm, output, to_err(args))
    return result

def print_object(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    reference : U32 <- argument(args, 3)
    result : O.Outcome <- L.print_object_to(vm, reference, False{}, to_err(args))
    return result

def println_object(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    reference : U32 <- argument(args, 3)
    result : O.Outcome <- L.print_object_to(vm, reference, True{}, to_err(args))
    return result


def native_or_missing(native: Bool, +id: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match native:
    case True{}: Nb.call(id, vm, args)
    case False{}: Fail{"MissingMethod: unknown intrinsic"}

def execute_ready(+id: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 1: L.object_init(vm, args)
    case 2: println_out(vm, args, 2)
    case 3: println_out(vm, args, 3)
    case 4: println_out(vm, args, 4)
    case 5: println_out(vm, args, 5)
    case 6: println_out(vm, args, 6)
    case 281: println_out(vm, args, 281)
    case 282: println_out(vm, args, 282)
    case 318: println_object(vm, args)
    case 543: print_out(vm, args, 2)
    case 544: print_out(vm, args, 3)
    case 545: print_out(vm, args, 5)
    case 546: print_out(vm, args, 6)
    case 547: print_out(vm, args, 7)
    case 548: print_out(vm, args, 281)
    case 549: print_out(vm, args, 282)
    case 550: print_object(vm, args)
    case 551: Fail{"java/lang/UnsatisfiedLinkError"}
    case 800: Tj.execute(800, vm, args)
    case 801: Tj.execute(801, vm, args)
    case 802: Tj.execute(802, vm, args)
    case 803: Tj.execute(803, vm, args)
    case 804: Tj.execute(804, vm, args)
    case 805: Tj.execute(805, vm, args)
    case 806: Tj.execute(806, vm, args)
    case 807: Tj.execute(807, vm, args)
    case 808: Tj.execute(808, vm, args)
    case 809: Tj.execute(809, vm, args)
    case 810: Tj.execute(810, vm, args)
    case 811: Tj.execute(811, vm, args)
    case 812: Tj.execute(812, vm, args)
    case 813: Tj.execute(813, vm, args)
    case 814: Tj.execute(814, vm, args)
    case 815: Tj.execute(815, vm, args)
    case 816: Tj.execute(816, vm, args)
    case 817: Tj.execute(817, vm, args)
    case 818: St.print_stack_trace(vm, args, False{})
    case 829: St.frames(vm, args)
    case 830: Tj.execute(830, vm, args)
    case 820: Hio.call(vm, args)
    case 821: Nb.load(vm, args, True{})
    case 823: Cs.execute(823, vm, args)
    case 824: Cs.execute(824, vm, args)
    case 825: Cs.execute(825, vm, args)
    case 826: Cs.execute(826, vm, args)
    case 827: Cs.execute(827, vm, args)
    case 828: Cs.execute(828, vm, args)
    case 831: L.string_intern(vm, args)
    case 822: Nb.load(vm, args, False{})
    case 819: St.print_stack_trace(vm, args, True{})
    case 552: L.security_manager(vm, args)
    case 553: L.do_privileged(vm, args)
    case 554: L.do_privileged_exception(vm, args)
    case 555: L.access_control_context(vm, args)
    case 556: L.privileged_exception_init(vm, args)
    case 557: L.class_to_string(vm, args)
    case 594: L.enum_compare(vm, args)
    case 595: L.enum_declaring_class(vm, args)
    case 658: Ld.loader_init(vm, args, False{})
    case 659: Ld.loader_init(vm, args, True{})
    case 660: Ld.loader_get_parent(vm, args)
    case 661: Ld.loader_load_two(vm, args)
    case 662: Ld.loader_find_loaded(vm, args)
    case 663: Ld.loader_find_class(vm, args)
    case 664: Ld.define_class(vm, args, True{})
    case 665: Ld.define_class(vm, args, False{})
    case 666: Ld.loader_resolve_class(vm, args)
    case 667: Ld.loader_find_system(vm, args)
    case 668: Ld.loader_parallel(vm, args)
    case 669: Ld.loader_lock(vm, args)
    case 670: Ld.loader_find_resource(vm, args)
    case 671: L.array_clone(vm, args)
    case 672: L.annotated_component(vm, args)
    case 673: L.annotated_wildcard(vm, args, True{})
    case 674: L.annotated_wildcard(vm, args, False{})
    case 675: L.annotated_variable_bounds(vm, args)
    case 676: L.type_variable_annotated_bounds(vm, args)
    case 677: L.variable_annotations(vm, args)
    case 678: L.variable_annotation(vm, args)
    case 679: L.variable_annotation_present(vm, args)
    case 680: L.list_to_string(vm, args)
    case 681: Se.execute(681, vm, args)
    case 682: Se.execute(682, vm, args)
    case 683: Se.execute(683, vm, args)
    case 684: Se.execute(684, vm, args)
    case 685: Se.execute(685, vm, args)
    case 686: Se.execute(686, vm, args)
    case 687: Se.execute(687, vm, args)
    case 688: Se.execute(688, vm, args)
    case 689: Se.execute(689, vm, args)
    case 690: Se.execute(690, vm, args)
    case 691: Se.execute(691, vm, args)
    case 692: Se.execute(692, vm, args)
    case 693: Se.execute(693, vm, args)
    case 694: Se.execute(694, vm, args)
    case 695: Se.execute(695, vm, args)
    case 696: Se.execute(696, vm, args)
    case 697: Se.execute(697, vm, args)
    case 698: Se.execute(698, vm, args)
    case 699: Se.execute(699, vm, args)
    case 700: Se.execute(700, vm, args)
    case 701: Se.execute(701, vm, args)
    case 702: Se.execute(702, vm, args)
    case 703: Se.execute(703, vm, args)
    case 704: Se.execute(704, vm, args)
    case 705: Se.execute(705, vm, args)
    case 706: Se.execute(706, vm, args)
    case 707: Se.execute(707, vm, args)
    case 708: Se.execute(708, vm, args)
    case 709: Se.execute(709, vm, args)
    case 710: Se.execute(710, vm, args)
    case 711: Se.execute(711, vm, args)
    case 712: Se.execute(712, vm, args)
    case 713: Se.execute(713, vm, args)
    case 714: Se.execute(714, vm, args)
    case 715: Se.execute(715, vm, args)
    case 716: Se.execute(716, vm, args)
    case 717: Se.execute(717, vm, args)
    case 718: Se.execute(718, vm, args)
    case 719: Se.execute(719, vm, args)
    case 720: Se.execute(720, vm, args)
    case 721: Se.execute(721, vm, args)
    case 722: Se.execute(722, vm, args)
    case 723: Se.execute(723, vm, args)
    case 726: Se.execute(726, vm, args)
    case 727: Se.execute(727, vm, args)
    case 728: Se.execute(728, vm, args)
    case 729: Se.execute(729, vm, args)
    case 730: Se.execute(730, vm, args)
    case 731: Se.execute(731, vm, args)
    case 732: Se.execute(732, vm, args)
    case 733: Se.execute(733, vm, args)
    case 734: Se.execute(734, vm, args)
    case 735: Se.execute(735, vm, args)
    case 736: Se.execute(736, vm, args)
    case 737: Se.execute(737, vm, args)
    case 738: Se.execute(738, vm, args)
    case 739: Se.execute(739, vm, args)
    case 740: Se.execute(740, vm, args)
    case 741: Se.execute(741, vm, args)
    case 742: Se.execute(742, vm, args)
    case 743: Se.execute(743, vm, args)
    case 744: Se.execute(744, vm, args)
    case 745: Se.execute(745, vm, args)
    case 746: Se.execute(746, vm, args)
    case 747: Se.execute(747, vm, args)
    case 748: Se.execute(748, vm, args)
    case 749: Se.execute(749, vm, args)
    case 750: Se.execute(750, vm, args)
    case 751: Se.execute(751, vm, args)
    case 752: Se.execute(752, vm, args)
    case 753: Se.execute(753, vm, args)
    case 754: Se.execute(754, vm, args)
    case 755: Se.execute(755, vm, args)
    case 756: Se.execute(756, vm, args)
    case 757: Se.execute(757, vm, args)
    case 758: Se.execute(758, vm, args)
    case 759: Se.execute(759, vm, args)
    case 760: Se.execute(760, vm, args)
    case 761: Se.execute(761, vm, args)
    case 762: Se.execute(762, vm, args)
    case 763: Se.execute(763, vm, args)
    case 764: Se.execute(764, vm, args)
    case 765: Se.execute(765, vm, args)
    case 766: Se.execute(766, vm, args)
    case 767: Se.execute(767, vm, args)
    case 768: Se.execute(768, vm, args)
    case 769: Se.execute(769, vm, args)
    case 770: Se.execute(770, vm, args)
    case 771: Se.execute(771, vm, args)
    case 772: Se.execute(772, vm, args)
    case 773: Se.execute(773, vm, args)
    case 774: Se.execute(774, vm, args)
    case 775: Se.execute(775, vm, args)
    case 776: Se.execute(776, vm, args)
    case 777: Se.execute(777, vm, args)
    case 778: Se.execute(778, vm, args)
    case 779: Se.execute(779, vm, args)
    case 780: Se.execute(780, vm, args)
    case 781: Se.execute(781, vm, args)
    case 782: Se.execute(782, vm, args)
    case 783: Se.execute(783, vm, args)
    case 784: Se.execute(784, vm, args)
    case 785: Se.execute(785, vm, args)
    case 786: Se.execute(786, vm, args)
    case 787: Se.execute(787, vm, args)
    case 788: Se.execute(788, vm, args)
    case 654: Str.integer_radix(vm, args, 4n, 15)
    case 655: Str.integer_radix(vm, args, 3n, 7)
    case 656: Str.integer_radix(vm, args, 1n, 1)
    case 657: Str.integer_static_text(vm, args)
    case 596: Fs.file_init_parent_text(vm, args)
    case 597: Fs.file_init_parent_file(vm, args)
    case 598: Fs.file_init_uri(vm, args)
    case 599: Fs.file_get_name(vm, args)
    case 600: Fs.file_get_parent(vm, args)
    case 601: Fs.file_get_parent_file(vm, args)
    case 602: Fs.file_get_absolute_path(vm, args)
    case 603: Fs.file_get_absolute_file(vm, args)
    case 604: Fs.file_is_absolute(vm, args)
    case 605: Fs.file_list(vm, args, True{})
    case 606: Fs.file_list(vm, args, False{})
    case 607: Fs.file_equals(vm, args)
    case 608: Fs.file_hash(vm, args)
    case 609: Fs.uri_init(vm, args)
    case 610: Fs.uri_get(vm, args, 0)
    case 611: Fs.uri_get(vm, args, 1)
    case 612: Fs.uri_get(vm, args, 2)
    case 613: Fs.uri_get(vm, args, 3)
    case 614: Fs.uri_get(vm, args, 4)
    case 615: Fs.uri_get(vm, args, 5)
    case 616: Fs.uri_get(vm, args, 6)
    case 617: Fs.uri_get(vm, args, 7)
    case 618: Fs.uri_flag(vm, args, True{})
    case 619: Fs.uri_flag(vm, args, False{})
    case 620: Fs.uri_equals(vm, args)
    case 621: Fs.uri_hash(vm, args)
    case 622: Fs.uri_to_url(vm, args)
    case 623: Fs.url_init(vm, args)
    case 624: Fs.url_init_context(vm, args)
    case 625: Fs.url_get(vm, args, 3)
    case 626: Fs.url_get(vm, args, 4)
    case 627: Fs.url_get(vm, args, 5)
    case 628: Fs.url_get(vm, args, 6)
    case 629: Fs.url_port(vm, args)
    case 630: Fs.url_equals(vm, args)
    case 631: Fs.url_hash(vm, args)
    case 632: Fs.url_to_uri(vm, args)
    case 633: Fs.url_open_connection(vm, args)
    case 634: Fs.connection_input(vm, args)
    case 635: Fs.connection_get_url(vm, args)
    case 636: Fs.connection_set_caches(vm, args)
    case 637: Fs.connection_get_caches(vm, args)
    case 638: Fs.connection_connect(vm, args)
    case 639: Fs.jar_file_url(vm, args)
    case 640: Fs.jar_entry_name(vm, args)
    case 641: Fs.jar_get_file(vm, args)
    case 642: Fs.jar_get_entry(vm, args)
    case 643: Fs.zip_init(vm, args, False{})
    case 644: Fs.zip_init(vm, args, True{})
    case 645: Fs.zip_get_entry(vm, args)
    case 646: Fs.zip_entries(vm, args)
    case 647: Fs.zip_size(vm, args)
    case 648: Fs.zip_input(vm, args)
    case 649: Fs.zip_close(vm, args)
    case 650: Fs.zip_name(vm, args)
    case 651: Fs.entry_get_name(vm, args)
    case 652: Fs.entry_is_directory(vm, args)
    case 653: Fs.entry_hash(vm, args)
    case 558: L.class_new_instance(vm, args)
    case 559: Str.string_index_of_char(vm, args)
    case 560: Str.string_index_of_char_from(vm, args)
    case 561: Str.string_index_of(vm, args)
    case 562: Str.string_index_of_from(vm, args)
    case 563: Str.string_last_index_of_char(vm, args)
    case 564: Str.string_last_index_of_char_from(vm, args)
    case 565: Str.string_last_index_of(vm, args)
    case 566: Str.string_last_index_of_from(vm, args)
    case 567: Str.string_starts_with(vm, args)
    case 568: Str.string_starts_with_from(vm, args)
    case 569: Str.string_ends_with(vm, args)
    case 570: Str.string_trim(vm, args)
    case 571: Str.string_replace_char(vm, args)
    case 572: Str.string_replace(vm, args)
    case 573: Str.string_equals_ignore_case(vm, args)
    case 574: Str.string_to_upper(vm, args)
    case 575: Str.string_to_lower(vm, args)
    case 576: Str.string_to_char_array(vm, args)
    case 577: Str.string_value_of_char(vm, args)
    case 578: Str.string_value_of_chars(vm, args)
    case 579: Str.string_value_of_chars_range(vm, args)
    case 580: Str.string_init_empty(vm, args)
    case 581: Str.string_init_string(vm, args)
    case 582: Str.string_init_chars(vm, args)
    case 583: Str.string_init_chars_range(vm, args)

    case 9: open_resource(vm, args)
    case 10: read_stream(vm, args)
    case 11: close_stream(vm, args)
    case 12: L.object_equals(vm, args)
    case 13: L.object_hash(vm, args)
    case 14: L.object_to_string(vm, args)
    case 115: L.object_get_class(vm, args)
    case 116: L.class_name(vm, args)
    case 117: L.class_superclass(vm, args)
    case 118: L.class_get_modifiers(vm, args)
    case 119: L.class_is_primitive(vm, args)
    case 120: L.class_is_array(vm, args)
    case 121: L.class_is_interface(vm, args)
    case 122: L.class_assignable_from(vm, args)
    case 123: L.class_cast(vm, args)
    case 124: Ld.for_name(vm, args, False{})
    case 125: L.class_loader_system(vm, args)
    case 126: Ld.loader_load_one(vm, args)
    case 140: L.class_loader_resource(vm, args)
    case 141: Fs.url_open_stream(vm, args)
    case 142: Fs.url_get(vm, args, 2)
    case 143: L.properties_init(vm, args)
    case 144: L.properties_load(vm, args)
    case 209: L.properties_load_reader(vm, args)
    case 145: L.properties_get(vm, args)
    case 146: L.properties_set(vm, args)
    case 208: L.properties_get_default(vm, args)
    case 147: L.boolean_value_of(vm, args)
    case 148: L.boolean_value(vm, args)
    case 149: L.boolean_to_string(vm, args)
    case 150: L.enum_init(vm, args)
    case 151: L.enum_name(vm, args)
    case 152: L.enum_ordinal(vm, args)
    case 169: L.class_component(vm, args)
    case 170: println_out(vm, args, 7)
    case 171: L.class_resource_stream(vm, args)
    case 172: L.class_resource_url(vm, args)
    case 173: L.class_get_loader(vm, args)
    case 174: Ld.loader_resource_stream(vm, args)
    case 175: Ld.loader_get_resource(vm, args)
    case 176: Fs.url_get(vm, args, 1)
    case 177: Fs.url_get(vm, args, 0)
    case 178: Fs.url_get(vm, args, 0)
    case 153: L.enum_value_of(vm, args)
    case 154: L.class_is_annotation(vm, args)
    case 155: L.class_is_enum(vm, args)
    case 156: L.class_get_interfaces(vm, args)
    case 157: L.byte_value_of(vm, args)
    case 158: L.primitive_unbox(vm, args)
    case 159: L.primitive_to_string(vm, args)
    case 160: L.short_value_of(vm, args)
    case 161: L.primitive_unbox(vm, args)
    case 162: L.primitive_to_string(vm, args)
    case 163: L.character_value_of(vm, args)
    case 164: L.primitive_unbox(vm, args)
    case 165: L.primitive_to_string(vm, args)
    case 166: L.float_value_of(vm, args)
    case 167: L.float_unbox(vm, args)
    case 168: L.primitive_to_string(vm, args)
    case 275: L.wide_box(vm, args, "java/lang/Long", 4)
    case 276: L.wide_value(vm, args, 4)
    case 277: L.long_to_string(vm, args)
    case 278: L.wide_box(vm, args, "java/lang/Double", 5)
    case 279: L.wide_value(vm, args, 5)
    case 280: L.double_to_string(vm, args)
    case 319: L.long_equals(vm, args, 4)
    case 320: L.wide_hash_code(vm, args, 4)
    case 321: L.long_parse(vm, args)
    case 322: L.long_equals(vm, args, 5)
    case 323: L.wide_hash_code(vm, args, 5)
    case 329: L.string_value_of_wide(vm, args, 4)
    case 330: L.string_value_of_wide(vm, args, 5)
    case 331: L.builder_append_wide(vm, args, 4)
    case 332: L.builder_append_wide(vm, args, 5)
    case 326: L.double_raw_bits(vm, args)
    case 327: L.double_canonical_bits(vm, args)
    case 328: L.long_bits_to_double(vm, args)
    case 324: L.double_classify(vm, args, False{})
    case 325: L.double_classify(vm, args, True{})
    case 333: L.long_float_value(vm, args)
    case 334: L.double_int_value(vm, args)
    case 335: L.double_long_value(vm, args)
    case 336: L.double_float_value(vm, args)
    case 337: L.wide_low_value(vm, args, 4)
    case 338: L.long_double_value(vm, args)
    case 339: L.reflect_field_get_long(vm, args)
    case 340: L.reflect_field_set_long(vm, args)
    case 341: L.reflect_field_get_double(vm, args)
    case 342: L.reflect_field_set_double(vm, args)
    case 127: L.class_declared_fields(vm, args)
    case 128: L.class_declared_methods(vm, args)
    case 129: L.class_declared_constructors(vm, args)
    case 130: L.reflect_field_name(vm, args)
    case 131: L.reflect_field_modifiers(vm, args)
    case 132: L.reflect_field_type(vm, args)
    case 133: L.reflect_method_name(vm, args)
    case 134: L.reflect_method_modifiers(vm, args)
    case 135: L.reflect_method_return_type(vm, args)
    case 136: L.reflect_method_parameter_types(vm, args)
    case 288: L.reflect_method_is_default(vm, args)
    case 289: L.reflect_method_generic_return(vm, args)
    case 290: L.reflect_method_generic_parameter_types(vm, args)
    case 291: L.reflect_method_get_generic_exception_types(vm, args)
    case 294: L.parameterized_arguments(vm, args)
    case 295: L.parameterized_raw(vm, args)
    case 296: L.parameterized_owner(vm, args)
    case 297: L.type_variable_bounds_lazy(vm, args)
    case 298: L.type_variable_name(vm, args)
    case 299: L.wildcard_upper(vm, args)
    case 300: L.wildcard_lower(vm, args)
    case 301: L.generic_array_component(vm, args)
    case 292: L.reflect_annotated_type_get_owner(vm, args)
    case 293: L.annotated_actuals(vm, args)
    case 302: L.reflect_field_generic_type(vm, args)
    case 303: L.field_annotated(vm, args)
    case 304: L.class_generic_superclass(vm, args)
    case 310: L.standard_enum_values(vm, args, L.class_id(vm, "java/lang/annotation/RetentionPolicy"))
    case 311: L.standard_enum_value_of(vm, args, L.class_id(vm, "java/lang/annotation/RetentionPolicy"))
    case 312: L.standard_enum_values(vm, args, L.class_id(vm, "java/lang/annotation/ElementType"))
    case 313: L.standard_enum_value_of(vm, args, L.class_id(vm, "java/lang/annotation/ElementType"))
    case 314: L.annotation_exception_init(vm, args)
    case 315: L.annotation_exception_first(vm, args)
    case 316: L.annotation_exception_second(vm, args)
    case 137: L.reflect_constructor_name(vm, args)
    case 138: L.reflect_constructor_modifiers(vm, args)
    case 139: L.reflect_constructor_parameter_types(vm, args)
    case 179: L.reflect_field_get(vm, args)
    case 180: L.reflect_field_set(vm, args)
    case 181: L.reflect_field_get_int(vm, args)
    case 182: L.reflect_field_set_int(vm, args)
    case 183: L.reflect_method_invoke(vm, args)
    case 184: L.reflect_constructor_new_instance(vm, args)
    case 185: L.class_is_instance(vm, args)
    case 186: L.class_declared_field(vm, args)
    case 187: L.class_declared_method(vm, args)
    case 188: L.class_declared_constructor(vm, args)
    case 189: L.reflect_declaring_class(vm, args)
    case 190: L.reflect_declaring_class(vm, args)
    case 191: L.reflect_declaring_class(vm, args)
    case 192: L.accessible_set(vm, args)
    case 193: L.accessible_is(vm, args)
    case 194: L.class_public_fields(vm, args)
    case 195: L.class_public_methods(vm, args)
    case 196: L.class_public_constructors(vm, args)
    case 197: L.class_public_field(vm, args)
    case 198: L.class_public_method(vm, args)
    case 199: L.class_public_constructor(vm, args)
    case 202: L.class_loader_resources(vm, args)
    case 203: L.class_loader_instance_resources(vm, args)
    case 204: L.resource_enum_has_more(vm, args)
    case 205: L.resource_enum_next(vm, args)
    case 206: L.resource_enum_has_more(vm, args)
    case 207: L.resource_enum_next(vm, args)
    case 210: L.class_is_annotation_present(vm, args)
    case 215: L.class_get_annotation(vm, args)
    case 216: L.class_get_declared_annotation(vm, args)
    case 217: L.class_get_annotations(vm, args)
    case 218: L.class_get_declared_annotations(vm, args)
    case 219: L.reflect_field_is_annotation_present(vm, args)
    case 220: L.reflect_field_get_annotation(vm, args)
    case 221: L.reflect_field_get_annotation(vm, args)
    case 222: L.reflect_field_get_annotations(vm, args)
    case 223: L.reflect_field_get_annotations(vm, args)
    case 224: L.reflect_method_is_annotation_present(vm, args)
    case 225: L.reflect_method_get_annotation(vm, args)
    case 226: L.reflect_method_get_annotation(vm, args)
    case 227: L.reflect_method_get_annotations(vm, args)
    case 228: L.reflect_method_get_annotations(vm, args)
    case 229: L.reflect_method_get_parameter_annotations(vm, args)
    case 230: L.reflect_method_get_default_value(vm, args)
    case 231: L.reflect_method_is_annotation_present(vm, args)
    case 232: L.reflect_method_get_annotation(vm, args)
    case 233: L.reflect_method_get_annotation(vm, args)
    case 234: L.reflect_method_get_annotations(vm, args)
    case 235: L.reflect_method_get_annotations(vm, args)
    case 236: L.reflect_method_get_parameter_annotations(vm, args)
    case 237: L.method_annotated_parameters(vm, args)
    case 238: L.method_annotated_return(vm, args)
    case 239: L.reflect_annotated_type_is_annotation_present(vm, args)
    case 240: L.reflect_annotated_type_get_annotation(vm, args)
    case 241: L.reflect_annotated_type_get_annotation(vm, args)
    case 242: L.reflect_annotated_type_get_annotations(vm, args)
    case 243: L.reflect_annotated_type_get_annotations(vm, args)
    case 286: L.reflect_annotated_type_get_type(vm, args)
    case 287: L.type_get_type_name(vm, args)
    case 249: L.proxy_init(vm, args)
    case 245: L.proxy_new_instance(vm, args)
    case 246: L.proxy_get_proxy_class(vm, args)
    case 247: L.proxy_is_proxy_class(vm, args)
    case 248: L.proxy_get_invocation_handler(vm, args)
    case 265: L.class_get_annotations_by_type(vm, args)
    case 266: L.class_get_annotations_by_type(vm, args)
    case 267: L.reflect_field_get_annotations_by_type(vm, args)
    case 268: L.reflect_field_get_annotations_by_type(vm, args)
    case 269: L.reflect_method_get_annotations_by_type(vm, args)
    case 270: L.reflect_method_get_annotations_by_type(vm, args)
    case 271: L.reflect_constructor_get_annotations_by_type(vm, args)
    case 272: L.reflect_constructor_get_annotations_by_type(vm, args)
    case 250: Ld.for_name(vm, args, True{})
    case 251: L.reflect_field_is_synthetic(vm, args)
    case 252: L.reflect_field_is_enum_constant(vm, args)
    case 253: L.reflect_method_is_bridge(vm, args)
    case 254: L.reflect_method_is_synthetic(vm, args)
    case 255: L.reflect_method_is_varargs(vm, args)
    case 244: L.reflect_method_get_exception_types(vm, args)
    case 256: L.reflect_constructor_get_exception_types(vm, args)
    case 257: L.reflect_constructor_is_synthetic(vm, args)
    case 258: L.reflect_constructor_is_varargs(vm, args)
    case 259: L.reflect_field_equals(vm, args)
    case 260: L.reflect_field_hash(vm, args)
    case 261: L.reflect_method_equals(vm, args)
    case 262: L.reflect_method_hash(vm, args)
    case 263: L.reflect_constructor_equals(vm, args)
    case 264: L.reflect_constructor_hash(vm, args)
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
    case 462: L.string_contains(vm, args)
    case 463: L.assertion_error_init(vm, args)
    case 464: L.executable_parameters(vm, args)
    case 465: L.executable_parameter_count(vm, args)
    case 466: L.parameter_intrinsic(466, vm, args)
    case 467: L.parameter_intrinsic(467, vm, args)
    case 468: L.parameter_intrinsic(468, vm, args)
    case 469: L.parameter_intrinsic(469, vm, args)
    case 470: L.parameter_intrinsic(470, vm, args)
    case 471: L.parameter_intrinsic(471, vm, args)
    case 472: L.parameter_intrinsic(472, vm, args)
    case 473: L.parameter_intrinsic(473, vm, args)
    case 474: L.parameter_intrinsic(474, vm, args)
    case 475: L.parameter_intrinsic(475, vm, args)
    case 476: L.parameter_intrinsic(476, vm, args)
    case 477: L.parameter_intrinsic(477, vm, args)
    case 478: L.parameter_intrinsic(478, vm, args)
    case 479: L.parameter_intrinsic(479, vm, args)
    case 480: L.parameter_intrinsic(480, vm, args)
    case 481: L.parameter_intrinsic(481, vm, args)
    case 482: L.parameter_intrinsic(482, vm, args)
    case 483: L.parameter_intrinsic(483, vm, args)
    case 484: L.parameter_intrinsic(484, vm, args)
    case 485: L.comparable_compare(vm, args, 485)
    case 486: L.comparable_compare(vm, args, 486)
    case 487: L.comparable_compare(vm, args, 487)
    case 488: L.comparable_compare(vm, args, 488)
    case 489: L.comparable_compare(vm, args, 489)
    case 490: L.comparable_compare(vm, args, 490)
    case 491: L.comparable_compare(vm, args, 491)
    case 492: L.comparable_compare(vm, args, 492)
    case 493: L.comparable_compare(vm, args, 493)
    case 494: L.static_compare(vm, args, 494)
    case 495: L.static_compare(vm, args, 495)
    case 496: L.static_compare(vm, args, 496)
    case 497: L.static_compare(vm, args, 497)
    case 498: L.nested_class_intrinsic(498, vm, args)
    case 499: L.nested_class_intrinsic(499, vm, args)
    case 500: L.nested_class_intrinsic(500, vm, args)
    case 501: L.nested_class_intrinsic(501, vm, args)
    case 502: L.nested_class_intrinsic(502, vm, args)
    case 503: L.nested_class_intrinsic(503, vm, args)
    case 504: L.nested_class_intrinsic(504, vm, args)
    case 505: L.nested_class_intrinsic(505, vm, args)
    case 506: L.nested_class_intrinsic(506, vm, args)
    case 507: L.nested_class_intrinsic(507, vm, args)
    case 508: L.nested_class_intrinsic(508, vm, args)
    case 509: L.class_type_parameters(vm, args)
    case 510: L.executable_type_parameters(vm, args)
    case 511: L.executable_type_parameters(vm, args)
    case 512: L.class_generic_interfaces_out(vm, args)
    case 513: L.executable_to_generic_string(vm, args)
    case 514: L.executable_to_generic_string(vm, args)
    case 515: L.type_variable_declaration(vm, args)
    case 516: L.type_equals_intrinsic(vm, args)
    case 517: L.type_hash_intrinsic(vm, args)
    case 518: L.type_equals_intrinsic(vm, args)
    case 519: L.type_hash_intrinsic(vm, args)
    case 520: L.type_equals_intrinsic(vm, args)
    case 521: L.type_hash_intrinsic(vm, args)
    case 522: L.type_equals_intrinsic(vm, args)
    case 523: L.type_hash_intrinsic(vm, args)
    case 524: L.executable_generic_parameters(vm, args)
    case 525: L.executable_generic_exceptions(vm, args)
    case 526: L.executable_to_string(vm, args)
    case 527: L.executable_to_string(vm, args)
    case 528: L.field_to_string(vm, args)
    case 529: L.field_to_generic_string(vm, args)
    case 530: L.modifier_test(vm, args, 1)
    case 531: L.modifier_test(vm, args, 2)
    case 532: L.modifier_test(vm, args, 4)
    case 533: L.modifier_test(vm, args, 8)
    case 534: L.modifier_test(vm, args, 16)
    case 535: L.modifier_test(vm, args, 32)
    case 536: L.modifier_test(vm, args, 64)
    case 537: L.modifier_test(vm, args, 128)
    case 538: L.modifier_test(vm, args, 256)
    case 539: L.modifier_test(vm, args, 512)
    case 540: L.modifier_test(vm, args, 1024)
    case 541: L.modifier_test(vm, args, 2048)
    case 542: L.modifier_string(vm, args)
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
    case 725: L.integer_parse_radix(vm, args)
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
    case 79: Fs.file_init(vm, args)
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
    case 109: L.throwable_get_message(vm, args)
    case 110: L.throwable_get_cause(vm, args)
    case 111: L.throwable_init_cause(vm, args)
    case 112: L.throwable_add_suppressed(vm, args)
    case 113: L.throwable_get_suppressed(vm, args)
    case 114: L.throwable_to_string(vm, args)
    case 273: L.throwable_get_cause(vm, args)
    case 283: L.throwable_get_cause(vm, args)
    case 211: L.throwable_init0(vm, args)
    case 212: L.throwable_init_s(vm, args)
    case 213: L.throwable_init_t(vm, args)
    case 214: L.throwable_init_st(vm, args)
    case 400: I.execute_vm(id, vm, args)
    case 584: I.execute_vm(id, vm, args)
    case 585: I.execute_vm(id, vm, args)
    case 586: I.execute_vm(id, vm, args)
    case 587: I.execute_vm(id, vm, args)
    case 588: I.execute_vm(id, vm, args)
    case 589: I.execute_vm(id, vm, args)
    case 590: I.execute_vm(id, vm, args)
    case 591: I.execute_vm(id, vm, args)
    case 592: I.execute_vm(id, vm, args)
    case 593: I.execute_vm(id, vm, args)
    case 401: I.execute_vm(id, vm, args)
    case 402: I.execute_vm(id, vm, args)
    case 403: I.execute_vm(id, vm, args)
    case 404: I.execute_vm(id, vm, args)
    case 405: I.execute_vm(id, vm, args)
    case 406: I.execute_vm(id, vm, args)
    case 407: I.execute_vm(id, vm, args)
    case 408: I.execute_vm(id, vm, args)
    case 409: I.execute_vm(id, vm, args)
    case 410: I.execute_vm(id, vm, args)
    case 411: I.execute_vm(id, vm, args)
    case 412: I.execute_vm(id, vm, args)
    case 413: I.execute_vm(id, vm, args)
    case 414: I.execute_vm(id, vm, args)
    case 415: I.execute_vm(id, vm, args)
    case 416: I.execute_vm(id, vm, args)
    case 417: I.execute_vm(id, vm, args)
    case 418: I.execute_vm(id, vm, args)
    case 419: I.execute_vm(id, vm, args)
    case 428: I.execute_vm(id, vm, args)
    case 429: I.execute_vm(id, vm, args)
    case 430:
      do Result<&2, &2, String, O.Outcome>:
        bits : U32 <- static_argument(args, 2)
        result : O.Outcome <- L.int_out(vm, bits)
        return result
    case 431:
      do Result<&2, &2, String, O.Outcome>:
        bits : U32 <- static_argument(args, 1)
        return O.Returned{vm, Some{M.Slot{2, bits}}}
    case 439: I.execute_vm(id, vm, args)
    case 440: I.execute_vm(id, vm, args)
    case 441: I.execute_vm(id, vm, args)
    case 442: I.execute_vm(id, vm, args)
    case 443: I.execute_vm(id, vm, args)
    case 444: I.execute_vm(id, vm, args)
    case 445: I.execute_vm(id, vm, args)
    case 446: I.execute_vm(id, vm, args)
    case 447: I.execute_vm(id, vm, args)
    case 448: I.execute_vm(id, vm, args)
    case 449: I.execute_vm(id, vm, args)
    case 451: I.execute_vm(id, vm, args)
    case 452: I.execute_vm(id, vm, args)
    case 453: I.execute_vm(id, vm, args)
    case 454: I.execute_vm(id, vm, args)
    case 455: I.execute_vm(id, vm, args)
    case 456: I.execute_vm(id, vm, args)
    case 457: I.execute_vm(id, vm, args)
    case 458: I.execute_vm(id, vm, args)
    case 459: I.execute_vm(id, vm, args)
    case 460: I.execute_vm(id, vm, args)
    case 461: I.execute_vm(id, vm, args)
    case 433: I.execute_vm(id, vm, args)
    case 434: I.execute_vm(id, vm, args)
    case 435: I.execute_vm(id, vm, args)
    case 436: I.execute_vm(id, vm, args)
    case 437: I.execute_vm(id, vm, args)
    case 438: I.execute_vm(id, vm, args)
    case 432: I.execute_vm(id, vm, args)
    case 420: I.execute_vm(id, vm, args)
    case 421: I.execute_vm(id, vm, args)
    case 422: I.execute_vm(id, vm, args)
    case 423: I.execute_vm(id, vm, args)
    case 424: I.execute_vm(id, vm, args)
    case 425: I.execute_vm(id, vm, args)
    case 426: I.execute_vm(id, vm, args)
    case 427: I.execute_vm(id, vm, args)
    case _: native_or_missing(Nb.is_native_intrinsic(id), id, vm, args)

def execute_initialized(start: L.ClassForNameStart, +id: U32, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match start:
    case L.ClassForNameReady{+vm}: execute_ready(id, vm, args)
    case L.ClassForNameCall{+vm, owner, +method}: Done{L.init_call(vm, owner, method, M.NeedIntrinsicRetry{id, args})}
    case L.ClassForNameBlocked{+vm, class}: Done{L.init_park(vm, class, M.NeedIntrinsicRetry{id, args})}

# Every intrinsic dispatch, whether from bytecode or requested by another
# intrinsic, first initializes the class the operation requires; the
# intrinsic re-runs with the same arguments after each <clinit> returns.
def execute_vm(+id: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    target : U32 <- L.initialization_target(vm, args, id)
    start : L.ClassForNameStart <- L.class_for_name_walk(256n, vm, target)
    result : O.Outcome <- execute_initialized(start, id, args)
    return result

def continue_java(+vm: M.VM, cont: M.Cont, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match cont:
    case M.NeedIntrinsicRetry{+kind, +args}: execute_vm(kind, vm, args)
    case M.NeedLoaderParent{+loader, +name}: Ld.continue_parent(vm, loader, name, value)
    case M.NeedDefine{+job}: Ld.continue_define(vm, job, value)
    case M.NeedForName{+initialize}: Ld.continue_for_name(vm, initialize, value)
    case M.NeedResourceParent{+loader, +name}: Ld.continue_resource_parent(vm, loader, name, value)
    case M.NeedResourceStream{}: Ld.continue_resource_stream(vm, value)
    case M.NeedSerialWrite{stream, tasks}: Se.continue_java(vm, cont, value)
    case M.NeedSerialRead{stream, tasks, values}: Se.continue_java(vm, cont, value)
    case M.NeedBulkRead{+stream, +array, +offset, +length, +got}: continue_bulk_read(vm, stream, array, offset, length, got, M.slot_bits(value))
    case _: L.continue_java(vm, cont, value)
