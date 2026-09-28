import Base

# A category-two JVM value is represented by its two raw U32 words. The VM
# keeps the pair behind a wide heap entry; these pure helpers implement the
# Java long bit operations without relying on a host 64-bit type.
type Words is Data:
  Words{high: U32, low: U32}
type DoubleParts is Data:
  DoubleParts{sign: U32, exponent: U32, mantissa: Words}


def add(a: Words, b: Words) -> Words:
  match a b:
    case Words{ah, +al} Words{bh, bl}:
      +lo = (al + bl : U32)
      carry : U32 = Bool.to_u32(U32.is_lt(lo, al))
      Words{(ah + bh + carry : U32), lo}

def sub(a: Words, b: Words) -> Words:
  match a b:
    case Words{ah, +al} Words{bh, +bl}:
      borrow : U32 = Bool.to_u32(U32.is_lt(al, bl))
      Words{(ah - bh - borrow : U32), (al - bl : U32)}

def neg(a: Words) -> Words:
  sub(Words{0, 0}, a)

def signed_less(a: Words, b: Words) -> Bool:
  match a b:
    case Words{ah, al} Words{bh, bl}:
      +sa = U32.xor(ah, 2147483648)
      +sb = U32.xor(bh, 2147483648)
      Bool.pick(Bool, U32.is_lt(sa, sb), True{}, Bool.pick(Bool, U32.is_gt(sa, sb), False{}, U32.is_lt(al, bl)))

def unsigned_less(a: Words, b: Words) -> Bool:
  match a b:
    case Words{+ah, al} Words{+bh, bl}:
      Bool.pick(Bool, U32.is_lt(ah, bh), True{}, Bool.pick(Bool, U32.is_gt(ah, bh), False{}, U32.is_lt(al, bl)))

def shl_one(a: Words) -> Words:
  match a:
    case Words{high, +low}:
      Words{U32.or(U32.shl(high), U32.shrn(low, 31n)), U32.shl(low)}

def shr_one(a: Words) -> Words:
  match a:
    case Words{+high, low}:
      Words{U32.shrn(high, 1n), U32.or(U32.shrn(low, 1n), U32.shln(U32.and(high, 1), 31n))}

def sar_one(a: Words) -> Words:
  match a:
    case Words{+high, +low}:
      sign : U32 = Bool.pick(U32, U32.is_ge(high, 2147483648), 2147483648, 0)
      Words{U32.or(U32.shrn(high, 1n), sign), U32.or(U32.shrn(low, 1n), U32.shln(U32.and(high, 1), 31n))}

@unsafe def shl_steps(n: Nat, value: Words) -> Words:
  match n:
    case 0n:
      value
    case 1n+p:
      shl_steps(p, shl_one(value))

@unsafe def shr_steps(n: Nat, value: Words) -> Words:
  match n:
    case 0n:
      value
    case 1n+p:
      shr_steps(p, shr_one(value))

@unsafe def sar_steps(n: Nat, value: Words) -> Words:
  match n:
    case 0n:
      value
    case 1n+p:
      sar_steps(p, sar_one(value))

def shift_count(value: U32) -> Nat:
  U32.to_nat(U32.and(value, 63))

def shl(value: Words, count: U32) -> Words:
  shl_steps(shift_count(count), value)

def shr(value: Words, count: U32) -> Words:
  shr_steps(shift_count(count), value)

def sar(value: Words, count: U32) -> Words:
  sar_steps(shift_count(count), value)

@unsafe def mul_steps(n: Nat, +a: Words, b: Words, +result: Words) -> Words:
  match n b:
    case 0n _:
      result
    case 1n+p Words{bh, +bl}:
      bit : Bool = U32.is_eq(U32.and(bl, 1), 1)
      next : Words = Bool.pick(Words, bit, add(result, a), result)
      mul_steps(p, shl_one(a), shr_one(Words{bh, bl}), next)

def mul(a: Words, b: Words) -> Words:
  mul_steps(64n, a, b, Words{0, 0})

def int_to_long(+value: U32) -> Words:
  sign : U32 = Bool.pick(U32, U32.is_ge(value, 2147483648), 4294967295, 0)
  Words{sign, value}

def long_to_int(value: Words) -> U32:
  match value:
    case Words{high, low}: low

def long_zero(value: Words) -> Bool:
  match value:
    case Words{high, low}: U32.is_eq(high, 0) && U32.is_eq(low, 0)

def long_cmp(+a: Words, +b: Words) -> U32:
  Bool.pick(U32, signed_less(a, b), 4294967295, Bool.pick(U32, signed_less(b, a), 1, 0))
def sign_bit(value: Words) -> Bool:
  match value:
    case Words{high, low}:
      U32.is_ge(high, 2147483648)

type Division is Data:
  Division{quotient: Words, remainder: Words}
type DivisionStep is Data:
  DivisionStep{remainder: Words, quotientBit: Bool}


