import Base
import ../model.bend as M

# Java 8 method signatures. An absent attribute stays erased; this parser does
# not invent type arguments the class file did not record.
type SigType is Data:
  Base{name: String}
  Object{binary: String, args: +List<SigType>}
  Var{name: String}
  Array{element: SigType}
  Wild{kind: U32, bound: Maybe<&2, SigType>}

type TypeParam is Data:
  TypeParam{name: String, bounds: +List<SigType>}

type MethodSignature is Data:
  MethodSignature{variables: +List<TypeParam>, parameters: +List<SigType>, result: SigType, thrown: +List<SigType>}

type Frame is Data:
  WantArray{}
  WantWild{kind: U32}
  WantArg{binary: String, acc: +List<SigType>}
  WantParam{acc: +List<SigType>, variables: +List<TypeParam>}
  WantBound{name: String, bounds: +List<SigType>, params: +List<TypeParam>}
  WantResult{variables: +List<TypeParam>, parameters: +List<SigType>}
  WantThrow{variables: +List<TypeParam>, parameters: +List<SigType>, result: SigType, acc: +List<SigType>}

type Work is Data:
  Work{mode: U32, text: String, acc: String, types: +List<SigType>, params: +List<TypeParam>, name: String, binary: String, void_ok: Bool, stack: +List<Frame>, signature: MethodSignature}

type Next is Data:
  Continue{value: Work}
  Stop{value: MethodSignature}

def empty_signature() -> MethodSignature:
  MethodSignature{Nil{}, Nil{}, Base{"void"}, Nil{}}

def fail(-A: Data, text: String) -> Result<&2, &2, String, A>:
  Fail{"VmError.InvalidSignature: " ++ text}

def char_text(value: Char) -> String:
  String.from_list([value])

def display_name(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{47}, rest}: "." ++ display_name(rest)
    case SCon{head, rest}: char_text(head) ++ display_name(rest)

def join_owner(prefix: String, current: String) -> String:
  match prefix:
    case SNil{}: current
    case _: prefix ++ "$" ++ current

def owner_prefix_go(text: String, prefix: String, current: String) -> String:
  match text:
    case SNil{}: prefix
    case SCon{Chr{36}, rest}: owner_prefix_go(rest, join_owner(prefix, current), "")
    case SCon{head, rest}: owner_prefix_go(rest, prefix, current ++ char_text(head))

def owner_prefix(text: String) -> String:
  owner_prefix_go(text, "", "")

type Show is Data:
  One{value: SigType}
  Many{values: +List<SigType>, first: Bool}

@unsafe def show(item: Show) -> String:
  match item:
    case One{Base{name}}: name
    case One{Var{name}}: name
    case One{Array{element}}: show(One{element}) ++ "[]"
    case One{Wild{kind, bound}}:
      match kind bound:
        case 1 Some{inner}: "? extends " ++ show(One{inner})
        case 2 Some{inner}: "? super " ++ show(One{inner})
        case _ _: "?"
    case One{Object{binary, args}}:
      match args:
        case Nil{}: display_name(binary)
        case _: display_name(binary) ++ "<" ++ show(Many{args, True{}}) ++ ">"
    case Many{Nil{}, first}: ""
    case Many{Con{head, tail}, first}:
      Bool.pick(String, first, "", ", ") ++ show(One{head}) ++ show(Many{tail, False{}})

def type_name(value: SigType) -> String:
  show(One{value})

def work(mode: U32, text: String, acc: String, types: +List<SigType>, params: +List<TypeParam>, name: String, binary: String, void_ok: Bool, stack: +List<Frame>, signature: MethodSignature) -> Work:
  Work{mode, text, acc, types, params, name, binary, void_ok, stack, signature}

def go(mode: U32, text: String, acc: String, types: +List<SigType>, params: +List<TypeParam>, name: String, binary: String, stack: +List<Frame>, signature: MethodSignature) -> Result<&2, &2, String, Next>:
  Done{Continue{work(mode, text, acc, types, params, name, binary, False{}, stack, signature)}}

def pop_type(stack: +List<Frame>, typ: SigType, rest: String, signature: MethodSignature) -> Result<&2, &2, String, Next>:
  match stack:
    case Nil{}: fail(Next, "unexpected type")
    case Con{WantArray{}, tail}: pop_type(tail, Array{typ}, rest, signature)
    case Con{WantWild{kind}, tail}: pop_type(tail, Wild{kind, Some{typ}}, rest, signature)
    case Con{WantArg{arg_binary, arg_acc}, tail}: go(5, rest, "", Con{typ, arg_acc}, Nil{}, "", arg_binary, tail, signature)
    case Con{WantParam{arg_acc, variables}, tail}: go(7, rest, "", Con{typ, arg_acc}, variables, "", "", tail, signature)
    case Con{WantBound{bound_name, bounds, bound_params}, tail}: go(10, rest, "", Con{typ, bounds}, bound_params, bound_name, "", tail, signature)
    case Con{WantResult{+variables, +parameters}, tail}: go(8, rest, "", Nil{}, variables, "", "", tail, MethodSignature{variables, parameters, typ, Nil{}})
    case Con{WantThrow{+variables, +parameters, result, thrown}, tail}: go(8, rest, "", Con{typ, thrown}, variables, "", "", tail, MethodSignature{variables, parameters, result, Nil{}})

