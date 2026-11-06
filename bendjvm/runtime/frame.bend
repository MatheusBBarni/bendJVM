import Base
import ../model.bend as M
import ./state.bend as S

type Popped is Data:
  Popped{frame: M.Frame, value: M.Slot}

type Arguments is Data:
  Arguments{frame: M.Frame, values: +List<M.Slot>}

def valid_slot(slot: M.Slot) -> Bool:
  match slot:
    case M.Slot{+single_tag, bits}: U32.is_ge(single_tag, 1) && U32.is_le(single_tag, 3)
    case M.Wide{+wide_tag, high, low}: U32.is_ge(wide_tag, 4) && U32.is_le(wide_tag, 5)
    case M.Unusable{}: False{}

def category_one(slot: M.Slot) -> Bool:
  match slot:
    case M.Slot{+tag, bits}: U32.is_ge(tag, 1) && U32.is_le(tag, 3)
    case _: False{}

def category_two(slot: M.Slot) -> Bool:
  match slot:
    case M.Wide{+tag, high, low}: U32.is_ge(tag, 4) && U32.is_le(tag, 5)
    case _: False{}

def stack_width(stack: +List<M.Slot>) -> U32:
  match stack:
    case Nil{}: 0
    case Con{value, rest}: U32.add(M.slot_width(value), stack_width(rest))

def room(+used: U32, width: U32, +maximum: U32) -> Bool:
  Bool.pick(Bool, U32.is_le(used, maximum), U32.is_le(width, U32.sub(maximum, used)), False{})

def pop_stack(frame: M.Frame, +tag: U32, stack: +List<M.Slot>) -> Result<&2, &2, String, Popped>:
  match stack:
    case Nil{}:
      Fail{"StackUnderflow"}
    case Con{+value, rest}:
      do Result<&2, &2, String, Popped>:
        valid : Unit <- S.check(valid_slot(value), "InvalidState: empty operand slot")
        typed : Unit <- S.check(Bool.or(U32.is_eq(tag, 0), U32.is_eq(tag, M.slot_tag(value))), "InvalidState: operand type mismatch")
        return Popped{S.frame_stack(frame, rest), value}

def pop(+frame: M.Frame, tag: U32) -> Result<&2, &2, String, Popped>:
  pop_stack(frame, tag, S.stack(frame))

def push(+frame: M.Frame, +value: M.Slot, max: U32) -> Result<&2, &2, String, M.Frame>:
  do Result<&2, &2, String, M.Frame>:
    valid : Unit <- S.check(valid_slot(value), "InvalidState: invalid pushed slot")
    used : U32 = stack_width(S.stack(frame))
    room : Unit <- S.check(room(used, M.slot_width(value), max), "StackOverflow")
    return S.frame_stack(frame, Con{value, S.stack(frame)})

def local_continuation_found(found: Maybe<&2, M.Slot>) -> Bool:
  match found:
    case Some{M.Unusable{}}: True{}
    case _: False{}

def local_continuation(locals: +List<M.Slot>, index: U32) -> Bool:
  local_continuation_found(M.nth(M.Slot, locals, U32.add(index, 1)))

def local_valid(slot: M.Slot, +tag: U32, locals: +List<M.Slot>, index: U32) -> Bool:
  match slot:
    case M.Slot{actual, bits}: U32.is_eq(actual, tag) && U32.is_le(tag, 3)
    case M.Wide{+actual, high, low}: U32.is_eq(actual, tag) && U32.is_ge(actual, 4) && U32.is_le(actual, 5) && local_continuation(locals, index)
    case M.Unusable{}: False{}

def local(+frame: M.Frame, +index: U32, tag: U32) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    +locals : +List<M.Slot> = S.locals(frame)
    +slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, locals, index), "InvalidLocalIndex")
    typed : Unit <- S.check(local_valid(slot, tag, locals, index), "InvalidState: local type mismatch")
    return slot

def clear_local(locals: +List<M.Slot>, index: U32) -> +List<M.Slot>:
  M.replace(M.Slot, locals, U32.to_nat(index), M.Slot{0, 0})

def clear_wide_start_result(hasNext: Bool, +cleared: +List<M.Slot>, index: U32) -> +List<M.Slot>:
  match hasNext:
    case True{}: clear_local(cleared, U32.add(index, 1))
    case False{}: cleared

def clear_wide_start(+locals: +List<M.Slot>, +index: U32) -> +List<M.Slot>:
  +cleared : +List<M.Slot> = clear_local(locals, index)
  clear_wide_start_result(U32.is_lt(U32.add(index, 1), M.length(M.Slot, locals)), cleared, index)

def invalidate_continuation_result(+locals: +List<M.Slot>, +index: U32, previous: Maybe<&2, M.Slot>) -> +List<M.Slot>:
  match previous:
    case Some{M.Wide{tag, high, low}}: clear_local(clear_local(locals, U32.sub(index, 1)), index)
    case _: locals