def low_bit(value: Words, bit: Bool) -> Words:
  match value:
    case Words{high, low}:
      Words{high, U32.or(low, Bool.to_u32(bit))}

def quotient_step(value: Words, bit: U32) -> Words:
  match value:
    case Words{high, +low}:
      Words{U32.or(U32.shl(high), U32.shrn(low, 31n)), U32.or(U32.shl(low), bit)}

def unsigned_div_step(bit: Bool, remainder: Words, +divisor: Words) -> DivisionStep:
  +shifted = low_bit(shl_one(remainder), bit)
  Bool.pick(DivisionStep, unsigned_less(shifted, divisor), DivisionStep{shifted, False{}}, DivisionStep{sub(shifted, divisor), True{}})
def division_remainder(step: DivisionStep) -> Words:
  match step:
    case DivisionStep{remainder, quotientBit}: remainder

def division_bit(step: DivisionStep) -> Bool:
  match step:
    case DivisionStep{remainder, quotientBit}: quotientBit

@unsafe def divide_steps(n: Nat, +dividend: Words, +divisor: Words, quotient: Words, remainder: Words) -> Division:
  match n:
    case 0n:
      Division{quotient, remainder}
    case 1n+p:
      bit : Bool = sign_bit(dividend)
      next_dividend : Words = shl_one(dividend)
      +step : DivisionStep = unsigned_div_step(bit, remainder, divisor)
      +next_remainder : Words = division_remainder(step)
      qbit : U32 = Bool.to_u32(division_bit(step))
      next_quotient : Words = quotient_step(quotient, qbit)
      divide_steps(p, next_dividend, divisor, next_quotient, next_remainder)

def unsigned_divide(dividend: Words, divisor: Words) -> Division:
  divide_steps(64n, dividend, divisor, Words{0, 0}, Words{0, 0})

def signed_divide_result(+negative: Bool, result: Division) -> Words:
  match result:
    case Division{+quotient, remainder}:
      Bool.pick(Words, negative, neg(quotient), quotient)

def signed_remainder_result(+negative: Bool, result: Division) -> Words:
  match result:
    case Division{quotient, +remainder}:
      Bool.pick(Words, negative, neg(remainder), remainder)

def signed_divide(+dividend: Words, +divisor: Words) -> Words:
  +a_negative = sign_bit(dividend)
  +b_negative = sign_bit(divisor)
  +a_magnitude = Bool.pick(Words, a_negative, neg(dividend), dividend)
  +b_magnitude = Bool.pick(Words, b_negative, neg(divisor), divisor)
  signed_divide_result(Bool.xor(a_negative, b_negative), unsigned_divide(a_magnitude, b_magnitude))

def signed_remainder(+dividend: Words, +divisor: Words) -> Words:
  +negative = sign_bit(dividend)
  +a_magnitude = Bool.pick(Words, negative, neg(dividend), dividend)
  +b_magnitude = Bool.pick(Words, sign_bit(divisor), neg(divisor), divisor)
  signed_remainder_result(negative, unsigned_divide(a_magnitude, b_magnitude))
def bit_and(a: Words, b: Words) -> Words:
  match a b:
    case Words{ah, al} Words{bh, bl}: Words{U32.and(ah, bh), U32.and(al, bl)}

def bit_or(a: Words, b: Words) -> Words:
  match a b:
    case Words{ah, al} Words{bh, bl}: Words{U32.or(ah, bh), U32.or(al, bl)}

def bit_xor(a: Words, b: Words) -> Words:
  match a b:
    case Words{ah, al} Words{bh, bl}: Words{U32.xor(ah, bh), U32.xor(al, bl)}
def double_unpack(value: Words) -> DoubleParts:
  match value:
    case Words{+high, low}:
      +exponent : U32 = U32.and(U32.shrn(high, 20n), 2047)
      +fraction : U32 = U32.and(high, 1048575)
      hidden : U32 = Bool.pick(U32, U32.is_eq(exponent, 0), fraction, U32.or(fraction, 1048576))
      DoubleParts{U32.and(high, 2147483648), exponent, Words{hidden, low}}

def double_add_parts(+a: DoubleParts, +b: DoubleParts) -> DoubleParts:
  match a b:
    case DoubleParts{sa, ea, ma} DoubleParts{sb, eb, mb}:
      Bool.pick(DoubleParts, U32.is_ge(ea, eb),
        DoubleParts{sa, ea, add(ma, shr(mb, U32.sub(ea, eb)))},
        DoubleParts{sb, eb, add(mb, shr(ma, U32.sub(eb, ea)))})

def double_normalize(+value: DoubleParts) -> DoubleParts:
  match value:
    case DoubleParts{+sign, +exponent, +mantissa}:
      match mantissa:
        case Words{high, low}:
          Bool.pick(DoubleParts, U32.is_ge(high, 2097152),
            DoubleParts{sign, U32.add(exponent, 1), shr(mantissa, 1)},
            DoubleParts{sign, exponent, Words{high, low}})

