import Base
import ../model.bend as M
import ../runtime/value.bend as V
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ./outcome.bend as O
import ./library.bend as L

# java.lang.String searching, comparison and transformation (Java 8 semantics).
# Strings are lists of UTF-16 code units; -1 is the U32 4294967295.

def none() -> U32:
  4294967295

def bits(slot: M.Slot) -> U32:
  M.slot_bits(slot)

def receiver_chars(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    +receiver : M.Slot <- L.slot0(args)
    +chars : +List<U32> <- L.string_chars(vm, bits(receiver))
    return chars

# Argument `index` as a String (NullPointerException when null).
def string_arg(+vm: M.VM, +args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    +slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, args, index), "InvalidState: intrinsic argument count")
    +checked : Unit <- S.check(U32.is_ne(bits(slot), 0), L.npe())
    +chars : +List<U32> <- L.string_chars(vm, bits(slot))
    return chars

def sequence_arg(+vm: M.VM, +args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    +slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, args, index), "InvalidState: intrinsic argument count")
    +chars : +List<U32> <- L.char_sequence_chars(vm, bits(slot))
    return chars

def int_arg(+args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, args, index), "InvalidState: intrinsic argument count")
    return bits(slot)

# A start index clamped to [0, len] the way indexOf treats fromIndex.
def clamp_from(+from: U32, +len: U32) -> U32:
  Bool.pick(U32, V.negative(from), 0, Bool.pick(U32, U32.is_gt(from, len), len, from))

def found_or_next(hit: Bool, +index: U32, next: Unit -> U32) -> U32:
  match hit:
    case True{}: index
    case False{}: next(Unit{})

# First index >= from whose units start with `needle`.
def index_of_units(+text: +List<U32>, +needle: +List<U32>, +index: U32, +from: U32) -> U32:
  match text:
    case Nil{}: Bool.pick(U32, U32.is_ge(index, from) && Bool.not(L.chars_nonempty(needle)), index, none())
    case Con{+unit, +rest}:
      found_or_next(U32.is_ge(index, from) && L.starts_with_units(Con{unit, rest}, needle), index,
        unit0 => index_of_units(rest, needle, U32.add(index, 1), from))

# Last index <= limit whose units start with `needle`.
def last_index_of_units(+text: +List<U32>, +needle: +List<U32>, +index: U32, +limit: U32, +best: U32) -> U32:
  match text:
    case Nil{}: Bool.pick(U32, U32.is_le(index, limit) && Bool.not(L.chars_nonempty(needle)), index, best)
    case Con{+unit, +rest}:
      +hit : Bool = U32.is_le(index, limit) && L.starts_with_units(Con{unit, rest}, needle)
      last_index_of_units(rest, needle, U32.add(index, 1), limit, Bool.pick(U32, hit, index, best))

# indexOf(int ch) searches for a code point: a unit, or a surrogate pair.
def code_point_units(+ch: U32) -> +List<U32>:
  L.units_from_char(ch, Nil{})

def index_of_char(+chars: +List<U32>, +ch: U32, +from: U32) -> U32:
  +len : U32 = L.chars_len(chars)
  Bool.pick(U32, U32.is_ge(from, len) && Bool.not(V.negative(from)), none(), index_of_units(chars, code_point_units(ch), 0, clamp_from(from, len)))

def last_index_limit(+from: U32, +len: U32) -> U32:
  Bool.pick(U32, U32.is_ge(from, len), U32.sub(len, 1), from)

def last_index_of_char(+chars: +List<U32>, +ch: U32, +from: U32) -> U32:
  +len : U32 = L.chars_len(chars)
  Bool.pick(U32, V.negative(from) || U32.is_eq(len, 0), none(), last_index_of_units(chars, code_point_units(ch), 0, last_index_limit(from, len), none()))

def last_index_of_string(+chars: +List<U32>, +needle: +List<U32>, +from: U32) -> U32:
  +len : U32 = L.chars_len(chars)
  +limit : U32 = Bool.pick(U32, U32.is_gt(from, len), len, from)
  Bool.pick(U32, V.negative(from), none(), last_index_of_units(chars, needle, 0, limit, none()))

