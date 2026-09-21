import Base
import ../model.bend as M

def negative(x: U32) -> Bool:
  U32.is_ge(x, 2147483648)

def negate(x: U32) -> U32:
  U32.sub(0, x)

def magnitude(+x: U32) -> U32:
  Bool.pick(U32, negative(x), negate(x), x)

def signed_lt(a: U32, b: U32) -> Bool:
  U32.is_lt(U32.xor(a, 2147483648), U32.xor(b, 2147483648))

def signed_div(+a: U32, +b: U32) -> U32:
  +q = U32.div(magnitude(a), magnitude(b))
  Bool.pick(U32, Bool.xor(negative(a), negative(b)), negate(q), q)

def signed_rem(+a: U32, b: U32) -> U32:
  +r = U32.mod(magnitude(a), magnitude(b))
  Bool.pick(U32, negative(a), negate(r), r)

def shift_left(a: U32, b: U32) -> U32:
  U32.shln(a, U32.to_nat(U32.and(b, 31)))

def shift_unsigned(a: U32, b: U32) -> U32:
  U32.shrn(a, U32.to_nat(U32.and(b, 31)))

def shift_signed(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, negative(a), U32.not(shift_unsigned(U32.not(a), b)), shift_unsigned(a, b))

def narrow_byte(x: U32) -> U32:
  shift_signed(U32.shln(x, 24n), 24)

def narrow_short(x: U32) -> U32:
  shift_signed(U32.shln(x, 16n), 16)

def from_bits(bits: U32) -> F32:
  U32{data} = bits
  F32{data}

def int_float(+bits: U32) -> U32:
  +f = U32.to_f32(magnitude(bits))
  F32.bits(Bool.pick(F32, negative(bits), F32.neg(f), f))

def float_int_finite(+f: F32) -> U32:
  +n = F32.to_u32(F32.trunc(F32.abs(f)))
  Bool.pick(U32, F32.is_lt(f, 0.0), negate(n), n)

def float_int_low(f: F32, low: Bool) -> U32:
  match low:
    case True{}:
      2147483648
    case False{}:
      float_int_finite(f)

def float_int_high(+f: F32, high: Bool) -> U32:
  match high:
    case True{}:
      2147483647
    case False{}:
      float_int_low(f, F32.is_le(f, F32.neg(2147483648.0)))

def float_int_nan(+f: F32, nan: Bool) -> U32:
  match nan:
    case True{}:
      0
    case False{}:
      float_int_high(f, F32.is_ge(f, 2147483648.0))

def float_int(bits: U32) -> U32:
  +f = from_bits(bits)
  float_int_nan(f, F32.is_ne(f, f))

def float_compare_order(+a: F32, +b: F32) -> U32:
  Bool.pick(U32, F32.is_lt(a, b), 4294967295, Bool.pick(U32, F32.is_gt(a, b), 1, 0))

def float_compare_nan(a: F32, b: F32, high: Bool, nan: Bool) -> U32:
  match nan:
    case True{}:
      Bool.pick(U32, high, 1, 4294967295)
    case False{}:
      float_compare_order(a, b)

def float_compare(x: U32, y: U32, high: Bool) -> U32:
  +a = from_bits(x)
  +b = from_bits(y)
  float_compare_nan(a, b, high, Bool.or(F32.is_ne(a, a), F32.is_ne(b, b)))

def int_show(+x: U32) -> String:
  Bool.pick(String, negative(x), "-" ++ U32.show(negate(x)), U32.show(x))

def slot_tag(slot: M.Slot) -> U32:
  M.Slot{tag, bits} = slot
  tag

def slot_bits(slot: M.Slot) -> U32:
  M.Slot{tag, bits} = slot
  bits
