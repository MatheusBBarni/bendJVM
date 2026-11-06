import Base

# Little-endian base-2^32 limbs. Values returned by this module are normalized:
# the empty list is zero, and a nonempty list has a nonzero final limb.
# Construction and arithmetic are bounded to 40 limbs (1280 bits).
type BigUint is Data:
  BigUint{limbs: +List<U32>}

type BigResult is Data:
  BigOk{value: BigUint}
  BigOverflow{}
  BigUnderflow{}

type DivMod is Data:
  DivMod{quotient: BigUint, remainder: U32}


# 0 means equal, 1 means less, and 2 means greater.
def zero() -> BigUint:
  BigUint{Nil{}}

def is_zero(value: BigUint) -> Bool:
  match value:
    case BigUint{Nil{}}: True{}
    case BigUint{_}: False{}

# All internal callers provide at most 40 limbs; fuel makes the bound explicit.
def trim_high_result(+head: U32, tail: +List<U32>) -> +List<U32>:
  match tail:
    case Nil{}: Bool.pick(+List<U32>, U32.is_eq(head, 0), Nil{}, Con{head, Nil{}})
    case Con{next, rest}: Con{head, Con{next, rest}}

@unsafe def trim_high_go(fuel: Nat, limbs: +List<U32>) -> +List<U32>:
  match fuel limbs:
    case _ Nil{}: Nil{}
    case 0n _: limbs
    case 1n+p Con{head, rest}: trim_high_result(head, trim_high_go(p, rest))

def trim_high(limbs: +List<U32>) -> +List<U32>:
  trim_high_go(40n, limbs)
# Processes at most 40 limbs; an input with further limbs is rejected.
def normalize_high_result(+head: U32, result: BigResult) -> BigResult:
  match result:
    case BigOverflow{}: BigOverflow{}
    case BigUnderflow{}: BigUnderflow{}
    case BigOk{BigUint{tail}}:
      match tail:
        case Nil{}: BigOk{BigUint{Bool.pick(+List<U32>, U32.is_eq(head, 0), Nil{}, Con{head, Nil{}})}}
        case Con{next, rest}: BigOk{BigUint{Con{head, Con{next, rest}}}}

@unsafe def normalize_go(fuel: Nat, limbs: +List<U32>) -> BigResult:
  match fuel limbs:
    case _ Nil{}: BigOk{BigUint{trim_high(limbs)}}
    case 0n Con{_, _}: BigOverflow{}
    case 1n+p Con{head, rest}: normalize_high_result(head, normalize_go(p, rest))

def from_limbs(limbs: +List<U32>) -> BigResult:
  normalize_go(40n, limbs)

def from_u32(+value: U32) -> BigUint:
  BigUint{Bool.pick(+List<U32>, U32.is_eq(value, 0), Nil{}, Con{value, Nil{}})}

def equal(a: BigUint, b: BigUint) -> Bool:
  match a b:
    case BigUint{Nil{}} BigUint{Nil{}}: True{}
    case BigUint{Con{ah, at}} BigUint{Con{bh, bt}}:
      U32.is_eq(ah, bh) && equal(BigUint{at}, BigUint{bt})
    case _ _: False{}

# Compare little-endian canonical lists by length, then by their most
# significant differing limb.
@unsafe def length_go(n: Nat, xs: +List<U32>, length: U32) -> U32:
  match n xs:
    case 0n _: length
    case 1n+p Nil{}: length
    case 1n+p Con{head, rest}: length_go(p, rest, U32.add(length, 1))

def limb_length(xs: +List<U32>) -> U32:
  length_go(40n, xs, 0)

def compare_deeper(deeper: U32, +left: U32, +right: U32) -> U32:
  match deeper:
    case 1: 1
    case 2: 2
    case _: Bool.pick(U32, U32.is_lt(left, right), 1, Bool.pick(U32, U32.is_gt(left, right), 2, 0))

@unsafe def compare_rev(n: Nat, a: +List<U32>, b: +List<U32>) -> U32:
  match n a b:
    case 0n _ _: 0
    case 1n+p Nil{} Nil{}: 0
    case 1n+p Con{ah, at} Con{bh, bt}:
      compare_deeper(compare_rev(p, at, bt), ah, bh)
    case _ _ _: 0

