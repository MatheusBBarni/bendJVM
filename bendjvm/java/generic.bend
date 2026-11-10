import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../classfile/signature.bend as Sig

# A generic declaration in a type variable's lookup chain: kind 1 class,
# 2 method, 3 constructor; `id` is the class or method id.
type Scope is Data:
  Scope{kind: U32, id: U32, params: +List<Sig.TypeParam>}

type TypeRef is Data:
  TypeRef{vm: M.VM, reference: U32}

type TypeRefs is Data:
  TypeRefs{vm: M.VM, refs: +List<U32>}

type Split is Data:
  Split{refs: +List<U32>, rest: +List<U32>}

type Job is Data:
  GenEmit{value: Sig.SigType}
  GenAwait{parsed: Result<&2, &2, String, TypeRef>}
  GenSealObject{binary: String, count: Nat, label: String}
  GenBuildObject{binary: String}
  GenSealWild{label: String, upper: Nat, lower: Nat}
  GenBuildWild{}
  GenSealArray{label: String}
  GenBuildArray{}
  GenTypeArray{refs: +List<U32>}
  GenOwner{binary: String}
  GenLabel{text: String}
type Task is Data:
  Task{vm: M.VM, jobs: +List<Job>, scopes: +List<Scope>, acc: +List<U32>}
  AfterObject{split: Split, vm: M.VM, binary: String, label: String, jobs: +List<Job>, scopes: +List<Scope>}
  AfterWildLower{split: Split, vm: M.VM, label: String, upper: Nat, jobs: +List<Job>, scopes: +List<Scope>}
  AfterWildUpper{lower_refs: +List<U32>, split: Split, vm: M.VM, label: String, jobs: +List<Job>, scopes: +List<Scope>}
  AfterChildren{parsed: Result<&2, &2, String, TypeRefs>, binary: String, label: String, jobs: +List<Job>, scopes: +List<Scope>, acc: +List<U32>}
  BeforeChildren{vm: M.VM, child_jobs: +List<Job>, binary: String, label: String, jobs: +List<Job>, scopes: +List<Scope>, acc: +List<U32>}

def class_id(+vm: M.VM, name: String) -> U32:
  H.named_class(S.classes(vm), S.symbols(vm), name)

def units_from_char(+u: U32, +rest: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_le(u, 65535), Con{u, rest}, Con{U32.add(55296, U32.shrn(U32.sub(u, 65536), 10n)), Con{U32.add(56320, U32.and(U32.sub(u, 65536), 1023)), rest}})

def units_from_list(values: +List<Char>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}: units_from_char(Char.to_u32(head), units_from_list(tail))

def units_from_string(text: String) -> +List<U32>:
  units_from_list(String.to_list(text))

def ref_slots(refs: +List<U32>) -> +List<M.Slot>:
  match refs:
    case Nil{}: Nil{}
    case Con{reference, rest}: Con{M.Slot{3, reference}, ref_slots(rest)}

def alloc_ref(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, TypeRef>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{vm, reference}}: Done{TypeRef{vm, reference}}

def string_ref(+vm: M.VM, text: String) -> Result<&2, &2, String, TypeRef>:
  alloc_ref(H.literal_string(vm, units_from_string(text)))

def mirror_missing(+vm: M.VM, name: String, missing: Bool) -> Result<&2, &2, String, TypeRef>:
  match missing:
    case True{}: Fail{"java/lang/NoClassDefFoundError"}
    case False{}:
      +target = class_id(vm, name)
      alloc_ref(H.class_mirror(vm, target))

def mirror_ref(+vm: M.VM, +name: String) -> Result<&2, &2, String, TypeRef>:
  mirror_missing(vm, name, U32.is_eq(class_id(vm, name), 4294967295))

def type_array(+vm: M.VM, +refs: +List<U32>) -> Result<&2, &2, String, TypeRef>:
  alloc_ref(H.allocate(vm, H.reference_array_entry(class_id(vm, "[Ljava/lang/reflect/Type;"), class_id(vm, "java/lang/reflect/Type"), ref_slots(refs))))