def invalidate_continuation_nonzero(nonzero: Bool, +locals: +List<M.Slot>, +index: U32) -> +List<M.Slot>:
  match nonzero:
    case True{}: invalidate_continuation_result(locals, index, M.nth(M.Slot, locals, U32.sub(index, 1)))
    case False{}: locals

def invalidate_continuation(locals: +List<M.Slot>, +index: U32) -> +List<M.Slot>:
  invalidate_continuation_nonzero(U32.is_gt(index, 0), locals, index)

def invalidate_local_found(found: Maybe<&2, M.Slot>, +locals: +List<M.Slot>, index: U32) -> +List<M.Slot>:
  match found:
    case Some{M.Wide{tag, high, low}}: clear_wide_start(locals, index)
    case Some{M.Unusable{}}: invalidate_continuation(locals, index)
    case _: locals

def invalidate_local(+locals: +List<M.Slot>, +index: U32) -> +List<M.Slot>:
  invalidate_local_found(M.nth(M.Slot, locals, index), locals, index)

def prepare_local_store(locals: +List<M.Slot>, +index: U32, width: U32) -> +List<M.Slot>:
  match width:
    case 2: invalidate_local(locals, U32.add(index, 1))
    case _: locals

def local_set_raw(locals: +List<M.Slot>, +index: U32, +value: M.Slot) -> +List<M.Slot>:
  +first : +List<M.Slot> = invalidate_local(locals, index)
  +width = M.slot_width(value)
  +prepared : +List<M.Slot> = prepare_local_store(first, index, width)
  +written : +List<M.Slot> = M.replace(M.Slot, prepared, U32.to_nat(index), value)
  Bool.pick(+List<M.Slot>, U32.is_eq(width, 2), M.replace(M.Slot, written, U32.to_nat(U32.add(index, 1)), M.Unusable{}), written)

def local_room(index: U32, width: U32, +maximum: U32) -> Bool:
  match width:
    case 1: U32.is_lt(index, maximum)
    case 2: Bool.pick(Bool, U32.is_ge(maximum, 2), U32.is_lt(index, U32.sub(maximum, 1)), False{})
    case _: False{}

def set_local(+frame: M.Frame, +index: U32, +value: M.Slot) -> Result<&2, &2, String, M.Frame>:
  do Result<&2, &2, String, M.Frame>:
    width : U32 = M.slot_width(value)
    bounds : Unit <- S.check(local_room(index, width, M.length(M.Slot, S.locals(frame))), "InvalidLocalIndex")
    return S.frame_locals(frame, local_set_raw(S.locals(frame), index, value))
def branch(frame: M.Frame, +target: U32, size: U32) -> Result<&2, &2, String, M.Frame>:
  do Result<&2, &2, String, M.Frame>:
    bounds : Unit <- S.check(U32.is_lt(target, size), "InvalidBranchTarget")
    return S.frame_pc(frame, target)

def argument_continue(popped: Popped, next: M.Frame -> M.Slot -> Result<&2, &2, String, Arguments>) -> Result<&2, &2, String, Arguments>:
  match popped:
    case Popped{frame, value}:
      next(frame, value)

@unsafe def argument_next(frame: M.Frame, count: Nat, +acc: +List<M.Slot>) -> Result<&2, &2, String, Arguments>:
  match count:
    case 0n:
      Done{Arguments{frame, acc}}
    case 1n+p:
      do Result<&2, &2, String, Arguments>:
        popped : Popped <- pop(frame, 0)
        result : Arguments <- argument_continue(popped, next => value => argument_next(next, p, Con{value, acc}))
        return result
def arguments(frame: M.Frame, count: U32) -> Result<&2, &2, String, Arguments>:
  argument_next(frame, U32.to_nat(count), Nil{})