def compare(a: BigUint, b: BigUint) -> U32:
  match a b:
    case BigUint{+al} BigUint{+bl}:
      +alen = limb_length(al)
      +blen = limb_length(bl)
      Bool.pick(U32, U32.is_lt(alen, blen), 1,
        Bool.pick(U32, U32.is_gt(alen, blen), 2, compare_rev(40n, al, bl)))

# Tail-recursive bounded list reversal. Public lists are capped at 40 limbs.
@unsafe def reverse_go(n: Nat, xs: +List<U32>, acc: +List<U32>) -> +List<U32>:
  match n xs:
    case 0n _: acc
    case 1n+p Nil{}: acc
    case 1n+p Con{head, rest}: reverse_go(p, rest, Con{head, acc})

def reverse_limbs(xs: +List<U32>) -> +List<U32>:
  reverse_go(40n, xs, Nil{})

@unsafe def add_go(n: Nat, a: +List<U32>, b: +List<U32>, carry: U32, acc: +List<U32>) -> BigResult:
  match n a b:
    case 0n Nil{} Nil{}:
      match carry:
        case 0: BigOk{BigUint{reverse_limbs(acc)}}
        case _: BigOverflow{}
    case 0n _ _: BigOverflow{}
    case 1n+p Nil{} Nil{}:
      match carry:
        case 0: BigOk{BigUint{reverse_limbs(acc)}}
        case 1: BigOk{BigUint{reverse_limbs(Con{carry, acc})}}
        case _: BigOverflow{}
    case 1n+p Con{+ah, at} Nil{}:
      +sum = (ah + carry : U32)
      next : U32 = Bool.to_u32(U32.is_lt(sum, ah))
      add_go(p, at, Nil{}, next, Con{sum, acc})
    case 1n+p Nil{} Con{+bh, bt}:
      +sum = (bh + carry : U32)
      next : U32 = Bool.to_u32(U32.is_lt(sum, bh))
      add_go(p, Nil{}, bt, next, Con{sum, acc})
    case 1n+p Con{+ah, at} Con{bh, bt}:
      +partial = (ah + bh : U32)
      c1 : U32 = Bool.to_u32(U32.is_lt(partial, ah))
      +sum = (partial + carry : U32)
      c2 : U32 = Bool.to_u32(U32.is_lt(sum, partial))
      add_go(p, at, bt, U32.or(c1, c2), Con{sum, acc})

def add(a: BigUint, b: BigUint) -> BigResult:
  match a b:
    case BigUint{al} BigUint{bl}: add_go(40n, al, bl, 0, Nil{})

@unsafe def sub_go(n: Nat, a: +List<U32>, b: +List<U32>, +borrow: U32, acc: +List<U32>) -> BigUint:
  match n a b:
    case 0n _ _: BigUint{trim_high(reverse_limbs(acc))}
    case 1n+p Nil{} Nil{}: BigUint{trim_high(reverse_limbs(acc))}
    case 1n+p Con{+ah, at} Nil{}:
      under : Bool = U32.is_lt(ah, borrow)
      sub_go(p, at, Nil{}, Bool.to_u32(under), Con{(ah - borrow : U32), acc})
    case 1n+p Nil{} Con{_, _}: BigUint{trim_high(reverse_limbs(acc))}
    case 1n+p Con{+ah, at} Con{+bh, bt}:
      +partial = (ah - bh : U32)
      b1 : Bool = U32.is_lt(ah, bh)
      +result = (partial - borrow : U32)
      b2 : Bool = U32.is_lt(partial, borrow)
      sub_go(p, at, bt, Bool.to_u32(b1 || b2), Con{result, acc})

# Precondition: a >= b. The checked form reports violated preconditions.
def subtract_ordered(order: U32, a: BigUint, b: BigUint) -> BigResult:
  match order:
    case 1: BigUnderflow{}
    case _: match a b:
      case BigUint{al} BigUint{bl}: BigOk{sub_go(40n, al, bl, 0, Nil{})}

def subtract_checked(+a: BigUint, +b: BigUint) -> BigResult:
  subtract_ordered(compare(a, b), a, b)


def sub(a: BigUint, b: BigUint) -> BigResult:
  subtract_checked(a, b)

