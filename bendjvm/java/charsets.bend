import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ./outcome.bend as O
import ./library.bend as L
import ./strings.bend as Str

# String <-> byte[] conversions (intrinsics 823-828, plan 05): String.getBytes
# and the byte[] String constructors for UTF-8 (the default charset),
# US-ASCII and ISO-8859-1. Malformed UTF-8 decodes to U+FFFD, and unmappable
# characters encode to '?', as the JDK's replacement behavior does.

def ascii_upper(units: +List<U32>) -> +List<U32>:
  match units:
    case Nil{}: Nil{}
    case Con{+u, rest}: Con{Bool.pick(U32, U32.is_ge(u, 97) && U32.is_le(u, 122), U32.sub(u, 32), u), ascii_upper(rest)}

# 0 UTF-8, 1 US-ASCII, 2 ISO-8859-1, 3 unsupported.
def charset_code(+name: String) -> U32:
  +upper : String = L.utf16(ascii_upper(L.units_from_string(name)), 0)
  Bool.pick(U32, String.eq(upper, "UTF-8") || String.eq(upper, "UTF8"), 0,
    Bool.pick(U32, String.eq(upper, "US-ASCII") || String.eq(upper, "ASCII"), 1,
      Bool.pick(U32, String.eq(upper, "ISO-8859-1") || String.eq(upper, "ISO8859_1") || String.eq(upper, "LATIN1"), 2, 3)))

def utf8_one(+unit: U32, +rest: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_lt(unit, 128), Con{unit, rest},
    Bool.pick(+List<U32>, U32.is_lt(unit, 2048), Con{U32.or(192, U32.shrn(unit, 6n)), Con{U32.or(128, U32.and(unit, 63)), rest}},
      Bool.pick(+List<U32>, U32.is_lt(unit, 65536),
        Con{U32.or(224, U32.shrn(unit, 12n)), Con{U32.or(128, U32.and(U32.shrn(unit, 6n), 63)), Con{U32.or(128, U32.and(unit, 63)), rest}}},
        Con{U32.or(240, U32.shrn(unit, 18n)), Con{U32.or(128, U32.and(U32.shrn(unit, 12n), 63)), Con{U32.or(128, U32.and(U32.shrn(unit, 6n), 63)), Con{U32.or(128, U32.and(unit, 63)), rest}}}})))

def is_high(+unit: U32) -> Bool:
  U32.is_ge(unit, 55296) && U32.is_le(unit, 56319)

def is_low(+unit: U32) -> Bool:
  U32.is_ge(unit, 56320) && U32.is_le(unit, 57343)

def pair(+high: U32, +low: U32) -> U32:
  U32.add(65536, U32.add(U32.shln(U32.sub(high, 55296), 10n), U32.sub(low, 56320)))

def narrow_encode(units: +List<U32>, +limit: U32) -> +List<U32>:
  match units:
    case Nil{}: Nil{}
    case Con{+unit, rest}: Con{Bool.pick(U32, U32.is_lt(unit, limit), unit, 63), narrow_encode(rest, limit)}

def continuation(+b: U32) -> Bool:
  U32.is_eq(U32.and(b, 192), 128)

def from_code_point(+code: U32, +rest: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_lt(code, 65536), Con{code, rest},
    Con{U32.add(55296, U32.shrn(U32.sub(code, 65536), 10n)), Con{U32.add(56320, U32.and(U32.sub(code, 65536), 1023)), rest}})

