import Base
import ../model.bend as M
import ../bytecode/decode.bend as Decode
import ../classfile/descriptor.bend as D
import ../classfile/constant_pool.bend as CP

# Inputs and outputs are top-first slot tags. Kind 1/2 read/write a local,
# kind 3 increments an integer local, kind 4 permutes category-one values.
type Rule is Data:
  Rule{kind: U32, tag: U32, inputs: +List<U32>, outputs: +List<U32>}

def supported(value: M.JvmType) -> Bool:
  match value:
    case M.Primitive{74}: False{}
    case M.Primitive{68}: False{}
    case M.ArrayType{element}: supported(element)
    case _: True{}

def tags(values: +List<M.JvmType>) -> Result<&2, &2, String, +List<U32>>:
  match values:
    case Nil{}:
      Done{Nil{}}
    case Con{+value, rest}:
      do Result<&2, &2, String, +List<U32>>:
        Decode.require(supported(value), "VerifyError: category-two descriptor is unsupported")
        tail : +List<U32> <- tags(rest)
        return Con{D.slot_tag(value), tail}

def result_tag(+value: M.JvmType) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    Decode.require(supported(value), "VerifyError: category-two descriptor is unsupported")
    return D.slot_tag(value)

def cp_value(value: Maybe<&2, M.Constant>) -> Result<&2, &2, String, M.Constant>:
  match value:
    case None{}: Fail{"VerifyError: constant-pool index out of bounds"}
    case Some{M.Unused{}}: Fail{"VerifyError: invalid constant-pool slot"}
    case Some{entry}: Done{entry}

def cp(+pool: +List<M.Constant>, +index: U32) -> Result<&2, &2, String, M.Constant>:
  do Result<&2, &2, String, M.Constant>:
    Decode.require(U32.is_ne(index, 0), "VerifyError: constant-pool index is zero")
    cp_value(M.nth(M.Constant, pool, index))

def cp_tag(entry: M.Constant) -> U32:
  match entry:
    case M.Number{tag, bits}: tag
    case M.Index{tag, index}: tag
    case M.PairIndex{tag, first, second}: tag
    case M.Utf{text}: 1
    case M.Unused{}: 0

def ldc(entry: M.Constant, +pool: +List<M.Constant>) -> Result<&2, &2, String, Rule>:
  match entry:
    case M.Number{3, bits}: Done{Rule{0, 0, Nil{}, [1]}}
    case M.Number{4, bits}: Done{Rule{0, 0, Nil{}, [2]}}
    case M.Index{8, index}:
      do Result<&2, &2, String, Rule>:
        text : String <- CP.utf(pool, index)
        return Rule{0, 0, Nil{}, [3]}
    case _: Fail{"VerifyError: ldc requires Integer, Float, or String constant"}

def field_rule(op: U32, +tag: U32) -> Rule:
  match op:
    case 178: Rule{0, 0, Nil{}, [tag]}
    case 179: Rule{0, 0, [tag], Nil{}}
    case 180: Rule{0, 0, [3], [tag]}
    case _: Rule{0, 0, [tag, 3], Nil{}}

def field(+op: U32, +index: U32, +pool: +List<M.Constant>) -> Result<&2, &2, String, Rule>:
  do Result<&2, &2, String, Rule>:
    entry : M.Constant <- cp(pool, index)
    Decode.require(U32.is_eq(cp_tag(entry), 9), "VerifyError: field operand is not Fieldref")
    member : CP.Member <- CP.member(pool, index)
    value : M.JvmType <- D.parse_field(CP.member_descriptor(member))
    slot : U32 <- result_tag(value)
    return field_rule(op, slot)

def call_tag(op: U32, +tag: U32) -> Bool:
  match op:
    case 185: U32.is_eq(tag, 11)
    case 182: U32.is_eq(tag, 10)
    case _: U32.is_eq(tag, 10) || U32.is_eq(tag, 11)

def receiver(op: U32, parameters: +List<U32>) -> +List<U32>:
  match op:
    case 184: parameters
    case _: M.append(U32, parameters, [3])

def returns(tag: U32) -> +List<U32>:
  match tag:
    case 0: Nil{}
    case _: [tag]

def interface_count(op: U32, count: U32, parameters: +List<U32>) -> Bool:
  match op:
    case 185: U32.is_eq(count, (M.length(U32, parameters) + 1 : U32))
    case _: True{}