def object_missing(+vm: M.VM, class_name: String, fields: +List<M.Binding>, missing: Bool) -> Result<&2, &2, String, TypeRef>:
  match missing:
    case True{}: Fail{"java/lang/NoClassDefFoundError"}
    case False{}: alloc_ref(H.allocate(vm, H.object_entry(class_id(vm, class_name), fields)))

def object_ref(+vm: M.VM, +class_name: String, fields: +List<M.Binding>) -> Result<&2, &2, String, TypeRef>:
  object_missing(vm, class_name, fields, U32.is_eq(class_id(vm, class_name), 4294967295))

def emit_jobs(values: +List<Sig.SigType>) -> +List<Job>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}: Con{GenEmit{head}, emit_jobs(tail)}

def bounds_or_object(bounds: +List<Sig.SigType>) -> +List<Sig.SigType>:
  match bounds:
    case Nil{}: [Sig.Base{"java/lang/Object"}]
    case found: found

def param_named(params: +List<Sig.TypeParam>, +name: String) -> Bool:
  match params:
    case Nil{}: False{}
    case Con{Sig.TypeParam{param_name, bounds}, rest}: String.eq(param_name, name) || param_named(rest, name)

# The innermost declaration (method, class, enclosing class...) that declares `name`.
def scope_of(scopes: +List<Scope>, +name: String) -> Maybe<&2, Scope>:
  match scopes:
    case Nil{}: None{}
    case Con{Scope{kind, id, params}, rest}:
      Bool.pick(Maybe<&2, Scope>, param_named(params, name), Some{Scope{kind, id, Nil{}}}, scope_of(rest, name))

def plain_component(value: Sig.SigType) -> Bool:
  match value:
    case Sig.Base{name}: True{}
    case Sig.Object{binary, args}:
      match args:
        case Nil{}: True{}
        case _: False{}
    case Sig.Array{element}: plain_component(element)
    case _: False{}

def array_descriptor(value: Sig.SigType) -> String:
  match value:
    case Sig.Base{name}:
      match name:
        case "int": "I"
        case "boolean": "Z"
        case "byte": "B"
        case "short": "S"
        case "char": "C"
        case "float": "F"
        case "long": "J"
        case "double": "D"
        case "void": "V"
        case other: "L" ++ other ++ ";"
    case Sig.Object{binary, args}: "L" ++ binary ++ ";"
    case Sig.Array{element}: "[" ++ array_descriptor(element)
    case _: "Ljava/lang/Object;"

def wild_upper(kind: U32, bound: Maybe<&2, Sig.SigType>) -> +List<Sig.SigType>:
  match kind bound:
    case 1 Some{inner}: [inner]
    case _ _: [Sig.Base{"java/lang/Object"}]

def wild_lower(kind: U32, bound: Maybe<&2, Sig.SigType>) -> +List<Sig.SigType>:
  match kind bound:
    case 2 Some{inner}: [inner]
    case _ _: Nil{}

def take_refs(xs: +List<U32>, count: Nat, out: +List<U32>) -> Split:
  match xs count:
    case leftover 0n: Split{M.reverse(U32, out), leftover}
    case Con{head, more} 1n+p: take_refs(more, p, Con{head, out})
    case _ _: Split{Nil{}, Nil{}}

def task(vm: M.VM, jobs: +List<Job>, scopes: +List<Scope>, acc: +List<U32>) -> Task:
  Task{vm, jobs, scopes, acc}

def enqueue(vm: M.VM, jobs: +List<Job>, scopes: +List<Scope>, acc: +List<U32>, parsed: Result<&2, &2, String, TypeRef>) -> Task:
  Task{vm, Con{GenAwait{parsed}, jobs}, scopes, acc}


@unsafe def choose_array(+vm: M.VM, jobs: +List<Job>, scopes: +List<Scope>, acc: +List<U32>, +element: Sig.SigType, plain: Bool) -> Task:
  match plain:
    case True{}: enqueue(vm, jobs, scopes, acc, mirror_ref(vm, "[" ++ array_descriptor(element)))
    case False{}: task(vm, Con{GenEmit{element}, Con{GenSealArray{type_label(64n, element) ++ "[]"}, jobs}}, scopes, acc)



