import Base
import ../model.bend as M
import ./reader.bend as R
import ./constant_pool.bend as CP

def word_value(word: R.RWord) -> U32:
  match word:
    case R.RWord{reader, value}:
      value

def word_reader(word: R.RWord) -> R.Reader:
  match word:
    case R.RWord{reader, value}:
      reader

def bytes_value(bytes: R.RBytes) -> +List<U32>:
  match bytes:
    case R.RBytes{reader, value}:
      value

def bytes_reader(bytes: R.RBytes) -> R.Reader:
  match bytes:
    case R.RBytes{reader, value}:
      reader

type Attributes is Data:
  Attributes{reader: R.Reader, values: +List<M.Attribute>}

# A byte budget also bounds the aggregate number of metadata nodes: every
# encoded node consumes at least one byte. Check lengths before slicing.
def read_bounded(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, acc: +List<M.Attribute>, +budget: U32) -> Result<&2, &2, String, Attributes>:
  match count:
    case 0n:
      Done{Attributes{reader, M.reverse(M.Attribute, acc)}}
    case 1n+p:
      do Result<&2, &2, String, Attributes>:
        +name_word : R.RWord <- R.read_u2(reader)
        name : String <- CP.utf(pool, word_value(name_word))
        +length_word : R.RWord <- R.read_u4(word_reader(name_word))
        +length : U32 = word_value(length_word)
        R.require(U32.is_le(length, budget), "VmError.InvalidClassFile: attribute byte budget exceeded")
        +bytes : R.RBytes <- R.slice(word_reader(length_word), length)
        value : +List<U32> = bytes_value(bytes)
        result : Attributes <- read_bounded(p, bytes_reader(bytes), pool, Con{M.Attribute{name, value}, acc}, (budget - length : U32))
        return result

def read_go(+count: Nat, reader: R.Reader, +pool: +List<M.Constant>, acc: +List<M.Attribute>) -> Result<&2, &2, String, Attributes>:
  do Result<&2, &2, String, Attributes>:
    R.require(Nat.is_le(count, 4096n), "VmError.InvalidClassFile: too many attributes")
    read_bounded(count, reader, pool, acc, 262144)

def parse(reader: R.Reader, pool: +List<M.Constant>) -> Result<&2, &2, String, Attributes>:
  do Result<&2, &2, String, Attributes>:
    +count_word : R.RWord <- R.read_u2(reader)
    count : U32 = word_value(count_word)
    result : Attributes <- read_go(U32.to_nat(count), word_reader(count_word), pool, Nil{})
    return result

def named_go(values: +List<M.Attribute>, +name: String, +acc: +List<M.Attribute>) -> +List<M.Attribute>:
  match values:
    case Nil{}:
      M.reverse(M.Attribute, acc)
    case Con{M.Attribute{+kind, +bytes}, tail}:
      named_go(tail, name, Bool.pick(+List<M.Attribute>, String.eq(kind, name), Con{M.Attribute{kind, bytes}, acc}, acc))
    case Con{M.ValidatedAnnotations{metadata}, tail}: named_go(tail, name, acc)

def named(values: +List<M.Attribute>, name: String) -> +List<M.Attribute>:
  named_go(values, name, Nil{})