# A carry out of the top limb becomes a new limb while the 40-limb bound allows it.
@unsafe def shift_left_one_go(n: Nat, limbs: +List<U32>, carry: U32, acc: +List<U32>) -> BigResult:
  match n limbs:
    case 0n Nil{}:
      match carry:
        case 0: BigOk{BigUint{reverse_limbs(acc)}}
        case _: BigOverflow{}
    case 1n+p Nil{}:
      match carry:
        case 0: BigOk{BigUint{reverse_limbs(acc)}}
        case _: BigOk{BigUint{reverse_limbs(Con{carry, acc})}}
    case 0n Con{_, _}: BigOverflow{}
    case 1n+p Con{+head, rest}:
      next : U32 = U32.shrn(head, 31n)
      word : U32 = U32.or(U32.shl(head), carry)
      shift_left_one_go(p, rest, next, Con{word, acc})
# Shift one bit without any wide intermediate; carry is a single high bit.
def shift_left_one(value: BigUint) -> BigResult:
  match value:
    case BigUint{limbs}:
      shift_left_one_go(40n, limbs, 0, Nil{})


# Shift by a bounded count using at most 1280 one-bit steps.
@unsafe def shl_progress(n: Nat, result: BigResult) -> BigResult:
  match n result:
    case 0n BigOverflow{}: BigOverflow{}
    case 0n BigOk{value}: BigOk{value}
    case 0n BigUnderflow{}: BigUnderflow{}
    case 1n+p BigOverflow{}: BigOverflow{}
    case 1n+p BigOk{value}: shl_progress(p, shift_left_one(value))
    case 1n+p BigUnderflow{}: BigUnderflow{}
@unsafe def shl_steps(n: Nat, value: BigUint) -> BigResult:
  shl_progress(n, BigOk{value})

def shl_count_result(allowed: Bool, count: U32, value: BigUint) -> BigResult:
  match allowed:
    case False{}: BigOverflow{}
    case True{}: shl_steps(U32.to_nat(count), value)

def shl(value: BigUint, +count: U32) -> BigResult:
  shl_count_result(U32.is_le(count, 1280), count, value)






@unsafe def shift_right_one_go(n: Nat, limbs: +List<U32>, carry: U32, acc: +List<U32>) -> +List<U32>:
  match n limbs:
    case _ Nil{}: acc
    case 0n _: acc
    case 1n+p Con{+head, rest}:
      next : U32 = U32.and(head, 1)
      word : U32 = U32.or(U32.shrn(head, 1n), U32.shln(carry, 31n))
      shift_right_one_go(p, rest, next, Con{word, acc})

@unsafe def shift_right_one(value: BigUint) -> BigUint:
  match value:
    case BigUint{limbs}: BigUint{trim_high(shift_right_one_go(40n, reverse_limbs(limbs), 0, Nil{}))}

@unsafe def shr_steps(n: Nat, value: BigUint) -> BigUint:
  match n:
    case 0n: value
    case 1n+p: shr_steps(p, shift_right_one(value))

def shr_count_result(allowed: Bool, count: U32, value: BigUint) -> BigUint:
  match allowed:
    case False{}: zero()
    case True{}: shr_steps(U32.to_nat(count), value)

def shr(value: BigUint, +count: U32) -> BigUint:
  shr_count_result(U32.is_le(count, 1280), count, value)



# Division is bit-serial: remainder is always less than divisor, and each
# intermediate is formed with U32 operations only. Divisor zero is rejected.
type DivisionStep is Data:
  DivisionStep{remainder: U32, quotientBit: U32}

def div_bit(+remainder: U32, bit: U32, +divisor: U32) -> DivisionStep:
  # When remainder's top bit is set, the mathematical shifted value is >= any
  # U32 divisor; subtracting modulo 2^32 yields the exact reduced remainder.
  +shifted : U32 = U32.or(U32.shl(remainder), bit)
  overflow : Bool = U32.is_ge(remainder, 2147483648)
  +take : Bool = overflow || U32.is_ge(shifted, divisor)
  DivisionStep{Bool.pick(U32, take, (shifted - divisor : U32), shifted), Bool.to_u32(take)}

type LimbDivision is Data:
  LimbDivision{quotient: U32, remainder: U32}

def div_step_rem(step: DivisionStep) -> U32:
  match step: case DivisionStep{remainder, quotientBit}: remainder
def div_step_bit(step: DivisionStep) -> U32:
  match step: case DivisionStep{remainder, quotientBit}: quotientBit
