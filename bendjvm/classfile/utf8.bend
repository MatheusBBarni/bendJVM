import Base
import ./reader.bend as R

type State is Data:
  State{needed: U32, value: U32, minimum: U32, text: String, pending: U32}

def high_surrogate(+unit: U32) -> Bool:
  Bool.and(U32.is_ge(unit, 55296), U32.is_le(unit, 56319))

def low_surrogate(+unit: U32) -> Bool:
  Bool.and(U32.is_ge(unit, 56320), U32.is_le(unit, 57343))

def leading_kind(+byte: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ge(byte, 1), U32.is_le(byte, 127)), 1,
    Bool.pick(U32, Bool.and(U32.is_ge(byte, 192), U32.is_le(byte, 223)), 2,
      Bool.pick(U32, Bool.and(U32.is_ge(byte, 224), U32.is_le(byte, 239)), 3, 0)))

def append_value_zero(+value: U32, +text: String, high: Bool, low: Bool) -> State:
  match high:
    case True{}: State{0, 0, 0, text, value}
    case False{}:
      match low:
        case True{}: State{0, 0, 0, SCon{Chr{65533}, text}, 0}
        case False{}: State{0, 0, 0, SCon{Chr{value}, text}, 0}

def append_value_pending(old: U32, +value: U32, +text: String, low: Bool) -> State:
  match low:
    case True{}: State{0, 0, 0, SCon{Chr{U32.add(65536, U32.add(U32.shln(U32.sub(old, 55296), 10n), U32.sub(value, 56320)))}, text}, 0}
    case False{}: State{0, 0, 0, SCon{Chr{65533}, text}, 0}

def append_value(pending: U32, +value: U32, +text: String) -> State:
  match pending:
    case 0: append_value_zero(value, text, high_surrogate(value), low_surrogate(value))
    case old: append_value_pending(old, value, text, low_surrogate(value))

def leading(kind: U32, byte: U32, pending: U32, text: String) -> Result<&2, &2, String, State>:
  match kind:
    case 1: Done{append_value(pending, byte, text)}
    case 2: Done{State{1, U32.and(byte, 31), 128, text, pending}}
    case 3: Done{State{2, U32.and(byte, 15), 2048, text, pending}}
    case _: Fail{"VmError.InvalidConstantPool: malformed modified UTF-8 leading byte"}

def continuation(needed: U32, +value: U32, +minimum: U32, pending: U32, text: String) -> Result<&2, &2, String, State>:
  match needed:
    case 1:
      do Result<&2, &2, String, State>:
        R.require(Bool.or(U32.is_ge(value, minimum), Bool.and(U32.is_eq(value, 0), U32.is_eq(minimum, 128))), "VmError.InvalidConstantPool: overlong modified UTF-8")
        return append_value(pending, value, text)
    case _:
      Done{State{(needed - 1 : U32), value, minimum, text, pending}}

def step(+byte: U32, state: State) -> Result<&2, &2, String, State>:
  match state:
    case State{0, value, minimum, text, pending}:
      leading(leading_kind(byte), byte, pending, text)
    case State{needed, value, minimum, text, pending}:
      do Result<&2, &2, String, State>:
        R.require(Bool.and(U32.is_ge(byte, 128), U32.is_le(byte, 191)), "VmError.InvalidConstantPool: malformed modified UTF-8 continuation")
        next : State <- continuation(needed, (value * 64 + U32.and(byte, 63) : U32), minimum, pending, text)
        return next

def finish_text(pending: U32, text: String) -> String:
  match pending:
    case 0: String.reverse(text)
    case _: String.reverse(SCon{Chr{65533}, text})

def finish(state: State) -> Result<&2, &2, String, String>:
  match state:
    case State{0, value, minimum, text, pending}: Done{finish_text(pending, text)}
    case _: Fail{"VmError.InvalidConstantPool: truncated modified UTF-8 sequence"}

def decode_go(bytes: +List<U32>, state: State) -> Result<&2, &2, String, String>:
  match bytes:
    case Nil{}:
      finish(state)
    case Con{byte, tail}:
      do Result<&2, &2, String, String>:
        next : State <- step(byte, state)
        text : String <- decode_go(tail, next)
        return text

def decode(bytes: +List<U32>) -> Result<&2, &2, String, String>:
  decode_go(bytes, State{0, 0, 0, SNil{}, 0})
