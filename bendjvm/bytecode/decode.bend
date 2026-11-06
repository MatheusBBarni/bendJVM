import Base
import ../model.bend as M

type Piece is Data:
  Piece{instruction: M.Instruction, rest: +List<U32>, width: U32, switches: +List<M.SwitchTable>}

type Boundary is Data:
  Boundary{offset: U32, pc: U32}

type Decoded is Data:
  Decoded{instructions: +List<M.Instruction>, switches: +List<M.SwitchTable>}
type ScanWork is Data:
  ScanWork{bytes: +List<U32>, offset: U32, instructions: +List<M.Instruction>, switches: +List<M.SwitchTable>}


type KeyTargets is Data:
  KeyTargets{keys: +List<U32>, targets: +List<U32>}
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

# Big-endian u4 from four bytes; signed operands reinterpret it as two's complement.
def word32(a: U32, b: U32, c: U32, d: U32) -> U32:
  (((a * 256 + b) * 256 + c) * 256 + d : U32)

def format(op: U32) -> U32:
  match op:
    case 197: 9
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
    case 9: 1
    case 10: 1
    case 12: 1
    case 13: 1
    case 16: 2
    case 17: 3
    case 18: 2
    case 19: 3
    case 14: 1
    case 15: 1
    case 21: 2
    case 23: 2
    case 25: 2
    case 26: 1
    case 27: 1
    case 28: 1
    case 20: 3
    case 22: 2
    case 24: 2
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
    case 55: 2
    case 57: 2
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
    case 97: 1
    case 99: 1
    case 101: 1
    case 103: 1
    case 105: 1
    case 107: 1
    case 109: 1
    case 111: 1
    case 113: 1
    case 115: 1
    case 117: 1
    case 119: 1
    case 121: 1
    case 123: 1
    case 125: 1
    case 127: 1
    case 129: 1
    case 131: 1
    case 133: 1
    case 135: 1
    case 136: 1
    case 137: 1
    case 138: 1
    case 139: 1
    case 140: 1
    case 141: 1
    case 142: 1
    case 143: 1
    case 144: 1
    case 148: 1
    case 151: 1
    case 152: 1
    case 173: 1
    case 174: 1
    case 175: 1
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
    case 186: 5
    case 187: 3
    case 188: 2
    case 189: 3
    case 190: 1
    case 191: 1
    case 192: 3
    case 194: 1
    case 195: 1
    case 193: 3
    case 196: 6
    case 198: 3
    case 199: 3
    case 200: 7
    case 30: 1
    case 31: 1
    case 32: 1
    case 33: 1
    case 38: 1
    case 39: 1
    case 40: 1
    case 41: 1
    case 47: 1
    case 49: 1
    case 63: 1
    case 64: 1
    case 65: 1
    case 66: 1
    case 71: 1
    case 72: 1
    case 73: 1
    case 74: 1
    case 80: 1
    case 82: 1
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
    case 31: 1
    case 32: 2
    case 33: 3
    case 35: 1
    case 36: 2
    case 37: 3
    case 39: 1
    case 40: 2
    case 41: 3
    case 43: 1
    case 44: 2
    case 45: 3
    case 60: 1
    case 61: 2
    case 62: 3
    case 64: 1
    case 65: 2
    case 66: 3
    case 68: 1
    case 69: 2
    case 70: 3
    case 72: 1
    case 73: 2
    case 74: 3
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
    case 22: True{}
    case 23: True{}
    case 24: True{}
    case 25: True{}
    case 54: True{}
    case 55: True{}
    case 56: True{}
    case 57: True{}
    case 58: True{}
    case _: False{}

def mk_instruction(op: U32, a: U32, b: U32, c: U32, offset: U32) -> M.Instruction:
  M.Instruction{op, a, b, c, offset}

def mk_piece(op: U32, a: U32, b: U32, c: U32, offset: U32, rest: +List<U32>, width: U32) -> Piece:
  Piece{mk_instruction(op, a, b, c, offset), rest, width, Nil{}}

def wide_iinc(+tail: +List<U32>, a: U32, b: U32, offset: U32) -> Result<&2, &2, String, Piece>:
  match tail:
    case Con{c, Con{d, rest}}:
      Done{mk_piece(132, word(a, b), signed16(word(c, d)), 1, offset, rest, 6)}
    case _: Fail{"InvalidBytecode: truncated wide iinc operands"}
