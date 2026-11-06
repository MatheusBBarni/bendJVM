import Base
import ./wide.bend as W
import ./double_format.bend as DF

type Decoded is Data:
  Decoded{kind: U32, sign: U32, exponent: U32, significand: W.Words}

type Normalized is Data:
  Normalized{sign: U32, exponent: U32, extended: W.Words}

type DivisionStep is Data:
  DivisionStep{quotient: W.Words, remainder: W.Words}

type Quad is Data:
  Quad{high: U32, upper: U32, lower: U32, low: U32}

# The VM transports binary64 values as raw high/low words. These helpers never
# convert the payload to a Bend/JavaScript floating-point number.
def high_word(value: W.Words) -> U32:
  match value:
    case W.Words{high, low}: high

def low_word(value: W.Words) -> U32:
  match value:
    case W.Words{high, low}: low

def sign_bit(value: W.Words) -> U32:
  match value:
    case W.Words{high, low}: U32.and(high, 2147483648)

def exponent_bits(value: W.Words) -> U32:
  match value:
    case W.Words{high, low}: U32.and(U32.shrn(high, 20n), 2047)

def fraction(value: W.Words) -> W.Words:
  match value:
    case W.Words{high, low}: W.Words{U32.and(high, 1048575), low}

def is_zero(value: W.Words) -> Bool:
  match value:
    case W.Words{high, low}: U32.is_eq(U32.and(high, 2147483647), 0) && U32.is_eq(low, 0)

def double_is_nan(+value: W.Words) -> Bool:
  U32.is_eq(exponent_bits(value), 2047) && Bool.not(W.long_zero(fraction(value)))

def double_is_infinite(+value: W.Words) -> Bool:
  U32.is_eq(exponent_bits(value), 2047) && W.long_zero(fraction(value))

def nan_value() -> W.Words:
  W.Words{2146959360, 0}

def infinity(sign: U32) -> W.Words:
  W.Words{U32.or(sign, 2146435072), 0}

def zero(sign: U32) -> W.Words:
  W.Words{sign, 0}


def exponent_less(left: U32, right: U32) -> Bool:
  U32.is_lt(U32.xor(left, 2147483648), U32.xor(right, 2147483648))

def exponent_ge(left: U32, right: U32) -> Bool:
  Bool.not(exponent_less(left, right))

def exponent_minimum() -> U32:
  U32.sub(0, 1022)

def exponent_maximum() -> U32:
  1023

@unsafe def top_bit_steps(steps: Nat, +value: W.Words, +bit: U32, found: U32) -> U32:
  match steps:
    case 0n: found
    case 1n+rest:
      mask : W.Words = W.shl(W.Words{0, 1}, bit)
      next : U32 = Bool.pick(U32, W.long_zero(W.bit_and(value, mask)), found, bit)
      top_bit_steps(rest, value, U32.add(bit, 1), next)

def top_bit(value: W.Words) -> U32:
  top_bit_steps(64n, value, 0, 0)

def shift_right_jam_large(value: W.Words) -> W.Words:
  Bool.pick(W.Words, W.long_zero(value), W.Words{0, 0}, W.Words{0, 1})

def shift_right_jam_bounded(+value: W.Words, +count: U32) -> W.Words:
  +shifted : W.Words = W.shr(value, count)
  mask : W.Words = W.sub(W.shl(W.Words{0, 1}, count), W.Words{0, 1})
  sticky : Bool = Bool.not(W.long_zero(W.bit_and(value, mask)))
  Bool.pick(W.Words, sticky, W.bit_or(shifted, W.Words{0, 1}), shifted)

def shift_right_jam_nonzero(+value: W.Words, +count: U32) -> W.Words:
  large_count : Bool = U32.is_ge(count, 64)
  Bool.pick(W.Words, large_count, shift_right_jam_large(value), shift_right_jam_bounded(value, count))

def shift_right_jam(+value: W.Words, +count: U32) -> W.Words:
  is_zero_count : Bool = U32.is_eq(count, 0)
  Bool.pick(W.Words, is_zero_count, value, shift_right_jam_nonzero(value, count))
def rounded_significand_from_main(extended: W.Words, +main: W.Words) -> W.Words:
  match extended main:
    case W.Words{extended_high, extended_low} W.Words{main_high, main_low}:
      +discarded : U32 = U32.and(extended_low, 7)
      odd : Bool = U32.is_eq(U32.and(main_low, 1), 1)
      increment : Bool = U32.is_gt(discarded, 4) || (U32.is_eq(discarded, 4) && odd)
      Bool.pick(W.Words, increment, W.add(main, W.Words{0, 1}), main)

def rounded_significand(+extended: W.Words) -> W.Words:
  +main : W.Words = W.shr(extended, 3)
  rounded_significand_from_main(extended, main)

