import Base
import ../model.bend as M
import ../runtime/value.bend as V
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy

type Outcome is Data:
  Outcome{vm: M.VM, output: Maybe<&2, String>, value: Maybe<&2, M.Slot>}
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

def string_entry(entry: M.HeapEntry) -> Result<&2, &2, String, String>:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  do Result<&2, &2, String, String>:
    checked : Unit <- S.check(U32.is_eq(kind, 3), "InvalidState: println(String) requires String")
    return utf16(chars, 0)

def string_value(heap: +List<M.HeapEntry>, reference: U32, null: Bool) -> Result<&2, &2, String, String>:
  match null:
    case True{}:
      Done{"null"}
    case False{}:
      do Result<&2, &2, String, String>:
        entry : M.HeapEntry <- H.get(heap, reference)
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
    text : String <- string_value(heap, bits, U32.is_eq(bits, 0))
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
    case 7:
      Done{None{}}
    case 8:
      do Result<&2, &2, String, Maybe<&2, String>>:
        bits : U32 <- argument(args, 3)
        return None{}
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
    case Con{M.Slot{tag, bits}, Nil{}}:
      do Result<&2, &2, String, U32>:
        checked : Unit <- S.check(U32.is_eq(tag, 3), "InvalidState: intrinsic receiver tag")
        return bits
    case _:
      Fail{"InvalidState: intrinsic argument count"}

def open_resource_allocation(+vm: M.VM, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, Outcome>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{allocation_value}:
      match allocation_value:
        case H.Allocation{updated, reference}:
          Done{Outcome{updated, None{}, Some{M.Slot{3, reference}}}}

def open_resource_found(+vm: M.VM, found: Maybe<&2, M.Resource>) -> Result<&2, &2, String, Outcome>:
  match found:
    case None{}:
      Done{Outcome{vm, None{}, Some{M.Slot{3, 0}}}}
    case Some{resource}:
      match resource:
        case M.Resource{resource_name, +bytes}:
          open_resource_allocation(vm, H.allocate(vm, H.stream_entry(class_id_find(S.classes(vm), S.symbols(vm), "java/io/InputStream"), bytes)))

def open_resource(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, Outcome>:
  do Result<&2, &2, String, Outcome>:
    +bits : U32 <- static_argument(args, 3)
    name : String <- string_value(S.heap(vm), bits, U32.is_eq(bits, 0))
    result : Outcome <- open_resource_found(vm, resource_find(S.resources(vm), name))
    return result

def stream_read_byte(+vm: M.VM, reference: U32, class: U32, +position: U32, fields: +List<M.Binding>, +values: +List<M.Slot>, chars: +List<U32>) -> Result<&2, &2, String, Outcome>:
  do Result<&2, &2, String, Outcome>:
    value : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, position), "InvalidState: stream position")
    updated : M.HeapEntry = M.HeapEntry{class, 4, U32.add(position, 1), fields, values, chars}
    return Outcome{H.put(vm, reference, updated), None{}, Some{value}}

def stream_read_state(+vm: M.VM, reference: U32, class: U32, +position: U32, fields: +List<M.Binding>, +values: +List<M.Slot>, chars: +List<U32>, closed: Bool) -> Result<&2, &2, String, Outcome>:
  match closed:
    case True{}:
      Done{Outcome{vm, None{}, Some{M.Slot{1, 4294967295}}}}
    case False{}:
      Bool.pick(Result<&2, &2, String, Outcome>, U32.is_ge(position, M.length(M.Slot, values)), Done{Outcome{vm, None{}, Some{M.Slot{1, 4294967295}}}}, stream_read_byte(vm, reference, class, position, fields, values, chars))

def stream_read_entry(+vm: M.VM, reference: U32, entry: M.HeapEntry) -> Result<&2, &2, String, Outcome>:
  match entry:
    case M.HeapEntry{class, 4, position, +fields, +values, chars}:
      stream_read_state(vm, reference, class, position, fields, values, chars, H.stream_closed(fields))
    case _:
      Fail{"InvalidState: InputStream reference"}

def read_stream(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, Outcome>:
  do Result<&2, &2, String, Outcome>:
    +reference : U32 <- receiver(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    result : Outcome <- stream_read_entry(vm, reference, entry)
    return result

def close_stream_entry(+vm: M.VM, reference: U32, entry: M.HeapEntry) -> Result<&2, &2, String, Outcome>:
  match entry:
    case M.HeapEntry{class, 4, position, +fields, values, chars}:
      updated : M.HeapEntry = M.HeapEntry{class, 4, position, H.binding_set(fields, 0, M.Slot{1, 1}), values, chars}
      Done{Outcome{H.put(vm, reference, updated), None{}, None{}}}
    case _:
      Fail{"InvalidState: InputStream reference"}

def close_stream(+vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, Outcome>:
  do Result<&2, &2, String, Outcome>:
    +reference : U32 <- receiver(args)
    entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    result : Outcome <- close_stream_entry(vm, reference, entry)
    return result

def legacy_outcome(id: U32, +vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, Outcome>:
  do Result<&2, &2, String, Outcome>:
    output : Maybe<&2, String> <- execute(id, S.heap(vm), args)
    return Outcome{vm, output, None{}}

def execute_vm(id: U32, +vm: M.VM, args: +List<M.Slot>) -> Result<&2, &2, String, Outcome>:
  match id:
    case 9:
      open_resource(vm, args)
    case 10:
      read_stream(vm, args)
    case 11:
      close_stream(vm, args)
    case _:
      legacy_outcome(id, vm, args)
