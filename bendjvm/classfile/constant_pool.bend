import Base
import ../model.bend as M
import ./reader.bend as R
import ./descriptor.bend as D
import ./utf8.bend as Utf

type Member is Data:
  Member{owner: String, name: String, descriptor: String, tag: U32}
def member_owner(value: Member) -> String:
  Member{owner, name, descriptor, tag} = value
  owner

def member_name(value: Member) -> String:
  Member{owner, name, descriptor, tag} = value
  name

def member_descriptor(value: Member) -> String:
  Member{owner, name, descriptor, tag} = value
  descriptor

def member_tag(value: Member) -> U32:
  Member{owner, name, descriptor, tag} = value
  tag

type NameType is Data:
  NameType{name: String, descriptor: String}

type Entry is Data:
  Entry{reader: R.Reader, value: M.Constant, wide: Bool}

type Pool is Data:
  Pool{reader: R.Reader, values: +List<M.Constant>}

def tag(value: M.Constant) -> U32:
  match value:
    case M.Unused{}: 0
    case M.Utf{text}: 1
    case M.Number{kind, bits}: kind
    case M.Index{kind, index}: kind
    case M.PairIndex{kind, first, second}: kind

def found(value: Maybe<&2, M.Constant>) -> Result<&2, &2, String, M.Constant>:
  match value:
    case None{}:
      Fail{"VmError.InvalidConstantPool: index out of bounds"}
    case Some{M.Unused{}}:
      Fail{"VmError.InvalidConstantPool: reserved slot reference"}
    case Some{value}:
      Done{value}

def get(pool: +List<M.Constant>, +index: U32) -> Result<&2, &2, String, M.Constant>:
  do Result<&2, &2, String, M.Constant>:
    R.require(U32.is_ne(index, 0), "VmError.InvalidConstantPool: zero index")
    value : M.Constant <- found(M.nth(M.Constant, pool, index))
    return value

def expect_utf(value: M.Constant) -> Result<&2, &2, String, String>:
  match value:
    case M.Utf{text}:
      Done{text}
    case _:
      Fail{"VmError.InvalidConstantPool: expected Utf8"}