def double_pack_finite(sign: U32, normalized: W.Words, final_exponent: U32) -> W.Words:
  match normalized:
    case W.Words{+normalized_high, normalized_low}:
      +hidden = U32.is_ge(normalized_high, 1048576)
      +raw_exponent = Bool.pick(U32, hidden, U32.add(final_exponent, 1023), 0)
      fraction_high : U32 = U32.and(normalized_high, 1048575)
      W.Words{U32.or(sign, U32.or(U32.shln(raw_exponent, 20n), fraction_high)), normalized_low}

def double_pack64(+sign: U32, +exponent: U32, extended: W.Words) -> W.Words:
  +underflow = exponent_less(exponent, exponent_minimum())
  +distance = Bool.pick(U32, underflow, U32.sub(exponent_minimum(), exponent), 0)
  +adjusted_extended = shift_right_jam(extended, distance)
  +adjusted_exponent = Bool.pick(U32, underflow, exponent_minimum(), exponent)
  +rounded = rounded_significand(adjusted_extended)
  +carry = U32.is_ge(high_word(rounded), 2097152)
  +normalized = Bool.pick(W.Words, carry, W.shr(rounded, 1), rounded)
  +final_exponent = Bool.pick(U32, carry, U32.add(adjusted_exponent, 1), adjusted_exponent)
  +zero_normalized = W.long_zero(normalized)
  +overflow_exponent = exponent_less(1023, final_exponent)
  Bool.pick(W.Words, zero_normalized, zero(sign),
    Bool.pick(W.Words, overflow_exponent, infinity(sign), double_pack_finite(sign, normalized, final_exponent)))

def float_pack_finite(sign: U32, +normalized: W.Words, final_exponent: U32) -> U32:
  +hidden = U32.is_ge(low_word(normalized), 8388608)
  +raw_exponent = Bool.pick(U32, hidden, U32.add(final_exponent, 127), 0)
  U32.or(sign, U32.or(U32.shln(raw_exponent, 23n), U32.and(low_word(normalized), 8388607)))

def float_pack32(+sign: U32, +exponent: U32, extended: W.Words) -> U32:
  +minimum = U32.sub(0, 126)
  +underflow = exponent_less(exponent, minimum)
  +distance = Bool.pick(U32, underflow, U32.sub(minimum, exponent), 0)
  +adjusted_extended = shift_right_jam(extended, distance)
  +adjusted_exponent = Bool.pick(U32, underflow, minimum, exponent)
  +rounded = rounded_significand(adjusted_extended)
  +carry = U32.is_ge(low_word(rounded), 16777216)
  +normalized = Bool.pick(W.Words, carry, W.shr(rounded, 1), rounded)
  +final_exponent = Bool.pick(U32, carry, U32.add(adjusted_exponent, 1), adjusted_exponent)
  +zero_normalized = W.long_zero(normalized)
  +overflow_exponent = exponent_less(127, final_exponent)
  Bool.pick(U32, zero_normalized, sign,
    Bool.pick(U32, overflow_exponent, U32.or(sign, 2139095040), float_pack_finite(sign, normalized, final_exponent)))

def unpack_subnormal(sign: U32, +fraction_words: W.Words) -> Decoded:
  +top = top_bit(fraction_words)
  +shift = U32.sub(52, top)
  Decoded{1, sign, U32.sub(exponent_minimum(), shift), W.shl(fraction_words, shift)}

def unpack_normal(sign: U32, raw_exponent: U32, +fraction_words: W.Words) -> Decoded:
  Decoded{1, sign, U32.sub(raw_exponent, 1023), W.Words{U32.or(U32.and(high_word(fraction_words), 1048575), 1048576), low_word(fraction_words)}}

def unpack_finite(+sign: U32, +raw_exponent: U32, +fraction_words: W.Words) -> Decoded:
  +zero_exponent = U32.is_eq(raw_exponent, 0)
  +zero_fraction = W.long_zero(fraction_words)
  Bool.pick(Decoded, zero_exponent && zero_fraction,
    Decoded{0, sign, exponent_minimum(), W.Words{0, 0}},
    Bool.pick(Decoded, zero_exponent, unpack_subnormal(sign, fraction_words), unpack_normal(sign, raw_exponent, fraction_words)))

def unpack(+value: W.Words) -> Decoded:
  match value:
    case W.Words{high, low}:
      +sign = U32.and(high, 2147483648)
      +raw_exponent = U32.and(U32.shrn(high, 20n), 2047)
      +fraction_words : W.Words = W.Words{U32.and(high, 1048575), low}
      +special_exponent = U32.is_eq(raw_exponent, 2047)
      Bool.pick(Decoded, special_exponent,
        Bool.pick(Decoded, W.long_zero(fraction_words), Decoded{2, sign, raw_exponent, W.Words{0, 0}}, Decoded{3, sign, raw_exponent, fraction_words}),
        unpack_finite(sign, raw_exponent, fraction_words))