def wide_local_piece(op: U32, a: U32, b: U32, +tail: +List<U32>, offset: U32) -> Result<&2, &2, String, Piece>:
  Done{mk_piece(op, word(a, b), 0, 1, offset, tail, 4)}
def wide_invalid_modifier(op: U32) -> Result<&2, &2, String, Piece>:
  match op:
    case 169: Fail{"UnsupportedOpcode: wide ret"}
    case _: Fail{"InvalidBytecode: invalid wide modifier " ++ U32.show(op)}


def wide_local_result(ok: Bool, op: U32, a: U32, b: U32, +tail: +List<U32>, offset: U32) -> Result<&2, &2, String, Piece>:
  match ok:
    case True{}:
      wide_local_piece(op, a, b, tail, offset)
    case False{}:
      wide_invalid_modifier(op)

def wide_parts(op: U32, a: U32, b: U32, +tail: +List<U32>, offset: U32) -> Result<&2, &2, String, Piece>:
  match op:
    case 132:
      wide_iinc(tail, a, b, offset)
    case +local:
      wide_local_result(wide_local(local), local, a, b, tail, offset)
def wide(bytes: +List<U32>, offset: U32) -> Result<&2, &2, String, Piece>:
  match bytes:
    case Con{op, Con{a, Con{b, tail}}}:
      wide_parts(op, a, b, tail, offset)
    case _:
      Fail{"InvalidBytecode: truncated wide instruction"}

def signed32_less(a: U32, b: U32) -> Bool:
  U32.is_lt(U32.xor(a, 2147483648), U32.xor(b, 2147483648))

def displacement_signed(+offset: U32, +raw: U32, negative: Bool) -> Result<&2, &2, String, U32>:
  match negative:
    case False{}:
      do Result<&2, &2, String, U32>:
        require(U32.is_le(raw, U32.sub(4294967295, offset)), "InvalidBytecode: switch target arithmetic overflow")
        return U32.add(offset, raw)
    case True{}:
      +magnitude : U32 = U32.add(U32.xor(raw, 4294967295), 1)
      do Result<&2, &2, String, U32>:
        require(U32.is_le(magnitude, offset), "InvalidBytecode: switch target arithmetic underflow")
        return U32.sub(offset, magnitude)

def displacement(+offset: U32, +raw: U32) -> Result<&2, &2, String, U32>:
  displacement_signed(offset, raw, U32.is_ge(raw, 2147483648))
def skip_switch_padding(padding: U32, +bytes: +List<U32>) -> Result<&2, &2, String, +List<U32>>:
  match padding bytes:
    case 0 _:
      Done{bytes}
    case 1 Con{a, rest}:
      do Result<&2, &2, String, +List<U32>>:
        require(U32.is_eq(a, 0), "InvalidBytecode: nonzero switch padding")
        return rest
    case 2 Con{a, Con{b, rest}}:
      do Result<&2, &2, String, +List<U32>>:
        require(U32.is_eq(a, 0) && U32.is_eq(b, 0), "InvalidBytecode: nonzero switch padding")
        return rest
    case 3 Con{a, Con{b, Con{c, rest}}}:
      do Result<&2, &2, String, +List<U32>>:
        require(U32.is_eq(a, 0) && U32.is_eq(b, 0) && U32.is_eq(c, 0), "InvalidBytecode: nonzero switch padding")
        return rest
    case _ _:
      Fail{"InvalidBytecode: truncated switch padding"}

def switch_targets(+bytes: +List<U32>, count: U32, +acc: +List<U32>, +offset: U32) -> Result<&2, &2, String, +List<U32>>:
  match bytes count:
    case _ 0: Done{M.reverse(U32, acc)}
    case Con{a, Con{b, Con{c, Con{d, rest}}}} _:
      do Result<&2, &2, String, +List<U32>>:
        target : U32 <- displacement(offset, word32(a, b, c, d))
        tail : +List<U32> <- switch_targets(rest, (count - 1 : U32), Con{target, acc}, offset)
        return tail
    case _ _: Fail{"InvalidBytecode: truncated switch targets"}

def lookup_key_ordered(keys: +List<U32>, key: U32) -> Result<&2, &2, String, Unit>:
  match keys:
    case Nil{}: Done{Unit{}}
    case Con{previous, _}:
      do Result<&2, &2, String, Unit>:
        require(signed32_less(previous, key), "InvalidBytecode: lookupswitch keys are not strictly increasing")
        return Unit{}