def utf(pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    value : M.Constant <- get(pool, index)
    text : String <- expect_utf(value)
    return text
def expect_string(+pool: +List<M.Constant>, value: M.Constant) -> Result<&2, &2, String, String>:
  match value:
    case M.Index{8, index}:
      utf(pool, index)
    case _:
      Fail{"VmError.InvalidConstantPool: expected String"}

def string(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    value : M.Constant <- get(pool, index)
    text : String <- expect_string(pool, value)
    return text


def expect_class(pool: +List<M.Constant>, value: M.Constant) -> Result<&2, &2, String, String>:
  match value:
    case M.Index{7, index}:
      utf(pool, index)
    case _:
      Fail{"VmError.InvalidConstantPool: expected Class"}

def class_name(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    value : M.Constant <- get(pool, index)
    name : String <- expect_class(pool, value)
    return name

def expect_name_type(+pool: +List<M.Constant>, value: M.Constant) -> Result<&2, &2, String, NameType>:
  match value:
    case M.PairIndex{12, first, second}:
      do Result<&2, &2, String, NameType>:
        name : String <- utf(pool, first)
        descriptor : String <- utf(pool, second)
        return NameType{name, descriptor}
    case _:
      Fail{"VmError.InvalidConstantPool: expected NameAndType"}

def name_type(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, NameType>:
  do Result<&2, &2, String, NameType>:
    value : M.Constant <- get(pool, index)
    result : NameType <- expect_name_type(pool, value)
    return result

def member_value(owner: String, pair: NameType, kind: U32) -> Member:
  match pair:
    case NameType{name, descriptor}:
      Member{owner, name, descriptor, kind}

def member_pair(check: Result<&2, &2, String, NameType>, owner: String, kind: U32) -> Result<&2, &2, String, Member>:
  match check:
    case Fail{error}:
      Fail{error}
    case Done{pair}:
      Done{member_value(owner, pair, kind)}

def expect_member(+pool: +List<M.Constant>, value: M.Constant) -> Result<&2, &2, String, Member>:
  match value:
    case M.PairIndex{+kind, first, second}:
      Result.bind(&2, &2, String, Unit, Member,
        R.require(Bool.and(U32.is_ge(kind, 9), U32.is_le(kind, 11)), "VmError.InvalidConstantPool: expected member reference"),
        unit =>
          Result.bind(&2, &2, String, String, Member, class_name(pool, first), owner =>
            member_pair(name_type(pool, second), owner, kind)))
    case _:
      Fail{"VmError.InvalidConstantPool: expected member reference"}

def member(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, Member>:
  do Result<&2, &2, String, Member>:
    value : M.Constant <- get(pool, index)
    result : Member <- expect_member(pool, value)
    return result
def member_owner_at(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    value : Member <- member(pool, index)
    return member_owner(value)

def member_name_at(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    value : Member <- member(pool, index)
    return member_name(value)

def member_descriptor_at(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    value : Member <- member(pool, index)
    return member_descriptor(value)
def member_components(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, +List<String>>:
  do Result<&2, &2, String, +List<String>>:
    +value : Member <- member(pool, index)
    return [member_owner(value), member_name(value), member_descriptor(value)]

def index_entry(word: R.RWord, kind: U32) -> Entry:
  match word:
    case R.RWord{reader, value}:
      Entry{reader, M.Index{kind, value}, False{}}

def read_index(reader: R.Reader, kind: U32) -> Result<&2, &2, String, Entry>:
  do Result<&2, &2, String, Entry>:
    word : R.RWord <- R.read_u2(reader)
    result : Entry = index_entry(word, kind)
    return result

def pair_entry(second: R.RWord, first: U32, kind: U32) -> Entry:
  match second:
    case R.RWord{reader, value}:
      Entry{reader, M.PairIndex{kind, first, value}, False{}}

def read_pair_first(first: R.RWord, kind: U32) -> Result<&2, &2, String, Entry>:
  match first:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, Entry>:
        second : R.RWord <- R.read_u2(reader)
        result : Entry = pair_entry(second, value, kind)
        return result

def read_pair(reader: R.Reader, kind: U32) -> Result<&2, &2, String, Entry>:
  do Result<&2, &2, String, Entry>:
    first : R.RWord <- R.read_u2(reader)
    result : Entry <- read_pair_first(first, kind)
    return result

def number_entry(word: R.RWord, kind: U32) -> Entry:
  match word:
    case R.RWord{reader, value}:
      Entry{reader, M.Number{kind, value}, False{}}

def read_number(reader: R.Reader, kind: U32) -> Result<&2, &2, String, Entry>:
  do Result<&2, &2, String, Entry>:
    word : R.RWord <- R.read_u4(reader)
    result : Entry = number_entry(word, kind)
    return result

def wide_second(second: R.RWord, first: U32, kind: U32) -> Entry:
  match second:
    case R.RWord{reader, value}:
      Entry{reader, M.PairIndex{kind, first, value}, True{}}

def read_wide_first(first: R.RWord, kind: U32) -> Result<&2, &2, String, Entry>:
  match first:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, Entry>:
        second : R.RWord <- R.read_u4(reader)
        result : Entry = wide_second(second, value, kind)
        return result

def read_wide(reader: R.Reader, kind: U32) -> Result<&2, &2, String, Entry>:
  do Result<&2, &2, String, Entry>:
    first : R.RWord <- R.read_u4(reader)
    result : Entry <- read_wide_first(first, kind)
    return result

def utf_bytes(bytes: R.RBytes) -> Result<&2, &2, String, Entry>:
  match bytes:
    case R.RBytes{reader, value}:
      do Result<&2, &2, String, Entry>:
        text : String <- Utf.decode(value)
        return Entry{reader, M.Utf{text}, False{}}

def utf_length(length: R.RWord) -> Result<&2, &2, String, Entry>:
  match length:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, Entry>:
        bytes : R.RBytes <- R.slice(reader, value)
        result : Entry <- utf_bytes(bytes)
        return result

def method_handle_entry(second: R.RWord, first: U32) -> Entry:
  match second:
    case R.RWord{reader, value}:
      Entry{reader, M.PairIndex{15, first, value}, False{}}

def method_handle_first(first: R.RWord) -> Result<&2, &2, String, Entry>:
  match first:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, Entry>:
        second : R.RWord <- R.read_u2(reader)
        result : Entry = method_handle_entry(second, value)
        return result

def read_method_handle(reader: R.Reader) -> Result<&2, &2, String, Entry>:
  do Result<&2, &2, String, Entry>:
    first : R.RWord <- R.read_u1(reader)
    result : Entry <- method_handle_first(first)
    return result

def read_entry(kind: U32, reader: R.Reader) -> Result<&2, &2, String, Entry>:
  match kind:
    case 1:
      do Result<&2, &2, String, Entry>:
        length : R.RWord <- R.read_u2(reader)
        result : Entry <- utf_length(length)
        return result
    case 3: read_number(reader, 3)
    case 4: read_number(reader, 4)
    case 5: read_wide(reader, 5)
    case 6: read_wide(reader, 6)
    case 7: read_index(reader, 7)
    case 8: read_index(reader, 8)
    case 9: read_pair(reader, 9)
    case 10: read_pair(reader, 10)
    case 11: read_pair(reader, 11)
    case 12: read_pair(reader, 12)
    case 15: read_method_handle(reader)
    case 16: read_index(reader, 16)
    case 18: read_pair(reader, 18)
    case _:
      Fail{"VmError.InvalidConstantPool: unknown Java 8 constant tag " ++ U32.show(kind)}

def parse_entry_cont(entry: Result<&2, &2, String, Entry>, count: Nat, acc: +List<M.Constant>, next: Nat -> R.Reader -> Bool -> +List<M.Constant> -> Result<&2, &2, String, Pool>) -> Result<&2, &2, String, Pool>:
  match entry:
    case Fail{error}:
      Fail{error}
    case Done{Entry{reader, value, wide}}:
      next(count, reader, wide, Con{value, acc})

def parse_word_cont(word: Result<&2, &2, String, R.RWord>, count: Nat, acc: +List<M.Constant>, next: Nat -> R.Reader -> Bool -> +List<M.Constant> -> Result<&2, &2, String, Pool>) -> Result<&2, &2, String, Pool>:
  match word:
    case Fail{error}:
      Fail{error}
    case Done{R.RWord{reader, value}}:
      parse_entry_cont(read_entry(value, reader), count, acc, next)

@unsafe def parse_go(count: Nat, reader: R.Reader, reserved: Bool, acc: +List<M.Constant>) -> Result<&2, &2, String, Pool>:
  match count reserved:
    case 0n True{}:
      Fail{"VmError.InvalidConstantPool: wide constant has no reserved slot"}
    case 0n False{}:
      Done{Pool{reader, M.reverse(M.Constant, acc)}}
    case 1n+p True{}:
      parse_go(p, reader, False{}, Con{M.Unused{}, acc})
    case 1n+p False{}:
      parse_word_cont(R.read_u1(reader), p, acc, parse_go)


def class_text(text: String) -> Result<&2, &2, String, Unit>:
  match text:
    case SCon{Chr{91}, t}:
      do Result<&2, &2, String, Unit>:
        value : M.JvmType <- D.parse_field(SCon{Chr{91}, t})
        return Unit{}
    case _:
      R.require(D.valid_class_name(text), "VmError.InvalidConstantPool: invalid class name")

def method_name(+name: String, constructors: Bool) -> Bool:
  Bool.or(Bool.and(constructors, String.eq(name, "<init>")), Bool.and(D.valid_member_name(name), Bool.and(Bool.not(String.contains(name, "<")), Bool.not(String.contains(name, ">")))))

def check_member(kind: U32, name: String, descriptor: String) -> Result<&2, &2, String, Unit>:
  match kind:
    case 9:
      do Result<&2, &2, String, Unit>:
        R.require(D.valid_member_name(name), "VmError.InvalidConstantPool: invalid field name")
        value : M.JvmType <- D.parse_field(descriptor)
        return Unit{}
    case _:
      do Result<&2, &2, String, Unit>:
        R.require(method_name(name, U32.is_eq(kind, 10)), "VmError.InvalidConstantPool: invalid method name")
        value : M.Descriptor <- D.parse_method(descriptor)
        return Unit{}

def check_name_type(name: String, descriptor: String) -> Result<&2, &2, String, Unit>:
  match descriptor:
    case SCon{Chr{40}, t}:
      check_member(10, name, SCon{Chr{40}, t})
    case _:
      check_member(9, name, descriptor)

def handle_tag(+kind: U32, +reference_tag: U32) -> Bool:
  Bool.pick(Bool, U32.is_le(kind, 4), U32.is_eq(reference_tag, 9),
    Bool.pick(Bool, U32.is_eq(kind, 9), U32.is_eq(reference_tag, 11),
      Bool.pick(Bool, Bool.or(U32.is_eq(kind, 6), U32.is_eq(kind, 7)), Bool.or(U32.is_eq(reference_tag, 10), U32.is_eq(reference_tag, 11)), U32.is_eq(reference_tag, 10))))

def check_handle_member(ref: Member, kind: U32) -> Result<&2, &2, String, Unit>:
  match ref:
    case Member{owner, +name, descriptor, ref_tag}:
      R.require(Bool.pick(Bool, U32.is_eq(kind, 8), String.eq(name, "<init>"), Bool.and(Bool.not(String.eq(name, "<init>")), Bool.not(String.eq(name, "<clinit>")))), "VmError.InvalidConstantPool: method handle target name")

def check_handle_value(value: M.Constant, +kind: U32, +pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    R.require(handle_tag(kind, tag(value)), "VmError.InvalidConstantPool: method handle target tag")
    ref : Member <- member(pool, index)
    result : Unit <- check_handle_member(ref, kind)
    return result

def check_handle(+pool: +List<M.Constant>, +kind: U32, +index: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    R.require(Bool.and(U32.is_ge(kind, 1), U32.is_le(kind, 9)), "VmError.InvalidConstantPool: invalid method handle kind")
    value : M.Constant <- get(pool, index)
    result : Unit <- check_handle_value(value, kind, pool, index)
    return result

def check_bootstrap_pair(pair: NameType) -> Result<&2, &2, String, Unit>:
  match pair:
    case NameType{name, descriptor}:
      check_member(11, name, descriptor)

def check_member_value(ref: Member, kind: U32) -> Result<&2, &2, String, Unit>:
  match ref:
    case Member{owner, name, descriptor, ref_tag}:
      check_member(kind, name, descriptor)


def pair_constant(kind: U32, first: U32, second: U32) -> M.Constant:
  M.PairIndex{kind, first, second}

def check_member_constant(+pool: +List<M.Constant>, +kind: U32, first: U32, second: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    ref : Member <- expect_member(pool, pair_constant(kind, first, second))
    result : Unit <- check_member_value(ref, kind)
    return result
def check_pair_by_tag(+pool: +List<M.Constant>, +tag: U32, +first: U32, +second: U32) -> Result<&2, &2, String, Unit>:
  match tag:
    case 5: Done{Unit{}}
    case 6: Done{Unit{}}
    case 12:
      do Result<&2, &2, String, Unit>:
        name : String <- utf(pool, first)
        descriptor : String <- utf(pool, second)
        check_name_type(name, descriptor)
    case 15:
      check_handle(pool, first, second)
    case 18:
      do Result<&2, &2, String, Unit>:
        pair : NameType <- name_type(pool, second)
        result : Unit <- check_bootstrap_pair(pair)
        return result
    case 9:
      check_member_constant(pool, tag, first, second)
    case 10:
      check_member_constant(pool, tag, first, second)
    case 11:
      check_member_constant(pool, tag, first, second)
    case _:
      Fail{"VmError.InvalidConstantPool: invalid constant representation"}

def check_entry(+pool: +List<M.Constant>, entry: M.Constant) -> Result<&2, &2, String, Unit>:
  match entry:
    case M.Utf{text}: Done{Unit{}}
    case M.Number{kind, bits}: Done{Unit{}}
    case M.Index{7, index}:
      do Result<&2, &2, String, Unit>:
        name : String <- utf(pool, index)
        class_text(name)
    case M.Index{8, index}:
      do Result<&2, &2, String, Unit>:
        text : String <- utf(pool, index)
        return Unit{}
    case M.Index{16, index}:
      do Result<&2, &2, String, Unit>:
        text : String <- utf(pool, index)
        descriptor : M.Descriptor <- D.parse_method(text)
        return Unit{}
    case M.PairIndex{kind2, first, second}:
      check_pair_by_tag(pool, kind2, first, second)
    case _:
      Done{Unit{}}

def validate(values: +List<M.Constant>, +pool: +List<M.Constant>) -> Result<&2, &2, String, Unit>:
  match values:
    case Nil{}:
      Done{Unit{}}
    case Con{h, t}:
      do Result<&2, &2, String, Unit>:
        check_entry(pool, h)
        validate(t, pool)

def parse_finish(parsed: Pool) -> Result<&2, &2, String, Pool>:
  match parsed:
    case Pool{reader, +values}:
      do Result<&2, &2, String, Pool>:
        validate(values, values)
        return Pool{reader, values}

def parse_after_word(word: R.RWord) -> Result<&2, &2, String, Pool>:
  match word:
    case R.RWord{reader, +count}:
      do Result<&2, &2, String, Pool>:
        R.require(U32.is_gt(count, 0), "VmError.InvalidConstantPool: zero constant pool count")
        parsed : Pool <- parse_go(U32.to_nat((count - 1 : U32)), reader, False{}, Con{M.Unused{}, Nil{}})
        result : Pool <- parse_finish(parsed)
        return result

def parse(reader: R.Reader) -> Result<&2, &2, String, Pool>:
  do Result<&2, &2, String, Pool>:
    word : R.RWord <- R.read_u2(reader)
    result : Pool <- parse_after_word(word)
    return result
