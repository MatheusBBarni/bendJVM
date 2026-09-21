import Base
import ../model.bend as M
import ./reader.bend as R

type ParsedType is Data:
  ParsedType{value: M.JvmType, rest: String}

def slot_tag(value: M.JvmType) -> U32:
  match value:
    case M.Primitive{86}:
      0
    case M.Primitive{70}:
      2
    case M.Primitive{tag}:
      1
    case M.ObjectType{name}:
      3
    case M.ArrayType{element}:
      3
def parameter_count(value: M.Descriptor) -> U32:
  match value:
    case M.Descriptor{parameters, result}:
      M.length(M.JvmType, parameters)

def result_type(value: M.Descriptor) -> M.JvmType:
  match value:
    case M.Descriptor{parameters, result}:
      result
def parameter_types(value: M.Descriptor) -> +List<M.JvmType>:
  match value:
    case M.Descriptor{parameters, result}:
      parameters

def slots(value: M.JvmType) -> U32:
  match value:
    case M.Primitive{86}:
      0
    case M.Primitive{74}:
      2
    case M.Primitive{68}:
      2
    case M.Primitive{tag}:
      1
    case M.ObjectType{name}:
      1
    case M.ArrayType{element}:
      1

def parameter_slots(values: +List<M.JvmType>) -> U32:
  match values:
    case Nil{}:
      0
    case Con{h, t}:
      (slots(h) + parameter_slots(t) : U32)

def name_go(text: String, component: Bool) -> Bool:
  match text:
    case SNil{}:
      component
    case SCon{Chr{47}, t}:
      Bool.and(component, name_go(t, False{}))
    case SCon{Chr{46}, t}:
      False{}
    case SCon{Chr{59}, t}:
      False{}
    case SCon{Chr{91}, t}:
      False{}
    case SCon{Chr{0}, t}:
      False{}
    case SCon{h, t}:
      name_go(t, True{})

def valid_class_name(text: String) -> Bool:
  name_go(text, False{})

def valid_member_name(text: String) -> Bool:
  match text:
    case SNil{}:
      False{}
    case SCon{+h, +t}:
      Bool.and(Bool.not(String.contains(SCon{h, t}, "/")), valid_class_name(SCon{h, t}))

def object_value(name: String, rest: String) -> ParsedType:
  ParsedType{M.ObjectType{name}, rest}

def object_finish(check: Result<&2, &2, String, Unit>, name: String, rest: String) -> Result<&2, &2, String, ParsedType>:
  match check:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      Done{object_value(name, rest)}

def object_name(text: String, acc: String) -> Result<&2, &2, String, ParsedType>:
  match text:
    case SNil{}:
      Fail{"VmError.InvalidDescriptor: unterminated object type"}
    case SCon{Chr{59}, t}:
      +name = String.reverse(acc)
      object_finish(R.require(valid_class_name(name), "VmError.InvalidDescriptor: invalid object name"), name, t)
    case SCon{h, t}:
      object_name(t, SCon{h, acc})
def array_type(parsed: Result<&2, &2, String, ParsedType>) -> Result<&2, &2, String, ParsedType>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{ParsedType{value, rest}}:
      Done{ParsedType{M.ArrayType{value}, rest}}

def parse_type(fuel: Nat, text: String, allow_void: Bool, +depth: U32) -> Result<&2, &2, String, ParsedType>:
  match fuel text:
    case 0n _:
      Fail{"VmError.InvalidDescriptor: incomplete type"}
    case 1n+p SNil{}:
      Fail{"VmError.InvalidDescriptor: missing type"}
    case 1n+p SCon{Chr{66}, t}:
      Done{ParsedType{M.Primitive{66}, t}}
    case 1n+p SCon{Chr{67}, t}:
      Done{ParsedType{M.Primitive{67}, t}}
    case 1n+p SCon{Chr{68}, t}:
      Done{ParsedType{M.Primitive{68}, t}}
    case 1n+p SCon{Chr{70}, t}:
      Done{ParsedType{M.Primitive{70}, t}}
    case 1n+p SCon{Chr{73}, t}:
      Done{ParsedType{M.Primitive{73}, t}}
    case 1n+p SCon{Chr{74}, t}:
      Done{ParsedType{M.Primitive{74}, t}}
    case 1n+p SCon{Chr{83}, t}:
      Done{ParsedType{M.Primitive{83}, t}}
    case 1n+p SCon{Chr{90}, t}:
      Done{ParsedType{M.Primitive{90}, t}}
    case 1n+p SCon{Chr{86}, t}:
      do Result<&2, &2, String, ParsedType>:
        R.require(allow_void, "VmError.InvalidDescriptor: void is only a return type")
        return ParsedType{M.Primitive{86}, t}
    case 1n+p SCon{Chr{76}, t}:
      object_name(t, SNil{})
    case 1n+p SCon{Chr{91}, t}:
      do Result<&2, &2, String, ParsedType>:
        R.require(U32.is_lt(depth, 255), "VmError.InvalidDescriptor: array exceeds 255 dimensions")
        value : ParsedType <- array_type(parse_type(p, t, False{}, (depth + 1 : U32)))
        return value
    case 1n+p SCon{h, t}:
      Fail{"VmError.InvalidDescriptor: unknown type tag"}