def choose_owner(vm: M.VM, prefix: String, empty: Bool) -> Result<&2, &2, String, TypeRef>:
  match empty:
    case True{}: Done{TypeRef{vm, 0}}
    case False{}: mirror_ref(vm, prefix)
type Piece is Data:
  PieceType{value: Sig.SigType}
  PieceArgs{values: +List<Sig.SigType>, first: Bool}

type Walked is Data:
  Walked{label: String, count: Nat, jobs: +List<Job>}

def walk_cons(head: Walked, rest: Walked, first: Bool) -> Walked:
  match head rest:
    case Walked{label, count, jobs} Walked{rest_label, rest_count, rest_jobs}:
      Walked{Bool.pick(String, first, "", ", ") ++ label ++ rest_label, (1n + rest_count : Nat), M.append(Job, jobs, rest_jobs)}

def walk_object(inner: Walked, +binary: String) -> Walked:
  match inner:
    case Walked{label, count, jobs}:
      Walked{Sig.display_name(binary) ++ "<" ++ label ++ ">", count, jobs}

def walked_label(walked: Walked) -> String:
  match walked:
    case Walked{label, count, jobs}: label

# The JDK getTypeName text of a signature type.
@unsafe def type_label(fuel: Nat, value: Sig.SigType) -> String:
  walked_label(walk(fuel, PieceType{value}))

@unsafe def wild_label(fuel: Nat, kind: U32, bound: Maybe<&2, Sig.SigType>) -> String:
  match kind bound:
    case 1 Some{inner}: "? extends " ++ type_label(fuel, inner)
    case 2 Some{inner}: "? super " ++ type_label(fuel, inner)
    case _ _: "?"

@unsafe def walk(fuel: Nat, piece: Piece) -> Walked:
  match fuel piece:
    case 0n _: Walked{"", 0n, Nil{}}
    case 1n+p PieceArgs{Nil{}, first}: Walked{"", 0n, Nil{}}
    case 1n++p PieceArgs{Con{head, tail}, first}: walk_cons(walk(p, PieceType{head}), walk(p, PieceArgs{tail, False{}}), first)
    case 1n+p PieceType{Sig.Base{+name}}: Walked{Sig.display_name(name), 1n, [GenEmit{Sig.Base{name}}]}
    case 1n+p PieceType{Sig.Var{+name}}: Walked{name, 1n, [GenEmit{Sig.Var{name}}]}
    case 1n+p PieceType{Sig.Object{+binary, Nil{}}}: Walked{Sig.display_name(binary), 1n, [GenEmit{Sig.Object{binary, Nil{}}}]}
    # A parameterized argument is one child: it becomes its own ParameterizedType.
    case 1n+p PieceType{Sig.Object{+binary, +args}}: Walked{walked_label(walk_object(walk(p, PieceArgs{args, True{}}), binary)), 1n, [GenEmit{Sig.Object{binary, args}}]}
    case 1n+p PieceType{Sig.Array{+element}}: Walked{type_label(p, element) ++ "[]", 1n, [GenEmit{Sig.Array{element}}]}
    case 1n+p PieceType{Sig.Wild{+kind, +bound}}: Walked{wild_label(p, kind, bound), 1n, [GenEmit{Sig.Wild{kind, bound}}]}

def children_task(walked: Walked, vm: M.VM, jobs: +List<Job>, scopes: +List<Scope>, acc: +List<U32>, +binary: String) -> Task:
  match walked:
    case Walked{label, count, emitted}: BeforeChildren{vm, emitted, binary, label, jobs, scopes, acc}