# UTF-8 bytes to UTF-16 units; each malformed sequence becomes U+FFFD.
@unsafe def utf8_decode(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: utf8_lead(U32.and(b, 255), rest)

# 0 ASCII, 2/3/4 lead byte of a sequence that long, 1 invalid lead.
def lead_kind(+b: U32) -> U32:
  Bool.pick(U32, U32.is_lt(b, 128), 0,
    Bool.pick(U32, U32.is_ge(b, 194) && U32.is_le(b, 223), 2,
      Bool.pick(U32, U32.is_ge(b, 224) && U32.is_le(b, 239), 3,
        Bool.pick(U32, U32.is_ge(b, 240) && U32.is_le(b, 244), 4, 1))))

@unsafe def utf8_lead(+b: U32, +rest: +List<U32>) -> +List<U32>:
  utf8_kind(lead_kind(b), b, rest)

@unsafe def utf8_kind(+kind: U32, +b: U32, +rest: +List<U32>) -> +List<U32>:
  match kind:
    case 0: Con{b, utf8_decode(rest)}
    case 2: utf8_two(b, rest)
    case 3: utf8_three(b, rest)
    case 4: utf8_four(b, rest)
    case _: Con{65533, utf8_decode(rest)}

# A truncated sequence at the end of input decodes to a single U+FFFD.
@unsafe def drop_one(rest: +List<U32>) -> +List<U32>:
  match rest:
    case Nil{}: Nil{}
    case Con{+c, +more}: drop_if(continuation(U32.and(c, 255)), more, rest)

@unsafe def drop_if(cont: Bool, +more: +List<U32>, +rest: +List<U32>) -> +List<U32>:
  match cont:
    case True{}: drop_one(more)
    case False{}: rest

@unsafe def utf8_take(ok: Bool, +code: U32, +more: +List<U32>, +rest: +List<U32>) -> +List<U32>:
  match ok:
    case True{}: from_code_point(code, utf8_decode(more))
    case False{}: Con{65533, utf8_decode(rest)}

@unsafe def utf8_two(+b: U32, +rest: +List<U32>) -> +List<U32>:
  match rest:
    case Con{+c, +more}: utf8_take(continuation(U32.and(c, 255)), U32.or(U32.shln(U32.and(b, 31), 6n), U32.and(c, 63)), more, rest)
    case Nil{}: [65533]

@unsafe def utf8_three(+b: U32, +rest: +List<U32>) -> +List<U32>:
  match rest:
    case Con{+c, Con{+d, +more}}:
      +code : U32 = U32.or(U32.or(U32.shln(U32.and(b, 15), 12n), U32.shln(U32.and(c, 63), 6n)), U32.and(d, 63))
      utf8_take(continuation(U32.and(c, 255)) && continuation(U32.and(d, 255)) && U32.is_ge(code, 2048) && Bool.not(U32.is_ge(code, 55296) && U32.is_le(code, 57343)), code, more, rest)
    case _: Con{65533, utf8_decode(drop_one(rest))}

@unsafe def utf8_four(+b: U32, +rest: +List<U32>) -> +List<U32>:
  match rest:
    case Con{+c, Con{+d, Con{+e, +more}}}:
      +code : U32 = U32.or(U32.or(U32.shln(U32.and(b, 7), 18n), U32.shln(U32.and(c, 63), 12n)), U32.or(U32.shln(U32.and(d, 63), 6n), U32.and(e, 63)))
      utf8_take(continuation(U32.and(c, 255)) && continuation(U32.and(d, 255)) && continuation(U32.and(e, 255)) && U32.is_ge(code, 65536) && U32.is_le(code, 1114111), code, more, rest)
    case _: Con{65533, utf8_decode(drop_one(rest))}

def narrow_decode(bytes: +List<U32>, +ascii: Bool) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}:
      +value : U32 = U32.and(b, 255)
      Con{Bool.pick(U32, ascii && U32.is_ge(value, 128), 65533, value), narrow_decode(rest, ascii)}

@unsafe def decode(+code: U32, bytes: +List<U32>) -> +List<U32>:
  match code:
    case 0: utf8_decode(bytes)
    case 1: narrow_decode(bytes, True{})
    case _: narrow_decode(bytes, False{})

def slot_bytes(slots: +List<M.Slot>) -> +List<U32>:
  match slots:
    case Nil{}: Nil{}
    case Con{slot, rest}: Con{U32.and(M.slot_bits(slot), 255), slot_bytes(rest)}

def byte_slots(bytes: +List<U32>) -> +List<M.Slot>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: Con{M.Slot{1, Bool.pick(U32, U32.is_ge(b, 128), U32.or(b, 4294967040), b)}, byte_slots(rest)}

def unsupported(+name: String) -> String:
  "java/io/UnsupportedEncodingException: " ++ name

