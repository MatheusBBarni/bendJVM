import Base
import ../model.bend as M
import ./reader.bend as R
import ./constant_pool.bend as CP
import ./descriptor.bend as D

# Annotation attributes are deliberately kept symbolic.  In particular, a
# long/double constant remains a PairIndex in the pool and is never decoded.
# The limits below make every recursive table parser bounded independently of
# the size of the enclosing class file.
def max_annotations() -> U32:
  4096

def max_elements() -> U32:
  4096

def max_parameters() -> U32:
  255

def max_table() -> U32:
  4096

def max_attributes() -> Nat:
  4096n

def max_depth() -> U32:
  64

def max_path() -> U32:
  255

def word_value(word: R.RWord) -> U32:
  match word:
    case R.RWord{reader, value}:
      value

def word_reader(word: R.RWord) -> R.Reader:
  match word:
    case R.RWord{reader, value}:
      reader

def invalid_annotation(message: String) -> Result<&2, &2, String, Unit>:
  Fail{"VmError.InvalidAnnotation: " ++ message}

def require_annotation(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      invalid_annotation(message)

def invalid_annotation_value(message: String) -> Result<&2, &2, String, M.AnnotationValue>:
  Fail{"VmError.InvalidAnnotation: " ++ message}

def cp_annotation_result(result: Result<&2, &2, String, M.Constant>) -> Result<&2, &2, String, M.Constant>:
  match result:
    case Done{value}:
      Done{value}
    case Fail{error}:
      Fail{"VmError.InvalidAnnotation: invalid constant-pool reference"}

def cp_annotation(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, M.Constant>:
  cp_annotation_result(CP.get(pool, index))

def utf_annotation_result(result: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match result:
    case Done{text}:
      Done{text}
    case Fail{error}:
      Fail{"VmError.InvalidAnnotation: expected Utf8 constant"}

def utf_annotation(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, String>:
  utf_annotation_result(CP.utf(pool, index))

def descriptor_result(result: Result<&2, &2, String, M.JvmType>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{error}:
      Fail{"VmError.InvalidAnnotation: invalid descriptor"}
    case Done{M.ObjectType{name}}:
      Done{Unit{}}
    case Done{_}:
      Fail{"VmError.InvalidAnnotation: annotation type must be an object descriptor"}

def field_descriptor_result(result: Result<&2, &2, String, M.JvmType>) -> Result<&2, &2, String, Unit>:
  match result:
    case Fail{error}:
      Fail{"VmError.InvalidAnnotation: invalid class descriptor"}
    case Done{M.Primitive{86}}:
      Fail{"VmError.InvalidAnnotation: void is not a class descriptor"}
    case Done{_}:
      Done{Unit{}}

def annotation_descriptor(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    text : String <- utf_annotation(pool, index)
    descriptor_result(D.parse_field(text))

def object_descriptor(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    text : String <- utf_annotation(pool, index)
    descriptor_result(D.parse_field(text))
def class_descriptor_text(text: String) -> Result<&2, &2, String, Unit>:
  match text:
    case SCon{Chr{91}, t}:
      field_descriptor_result(D.parse_field(SCon{Chr{91}, t}))
    case _:
      require_annotation(D.valid_class_name(text), "invalid class constant name")

def class_constant_index(value: M.Constant) -> Result<&2, &2, String, U32>:
  match value:
    case M.Index{7, index}:
      Done{index}
    case _:
      Fail{"VmError.InvalidAnnotation: expected Class constant"}
def class_constant(+pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    value : M.Constant <- cp_annotation(pool, index)
    name_index : U32 <- class_constant_index(value)
    text : String <- utf_annotation(pool, name_index)
    class_descriptor_text(text)

 
def name_index(+pool: +List<M.Constant>, +index: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    text : String <- utf_annotation(pool, index)
    require_annotation(D.valid_member_name(text), "invalid annotation element name")
    return index

def enum_name_index(+pool: +List<M.Constant>, +index: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    text : String <- utf_annotation(pool, index)
    require_annotation(D.valid_member_name(text), "invalid enum constant name")
    return index

def expect_number(value: M.Constant, expected: U32) -> Result<&2, &2, String, Unit>:
  match value:
    case M.Number{kind, bits}:
      require_annotation(U32.is_eq(kind, expected), "annotation constant has wrong kind")
    case _:
      invalid_annotation("expected Integer/Float constant")

def expect_wide(value: M.Constant, expected: U32) -> Result<&2, &2, String, Unit>:
  match value:
    case M.PairIndex{kind, first, second}:
      require_annotation(U32.is_eq(kind, expected), "annotation wide constant has wrong kind")
    case _:
      invalid_annotation("expected long/double constant")

def expect_string(value: M.Constant) -> Result<&2, &2, String, Unit>:
  match value:
    case M.Utf{text}:
      Done{Unit{}}
    case _:
      invalid_annotation("expected Utf8 string constant")

def const_check(tag: U32, value: M.Constant) -> Result<&2, &2, String, Unit>:
  match tag:
    case 66: expect_number(value, 3)
    case 67: expect_number(value, 3)
    case 83: expect_number(value, 3)
    case 90: expect_number(value, 3)
    case 73: expect_number(value, 3)
    case 70: expect_number(value, 4)
    case 74: expect_wide(value, 5)
    case 68: expect_wide(value, 6)
    case 115: expect_string(value)
    case _: invalid_annotation("unknown annotation constant tag")

def const_value(+pool: +List<M.Constant>, +tag: U32, +index: U32) -> Result<&2, &2, String, M.AnnotationValue>:
  do Result<&2, &2, String, M.AnnotationValue>:
    value : M.Constant <- cp_annotation(pool, index)
    const_check(tag, value)
    return M.AnnotationConst{tag, index}
type ValueRead is Data:
  ValueRead{reader: R.Reader, value: M.AnnotationValue}

def value_from_word(tag: U32, word: R.RWord, +pool: +List<M.Constant>) -> Result<&2, &2, String, ValueRead>:
  match word:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, ValueRead>:
        result : M.AnnotationValue <- const_value(pool, tag, value)
        return ValueRead{reader, result}

type AnnotationRead is Data:
  AnnotationRead{reader: R.Reader, value: M.Annotation}
type ValueReadList is Data:
  ValueReadList{reader: R.Reader, values: +List<M.AnnotationValue>}

type ElementsRead is Data:
  ElementsRead{reader: R.Reader, values: +List<M.AnnotationElement>}

type AnnotationsRead is Data:
  AnnotationsRead{reader: R.Reader, values: +List<M.Annotation>}

type ParameterAnnotationsRead is Data:
  ParameterAnnotationsRead{reader: R.Reader, values: +List<+List<M.Annotation>>}

type TypeAnnotationsRead is Data:
  TypeAnnotationsRead{reader: R.Reader, values: +List<M.TypeAnnotation>}

type WordsRead is Data:
  WordsRead{reader: R.Reader, values: +List<U32>}

type PathRead is Data:
  PathRead{reader: R.Reader, values: +List<U32>}

type AttrKind is Data:
  Unknown{}
  VisibleAnnotations{}
  InvisibleAnnotations{}
  VisibleParameters{}
  InvisibleParameters{}
  VisibleTypes{}
  InvisibleTypes{}
  DefaultValue{}
  Exceptions{}

type ParsedAttribute is Data:
  ParsedUnknown{}
  ParsedVisibleAnnotations{values: +List<M.Annotation>}
  ParsedInvisibleAnnotations{values: +List<M.Annotation>}
  ParsedVisibleParameters{values: +List<+List<M.Annotation>>}
  ParsedInvisibleParameters{values: +List<+List<M.Annotation>>}
  ParsedVisibleTypes{values: +List<M.TypeAnnotation>}
  ParsedInvisibleTypes{values: +List<M.TypeAnnotation>}
  ParsedDefault{value: M.AnnotationValue}
  ParsedExceptions{values: +List<U32>}

type MetaState is Data:
  MetaState{flags: U32, exceptions: +List<U32>, annotations: +List<M.Annotation>, parameters: +List<+List<M.Annotation>>, types: +List<M.TypeAnnotation>, defaultValue: Maybe<&2, M.AnnotationValue>}

def meta_empty() -> MetaState:
  MetaState{0, Nil{}, Nil{}, Nil{}, Nil{}, None{}}

def meta_result(state: MetaState) -> M.AnnotationMetadata:
  match state:
    case MetaState{flags, exceptions, annotations, parameters, types, defaultValue}:
      M.AnnotationMetadata{flags, exceptions, annotations, parameters, types, defaultValue}

def kind_after_invisible_annotations(ok: Bool) -> AttrKind:
  match ok:
    case True{}:
      InvisibleAnnotations{}
    case False{}:
      Unknown{}

def kind_after_visible_annotations(ok: Bool, +name: String) -> AttrKind:
  match ok:
    case True{}:
      VisibleAnnotations{}
    case False{}:
      kind_after_invisible_annotations(String.eq(name, "RuntimeInvisibleAnnotations"))

def classify_annotations(+name: String) -> AttrKind:
  kind_after_visible_annotations(String.eq(name, "RuntimeVisibleAnnotations"), name)

def kind_after_invisible_parameters(ok: Bool) -> AttrKind:
  match ok:
    case True{}:
      InvisibleParameters{}
    case False{}:
      Unknown{}

def kind_after_visible_parameters(ok: Bool, +name: String) -> AttrKind:
  match ok:
    case True{}:
      VisibleParameters{}
    case False{}:
      kind_after_invisible_parameters(String.eq(name, "RuntimeInvisibleParameterAnnotations"))

def classify_parameters(+name: String) -> AttrKind:
  kind_after_visible_parameters(String.eq(name, "RuntimeVisibleParameterAnnotations"), name)

def kind_after_invisible_types(ok: Bool) -> AttrKind:
  match ok:
    case True{}:
      InvisibleTypes{}
    case False{}:
      Unknown{}

def kind_after_visible_types(ok: Bool, +name: String) -> AttrKind:
  match ok:
    case True{}:
      VisibleTypes{}
    case False{}:
      kind_after_invisible_types(String.eq(name, "RuntimeInvisibleTypeAnnotations"))

def classify_types(+name: String) -> AttrKind:
  kind_after_visible_types(String.eq(name, "RuntimeVisibleTypeAnnotations"), name)

def kind_after_exceptions(ok: Bool) -> AttrKind:
  match ok:
    case True{}:
      Exceptions{}
    case False{}:
      Unknown{}

def kind_after_default(ok: Bool, +name: String) -> AttrKind:
  match ok:
    case True{}:
      DefaultValue{}
    case False{}:
      kind_after_exceptions(String.eq(name, "Exceptions"))

def classify_default(+name: String) -> AttrKind:
  kind_after_default(String.eq(name, "AnnotationDefault"), name)

def classify_more_from_parameters(kind: AttrKind, +name: String) -> AttrKind:
  match kind:
    case Unknown{}:
      classify_types(name)
    case value:
      value

def classify_from_types(kind: AttrKind, +name: String) -> AttrKind:
  match kind:
    case Unknown{}:
      classify_default(name)
    case value:
      value

def classify_more(+name: String) -> AttrKind:
  classify_from_types(classify_more_from_parameters(classify_parameters(name), name), name)

def classify_from_annotations(kind: AttrKind, +name: String) -> AttrKind:
  match kind:
    case Unknown{}:
      classify_more(name)
    case value:
      value

def classify(+name: String) -> AttrKind:
  classify_from_annotations(classify_annotations(name), name)

def depth_check(depth: U32) -> Result<&2, &2, String, Unit>:
  require_annotation(U32.is_le(depth, max_depth()), "annotation nesting depth exceeded")

def count_annotations(count: U32) -> Result<&2, &2, String, Unit>:
  require_annotation(U32.is_le(count, max_annotations()), "annotation table is too large")

def count_elements(count: U32) -> Result<&2, &2, String, Unit>:
  require_annotation(U32.is_le(count, max_elements()), "annotation element table is too large")

def count_table(count: U32) -> Result<&2, &2, String, Unit>:
  require_annotation(U32.is_le(count, max_table()), "type annotation table is too large")

def words_u1_word(count: Nat, acc: +List<U32>, word: R.RWord, next: Nat -> R.Reader -> +List<U32> -> Result<&2, &2, String, WordsRead>) -> Result<&2, &2, String, WordsRead>:
  match word:
    case R.RWord{reader, value}:
      next(count, reader, Con{value, acc})

def words_u1_after(count: Nat, acc: +List<U32>, result: Result<&2, &2, String, R.RWord>, next: Nat -> R.Reader -> +List<U32> -> Result<&2, &2, String, WordsRead>) -> Result<&2, &2, String, WordsRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{word}:
      words_u1_word(count, acc, word, next)

@unsafe def words_u1(count: Nat, reader: R.Reader, acc: +List<U32>) -> Result<&2, &2, String, WordsRead>:
  match count:
    case 0n:
      Done{WordsRead{reader, M.reverse(U32, acc)}}
    case 1n+p:
      words_u1_after(p, acc, R.read_u1(reader), words_u1)


def words_u2_word(count: Nat, acc: +List<U32>, word: R.RWord, next: Nat -> R.Reader -> +List<U32> -> Result<&2, &2, String, WordsRead>) -> Result<&2, &2, String, WordsRead>:
  match word:
    case R.RWord{reader, value}:
      next(count, reader, Con{value, acc})

def words_u2_after(count: Nat, acc: +List<U32>, result: Result<&2, &2, String, R.RWord>, next: Nat -> R.Reader -> +List<U32> -> Result<&2, &2, String, WordsRead>) -> Result<&2, &2, String, WordsRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{word}:
      words_u2_word(count, acc, word, next)

@unsafe def words_u2(count: Nat, reader: R.Reader, acc: +List<U32>) -> Result<&2, &2, String, WordsRead>:
  match count:
    case 0n:
      Done{WordsRead{reader, M.reverse(U32, acc)}}
    case 1n+p:
      words_u2_after(p, acc, R.read_u2(reader), words_u2)

def localvar_target(length_word: R.RWord) -> Result<&2, &2, String, WordsRead>:
  match length_word:
    case R.RWord{reader, +value}:
      do Result<&2, &2, String, WordsRead>:
        count_table(value)
        words_u2(U32.to_nat((1 + value * 3 : U32)), reader, Con{value, Nil{}})

def target_offset_word(word: R.RWord) -> Result<&2, &2, String, WordsRead>:
  match word:
    case R.RWord{reader, value}:
      words_u1(1n, reader, [value])

def target_offset(result: Result<&2, &2, String, R.RWord>) -> Result<&2, &2, String, WordsRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{word}:
      target_offset_word(word)

def target_info(target: U32, reader: R.Reader) -> Result<&2, &2, String, WordsRead>:
  match target:
    case 0:
      words_u1(1n, reader, Nil{})
    case 1:
      words_u1(1n, reader, Nil{})
    case 16:
      words_u2(1n, reader, Nil{})
    case 17:
      words_u1(2n, reader, Nil{})
    case 18:
      words_u1(2n, reader, Nil{})
    case 19:
      Done{WordsRead{reader, Nil{}}}
    case 20:
      Done{WordsRead{reader, Nil{}}}
    case 21:
      Done{WordsRead{reader, Nil{}}}
    case 22:
      words_u1(1n, reader, Nil{})
    case 23:
      words_u2(1n, reader, Nil{})
    case 64:
      do Result<&2, &2, String, WordsRead>:
        length : R.RWord <- R.read_u2(reader)
        localvar_target(length)
    case 65:
      do Result<&2, &2, String, WordsRead>:
        length : R.RWord <- R.read_u2(reader)
        localvar_target(length)
    case 66:
      words_u2(1n, reader, Nil{})
    case 67:
      words_u2(1n, reader, Nil{})
    case 68:
      words_u2(1n, reader, Nil{})
    case 71:
      target_offset(R.read_u2(reader))
    case 72:
      target_offset(R.read_u2(reader))
    case 73:
      target_offset(R.read_u2(reader))
    case 74:
      target_offset(R.read_u2(reader))
    case 75:
      target_offset(R.read_u2(reader))
    case _:
      Fail{"VmError.InvalidAnnotation: unknown type annotation target_type"}


def path_index_word(count: Nat, +kind: U32, acc: +List<U32>, word: R.RWord, next: Nat -> R.Reader -> +List<U32> -> Result<&2, &2, String, PathRead>) -> Result<&2, &2, String, PathRead>:
  match word:
    case R.RWord{reader, value}:
      do Result<&2, &2, String, PathRead>:
        require_annotation(U32.is_le(kind, 3), "invalid type_path kind")
        next(count, reader, Con{value, Con{kind, acc}})

def path_index_result(count: Nat, kind: U32, acc: +List<U32>, result: Result<&2, &2, String, R.RWord>, next: Nat -> R.Reader -> +List<U32> -> Result<&2, &2, String, PathRead>) -> Result<&2, &2, String, PathRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{word}:
      path_index_word(count, kind, acc, word, next)

def path_kind_word(count: Nat, acc: +List<U32>, word: R.RWord, next: Nat -> R.Reader -> +List<U32> -> Result<&2, &2, String, PathRead>) -> Result<&2, &2, String, PathRead>:
  match word:
    case R.RWord{reader, value}:
      path_index_result(count, value, acc, R.read_u1(reader), next)

def path_kind_result(count: Nat, acc: +List<U32>, result: Result<&2, &2, String, R.RWord>, next: Nat -> R.Reader -> +List<U32> -> Result<&2, &2, String, PathRead>) -> Result<&2, &2, String, PathRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{word}:
      path_kind_word(count, acc, word, next)

@unsafe def path_go(count: Nat, reader: R.Reader, acc: +List<U32>) -> Result<&2, &2, String, PathRead>:
  match count:
    case 0n:
      Done{PathRead{reader, M.reverse(U32, acc)}}
    case 1n+p:
      path_kind_result(p, acc, R.read_u1(reader), path_go)

def type_path_word(result: Result<&2, &2, String, R.RWord>) -> Result<&2, &2, String, PathRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{word}:
      match word:
        case R.RWord{reader, +value}:
          do Result<&2, &2, String, PathRead>:
            require_annotation(U32.is_le(value, max_path()), "type_path is too long")
            path_go(U32.to_nat(value), reader, Nil{})

def type_path(reader: R.Reader) -> Result<&2, &2, String, PathRead>:
  type_path_word(R.read_u1(reader))
def enum_name_word(type_index: U32, +pool: +List<M.Constant>, word: R.RWord) -> Result<&2, &2, String, ValueRead>:
  match word:
    case R.RWord{reader, +value}:
      do Result<&2, &2, String, ValueRead>:
        checked : U32 <- enum_name_index(pool, value)
        return ValueRead{reader, M.AnnotationEnum{type_index, value}}

def enum_name_result(type_index: U32, +pool: +List<M.Constant>, result: Result<&2, &2, String, R.RWord>) -> Result<&2, &2, String, ValueRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{word}:
      enum_name_word(type_index, pool, word)

def enum_type_word(+pool: +List<M.Constant>, word: R.RWord) -> Result<&2, &2, String, ValueRead>:
  match word:
    case R.RWord{reader, +value}:
      do Result<&2, &2, String, ValueRead>:
        object_descriptor(pool, value)
        enum_name_result(value, pool, R.read_u2(reader))
def enum_type_result(+pool: +List<M.Constant>, result: Result<&2, &2, String, R.RWord>) -> Result<&2, &2, String, ValueRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{word}:
      enum_type_word(pool, word)

def enum_type(reader: R.Reader, +pool: +List<M.Constant>, depth: U32) -> Result<&2, &2, String, ValueRead>:
  enum_type_result(pool, R.read_u2(reader))

def class_value_word(+pool: +List<M.Constant>, word: R.RWord) -> Result<&2, &2, String, ValueRead>:
  match word:
    case R.RWord{reader, +value}:
      do Result<&2, &2, String, ValueRead>:
        text : String <- utf_annotation(pool, value)
        field_descriptor_result(D.parse_field(text))
        return ValueRead{reader, M.AnnotationClass{value}}

def class_value_result(+pool: +List<M.Constant>, result: Result<&2, &2, String, R.RWord>) -> Result<&2, &2, String, ValueRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{word}:
      class_value_word(pool, word)

def class_value(reader: R.Reader, +pool: +List<M.Constant>) -> Result<&2, &2, String, ValueRead>:
  class_value_result(pool, R.read_u2(reader))


@unsafe def nested_elements(elements: +List<M.AnnotationElement>) -> +List<M.AnnotationValue>:
  match elements:
    case Nil{}:
      Nil{}
    case Con{M.AnnotationElement{nameIndex, value}, tail}:
      Con{M.AnnotationElementValue{nameIndex, value}, nested_elements(tail)}

def nested_result(result: Result<&2, &2, String, AnnotationRead>) -> Result<&2, &2, String, ValueRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{value}:
      match value:
        case AnnotationRead{reader, value}:
          match value:
            case M.Annotation{typeIndex, elements}:
              Done{ValueRead{reader, M.AnnotationNested{typeIndex, nested_elements(elements)}}}

def array_values_result(+pool: +List<M.Constant>, result: Result<&2, &2, String, ValueReadList>) -> Result<&2, &2, String, ValueRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{value}:
      match value:
        case ValueReadList{reader, values}:
          Done{ValueRead{reader, M.AnnotationArray{values}}}

def elements_reader(value: ElementsRead) -> R.Reader:
  match value:
    case ElementsRead{reader, values}: reader

def elements_values(value: ElementsRead) -> +List<M.AnnotationElement>:
  match value:
    case ElementsRead{reader, values}: values

def value_reader(value: ValueRead) -> R.Reader:
  match value:
    case ValueRead{reader, value}: reader

def value_value(value: ValueRead) -> M.AnnotationValue:
  match value:
    case ValueRead{reader, value}: value

def nested_annotation(result: Result<&2, &2, String, AnnotationRead>) -> Result<&2, &2, String, ValueRead>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{value}:
      match value:
        case AnnotationRead{reader, value}:
          match value:
            case M.Annotation{typeIndex, elements}:
              Done{ValueRead{reader, M.AnnotationNested{typeIndex, nested_elements(elements)}}}

def primitive_value(tag: U32, reader: R.Reader, +pool: +List<M.Constant>, depth: U32) -> Result<&2, &2, String, ValueRead>:
  do Result<&2, &2, String, ValueRead>:
    depth_check(depth)
    word : R.RWord <- R.read_u2(reader)
    value : ValueRead <- value_from_word(tag, word, pool)
    return value

@unsafe def parse_value_core(~annotation_cb: @reader: R.Reader -> @+pool: +List<M.Constant> -> @depth: U32 -> Result<&2, &2, String, AnnotationRead>, mode: U32, count: Nat, tag: U32, reader: R.Reader, +pool: +List<M.Constant>, +depth: U32, acc: +List<M.AnnotationValue>) -> Result<&2, &2, String, ValueRead>:
  match mode:
    case 1:
      match count:
        case 0n:
          Done{ValueRead{reader, M.AnnotationArray{M.reverse(M.AnnotationValue, acc)}}}
        case 1n+p:
          do Result<&2, &2, String, ValueRead>:
            +tag_word : R.RWord <- R.read_u1(reader)
            item_tag : U32 = word_value(tag_word)
            item_reader : R.Reader = word_reader(tag_word)
            +item : ValueRead <- parse_value_core(~annotation_cb, 0, 0n, item_tag, item_reader, pool, depth, Nil{})
            next : ValueRead <- parse_value_core(~annotation_cb, 1, p, 0, value_reader(item), pool, depth, Con{value_value(item), acc})
            return next
    case _:
      match tag:
        case 66:
          primitive_value(tag, reader, pool, depth)
        case 67:
          primitive_value(tag, reader, pool, depth)
        case 83:
          primitive_value(tag, reader, pool, depth)
        case 90:
          primitive_value(tag, reader, pool, depth)
        case 73:
          primitive_value(tag, reader, pool, depth)
        case 70:
          primitive_value(tag, reader, pool, depth)
        case 74:
          primitive_value(tag, reader, pool, depth)
        case 68:
          primitive_value(tag, reader, pool, depth)
        case 115:
          primitive_value(tag, reader, pool, depth)
        case 101:
          enum_type(reader, pool, depth)
        case 99:
          class_value(reader, pool)
        case 64:
          do Result<&2, &2, String, ValueRead>:
            result : ValueRead <- nested_annotation(annotation_cb(reader, pool, (depth + 1 : U32)))
            return result
        case 91:
          do Result<&2, &2, String, ValueRead>:
            depth_check(depth)
            +count_word : R.RWord <- R.read_u2(reader)
            +array_count : U32 = word_value(count_word)
            count_elements(array_count)
            result : ValueRead <- parse_value_core(~annotation_cb, 1, U32.to_nat(array_count), 0, word_reader(count_word), pool, depth, Nil{})
            return result
        case _:
          Fail{"VmError.InvalidAnnotation: unknown annotation element_value tag"}

@unsafe def parse_value_entry(~annotation_cb: @reader: R.Reader -> @+pool: +List<M.Constant> -> @depth: U32 -> Result<&2, &2, String, AnnotationRead>, tag: U32, reader: R.Reader, +pool: +List<M.Constant>, depth: U32) -> Result<&2, &2, String, ValueRead>:
  parse_value_core(~annotation_cb, 0, 0n, tag, reader, pool, depth, Nil{})

@unsafe def elements_go(~annotation_cb: @reader: R.Reader -> @+pool: +List<M.Constant> -> @depth: U32 -> Result<&2, &2, String, AnnotationRead>, count: Nat, reader: R.Reader, +pool: +List<M.Constant>, +depth: U32, acc: +List<M.AnnotationElement>) -> Result<&2, &2, String, ElementsRead>:
  match count:
    case 0n:
      Done{ElementsRead{reader, M.reverse(M.AnnotationElement, acc)}}
    case 1n+p:
      do Result<&2, &2, String, ElementsRead>:
        +name_word : R.RWord <- R.read_u2(reader)
        name_ref : U32 = word_value(name_word)
        name_reader : R.Reader = word_reader(name_word)
        name : U32 <- name_index(pool, name_ref)
        +tag_word : R.RWord <- R.read_u1(name_reader)
        tag : U32 = word_value(tag_word)
        +value : ValueRead <- parse_value_core(~annotation_cb, 0, 0n, tag, word_reader(tag_word), pool, depth, Nil{})
        next : ElementsRead <- elements_go(~annotation_cb, p, value_reader(value), pool, depth, Con{M.AnnotationElement{name, value_value(value)}, acc})
        return next

@unsafe def annotation_core(~annotation_cb: @reader: R.Reader -> @+pool: +List<M.Constant> -> @depth: U32 -> Result<&2, &2, String, AnnotationRead>, reader: R.Reader, +pool: +List<M.Constant>, depth: U32) -> Result<&2, &2, String, AnnotationRead>:
  do Result<&2, &2, String, AnnotationRead>:
    +type_word : R.RWord <- R.read_u2(reader)
    +type_index : U32 = word_value(type_word)
    annotation_descriptor(pool, type_index)
    +count_word : R.RWord <- R.read_u2(word_reader(type_word))
    +count : U32 = word_value(count_word)
    count_elements(count)
    +result : ElementsRead <- elements_go(~annotation_cb, U32.to_nat(count), word_reader(count_word), pool, depth, Nil{})
    return AnnotationRead{elements_reader(result), M.Annotation{type_index, elements_values(result)}}

@unsafe def parse_annotation_entry(reader: R.Reader, +pool: +List<M.Constant>, depth: U32) -> Result<&2, &2, String, AnnotationRead>:
  annotation_core(~parse_annotation_entry, reader, pool, depth)

def annotations_finish_reader(values: +List<M.Annotation>, result: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, +List<M.Annotation>>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      Done{values}

def annotations_finish(result: Result<&2, &2, String, AnnotationsRead>) -> Result<&2, &2, String, +List<M.Annotation>>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{value}:
      match value:
        case AnnotationsRead{reader, values}:
          annotations_finish_reader(values, R.finish(reader))

def annotation_reader(value: AnnotationRead) -> R.Reader:
  match value:
    case AnnotationRead{reader, value}: reader

def annotation_value(value: AnnotationRead) -> M.Annotation:
  match value:
    case AnnotationRead{reader, value}: value

@unsafe def annotations_go(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, acc: +List<M.Annotation>) -> Result<&2, &2, String, AnnotationsRead>:
  match count:
    case 0n:
      Done{AnnotationsRead{reader, M.reverse(M.Annotation, acc)}}
    case 1n+p:
      do Result<&2, &2, String, AnnotationsRead>:
        +annotation : AnnotationRead <- parse_annotation_entry(reader, pool, 0)
        next : AnnotationsRead <- annotations_go(p, annotation_reader(annotation), pool, Con{annotation_value(annotation), acc})
        return next

def annotations_count_word(+pool: +List<M.Constant>, word: R.RWord) -> Result<&2, &2, String, +List<M.Annotation>>:
  match word:
    case R.RWord{reader, +value}:
      do Result<&2, &2, String, +List<M.Annotation>>:
        count_annotations(value)
        values : +List<M.Annotation> <- annotations_finish(annotations_go(U32.to_nat(value), reader, pool, Nil{}))
        return values

def parse_annotation_bytes(bytes: +List<U32>, +pool: +List<M.Constant>) -> Result<&2, &2, String, +List<M.Annotation>>:
  reader = R.new(bytes)
  do Result<&2, &2, String, +List<M.Annotation>>:
    word : R.RWord <- R.read_u2(reader)
    values : +List<M.Annotation> <- annotations_count_word(pool, word)
    return values

def annotations_reader(value: AnnotationsRead) -> R.Reader:
  match value:
    case AnnotationsRead{reader, values}: reader

def annotations_values(value: AnnotationsRead) -> +List<M.Annotation>:
  match value:
    case AnnotationsRead{reader, values}: values

@unsafe def parameters_go(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, acc: +List<+List<M.Annotation>>) -> Result<&2, &2, String, ParameterAnnotationsRead>:
  match count:
    case 0n:
      Done{ParameterAnnotationsRead{reader, M.reverse(+List<M.Annotation>, acc)}}
    case 1n+p:
      do Result<&2, &2, String, ParameterAnnotationsRead>:
        +count_word : R.RWord <- R.read_u2(reader)
        +count : U32 = word_value(count_word)
        count_annotations(count)
        +annotations : AnnotationsRead <- annotations_go(U32.to_nat(count), word_reader(count_word), pool, Nil{})
        next : ParameterAnnotationsRead <- parameters_go(p, annotations_reader(annotations), pool, Con{annotations_values(annotations), acc})
        return next
def parameters_finish_reader(values: +List<+List<M.Annotation>>, result: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, +List<+List<M.Annotation>>>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      Done{values}

def parameters_finish(result: Result<&2, &2, String, ParameterAnnotationsRead>) -> Result<&2, &2, String, +List<+List<M.Annotation>>>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{value}:
      match value:
        case ParameterAnnotationsRead{reader, values}:
          parameters_finish_reader(values, R.finish(reader))

def parameters_count_word_top(+pool: +List<M.Constant>, word: R.RWord) -> Result<&2, &2, String, +List<+List<M.Annotation>>>:
  match word:
    case R.RWord{reader, +value}:
      do Result<&2, &2, String, +List<+List<M.Annotation>>>:
        require_annotation(U32.is_le(value, max_parameters()), "parameter annotation table is too large")
        values : +List<+List<M.Annotation>> <- parameters_finish(parameters_go(U32.to_nat(value), reader, pool, Nil{}))
        return values

def parse_parameters_bytes(bytes: +List<U32>, +pool: +List<M.Constant>) -> Result<&2, &2, String, +List<+List<M.Annotation>>>:
  reader = R.new(bytes)
  do Result<&2, &2, String, +List<+List<M.Annotation>>>:
    word : R.RWord <- R.read_u1(reader)
    values : +List<+List<M.Annotation>> <- parameters_count_word_top(pool, word)
    return values

def words_reader(value: WordsRead) -> R.Reader:
  match value:
    case WordsRead{reader, values}: reader

def words_values(value: WordsRead) -> +List<U32>:
  match value:
    case WordsRead{reader, values}: values

def path_reader(value: PathRead) -> R.Reader:
  match value:
    case PathRead{reader, values}: reader

def path_values(value: PathRead) -> +List<U32>:
  match value:
    case PathRead{reader, values}: values

@unsafe def type_annotations_go(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, acc: +List<M.TypeAnnotation>) -> Result<&2, &2, String, TypeAnnotationsRead>:
  match count:
    case 0n:
      Done{TypeAnnotationsRead{reader, M.reverse(M.TypeAnnotation, acc)}}
    case 1n+p:
      do Result<&2, &2, String, TypeAnnotationsRead>:
        +target_word : R.RWord <- R.read_u1(reader)
        +target : U32 = word_value(target_word)
        +target_read : WordsRead <- target_info(target, word_reader(target_word))
        +path_read : PathRead <- type_path(words_reader(target_read))
        +annotation : AnnotationRead <- parse_annotation_entry(path_reader(path_read), pool, 0)
        next : TypeAnnotationsRead <- type_annotations_go(p, annotation_reader(annotation), pool, Con{M.TypeAnnotation{target, words_values(target_read), path_values(path_read), annotation_value(annotation)}, acc})
        return next
def types_finish_reader(values: +List<M.TypeAnnotation>, result: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, +List<M.TypeAnnotation>>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      Done{values}

def types_finish(result: Result<&2, &2, String, TypeAnnotationsRead>) -> Result<&2, &2, String, +List<M.TypeAnnotation>>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{value}:
      match value:
        case TypeAnnotationsRead{reader, values}:
          types_finish_reader(values, R.finish(reader))

def types_count_word(+pool: +List<M.Constant>, word: R.RWord) -> Result<&2, &2, String, +List<M.TypeAnnotation>>:
  match word:
    case R.RWord{reader, +value}:
      do Result<&2, &2, String, +List<M.TypeAnnotation>>:
        count_annotations(value)
        values : +List<M.TypeAnnotation> <- types_finish(type_annotations_go(U32.to_nat(value), reader, pool, Nil{}))
        return values

def parse_types_bytes(bytes: +List<U32>, +pool: +List<M.Constant>) -> Result<&2, &2, String, +List<M.TypeAnnotation>>:
  reader = R.new(bytes)
  do Result<&2, &2, String, +List<M.TypeAnnotation>>:
    word : R.RWord <- R.read_u2(reader)
    values : +List<M.TypeAnnotation> <- types_count_word(pool, word)
    return values

def default_finish(value: M.AnnotationValue, result: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, M.AnnotationValue>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      Done{value}

def default_result(result: Result<&2, &2, String, ValueRead>) -> Result<&2, &2, String, M.AnnotationValue>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{value}:
      match value:
        case ValueRead{reader, value}:
          default_finish(value, R.finish(reader))

def default_word(+pool: +List<M.Constant>, word: R.RWord) -> Result<&2, &2, String, M.AnnotationValue>:
  match word:
    case R.RWord{reader, value}:
      default_result(parse_value_core(~parse_annotation_entry, 0, 0n, value, reader, pool, 0, Nil{}))

def parse_default_bytes(bytes: +List<U32>, +pool: +List<M.Constant>) -> Result<&2, &2, String, M.AnnotationValue>:
  reader = R.new(bytes)
  do Result<&2, &2, String, M.AnnotationValue>:
    word : R.RWord <- R.read_u1(reader)
    value : M.AnnotationValue <- default_word(pool, word)
    return value

@unsafe def exceptions_go(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, acc: +List<U32>) -> Result<&2, &2, String, WordsRead>:
  match count:
    case 0n:
      Done{WordsRead{reader, M.reverse(U32, acc)}}
    case 1n+p:
      do Result<&2, &2, String, WordsRead>:
        +word : R.RWord <- R.read_u2(reader)
        +value : U32 = word_value(word)
        class_constant(pool, value)
        next : WordsRead <- exceptions_go(p, word_reader(word), pool, Con{value, acc})
        return next

def exceptions_finish_reader(values: +List<U32>, result: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, +List<U32>>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      Done{values}

def exceptions_finish(result: Result<&2, &2, String, WordsRead>) -> Result<&2, &2, String, +List<U32>>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{value}:
      match value:
        case WordsRead{reader, values}:
          exceptions_finish_reader(values, R.finish(reader))

def exceptions_count_word(+pool: +List<M.Constant>, word: R.RWord) -> Result<&2, &2, String, +List<U32>>:
  match word:
    case R.RWord{reader, +value}:
      do Result<&2, &2, String, +List<U32>>:
        count_table(value)
        values : +List<U32> <- exceptions_finish(exceptions_go(U32.to_nat(value), reader, pool, Nil{}))
        return values
def parse_exceptions_bytes(bytes: +List<U32>, +pool: +List<M.Constant>) -> Result<&2, &2, String, +List<U32>>:
  reader = R.new(bytes)
  do Result<&2, &2, String, +List<U32>>:
    word : R.RWord <- R.read_u2(reader)
    values : +List<U32> <- exceptions_count_word(pool, word)
    return values

def parse_one(kind: AttrKind, bytes: +List<U32>, +pool: +List<M.Constant>) -> Result<&2, &2, String, ParsedAttribute>:
  match kind:
    case Unknown{}:
      Done{ParsedUnknown{}}
    case VisibleAnnotations{}:
      do Result<&2, &2, String, ParsedAttribute>:
        values : +List<M.Annotation> <- parse_annotation_bytes(bytes, pool)
        return ParsedVisibleAnnotations{values}
    case InvisibleAnnotations{}:
      do Result<&2, &2, String, ParsedAttribute>:
        values : +List<M.Annotation> <- parse_annotation_bytes(bytes, pool)
        return ParsedInvisibleAnnotations{values}
    case VisibleParameters{}:
      do Result<&2, &2, String, ParsedAttribute>:
        values : +List<+List<M.Annotation>> <- parse_parameters_bytes(bytes, pool)
        return ParsedVisibleParameters{values}
    case InvisibleParameters{}:
      do Result<&2, &2, String, ParsedAttribute>:
        values : +List<+List<M.Annotation>> <- parse_parameters_bytes(bytes, pool)
        return ParsedInvisibleParameters{values}
    case VisibleTypes{}:
      do Result<&2, &2, String, ParsedAttribute>:
        values : +List<M.TypeAnnotation> <- parse_types_bytes(bytes, pool)
        return ParsedVisibleTypes{values}
    case InvisibleTypes{}:
      do Result<&2, &2, String, ParsedAttribute>:
        values : +List<M.TypeAnnotation> <- parse_types_bytes(bytes, pool)
        return ParsedInvisibleTypes{values}
    case DefaultValue{}:
      do Result<&2, &2, String, ParsedAttribute>:
        value : M.AnnotationValue <- parse_default_bytes(bytes, pool)
        return ParsedDefault{value}
    case Exceptions{}:
      do Result<&2, &2, String, ParsedAttribute>:
        values : +List<U32> <- parse_exceptions_bytes(bytes, pool)
        return ParsedExceptions{values}

def duplicate(bit: U32, flags: U32) -> Result<&2, &2, String, Unit>:
  require_annotation(U32.is_eq(U32.and(bit, flags), 0), "duplicate annotation attribute")

def add_parsed(parsed: ParsedAttribute, state: MetaState) -> Result<&2, &2, String, MetaState>:
  match parsed state:
    case ParsedUnknown{} MetaState{flags, exceptions, annotations, parameters, types, defaultValue}:
      Done{MetaState{flags, exceptions, annotations, parameters, types, defaultValue}}
    case ParsedVisibleAnnotations{values} MetaState{+flags, exceptions, annotations, parameters, types, defaultValue}:
      do Result<&2, &2, String, MetaState>:
        duplicate(1, flags)
        return MetaState{U32.or(flags, 1), exceptions, values, parameters, types, defaultValue}
    case ParsedInvisibleAnnotations{values} MetaState{+flags, exceptions, annotations, parameters, types, defaultValue}:
      do Result<&2, &2, String, MetaState>:
        duplicate(2, flags)
        return MetaState{U32.or(flags, 2), exceptions, annotations, parameters, types, defaultValue}
    case ParsedVisibleParameters{values} MetaState{+flags, exceptions, annotations, parameters, types, defaultValue}:
      do Result<&2, &2, String, MetaState>:
        duplicate(4, flags)
        return MetaState{U32.or(flags, 4), exceptions, annotations, values, types, defaultValue}
    case ParsedInvisibleParameters{values} MetaState{+flags, exceptions, annotations, parameters, types, defaultValue}:
      do Result<&2, &2, String, MetaState>:
        duplicate(8, flags)
        return MetaState{U32.or(flags, 8), exceptions, annotations, parameters, types, defaultValue}
    case ParsedVisibleTypes{values} MetaState{+flags, exceptions, annotations, parameters, types, defaultValue}:
      do Result<&2, &2, String, MetaState>:
        duplicate(16, flags)
        return MetaState{U32.or(flags, 16), exceptions, annotations, parameters, values, defaultValue}
    case ParsedInvisibleTypes{values} MetaState{+flags, exceptions, annotations, parameters, types, defaultValue}:
      do Result<&2, &2, String, MetaState>:
        duplicate(32, flags)
        return MetaState{U32.or(flags, 32), exceptions, annotations, parameters, types, defaultValue}
    case ParsedDefault{value} MetaState{+flags, exceptions, annotations, parameters, types, defaultValue}:
      do Result<&2, &2, String, MetaState>:
        duplicate(64, flags)
        return MetaState{U32.or(flags, 64), exceptions, annotations, parameters, types, Some{value}}
    case ParsedExceptions{values} MetaState{+flags, exceptions, annotations, parameters, types, defaultValue}:
      do Result<&2, &2, String, MetaState>:
        duplicate(128, flags)
        return MetaState{U32.or(flags, 128), values, annotations, parameters, types, defaultValue}

@unsafe def attributes_go(fuel: Nat, attributes: +List<M.Attribute>, +pool: +List<M.Constant>, state: MetaState) -> Result<&2, &2, String, MetaState>:
  match fuel attributes:
    case 0n Nil{}:
      Done{state}
    case 0n Con{head, tail}:
      Fail{"VmError.InvalidAnnotation: too many attributes"}
    case 1n+p Nil{}:
      Done{state}
    case 1n+p Con{M.Attribute{name, +bytes}, tail}:
      do Result<&2, &2, String, MetaState>:
        +parsed : ParsedAttribute <- parse_one(classify(name), bytes, pool)
        next_state : MetaState <- add_parsed(parsed, state)
        next : MetaState <- attributes_go(p, tail, pool, next_state)
        return next

def parse_attributes(attributes: +List<M.Attribute>, +pool: +List<M.Constant>) -> Result<&2, &2, String, M.AnnotationMetadata>:
  do Result<&2, &2, String, M.AnnotationMetadata>:
    state : MetaState <- attributes_go(max_attributes(), attributes, pool, meta_empty())
    return meta_result(state)