def decoded_raw_exponent(value: Decoded) -> U32:
  match value:
    case Decoded{kind, sign, exponent, significand}: exponent

def decoded_significand(value: Decoded) -> W.Words:
  match value:
    case Decoded{kind, sign, exponent, significand}: significand

def decoded_sign(value: Decoded) -> U32:
  match value:
    case Decoded{kind, sign, exponent, significand}: sign

def decoded_kind(value: Decoded) -> U32:
  match value:
    case Decoded{kind, sign, exponent, significand}: kind

def raw_equal(a: W.Words, b: W.Words) -> Bool:
  match a b:
    case W.Words{ah, al} W.Words{bh, bl}: U32.is_eq(ah, bh) && U32.is_eq(al, bl)

def pack_normalized(value: Normalized) -> W.Words:
  match value:
    case Normalized{sign, exponent, extended}: double_pack64(sign, exponent, extended)


def add_same_sign(+left: W.Words, +right: W.Words, sign: U32, +exponent: U32) -> W.Words:
  +sum = W.add(left, right)
  +carry = U32.is_ge(high_word(sum), 16777216)
  +extended = Bool.pick(W.Words, carry, shift_right_jam(sum, 1), sum)
  +result_exponent = Bool.pick(U32, carry, U32.add(exponent, 1), exponent)
  double_pack64(sign, result_exponent, extended)

@unsafe def normalize_difference(steps: Nat, +sign: U32, +exponent: U32, +extended: W.Words) -> Normalized:
  match steps:
    case 0n: Normalized{sign, exponent, extended}
    case 1n+rest:
      normalize_difference_decide(W.long_zero(extended) || U32.is_ge(high_word(extended), 8388608), rest, sign, exponent, extended)

# Stops as soon as the leading bit is in place (or the value is zero).
@unsafe def normalize_difference_decide(done: Bool, steps: Nat, +sign: U32, +exponent: U32, +extended: W.Words) -> Normalized:
  match done:
    case True{}: Normalized{sign, exponent, extended}
    case False{}: normalize_difference(steps, sign, U32.sub(exponent, 1), W.shl(extended, 1))
def subtract_magnitudes(+left: W.Words, +right: W.Words, left_sign: U32, right_sign: U32, exponent: U32) -> W.Words:
  +left_smaller = W.unsigned_less(left, right)
  +larger = Bool.pick(W.Words, left_smaller, right, left)
  +smaller = Bool.pick(W.Words, left_smaller, left, right)
  +difference = W.sub(larger, smaller)
  +result_sign = Bool.pick(U32, W.long_zero(difference), 0, Bool.pick(U32, left_smaller, right_sign, left_sign))
  pack_normalized(normalize_difference(56n, result_sign, exponent, difference))

def add_magnitudes(+sign_a: U32, +exponent_a: U32, +significand_a: W.Words, +sign_b: U32, +exponent_b: U32, +significand_b: W.Words) -> W.Words:
  +a_larger = exponent_ge(exponent_a, exponent_b)
  +exponent = Bool.pick(U32, a_larger, exponent_a, exponent_b)
  +distance = Bool.pick(U32, a_larger, U32.sub(exponent_a, exponent_b), U32.sub(exponent_b, exponent_a))
  +left = Bool.pick(W.Words, a_larger, W.shl(significand_a, 3), W.shl(significand_b, 3))
  +right_raw = Bool.pick(W.Words, a_larger, W.shl(significand_b, 3), W.shl(significand_a, 3))
  +right = shift_right_jam(right_raw, distance)
  +left_sign = Bool.pick(U32, a_larger, sign_a, sign_b)
  +right_sign = Bool.pick(U32, a_larger, sign_b, sign_a)
  +same_sign = U32.is_eq(left_sign, right_sign)
  Bool.pick(W.Words, same_sign,
    add_same_sign(left, right, left_sign, exponent),
    subtract_magnitudes(left, right, left_sign, right_sign, exponent))


def add_finite_by_kind(kind_a: U32, kind_b: U32, +a: W.Words, +b: W.Words, +decoded_a: Decoded, +decoded_b: Decoded) -> W.Words:
  match kind_a kind_b:
    case 0 0:
      +sign_a = decoded_sign(decoded_a)
      +sign_b = decoded_sign(decoded_b)
      Bool.pick(W.Words, U32.is_eq(sign_a, sign_b) && U32.is_ne(sign_a, 0), zero(2147483648), zero(0))
    case 0 _: b
    case _ 0: a
    case _ _: add_magnitudes(decoded_sign(decoded_a), decoded_raw_exponent(decoded_a), decoded_significand(decoded_a), decoded_sign(decoded_b), decoded_raw_exponent(decoded_b), decoded_significand(decoded_b))