def indexed_targets(+bytes: +List<U32>, count: U32, +keys: +List<U32>, +targets: +List<U32>, +offset: U32) -> Result<&2, &2, String, KeyTargets>:
  match bytes count:
    case _ 0:
      Done{KeyTargets{M.reverse(U32, keys), M.reverse(U32, targets)}}
    case Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, rest}}}}}}}} _:
      do Result<&2, &2, String, KeyTargets>:
        +key : U32 = word32(a, b, c, d)
        ordered : Unit <- lookup_key_ordered(keys, key)
        target : U32 <- displacement(offset, word32(e, f, g, h))
        pairs : KeyTargets <- indexed_targets(rest, (count - 1 : U32), Con{key, keys}, Con{target, targets}, offset)
        return pairs
    case _ _: Fail{"InvalidBytecode: truncated lookupswitch pairs"}
def skip_bytes(+bytes: +List<U32>, count: U32) -> +List<U32>:
  match bytes count:
    case _ 0: bytes
    case Con{_, rest} _: skip_bytes(rest, (count - 1 : U32))
    case Nil{} _: Nil{}

def switch_table_piece(op: U32, padding: U32, +offset: U32, default: U32, +rest: +List<U32>) -> Result<&2, &2, String, Piece>:
  match rest:
    case Con{e, Con{f, Con{g, Con{h, Con{i, Con{j, Con{k, Con{l, +entries}}}}}}}}:
      do Result<&2, &2, String, Piece>:
        +low : U32 = word32(e, f, g, h)
        +high : U32 = word32(i, j, k, l)
        require(signed32_less(low, high) || U32.is_eq(low, high), "InvalidBytecode: tableswitch high is less than low")
        +difference : U32 = U32.sub(high, low)
        require(U32.is_ne(difference, 4294967295), "InvalidBytecode: tableswitch range overflow")
        +count : U32 = U32.add(difference, 1)
        available : U32 = M.length(U32, entries)
        require(U32.is_le(count, U32.div(available, 4)), "InvalidBytecode: truncated tableswitch payload")
        targets : +List<U32> <- switch_targets(entries, count, Nil{}, offset)
        table : M.SwitchTable = M.SwitchTable{170, low, high, Nil{}, targets}
        return Piece{M.Instruction{op, default, 0, 0, offset}, skip_bytes(entries, U32.mul(count, 4)), U32.add(1, U32.add(padding, U32.add(12, U32.mul(count, 4)))), [table]}
    case _: Fail{"InvalidBytecode: truncated tableswitch payload"}

def switch_lookup_result(op: U32, padding: U32, offset: U32, default: U32, +count: U32, +entries: +List<U32>, pairs: KeyTargets) -> Result<&2, &2, String, Piece>:
  match pairs:
    case KeyTargets{keys, targets}:
      table : M.SwitchTable = M.SwitchTable{171, 0, 0, keys, targets}
      Done{Piece{M.Instruction{op, default, 0, 0, offset}, skip_bytes(entries, U32.mul(count, 8)), U32.add(1, U32.add(padding, U32.add(8, U32.mul(count, 8)))), [table]}}

def switch_lookup_piece(op: U32, padding: U32, +offset: U32, default: U32, +rest: +List<U32>) -> Result<&2, &2, String, Piece>:
  match rest:
    case Con{e, Con{f, Con{g, Con{h, +entries}}}}:
      do Result<&2, &2, String, Piece>:
        +count : U32 = word32(e, f, g, h)
        require(U32.is_lt(count, 2147483648), "InvalidBytecode: negative lookupswitch npairs")
        available : U32 = M.length(U32, entries)
        require(U32.is_le(count, U32.div(available, 8)), "InvalidBytecode: truncated lookupswitch payload")
        pairs : KeyTargets <- indexed_targets(entries, count, Nil{}, Nil{}, offset)
        piece : Piece <- switch_lookup_result(op, padding, offset, default, count, entries, pairs)
        return piece
    case _: Fail{"InvalidBytecode: truncated lookupswitch count"}

def switch_entries_piece(op: U32, padding: U32, offset: U32, default: U32, rest: +List<U32>) -> Result<&2, &2, String, Piece>:
  match op:
    case 170: switch_table_piece(op, padding, offset, default, rest)
    case 171: switch_lookup_piece(op, padding, offset, default, rest)
    case _: Fail{"InvalidBytecode: invalid switch opcode"}