@unsafe def drive(fuel: Nat, value: Task) -> Result<&2, &2, String, TypeRefs>:
  match fuel value:
    case 0n _: Fail{"VmError.InvalidSignature: truncated generic type"}
    case 1n+p Task{vm, Nil{}, variables, acc}: Done{TypeRefs{vm, M.reverse(U32, acc)}}
    case 1n+p Task{vm, Con{GenAwait{Fail{error}}, jobs}, variables, acc}: Fail{error}
    case 1n+p Task{vm, Con{GenAwait{Done{TypeRef{next, reference}}}, jobs}, variables, acc}:
      drive(p, task(next, jobs, variables, Con{reference, acc}))
    case 1n+p Task{vm, Con{GenEmit{Sig.Base{name}}, jobs}, variables, acc}:
      drive(p, enqueue(vm, jobs, variables, acc, mirror_ref(vm, name)))
    case 1n+p Task{+vm, Con{GenEmit{Sig.Object{binary, Nil{}}}, jobs}, variables, acc}:
      drive(p, enqueue(vm, jobs, variables, acc, mirror_ref(vm, binary)))
    case 1n+p Task{+vm, Con{GenEmit{Sig.Array{+element}}, jobs}, variables, acc}:
      drive(p, choose_array(vm, jobs, variables, acc, element, plain_component(element)))
    case 1n+p Task{vm, Con{GenEmit{Sig.Wild{+kind, +bound}}, jobs}, variables, acc}:
      +upper = wild_upper(kind, bound)
      +lower = wild_lower(kind, bound)
      drive(p, task(vm, M.append(Job, emit_jobs(upper), M.append(Job, emit_jobs(lower), Con{GenSealWild{wild_label(64n, kind, bound), U32.to_nat(M.length(Sig.SigType, upper)), U32.to_nat(M.length(Sig.SigType, lower))}, jobs})), variables, acc))
    case 1n+p Task{+vm, Con{GenTypeArray{refs}, jobs}, variables, acc}:
      drive(p, enqueue(vm, jobs, variables, acc, type_array(vm, refs)))
    case 1n+p Task{+vm, Con{GenOwner{+binary}, jobs}, variables, acc}:
      +prefix = Sig.owner_prefix(binary)
      drive(p, enqueue(vm, jobs, variables, acc, choose_owner(vm, prefix, String.is_empty(prefix))))
    case 1n+p Task{+vm, Con{GenLabel{text}, jobs}, variables, acc}:
      drive(p, enqueue(vm, jobs, variables, acc, string_ref(vm, text)))
    case 1n+p Task{+vm, Con{GenEmit{Sig.Object{+binary, args}}, jobs}, variables, acc}:
      drive(p, children_task(walk_object(walk(64n, PieceArgs{args, True{}}), binary), vm, jobs, variables, acc, binary))
    case 1n+p Task{+vm, Con{GenEmit{Sig.Var{+name}}, jobs}, +variables, acc}:
      drive(p, enqueue(vm, jobs, variables, acc, type_variable_ref(vm, name, scope_of(variables, name))))
    case 1n++p BeforeChildren{vm, child_jobs, +binary, +label, +jobs, +variables, +acc}:
      drive(p, AfterChildren{drive(p, task(vm, child_jobs, variables, Nil{})), binary, label, jobs, variables, acc})
    case 1n+p AfterChildren{Fail{error}, binary, label, jobs, variables, acc}: Fail{error}
    case 1n+p AfterChildren{Done{TypeRefs{next, refs}}, binary, label, jobs, variables, acc}:
      drive(p, AfterObject{Split{refs, acc}, next, binary, label, jobs, variables})
    case 1n+p AfterObject{Split{refs, rest}, vm, +binary, label, jobs, variables}:
      drive(p, task(vm, Con{GenTypeArray{refs}, Con{GenOwner{binary}, Con{GenLabel{label}, Con{GenBuildObject{binary}, jobs}}}}, variables, rest))
    case 1n+p Task{+vm, Con{GenBuildObject{binary}, jobs}, variables, Con{label_ref, Con{owner_ref, Con{array_ref, rest}}}}:
      +raw = class_id(vm, binary)
      drive(p, enqueue(vm, jobs, variables, rest, object_missing(vm, "sun/reflect/generics/reflectiveObjects/ParameterizedTypeImpl", [M.Binding{0, M.Slot{1, raw}}, M.Binding{1, M.Slot{3, array_ref}}, M.Binding{2, M.Slot{3, owner_ref}}, M.Binding{3, M.Slot{3, label_ref}}], U32.is_eq(raw, 4294967295))))
    case 1n+p Task{vm, Con{GenSealWild{label, upper, lower}, jobs}, variables, acc}:
      drive(p, AfterWildLower{take_refs(acc, lower, Nil{}), vm, label, upper, jobs, variables})
    case 1n+p AfterWildLower{Split{+lower_refs, mid}, vm, label, upper, jobs, variables}:
      drive(p, AfterWildUpper{lower_refs, take_refs(mid, upper, Nil{}), vm, label, jobs, variables})
    case 1n+p AfterWildUpper{+lower_refs, Split{+upper_refs, rest}, +vm, label, jobs, variables}:
      drive(p, task(vm, Con{GenTypeArray{upper_refs}, Con{GenTypeArray{lower_refs}, Con{GenLabel{label}, Con{GenBuildWild{}, jobs}}}}, variables, rest))
    case 1n+p Task{+vm, Con{GenBuildWild{}, jobs}, variables, Con{label_ref, Con{lower_ref, Con{upper_ref, rest}}}}:
      drive(p, enqueue(vm, jobs, variables, rest, object_ref(vm, "sun/reflect/generics/reflectiveObjects/WildcardTypeImpl", [M.Binding{0, M.Slot{3, upper_ref}}, M.Binding{1, M.Slot{3, lower_ref}}, M.Binding{2, M.Slot{3, label_ref}}])))
    case 1n+p Task{+vm, Con{GenSealArray{label}, jobs}, variables, Con{component, rest}}:
      drive(p, Task{vm, Con{GenAwait{string_ref(vm, label)}, Con{GenBuildArray{}, jobs}}, variables, Con{component, rest}})
    case 1n+p Task{+vm, Con{GenBuildArray{}, jobs}, variables, Con{label_ref, Con{component, rest}}}:
      drive(p, enqueue(vm, jobs, variables, rest, object_ref(vm, "sun/reflect/generics/reflectiveObjects/GenericArrayTypeImpl", [M.Binding{0, M.Slot{3, component}}, M.Binding{1, M.Slot{3, label_ref}}])))
    case _ _: Fail{"VmError.InvalidSignature: generic type"}