def div_rem(part: LimbDivision) -> U32:
  match part: case LimbDivision{quotient, remainder}: remainder
def div_quot(part: LimbDivision) -> U32:
  match part: case LimbDivision{quotient, remainder}: quotient

@unsafe def div_limb(n: Nat, +word: U32, +divisor: U32, rem: U32, quotient: U32) -> LimbDivision:
  match n:
    case 0n: LimbDivision{quotient, rem}
    case 1n++p:
      bit : U32 = U32.and(U32.shrn(word, p), 1)
      +step : DivisionStep = div_bit(rem, bit, divisor)
      div_limb(p, word, divisor, div_step_rem(step),
        U32.or(U32.shln(quotient, 1n), div_step_bit(step)))

@unsafe def divmod_go(n: Nat, limbs: +List<U32>, +divisor: U32, remainder: U32, acc: +List<U32>) -> DivMod:
  match n limbs:
    case _ Nil{}: DivMod{BigUint{trim_high(acc)}, remainder}
    case 0n _: DivMod{BigUint{trim_high(acc)}, remainder}
    case 1n++p Con{head, rest}:
      # Consume bits MSB-first in each limb; quotient limbs retain that order.
      +part : LimbDivision = div_limb(32n, head, divisor, remainder, 0)
      divmod_go(p, rest, divisor, div_rem(part), Con{div_quot(part), acc})

def divmod_zero_result(isZero: Bool, value: BigUint, divisor: U32) -> Maybe<&2, DivMod>:
  match isZero:
    case True{}: None{}
    case False{}:
      match value:
        case BigUint{limbs}: Some{divmod_go(40n, reverse_limbs(limbs), divisor, 0, Nil{})}

def divmod_u32(value: BigUint, +divisor: U32) -> Maybe<&2, DivMod>:
  divmod_zero_result(U32.is_eq(divisor, 0), value, divisor)

def div_u32_result(found: Maybe<&2, DivMod>) -> Maybe<&2, BigUint>:
  match found:
    case None{}: None{}
    case Some{DivMod{quotient, remainder}}: Some{quotient}


def div_u32(value: BigUint, divisor: U32) -> Maybe<&2, BigUint>:
  div_u32_result(divmod_u32(value, divisor))

def mod_u32_result(found: Maybe<&2, DivMod>) -> Maybe<&2, U32>:
  match found:
    case None{}: None{}
    case Some{DivMod{quotient, remainder}}: Some{remainder}


def mod_u32(value: BigUint, divisor: U32) -> Maybe<&2, U32>:
  mod_u32_result(divmod_u32(value, divisor))




type BigMulState is Data:
  MulContinue{multiplier: U32, shifted: BigUint, acc: BigUint}
  MulFinished{result: BigResult}

def mul_shift_finish(multiplier: U32, shifted: BigUint, next: BigUint, result: BigResult) -> BigMulState:
  match result:
    case BigOverflow{}: MulFinished{BigOverflow{}}
    case BigUnderflow{}: MulFinished{BigUnderflow{}}
    case BigOk{shiftedNext}: MulContinue{U32.shrn(multiplier, 1n), shiftedNext, next}

def mul_step_finish(multiplier: U32, +shifted: BigUint, next: BigUint, hasMore: Bool) -> BigMulState:
  match hasMore:
    case True{}: mul_shift_finish(multiplier, shifted, next, shift_left_one(shifted))
    case False{}: MulFinished{BigOk{next}}

def mul_step_result(+multiplier: U32, shifted: BigUint, result: BigResult) -> BigMulState:
  match result:
    case BigOverflow{}: MulFinished{BigOverflow{}}
    case BigUnderflow{}: MulFinished{BigUnderflow{}}
    case BigOk{next}:
      mul_step_finish(multiplier, shifted, next, U32.is_ne(U32.shrn(multiplier, 1n), 0))

def mul_step(+multiplier: U32, +shifted: BigUint, +acc: BigUint) -> BigMulState:
  mul_step_result(multiplier, shifted, Bool.pick(BigResult,
    U32.is_eq(U32.and(multiplier, 1), 1), add(acc, shifted), BigOk{acc}))

@unsafe def mul_bits(n: Nat, state: BigMulState) -> BigResult:
  match n state:
    case 0n MulFinished{result}: result
    case 0n MulContinue{_, _, _}: BigOverflow{}
    case 1n+p MulFinished{result}: result
    case 1n+p MulContinue{multiplier, shifted, acc}:
      mul_bits(p, mul_step(multiplier, shifted, acc))

