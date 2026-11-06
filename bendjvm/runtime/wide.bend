import Base

# Category-two JVM values retain raw high/low U32 words in model.Slot. These
# pure helpers implement Java long bit operations without host 64-bit types.
type Words is Data:
  Words{high: U32, low: U32}


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

def shl_steps(n: Nat, value: Words) -> Words:
  match n:
    case 0n:
      value
    case 1n+p:
      shl_steps(p, shl_one(value))

def shr_steps(n: Nat, value: Words) -> Words:
  match n:
    case 0n:
      value
    case 1n+p:
      shr_steps(p, shr_one(value))

def sar_steps(n: Nat, value: Words) -> Words:
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

def mul_steps(n: Nat, +a: Words, b: Words, +result: Words) -> Words:
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

def unsigned_remainder_overflows(remainder: Words) -> Bool:
  match remainder:
    case Words{high, low}: U32.is_ge(high, 2147483648)

def unsigned_div_step(bit: Bool, +remainder: Words, +divisor: Words) -> DivisionStep:
  overflow = unsigned_remainder_overflows(remainder)
  +shifted = low_bit(shl_one(remainder), bit)
  +take : Bool = overflow || Bool.not(unsigned_less(shifted, divisor))
  DivisionStep{Bool.pick(Words, take, sub(shifted, divisor), shifted), take}
def division_remainder(step: DivisionStep) -> Words:
  match step:
    case DivisionStep{remainder, quotientBit}: remainder

def division_bit(step: DivisionStep) -> Bool:
  match step:
    case DivisionStep{remainder, quotientBit}: quotientBit

def divide_steps(n: Nat, +dividend: Words, +divisor: Words, quotient: Words, remainder: Words) -> Division:
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
# Decimal digits of an unsigned 64-bit magnitude, least significant first into acc.
# `n` bounds the loop (20 digits suffice for 2^64); `done` stops after the most
# significant digit, so the recursion is structural and needs no @unsafe.
def long_digits(n: Nat, done: Bool, +division: Division, +acc: String) -> String:
  match n done division:
    case 0n _ _: acc
    case 1n+p True{} _: acc
    case 1n+p False{} Division{+quotient, remainder}:
      long_digits(p, long_zero(quotient), unsigned_divide(quotient, Words{0, 10}), SCon{Chr{U32.add(48, long_to_int(remainder))}, acc})

def long_show(+value: Words) -> String:
  +negative = sign_bit(value)
  +magnitude = Bool.pick(Words, negative, neg(value), value)
  +digits = long_digits(21n, False{}, unsigned_divide(magnitude, Words{0, 10}), "")
  Bool.pick(String, negative, "-" ++ digits, digits)
