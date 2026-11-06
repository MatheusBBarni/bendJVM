import Base
import ./wide.bend as W
import ./big_uint.bend as B

type Exact is Data:
  Exact{significand: B.BigUint, exponent: U32}

type Bounds is Data:
  Bounds{lower: Exact, upper: Exact, inclusive: Bool}

type Decimal is Data:
  Decimal{significand: B.BigUint, exponent: U32}

type Ratio is Data:
  Ratio{numerator: B.BigUint, denominator: B.BigUint}


# Scaled values are significand * 2^exponent2 * 5^exponent5. Signed
# exponents are represented in U32 two's-complement form.
def signed_less(a: U32, b: U32) -> Bool:
  U32.is_lt(U32.xor(a, 2147483648), U32.xor(b, 2147483648))

def signed_min(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, signed_less(a, b), a, b)

def checked_big(result: B.BigResult) -> Result<&2, &2, String, B.BigUint>:
  match result:
    case B.BigOk{value}: Done{value}
    case B.BigOverflow{}: Fail{"VmError.NumericFormatOverflow: 1280-bit integer bound exceeded"}
    case B.BigUnderflow{}: Fail{"VmError.NumericFormatUnderflow: invalid unsigned subtraction"}

@unsafe def multiply_fives(steps: Nat, value: B.BigUint) -> Result<&2, &2, String, B.BigUint>:
  match steps:
    case 0n: Done{value}
    case 1n+rest:
      do Result<&2, &2, String, B.BigUint>:
        next : B.BigUint <- checked_big(B.mul_u32(value, 5))
        result : B.BigUint <- multiply_fives(rest, next)
        return result

def scale_nonnegative(value: B.BigUint, power2: U32, power5: U32) -> Result<&2, &2, String, B.BigUint>:
  do Result<&2, &2, String, B.BigUint>:
    shifted : B.BigUint <- checked_big(B.shl(value, power2))
    result : B.BigUint <- multiply_fives(U32.to_nat(power5), shifted)
    return result