def call(+op: U32, +index: U32, count: U32, +pool: +List<M.Constant>) -> Result<&2, &2, String, Rule>:
  do Result<&2, &2, String, Rule>:
    entry : M.Constant <- cp(pool, index)
    Decode.require(call_tag(op, cp_tag(entry)), "VerifyError: invocation constant-pool tag mismatch")
    member : CP.Member <- CP.member(pool, index)
    +parsed : M.Descriptor <- D.parse_method(CP.member_descriptor(member))
    +args : +List<U32> <- tags(D.parameter_types(parsed))
    resultTag : U32 <- result_tag(D.result_type(parsed))
    Decode.require(interface_count(op, count, args), "VerifyError: invokeinterface count does not match descriptor")
    return Rule{0, 0, receiver(op, M.reverse(U32, args)), returns(resultTag)}

def class_rule(op: U32) -> Rule:
  match op:
    case 187: Rule{0, 0, Nil{}, [3]}
    case 189: Rule{0, 0, [1], [3]}
    case 192: Rule{0, 0, [3], [3]}
    case _: Rule{0, 0, [3], [1]}

def new_name(op: U32, name: String) -> Bool:
  match op name:
    case 187 SCon{Chr{91}, rest}: False{}
    case _ _: True{}

def class_operand(+op: U32, +index: U32, +pool: +List<M.Constant>) -> Result<&2, &2, String, Rule>:
  do Result<&2, &2, String, Rule>:
    entry : M.Constant <- cp(pool, index)
    Decode.require(U32.is_eq(cp_tag(entry), 7), "VerifyError: class operand is not Class constant")
    name : String <- CP.class_name(pool, index)
    Decode.require(new_name(op, name), "VerifyError: new cannot allocate an array class")
    return class_rule(op)

def primitive_array(atype: U32) -> Bool:
  match atype:
    case 4: True{}
    case 5: True{}
    case 6: True{}
    case 8: True{}
    case 9: True{}
    case 10: True{}
    case _: False{}

def returning(+tag: U32, expected: U32) -> Result<&2, &2, String, Rule>:
  do Result<&2, &2, String, Rule>:
    Decode.require(U32.is_eq(tag, expected), "VerifyError: return opcode does not match method descriptor")
    return Rule{0, 0, returns(tag), Nil{}}