def string_index_of_char(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +ch : U32 <- int_arg(args, 1)
    +result : O.Outcome <- L.int_out(vm, index_of_char(chars, ch, 0))
    return result

def string_index_of_char_from(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +ch : U32 <- int_arg(args, 1)
    +from : U32 <- int_arg(args, 2)
    +result : O.Outcome <- L.int_out(vm, index_of_char(chars, ch, from))
    return result

def string_index_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +needle : +List<U32> <- string_arg(vm, args, 1)
    +result : O.Outcome <- L.int_out(vm, index_of_units(chars, needle, 0, 0))
    return result

def string_index_of_from(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +needle : +List<U32> <- string_arg(vm, args, 1)
    +from : U32 <- int_arg(args, 2)
    +len : U32 = L.chars_len(chars)
    +result : O.Outcome <- L.int_out(vm, index_of_units(chars, needle, 0, clamp_from(from, len)))
    return result

def string_last_index_of_char(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +ch : U32 <- int_arg(args, 1)
    +len : U32 = L.chars_len(chars)
    +result : O.Outcome <- L.int_out(vm, last_index_of_char(chars, ch, len))
    return result

def string_last_index_of_char_from(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +ch : U32 <- int_arg(args, 1)
    +from : U32 <- int_arg(args, 2)
    +result : O.Outcome <- L.int_out(vm, last_index_of_char(chars, ch, from))
    return result

def string_last_index_of(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +needle : +List<U32> <- string_arg(vm, args, 1)
    +len : U32 = L.chars_len(chars)
    +result : O.Outcome <- L.int_out(vm, last_index_of_string(chars, needle, len))
    return result

def string_last_index_of_from(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +needle : +List<U32> <- string_arg(vm, args, 1)
    +from : U32 <- int_arg(args, 2)
    +result : O.Outcome <- L.int_out(vm, last_index_of_string(chars, needle, from))
    return result

def string_starts_with(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +prefix : +List<U32> <- string_arg(vm, args, 1)
    +result : O.Outcome <- L.bool_out(vm, L.starts_with_units(chars, prefix))
    return result

def string_starts_with_from(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +prefix : +List<U32> <- string_arg(vm, args, 1)
    +from : U32 <- int_arg(args, 2)
    +len : U32 = L.chars_len(chars)
    +inside : Bool = Bool.not(V.negative(from)) && U32.is_le(from, len)
    +result : O.Outcome <- L.bool_out(vm, inside && L.starts_with_units(H.drop_chars(chars, U32.to_nat(Bool.pick(U32, inside, from, 0))), prefix))
    return result

def string_ends_with(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +suffix : +List<U32> <- string_arg(vm, args, 1)
    +result : O.Outcome <- L.bool_out(vm, L.starts_with_units(M.reverse(U32, chars), M.reverse(U32, suffix)))
    return result

@unsafe def drop_spaces_step(space: Bool, +unit: U32, +rest: +List<U32>) -> +List<U32>:
  match space:
    case True{}: drop_spaces(rest)
    case False{}: Con{unit, rest}

def drop_spaces(+chars: +List<U32>) -> +List<U32>:
  match chars:
    case Nil{}: Nil{}
    case Con{+unit, +rest}: drop_spaces_step(U32.is_le(unit, 32), unit, rest)

# trim() removes leading and trailing units <= U+0020.
@unsafe def string_trim(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : M.Slot <- L.slot0(args)
    +chars : +List<U32> <- L.string_chars(vm, bits(receiver))
    +trimmed : +List<U32> = M.reverse(U32, drop_spaces(M.reverse(U32, drop_spaces(chars))))
    +same : Bool = U32.is_eq(L.chars_len(trimmed), L.chars_len(chars))
    +result : O.Outcome <- trim_result(same, vm, bits(receiver), trimmed)
    return result

@unsafe def trim_result(same: Bool, +vm: M.VM, +receiver: U32, +trimmed: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  match same:
    case True{}: L.ref_out(vm, receiver)
    case False{}: L.string_out(vm, trimmed)

def replace_unit(+chars: +List<U32>, +old: U32, +new: U32) -> +List<U32>:
  match chars:
    case Nil{}: Nil{}
    case Con{+unit, rest}: Con{Bool.pick(U32, U32.is_eq(unit, old), new, unit), replace_unit(rest, old, new)}

def string_replace_char(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +old : U32 <- int_arg(args, 1)
    +new : U32 <- int_arg(args, 2)
    +result : O.Outcome <- L.string_out(vm, replace_unit(chars, U32.and(old, 65535), U32.and(new, 65535)))
    return result

# replace(CharSequence, CharSequence): non-overlapping, left to right; an empty
# target inserts the replacement before every unit and at the end.
@unsafe def replace_step(hit: Bool, +text: +List<U32>, +target: +List<U32>, +replacement: +List<U32>, +target_len: U32) -> +List<U32>:
  match hit:
    case True{}: M.append(U32, replacement, replace_units(H.drop_chars(text, U32.to_nat(target_len)), target, replacement, target_len))
    case False{}:
      match text:
        case Nil{}: Nil{}
        case Con{+unit, rest}: Con{unit, replace_units(rest, target, replacement, target_len)}

def replace_units(+text: +List<U32>, +target: +List<U32>, +replacement: +List<U32>, +target_len: U32) -> +List<U32>:
  match text:
    case Nil{}: Nil{}
    case Con{+unit, rest}: replace_step(L.starts_with_units(Con{unit, rest}, target), Con{unit, rest}, target, replacement, target_len)

def replace_empty(+text: +List<U32>, +replacement: +List<U32>) -> +List<U32>:
  match text:
    case Nil{}: replacement
    case Con{+unit, rest}: M.append(U32, replacement, Con{unit, replace_empty(rest, replacement)})

def replace_all_units(empty: Bool, +text: +List<U32>, +target: +List<U32>, +replacement: +List<U32>) -> +List<U32>:
  match empty:
    case True{}: replace_empty(text, replacement)
    case False{}: replace_units(text, target, replacement, L.chars_len(target))

def string_replace(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +target : +List<U32> <- sequence_arg(vm, args, 1)
    +replacement : +List<U32> <- sequence_arg(vm, args, 2)
    +result : O.Outcome <- L.string_out(vm, replace_all_units(Bool.not(L.chars_nonempty(target)), chars, target, replacement))
    return result

# Character.toUpperCase/toLowerCase for ASCII and Latin-1, compared unit by unit
# as String.regionMatches(ignoreCase) does.
def upper_unit(+unit: U32) -> U32:
  Bool.pick(U32, (U32.is_ge(unit, 97) && U32.is_le(unit, 122)) || (U32.is_ge(unit, 224) && U32.is_le(unit, 254) && U32.is_ne(unit, 247)), U32.sub(unit, 32),
    Bool.pick(U32, U32.is_eq(unit, 255), 376, unit))

def lower_unit(+unit: U32) -> U32:
  Bool.pick(U32, (U32.is_ge(unit, 65) && U32.is_le(unit, 90)) || (U32.is_ge(unit, 192) && U32.is_le(unit, 222) && U32.is_ne(unit, 215)), U32.add(unit, 32),
    Bool.pick(U32, U32.is_eq(unit, 376), 255, unit))

def units_equal_ignore_case(+left: +List<U32>, +right: +List<U32>) -> Bool:
  match left right:
    case Nil{} Nil{}: True{}
    case Con{+a, ra} Con{+b, rb}:
      (U32.is_eq(a, b) || U32.is_eq(upper_unit(a), upper_unit(b)) || U32.is_eq(lower_unit(upper_unit(a)), lower_unit(upper_unit(b)))) && units_equal_ignore_case(ra, rb)
    case _ _: False{}

@unsafe def string_equals_ignore_case(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +other : M.Slot <- L.slot1(args)
    +result : O.Outcome <- equals_ignore_case_other(vm, chars, bits(other))
    return result

@unsafe def equals_ignore_case_other(+vm: M.VM, +chars: +List<U32>, +other: U32) -> Result<&2, &2, String, O.Outcome>:
  match other:
    case 0: L.bool_out(vm, False{})
    case +ref:
      do Result<&2, &2, String, O.Outcome>:
        +right : +List<U32> <- L.string_chars(vm, ref)
        +result : O.Outcome <- L.bool_out(vm, U32.is_eq(L.chars_len(chars), L.chars_len(right)) && units_equal_ignore_case(chars, right))
        return result

def map_units(+chars: +List<U32>, +upper: Bool) -> +List<U32>:
  match chars:
    case Nil{}: Nil{}
    case Con{+unit, rest}: Con{Bool.pick(U32, upper, upper_unit(unit), lower_unit(unit)), map_units(rest, upper)}

def string_to_upper(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +result : O.Outcome <- L.string_out(vm, map_units(chars, True{}))
    return result

def string_to_lower(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +result : O.Outcome <- L.string_out(vm, map_units(chars, False{}))
    return result

def unit_slots(+chars: +List<U32>) -> +List<M.Slot>:
  match chars:
    case Nil{}: Nil{}
    case Con{unit, rest}: Con{M.Slot{1, unit}, unit_slots(rest)}

def char_array_alloc(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{vm, reference}}: L.ref_out(vm, reference)

def string_to_char_array(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +chars : +List<U32> <- receiver_chars(vm, args)
    +result : O.Outcome <- char_array_alloc(H.allocate(vm, H.primitive_array_entry(L.class_id(vm, "[C"), 5, unit_slots(chars))))
    return result

def string_value_of_char(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ch : U32 <- int_arg(args, 0)
    +result : O.Outcome <- L.string_out(vm, [U32.and(ch, 65535)])
    return result

def slot_units(+values: +List<M.Slot>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{slot, rest}: Con{U32.and(bits(slot), 65535), slot_units(rest)}

# The units of a char[] argument (NullPointerException when null).
def char_array_units(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    +checked : Unit <- S.check(U32.is_ne(reference, 0), L.npe())
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    return slot_units(L.entry_values(entry))

def char_range(+units: +List<U32>, +offset: U32, +count: U32) -> Result<&2, &2, String, +List<U32>>:
  +len : U32 = L.chars_len(units)
  do Result<&2, &2, String, +List<U32>>:
    +checked : Unit <- S.check(Bool.not(V.negative(offset)) && Bool.not(V.negative(count)) && U32.is_le(offset, len) && U32.is_le(count, U32.sub(len, offset)), L.sioob())
    return H.slice_chars(H.drop_chars(units, U32.to_nat(offset)), U32.to_nat(count))

def string_value_of_chars(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +array : U32 <- int_arg(args, 0)
    +units : +List<U32> <- char_array_units(vm, array)
    +result : O.Outcome <- L.string_out(vm, units)
    return result

def string_value_of_chars_range(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +array : U32 <- int_arg(args, 0)
    +offset : U32 <- int_arg(args, 1)
    +count : U32 <- int_arg(args, 2)
    +units : +List<U32> <- char_array_units(vm, array)
    +range : +List<U32> <- char_range(units, offset, count)
    +result : O.Outcome <- L.string_out(vm, range)
    return result

# new String(...) turns the freshly allocated object into a String entry.
def string_init_units(+vm: M.VM, +receiver: U32, +units: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  L.void_out(H.put(vm, receiver, H.string_entry(L.class_id(vm, "java/lang/String"), units)))

def string_init_empty(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- int_arg(args, 0)
    +result : O.Outcome <- string_init_units(vm, receiver, Nil{})
    return result

def string_init_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- int_arg(args, 0)
    +units : +List<U32> <- string_arg(vm, args, 1)
    +result : O.Outcome <- string_init_units(vm, receiver, units)
    return result

def string_init_chars(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- int_arg(args, 0)
    +array : U32 <- int_arg(args, 1)
    +units : +List<U32> <- char_array_units(vm, array)
    +result : O.Outcome <- string_init_units(vm, receiver, units)
    return result

def string_init_chars_range(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- int_arg(args, 0)
    +array : U32 <- int_arg(args, 1)
    +offset : U32 <- int_arg(args, 2)
    +count : U32 <- int_arg(args, 3)
    +units : +List<U32> <- char_array_units(vm, array)
    +range : +List<U32> <- char_range(units, offset, count)
    +result : O.Outcome <- string_init_units(vm, receiver, range)
    return result

# Integer.toHexString/toOctalString/toBinaryString: the unsigned value in base
# 2^shift with lowercase digits; Integer.toString(int) is signed decimal.
@unsafe def radix_digit(+value: U32) -> U32:
  Bool.pick(U32, U32.is_lt(value, 10), U32.add(48, value), U32.add(87, value))

@unsafe def radix_units(+value: U32, +shift: Nat, +mask: U32, +acc: +List<U32>) -> +List<U32>:
  radix_step(U32.is_eq(value, 0), value, shift, mask, acc)

@unsafe def radix_step(done: Bool, +value: U32, +shift: Nat, +mask: U32, +acc: +List<U32>) -> +List<U32>:
  match done:
    case True{}: acc
    case False{}: radix_units(U32.shrn(value, shift), shift, mask, Con{radix_digit(U32.and(value, mask)), acc})

@unsafe def unsigned_text(+value: U32, +shift: Nat, +mask: U32) -> +List<U32>:
  unsigned_select(U32.is_eq(value, 0), value, shift, mask)

@unsafe def unsigned_select(zero: Bool, +value: U32, +shift: Nat, +mask: U32) -> +List<U32>:
  match zero:
    case True{}: [48]
    case False{}: radix_units(value, shift, mask, Nil{})

@unsafe def integer_radix(+vm: M.VM, +args: +List<M.Slot>, +shift: Nat, +mask: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : U32 <- int_arg(args, 0)
    +result : O.Outcome <- L.string_out(vm, unsigned_text(value, shift, mask))
    return result

@unsafe def integer_static_text(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : U32 <- int_arg(args, 0)
    +result : O.Outcome <- L.string_out(vm, L.units_from_string(V.int_show(value)))
    return result