def start_java(text: String, void_ok: Bool, frame: Frame, stack: +List<Frame>, signature: MethodSignature) -> Work:
  Work{1, text, "", Nil{}, Nil{}, "", "", void_ok, Con{frame, stack}, signature}

def start_ref(text: String, frame: Frame, stack: +List<Frame>, signature: MethodSignature) -> Work:
  Work{2, text, "", Nil{}, Nil{}, "", "", False{}, Con{frame, stack}, signature}

def signature_result(value: MethodSignature) -> SigType:
  match value:
    case MethodSignature{variables, parameters, result, thrown}: result

def once(value: Work) -> Result<&2, &2, String, Next>:
  match value:
    case Work{mode, text, acc, types, params, name, binary, void_ok, stack, signature}:
      match mode text:
        case 1 SNil{}: fail(Next, "java type")
        case 1 SCon{Chr{66}, rest}: pop_type(stack, Base{"byte"}, rest, signature)
        case 1 SCon{Chr{67}, rest}: pop_type(stack, Base{"char"}, rest, signature)
        case 1 SCon{Chr{68}, rest}: pop_type(stack, Base{"double"}, rest, signature)
        case 1 SCon{Chr{70}, rest}: pop_type(stack, Base{"float"}, rest, signature)
        case 1 SCon{Chr{73}, rest}: pop_type(stack, Base{"int"}, rest, signature)
        case 1 SCon{Chr{74}, rest}: pop_type(stack, Base{"long"}, rest, signature)
        case 1 SCon{Chr{83}, rest}: pop_type(stack, Base{"short"}, rest, signature)
        case 1 SCon{Chr{90}, rest}: pop_type(stack, Base{"boolean"}, rest, signature)
        case 1 SCon{Chr{86}, rest}:
          match void_ok:
            case True{}: pop_type(stack, Base{"void"}, rest, signature)
            case False{}: fail(Next, "void type")
        case 1 SCon{Chr{76}, rest}: go(3, rest, "", Nil{}, Nil{}, "", "", stack, signature)
        case 1 SCon{Chr{84}, rest}: go(6, rest, "", Nil{}, Nil{}, "", "", stack, signature)
        case 1 SCon{Chr{91}, rest}: Done{Continue{start_java(rest, False{}, WantArray{}, stack, signature)}}
        case 1 _: fail(Next, "java type")
        case 2 SNil{}: fail(Next, "reference type")
        case 2 SCon{Chr{76}, rest}: go(3, rest, "", Nil{}, Nil{}, "", "", stack, signature)
        case 2 SCon{Chr{84}, rest}: go(6, rest, "", Nil{}, Nil{}, "", "", stack, signature)
        case 2 SCon{Chr{91}, rest}: Done{Continue{start_java(rest, False{}, WantArray{}, stack, signature)}}
        case 2 _: fail(Next, "reference type")
        case 3 SNil{}: fail(Next, "class name")
        case 3 SCon{Chr{60}, rest}: go(5, rest, "", Nil{}, Nil{}, "", acc, stack, signature)
        case 3 SCon{Chr{46}, rest}: go(3, rest, acc ++ "$", Nil{}, Nil{}, "", "", stack, signature)
        case 3 SCon{Chr{59}, rest}: pop_type(stack, Object{acc, Nil{}}, rest, signature)
        case 3 SCon{head, rest}: go(3, rest, acc ++ char_text(head), Nil{}, Nil{}, "", "", stack, signature)
        case 5 SNil{}: fail(Next, "type arguments")
        case 5 SCon{Chr{62}, rest}:
          match rest:
            case SCon{Chr{59}, tail}: pop_type(stack, Object{binary, M.reverse(SigType, types)}, tail, signature)
            case SCon{Chr{46}, tail}: go(3, tail, binary ++ "$", Nil{}, Nil{}, "", "", stack, signature)
            case _: fail(Next, "class type arguments")
        case 5 SCon{Chr{42}, rest}: go(5, rest, "", Con{Wild{0, None{}}, types}, Nil{}, "", binary, stack, signature)
        case 5 SCon{Chr{43}, rest}: Done{Continue{start_ref(rest, WantWild{1}, Con{WantArg{binary, types}, stack}, signature)}}
        case 5 SCon{Chr{45}, rest}: Done{Continue{start_ref(rest, WantWild{2}, Con{WantArg{binary, types}, stack}, signature)}}
        case 5 SCon{head, tail}: Done{Continue{start_ref(SCon{head, tail}, WantArg{binary, types}, stack, signature)}}
        case 6 SNil{}: fail(Next, "type variable")
        case 6 SCon{Chr{59}, rest}: pop_type(stack, Var{acc}, rest, signature)
        case 6 SCon{head, rest}: go(6, rest, acc ++ char_text(head), Nil{}, Nil{}, "", "", stack, signature)
        case 7 SNil{}: fail(Next, "parameters")
        case 7 SCon{Chr{41}, rest}: Done{Continue{start_java(rest, True{}, WantResult{params, M.reverse(SigType, types)}, stack, signature)}}
        case 7 SCon{head, tail}: Done{Continue{start_java(SCon{head, tail}, False{}, WantParam{types, params}, stack, signature)}}
        case 8 SNil{}:
          match signature:
            case MethodSignature{variables, parameters, result, thrown}:
              Done{Stop{MethodSignature{variables, parameters, result, M.reverse(SigType, types)}}}
        case 8 SCon{Chr{94}, rest}:
          match signature:
            case MethodSignature{+variables, +parameters, +result, thrown}:
              Done{Continue{start_ref(rest, WantThrow{variables, parameters, result, types}, stack, MethodSignature{variables, parameters, result, thrown})}}
        case 8 _: fail(Next, "throws")
        case 9 SNil{}: fail(Next, "type parameter")
        case 9 SCon{Chr{58}, rest}: Done{Continue{start_ref(rest, WantBound{acc, Nil{}, params}, stack, signature)}}
        case 9 SCon{head, rest}: go(9, rest, acc ++ char_text(head), Nil{}, params, "", "", stack, signature)
        case 10 SCon{Chr{58}, SCon{Chr{58}, rest}}: go(10, SCon{Chr{58}, rest}, "", types, params, name, "", stack, signature)
        case 10 SCon{Chr{58}, rest}: Done{Continue{start_ref(rest, WantBound{name, types, params}, stack, signature)}}
        case 10 SCon{Chr{62}, rest}: go(14, rest, "", Nil{}, M.reverse(TypeParam, Con{TypeParam{name, M.reverse(SigType, types)}, params}), "", "", stack, signature)
        case 10 SCon{head, tail}: go(9, SCon{head, tail}, "", Nil{}, Con{TypeParam{name, M.reverse(SigType, types)}, params}, "", "", stack, signature)
        case 10 _: fail(Next, "type parameter")
        case 13 SNil{}: fail(Next, "type parameters")
        case 13 SCon{Chr{62}, rest}: go(14, rest, "", Nil{}, M.reverse(TypeParam, params), "", "", stack, signature)
        case 13 SCon{head, tail}: go(9, SCon{head, tail}, "", Nil{}, params, "", "", stack, signature)
        case 14 SCon{Chr{40}, rest}: go(7, rest, "", Nil{}, params, "", "", stack, signature)
        case 14 _: fail(Next, "method parameters")
        case 15 SCon{Chr{60}, rest}: go(13, rest, "", Nil{}, Nil{}, "", "", stack, signature)
        case 15 SCon{Chr{40}, rest}: go(7, rest, "", Nil{}, Nil{}, "", "", stack, signature)
        case 15 _: fail(Next, "method")
        case _ _: fail(Next, "state")

