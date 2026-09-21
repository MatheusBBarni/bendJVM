import Base
import ../model.bend as M
import ./reader.bend as R
import ./constant_pool.bend as CP
import ./attribute.bend as A
import ../bytecode/decode.bend as BC

# Parser state wrappers keep reader ownership explicit across recursive sections.
type Interfaces is Data:
  Interfaces{reader: R.Reader, values: +List<String>, pool: +List<M.Constant>}

type Fields is Data:
  Fields{reader: R.Reader, values: +List<M.Field>, pool: +List<M.Constant>}

type CodeInfo is Data:
  CodeInfo{maxStack: U32, maxLocals: U32, code: +List<U32>, handlers: +List<M.Handler>}

type Methods is Data:
  Methods{reader: R.Reader, values: +List<M.Method>, pool: +List<M.Constant>}

type ClassTail is Data:
  ClassTail{reader: R.Reader, interfaces: +List<String>, fields: +List<M.Field>, methods: +List<M.Method>, attributes: +List<M.Attribute>}

def require(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{message}

def be_word(a: U32, b: U32) -> U32:
  (a * 256 + b : U32)

def word_value(word: R.RWord) -> U32:
  match word:
    case R.RWord{reader, value}:
      value

def word_reader(word: R.RWord) -> R.Reader:
  match word:
    case R.RWord{reader, value}:
      reader

def bytes_index(bytes: +List<U32>) -> U32:
  match bytes:
    case Con{a, Con{b, tail}}:
      be_word(a, b)
    case _:
      0

def constant_index(attributes: +List<M.Attribute>) -> U32:
  match attributes:
    case Nil{}:
      0
    case Con{M.Attribute{name, bytes}, rest}:
      Bool.pick(U32, String.eq(name, "ConstantValue"), bytes_index(bytes), constant_index(rest))

def code_info_default() -> CodeInfo:
  CodeInfo{0, 0, Nil{}, Nil{}}

def code_attribute(attributes: +List<M.Attribute>) -> Maybe<&2, +List<U32>>:
  match attributes:
    case Nil{}:
      None{}
    case Con{M.Attribute{name, bytes}, rest}:
      Bool.pick(Maybe<&2, +List<U32>>, String.eq(name, "Code"), Some{bytes}, code_attribute(rest))
@unsafe def skip_attributes_go(count: Nat, reader: R.Reader) -> Result<&2, &2, String, R.Reader>:
  match count:
    case 0n:
      Done{reader}
    case 1n+p:
      do Result<&2, &2, String, R.Reader>:
        +name : R.RWord <- R.read_u2(reader)
        +length : R.RWord <- R.read_u4(word_reader(name))
        skipped : R.Reader <- R.skip(word_reader(length), word_value(length))
        result : R.Reader <- skip_attributes_go(p, skipped)
        return result

def handler_finish(reader: R.Reader, +handlers: +List<M.Handler>) -> Result<&2, &2, String, +List<M.Handler>>:
  do Result<&2, &2, String, +List<M.Handler>>:
    +count : R.RWord <- R.read_u2(reader)
    checked : R.Reader <- skip_attributes_go(U32.to_nat(word_value(count)), word_reader(count))
    return M.reverse(M.Handler, handlers)
@unsafe def handlers_go(count: Nat, reader: R.Reader, acc: +List<M.Handler>) -> Result<&2, &2, String, +List<M.Handler>>:
  match count:
    case 0n:
      handler_finish(reader, acc)
    case 1n+p:
      do Result<&2, &2, String, +List<M.Handler>>:
        +start : R.RWord <- R.read_u2(reader)
        +end : R.RWord <- R.read_u2(word_reader(start))
        +target : R.RWord <- R.read_u2(word_reader(end))
        +catch_type : R.RWord <- R.read_u2(word_reader(target))
        result : +List<M.Handler> <- handlers_go(p, word_reader(catch_type), Con{M.Handler{word_value(start), word_value(end), word_value(target), word_value(catch_type)}, acc})
        return result

def code_after_exceptions(max_stack: U32, max_locals: U32, code: +List<U32>, exception_count: R.RWord) -> Result<&2, &2, String, CodeInfo>:
  match exception_count:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, CodeInfo>:
        handlers : +List<M.Handler> <- handlers_go(U32.to_nat(value), reader, Nil{})
        return CodeInfo{max_stack, max_locals, code, handlers}

def code_after_code(max_stack: U32, max_locals: U32, code: R.RBytes) -> Result<&2, &2, String, CodeInfo>:
  match code:
    case R.RBytes{reader, value}:
      do Result<&2, &2, String, CodeInfo>:
        exception_count : R.RWord <- R.read_u2(reader)
        result : CodeInfo <- code_after_exceptions(max_stack, max_locals, value, exception_count)
        return result

def code_after_locals(max_stack: U32, locals: R.RWord) -> Result<&2, &2, String, CodeInfo>:
  match locals:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, CodeInfo>:
        +code_length : R.RWord <- R.read_u4(reader)
        length : U32 = word_value(code_length)
        bytes : R.RBytes <- R.slice(word_reader(code_length), length)
        result : CodeInfo <- code_after_code(max_stack, value, bytes)
        return result

def code_after_stack(stack: R.RWord) -> Result<&2, &2, String, CodeInfo>:
  match stack:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, CodeInfo>:
        locals : R.RWord <- R.read_u2(reader)
        result : CodeInfo <- code_after_locals(value, locals)
        return result

def parse_code_bytes(+bytes: +List<U32>) -> Result<&2, &2, String, CodeInfo>:
  reader = R.new(bytes)
  do Result<&2, &2, String, CodeInfo>:
    stack : R.RWord <- R.read_u2(reader)
    result : CodeInfo <- code_after_stack(stack)
    return result

def attrs_values(attributes: A.Attributes) -> +List<M.Attribute>:
  match attributes:
    case A.Attributes{reader, values}:
      values

def attrs_reader(attributes: A.Attributes) -> R.Reader:
  match attributes:
    case A.Attributes{reader, values}:
      reader

def method_code_found(found: Maybe<&2, +List<U32>>) -> Result<&2, &2, String, CodeInfo>:
  match found:
    case None{}:
      Done{code_info_default()}
    case Some{bytes}:
      parse_code_bytes(bytes)

def method_code(attributes: +List<M.Attribute>) -> Result<&2, &2, String, CodeInfo>:
  method_code_found(code_attribute(attributes))

def method_build(info: CodeInfo, flags: U32, name: String, descriptor: String, attributes: +List<M.Attribute>) -> Result<&2, &2, String, M.Method>:
  match info:
    case CodeInfo{maxStack, maxLocals, code, handlers}:
      BC.method(M.Method{flags, name, descriptor, maxStack, maxLocals, code, Nil{}, handlers, attributes})

@unsafe def methods_go(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, acc: +List<M.Method>) -> Result<&2, &2, String, Methods>:
  match count:
    case 0n:
      Done{Methods{reader, M.reverse(M.Method, acc), pool}}
    case 1n+p:
      do Result<&2, &2, String, Methods>:
        +flags_word : R.RWord <- R.read_u2(reader)
        flags : U32 = word_value(flags_word)
        +name_word : R.RWord <- R.read_u2(word_reader(flags_word))
        name : String <- CP.utf(pool, word_value(name_word))
        +descriptor_word : R.RWord <- R.read_u2(word_reader(name_word))
        descriptor : String <- CP.utf(pool, word_value(descriptor_word))
        +attr_count : R.RWord <- R.read_u2(word_reader(descriptor_word))
        +attributes : A.Attributes <- A.read_go(U32.to_nat(word_value(attr_count)), word_reader(attr_count), pool, Nil{})
        info : CodeInfo <- method_code(attrs_values(attributes))
        method : M.Method <- method_build(info, flags, name, descriptor, attrs_values(attributes))
        result : Methods <- methods_go(p, attrs_reader(attributes), pool, Con{method, acc})
        return result

def field_build(flags: U32, name: String, descriptor: String, +attributes: A.Attributes) -> M.Field:
  M.Field{flags, name, descriptor, constant_index(attrs_values(attributes)), attrs_values(attributes)}

@unsafe def fields_go(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, acc: +List<M.Field>) -> Result<&2, &2, String, Fields>:
  match count:
    case 0n:
      Done{Fields{reader, M.reverse(M.Field, acc), pool}}
    case 1n+p:
      do Result<&2, &2, String, Fields>:
        +flags_word : R.RWord <- R.read_u2(reader)
        flags : U32 = word_value(flags_word)
        +name_word : R.RWord <- R.read_u2(word_reader(flags_word))
        name : String <- CP.utf(pool, word_value(name_word))
        +descriptor_word : R.RWord <- R.read_u2(word_reader(name_word))
        descriptor : String <- CP.utf(pool, word_value(descriptor_word))
        +attr_count : R.RWord <- R.read_u2(word_reader(descriptor_word))
        +attributes : A.Attributes <- A.read_go(U32.to_nat(word_value(attr_count)), word_reader(attr_count), pool, Nil{})
        result : Fields <- fields_go(p, attrs_reader(attributes), pool, Con{field_build(flags, name, descriptor, attributes), acc})
        return result

@unsafe def interfaces_go(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, acc: +List<String>) -> Result<&2, &2, String, Interfaces>:
  match count:
    case 0n:
      Done{Interfaces{reader, M.reverse(String, acc), pool}}
    case 1n+p:
      do Result<&2, &2, String, Interfaces>:
        +index_word : R.RWord <- R.read_u2(reader)
        name : String <- CP.class_name(pool, word_value(index_word))
        result : Interfaces <- interfaces_go(p, word_reader(index_word), pool, Con{name, acc})
        return result

def parse_class_attributes(methods: Methods, fields: +List<M.Field>, interfaces: +List<String>, minor: U32, major: U32, flags: U32, name: String, parent: String) -> Result<&2, &2, String, M.ClassFile>:
  match methods:
    case Methods{reader, values, +pool}:
      do Result<&2, &2, String, M.ClassFile>:
        attributes : A.Attributes <- A.parse(reader, pool)
        return M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, values, attrs_values(attributes)}

