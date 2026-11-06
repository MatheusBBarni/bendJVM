import Base
import ../model.bend as M
import ../classfile/reader.bend as R
import ../classfile/constant_pool.bend as CP

type Verification is Data:
  Top{}
  Integer{}
  Float{}
  Double{}
  Long{}
  Null{}
  UninitializedThis{}
  Object{index: U32, name: String}
  Uninitialized{offset: U32}

type Frame is Data:
  Same{offset: U32}
  SameLocalsOne{offset: U32, stack: Verification}
  Chop{offset: U32, count: U32}
  Append{offset: U32, locals: +List<Verification>}
  Full{offset: U32, locals: +List<Verification>, stack: +List<Verification>}

type Frames is Data:
  Frames{codeLength: U32, frames: +List<Frame>}

type VRead is Data:
  VRead{reader: R.Reader, value: Verification}

type FRead is Data:
  FRead{reader: R.Reader, kind: U32, delta: U32, stack: +List<Verification>, locals: +List<Verification>, count: U32}
type VListRead is Data:
  VListRead{reader: R.Reader, values: +List<Verification>}

type FrameListRead is Data:
  FrameListRead{reader: R.Reader, frames: +List<Frame>}


def require(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  R.require(ok, "VmError.InvalidClassFile: StackMapTable " ++ message)
def stack_word_reader(word: R.RWord) -> R.Reader:
  match word:
    case R.RWord{reader, value}: reader

def stack_word_value(word: R.RWord) -> U32:
  match word:
    case R.RWord{reader, value}: value

def vread_reader(value: VRead) -> R.Reader:
  match value:
    case VRead{reader, value}: reader

def vread_value(value: VRead) -> Verification:
  match value:
    case VRead{reader, value}: value

def verification_list_reader(value: VListRead) -> R.Reader:
  match value:
    case VListRead{reader, values}: reader

def verification_list_values(value: VListRead) -> +List<Verification>:
  match value:
    case VListRead{reader, values}: values

def frame_list_reader(value: FrameListRead) -> R.Reader:
  match value:
    case FrameListRead{reader, frames}: reader

def frame_list_values(value: FrameListRead) -> +List<Frame>:
  match value:
    case FrameListRead{reader, frames}: frames



def verification_kind(afterTag: R.Reader, kind: U32, pool: +List<M.Constant>, codeLength: U32) -> Result<&2, &2, String, VRead>:
  match kind:
    case 0: Done{VRead{afterTag, Top{}}}
    case 1: Done{VRead{afterTag, Integer{}}}
    case 2: Done{VRead{afterTag, Float{}}}
    case 3: Done{VRead{afterTag, Double{}}}
    case 4: Done{VRead{afterTag, Long{}}}
    case 5: Done{VRead{afterTag, Null{}}}
    case 6: Done{VRead{afterTag, UninitializedThis{}}}
    case 7:
      do Result<&2, &2, String, VRead>:
        +cp : R.RWord <- R.read_u2(afterTag)
        +index : U32 = stack_word_value(cp)
        name : String <- CP.class_name(pool, index)
        return VRead{stack_word_reader(cp), Object{index, name}}
    case 8:
      do Result<&2, &2, String, VRead>:
        +pc : R.RWord <- R.read_u2(afterTag)
        +offset : U32 = stack_word_value(pc)
        require(U32.is_lt(offset, codeLength), "uninitialized offset out of code")
        return VRead{stack_word_reader(pc), Uninitialized{offset}}
    case _:
      Fail{"VmError.InvalidClassFile: StackMapTable invalid verification_type_info tag " ++ U32.show(kind)}

def verification(reader: R.Reader, pool: +List<M.Constant>, codeLength: U32) -> Result<&2, &2, String, VRead>:
  do Result<&2, &2, String, VRead>:
    +tag : R.RWord <- R.read_u1(reader)
    value : VRead <- verification_kind(stack_word_reader(tag), stack_word_value(tag), pool, codeLength)
    return value
def list_values(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, +codeLength: U32, acc: +List<Verification>) -> Result<&2, &2, String, VListRead>:
  match count:
    case 0n: Done{VListRead{reader, M.reverse(Verification, acc)}}
    case 1n+rest:
      do Result<&2, &2, String, VListRead>:
        +item : VRead <- verification(reader, pool, codeLength)
        result : VListRead <- list_values(rest, vread_reader(item), pool, codeLength, Con{vread_value(item), acc})
        return result
def one_stack_short(tag: U32, reader: R.Reader, pool: +List<M.Constant>, codeLength: U32) -> Result<&2, &2, String, FRead>:
  do Result<&2, &2, String, FRead>:
    +value : VRead <- verification(reader, pool, codeLength)
    return FRead{vread_reader(value), 1, (tag - 64 : U32), [vread_value(value)], Nil{}, 0}

def extended_one_stack(reader: R.Reader, pool: +List<M.Constant>, codeLength: U32) -> Result<&2, &2, String, FRead>:
  do Result<&2, &2, String, FRead>:
    +delta_word : R.RWord <- R.read_u2(reader)
    +value : VRead <- verification(stack_word_reader(delta_word), pool, codeLength)
    return FRead{vread_reader(value), 1, stack_word_value(delta_word), [vread_value(value)], Nil{}, 0}

def chop_frame(tag: U32, reader: R.Reader) -> Result<&2, &2, String, FRead>:
  do Result<&2, &2, String, FRead>:
    +delta : R.RWord <- R.read_u2(reader)
    return FRead{stack_word_reader(delta), 2, stack_word_value(delta), Nil{}, Nil{}, (251 - tag : U32)}

def same_extended(reader: R.Reader) -> Result<&2, &2, String, FRead>:
  do Result<&2, &2, String, FRead>:
    +delta : R.RWord <- R.read_u2(reader)
    return FRead{stack_word_reader(delta), 0, stack_word_value(delta), Nil{}, Nil{}, 0}

def append_frame(tag: U32, reader: R.Reader, pool: +List<M.Constant>, codeLength: U32) -> Result<&2, &2, String, FRead>:
  do Result<&2, &2, String, FRead>:
    +delta : R.RWord <- R.read_u2(reader)
    +count : U32 = (tag - 251 : U32)
    require(U32.is_le(count, R.remaining(stack_word_reader(delta))), "truncated verification values")
    +values : VListRead <- list_values(U32.to_nat(count), stack_word_reader(delta), pool, codeLength, Nil{})
    return FRead{verification_list_reader(values), 3, stack_word_value(delta), Nil{}, verification_list_values(values), count}

def full_frame(reader: R.Reader, +pool: +List<M.Constant>, +codeLength: U32) -> Result<&2, &2, String, FRead>:
  do Result<&2, &2, String, FRead>:
    +delta : R.RWord <- R.read_u2(reader)
    +local_count : R.RWord <- R.read_u2(stack_word_reader(delta))
    require(U32.is_le(stack_word_value(local_count), R.remaining(stack_word_reader(local_count))), "truncated verification values")
    +locals : VListRead <- list_values(U32.to_nat(stack_word_value(local_count)), stack_word_reader(local_count), pool, codeLength, Nil{})
    +stack_count : R.RWord <- R.read_u2(verification_list_reader(locals))
    require(U32.is_le(stack_word_value(stack_count), R.remaining(stack_word_reader(stack_count))), "truncated verification values")
    +stack : VListRead <- list_values(U32.to_nat(stack_word_value(stack_count)), stack_word_reader(stack_count), pool, codeLength, Nil{})
    return FRead{verification_list_reader(stack), 4, stack_word_value(delta), verification_list_values(stack), verification_list_values(locals), stack_word_value(stack_count)}

def frame_extended(+tag: U32, +reader: R.Reader, +pool: +List<M.Constant>, +codeLength: U32) -> Result<&2, &2, String, FRead>:
  match tag:
    case 247: extended_one_stack(reader, pool, codeLength)
    case _:
      Bool.pick(Result<&2, &2, String, FRead>, Bool.and(U32.is_ge(tag, 248), U32.is_le(tag, 250)),
        chop_frame(tag, reader),
        Bool.pick(Result<&2, &2, String, FRead>, U32.is_eq(tag, 251), same_extended(reader),
          Bool.pick(Result<&2, &2, String, FRead>, Bool.and(U32.is_ge(tag, 252), U32.is_le(tag, 254)), append_frame(tag, reader, pool, codeLength),
            Bool.pick(Result<&2, &2, String, FRead>, U32.is_eq(tag, 255), full_frame(reader, pool, codeLength),
              Fail{"VmError.InvalidClassFile: StackMapTable invalid frame_type " ++ U32.show(tag)}))))

def frame_one_stack(+tag: U32, +reader: R.Reader, +pool: +List<M.Constant>, +codeLength: U32) -> Result<&2, &2, String, FRead>:
  match tag:
    case _:
      Bool.pick(Result<&2, &2, String, FRead>, Bool.and(U32.is_ge(tag, 64), U32.is_le(tag, 127)),
        one_stack_short(tag, reader, pool, codeLength), frame_extended(tag, reader, pool, codeLength))

def frame_data(+tag: U32, +reader: R.Reader, pool: +List<M.Constant>, codeLength: U32) -> Result<&2, &2, String, FRead>:
  match tag:
    case _:
      Bool.pick(Result<&2, &2, String, FRead>, U32.is_le(tag, 63),
        Done{FRead{reader, 0, tag, Nil{}, Nil{}, 0}},
        frame_one_stack(tag, reader, pool, codeLength))

def fread_reader(value: FRead) -> R.Reader:
  match value:
    case FRead{reader, kind, delta, stack, locals, count}: reader

def fread_kind(value: FRead) -> U32:
  match value:
    case FRead{reader, kind, delta, stack, locals, count}: kind

def fread_delta(value: FRead) -> U32:
  match value:
    case FRead{reader, kind, delta, stack, locals, count}: delta

def fread_count(value: FRead) -> U32:
  match value:
    case FRead{reader, kind, delta, stack, locals, count}: count

def fread_stack(value: FRead) -> +List<Verification>:
  match value:
    case FRead{reader, kind, delta, +stack, locals, count}: stack

def fread_locals(value: FRead) -> +List<Verification>:
  match value:
    case FRead{reader, kind, delta, stack, +locals, count}: locals
def frame_offset(hasPrevious: Bool, +previous: U32, +delta: U32, +codeLength: U32) -> Result<&2, &2, String, U32>:
  match hasPrevious:
    case False{}:
      do Result<&2, &2, String, U32>:
        require(U32.is_lt(delta, codeLength), "frame offset delta out of code")
        return delta
    case True{}:
      do Result<&2, &2, String, U32>:
        require(U32.is_lt(delta, codeLength), "frame offset delta out of code")
        require(U32.is_lt(previous, codeLength), "frame offset out of code")
        remaining : U32 = (codeLength - previous - 1 : U32)
        require(U32.is_le(delta, remaining), "frame offset overflow or out of code")
        return (previous + delta + 1 : U32)

def one_stack_frame(offset: U32, stack: +List<Verification>) -> Result<&2, &2, String, Frame>:
  match stack:
    case Con{value, Nil{}}: Done{SameLocalsOne{offset, value}}
    case _: Fail{"VmError.InvalidClassFile: StackMapTable invalid one-stack frame"}

def frame_record(kind: U32, offset: U32, count: U32, locals: +List<Verification>, stack: +List<Verification>) -> Result<&2, &2, String, Frame>:
  match kind:
    case 0: Done{Same{offset}}
    case 1: one_stack_frame(offset, stack)
    case 2: Done{Chop{offset, count}}
    case 3: Done{Append{offset, locals}}
    case 4: Done{Full{offset, locals, stack}}
    case _: Fail{"VmError.InvalidClassFile: StackMapTable invalid frame record"}

def frame_loop(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, +codeLength: U32, previous: U32, hasPrevious: Bool, acc: +List<Frame>) -> Result<&2, &2, String, FrameListRead>:
  match count:
    case 0n: Done{FrameListRead{reader, M.reverse(Frame, acc)}}
    case 1n+rest:
      do Result<&2, &2, String, FrameListRead>:
        +tagWord : R.RWord <- R.read_u1(reader)
        +parsed : FRead <- frame_data(stack_word_value(tagWord), stack_word_reader(tagWord), pool, codeLength)
        +offset : U32 <- frame_offset(hasPrevious, previous, fread_delta(parsed), codeLength)
        frame : Frame <- frame_record(fread_kind(parsed), offset, fread_count(parsed), fread_locals(parsed), fread_stack(parsed))
        result : FrameListRead <- frame_loop(rest, fread_reader(parsed), pool, codeLength, offset, True{}, Con{frame, acc})
        return result

def parse(bytes: +List<U32>, +pool: +List<M.Constant>, +codeLength: U32) -> Result<&2, &2, String, Frames>:
  do Result<&2, &2, String, Frames>:
    reader : R.Reader = R.new(bytes)
    +countWord : R.RWord <- R.read_u2(reader)
    +body : R.Reader = stack_word_reader(countWord)
    +count : U32 = stack_word_value(countWord)
    require(U32.is_le(count, codeLength), "frame count exceeds code length")
    require(U32.is_le(count, R.remaining(body)), "truncated frame entries")
    +result : FrameListRead <- frame_loop(U32.to_nat(count), body, pool, codeLength, 0, False{}, Nil{})
    R.finish(frame_list_reader(result))
    return Frames{codeLength, frame_list_values(result)}