def scaled_compare(left: B.BigUint, +left2: U32, +left5: U32, right: B.BigUint, +right2: U32, +right5: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +minimum2 : U32 = signed_min(left2, right2)
    +minimum5 : U32 = signed_min(left5, right5)
    left_value : B.BigUint <- scale_nonnegative(left, U32.sub(left2, minimum2), U32.sub(left5, minimum5))
    right_value : B.BigUint <- scale_nonnegative(right, U32.sub(right2, minimum2), U32.sub(right5, minimum5))
    return B.compare(left_value, right_value)

def one() -> B.BigUint:
  B.from_u32(1)

def words_big(value: W.Words) -> Result<&2, &2, String, B.BigUint>:
  match value:
    case W.Words{high, low}: checked_big(B.from_limbs([low, high]))

def raw_exponent(value: W.Words) -> U32:
  match value:
    case W.Words{high, low}: U32.and(U32.shrn(high, 20n), 2047)

def raw_fraction(value: W.Words) -> W.Words:
  match value:
    case W.Words{high, low}: W.Words{U32.and(high, 1048575), low}

def positive_raw(value: W.Words) -> W.Words:
  match value:
    case W.Words{high, low}: W.Words{U32.and(high, 2147483647), low}

def normal_significand(value: W.Words) -> Result<&2, &2, String, B.BigUint>:
  match value:
    case W.Words{high, low}:
      words_big(W.Words{U32.or(high, 1048576), low})

def exact_from_exponent(exponent: U32, +value: W.Words) -> Result<&2, &2, String, Exact>:
  match exponent:
    case 2047:
      do Result<&2, &2, String, Exact>:
        significand : B.BigUint <- checked_big(B.from_limbs([0, 1048576]))
        return Exact{significand, 972}
    case 0:
      do Result<&2, &2, String, Exact>:
        significand : B.BigUint <- words_big(raw_fraction(value))
        return Exact{significand, U32.sub(0, 1074)}
    case exponent:
      do Result<&2, &2, String, Exact>:
        significand : B.BigUint <- normal_significand(raw_fraction(value))
        return Exact{significand, U32.sub(U32.sub(exponent, 1023), 52)}

def exact_from_raw(+value: W.Words) -> Result<&2, &2, String, Exact>:
  exact_from_exponent(raw_exponent(value), value)

def midpoint(left: Exact, right: Exact) -> Result<&2, &2, String, Exact>:
  match left right:
    case Exact{left_significand, +left_exponent} Exact{right_significand, +right_exponent}:
      do Result<&2, &2, String, Exact>:
        +common : U32 = signed_min(left_exponent, right_exponent)
        left_shifted : B.BigUint <- checked_big(B.shl(left_significand, U32.sub(left_exponent, common)))
        right_shifted : B.BigUint <- checked_big(B.shl(right_significand, U32.sub(right_exponent, common)))
        sum : B.BigUint <- checked_big(B.add(left_shifted, right_shifted))
        return Exact{sum, U32.sub(common, 1)}

def even_remainder(remainder: Maybe<&2, U32>) -> Result<&2, &2, String, Bool>:
  match remainder:
    case None{}: Fail{"VmError.NumericFormatDivisionByZero"}
    case Some{remainder}: Done{U32.is_eq(remainder, 0)}

def even_significand(value: B.BigUint) -> Result<&2, &2, String, Bool>:
  even_remainder(B.mod_u32(value, 2))

def exact_even_significand(value: Exact) -> Result<&2, &2, String, Bool>:
  match value:
    case Exact{significand, exponent}: even_significand(significand)

# B.compare returns 1 when the left operand is less than the right one.
def is_less(compared: U32) -> Bool:
  U32.is_eq(compared, 1)

def exact_compare_one(+value: Exact, +exponent: U32) -> Result<&2, &2, String, U32>:
  match value:
    case Exact{significand, exact_exponent}:
      scaled_compare(significand, exact_exponent, 0, one(), exponent, exponent)

# The search continues only while needed: generated Bool.pick is eager, so the
# continue/stop decision is a match on the comparison (a parameter), not a pick.
@unsafe def exponent_up(steps: Nat, +value: Exact, +exponent: U32) -> Result<&2, &2, String, U32>:
  match steps:
    case 0n: Done{exponent}
    case 1n+rest:
      +next : U32 = U32.add(exponent, 1)
      Result.bind(&2, &2, String, U32, U32, exact_compare_one(value, next),
        compared => exponent_up_decide(is_less(compared), rest, value, exponent, next))

@unsafe def exponent_up_decide(stop: Bool, steps: Nat, +value: Exact, +exponent: U32, +next: U32) -> Result<&2, &2, String, U32>:
  match stop:
    case True{}: Done{exponent}
    case False{}: exponent_up(steps, value, next)

@unsafe def exponent_down(steps: Nat, +value: Exact, exponent: U32) -> Result<&2, &2, String, U32>:
  match steps:
    case 0n: Done{exponent}
    case 1n+rest:
      +next : U32 = U32.sub(exponent, 1)
      Result.bind(&2, &2, String, U32, U32, exact_compare_one(value, next),
        compared => exponent_down_decide(is_less(compared), rest, value, next))

@unsafe def exponent_down_decide(below: Bool, steps: Nat, +value: Exact, +next: U32) -> Result<&2, &2, String, U32>:
  match below:
    case True{}: exponent_down(steps, value, next)
    case False{}: Done{next}

@unsafe def decimal_exponent_decide(below_one: Bool, +value: Exact) -> Result<&2, &2, String, U32>:
  match below_one:
    case True{}: exponent_down(325n, value, 0)
    case False{}: exponent_up(310n, value, 0)

@unsafe def decimal_exponent(+value: Exact) -> Result<&2, &2, String, U32>:
  Result.bind(&2, &2, String, U32, U32, exact_compare_one(value, 0),
    compared => decimal_exponent_decide(is_less(compared), value))


def rounding_bounds(value: W.Words) -> Result<&2, &2, String, Bounds>:
  do Result<&2, &2, String, Bounds>:
    +raw : W.Words = positive_raw(value)
    previous : W.Words = W.sub(raw, W.Words{0, 1})
    following : W.Words = W.add(raw, W.Words{0, 1})
    +exact : Exact <- exact_from_raw(raw)
    before : Exact <- exact_from_raw(previous)
    after : Exact <- exact_from_raw(following)
    lower : Exact <- midpoint(before, exact)
    upper : Exact <- midpoint(exact, after)
    inclusive : Bool <- exact_even_significand(exact)
    return Bounds{lower, upper, inclusive}

@unsafe def multiply_tens(steps: Nat, value: B.BigUint) -> Result<&2, &2, String, B.BigUint>:
  match steps:
    case 0n: Done{value}
    case 1n+rest:
      do Result<&2, &2, String, B.BigUint>:
        next : B.BigUint <- checked_big(B.mul_u32(value, 10))
        result : B.BigUint <- multiply_tens(rest, next)
        return result

def decimal_power(exponent: U32) -> Result<&2, &2, String, B.BigUint>:
  multiply_tens(U32.to_nat(exponent), one())

def ratio_power_two_negative(numerator: B.BigUint, denominator: B.BigUint, power: U32) -> Result<&2, &2, String, Ratio>:
  do Result<&2, &2, String, Ratio>:
    shifted : B.BigUint <- checked_big(B.shl(denominator, U32.sub(0, power)))
    return Ratio{numerator, shifted}

def ratio_power_two_positive(numerator: B.BigUint, denominator: B.BigUint, power: U32) -> Result<&2, &2, String, Ratio>:
  do Result<&2, &2, String, Ratio>:
    shifted : B.BigUint <- checked_big(B.shl(numerator, power))
    return Ratio{shifted, denominator}

def ratio_power_two_sign(negative: Bool, +numerator: B.BigUint, +denominator: B.BigUint, +power: U32) -> Result<&2, &2, String, Ratio>:
  match negative:
    case True{}: ratio_power_two_negative(numerator, denominator, power)
    case False{}: ratio_power_two_positive(numerator, denominator, power)

def ratio_power_two(+numerator: B.BigUint, +denominator: B.BigUint, +power: U32) -> Result<&2, &2, String, Ratio>:
  ratio_power_two_sign(signed_less(power, 0), numerator, denominator, power)

def ratio_power_five_sign(negative: Bool, +numerator: B.BigUint, +denominator: B.BigUint, +power: U32) -> Result<&2, &2, String, Ratio>:
  match negative:
    case True{}:
      do Result<&2, &2, String, Ratio>:
        shifted : B.BigUint <- multiply_fives(U32.to_nat(U32.sub(0, power)), denominator)
        return Ratio{numerator, shifted}
    case False{}:
      do Result<&2, &2, String, Ratio>:
        shifted : B.BigUint <- multiply_fives(U32.to_nat(power), numerator)
        return Ratio{shifted, denominator}

def ratio_power_five_parts(+numerator: B.BigUint, +denominator: B.BigUint, +power: U32) -> Result<&2, &2, String, Ratio>:
  ratio_power_five_sign(signed_less(power, 0), numerator, denominator, power)

def ratio_power_five(value: Ratio, power: U32) -> Result<&2, &2, String, Ratio>:
  match value:
    case Ratio{numerator, denominator}: ratio_power_five_parts(numerator, denominator, power)

def is_odd_remainder(remainder: Maybe<&2, U32>) -> Result<&2, &2, String, Bool>:
  match remainder:
    case None{}: Fail{"VmError.NumericFormatDivisionByZero"}
    case Some{bit}: Done{U32.is_ne(bit, 0)}

def is_odd(value: B.BigUint) -> Result<&2, &2, String, Bool>:
  is_odd_remainder(B.mod_u32(value, 2))

def rounded_choice(round_up: Bool, +quotient: B.BigUint) -> Result<&2, &2, String, B.BigUint>:
  Bool.pick(Result<&2, &2, String, B.BigUint>, round_up,
    checked_big(B.add(quotient, B.from_u32(1))),
    Done{quotient})

def rounded_choice_from_comparison(+comparison: U32, odd: Bool, +quotient: B.BigUint) -> Result<&2, &2, String, B.BigUint>:
  rounded_choice(U32.is_gt(comparison, 1) || (U32.is_eq(comparison, 0) && odd), quotient)

def rounded_result(division: B.BigDivisionResult, denominator: B.BigUint) -> Result<&2, &2, String, B.BigUint>:
  match division:
    case B.BigDivideByZero{}: Fail{"VmError.NumericFormatDivisionByZero"}
    case B.BigDivided{+quotient, remainder}:
      Result.bind(&2, &2, String, B.BigUint, B.BigUint, checked_big(B.shl(remainder, 1)),
        half_remainder =>
          Result.bind(&2, &2, String, Bool, B.BigUint, is_odd(quotient),
            odd => rounded_choice_from_comparison(B.compare(half_remainder, denominator), odd, quotient)))

def rounded_ratio(value: Ratio) -> Result<&2, &2, String, B.BigUint>:
  match value:
    case Ratio{numerator, +denominator}: rounded_result(B.divmod(numerator, denominator), denominator)

def decimal_quotient_parts(+significand: B.BigUint, source_exponent: U32, +exponent: U32) -> Result<&2, &2, String, B.BigUint>:
  do Result<&2, &2, String, B.BigUint>:
    power2 : U32 = U32.sub(source_exponent, exponent)
    power5 : U32 = U32.sub(0, exponent)
    initial : Ratio <- ratio_power_two(significand, one(), power2)
    scaled : Ratio <- ratio_power_five(initial, power5)
    rounded : B.BigUint <- rounded_ratio(scaled)
    return rounded

def decimal_quotient(+value: Exact, exponent: U32) -> Result<&2, &2, String, B.BigUint>:
  match value:
    case Exact{significand, source_exponent}:
      decimal_quotient_parts(significand, source_exponent, exponent)
def normalized_division(division: Maybe<&2, B.DivMod>, exponent: U32) -> Result<&2, &2, String, Decimal>:
  match division:
    case None{}: Fail{"VmError.NumericFormatDivisionByZero"}
    case Some{B.DivMod{quotient, remainder}}:
      Bool.pick(Result<&2, &2, String, Decimal>, U32.is_eq(remainder, 0),
        Done{Decimal{quotient, U32.add(exponent, 1)}},
        Fail{"VmError.NumericFormatOverflow: rounded significand exceeded precision"})

def normalized_by_comparison(comparison: U32, +value: B.BigUint, +exponent: U32) -> Result<&2, &2, String, Decimal>:
  Bool.pick(Result<&2, &2, String, Decimal>, U32.is_eq(comparison, 1),
    Done{Decimal{value, exponent}},
    normalized_division(B.divmod_u32(value, 10), exponent))

def normalized_decimal(+value: B.BigUint, exponent: U32, precision: U32) -> Result<&2, &2, String, Decimal>:
  Result.bind(&2, &2, String, B.BigUint, Decimal, decimal_power(precision),
    threshold => normalized_by_comparison(B.compare(value, threshold), value, exponent))

def candidate_compare(+significand: B.BigUint, +exponent: U32, bound: Exact) -> Result<&2, &2, String, U32>:
  match bound:
    case Exact{bound_significand, bound_exponent}:
      scaled_compare(significand, exponent, exponent, bound_significand, bound_exponent, 0)

def candidate_inside(+significand: B.BigUint, +exponent: U32, bounds: Bounds) -> Result<&2, &2, String, Bool>:
  match bounds:
    case Bounds{+lower, +upper, +inclusive}:
      do Result<&2, &2, String, Bool>:
        +low : U32 <- candidate_compare(significand, exponent, lower)
        +high : U32 <- candidate_compare(significand, exponent, upper)
        # B.compare: 0 equal, 1 less, 2 greater. Bounds are open unless the
        # significand is even (round-half-even makes both midpoints reachable).
        low_ok : Bool = U32.is_eq(low, 2) || (inclusive && U32.is_eq(low, 0))
        high_ok : Bool = U32.is_eq(high, 1) || (inclusive && U32.is_eq(high, 0))
        return low_ok && high_ok

def normalized_candidate_inside(normalized: Decimal, bounds: Bounds) -> Result<&2, &2, String, Bool>:
  match normalized:
    case Decimal{significand, exponent}: candidate_inside(significand, exponent, bounds)

@unsafe def shortest(steps: Nat, +precision: U32, +value: Exact, +exponent: U32, +bounds: Bounds) -> Result<&2, &2, String, Decimal>:
  match steps:
    case 0n: Fail{"VmError.NumericFormatFailure: no 17-digit round-trip representation"}
    case 1n+rest:
      +scale : U32 = U32.sub(exponent, U32.sub(precision, 1))
      Result.bind(&2, &2, String, B.BigUint, Decimal, decimal_quotient(value, scale),
        rounded_significand =>
          Result.bind(&2, &2, String, Decimal, Decimal, normalized_decimal(rounded_significand, scale, precision),
            +normalized =>
              Result.bind(&2, &2, String, Bool, Decimal, normalized_candidate_inside(normalized, bounds),
                accepted => shortest_decide(accepted, normalized, rest, U32.add(precision, 1), value, exponent, bounds))))

@unsafe def shortest_decide(accepted: Bool, +normalized: Decimal, steps: Nat, +precision: U32, +value: Exact, +exponent: U32, +bounds: Bounds) -> Result<&2, &2, String, Decimal>:
  match accepted:
    case True{}: Done{normalized}
    case False{}: shortest(steps, precision, value, exponent, bounds)

def take_chars(count: Nat, values: +List<Char>) -> +List<Char>:
  match count values:
    case 0n _: Nil{}
    case 1n+rest Con{head, tail}: Con{head, take_chars(rest, tail)}
    case _ Nil{}: Nil{}

@unsafe def drop_chars(count: Nat, values: +List<Char>) -> +List<Char>:
  match count values:
    case 0n _: values
    case 1n+rest Con{head, tail}: drop_chars(rest, tail)
    case _ Nil{}: Nil{}

@unsafe def zero_chars(count: Nat, acc: +List<Char>) -> +List<Char>:
  match count:
    case 0n: acc
    case 1n+rest: zero_chars(rest, Con{Chr{48}, acc})

def zeros(count: U32) -> String:
  String.from_list(zero_chars(U32.to_nat(count), Nil{}))

def signed_show(+value: U32) -> String:
  Bool.pick(String, signed_less(value, 0), "-" ++ U32.show(U32.sub(0, value)), U32.show(value))

def plain_state(negative_point: Bool, zero_point: Bool, point_after_digits: Bool, +digits: String, +characters: +List<Char>, +point: U32, length: U32) -> String:
  match negative_point zero_point point_after_digits:
    case True{} _ _: "0." ++ zeros(U32.sub(0, point)) ++ digits
    case False{} True{} _: "0." ++ digits
    case False{} False{} True{}: digits ++ zeros(U32.sub(point, length)) ++ ".0"
    case False{} False{} False{}:
      String.from_list(take_chars(U32.to_nat(point), characters)) ++ "." ++ String.from_list(drop_chars(U32.to_nat(point), characters))

def character_length(values: +List<Char>) -> U32:
  match values:
    case Nil{}: 0
    case Con{head, rest}: U32.add(character_length(rest), 1)

def plain(+digits: String, exponent: U32) -> String:
  +characters = String.to_list(digits)
  +length : U32 = character_length(characters)
  +point = U32.add(exponent, length)
  plain_state(signed_less(point, 0), U32.is_eq(point, 0), U32.is_ge(point, length), digits, characters, point, length)

def fraction_text(rest: +List<Char>) -> String:
  match rest:
    case Nil{}: "0"
    case _: String.from_list(rest)

def scientific_characters(characters: +List<Char>, exponent: U32) -> String:
  match characters:
    case Con{first, rest}:
      String.from_list([first]) ++ "." ++ fraction_text(rest) ++ "E" ++ signed_show(exponent)
    case Nil{}: "0.0E0"

def scientific(digits: String, exponent: U32) -> String:
  scientific_characters(String.to_list(digits), exponent)

def render_layout(too_small: Bool, small_enough: Bool, +digits: String, exponent: U32, order: U32) -> String:
  match too_small small_enough:
    case False{} True{}: plain(digits, exponent)
    case True{} _: scientific(digits, order)
    case _ _: scientific(digits, order)

def render(value: Decimal) -> String:
  match value:
    case Decimal{significand, +exponent}:
      +digits : String = B.to_decimal(significand)
      length : U32 = character_length(String.to_list(digits))
      +order : U32 = U32.add(exponent, U32.sub(length, 1))
      # Java uses plain notation for 10^-3 <= |x| < 10^7 (order is signed).
      render_layout(signed_less(order, U32.sub(0, 3)), signed_less(order, 7), digits, exponent, order)

def sign_prefix(sign: U32, +text: String) -> String:
  Bool.pick(String, U32.is_ne(sign, 0), "-" ++ text, text)

# Remove decimal trailing zeros so the rendered digits are canonical.
@unsafe def strip_zeros(steps: Nat, +value: Decimal) -> Decimal:
  match steps:
    case 0n: value
    case 1n+rest: strip_zeros_found(rest, value, decimal_division(value))

def decimal_division(value: Decimal) -> Maybe<&2, B.DivMod>:
  match value:
    case Decimal{significand, exponent}: B.divmod_u32(significand, 10)

@unsafe def strip_zeros_quotient(zero: Bool, steps: Nat, +value: Decimal, +quotient: B.BigUint) -> Decimal:
  match zero:
    case True{}: value
    case False{}: strip_zeros(steps, Decimal{quotient, U32.add(decimal_exponent_of(value), 1)})

@unsafe def strip_zeros_found(steps: Nat, +value: Decimal, found: Maybe<&2, B.DivMod>) -> Decimal:
  match found:
    case Some{B.DivMod{+quotient, 0}}: strip_zeros_quotient(B.is_zero(quotient), steps, value, quotient)
    case _: value

def decimal_exponent_of(value: Decimal) -> U32:
  match value:
    case Decimal{significand, exponent}: exponent

def decimal_significand(value: Decimal) -> B.BigUint:
  match value:
    case Decimal{significand, exponent}: significand

def is_single_digit(value: Decimal) -> Bool:
  U32.is_eq(B.compare(decimal_significand(value), B.from_u32(10)), 1)

# JDK 19+ Double.toString: when the shortest round-tripping decimal has one
# digit, choose the closest decimal of length one or two. The correctly rounded
# two-digit value is never farther from x, so it wins whenever it round-trips.
def two_digit_choice(+shortest_value: Decimal, +candidate: Decimal, inside: Bool) -> Decimal:
  Bool.pick(Decimal, inside, candidate, shortest_value)

def two_digit_candidate(+shortest_value: Decimal, +exact: Exact, +order: U32, +bounds: Bounds) -> Result<&2, &2, String, Decimal>:
  do Result<&2, &2, String, Decimal>:
    +scale : U32 = U32.sub(order, 1)
    rounded : B.BigUint <- decimal_quotient(exact, scale)
    +candidate : Decimal <- normalized_decimal(rounded, scale, 2)
    inside : Bool <- normalized_candidate_inside(candidate, bounds)
    return two_digit_choice(shortest_value, candidate, inside)

def refine_short(single: Bool, +shortest_value: Decimal, +exact: Exact, +order: U32, +bounds: Bounds) -> Result<&2, &2, String, Decimal>:
  match single:
    case False{}: Done{shortest_value}
    case True{}: two_digit_candidate(shortest_value, exact, order, bounds)

def finite_exact(+exact: Exact, value: W.Words, sign: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +even_bounds : Bounds <- rounding_bounds(value)
    +decimal_order : U32 <- decimal_exponent(exact)
    +shortest_value : Decimal <- shortest(17n, 1, exact, decimal_order, even_bounds)
    refined : Decimal <- refine_short(is_single_digit(shortest_value), shortest_value, exact, decimal_order, even_bounds)
    return sign_prefix(sign, render(strip_zeros(18n, refined)))

def finite(+value: W.Words, sign: U32) -> Result<&2, &2, String, String>:
  Result.bind(&2, &2, String, Exact, String, exact_from_raw(positive_raw(value)),
    exact => finite_exact(exact, value, sign))

def format_finite(zero_value: Bool, value: W.Words, sign: U32) -> Result<&2, &2, String, String>:
  match zero_value:
    case True{}: Done{sign_prefix(sign, "0.0")}
    case False{}: finite(value, sign)

def format_exponent(special: Bool, sign: U32, exponent: U32, fraction_high: U32, low: U32, value: W.Words) -> Result<&2, &2, String, String>:
  match special:
    case True{}:
      Bool.pick(Result<&2, &2, String, String>, U32.is_ne(fraction_high, 0) || U32.is_ne(low, 0), Done{"NaN"}, Done{sign_prefix(sign, "Infinity")})
    case False{}:
      format_finite(U32.is_eq(exponent, 0) && U32.is_eq(fraction_high, 0) && U32.is_eq(low, 0), value, sign)

def format(+value: W.Words) -> Result<&2, &2, String, String>:
  match value:
    case W.Words{+high, low}:
      sign = U32.and(high, 2147483648)
      +exponent = U32.and(U32.shrn(high, 20n), 2047)
      fraction_high = U32.and(high, 1048575)
      format_exponent(U32.is_eq(exponent, 2047), sign, exponent, fraction_high, low, value)