def plain(op: U32, expected: U32) -> Result<&2, &2, String, Rule>:
  match op:
    case 0: Done{Rule{0, 0, Nil{}, Nil{}}}
    case 1: Done{Rule{0, 0, Nil{}, [3]}}
    case 2: Done{Rule{0, 0, Nil{}, [1]}}
    case 3: Done{Rule{0, 0, Nil{}, [1]}}
    case 4: Done{Rule{0, 0, Nil{}, [1]}}
    case 5: Done{Rule{0, 0, Nil{}, [1]}}
    case 6: Done{Rule{0, 0, Nil{}, [1]}}
    case 7: Done{Rule{0, 0, Nil{}, [1]}}
    case 8: Done{Rule{0, 0, Nil{}, [1]}}
    case 11: Done{Rule{0, 0, Nil{}, [2]}}
    case 12: Done{Rule{0, 0, Nil{}, [2]}}
    case 13: Done{Rule{0, 0, Nil{}, [2]}}
    case 16: Done{Rule{0, 0, Nil{}, [1]}}
    case 17: Done{Rule{0, 0, Nil{}, [1]}}
    case 21: Done{Rule{1, 1, Nil{}, [1]}}
    case 23: Done{Rule{1, 2, Nil{}, [2]}}
    case 25: Done{Rule{1, 3, Nil{}, [3]}}
    case 26: Done{Rule{1, 1, Nil{}, [1]}}
    case 27: Done{Rule{1, 1, Nil{}, [1]}}
    case 28: Done{Rule{1, 1, Nil{}, [1]}}
    case 29: Done{Rule{1, 1, Nil{}, [1]}}
    case 34: Done{Rule{1, 2, Nil{}, [2]}}
    case 35: Done{Rule{1, 2, Nil{}, [2]}}
    case 36: Done{Rule{1, 2, Nil{}, [2]}}
    case 37: Done{Rule{1, 2, Nil{}, [2]}}
    case 42: Done{Rule{1, 3, Nil{}, [3]}}
    case 43: Done{Rule{1, 3, Nil{}, [3]}}
    case 44: Done{Rule{1, 3, Nil{}, [3]}}
    case 45: Done{Rule{1, 3, Nil{}, [3]}}
    case 46: Done{Rule{0, 0, [1, 3], [1]}}
    case 48: Done{Rule{0, 0, [1, 3], [2]}}
    case 50: Done{Rule{0, 0, [1, 3], [3]}}
    case 51: Done{Rule{0, 0, [1, 3], [1]}}
    case 52: Done{Rule{0, 0, [1, 3], [1]}}
    case 53: Done{Rule{0, 0, [1, 3], [1]}}
    case 54: Done{Rule{2, 1, [1], Nil{}}}
    case 56: Done{Rule{2, 2, [2], Nil{}}}
    case 58: Done{Rule{2, 3, [3], Nil{}}}
    case 59: Done{Rule{2, 1, [1], Nil{}}}
    case 60: Done{Rule{2, 1, [1], Nil{}}}
    case 61: Done{Rule{2, 1, [1], Nil{}}}
    case 62: Done{Rule{2, 1, [1], Nil{}}}
    case 67: Done{Rule{2, 2, [2], Nil{}}}
    case 68: Done{Rule{2, 2, [2], Nil{}}}
    case 69: Done{Rule{2, 2, [2], Nil{}}}
    case 70: Done{Rule{2, 2, [2], Nil{}}}
    case 75: Done{Rule{2, 3, [3], Nil{}}}
    case 76: Done{Rule{2, 3, [3], Nil{}}}
    case 77: Done{Rule{2, 3, [3], Nil{}}}
    case 78: Done{Rule{2, 3, [3], Nil{}}}
    case 79: Done{Rule{0, 0, [1, 1, 3], Nil{}}}
    case 81: Done{Rule{0, 0, [2, 1, 3], Nil{}}}
    case 83: Done{Rule{0, 0, [3, 1, 3], Nil{}}}
    case 84: Done{Rule{0, 0, [1, 1, 3], Nil{}}}
    case 85: Done{Rule{0, 0, [1, 1, 3], Nil{}}}
    case 86: Done{Rule{0, 0, [1, 1, 3], Nil{}}}
    case 87: Done{Rule{4, 0, Nil{}, Nil{}}}
    case 88: Done{Rule{4, 0, Nil{}, Nil{}}}
    case 89: Done{Rule{4, 0, Nil{}, Nil{}}}
    case 90: Done{Rule{4, 0, Nil{}, Nil{}}}
    case 91: Done{Rule{4, 0, Nil{}, Nil{}}}
    case 92: Done{Rule{4, 0, Nil{}, Nil{}}}
    case 93: Done{Rule{4, 0, Nil{}, Nil{}}}
    case 94: Done{Rule{4, 0, Nil{}, Nil{}}}
    case 95: Done{Rule{4, 0, Nil{}, Nil{}}}
    case 96: Done{Rule{0, 0, [1, 1], [1]}}
    case 98: Done{Rule{0, 0, [2, 2], [2]}}
    case 100: Done{Rule{0, 0, [1, 1], [1]}}
    case 102: Done{Rule{0, 0, [2, 2], [2]}}
    case 104: Done{Rule{0, 0, [1, 1], [1]}}
    case 106: Done{Rule{0, 0, [2, 2], [2]}}
    case 108: Done{Rule{0, 0, [1, 1], [1]}}
    case 110: Done{Rule{0, 0, [2, 2], [2]}}
    case 112: Done{Rule{0, 0, [1, 1], [1]}}
    case 114: Done{Rule{0, 0, [2, 2], [2]}}
    case 116: Done{Rule{0, 0, [1], [1]}}
    case 118: Done{Rule{0, 0, [2], [2]}}
    case 120: Done{Rule{0, 0, [1, 1], [1]}}
    case 122: Done{Rule{0, 0, [1, 1], [1]}}
    case 124: Done{Rule{0, 0, [1, 1], [1]}}
    case 126: Done{Rule{0, 0, [1, 1], [1]}}
    case 128: Done{Rule{0, 0, [1, 1], [1]}}
    case 130: Done{Rule{0, 0, [1, 1], [1]}}
    case 132: Done{Rule{3, 1, Nil{}, Nil{}}}
    case 134: Done{Rule{0, 0, [1], [2]}}
    case 139: Done{Rule{0, 0, [2], [1]}}
    case 145: Done{Rule{0, 0, [1], [1]}}
    case 146: Done{Rule{0, 0, [1], [1]}}
    case 147: Done{Rule{0, 0, [1], [1]}}
    case 149: Done{Rule{0, 0, [2, 2], [1]}}
    case 150: Done{Rule{0, 0, [2, 2], [1]}}
    case 153: Done{Rule{0, 0, [1], Nil{}}}
    case 154: Done{Rule{0, 0, [1], Nil{}}}
    case 155: Done{Rule{0, 0, [1], Nil{}}}
    case 156: Done{Rule{0, 0, [1], Nil{}}}
    case 157: Done{Rule{0, 0, [1], Nil{}}}
    case 158: Done{Rule{0, 0, [1], Nil{}}}
    case 159: Done{Rule{0, 0, [1, 1], Nil{}}}
    case 160: Done{Rule{0, 0, [1, 1], Nil{}}}
    case 161: Done{Rule{0, 0, [1, 1], Nil{}}}
    case 162: Done{Rule{0, 0, [1, 1], Nil{}}}
    case 163: Done{Rule{0, 0, [1, 1], Nil{}}}
    case 164: Done{Rule{0, 0, [1, 1], Nil{}}}
    case 165: Done{Rule{0, 0, [3, 3], Nil{}}}
    case 166: Done{Rule{0, 0, [3, 3], Nil{}}}
    case 167: Done{Rule{0, 0, Nil{}, Nil{}}}
    case 172: returning(1, expected)
    case 174: returning(2, expected)
    case 176: returning(3, expected)
    case 177: returning(0, expected)
    case 190: Done{Rule{0, 0, [3], [1]}}
    case 191: Done{Rule{0, 0, [3], Nil{}}}
    case 198: Done{Rule{0, 0, [3], Nil{}}}
    case 199: Done{Rule{0, 0, [3], Nil{}}}
    case 200: Done{Rule{0, 0, Nil{}, Nil{}}}
    case _: Fail{"VerifyError: unsupported instruction contract"}