def add_finite_or_zero(a: W.Words, b: W.Words, +decoded_a: Decoded, +decoded_b: Decoded) -> W.Words:
  add_finite_by_kind(decoded_kind(decoded_a), decoded_kind(decoded_b), a, b, decoded_a, decoded_b)

def add_special_by_kind(kind_a: U32, kind_b: U32, +a: W.Words, +b: W.Words, +decoded_a: Decoded, +decoded_b: Decoded) -> W.Words:
  match kind_a kind_b:
    case 3 _: nan_value()
    case _ 3: nan_value()
    case 2 2:
      Bool.pick(W.Words, U32.is_eq(decoded_sign(decoded_a), decoded_sign(decoded_b)), a, nan_value())
    case 2 _: a
    case _ 2: b
    case _ _: add_finite_or_zero(a, b, decoded_a, decoded_b)

def add_special(+a: W.Words, +b: W.Words, +decoded_a: Decoded, +decoded_b: Decoded) -> W.Words:
  add_special_by_kind(decoded_kind(decoded_a), decoded_kind(decoded_b), a, b, decoded_a, decoded_b)

def add(+a: W.Words, +b: W.Words) -> W.Words:
  add_special(a, b, unpack(a), unpack(b))

def neg(value: W.Words) -> W.Words:
  match value:
    case W.Words{high, low}: W.Words{U32.xor(high, 2147483648), low}

def sub(a: W.Words, b: W.Words) -> W.Words:
  add(a, neg(b))

# A four-word unsigned intermediate is used only for the exact 53x53 product.
def quad_shift_left(value: Quad) -> Quad:
  match value:
    case Quad{high, +upper, +lower, +low}:
      Quad{U32.or(U32.shl(high), U32.shrn(upper, 31n)), U32.or(U32.shl(upper), U32.shrn(lower, 31n)), U32.or(U32.shl(lower), U32.shrn(low, 31n)), U32.shl(low)}

def quad_shift_right(value: Quad) -> Quad:
  match value:
    case Quad{+high, +upper, +lower, low}:
      Quad{U32.shrn(high, 1n), U32.or(U32.shrn(upper, 1n), U32.shln(U32.and(high, 1), 31n)), U32.or(U32.shrn(lower, 1n), U32.shln(U32.and(upper, 1), 31n)), U32.or(U32.shrn(low, 1n), U32.shln(U32.and(lower, 1), 31n))}


def word_sum(a: U32, b: U32, carry: U32) -> U32:
  (a + b + carry : U32)

def word_carry(+a: U32, +b: U32, carry: U32, sum: U32) -> U32:
  Bool.pick(U32, U32.is_lt((a + b : U32), a) || U32.is_lt(sum, (a + b : U32)), 1, 0)

def quad_add(a: Quad, b: Quad) -> Quad:
  match a b:
    case Quad{+ah, +au, +al, +ax} Quad{+bh, +bu, +bl, +bx}:
      +low = word_sum(ax, bx, 0)
      +carry0 = word_carry(ax, bx, 0, low)
      +lower = word_sum(al, bl, carry0)
      +carry1 = word_carry(al, bl, carry0, lower)
      +upper = word_sum(au, bu, carry1)
      +carry2 = word_carry(au, bu, carry1, upper)
      +high = word_sum(ah, bh, carry2)
      Quad{high, upper, lower, low}

@unsafe def quad_multiply_steps(steps: Nat, +multiplicand: Quad, +multiplier: W.Words, +result: Quad) -> Quad:
  match steps:
    case 0n: result
    case 1n+rest:
      bit : Bool = U32.is_eq(U32.and(low_word(multiplier), 1), 1)
      next_result : Quad = Bool.pick(Quad, bit, quad_add(result, multiplicand), result)
      quad_multiply_steps(rest, quad_shift_left(multiplicand), W.shr(multiplier, 1), next_result)

def quad_multiply(a: W.Words, b: W.Words) -> Quad:
  match a:
    case W.Words{high, low}: quad_multiply_steps(64n, Quad{0, 0, high, low}, b, Quad{0, 0, 0, 0})

@unsafe def quad_shift_jam_steps(steps: Nat, +value: Quad, sticky: Bool) -> W.Words:
  match steps:
    case 0n:
      match value:
        case Quad{high, upper, +lower, +low}:
          Bool.pick(W.Words, sticky, W.Words{lower, U32.or(low, 1)}, W.Words{lower, low})
    case 1n+rest:
      match value:
        case Quad{high, upper, lower, low}:
          quad_shift_jam_steps(rest, quad_shift_right(value), sticky || U32.is_eq(U32.and(low, 1), 1))