def switch_default_piece(op: U32, padding: U32, +offset: U32, payload: +List<U32>) -> Result<&2, &2, String, Piece>:
  match payload:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      do Result<&2, &2, String, Piece>:
        default : U32 <- displacement(offset, word32(a, b, c, d))
        piece : Piece <- switch_entries_piece(op, padding, offset, default, rest)
        return piece
    case _: Fail{"InvalidBytecode: truncated switch default"}

def switch_piece(op: U32, +bytes: +List<U32>, +offset: U32) -> Result<&2, &2, String, Piece>:
  do Result<&2, &2, String, Piece>:
    +padding : U32 = U32.mod(U32.sub(4, U32.mod(U32.add(offset, 1), 4)), 4)
    +payload : +List<U32> <- skip_switch_padding(padding, bytes)
    piece : Piece <- switch_default_piece(op, padding, offset, payload)
    return piece

def unsupported_opcode(op: U32, bytes: +List<U32>) -> Result<&2, &2, String, Piece>:
  match op bytes:
    case 168 Con{_, Con{_, _}}: Fail{"UnsupportedOpcode: jsr"}
    case 168 _: Fail{"InvalidBytecode: truncated jsr operands"}
    case 169 Con{_, _}: Fail{"UnsupportedOpcode: ret"}
    case 169 _: Fail{"InvalidBytecode: truncated ret operand"}
    case 201 Con{_, Con{_, Con{_, Con{_, _}}}}: Fail{"UnsupportedOpcode: jsr_w"}
    case 201 _: Fail{"InvalidBytecode: truncated jsr_w operands"}
    case _ _: Fail{"InvalidOpcode: reserved opcode " ++ U32.show(op)}

def one_ordinary(kind: U32, +op: U32, bytes: +List<U32>, +offset: U32) -> Result<&2, &2, String, Piece>:
  match kind:
    case 0:
      unsupported_opcode(op, bytes)
    case 1:
      Done{mk_piece(op, compact(op), 0, 0, offset, bytes, 1)}
    case 2:
      match bytes:
        case Con{a, rest}:
          Done{mk_piece(op, operand8(op, a), 0, 0, offset, rest, 2)}
        case _:
          Fail{"InvalidBytecode: truncated one-byte operand"}
    case 3:
      match bytes:
        case Con{a, Con{b, rest}}:
          Done{mk_piece(op, operand16(op, word(a, b), offset, branch(op)), 0, 0, offset, rest, 3)}
        case _:
          Fail{"InvalidBytecode: truncated two-byte operand"}
    case 4:
      match bytes:
        case Con{a, Con{b, rest}}:
          Done{mk_piece(op, a, signed8(b), 0, offset, rest, 3)}
        case _:
          Fail{"InvalidBytecode: truncated iinc operands"}
    case 5:
      match bytes:
        case Con{a, Con{b, Con{count, Con{zero, rest}}}}:
          do Result<&2, &2, String, Piece>:
            require(U32.is_eq(zero, 0), "InvalidBytecode: invokeinterface reserved byte is nonzero")
            return mk_piece(op, word(a, b), count, 0, offset, rest, 5)
        case _:
          Fail{"InvalidBytecode: truncated invokeinterface operands"}
    case 8:
      match bytes:
        case Con{a, Con{b, Con{zero1, Con{zero2, rest}}}}:
          do Result<&2, &2, String, Piece>:
            require(U32.is_eq(zero1, 0) && U32.is_eq(zero2, 0), "InvalidBytecode: invokedynamic reserved bytes are nonzero")
            return mk_piece(op, word(a, b), 0, 0, offset, rest, 5)
        case _:
          Fail{"InvalidBytecode: truncated invokedynamic operands"}
    case 9:
      match bytes:
        case Con{a, Con{b, Con{+dimensions, rest}}}:
          do Result<&2, &2, String, Piece>:
            require(U32.is_ne(dimensions, 0), "InvalidBytecode: multianewarray dimensions must be at least 1")
            return mk_piece(op, word(a, b), dimensions, 0, offset, rest, 4)
        case _:
          Fail{"InvalidBytecode: truncated multianewarray operands"}
    case 6:
      wide(bytes, offset)
    case _:
      match bytes:
        case Con{a, Con{b, Con{c, Con{d, rest}}}}:
          do Result<&2, &2, String, Piece>:
            target : U32 <- displacement(offset, word32(a, b, c, d))
            return mk_piece(op, target, 0, 0, offset, rest, 5)
        case _:
          Fail{"InvalidBytecode: truncated four-byte branch operand"}
