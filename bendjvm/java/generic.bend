import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../classfile/signature.bend as Sig

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
  GenSealVar{name: String, count: Nat}
  GenBuildVar{}
  GenSealWild{label: String, upper: Nat, lower: Nat}
  GenBuildWild{}
  GenSealArray{}
  GenBuildArray{}
  GenTypeArray{refs: +List<U32>}
  GenOwner{binary: String}
  GenLabel{text: String}
type Task is Data:
  Task{vm: M.VM, jobs: +List<Job>, variables: +List<Sig.TypeParam>, acc: +List<U32>}
  AfterObject{split: Split, vm: M.VM, binary: String, label: String, jobs: +List<Job>, variables: +List<Sig.TypeParam>}
  AfterVar{split: Split, vm: M.VM, name: String, jobs: +List<Job>, variables: +List<Sig.TypeParam>}
  AfterWildLower{split: Split, vm: M.VM, label: String, upper: Nat, jobs: +List<Job>, variables: +List<Sig.TypeParam>}
  AfterWildUpper{lower_refs: +List<U32>, split: Split, vm: M.VM, label: String, jobs: +List<Job>, variables: +List<Sig.TypeParam>}
  AfterChildren{parsed: Result<&2, &2, String, TypeRefs>, binary: String, label: String, jobs: +List<Job>, variables: +List<Sig.TypeParam>, acc: +List<U32>}
  BeforeChildren{vm: M.VM, child_jobs: +List<Job>, binary: String, label: String, jobs: +List<Job>, variables: +List<Sig.TypeParam>, acc: +List<U32>}

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

def string_ref_found(+vm: M.VM, +chars: +List<U32>, found: Maybe<&2, U32>) -> Result<&2, &2, String, TypeRef>:
  match found:
    case Some{reference}: Done{TypeRef{vm, reference}}
    case None{}: alloc_ref(H.allocate(vm, H.string_entry(class_id(vm, "java/lang/String"), chars)))

def string_ref(+vm: M.VM, text: String) -> Result<&2, &2, String, TypeRef>:
  +chars = units_from_string(text)
  string_ref_found(vm, chars, H.string_intern(S.heap(vm), chars))