def quad_shift_jam(value: Quad, count: U32) -> W.Words:
  quad_shift_jam_steps(U32.to_nat(count), value, False{})

def product_from_quad(+product: Quad, sign: U32, exponent_a: U32, exponent_b: U32) -> W.Words:
  match product:
    case Quad{high, upper, lower, low}:
      +overflow = U32.is_ge(high, 512)
      +shift = Bool.pick(U32, overflow, 50, 49)
      +extended = quad_shift_jam(product, shift)
      +exponent = U32.add(U32.add(exponent_a, exponent_b), Bool.to_u32(overflow))
      double_pack64(sign, exponent, extended)

def product_value(a: W.Words, b: W.Words, sign: U32, exponent_a: U32, exponent_b: U32) -> W.Words:
  product_from_quad(quad_multiply(a, b), sign, exponent_a, exponent_b)

def multiply_by_kind(kind_a: U32, kind_b: U32, +decoded_a: Decoded, +decoded_b: Decoded, sign: U32) -> W.Words:
  match kind_a kind_b:
    case 3 _: nan_value()
    case _ 3: nan_value()
    case 2 0: nan_value()
    case 0 2: nan_value()
    case 2 _: infinity(sign)
    case _ 2: infinity(sign)
    case 0 _: zero(sign)
    case _ 0: zero(sign)
    case _ _:
      product_value(decoded_significand(decoded_a), decoded_significand(decoded_b), sign, decoded_raw_exponent(decoded_a), decoded_raw_exponent(decoded_b))

def multiply(a: W.Words, b: W.Words) -> W.Words:
  +decoded_a = unpack(a)
  +decoded_b = unpack(b)
  +kind_a = decoded_kind(decoded_a)
  +kind_b = decoded_kind(decoded_b)
  +sign = U32.xor(decoded_sign(decoded_a), decoded_sign(decoded_b))
  multiply_by_kind(kind_a, kind_b, decoded_a, decoded_b, sign)

# Restoring division emits 56 normalized quotient bits plus a sticky remainder.
def division_step(+remainder: W.Words, +divisor: W.Words) -> DivisionStep:
  +less = W.unsigned_less(remainder, divisor)
  Bool.pick(DivisionStep, less,
    DivisionStep{W.Words{0, 0}, remainder},
    DivisionStep{W.Words{0, 1}, W.sub(remainder, divisor)})
def division_quotient_bit(step: DivisionStep) -> U32:
  match step:
    case DivisionStep{quotient, remainder}: low_word(quotient)

def division_remainder(step: DivisionStep) -> W.Words:
  match step:
    case DivisionStep{quotient, remainder}: remainder

@unsafe def quotient_steps(steps: Nat, remainder: W.Words, +divisor: W.Words, quotient: W.Words) -> DivisionStep:
  match steps:
    case 0n: DivisionStep{quotient, remainder}
    case 1n+rest:
      doubled : W.Words = W.shl(remainder, 1)
      +step : DivisionStep = division_step(doubled, divisor)
      bit : U32 = division_quotient_bit(step)
      next_quotient : W.Words = W.bit_or(W.shl(quotient, 1), W.Words{0, bit})
      quotient_steps(rest, division_remainder(step), divisor, next_quotient)

def quotient_value(value: DivisionStep) -> W.Words:
  match value:
    case DivisionStep{+quotient, remainder}:
      Bool.pick(W.Words, W.long_zero(remainder), quotient, W.bit_or(quotient, W.Words{0, 1}))

def quotient_ratio(sign: U32, +exponent: U32, +numerator: W.Words, +denominator: W.Words) -> W.Words:
  +ge = Bool.not(W.unsigned_less(numerator, denominator))
  +adjusted_exponent = Bool.pick(U32, ge, exponent, U32.sub(exponent, 1))
  +remainder = Bool.pick(W.Words, ge, W.sub(numerator, denominator), W.sub(W.shl(numerator, 1), denominator))
  result : DivisionStep = quotient_steps(55n, remainder, denominator, W.Words{0, 1})
  double_pack64(sign, adjusted_exponent, quotient_value(result))
def quotient_value_entry(sign: U32, +a: Decoded, +b: Decoded) -> W.Words:
  +numerator = decoded_significand(a)
  +denominator = decoded_significand(b)
  +quotient_exponent = U32.sub(decoded_raw_exponent(a), decoded_raw_exponent(b))
  quotient_ratio(sign, quotient_exponent, numerator, denominator)


def division_by_kind(kind_a: U32, kind_b: U32, +decoded_a: Decoded, +decoded_b: Decoded, sign: U32) -> W.Words:
  match kind_a kind_b:
    case 3 _: nan_value()
    case _ 3: nan_value()
    case 2 2: nan_value()
    case 0 0: nan_value()
    case 2 _: infinity(sign)
    case _ 2: zero(sign)
    case _ 0: infinity(sign)
    case 0 _: zero(sign)
    case _ _: quotient_value_entry(sign, decoded_a, decoded_b)