def one_ref(parsed: Result<&2, &2, String, TypeRefs>) -> Result<&2, &2, String, TypeRef>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{TypeRefs{vm, Con{reference, rest}}}: Done{TypeRef{vm, reference}}
    case Done{TypeRefs{vm, Nil{}}}: Fail{"VmError.InvalidSignature: missing type"}

def drive_one(+vm: M.VM, +value: Sig.SigType, +scopes: +List<Scope>) -> Result<&2, &2, String, TypeRef>:
  one_ref(drive(4096n, task(vm, [GenEmit{value}], scopes, Nil{})))

def drive_all(+vm: M.VM, +values: +List<Sig.SigType>, +scopes: +List<Scope>) -> Result<&2, &2, String, TypeRefs>:
  drive(4096n, task(vm, emit_jobs(values), scopes, Nil{}))

# A TypeVariableImpl names its declaration; bounds are computed on demand.
def type_variable_object(parsed: Result<&2, &2, String, TypeRef>, +kind: U32, +id: U32) -> Result<&2, &2, String, TypeRef>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{TypeRef{+vm, label}}: object_ref(vm, "sun/reflect/generics/reflectiveObjects/TypeVariableImpl", [M.Binding{0, M.Slot{3, label}}, M.Binding{1, M.Slot{1, kind}}, M.Binding{2, M.Slot{1, id}}])

def type_variable_ref(+vm: M.VM, +name: String, +found: Maybe<&2, Scope>) -> Result<&2, &2, String, TypeRef>:
  match found:
    case None{}: Fail{"java/lang/TypeNotPresentException: Type variable " ++ name ++ " not found"}
    case Some{Scope{kind, id, params}}: type_variable_object(string_ref(vm, name), kind, id)

@unsafe def declaration_variables(+vm: M.VM, +params: +List<Sig.TypeParam>, +kind: U32, +id: U32, +acc: +List<U32>) -> Result<&2, &2, String, TypeRefs>:
  match params:
    case Nil{}: Done{TypeRefs{vm, M.reverse(U32, acc)}}
    case Con{Sig.TypeParam{name, bounds}, rest}: declaration_next(type_variable_object(string_ref(vm, name), kind, id), rest, kind, id, acc)

