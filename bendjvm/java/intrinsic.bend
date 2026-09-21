import Base
import ../model.bend as M
import ../runtime/value.bend as V
import ../runtime/state.bend as S
import ../heap/heap.bend as H

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