def division(a: W.Words, b: W.Words) -> W.Words:
  +decoded_a = unpack(a)
  +decoded_b = unpack(b)
  +kind_a = decoded_kind(decoded_a)
  +kind_b = decoded_kind(decoded_b)
  +sign = U32.xor(decoded_sign(decoded_a), decoded_sign(decoded_b))
  division_by_kind(kind_a, kind_b, decoded_a, decoded_b, sign)

def div(a: W.Words, b: W.Words) -> W.Words:
  division(a, b)



@unsafe def modulus_bits(steps: Nat, +bit: U32, +value: W.Words, +divisor: W.Words, remainder: W.Words) -> W.Words:
  match steps:
    case 0n: remainder
    case 1n+rest:
      current : U32 = U32.and(low_word(W.shr(value, bit)), 1)
      +shifted : W.Words = W.bit_or(W.shl(remainder, 1), W.Words{0, current})
      next : W.Words = Bool.pick(W.Words, W.unsigned_less(shifted, divisor), shifted, W.sub(shifted, divisor))
      modulus_bits(rest, U32.sub(bit, 1), value, divisor, next)

@unsafe def modulus_zero_steps(steps: Nat, +divisor: W.Words, remainder: W.Words) -> W.Words:
  match steps:
    case 0n: remainder
    case 1n+rest:
      +shifted : W.Words = W.shl(remainder, 1)
      next : W.Words = Bool.pick(W.Words, W.unsigned_less(shifted, divisor), shifted, W.sub(shifted, divisor))
      modulus_zero_steps(rest, divisor, next)

def exact_remainder(sign: U32, exponent: U32, +value: W.Words) -> W.Words:
  +top = top_bit(value)
  +shift = U32.sub(52, top)
  +significand = W.shl(value, shift)
  +adjusted = U32.sub(exponent, shift)
  double_pack64(sign, adjusted, W.shl(significand, 3))

def finite_remainder_compute(sign: U32, exponent: U32, difference: U32, significand_a: W.Words, +significand_b: W.Words) -> W.Words:
  +initial = modulus_bits(53n, 52, significand_a, significand_b, W.Words{0, 0})
  +remainder = modulus_zero_steps(U32.to_nat(difference), significand_b, initial)
  exact_remainder(sign, exponent, remainder)

# Generated Bool.pick evaluates both arms; these dispatchers use match so the
# remainder loop never runs with a wrapped (negative) exponent difference.
def finite_remainder_same_value(same_value: Bool, sign: U32, exponent: U32, +difference: U32, +significand_a: W.Words, +significand_b: W.Words, +decoded_a: Decoded) -> W.Words:
  match same_value:
    case True{}: zero(decoded_sign(decoded_a))
    case False{}: finite_remainder_compute(sign, exponent, difference, significand_a, significand_b)

def finite_remainder_same_exponent(+a: W.Words, sign: U32, exponent: U32, +difference: U32, +significand_a: W.Words, +significand_b: W.Words, +decoded_a: Decoded) -> W.Words:
  finite_remainder_same_value(U32.is_eq(difference, 0) && raw_equal(significand_a, significand_b), sign, exponent, difference, significand_a, significand_b, decoded_a)

def finite_remainder_smaller(smaller: Bool, +a: W.Words, sign: U32, exponent: U32, +difference: U32, +significand_a: W.Words, +significand_b: W.Words, +decoded_a: Decoded) -> W.Words:
  match smaller:
    case True{}: a
    case False{}: finite_remainder_same_exponent(a, sign, exponent, difference, significand_a, significand_b, decoded_a)

def finite_remainder_ordered(+a: W.Words, sign: U32, exponent: U32, +difference: U32, +significand_a: W.Words, +significand_b: W.Words, +decoded_a: Decoded) -> W.Words:
  finite_remainder_smaller(U32.is_eq(difference, 0) && W.unsigned_less(significand_a, significand_b), a, sign, exponent, difference, significand_a, significand_b, decoded_a)

def finite_remainder_exponents(less: Bool, +a: W.Words, sign: U32, exponent: U32, +difference: U32, +significand_a: W.Words, +significand_b: W.Words, +decoded_a: Decoded) -> W.Words:
  match less:
    case True{}: a
    case False{}: finite_remainder_ordered(a, sign, exponent, difference, significand_a, significand_b, decoded_a)