@unsafe def declaration_next(made: Result<&2, &2, String, TypeRef>, +params: +List<Sig.TypeParam>, +kind: U32, +id: U32, +acc: +List<U32>) -> Result<&2, &2, String, TypeRefs>:
  match made:
    case Fail{error}: Fail{error}
    case Done{TypeRef{vm, reference}}: declaration_variables(vm, params, kind, id, Con{reference, acc})

# The TypeVariable objects a declaration introduces, in declaration order.
def type_parameters(+vm: M.VM, +params: +List<Sig.TypeParam>, +kind: U32, +id: U32) -> Result<&2, &2, String, TypeRefs>:
  declaration_variables(vm, params, kind, id, Nil{})

def param_bounds(+params: +List<Sig.TypeParam>, +name: String) -> +List<Sig.SigType>:
  match params:
    case Nil{}: [Sig.Base{"java/lang/Object"}]
    case Con{Sig.TypeParam{param_name, bounds}, rest}:
      Bool.pick(+List<Sig.SigType>, String.eq(param_name, name), bounds_or_object(bounds), param_bounds(rest, name))

# TypeVariable.getBounds: the declared bounds (Object when none), resolved in
# the declaration's own scope chain.
def bounds_refs(+vm: M.VM, +params: +List<Sig.TypeParam>, +name: String, +scopes: +List<Scope>) -> Result<&2, &2, String, TypeRefs>:
  drive_all(vm, param_bounds(params, name), scopes)

def signature_variables(parsed: Result<&2, &2, String, Sig.MethodSignature>) -> +List<Sig.TypeParam>:
  match parsed:
    case Fail{error}: Nil{}
    case Done{Sig.MethodSignature{variables, parameters, result, thrown}}: variables

@unsafe def class_params_text(+text: String) -> String:
  match text:
    case SCon{Chr{60}, rest}: "<" ++ params_body(rest, 0)
    case _: ""

@unsafe def params_body(+text: String, +depth: U32) -> String:
  match text depth:
    case SNil{} _: ""
    case SCon{Chr{62}, rest} 0: ">"
    case SCon{Chr{60}, rest} depth: "<" ++ params_body(rest, (depth + 1 : U32))
    case SCon{Chr{62}, rest} depth: ">" ++ params_body(rest, (depth - 1 : U32))
    case SCon{head, rest} depth: Sig.char_text(head) ++ params_body(rest, depth)

# A class signature "<T..>Super;I1;I2;" read as the method signature
# "<T..>(Super;I1;I2;)V": its type parameters, then superclass and interfaces.
def class_as_method(+text: String) -> String:
  class_params_text(text) ++ "(" ++ Sig.after_params(text) ++ ")V"

def class_variables(+text: String) -> +List<Sig.TypeParam>:
  signature_variables(Sig.parse_method(class_as_method(text)))

def method_variables(+text: String) -> +List<Sig.TypeParam>:
  signature_variables(Sig.parse_method(text))

def result_parsed(+vm: M.VM, parsed: Result<&2, &2, String, Sig.MethodSignature>, +kind: U32, +id: U32, +outer: +List<Scope>) -> Result<&2, &2, String, TypeRef>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{Sig.MethodSignature{+variables, parameters, +result, thrown}}: drive_one(vm, result, Con{Scope{kind, id, variables}, outer})

def parameters_parsed(+vm: M.VM, parsed: Result<&2, &2, String, Sig.MethodSignature>, +kind: U32, +id: U32, +outer: +List<Scope>) -> Result<&2, &2, String, TypeRefs>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{Sig.MethodSignature{+variables, +parameters, result, thrown}}: drive_all(vm, parameters, Con{Scope{kind, id, variables}, outer})

def thrown_parsed(+vm: M.VM, parsed: Result<&2, &2, String, Sig.MethodSignature>, +kind: U32, +id: U32, +outer: +List<Scope>) -> Result<&2, &2, String, TypeRefs>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{Sig.MethodSignature{+variables, parameters, result, +thrown}}: drive_all(vm, thrown, Con{Scope{kind, id, variables}, outer})

