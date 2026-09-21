import Base
import ./reader.bend as R

type State is Data:
  State{needed: U32, value: U32, minimum: U32, text: String}

def leading_kind(+byte: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ge(byte, 1), U32.is_le(byte, 127)), 1,
    Bool.pick(U32, Bool.and(U32.is_ge(byte, 192), U32.is_le(byte, 223)), 2,
      Bool.pick(U32, Bool.and(U32.is_ge(byte, 224), U32.is_le(byte, 239)), 3, 0)))

def leading(kind: U32, byte: U32, text: String) -> Result<&2, &2, String, State>:
  match kind:
    case 1:
      Done{State{0, 0, 0, SCon{Chr{byte}, text}}}
    case 2:
      Done{State{1, U32.and(byte, 31), 128, text}}
    case 3:
      Done{State{2, U32.and(byte, 15), 2048, text}}
    case _:
      Fail{"VmError.InvalidConstantPool: malformed modified UTF-8 leading byte"}

def continuation(needed: U32, +value: U32, +minimum: U32, text: String) -> Result<&2, &2, String, State>:
  match needed:
    case 1:
      do Result<&2, &2, String, State>:
        R.require(Bool.or(U32.is_ge(value, minimum), Bool.and(U32.is_eq(value, 0), U32.is_eq(minimum, 128))), "VmError.InvalidConstantPool: overlong modified UTF-8")
        return State{0, 0, 0, SCon{Chr{value}, text}}
    case _:
      Done{State{(needed - 1 : U32), value, minimum, text}}

def step(+byte: U32, state: State) -> Result<&2, &2, String, State>:
  match state:
    case State{0, value, minimum, text}:
      leading(leading_kind(byte), byte, text)
    case State{needed, value, minimum, text}:
      do Result<&2, &2, String, State>:
        R.require(Bool.and(U32.is_ge(byte, 128), U32.is_le(byte, 191)), "VmError.InvalidConstantPool: malformed modified UTF-8 continuation")
        next : State <- continuation(needed, (value * 64 + U32.and(byte, 63) : U32), minimum, text)
        return next

def finish(state: State) -> Result<&2, &2, String, String>:
  match state:
    case State{0, value, minimum, text}:
      Done{String.reverse(text)}
    case _:
      Fail{"VmError.InvalidConstantPool: truncated modified UTF-8 sequence"}

def decode_go(bytes: +List<U32>, state: State) -> Result<&2, &2, String, String>:
  match bytes:
    case Nil{}:
      finish(state)
    case Con{byte, tail}:
      do Result<&2, &2, String, String>:
        next : State <- step(byte, state)
        text : String <- decode_go(tail, next)
        return text

# A Bend Char stores one JVM UTF-16 code unit, including unpaired surrogates.
def decode(bytes: +List<U32>) -> Result<&2, &2, String, String>:
  decode_go(bytes, State{0, 0, 0, SNil{}})