def parse_methods_count(fields: Fields, interfaces: +List<String>, minor: U32, major: U32, flags: U32, name: String, parent: String) -> Result<&2, &2, String, M.ClassFile>:
  match fields:
    case Fields{reader, values, +pool}:
      do Result<&2, &2, String, M.ClassFile>:
        +methods_count : R.RWord <- R.read_u2(reader)
        methods : Methods <- methods_go(U32.to_nat(word_value(methods_count)), word_reader(methods_count), pool, Nil{})
        result : M.ClassFile <- parse_class_attributes(methods, values, interfaces, minor, major, flags, name, parent)
        return result

def parse_members(count_word: R.RWord, +pool: +List<M.Constant>, interfaces: +List<String>, minor: U32, major: U32, flags: U32, name: String, parent: String) -> Result<&2, &2, String, M.ClassFile>:
  match count_word:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, M.ClassFile>:
        fields : Fields <- fields_go(U32.to_nat(value), reader, pool, Nil{})
        result : M.ClassFile <- parse_methods_count(fields, interfaces, minor, major, flags, name, parent)
        return result



def parse_header_members(interfaces: Interfaces, access_word: R.RWord, name: String, minor: U32, major: U32, parent: String) -> Result<&2, &2, String, M.ClassFile>:
  match interfaces:
    case Interfaces{reader, values, +pool}:
      match access_word:
        case R.RWord{access_reader, value}:
          do Result<&2, &2, String, M.ClassFile>:
            fields_count : R.RWord <- R.read_u2(reader)
            result : M.ClassFile <- parse_members(fields_count, pool, values, minor, major, value, name, parent)
            return result