def one(kind: U32, +op: U32, bytes: +List<U32>, +offset: U32) -> Result<&2, &2, String, Piece>:
  match op:
    case 170:
      switch_piece(op, bytes, offset)
    case 171:
      switch_piece(op, bytes, offset)
    case _:
      one_ordinary(kind, op, bytes, offset)

def located(-A: Data, result: Result<&2, &2, String, A>, name: String, offset: U32) -> Result<&2, &2, String, A>:
  match result:
    case Fail{error}:
      Fail{error ++ " in " ++ name ++ " at byte " ++ U32.show(offset)}
    case Done{value}:
      Done{value}
def scan_piece_plain(instruction: M.Instruction, +rest: +List<U32>, width: U32, offset: U32, +acc: +List<M.Instruction>, +switches: +List<M.SwitchTable>) -> ScanWork:
  match instruction:
    case M.Instruction{op, a, b, c, position}:
      ScanWork{rest, U32.add(offset, width), Con{M.Instruction{op, a, b, c, position}, acc}, switches}

def scan_piece_switched(table: M.SwitchTable, instruction: M.Instruction, +rest: +List<U32>, width: U32, offset: U32, +acc: +List<M.Instruction>, +switches: +List<M.SwitchTable>) -> ScanWork:
  match instruction:
    case M.Instruction{op, a, b, c, position}:
      +switchIndex : U32 = M.length(M.SwitchTable, switches)
      ScanWork{rest, U32.add(offset, width), Con{M.Instruction{op, a, switchIndex, c, position}, acc}, Con{table, switches}}

def scan_piece_added(added: +List<M.SwitchTable>, instruction: M.Instruction, +rest: +List<U32>, width: U32, offset: U32, +acc: +List<M.Instruction>, +switches: +List<M.SwitchTable>) -> ScanWork:
  match added:
    case Nil{}: scan_piece_plain(instruction, rest, width, offset, acc, switches)
    case Con{table, _}: scan_piece_switched(table, instruction, rest, width, offset, acc, switches)

def scan_piece_decoded(instruction: M.Instruction, +rest: +List<U32>, width: U32, +added: +List<M.SwitchTable>, offset: U32, +acc: +List<M.Instruction>, +switches: +List<M.SwitchTable>) -> ScanWork:
  scan_piece_added(added, instruction, rest, width, offset, acc, switches)

def scan_piece(piece: Result<&2, &2, String, Piece>, offset: U32, +acc: +List<M.Instruction>, +switches: +List<M.SwitchTable>) -> Result<&2, &2, String, ScanWork>:
  match piece:
    case Fail{error}: Fail{error}
    case Done{Piece{instruction, rest, width, added}}:
      Done{scan_piece_decoded(instruction, rest, width, added, offset, acc, switches)}

def scan_work_bytes(value: ScanWork) -> +List<U32>:
  match value:
    case ScanWork{bytes, offset, instructions, switches}: bytes

def scan_work_offset(value: ScanWork) -> U32:
  match value:
    case ScanWork{bytes, offset, instructions, switches}: offset

def scan_work_instructions(value: ScanWork) -> +List<M.Instruction>:
  match value:
    case ScanWork{bytes, offset, instructions, switches}: instructions

def scan_work_switches(value: ScanWork) -> +List<M.SwitchTable>:
  match value:
    case ScanWork{bytes, offset, instructions, switches}: switches

@unsafe def scan(fuel: Nat, bytes: +List<U32>, +offset: U32, +name: String, +acc: +List<M.Instruction>, +switches: +List<M.SwitchTable>) -> Result<&2, &2, String, Decoded>:
  match fuel bytes:
    case _ Nil{}:
      Done{Decoded{M.reverse(M.Instruction, acc), M.reverse(M.SwitchTable, switches)}}
    case 0n _:
      Fail{"InvalidBytecode: instruction limit in " ++ name}
    case 1n+f Con{+op, rest}:
      do Result<&2, &2, String, Decoded>:
        +work : ScanWork <- scan_piece(located(Piece, one(format(op), op, rest, offset), name, offset), offset, acc, switches)
        tail : Decoded <- scan(f, scan_work_bytes(work), scan_work_offset(work), name, scan_work_instructions(work), scan_work_switches(work))
        return tail


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