def drop_first(+values: +List<Sig.SigType>) -> +List<Sig.SigType>:
  match values:
    case Nil{}: Nil{}
    case Con{head, rest}: rest

def first_type(+values: +List<Sig.SigType>) -> +List<Sig.SigType>:
  match values:
    case Nil{}: Nil{}
    case Con{head, rest}: [head]

def class_parsed(+vm: M.VM, parsed: Result<&2, &2, String, Sig.MethodSignature>, +interfaces: Bool, +outer: +List<Scope>) -> Result<&2, &2, String, TypeRefs>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{Sig.MethodSignature{variables, +parameters, result, thrown}}:
      drive_all(vm, Bool.pick(+List<Sig.SigType>, interfaces, drop_first(parameters), first_type(parameters)), outer)

# Generic return type of a method (kind 2) or constructor (kind 3) `id`; `outer`
# is the declaring class's scope chain.
def return_ref(+vm: M.VM, +text: String, +kind: U32, +id: U32, +outer: +List<Scope>) -> Result<&2, &2, String, TypeRef>:
  result_parsed(vm, Sig.parse_method(text), kind, id, outer)

def parameter_refs(+vm: M.VM, +text: String, +kind: U32, +id: U32, +outer: +List<Scope>) -> Result<&2, &2, String, TypeRefs>:
  parameters_parsed(vm, Sig.parse_method(text), kind, id, outer)

def thrown_refs(+vm: M.VM, +text: String, +kind: U32, +id: U32, +outer: +List<Scope>) -> Result<&2, &2, String, TypeRefs>:
  thrown_parsed(vm, Sig.parse_method(text), kind, id, outer)

# A field signature resolves in the declaring class's scope chain.
def field_ref(+vm: M.VM, +text: String, +scopes: +List<Scope>) -> Result<&2, &2, String, TypeRef>:
  return_ref(vm, "()" ++ text, 0, 0, scopes)

def superclass_ref(+vm: M.VM, +text: String, +scopes: +List<Scope>) -> Result<&2, &2, String, TypeRef>:
  one_ref(class_parsed(vm, Sig.parse_method(class_as_method(text)), False{}, scopes))

def interface_refs(+vm: M.VM, +text: String, +scopes: +List<Scope>) -> Result<&2, &2, String, TypeRefs>:
  class_parsed(vm, Sig.parse_method(class_as_method(text)), True{}, scopes)

@unsafe def plain_arrays(+values: +List<Sig.SigType>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: M.append(String, type_arrays(value), plain_arrays(rest))

@unsafe def wild_arrays(+bound: Maybe<&2, Sig.SigType>) -> +List<String>:
  match bound:
    case None{}: Nil{}
    case Some{inner}: type_arrays(inner)

# Array classes a signature names as plain Class objects; the caller creates
# them before driving, because array classes are made on first use.
@unsafe def type_arrays(+value: Sig.SigType) -> +List<String>:
  match value:
    case Sig.Array{+element}: Bool.pick(+List<String>, plain_component(element), ["[" ++ array_descriptor(element)], type_arrays(element))
    case Sig.Object{binary, args}: plain_arrays(args)
    case Sig.Wild{kind, bound}: wild_arrays(bound)
    case _: Nil{}

def params_arrays(+params: +List<Sig.TypeParam>) -> +List<String>:
  match params:
    case Nil{}: Nil{}
    case Con{Sig.TypeParam{name, bounds}, rest}: M.append(String, plain_arrays(bounds), params_arrays(rest))

def signature_arrays(parsed: Result<&2, &2, String, Sig.MethodSignature>) -> +List<String>:
  match parsed:
    case Fail{error}: Nil{}
    case Done{Sig.MethodSignature{variables, parameters, result, thrown}}:
      M.append(String, params_arrays(variables), M.append(String, plain_arrays(parameters), M.append(String, type_arrays(result), plain_arrays(thrown))))

def method_arrays(+text: String) -> +List<String>:
  signature_arrays(Sig.parse_method(text))

def class_arrays(+text: String) -> +List<String>:
  signature_arrays(Sig.parse_method(class_as_method(text)))