def parse_interfaces_count(count_word: R.RWord, access_word: R.RWord, name: String, minor: U32, major: U32, parent: String, pool: +List<M.Constant>) -> Result<&2, &2, String, M.ClassFile>:
  match count_word:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, M.ClassFile>:
        interfaces : Interfaces <- interfaces_go(U32.to_nat(value), reader, pool, Nil{})
        result : M.ClassFile <- parse_header_members(interfaces, access_word, name, minor, major, parent)
        return result
def parse_super(super_word: R.RWord, access_word: R.RWord, name: String, minor: U32, major: U32, +pool: +List<M.Constant>) -> Result<&2, &2, String, M.ClassFile>:
  match super_word:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, M.ClassFile>:
        parent : String <- CP.class_name(pool, value)
        interfaces_count : R.RWord <- R.read_u2(reader)
        result : M.ClassFile <- parse_interfaces_count(interfaces_count, access_word, name, minor, major, parent, pool)
        return result


def parse_name(+name_word: R.RWord, minor: U32, major: U32, +pool: +List<M.Constant>, access_word: R.RWord) -> Result<&2, &2, String, M.ClassFile>:
  do Result<&2, &2, String, M.ClassFile>:
    name : String <- CP.class_name(pool, word_value(name_word))
    parent_word : R.RWord <- R.read_u2(word_reader(name_word))
    result : M.ClassFile <- parse_super(parent_word, access_word, name, minor, major, pool)
    return result

