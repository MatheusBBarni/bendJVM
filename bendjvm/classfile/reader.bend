import Base
import ../model.bend as M

type Reader is Data:
  Reader{bytes: +List<U32>, offset: U32, left: U32}

type RWord is Data:
  RWord{reader: Reader, value: U32}

type RBytes is Data:
  RBytes{reader: Reader, value: +List<U32>}

def require(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{message}

def new(+bytes: +List<U32>) -> Reader:
  Reader{bytes, 0, M.length(U32, bytes)}

def position(reader: Reader) -> U32:
  match reader:
    case Reader{bytes, offset, left}:
      offset

def remaining(reader: Reader) -> U32:
  match reader:
    case Reader{bytes, offset, left}:
      left

def read_u1(reader: Reader) -> Result<&2, &2, String, RWord>:
  match reader:
    case Reader{Nil{}, offset, left}:
      Fail{"VmError.InvalidClassFile: truncated byte at " ++ U32.show(offset)}
    case Reader{Con{+h, t}, +offset, left}:
      do Result<&2, &2, String, RWord>:
        require(U32.is_le(h, 255), "VmError.InvalidClassFile: non-byte input at " ++ U32.show(offset))
        return RWord{Reader{t, (offset + 1 : U32), (left - 1 : U32)}, h}

def finish_u2(second: RWord, first: U32) -> RWord:
  match second:
    case RWord{reader, value}:
      RWord{reader, (first * 256 + value : U32)}

def read_u2_second(reader: Reader, first: U32) -> Result<&2, &2, String, RWord>:
  do Result<&2, &2, String, RWord>:
    second : RWord <- read_u1(reader)
    return finish_u2(second, first)

def read_u2_first(first: RWord) -> Result<&2, &2, String, RWord>:
  match first:
    case RWord{reader, value}:
      read_u2_second(reader, value)

def read_u2(reader: Reader) -> Result<&2, &2, String, RWord>:
  do Result<&2, &2, String, RWord>:
    first : RWord <- read_u1(reader)
    second : RWord <- read_u2_first(first)
    return second

def finish_u4(second: RWord, first: U32) -> RWord:
  match second:
    case RWord{reader, value}:
      RWord{reader, (first * 65536 + value : U32)}

def read_u4_second(reader: Reader, first: U32) -> Result<&2, &2, String, RWord>:
  do Result<&2, &2, String, RWord>:
    second : RWord <- read_u2(reader)
    return finish_u4(second, first)

def read_u4_first(first: RWord) -> Result<&2, &2, String, RWord>:
  match first:
    case RWord{reader, value}:
      read_u4_second(reader, value)

def read_u4(reader: Reader) -> Result<&2, &2, String, RWord>:
  do Result<&2, &2, String, RWord>:
    first : RWord <- read_u2(reader)
    second : RWord <- read_u4_first(first)
    return second

def slice_go(count: Nat, reader: Reader, acc: +List<U32>) -> Result<&2, &2, String, RBytes>:
  match count:
    case 0n:
      Done{RBytes{reader, M.reverse(U32, acc)}}
    case 1n+p:
      match reader:
        case Reader{Nil{}, offset, left}:
          Fail{"VmError.InvalidClassFile: truncated byte at " ++ U32.show(offset)}
        case Reader{Con{+h, t}, +offset, left}:
          do Result<&2, &2, String, RBytes>:
            require(U32.is_le(h, 255), "VmError.InvalidClassFile: non-byte input at " ++ U32.show(offset))
            result : RBytes <- slice_go(p, Reader{t, (offset + 1 : U32), (left - 1 : U32)}, Con{h, acc})
            return result

def slice(+reader: Reader, +count: U32) -> Result<&2, &2, String, RBytes>:
  do Result<&2, &2, String, RBytes>:
    require(U32.is_le(count, remaining(reader)), "VmError.InvalidClassFile: truncated slice at " ++ U32.show(position(reader)))
    result : RBytes <- slice_go(U32.to_nat(count), reader, Nil{})
    return result

def skip_go(count: Nat, reader: Reader) -> Result<&2, &2, String, Reader>:
  match count:
    case 0n:
      Done{reader}
    case 1n+p:
      match reader:
        case Reader{Nil{}, offset, left}:
          Fail{"VmError.InvalidClassFile: truncated byte at " ++ U32.show(offset)}
        case Reader{Con{+h, t}, +offset, left}:
          do Result<&2, &2, String, Reader>:
            require(U32.is_le(h, 255), "VmError.InvalidClassFile: non-byte input at " ++ U32.show(offset))
            result : Reader <- skip_go(p, Reader{t, (offset + 1 : U32), (left - 1 : U32)})
            return result

def skip(+reader: Reader, +count: U32) -> Result<&2, &2, String, Reader>:
  do Result<&2, &2, String, Reader>:
    require(U32.is_le(count, remaining(reader)), "VmError.InvalidClassFile: truncated skip at " ++ U32.show(position(reader)))
    result : Reader <- skip_go(U32.to_nat(count), reader)
    return result
def finish(reader: Reader) -> Result<&2, &2, String, Unit>:
  require(U32.is_eq(remaining(reader), 0), "VmError.InvalidClassFile: trailing bytes")
