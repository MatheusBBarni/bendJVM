import Base
import ../model.bend as M
import ./reader.bend as R
import ./constant_pool.bend as CP
import ./descriptor.bend as D

type BootstrapArgument is Data:
  BootstrapArgument{argumentIndex: U32, constantIndex: U32, tag: U32, value: M.Constant}

type BootstrapMethod is Data:
  BootstrapMethod{index: U32, methodRef: U32, handleKind: U32, handleReference: U32, arguments: +List<BootstrapArgument>}

type BootstrapMethods is Data:
  BootstrapMethods{methods: +List<BootstrapMethod>}

type ParsedArguments is Data:
  ParsedArguments{reader: R.Reader, values: +List<BootstrapArgument>}

type ParsedMethods is Data:
  ParsedMethods{reader: R.Reader, values: +List<BootstrapMethod>}
type ParsedMethodRead is Data:
  ParsedMethodRead{reader: R.Reader, method: BootstrapMethod}

type Handle is Data:
  Handle{kind: U32, reference: U32}


def word_value(word: R.RWord) -> U32:
  match word:
    case R.RWord{reader, value}: value

def word_reader(word: R.RWord) -> R.Reader:
  match word:
    case R.RWord{reader, value}: reader


def malformed(message: String) -> String:
  "VmError.InvalidBootstrapMethods: " ++ message