def charset_of(+vm: M.VM, +args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +units : +List<U32> <- Str.string_arg(vm, args, index)
    +name : String = L.utf16(units, 0)
    +code : U32 = charset_code(name)
    checked : Unit <- S.check(U32.is_ne(code, 3), unsupported(name))
    return code

def allocated_ref(allocation: H.Allocation) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case H.Allocation{vm, reference}: L.ref_out(vm, reference)

def array_bytes(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    checked : Unit <- S.check(U32.is_ne(reference, 0), L.npe())
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    return slot_bytes(L.entry_values(entry))

def range_ok(+offset: U32, +count: U32, +size: U32) -> Bool:
  U32.is_lt(offset, 2147483648) && U32.is_lt(count, 2147483648) && U32.is_le(offset, size) && U32.is_le(count, U32.sub(size, offset))

# new String(byte[] bytes, int offset, int length, charset); `code` 3 reads
# the charset name from argument `nameAt`.
@unsafe def init_bytes(+vm: M.VM, +args: +List<M.Slot>, +ranged: Bool, +nameAt: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- Str.int_arg(args, 0)
    +array : U32 <- Str.int_arg(args, 1)
    +bytes : +List<U32> <- array_bytes(vm, array)
    +offset : U32 <- Bool.pick(Result<&2, &2, String, U32>, ranged, Str.int_arg(args, 2), Done{0})
    +count : U32 <- Bool.pick(Result<&2, &2, String, U32>, ranged, Str.int_arg(args, 3), Done{M.length(U32, bytes)})
    checked : Unit <- S.check(range_ok(offset, count, M.length(U32, bytes)), "java/lang/StringIndexOutOfBoundsException")
    +code : U32 <- Bool.pick(Result<&2, &2, String, U32>, U32.is_eq(nameAt, 0), Done{0}, charset_of(vm, args, nameAt))
    +units : +List<U32> = decode(code, M.take(U32, M.drop(U32, bytes, U32.to_nat(offset)), U32.to_nat(count)))
    result : O.Outcome <- Str.string_init_units(vm, receiver, units)
    return result

@unsafe def execute(+id: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 823: get_bytes(vm, args, False{})
    case 824: get_bytes(vm, args, True{})
    case 825: init_bytes(vm, args, False{}, 0)
    case 826: init_bytes(vm, args, False{}, 2)
    case 827: init_bytes(vm, args, True{}, 4)
    case 828: init_bytes(vm, args, True{}, 0)
    case _: Fail{"MissingMethod: unknown charset intrinsic"}

# UTF-16 code units to UTF-8 bytes; a lone surrogate encodes as '?'.
@unsafe def utf8_encode(units: +List<U32>) -> +List<U32>:
  match units:
    case Nil{}: Nil{}
    case Con{+unit, rest}: utf8_unit(is_high(unit), is_low(unit), unit, rest)

@unsafe def utf8_pair(paired: Bool, +unit: U32, +next: U32, +more: +List<U32>) -> +List<U32>:
  match paired:
    case True{}: utf8_one(pair(unit, next), utf8_encode(more))
    case False{}: Con{63, utf8_encode(Con{next, more})}

@unsafe def utf8_unit(high: Bool, low: Bool, +unit: U32, rest: +List<U32>) -> +List<U32>:
  match high low rest:
    case True{} _ Con{+next, more}: utf8_pair(is_low(next), unit, next, more)
    case True{} _ Nil{}: [63]
    case False{} True{} _: Con{63, utf8_encode(rest)}
    case False{} False{} _: utf8_one(unit, utf8_encode(rest))

@unsafe def encode(+code: U32, units: +List<U32>) -> +List<U32>:
  match code:
    case 0: utf8_encode(units)
    case 1: narrow_encode(units, 128)
    case _: narrow_encode(units, 256)

@unsafe def get_bytes_code(+vm: M.VM, +args: +List<M.Slot>, +code: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +units : +List<U32> <- Str.string_arg(vm, args, 0)
    allocation : H.Allocation <- H.allocate(vm, H.primitive_array_entry(L.class_id(vm, "[B"), 8, byte_slots(encode(code, units))))
    result : O.Outcome <- allocated_ref(allocation)
    return result

# String.getBytes() / getBytes(String charsetName).
@unsafe def get_bytes(+vm: M.VM, +args: +List<M.Slot>, +named: Bool) -> Result<&2, &2, String, O.Outcome>:
  match named:
    case False{}: get_bytes_code(vm, args, 0)
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +code : U32 <- charset_of(vm, args, 1)
        result : O.Outcome <- get_bytes_code(vm, args, code)
        return result