def finite_remainder(+a: W.Words, +decoded_a: Decoded, +decoded_b: Decoded) -> W.Words:
  +ea = decoded_raw_exponent(decoded_a)
  +eb = decoded_raw_exponent(decoded_b)
  +significand_a = decoded_significand(decoded_a)
  +significand_b = decoded_significand(decoded_b)
  +difference = U32.sub(ea, eb)
  finite_remainder_exponents(exponent_less(ea, eb), a, decoded_sign(decoded_a), eb, difference, significand_a, significand_b, decoded_a)

def remainder_by_kind(kind_a: U32, kind_b: U32, +a: W.Words, +decoded_a: Decoded, +decoded_b: Decoded) -> W.Words:
  match kind_a kind_b:
    case 3 _: nan_value()
    case 2 _: nan_value()
    case _ 3: nan_value()
    case _ 2: a
    case _ 0: nan_value()
    case 0 _: a
    case _ _: finite_remainder(a, decoded_a, decoded_b)

def rem(+a: W.Words, +b: W.Words) -> W.Words:
  +decoded_a = unpack(a)
  +decoded_b = unpack(b)
  +kind_a = decoded_kind(decoded_a)
  +kind_b = decoded_kind(decoded_b)
  remainder_by_kind(kind_a, kind_b, a, decoded_a, decoded_b)

# Compare finite double values without converting their words to a host float.
def compare_ordered(+a: W.Words, +b: W.Words) -> U32:
  +both_zero = is_zero(a) && is_zero(b)
  +sign_a = sign_bit(a)
  +sign_b = sign_bit(b)
  +same_sign = U32.is_eq(sign_a, sign_b)
  +less = W.unsigned_less(a, b)
  +greater = W.unsigned_less(b, a)
  same_sign_result : U32 = Bool.pick(U32, U32.is_ne(sign_a, 0),
    Bool.pick(U32, less, 1, Bool.pick(U32, greater, 4294967295, 0)),
    Bool.pick(U32, less, 4294967295, Bool.pick(U32, greater, 1, 0)))
  sign_result : U32 = Bool.pick(U32, U32.is_ne(sign_a, 0), 4294967295, 1)
  Bool.pick(U32, both_zero, 0, Bool.pick(U32, same_sign, same_sign_result, sign_result))

def cmpg(+a: W.Words, +b: W.Words) -> U32:
  Bool.pick(U32, double_is_nan(a) || double_is_nan(b), 1, compare_ordered(a, b))

def cmpl(+a: W.Words, +b: W.Words) -> U32:
  Bool.pick(U32, double_is_nan(a) || double_is_nan(b), 4294967295, compare_ordered(a, b))

# Integer-to-floating conversions round once, directly from the integer bits.
def signed_magnitude(+value: W.Words) -> W.Words:
  Bool.pick(W.Words, U32.is_ne(sign_bit(value), 0), W.neg(value), value)

def integer_to_double(sign: U32, +magnitude: W.Words) -> W.Words:
  +top = top_bit(magnitude)
  +extended = Bool.pick(W.Words, U32.is_ge(top, 55), shift_right_jam(magnitude, U32.sub(top, 55)), W.shl(magnitude, U32.sub(55, top)))
  double_pack64(sign, top, extended)

def long_to_double(+value: W.Words) -> W.Words:
  integer_to_double(sign_bit(value), signed_magnitude(value))

def int_to_double(value: U32) -> W.Words:
  long_to_double(W.int_to_long(value))

def integer_to_float(sign: U32, +magnitude: W.Words) -> U32:
  +top = top_bit(magnitude)
  +extended = Bool.pick(W.Words, U32.is_ge(top, 26), shift_right_jam(magnitude, U32.sub(top, 26)), W.shl(magnitude, U32.sub(26, top)))
  float_pack32(sign, top, extended)

def long_to_float(+value: W.Words) -> U32:
  integer_to_float(sign_bit(value), signed_magnitude(value))

def f32_subnormal_to_double(sign: U32, fraction_bits: U32) -> W.Words:
  +fraction_words : W.Words = W.Words{0, fraction_bits}
  +top = top_bit(fraction_words)
  +shift = U32.sub(23, top)
  +significand = W.shl(fraction_words, shift)
  +exponent = U32.sub(U32.sub(0, 126), shift)
  double_pack64(sign, exponent, W.shl(W.shl(significand, 29), 3))

def f32_normal_to_double(sign: U32, raw_exponent: U32, fraction_bits: U32) -> W.Words:
  +significand = U32.or(fraction_bits, 8388608)
  +exponent = U32.sub(raw_exponent, 127)
  double_pack64(sign, exponent, W.shl(W.shl(W.Words{0, significand}, 29), 3))

def f32_finite_to_double(+sign: U32, +raw_exponent: U32, +fraction_bits: U32) -> W.Words:
  +zero_value = U32.is_eq(raw_exponent, 0) && U32.is_eq(fraction_bits, 0)
  +zero_exponent = U32.is_eq(raw_exponent, 0)
  Bool.pick(W.Words, zero_value, zero(sign),
    Bool.pick(W.Words, zero_exponent,
      f32_subnormal_to_double(sign, fraction_bits),
      f32_normal_to_double(sign, raw_exponent, fraction_bits)))