def require(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  R.require(ok, malformed(message))

def bootstrap_handle_value(+pool: +List<M.Constant>, value: M.Constant) -> Result<&2, &2, String, Handle>:
  match value:
    case M.PairIndex{15, +kind, +reference}:
      do Result<&2, &2, String, Handle>:
        CP.check_handle(pool, kind, reference)
        valid_kind : Unit <- require(U32.is_eq(kind, 6) || U32.is_eq(kind, 8), "bootstrap method handle must use REF_invokeStatic or REF_newInvokeSpecial")
        return Handle{kind, reference}
    case _:
      do Result<&2, &2, String, Handle>:
        require(False{}, "method_ref does not reference CONSTANT_MethodHandle")
        return Handle{0, 0}

def bootstrap_handle(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, Handle>:
  do Result<&2, &2, String, Handle>:
    value : M.Constant <- CP.get(pool, index)
    handle : Handle <- bootstrap_handle_value(pool, value)
    return handle

def validate_argument_value(+pool: +List<M.Constant>, index: U32, value: M.Constant) -> Result<&2, &2, String, M.Constant>:
  match value:
    # String and Class entries hold the index of their Utf8 text.
    case M.Index{8, +string_index}:
      do Result<&2, &2, String, M.Constant>:
        string : String <- CP.utf(pool, string_index)
        return value
    case M.Index{7, +name_index}:
      do Result<&2, &2, String, M.Constant>:
        class_name : String <- CP.utf(pool, name_index)
        return value
    case M.Number{+tag, bits}:
      do Result<&2, &2, String, M.Constant>:
        require(U32.is_eq(tag, 3) || U32.is_eq(tag, 4), "illegal bootstrap argument constant kind")
        return value
    # Long and Double constants keep their two words as a PairIndex record.
    case M.PairIndex{5, high, low}: Done{value}
    case M.PairIndex{6, high, low}: Done{value}
    case M.PairIndex{15, +kind, +reference}:
      do Result<&2, &2, String, M.Constant>:
        CP.check_handle(pool, kind, reference)
        return value
    case M.Index{16, descriptor_index}:
      do Result<&2, &2, String, M.Constant>:
        descriptor : String <- CP.utf(pool, descriptor_index)
        parsed : M.Descriptor <- D.parse_method(descriptor)
        return value
    case _:
      do Result<&2, &2, String, M.Constant>:
        require(False{}, "illegal bootstrap argument constant kind")
        return value

def validate_argument(+pool: +List<M.Constant>, +index: U32) -> Result<&2, &2, String, M.Constant>:
  do Result<&2, &2, String, M.Constant>:
    value : M.Constant <- CP.get(pool, index)
    validated : M.Constant <- validate_argument_value(pool, index, value)
    return validated

def arguments_go(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, +index: U32, acc: +List<BootstrapArgument>) -> Result<&2, &2, String, ParsedArguments>:
  match count:
    case 0n:
      Done{ParsedArguments{reader, M.reverse(BootstrapArgument, acc)}}
    case 1n+rest:
      do Result<&2, &2, String, ParsedArguments>:
        +word : R.RWord <- R.read_u2(reader)
        +constant_index : U32 = word_value(word)
        +value : M.Constant <- validate_argument(pool, constant_index)
        arguments : ParsedArguments <- arguments_go(rest, word_reader(word), pool, (index + 1 : U32), Con{BootstrapArgument{index, constant_index, CP.tag(value), value}, acc})
        return arguments
def method_go_construct_handle(index: U32, method_ref: U32, reader: R.Reader, +values: +List<BootstrapArgument>, handle: Handle) -> Result<&2, &2, String, ParsedMethodRead>:
  match handle:
    case Handle{kind, reference}:
      Done{ParsedMethodRead{reader, BootstrapMethod{index, method_ref, kind, reference, values}}}

def method_go_construct(index: U32, method_ref: U32, handle: Handle, parsed: ParsedArguments) -> Result<&2, &2, String, ParsedMethodRead>:
  match parsed:
    case ParsedArguments{reader, +values}:
      method_go_construct_handle(index, method_ref, reader, values, handle)
def method_go_read(reader: R.Reader, +pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, ParsedMethodRead>:
  do Result<&2, &2, String, ParsedMethodRead>:
    +method_word : R.RWord <- R.read_u2(reader)
    +method_ref : U32 = word_value(method_word)
    handle : Handle <- bootstrap_handle(pool, method_ref)
    +argument_count_word : R.RWord <- R.read_u2(word_reader(method_word))
    +argument_count : U32 = word_value(argument_count_word)
    R.require(U32.is_le((argument_count * 2 : U32), R.remaining(word_reader(argument_count_word))), malformed("truncated bootstrap argument table"))
    parsed_arguments : ParsedArguments <- arguments_go(U32.to_nat(argument_count), word_reader(argument_count_word), pool, 0, Nil{})
    parsed : ParsedMethodRead <- method_go_construct(index, method_ref, handle, parsed_arguments)
    return parsed

def method_read_reader(value: ParsedMethodRead) -> R.Reader:
  match value:
    case ParsedMethodRead{reader, method}: reader

def method_read_method(value: ParsedMethodRead) -> BootstrapMethod:
  match value:
    case ParsedMethodRead{reader, method}: method

def method_go(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, +index: U32, acc: +List<BootstrapMethod>) -> Result<&2, &2, String, ParsedMethods>:
  match count:
    case 0n:
      Done{ParsedMethods{reader, M.reverse(BootstrapMethod, acc)}}
    case 1n+rest:
      Result.bind(&2, &2, String, ParsedMethodRead, ParsedMethods,
        method_go_read(reader, pool, index),
        +step => method_go(rest, method_read_reader(step), pool, (index + 1 : U32), Con{method_read_method(step), acc}))


def methods_complete(parsed: ParsedMethods) -> Result<&2, &2, String, BootstrapMethods>:
  match parsed:
    case ParsedMethods{reader, +methods}:
      do Result<&2, &2, String, BootstrapMethods>:
        R.require(U32.is_eq(R.remaining(reader), 0), malformed("trailing bytes after bootstrap method table"))
        return BootstrapMethods{methods}

def parse(+bytes: +List<U32>, +pool: +List<M.Constant>) -> Result<&2, &2, String, BootstrapMethods>:
  do Result<&2, &2, String, BootstrapMethods>:
    byte_count : U32 = M.length(U32, bytes)
    R.require(U32.is_le(byte_count, 262144), malformed("attribute exceeds byte limit"))
    reader : R.Reader = R.new(bytes)
    +count_word : R.RWord <- R.read_u2(reader)
    +count : U32 = word_value(count_word)
    R.require(U32.is_le((count * 4 : U32), R.remaining(word_reader(count_word))), malformed("truncated bootstrap method table"))
    parsed : ParsedMethods <- method_go(U32.to_nat(count), word_reader(count_word), pool, 0, Nil{})
    result : BootstrapMethods <- methods_complete(parsed)
    return result

def class_attribute_value(is_bootstrap: Bool, bytes: +List<U32>, +pool: +List<M.Constant>, found: Bool, value: Maybe<&2, BootstrapMethods>) -> Result<&2, &2, String, Maybe<&2, BootstrapMethods>>:
  match is_bootstrap:
    case False{}: Done{value}
    case True{}:
      do Result<&2, &2, String, Maybe<&2, BootstrapMethods>>:
        require(Bool.not(found), "duplicate BootstrapMethods attribute")
        parsed : BootstrapMethods <- parse(bytes, pool)
        return Some{parsed}

def class_attributes_go(attributes: +List<M.Attribute>, +pool: +List<M.Constant>, +found: Bool, value: Maybe<&2, BootstrapMethods>) -> Result<&2, &2, String, Maybe<&2, BootstrapMethods>>:
  match attributes:
    case Nil{}:
      Done{value}
    case Con{M.ValidatedAnnotations{metadata}, tail}:
      class_attributes_go(tail, pool, found, value)
    case Con{M.Attribute{name, bytes}, tail}:
      do Result<&2, &2, String, Maybe<&2, BootstrapMethods>>:
        +is_bootstrap : Bool = String.eq(name, "BootstrapMethods")
        next_value : Maybe<&2, BootstrapMethods> <- class_attribute_value(is_bootstrap, bytes, pool, found, value)
        next_found : Bool = Bool.or(found, is_bootstrap)
        rest : Maybe<&2, BootstrapMethods> <- class_attributes_go(tail, pool, next_found, next_value)
        return rest

def parse_class_attributes(attributes: +List<M.Attribute>, +pool: +List<M.Constant>) -> Result<&2, &2, String, Maybe<&2, BootstrapMethods>>:
  class_attributes_go(attributes, pool, False{}, None{})
