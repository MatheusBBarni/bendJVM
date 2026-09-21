import Base
import ../model.bend as M

type Piece is Data:
  Piece{instruction: M.Instruction, rest: +List<U32>, width: U32}

type Boundary is Data:
  Boundary{offset: U32, pc: U32}

def require(ok: Bool, text: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{text}

def signed8(n: U32) -> U32:
  (U32.xor(n, 128) - 128 : U32)

def signed16(n: U32) -> U32:
  (U32.xor(n, 32768) - 32768 : U32)

def word(a: U32, b: U32) -> U32:
  (a * 256 + b : U32)

def format(op: U32) -> U32:
  match op:
    case 0: 1
    case 1: 1
    case 2: 1
    case 3: 1
    case 4: 1
    case 5: 1
    case 6: 1
    case 7: 1
    case 8: 1
    case 11: 1
    case 12: 1
    case 13: 1
    case 16: 2
    case 17: 3
    case 18: 2
    case 19: 3
    case 21: 2
    case 23: 2
    case 25: 2
    case 26: 1
    case 27: 1
    case 28: 1
    case 29: 1
    case 34: 1
    case 35: 1
    case 36: 1
    case 37: 1
    case 42: 1
    case 43: 1
    case 44: 1
    case 45: 1
    case 46: 1
    case 48: 1
    case 50: 1
    case 51: 1
    case 52: 1
    case 53: 1
    case 54: 2
    case 56: 2
    case 58: 2
    case 59: 1
    case 60: 1
    case 61: 1
    case 62: 1
    case 67: 1
    case 68: 1
    case 69: 1
    case 70: 1
    case 75: 1
    case 76: 1
    case 77: 1
    case 78: 1
    case 79: 1
    case 81: 1
    case 83: 1
    case 84: 1
    case 85: 1
    case 86: 1
    case 87: 1
    case 88: 1
    case 89: 1
    case 90: 1
    case 91: 1
    case 92: 1
    case 93: 1
    case 94: 1
    case 95: 1
    case 96: 1
    case 98: 1
    case 100: 1
    case 102: 1
    case 104: 1
    case 106: 1
    case 108: 1
    case 110: 1
    case 112: 1
    case 114: 1
    case 116: 1
    case 118: 1
    case 120: 1
    case 122: 1
    case 124: 1
    case 126: 1
    case 128: 1
    case 130: 1
    case 132: 4
    case 134: 1
    case 139: 1
    case 145: 1
    case 146: 1
    case 147: 1
    case 149: 1
    case 150: 1
    case 153: 3
    case 154: 3
    case 155: 3
    case 156: 3
    case 157: 3
    case 158: 3
    case 159: 3
    case 160: 3
    case 161: 3
    case 162: 3
    case 163: 3
    case 164: 3
    case 165: 3
    case 166: 3
    case 167: 3
    case 172: 1
    case 174: 1
    case 176: 1
    case 177: 1
    case 178: 3
    case 179: 3
    case 180: 3
    case 181: 3
    case 182: 3
    case 183: 3
    case 184: 3
    case 185: 5
    case 187: 3
    case 188: 2
    case 189: 3
    case 190: 1
    case 191: 1
    case 192: 3
    case 193: 3
    case 196: 6
    case 198: 3
    case 199: 3
    case 200: 7
    case _: 0

def compact(op: U32) -> U32:
  match op:
    case 2: 4294967295
    case 4: 1
    case 5: 2
    case 6: 3
    case 7: 4
    case 8: 5
    case 12: 1065353216
    case 13: 1073741824
    case 27: 1
    case 28: 2
    case 29: 3
    case 35: 1
    case 36: 2
    case 37: 3
    case 43: 1
    case 44: 2
    case 45: 3
    case 60: 1
    case 61: 2
    case 62: 3
    case 68: 1
    case 69: 2
    case 70: 3
    case 76: 1
    case 77: 2
    case 78: 3
    case _: 0

def branch(+op: U32) -> Bool:
  (((op >= 153 : U32) && (op <= 167 : U32)) || U32.is_eq(op, 198) || U32.is_eq(op, 199) || U32.is_eq(op, 200))

def operand8(op: U32, value: U32) -> U32:
  match op:
    case 16: signed8(value)
    case _: value

def operand16(op: U32, value: U32, offset: U32, relative: Bool) -> U32:
  match op relative:
    case 17 _: signed16(value)
    case _ True{}: (offset + signed16(value) : U32)
    case _ False{}: value

def wide_local(op: U32) -> Bool:
  match op:
    case 21: True{}
    case 23: True{}
    case 25: True{}
    case 54: True{}
    case 56: True{}
    case 58: True{}
    case _: False{}

def mk_instruction(op: U32, a: U32, b: U32, c: U32, offset: U32) -> M.Instruction:
  M.Instruction{op, a, b, c, offset}

def mk_piece(op: U32, a: U32, b: U32, c: U32, offset: U32, rest: +List<U32>, width: U32) -> Piece:
  Piece{mk_instruction(op, a, b, c, offset), rest, width}

def wide_iinc(+tail: +List<U32>, a: U32, b: U32, offset: U32) -> Result<&2, &2, String, Piece>:
  match tail:
    case Con{c, Con{d, rest}}:
      Done{mk_piece(196, word(a, b), signed16(word(c, d)), 132, offset, rest, 6)}
    case _:
      Fail{"InvalidBytecode: truncated wide iinc"}

def wide_parts(op: U32, a: U32, b: U32, +tail: +List<U32>, offset: U32) -> Result<&2, &2, String, Piece>:
  match op:
    case 132:
      wide_iinc(tail, a, b, offset)
    case other:
      Fail{"UnsupportedOpcode: wide modified opcode " ++ U32.show(other)}
def wide(bytes: +List<U32>, offset: U32) -> Result<&2, &2, String, Piece>:
  match bytes:
    case Con{op, Con{a, Con{b, tail}}}:
      wide_parts(op, a, b, tail, offset)
    case _:
      Fail{"InvalidBytecode: truncated wide instruction"}

def one(kind: U32, +op: U32, bytes: +List<U32>, +offset: U32) -> Result<&2, &2, String, Piece>:
  match kind:
    case 0:
      Fail{"UnsupportedOpcode: opcode " ++ U32.show(op)}
    case 1:
      Done{Piece{M.Instruction{op, compact(op), 0, 0, offset}, bytes, 1}}
    case 2:
      match bytes:
        case Con{a, rest}:
          Done{Piece{M.Instruction{op, operand8(op, a), 0, 0, offset}, rest, 2}}
        case _:
          Fail{"InvalidBytecode: truncated one-byte operand"}
    case 3:
      match bytes:
        case Con{a, Con{b, rest}}:
          Done{Piece{M.Instruction{op, operand16(op, word(a, b), offset, branch(op)), 0, 0, offset}, rest, 3}}
        case _:
          Fail{"InvalidBytecode: truncated two-byte operand"}
    case 4:
      match bytes:
        case Con{a, Con{b, rest}}:
          Done{Piece{M.Instruction{op, a, signed8(b), 0, offset}, rest, 3}}
        case _:
          Fail{"InvalidBytecode: truncated iinc operands"}
    case 5:
      match bytes:
        case Con{a, Con{b, Con{count, Con{zero, rest}}}}:
          do Result<&2, &2, String, Piece>:
            require(U32.is_eq(zero, 0), "InvalidBytecode: invokeinterface reserved byte is nonzero")
            return Piece{M.Instruction{op, word(a, b), count, 0, offset}, rest, 5}
        case _:
          Fail{"InvalidBytecode: truncated invokeinterface operands"}
    case 6:
      wide(bytes, offset)
    case _:
      match bytes:
        case Con{a, Con{b, Con{c, Con{d, rest}}}}:
          target = (offset + word(a, b) * 65536 + word(c, d) : U32)
          Done{Piece{M.Instruction{op, target, 0, 0, offset}, rest, 5}}
        case _:
          Fail{"InvalidBytecode: truncated four-byte branch operand"}

def located(-A: Data, result: Result<&2, &2, String, A>, name: String, offset: U32) -> Result<&2, &2, String, A>:
  match result:
    case Fail{error}:
      Fail{error ++ " in " ++ name ++ " at byte " ++ U32.show(offset)}
    case Done{value}:
      Done{value}

def scan_piece(piece: Result<&2, &2, String, Piece>, fuel: Nat, offset: U32, name: String, acc: +List<M.Instruction>, next: Nat -> +List<U32> -> @+next_offset: U32 -> @+next_name: String -> +List<M.Instruction> -> Result<&2, &2, String, +List<M.Instruction>>) -> Result<&2, &2, String, +List<M.Instruction>>:
  match piece:
    case Fail{error}:
      Fail{error}
    case Done{Piece{instruction, rest, width}}:
      next(fuel, rest, (offset + width : U32), name, Con{instruction, acc})

@unsafe def scan(fuel: Nat, bytes: +List<U32>, +offset: U32, +name: String, acc: +List<M.Instruction>) -> Result<&2, &2, String, +List<M.Instruction>>:
  match fuel bytes:
    case _ Nil{}:
      Done{M.reverse(M.Instruction, acc)}
    case 0n _:
      Fail{"InvalidBytecode: instruction limit in " ++ name}
    case 1n+f Con{+op, rest}:
      scan_piece(located(Piece, one(format(op), op, rest, offset), name, offset), f, offset, name, acc, scan)


def boundaries(instructions: +List<M.Instruction>, +pc: U32, +length: U32) -> +List<Boundary>:
  match instructions:
    case Nil{}:
      Con{Boundary{length, pc}, Nil{}}
    case Con{M.Instruction{op, a, b, c, offset}, rest}:
      Con{Boundary{offset, pc}, boundaries(rest, (pc + 1 : U32), length)}

def target_pick(found: Bool, pc: U32, rest: Result<&2, &2, String, U32>) -> Result<&2, &2, String, U32>:
  match found:
    case True{}: Done{pc}
    case False{}: rest

def target(map: +List<Boundary>, +offset: U32) -> Result<&2, &2, String, U32>:
  match map:
    case Nil{}:
      Fail{"InvalidBytecode: target is not an instruction boundary"}
    case Con{Boundary{position, pc}, rest}:
      target_pick(U32.is_eq(position, offset), pc, target(rest, offset))

def resolve_instruction(relative: Bool, op: U32, +a: U32, b: U32, c: U32, offset: U32, map: +List<Boundary>, length: U32) -> Result<&2, &2, String, M.Instruction>:
  match relative:
    case False{}:
      Done{M.Instruction{op, a, b, c, offset}}
    case True{}:
      do Result<&2, &2, String, M.Instruction>:
        require((a < length : U32), "InvalidBytecode: branch target outside code")
        pc : U32 <- target(map, a)
        return M.Instruction{op, pc, b, c, offset}

def resolve(instructions: +List<M.Instruction>, +map: +List<Boundary>, +length: U32, +name: String) -> Result<&2, &2, String, +List<M.Instruction>>:
  match instructions:
    case Nil{}:
      Done{Nil{}}
    case Con{M.Instruction{+op, a, b, c, +offset}, rest}:
      do Result<&2, &2, String, +List<M.Instruction>>:
        instruction : M.Instruction <- located(M.Instruction, resolve_instruction(branch(op), op, a, b, c, offset, map, length), name, offset)
        tail : +List<M.Instruction> <- resolve(rest, map, length, name)
        return Con{instruction, tail}

def resolve_handlers(handlers: +List<M.Handler>, +map: +List<Boundary>, +length: U32, +name: String) -> Result<&2, &2, String, +List<M.Handler>>:
  match handlers:
    case Nil{}:
      Done{Nil{}}
    case Con{M.Handler{+start, +end, +handler, catch}, rest}:
      do Result<&2, &2, String, +List<M.Handler>>:
        located(Unit, require((start < end : U32) && (end <= length : U32) && (handler < length : U32), "InvalidBytecode: invalid exception range"), name, start)
        s : U32 <- located(U32, target(map, start), name, start)
        e : U32 <- located(U32, target(map, end), name, end)
        h : U32 <- located(U32, target(map, handler), name, handler)
        tail : +List<M.Handler> <- resolve_handlers(rest, map, length, name)
        return Con{M.Handler{s, e, h, catch}, tail}

def method(value: M.Method) -> Result<&2, &2, String, M.Method>:
  match value:
    case M.Method{flags, +name, +descriptor, maxStack, maxLocals, +code, old, handlers, attributes}:
      do Result<&2, &2, String, M.Method>:
        +label : String = name ++ descriptor
        +raw : +List<M.Instruction> <- scan(List.length(&2, U32, code), code, 0, label, Nil{})
        +length : U32 = M.length(U32, code)
        +map : +List<Boundary> = boundaries(raw, 0, length)
        instructions : +List<M.Instruction> <- resolve(raw, map, length, label)
        converted : +List<M.Handler> <- resolve_handlers(handlers, map, length, label)
        return M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, converted, attributes}