def field_checked(check: Result<&2, &2, String, Unit>, value: M.JvmType) -> Result<&2, &2, String, M.JvmType>:
  match check:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      Done{value}

def field_parsed(parsed: ParsedType) -> Result<&2, &2, String, M.JvmType>:
  match parsed:
    case ParsedType{value, rest}:
      field_checked(R.require(String.is_empty(rest), "VmError.InvalidDescriptor: trailing field descriptor text"), value)

def return_limited(check: Result<&2, &2, String, Unit>, parameters: +List<M.JvmType>, value: M.JvmType) -> Result<&2, &2, String, M.Descriptor>:
  match check:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      Done{M.Descriptor{M.reverse(M.JvmType, parameters), value}}

def return_after_rest(check: Result<&2, &2, String, Unit>, +parameters: +List<M.JvmType>, value: M.JvmType) -> Result<&2, &2, String, M.Descriptor>:
  match check:
    case Fail{error}:
      Fail{error}
    case Done{unit}:
      return_limited(R.require(U32.is_le(parameter_slots(parameters), 255), "VmError.InvalidDescriptor: parameter slots exceed 255"), parameters, value)

def return_parsed(parsed: ParsedType, parameters: +List<M.JvmType>) -> Result<&2, &2, String, M.Descriptor>:
  match parsed:
    case ParsedType{value, rest}:
      return_after_rest(R.require(String.is_empty(rest), "VmError.InvalidDescriptor: trailing method descriptor text"), parameters, value)


def parse_field(+text: String) -> Result<&2, &2, String, M.JvmType>:
  do Result<&2, &2, String, M.JvmType>:
    parsed : ParsedType <- parse_type(1n+String.length(text), text, False{}, 0)
    result : M.JvmType <- field_parsed(parsed)
    return result

def return_type(+text: String, +parameters: +List<M.JvmType>) -> Result<&2, &2, String, M.Descriptor>:
  do Result<&2, &2, String, M.Descriptor>:
    parsed : ParsedType <- parse_type(1n+String.length(text), text, True{}, 0)
    result : M.Descriptor <- return_parsed(parsed, parameters)
    return result

def parse_type_text(+text: String, allow_void: Bool) -> Result<&2, &2, String, ParsedType>:
  parse_type(1n+String.length(text), text, allow_void, 0)

def parameter_continue(parsed: Result<&2, &2, String, ParsedType>, fuel: Nat, acc: +List<M.JvmType>, next: Nat -> String -> +List<M.JvmType> -> Result<&2, &2, String, M.Descriptor>) -> Result<&2, &2, String, M.Descriptor>:
  match parsed:
    case Fail{error}:
      Fail{error}
    case Done{ParsedType{value, rest}}:
      next(fuel, rest, Con{value, acc})

@unsafe def parameters(fuel: Nat, text: String, acc: +List<M.JvmType>) -> Result<&2, &2, String, M.Descriptor>:
  match fuel text:
    case 0n _:
      Fail{"VmError.InvalidDescriptor: unterminated parameters"}
    case 1n+p SNil{}:
      Fail{"VmError.InvalidDescriptor: missing closing parenthesis"}
    case 1n+p SCon{Chr{41}, +t}:
      return_type(t, acc)
    case 1n+p SCon{h, t}:
      parameter_continue(parse_type_text(SCon{h, t}, False{}), p, acc, parameters)

def method_start(text: String) -> Result<&2, &2, String, M.Descriptor>:
  match text:
    case SCon{Chr{40}, +t}:
      parameters(1n+String.length(t), t, Nil{})
    case _:
      Fail{"VmError.InvalidDescriptor: method must start with parenthesis"}

def parse_method(text: String) -> Result<&2, &2, String, M.Descriptor>:
  method_start(text)