type Loop is Data:
  Again{value: Work}
  Ready{parsed: Result<&2, &2, String, Next>}

@unsafe def run(fuel: Nat, loop: Loop) -> Result<&2, &2, String, MethodSignature>:
  match fuel loop:
    case 0n _: fail(MethodSignature, "truncated")
    case 1n+p Again{value}: run(p, Ready{once(value)})
    case 1n+p Ready{Fail{error}}: Fail{error}
    case 1n+p Ready{Done{Stop{result}}}: Done{result}
    case 1n+p Ready{Done{Continue{next}}}: run(p, Again{next})

def parse_method(text: String) -> Result<&2, &2, String, MethodSignature>:
  run(8192n, Again{work(15, text, "", Nil{}, Nil{}, "", "", False{}, Nil{}, empty_signature())})

def result_name(value: MethodSignature) -> String:
  match value:
    case MethodSignature{variables, parameters, result, thrown}: type_name(result)
def skip_params(text: String, depth: U32) -> String:
  match text depth:
    case SNil{} _: ""
    case SCon{Chr{62}, rest} 0: rest
    case SCon{Chr{60}, rest} depth: skip_params(rest, (depth + 1 : U32))
    case SCon{Chr{62}, rest} depth: skip_params(rest, (depth - 1 : U32))
    case SCon{head, rest} depth: skip_params(rest, depth)

def after_params(text: String) -> String:
  match text:
    case SCon{Chr{60}, rest}: skip_params(rest, 0)
    case other: other

def take_class(text: String, +depth: U32, +acc: String) -> String:
  match text:
    case SNil{}: acc
    case SCon{Chr{60}, rest}: take_class(rest, (depth + 1 : U32), acc ++ "<")
    case SCon{Chr{62}, rest}: take_class(rest, (depth - 1 : U32), acc ++ ">")
    case SCon{Chr{59}, rest}:
      Bool.pick(String, U32.is_eq(depth, 0), acc ++ ";", take_class(rest, depth, acc ++ ";"))
    case SCon{head, rest}: take_class(rest, depth, acc ++ char_text(head))

def class_superclass_signature(text: String) -> String:
  take_class(after_params(text), 0, "")