def mul_u32(value: BigUint, +multiplier: U32) -> BigResult:
  Bool.pick(BigResult, U32.is_eq(multiplier, 0), BigOk{zero()},
    mul_bits(32n, MulContinue{multiplier, value, zero()}))

# Return the least-significant decimal digit and quotient, useful to callers
# building decimal digits without an intermediate decimal integer string.
def decimal_digit(value: BigUint) -> Maybe<&2, DivMod>:
  divmod_u32(value, 10)

def decimal_zero_result(acc: +List<Char>) -> +List<Char>:
  match acc:
    case Nil{}: [Chr{48}]
    case Con{head, rest}: Con{head, rest}

@unsafe def decimal_chars(n: Nat, value: BigUint, acc: +List<Char>, found: Maybe<&2, DivMod>) -> +List<Char>:
  match n value found:
    case 0n _ _: acc
    case 1n+p BigUint{Nil{}} _: decimal_zero_result(acc)
    case 1n+p _ None{}: acc
    case 1n+p _ Some{DivMod{+quotient, remainder}}:
      decimal_chars(p, quotient, Con{Chr{(48 + remainder : U32)}, acc}, decimal_digit(quotient))




def to_decimal(+value: BigUint) -> String:
  String.from_list(decimal_chars(386n, value, Nil{}, decimal_digit(value)))

# Bit-serial division by a BigUint. The temporary remainder has a separate
# carry limb because 2*r+bit may momentarily be 1281 bits; after conditional
# subtraction the remainder is again strictly less than the <=1280-bit divisor.
type BigDivisionResult is Data:
  BigDivided{quotient: BigUint, remainder: BigUint}
  BigDivideByZero{}

type WideRemainder is Data:
  WideRemainder{high: U32, limbs: +List<U32>}
def wide_shift_insert(+bit: U32, shifted: WideRemainder) -> WideRemainder:
  match shifted:
    case WideRemainder{high, Nil{}}:
      WideRemainder{high, Bool.pick(+List<U32>, U32.is_eq(bit, 0), Nil{}, [bit])}
    case WideRemainder{high, Con{low, rest}}:
      WideRemainder{high, Con{U32.or(low, bit), rest}}

type BigDivisionStep is Data:
  BigDivisionStep{remainder: BigUint, quotientBit: U32}

type BigWordDivision is Data:
  BigWordDivision{quotient: U32, remainder: BigUint}

# The carry out of the top limb is a new limb; only a carry out of the 40th
# limb (bit 1280) is held in `high`.
@unsafe def wide_shift_go(n: Nat, limbs: +List<U32>, carry: U32, acc: +List<U32>) -> WideRemainder:
  match n limbs:
    case 0n _: WideRemainder{carry, reverse_limbs(acc)}
    case 1n+p Nil{}:
      match carry:
        case 0: WideRemainder{0, reverse_limbs(acc)}
        case _: WideRemainder{0, reverse_limbs(Con{carry, acc})}
    case 1n+p Con{+head, rest}:
      next : U32 = U32.shrn(head, 31n)
      word : U32 = U32.or(U32.shl(head), carry)
      wide_shift_go(p, rest, next, Con{word, acc})

def wide_shift_add(value: BigUint, bit: U32) -> WideRemainder:
  match value:
    case BigUint{limbs}:
      wide_shift_insert(bit, wide_shift_go(40n, limbs, 0, Nil{}))


def wide_ge(value: WideRemainder, divisor: BigUint) -> Bool:
  match value:
    case WideRemainder{high, limbs}:
      U32.is_ne(high, 0) || U32.is_ne(compare(BigUint{trim_high(limbs)}, divisor), 1)