def f32_bits_to_double(+bits: U32) -> W.Words:
  +sign = U32.and(bits, 2147483648)
  +raw_exponent = U32.and(U32.shrn(bits, 23n), 255)
  +fraction_bits = U32.and(bits, 8388607)
  +special_exponent = U32.is_eq(raw_exponent, 255)
  Bool.pick(W.Words, special_exponent,
    Bool.pick(W.Words, U32.is_eq(fraction_bits, 0), infinity(sign), nan_value()),
    f32_finite_to_double(sign, raw_exponent, fraction_bits))

def float_to_double(bits: U32) -> W.Words:
  f32_bits_to_double(bits)

# Floating-to-integer conversion truncates toward zero and saturates as Java requires.
def finite_to_long(+decoded: Decoded) -> W.Words:
  +exponent = decoded_raw_exponent(decoded)
  +sign = decoded_sign(decoded)
  +significand = decoded_significand(decoded)
  +negative_exponent = exponent_less(exponent, 0)
  +saturated = exponent_ge(exponent, 63)
  +magnitude = Bool.pick(W.Words, U32.is_ge(exponent, 52), W.shl(significand, U32.sub(exponent, 52)), W.shr(significand, U32.sub(52, exponent)))
  +signed = Bool.pick(W.Words, U32.is_ne(sign, 0), W.neg(magnitude), magnitude)
  +saturated_value = Bool.pick(W.Words, U32.is_ne(sign, 0), W.Words{2147483648, 0}, W.Words{2147483647, 4294967295})
  Bool.pick(W.Words, negative_exponent, W.Words{0, 0}, Bool.pick(W.Words, saturated, saturated_value, signed))

def double_to_long_kind(kind: U32, sign: U32, exponent: U32, significand: W.Words) -> W.Words:
  match kind:
    case 3: W.Words{0, 0}
    case 2: Bool.pick(W.Words, U32.is_ne(sign, 0), W.Words{2147483648, 0}, W.Words{2147483647, 4294967295})
    case 0: W.Words{0, 0}
    case 1: finite_to_long(Decoded{1, sign, exponent, significand})
    case _: W.Words{0, 0}

def double_to_long_decoded(decoded: Decoded) -> W.Words:
  match decoded:
    case Decoded{kind, sign, exponent, significand}: double_to_long_kind(kind, sign, exponent, significand)
def double_to_long(value: W.Words) -> W.Words:
  double_to_long_decoded(unpack(value))

def finite_to_int(+decoded: Decoded) -> U32:
  +exponent = decoded_raw_exponent(decoded)
  +sign = decoded_sign(decoded)
  +negative_exponent = exponent_less(exponent, 0)
  +saturated = exponent_ge(exponent, 31)
  converted : U32 = W.long_to_int(finite_to_long(decoded))
  saturated_value : U32 = Bool.pick(U32, U32.is_ne(sign, 0), 2147483648, 2147483647)
  Bool.pick(U32, negative_exponent, 0, Bool.pick(U32, saturated, saturated_value, converted))

def double_to_int_kind(kind: U32, sign: U32, exponent: U32, significand: W.Words) -> U32:
  match kind:
    case 3: 0
    case 2: Bool.pick(U32, U32.is_ne(sign, 0), 2147483648, 2147483647)
    case 0: 0
    case 1: finite_to_int(Decoded{1, sign, exponent, significand})
    case _: 0

def double_to_int_decoded(decoded: Decoded) -> U32:
  match decoded:
    case Decoded{kind, sign, exponent, significand}: double_to_int_kind(kind, sign, exponent, significand)

def double_to_int(value: W.Words) -> U32:
  double_to_int_decoded(unpack(value))

def double_to_f32_kind(kind: U32, sign: U32, exponent: U32, significand: W.Words) -> U32:
  match kind:
    case 3: 2143289344
    case 2: U32.or(sign, 2139095040)
    case 0: sign
    case 1:
      extended : W.Words = shift_right_jam(W.shl(significand, 3), 29)
      float_pack32(sign, exponent, extended)
    case _: 2143289344

def double_to_f32_decoded(decoded: Decoded) -> U32:
  match decoded:
    case Decoded{kind, sign, exponent, significand}: double_to_f32_kind(kind, sign, exponent, significand)

def double_to_f32(value: W.Words) -> U32:
  double_to_f32_decoded(unpack(value))

def float_to_long(bits: U32) -> W.Words:
  double_to_long(f32_bits_to_double(bits))

def double_to_string(value: W.Words) -> Result<&2, &2, String, String>:
  DF.format(value)