def select(op: U32, a: U32, b: U32, c: U32, pool: +List<M.Constant>, expected: U32) -> Result<&2, &2, String, Rule>:
  match op:
    case 18:
      do Result<&2, &2, String, Rule>:
        entry : M.Constant <- cp(pool, a)
        ldc(entry, pool)
    case 19:
      do Result<&2, &2, String, Rule>:
        entry : M.Constant <- cp(pool, a)
        ldc(entry, pool)
    case 178: field(178, a, pool)
    case 179: field(179, a, pool)
    case 180: field(180, a, pool)
    case 181: field(181, a, pool)
    case 182: call(182, a, b, pool)
    case 183: call(183, a, b, pool)
    case 184: call(184, a, b, pool)
    case 185: call(185, a, b, pool)
    case 187: class_operand(187, a, pool)
    case 188:
      do Result<&2, &2, String, Rule>:
        Decode.require(primitive_array(a), "VerifyError: unsupported newarray element type")
        return Rule{0, 0, [1], [3]}
    case 189: class_operand(189, a, pool)
    case 192: class_operand(192, a, pool)
    case 193: class_operand(193, a, pool)
    case 196: plain(c, expected)
    case _: plain(op, expected)

def local_bounds(rule: Rule, index: U32, maximum: U32) -> Result<&2, &2, String, Rule>:
  match rule:
    case Rule{+kind, tag, inputs, outputs}:
      do Result<&2, &2, String, Rule>:
        Decode.require(U32.is_eq(kind, 0) || U32.is_eq(kind, 4) || (index < maximum : U32), "VerifyError: local index exceeds max_locals")
        return Rule{kind, tag, inputs, outputs}

def verify(instruction: M.Instruction, pool: +List<M.Constant>, expected: U32, maximum: U32) -> Result<&2, &2, String, Rule>:
  match instruction:
    case M.Instruction{op, +a, b, c, offset}:
      do Result<&2, &2, String, Rule>:
        rule : Rule <- select(op, a, b, c, pool, expected)
        local_bounds(rule, a, maximum)