@unsafe def wide_sub_go(n: Nat, a: +List<U32>, b: +List<U32>, +borrow: U32, acc: +List<U32>) -> +List<U32>:
  match n a b:
    case 0n _ _: reverse_limbs(acc)
    case 1n+p Nil{} Nil{}: reverse_limbs(acc)
    case 1n+p Con{+ah, at} Nil{}:
      first : U32 = (ah - borrow : U32)
      next : U32 = Bool.to_u32(U32.is_lt(ah, borrow))
      wide_sub_go(p, at, Nil{}, next, Con{first, acc})
    case 1n+p Nil{} Con{+bh, bt}:
      +first : U32 = (0 - bh : U32)
      b1 : Bool = U32.is_ne(bh, 0)
      result : U32 = (first - borrow : U32)
      b2 : Bool = U32.is_lt(first, borrow)
      wide_sub_go(p, Nil{}, bt, Bool.to_u32(b1 || b2), Con{result, acc})
    case 1n+p Con{+ah, at} Con{+bh, bt}:
      +partial : U32 = (ah - bh : U32)
      b1 : Bool = U32.is_lt(ah, bh)
      result : U32 = (partial - borrow : U32)
      b2 : Bool = U32.is_lt(partial, borrow)
      wide_sub_go(p, at, bt, Bool.to_u32(b1 || b2), Con{result, acc})

def wide_sub(value: WideRemainder, divisor: BigUint) -> BigUint:
  match value divisor:
    case WideRemainder{high, limbs} BigUint{divisor_limbs}:
      # wide_ge ensures low-word subtraction is nonnegative modulo 2^1280.
      BigUint{trim_high(wide_sub_go(40n, limbs, divisor_limbs, 0, Nil{}))}

def big_division_unsubtracted(wide: WideRemainder) -> BigDivisionStep:
  match wide:
    case WideRemainder{high, limbs}: BigDivisionStep{BigUint{trim_high(limbs)}, 0}

def big_division_compare(wide: WideRemainder, divisor: BigUint, atLeast: Bool) -> BigDivisionStep:
  match atLeast:
    case True{}: BigDivisionStep{wide_sub(wide, divisor), 1}
    case False{}:
      big_division_unsubtracted(wide)

def big_division_shifted(+divisor: BigUint, +wide: WideRemainder) -> BigDivisionStep:
  big_division_compare(wide, divisor, wide_ge(wide, divisor))

def big_division_shift_result(divisor: BigUint, result: WideRemainder) -> BigDivisionStep:
  big_division_shifted(divisor, result)

def big_division_step(value: BigUint, divisor: BigUint, bit: U32) -> BigDivisionStep:
  big_division_shift_result(divisor, wide_shift_add(value, bit))

def big_word_quotient(step: BigDivisionStep) -> U32:
  match step: case BigDivisionStep{remainder, quotientBit}: quotientBit

def big_word_remainder(step: BigDivisionStep) -> BigUint:
  match step: case BigDivisionStep{remainder, quotientBit}: remainder

@unsafe def big_div_word(n: Nat, +word: U32, +divisor: BigUint, remainder: BigUint, quotient: U32) -> BigWordDivision:
  match n:
    case 0n: BigWordDivision{quotient, remainder}
    case 1n++p:
      bit : U32 = U32.and(U32.shrn(word, p), 1)
      +step : BigDivisionStep = big_division_step(remainder, divisor, bit)
      big_div_word(p, word, divisor, big_word_remainder(step),
        U32.or(U32.shln(quotient, 1n), big_word_quotient(step)))

def big_word_q(value: BigWordDivision) -> U32:
  match value: case BigWordDivision{quotient, remainder}: quotient

def big_word_r(value: BigWordDivision) -> BigUint:
  match value: case BigWordDivision{quotient, remainder}: remainder

@unsafe def big_divmod_words(n: Nat, words: +List<U32>, +divisor: BigUint, remainder: BigUint, quotient: +List<U32>) -> BigDivisionResult:
  match n words:
    case _ Nil{}: BigDivided{BigUint{trim_high(quotient)}, remainder}
    case 0n _: BigDivided{BigUint{trim_high(quotient)}, remainder}
    case 1n+p Con{word, rest}:
      +part : BigWordDivision = big_div_word(32n, word, divisor, remainder, 0)
      big_divmod_words(p, rest, divisor, big_word_r(part), Con{big_word_q(part), quotient})

def big_divmod_nonzero(a: BigUint, b: BigUint) -> BigDivisionResult:
  match a:
    case BigUint{limbs}: big_divmod_words(40n, reverse_limbs(limbs), b, zero(), Nil{})

def divmod(a: BigUint, b: BigUint) -> BigDivisionResult:
  match b:
    case BigUint{Nil{}}: BigDivideByZero{}
    case BigUint{limbs}: big_divmod_nonzero(a, BigUint{limbs})