def shape_result(valid: Bool, +stack: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  match valid:
    case True{}: Done{stack}
    case False{}: Fail{"InvalidStackShape"}

def shuffle_dup2(top: M.Slot, rest: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  match top rest:
    case M.Wide{tag, high, low} values:
      +wide : M.Slot = M.Wide{tag, high, low}
      shape_result(category_two(wide), Con{wide, Con{wide, values}})
    case M.Slot{tag, bits} Con{M.Slot{next_tag, next_bits}, tail}:
      +first : M.Slot = M.Slot{tag, bits}
      +second : M.Slot = M.Slot{next_tag, next_bits}
      shape_result(category_one(first) && category_one(second), Con{first, Con{second, Con{first, Con{second, tail}}}})
    case M.Slot{tag, bits} Nil{}:
      Fail{"StackUnderflow"}
    case _ _:
      Fail{"InvalidStackShape"}

def shuffle_dup2_x1(top: M.Slot, below: M.Slot, rest: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  match top below rest:
    case M.Wide{tag, high, low} M.Slot{below_tag, below_bits} values:
      +first : M.Slot = M.Wide{tag, high, low}
      +second : M.Slot = M.Slot{below_tag, below_bits}
      shape_result(category_two(first) && category_one(second), Con{first, Con{second, Con{first, values}}})
    case M.Slot{tag, bits} M.Slot{below_tag, below_bits} Con{M.Slot{third_tag, third_bits}, tail}:
      +first : M.Slot = M.Slot{tag, bits}
      +second : M.Slot = M.Slot{below_tag, below_bits}
      +third : M.Slot = M.Slot{third_tag, third_bits}
      shape_result(category_one(first) && category_one(second) && category_one(third),
        Con{first, Con{second, Con{third, Con{first, Con{second, tail}}}}})
    case _ _ _:
      Fail{"InvalidStackShape"}

def shuffle_dup2_x2(top: M.Slot, below: M.Slot, rest: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  match top below rest:
    case M.Wide{tag, high, low} M.Wide{below_tag, below_high, below_low} values:
      +first : M.Slot = M.Wide{tag, high, low}
      +second : M.Slot = M.Wide{below_tag, below_high, below_low}
      shape_result(category_two(first) && category_two(second), Con{first, Con{second, Con{first, values}}})
    case M.Wide{tag, high, low} M.Slot{below_tag, below_bits} Con{M.Slot{third_tag, third_bits}, tail}:
      +first : M.Slot = M.Wide{tag, high, low}
      +second : M.Slot = M.Slot{below_tag, below_bits}
      +third : M.Slot = M.Slot{third_tag, third_bits}
      shape_result(category_two(first) && category_one(second) && category_one(third),
        Con{first, Con{second, Con{third, Con{first, tail}}}})
    case M.Slot{tag, bits} M.Slot{below_tag, below_bits} Con{M.Wide{third_tag, third_high, third_low}, tail}:
      +first : M.Slot = M.Slot{tag, bits}
      +second : M.Slot = M.Slot{below_tag, below_bits}
      +third : M.Slot = M.Wide{third_tag, third_high, third_low}
      shape_result(category_one(first) && category_one(second) && category_two(third),
        Con{first, Con{second, Con{third, Con{first, Con{second, tail}}}}})
    case M.Slot{tag, bits} M.Slot{below_tag, below_bits} Con{M.Slot{third_tag, third_bits}, Con{M.Slot{fourth_tag, fourth_bits}, tail}}:
      +first : M.Slot = M.Slot{tag, bits}
      +second : M.Slot = M.Slot{below_tag, below_bits}
      +third : M.Slot = M.Slot{third_tag, third_bits}
      +fourth : M.Slot = M.Slot{fourth_tag, fourth_bits}
      shape_result(category_one(first) && category_one(second) && category_one(third) && category_one(fourth),
        Con{first, Con{second, Con{third, Con{fourth, Con{first, Con{second, tail}}}}}})
    case _ _ _:
      Fail{"InvalidStackShape"}

def shuffle(op: U32, stack: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  match op stack:
    case 87 Con{a, rest}: shape_result(category_one(a), rest)
    case 88 Con{M.Wide{tag, high, low}, rest}: shape_result(category_two(M.Wide{tag, high, low}), rest)
    case 88 Con{a, Con{b, rest}}: shape_result(category_one(a) && category_one(b), rest)
    case 89 Con{+a, rest}: shape_result(category_one(a), Con{a, Con{a, rest}})
    case 90 Con{+a, Con{+b, rest}}:
      shape_result(category_one(a) && category_one(b), Con{a, Con{b, Con{a, rest}}})
    case 91 Con{+a, Con{+b, Con{+c, rest}}}:
      shape_result(category_one(a) && category_one(b) && category_one(c), Con{a, Con{b, Con{c, Con{a, rest}}}})
    case 91 Con{+a, Con{+b, rest}}:
      shape_result(category_one(a) && category_two(b), Con{a, Con{b, Con{a, rest}}})
    case 92 Con{top, rest}: shuffle_dup2(top, rest)
    case 93 Con{top, Con{below, rest}}: shuffle_dup2_x1(top, below, rest)
    case 94 Con{top, Con{below, rest}}: shuffle_dup2_x2(top, below, rest)
    case 95 Con{+a, Con{+b, rest}}:
      shape_result(category_one(a) && category_one(b), Con{b, Con{a, rest}})
    case _ _:
      Fail{"StackUnderflow"}

def slots_valid(stack: +List<M.Slot>) -> Bool:
  match stack:
    case Nil{}: True{}
    case Con{h, t}: Bool.and(valid_slot(h), slots_valid(t))

def stack_op(frame: M.Frame, op: U32, max: U32) -> Result<&2, &2, String, M.Frame>:
  +fr = frame
  do Result<&2, &2, String, M.Frame>:
    valid_before : Unit <- S.check(slots_valid(S.stack(fr)), "InvalidState: stack category mismatch")
    +stack : +List<M.Slot> <- shuffle(op, S.stack(fr))
    valid : Unit <- S.check(slots_valid(stack), "InvalidState: stack category mismatch")
    room_check : Unit <- S.check(room(stack_width(stack), 0, max), "StackOverflow")
    return S.advance(S.frame_stack(fr, stack))