def parse_access(access_word: R.RWord, minor: U32, major: U32, pool: +List<M.Constant>, reader: R.Reader) -> Result<&2, &2, String, M.ClassFile>:
  do Result<&2, &2, String, M.ClassFile>:
    name_word : R.RWord <- R.read_u2(reader)
    result : M.ClassFile <- parse_name(name_word, minor, major, pool, access_word)
    return result

def parse_version_body(major: U32, minor: U32, +pool: +List<M.Constant>, reader: R.Reader) -> Result<&2, &2, String, M.ClassFile>:
  match major:
    case 52:
      do Result<&2, &2, String, M.ClassFile>:
        +access_word : R.RWord <- R.read_u2(reader)
        result : M.ClassFile <- parse_access(access_word, minor, major, pool, word_reader(access_word))
        return result
    case _:
      Fail{"VmError.UnsupportedClassVersion: major version is not Java 8"}
def parse_version(version_word: R.RWord, minor: U32, +pool: +List<M.Constant>, reader: R.Reader) -> Result<&2, &2, String, M.ClassFile>:
  match version_word:
    case R.RWord{reader, value}:
      parse_version_body(value, minor, pool, reader)
def parse_pool(pool: CP.Pool, minor: U32, major: U32) -> Result<&2, &2, String, M.ClassFile>:
  match pool:
    case CP.Pool{reader, values}:
      do Result<&2, &2, String, M.ClassFile>:
        +access_word : R.RWord <- R.read_u2(reader)
        result : M.ClassFile <- parse_access(access_word, minor, major, values, word_reader(access_word))
        return result

def parse_magic(magic: R.RWord) -> Result<&2, &2, String, M.ClassFile>:
  match magic:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, M.ClassFile>:
        require(U32.is_eq(value, 3405691582), "VmError.InvalidClassFile: invalid magic")
        +minor_word : R.RWord <- R.read_u2(reader)
        minor : U32 = word_value(minor_word)
        +major_word : R.RWord <- R.read_u2(word_reader(minor_word))
        +major : U32 = word_value(major_word)
        require(U32.is_eq(major, 52), "VmError.UnsupportedClassVersion: major version is not Java 8")
        pool : CP.Pool <- CP.parse(word_reader(major_word))
        result : M.ClassFile <- parse_pool(pool, minor, major)
        return result

def parse(+bytes: +List<U32>) -> Result<&2, &2, String, M.ClassFile>:
  do Result<&2, &2, String, M.ClassFile>:
    magic : R.RWord <- R.read_u4(R.new(bytes))
    parse_magic(magic)