def resolve_switch_targets(targets: +List<U32>, +map: +List<Boundary>, +length: U32, +name: String, +offset: U32) -> Result<&2, &2, String, +List<U32>>:
  match targets:
    case Nil{}:
      Done{Nil{}}
    case Con{+target_offset, rest}:
      do Result<&2, &2, String, +List<U32>>:
        located(Unit, require(U32.is_lt(target_offset, length), "InvalidBytecode: switch target outside code"), name, offset)
        pc : U32 <- located(U32, target(map, target_offset), name, offset)
        tail : +List<U32> <- resolve_switch_targets(rest, map, length, name, offset)
        return Con{pc, tail}

def switch_offsets(instructions: +List<M.Instruction>, +acc: +List<U32>) -> +List<U32>:
  match instructions:
    case Nil{}: M.reverse(U32, acc)
    case Con{M.Instruction{+op, a, b, c, offset}, rest}:
      switch_offsets(rest, Bool.pick(+List<U32>, U32.is_eq(op, 170) || U32.is_eq(op, 171), Con{offset, acc}, acc))
def resolve_switches(switches: +List<M.SwitchTable>, offsets: +List<U32>, +map: +List<Boundary>, +length: U32, +name: String) -> Result<&2, &2, String, +List<M.SwitchTable>>:
  match switches offsets:
    case Nil{} Nil{}:
      Done{Nil{}}
    case Con{M.SwitchTable{kind, low, high, keys, targets}, rest} Con{offset, offsets_tail}:
      do Result<&2, &2, String, +List<M.SwitchTable>>:
        resolved : +List<U32> <- resolve_switch_targets(targets, map, length, name, offset)
        tail : +List<M.SwitchTable> <- resolve_switches(rest, offsets_tail, map, length, name)
        return Con{M.SwitchTable{kind, low, high, keys, resolved}, tail}
    case _ _:
      Fail{"InvalidBytecode: switch table/offset count mismatch"}

def resolve_instruction(relative: Bool, op: U32, +a: U32, b: U32, c: U32, +offset: U32, map: +List<Boundary>, length: U32) -> Result<&2, &2, String, M.Instruction>:
  match relative:
    case False{}:
      Done{M.Instruction{op, a, b, c, offset}}
    case True{}:
      do Result<&2, &2, String, M.Instruction>:
        require((a < length : U32), "InvalidBytecode: branch target outside code")
        pc : U32 <- located(U32, target(map, a), "", offset)
        return M.Instruction{op, pc, b, c, offset}

def resolve(instructions: +List<M.Instruction>, +map: +List<Boundary>, +length: U32, +name: String) -> Result<&2, &2, String, +List<M.Instruction>>:
  match instructions:
    case Nil{}:
      Done{Nil{}}
    case Con{M.Instruction{+op, a, b, c, +offset}, rest}:
      do Result<&2, &2, String, +List<M.Instruction>>:
        instruction : M.Instruction <- located(M.Instruction, resolve_instruction(branch(op) || U32.is_eq(op, 170) || U32.is_eq(op, 171), op, a, b, c, offset, map, length), name, offset)
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

def method_decoded(flags: U32, +name: String, +descriptor: String, maxStack: U32, maxLocals: U32, +code: +List<U32>, handlers: +List<M.Handler>, attributes: +List<M.Attribute>, decoded: Decoded, +label: String) -> Result<&2, &2, String, M.Method>:
  match decoded:
    case Decoded{+raw, tables}:
      do Result<&2, &2, String, M.Method>:
        +length : U32 = M.length(U32, code)
        +map : +List<Boundary> = boundaries(raw, 0, length)
        instructions : +List<M.Instruction> <- resolve(raw, map, length, label)
        offsets : +List<U32> = switch_offsets(raw, Nil{})
        switches : +List<M.SwitchTable> <- resolve_switches(tables, offsets, map, length, label)
        converted : +List<M.Handler> <- resolve_handlers(handlers, map, length, label)
        return M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, converted, attributes, switches}

def method(value: M.Method) -> Result<&2, &2, String, M.Method>:
  match value:
    case M.Method{flags, +name, +descriptor, maxStack, maxLocals, +code, old, handlers, attributes, _}:
      do Result<&2, &2, String, M.Method>:
        +label : String = name ++ descriptor
        decoded : Decoded <- scan(List.length(&2, U32, code), code, 0, label, Nil{}, Nil{})
        parsed : M.Method <- method_decoded(flags, name, descriptor, maxStack, maxLocals, code, handlers, attributes, decoded, label)
        return parsed