def mirror_found(+vm: M.VM, +target: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, TypeRef>:
  match found:
    case Some{reference}: Done{TypeRef{vm, reference}}
    case None{}: alloc_ref(H.allocate(vm, H.class_mirror_entry(class_id(vm, "java/lang/Class"), target)))

def mirror_missing(+vm: M.VM, name: String, missing: Bool) -> Result<&2, &2, String, TypeRef>:
  match missing:
    case True{}: Fail{"java/lang/NoClassDefFoundError"}
    case False{}:
      +target = class_id(vm, name)
      mirror_found(vm, target, H.class_mirror(S.heap(vm), target))

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

def bound_named(variables: +List<Sig.TypeParam>, +name: String) -> +List<Sig.SigType>:
  match variables:
    case Nil{}: [Sig.Base{"java/lang/Object"}]
    case Con{Sig.TypeParam{param_name, bounds}, rest}:
      Bool.pick(+List<Sig.SigType>, String.eq(param_name, name), bounds_or_object(bounds), bound_named(rest, name))

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

def task(vm: M.VM, jobs: +List<Job>, variables: +List<Sig.TypeParam>, acc: +List<U32>) -> Task:
  Task{vm, jobs, variables, acc}

def enqueue(vm: M.VM, jobs: +List<Job>, variables: +List<Sig.TypeParam>, acc: +List<U32>, parsed: Result<&2, &2, String, TypeRef>) -> Task:
  Task{vm, Con{GenAwait{parsed}, jobs}, variables, acc}


def choose_array(+vm: M.VM, jobs: +List<Job>, variables: +List<Sig.TypeParam>, acc: +List<U32>, element: Sig.SigType, plain: Bool) -> Task:
  match plain:
    case True{}: enqueue(vm, jobs, variables, acc, mirror_ref(vm, "[" ++ array_descriptor(element)))
    case False{}: task(vm, Con{GenEmit{element}, Con{GenSealArray{}, jobs}}, variables, acc)



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

def walk(fuel: Nat, piece: Piece) -> Walked:
  match fuel piece:
    case 0n _: Walked{"", 0n, Nil{}}
    case 1n+p PieceArgs{Nil{}, first}: Walked{"", 0n, Nil{}}
    case 1n++p PieceArgs{Con{head, tail}, first}: walk_cons(walk(p, PieceType{head}), walk(p, PieceArgs{tail, False{}}), first)
    case 1n+p PieceType{Sig.Base{+name}}: Walked{name, 1n, [GenEmit{Sig.Base{name}}]}
    case 1n+p PieceType{Sig.Var{+name}}: Walked{name, 1n, [GenEmit{Sig.Var{name}}]}
    case 1n+p PieceType{Sig.Object{+binary, Nil{}}}: Walked{Sig.display_name(binary), 1n, [GenEmit{Sig.Object{binary, Nil{}}}]}
    case 1n+p PieceType{Sig.Object{+binary, args}}: walk_object(walk(p, PieceArgs{args, True{}}), binary)
    case 1n+p PieceType{Sig.Array{element}}: Walked{"", 1n, [GenEmit{Sig.Array{element}}]}
    case 1n+p PieceType{Sig.Wild{kind, bound}}: Walked{"", 1n, [GenEmit{Sig.Wild{kind, bound}}]}

def children_task(walked: Walked, vm: M.VM, jobs: +List<Job>, variables: +List<Sig.TypeParam>, acc: +List<U32>, +binary: String) -> Task:
  match walked:
    case Walked{label, count, emitted}: BeforeChildren{vm, emitted, binary, label, jobs, variables, acc}


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
    case 1n+p Task{+vm, Con{GenTypeArray{refs}, jobs}, variables, acc}:
      drive(p, enqueue(vm, jobs, variables, acc, type_array(vm, refs)))
    case 1n+p Task{+vm, Con{GenOwner{+binary}, jobs}, variables, acc}:
      +prefix = Sig.owner_prefix(binary)
      drive(p, enqueue(vm, jobs, variables, acc, choose_owner(vm, prefix, String.is_empty(prefix))))
    case 1n+p Task{+vm, Con{GenLabel{text}, jobs}, variables, acc}:
      drive(p, enqueue(vm, jobs, variables, acc, string_ref(vm, text)))
    case 1n+p Task{+vm, Con{GenEmit{Sig.Object{+binary, args}}, jobs}, variables, acc}:
      drive(p, children_task(walk(64n, PieceType{Sig.Object{binary, args}}), vm, jobs, variables, acc, binary))
    case 1n+p Task{vm, Con{GenEmit{Sig.Var{+name}}, jobs}, +variables, acc}:
      +bounds = bound_named(variables, name)
      +count = U32.to_nat(M.length(Sig.SigType, bounds))
      drive(p, task(vm, M.append(Job, emit_jobs(bounds), Con{GenSealVar{name, count}, jobs}), variables, acc))
    case 1n++p BeforeChildren{vm, child_jobs, +binary, +label, +jobs, +variables, +acc}:
      drive(p, AfterChildren{drive(p, task(vm, child_jobs, variables, Nil{})), binary, label, jobs, variables, acc})
    case 1n+p AfterChildren{Fail{error}, binary, label, jobs, variables, acc}: Fail{error}
    case 1n+p AfterChildren{Done{TypeRefs{next, refs}}, binary, label, jobs, variables, acc}:
      drive(p, AfterObject{Split{refs, acc}, next, binary, label, jobs, variables})
    case 1n+p AfterObject{Split{refs, rest}, vm, +binary, label, jobs, variables}:
      drive(p, task(vm, Con{GenTypeArray{refs}, Con{GenOwner{binary}, Con{GenLabel{label}, Con{GenBuildObject{binary}, jobs}}}}, variables, rest))
    case 1n+p Task{+vm, Con{GenBuildObject{binary}, jobs}, variables, Con{label_ref, Con{owner_ref, Con{array_ref, rest}}}}:
      +raw = class_id(vm, binary)
      drive(p, enqueue(vm, jobs, variables, rest, object_missing(vm, "java/lang/reflect/ParameterizedType", [M.Binding{0, M.Slot{1, raw}}, M.Binding{1, M.Slot{3, array_ref}}, M.Binding{2, M.Slot{3, owner_ref}}, M.Binding{3, M.Slot{3, label_ref}}], U32.is_eq(raw, 4294967295))))
    case 1n+p Task{vm, Con{GenSealVar{name, count}, jobs}, variables, acc}:
      drive(p, AfterVar{take_refs(acc, count, Nil{}), vm, name, jobs, variables})
    case 1n+p AfterVar{Split{+refs, rest}, +vm, name, jobs, variables}:
      drive(p, task(vm, Con{GenTypeArray{refs}, Con{GenLabel{name}, Con{GenBuildVar{}, jobs}}}, variables, rest))
    case 1n+p Task{+vm, Con{GenBuildVar{}, jobs}, variables, Con{label_ref, Con{array_ref, rest}}}:
      drive(p, enqueue(vm, jobs, variables, rest, object_ref(vm, "java/lang/reflect/TypeVariable", [M.Binding{0, M.Slot{3, label_ref}}, M.Binding{1, M.Slot{3, array_ref}}])))
    case 1n+p Task{vm, Con{GenSealWild{label, upper, lower}, jobs}, variables, acc}:
      drive(p, AfterWildLower{take_refs(acc, lower, Nil{}), vm, label, upper, jobs, variables})
    case 1n+p AfterWildLower{Split{+lower_refs, mid}, vm, label, upper, jobs, variables}:
      drive(p, AfterWildUpper{lower_refs, take_refs(mid, upper, Nil{}), vm, label, jobs, variables})
    case 1n+p AfterWildUpper{+lower_refs, Split{+upper_refs, rest}, +vm, label, jobs, variables}:
      drive(p, task(vm, Con{GenTypeArray{upper_refs}, Con{GenTypeArray{lower_refs}, Con{GenLabel{label}, Con{GenBuildWild{}, jobs}}}}, variables, rest))
    case 1n+p Task{+vm, Con{GenBuildWild{}, jobs}, variables, Con{label_ref, Con{lower_ref, Con{upper_ref, rest}}}}:
      drive(p, enqueue(vm, jobs, variables, rest, object_ref(vm, "java/lang/reflect/WildcardType", [M.Binding{0, M.Slot{3, upper_ref}}, M.Binding{1, M.Slot{3, lower_ref}}, M.Binding{2, M.Slot{3, label_ref}}])))
    case 1n+p Task{+vm, Con{GenSealArray{}, jobs}, variables, Con{component, rest}}:
      drive(p, Task{vm, Con{GenAwait{string_ref(vm, "array")}, Con{GenBuildArray{}, jobs}}, variables, Con{component, rest}})
    case 1n+p Task{+vm, Con{GenBuildArray{}, jobs}, variables, Con{label_ref, Con{component, rest}}}:
      drive(p, enqueue(vm, jobs, variables, rest, object_ref(vm, "java/lang/reflect/GenericArrayType", [M.Binding{0, M.Slot{3, component}}, M.Binding{1, M.Slot{3, label_ref}}])))
    case _ _: Fail{"VmError.InvalidSignature: generic type"}

def one_ref(parsed: Result<&2, &2, String, TypeRefs>) -> Result<&2, &2, String, TypeRef>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{TypeRefs{vm, Con{reference, rest}}}: Done{TypeRef{vm, reference}}
    case Done{TypeRefs{vm, Nil{}}}: Fail{"VmError.InvalidSignature: missing type"}

def drive_one(+vm: M.VM, value: Sig.SigType, +variables: +List<Sig.TypeParam>) -> Result<&2, &2, String, TypeRef>:
  one_ref(drive(4096n, task(vm, [GenEmit{value}], variables, Nil{})))

def return_parsed(+vm: M.VM, parsed: Result<&2, &2, String, Sig.MethodSignature>) -> Result<&2, &2, String, TypeRef>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{Sig.MethodSignature{+variables, parameters, +result, thrown}}: drive_one(vm, result, variables)

def parameter_parsed(+vm: M.VM, parsed: Result<&2, &2, String, Sig.MethodSignature>) -> Result<&2, &2, String, TypeRefs>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{Sig.MethodSignature{+variables, +parameters, result, thrown}}:
      drive(4096n, task(vm, emit_jobs(parameters), variables, Nil{}))

def thrown_parsed(+vm: M.VM, parsed: Result<&2, &2, String, Sig.MethodSignature>) -> Result<&2, &2, String, TypeRefs>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{Sig.MethodSignature{+variables, parameters, result, +thrown}}:
      drive(4096n, task(vm, emit_jobs(thrown), variables, Nil{}))

def return_ref(+vm: M.VM, text: String) -> Result<&2, &2, String, TypeRef>:
  return_parsed(vm, Sig.parse_method(text))
def field_ref(+vm: M.VM, text: String) -> Result<&2, &2, String, TypeRef>:
  return_ref(vm, "()" ++ text)

def superclass_ref(+vm: M.VM, text: String) -> Result<&2, &2, String, TypeRef>:
  field_ref(vm, Sig.class_superclass_signature(text))


def parameter_refs(+vm: M.VM, text: String) -> Result<&2, &2, String, TypeRefs>:
  parameter_parsed(vm, Sig.parse_method(text))

def thrown_refs(+vm: M.VM, text: String) -> Result<&2, &2, String, TypeRefs>:
  thrown_parsed(vm, Sig.parse_method(text))
