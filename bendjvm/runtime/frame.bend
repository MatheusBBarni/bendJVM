import Base
import ../model.bend as M
import ./state.bend as S
import ./value.bend as V

type Popped is Data:
  Popped{frame: M.Frame, value: M.Slot}

type Arguments is Data:
  Arguments{frame: M.Frame, values: +List<M.Slot>}

def valid_slot(slot: M.Slot) -> Bool:
  M.Slot{+tag, bits} = slot
  Bool.and(U32.is_ge(tag, 1), U32.is_le(tag, 3))

def pop_stack(frame: M.Frame, +tag: U32, stack: +List<M.Slot>) -> Result<&2, &2, String, Popped>:
  match stack:
    case Nil{}:
      Fail{"StackUnderflow"}
    case Con{+value, rest}:
      do Result<&2, &2, String, Popped>:
        valid : Unit <- S.check(valid_slot(value), "InvalidState: empty operand slot")
        typed : Unit <- S.check(Bool.or(U32.is_eq(tag, 0), U32.is_eq(tag, V.slot_tag(value))), "InvalidState: operand type mismatch")
        return Popped{S.frame_stack(frame, rest), value}

def pop(+frame: M.Frame, tag: U32) -> Result<&2, &2, String, Popped>:
  pop_stack(frame, tag, S.stack(frame))

def push(+frame: M.Frame, +value: M.Slot, max: U32) -> Result<&2, &2, String, M.Frame>:
  do Result<&2, &2, String, M.Frame>:
    valid : Unit <- S.check(valid_slot(value), "InvalidState: invalid pushed slot")
    room : Unit <- S.check(U32.is_lt(M.length(M.Slot, S.stack(frame)), max), "StackOverflow")
    return S.frame_stack(frame, Con{value, S.stack(frame)})

def local(+frame: M.Frame, index: U32, tag: U32) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    +slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, S.locals(frame), index), "InvalidLocalIndex")
    typed : Unit <- S.check(U32.is_eq(V.slot_tag(slot), tag), "InvalidState: local type mismatch")
    return slot

def set_local(+frame: M.Frame, +index: U32, value: M.Slot) -> Result<&2, &2, String, M.Frame>:
  do Result<&2, &2, String, M.Frame>:
    bounds : Unit <- S.check(U32.is_lt(index, M.length(M.Slot, S.locals(frame))), "InvalidLocalIndex")
    return S.frame_locals(frame, M.replace(M.Slot, S.locals(frame), U32.to_nat(index), value))

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

def shuffle(op: U32, stack: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  match op stack:
    case 87 Con{a, rest}:
      Done{rest}
    case 88 Con{a, Con{b, rest}}:
      Done{rest}
    case 89 Con{+a, rest}:
      Done{Con{a, Con{a, rest}}}
    case 90 Con{+a, Con{b, rest}}:
      Done{Con{a, Con{b, Con{a, rest}}}}
    case 91 Con{+a, Con{b, Con{c, rest}}}:
      Done{Con{a, Con{b, Con{c, Con{a, rest}}}}}
    case 92 Con{+a, Con{+b, rest}}:
      Done{Con{a, Con{b, Con{a, Con{b, rest}}}}}
    case 93 Con{+a, Con{+b, Con{c, rest}}}:
      Done{Con{a, Con{b, Con{c, Con{a, Con{b, rest}}}}}}
    case 94 Con{+a, Con{+b, Con{c, Con{d, rest}}}}:
      Done{Con{a, Con{b, Con{c, Con{d, Con{a, Con{b, rest}}}}}}}
    case 95 Con{a, Con{b, rest}}:
      Done{Con{b, Con{a, rest}}}
    case _ _:
      Fail{"StackUnderflow"}

def slots_valid(stack: +List<M.Slot>) -> Bool:
  match stack:
    case Nil{}:
      True{}
    case Con{h, t}:
      Bool.and(valid_slot(h), slots_valid(t))

def stack_op(frame: M.Frame, op: U32, max: U32) -> Result<&2, &2, String, M.Frame>:
  +fr = frame
  do Result<&2, &2, String, M.Frame>:
    +stack : +List<M.Slot> <- shuffle(op, S.stack(fr))
    valid : Unit <- S.check(slots_valid(stack), "InvalidState: stack category mismatch")
    room : Unit <- S.check(U32.is_le(M.length(M.Slot, stack), max), "StackOverflow")
    return S.advance(S.frame_stack(fr, stack))