def double_pack_normalized(value: DoubleParts) -> Words:
  match value:
    case DoubleParts{sign, exponent, mantissa}:
      match mantissa:
        case Words{high, low}:
          Words{U32.or(sign, U32.or(U32.shln(exponent, 20n), U32.and(high, 1048575))), low}

def double_pack(+value: DoubleParts) -> Words:
  double_pack_normalized(double_normalize(value))

def double_add(a: Words, b: Words) -> Words:
  double_pack(double_add_parts(double_unpack(a), double_unpack(b)))

def double_neg(value: Words) -> Words:
  match value:
    case Words{+high, low}: Words{U32.xor(high, 2147483648), low}

def double_sub(a: Words, b: Words) -> Words:
  double_add(a, double_neg(b))
type LongTextState is Data:
  LongPending{division: Division}
  LongReady{quotient: Words, remainder: Words, zero: Bool}

@unsafe def long_digits(n: Nat, +value: Words, +acc: String, state: Maybe<&2, LongTextState>) -> String:
  match n state:
    case 0n _:
      acc
    case 1n+p None{}:
      long_digits(n, value, acc, Some{LongPending{unsigned_divide(value, Words{0, 10})}})
    case 1n+p Some{LongPending{division}}:
      match division:
        case Division{+quotient, remainder}:
          long_digits(n, value, acc, Some{LongReady{quotient, remainder, long_zero(quotient)}})
    case 1n+p Some{LongReady{quotient, remainder, zero}}:
      match zero:
        case True{}:
          SCon{Chr{U32.add(48, long_to_int(remainder))}, acc}
        case False{}:
          long_digits(p, quotient, SCon{Chr{U32.add(48, long_to_int(remainder))}, acc}, None{})

def long_show(+value: Words) -> String:
  +negative = sign_bit(value)
  +magnitude = Bool.pick(Words, negative, neg(value), value)
  +digits = long_digits(128n, magnitude, "", None{})
  Bool.pick(String, negative, "-" ++ digits, digits)
type DoubleDecimal is Data:
  DoubleDecimal{integer: Words, remainder: Words, denominator: Words}

type FractionState is Data:
  FractionPending{division: Division}
  FractionReady{digit: U32, remainder: Words, zero: Bool}

def double_split(+mantissa: Words, +exponent: U32) -> DoubleDecimal:
  +left_shift = U32.sub(exponent, 1075)
  +right_shift = U32.sub(1075, exponent)
  Bool.pick(DoubleDecimal, U32.is_ge(exponent, 1075),
    DoubleDecimal{shl(mantissa, left_shift), Words{0, 0}, Words{0, 1}},
    Bool.pick(DoubleDecimal, U32.is_ge(exponent, 1023),
      DoubleDecimal{shr(mantissa, right_shift), sub(mantissa, shl(shr(mantissa, right_shift), right_shift)), shl(Words{0, 1}, right_shift)},
      DoubleDecimal{Words{0, 0}, mantissa, shl(Words{0, 1}, right_shift)}))

@unsafe def double_fraction(n: Nat, +remainder: Words, +denominator: Words, +acc: String, state: Maybe<&2, FractionState>) -> String:
  match n state:
    case 0n _:
      acc
    case 1n+p None{}:
      double_fraction(n, remainder, denominator, acc,
        Some{FractionPending{unsigned_divide(mul(remainder, Words{0, 10}), denominator)}})
    case 1n+p Some{FractionPending{division}}:
      match division:
        case Division{quotient, +remainder}:
          double_fraction(n, remainder, denominator, acc,
            Some{FractionReady{long_to_int(quotient), remainder, long_zero(remainder)}})
    case 1n+p Some{FractionReady{digit, +remainder, zero}}:
      match zero:
        case True{}:
          acc
        case False{}:
          double_fraction(p, remainder, denominator, SCon{Chr{U32.add(48, digit)}, acc}, None{})

def double_render_state(+integer: Words, +remainder: Words, +denominator: Words, zero: Bool) -> String:
  match zero:
    case True{}:
      long_show(integer)
    case False{}:
      long_show(integer) ++ "." ++ double_fraction(24n, remainder, denominator, "", None{})

def double_render(value: DoubleDecimal) -> String:
  match value:
    case DoubleDecimal{integer, +remainder, denominator}:
      double_render_state(integer, remainder, denominator, long_zero(remainder))

def double_show_parts(value: DoubleParts) -> String:
  match value:
    case DoubleParts{sign, exponent, mantissa}:
      +text = double_render(double_split(mantissa, exponent))
      Bool.pick(String, U32.is_ne(sign, 0), "-" ++ text, text)

def double_show(value: Words) -> String:
  double_show_parts(double_unpack(value))
