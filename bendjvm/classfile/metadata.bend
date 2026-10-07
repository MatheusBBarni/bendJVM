import Base
import ../model.bend as M
import ./annotation.bend as AN
import ./reader.bend as R
import ./constant_pool.bend as CP
import ./descriptor.bend as D

# Structured metadata is validated at parse time and cached beside raw attributes.
type Bound is Data:
  Bound{first: U32, count: U32}
type Context is Data:
  Context{site: U32, arity: U32, prefix: U32, interfaces: U32, hasParent: Bool, isStatic: Bool, bounds: +List<Bound>, codeLength: U32, locals: U32, handlers: U32}

def signature_text(attributes: +List<M.Attribute>, +pool: +List<M.Constant>) -> Result<&2, &2, String, String>:
  match attributes:
    case Nil{}: Done{""}
    case Con{M.ValidatedAnnotations{metadata}, tail}: signature_text(tail, pool)
    case Con{M.Attribute{+name, bytes}, tail}:
      match bytes:
        case Con{a, Con{b, Nil{}}}:
          Bool.pick(Result<&2, &2, String, String>, String.eq(name, "Signature"), CP.utf(pool, (a * 256 + b : U32)), signature_text(tail, pool))
        case _: signature_text(tail, pool)

# Only outer colons and completed reference types define formal-bound slots.
# The first empty class-bound slot is not a legal annotation target.
def bounds_select(is_class_bound: Bool, class_bound: Unit -> +List<Bound>, nested_bound: Unit -> +List<Bound>) -> +List<Bound>:
  match is_class_bound:
    case True{}: class_bound(Unit{})
    case False{}: nested_bound(Unit{})

@unsafe def bounds_go(text: String, mode: U32, +depth: U32, +first: U32, +count: U32, +acc: +List<Bound>) -> +List<Bound>:
  match text mode:
    case SNil{} _: M.reverse(Bound, acc)
    case SCon{Chr{62}, tail} 0: M.reverse(Bound, acc)
    case SCon{Chr{58}, tail} 0: bounds_go(tail, 1, 0, 0, 0, acc)
    case SCon{head, tail} 0: bounds_go(tail, 0, depth, first, count, acc)
    case SCon{Chr{58}, tail} 1: bounds_go(tail, 2, 0, 1, 0, acc)
    case SCon{head, tail} 1: bounds_go(SCon{head, tail}, 2, 0, 0, 0, acc)
    case SCon{Chr{60}, tail} 2: bounds_go(tail, 2, (depth + 1 : U32), first, count, acc)
    case SCon{Chr{62}, tail} 2: bounds_go(tail, 2, (depth - 1 : U32), first, count, acc)
    case SCon{Chr{59}, +tail} 2:
      bounds_select(U32.is_eq(depth, 0),
        unit => bounds_go(tail, 3, 0, first, (count + 1 : U32), acc),
        unit => bounds_go(tail, 2, depth, first, count, acc))
    case SCon{head, tail} 2: bounds_go(tail, 2, depth, first, count, acc)
    case SCon{Chr{58}, tail} 3: bounds_go(tail, 2, 0, first, count, acc)
    case SCon{head, tail} 3: bounds_go(SCon{head, tail}, 0, 0, 0, 0, Con{Bound{first, count}, acc})
    case _ _: M.reverse(Bound, acc)

def bounds(text: String) -> +List<Bound>:
  match text:
    case SCon{Chr{60}, tail}: bounds_go(tail, 0, 0, 0, 0, Nil{})
    case _: Nil{}

def bound_valid(values: +List<Bound>, index: U32, +bound: U32) -> Bool:
  match values index:
    case Nil{} _: False{}
    case Con{Bound{+first, count}, tail} 0: Bool.and(U32.is_le(first, bound), U32.is_lt(bound, (first + count : U32)))
    case Con{head, tail} _: bound_valid(tail, (index - 1 : U32), bound)

def local_ranges(values: +List<U32>, +length: U32, +locals: U32) -> Result<&2, &2, String, Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case Con{+start, Con{+size, Con{index, tail}}}:
      do Result<&2, &2, String, Unit>:
        AN.require_annotation(Bool.and(U32.is_le(start, length), U32.is_le(size, (length - start : U32))), "local-variable annotation range out of bounds")
        AN.require_annotation(U32.is_lt(index, locals), "local-variable annotation slot out of bounds")
        local_ranges(tail, length, locals)
    case _: AN.invalid_annotation("invalid local-variable target")

def target_case(+target: U32, info: +List<U32>, +site: U32, +arity: U32, +interfaces: U32, +hasParent: Bool, +isStatic: Bool, +variables: +List<Bound>, +length: U32, +locals: U32, +handlers: U32, throws: U32) -> Result<&2, &2, String, Unit>:
  match target info:
    case 0 Con{index, Nil{}}: AN.require_annotation(Bool.and(U32.is_eq(site, 0), U32.is_lt(index, M.length(Bound, variables))), "class type-parameter target out of bounds")
    case 1 Con{index, Nil{}}: AN.require_annotation(Bool.and(U32.is_eq(site, 2), U32.is_lt(index, M.length(Bound, variables))), "method type-parameter target out of bounds")
    case 16 Con{+index, Nil{}}: AN.require_annotation(Bool.and(U32.is_eq(site, 0), Bool.or(Bool.and(U32.is_eq(index, 65535), hasParent), U32.is_lt(index, interfaces))), "supertype target out of bounds")
    case 17 Con{index, Con{bound, Nil{}}}: AN.require_annotation(Bool.and(U32.is_eq(site, 0), bound_valid(variables, index, bound)), "class bound target out of bounds")
    case 18 Con{index, Con{bound, Nil{}}}: AN.require_annotation(Bool.and(U32.is_eq(site, 2), bound_valid(variables, index, bound)), "method bound target out of bounds")
    case 19 Nil{}: AN.require_annotation(U32.is_eq(site, 1), "field type annotation on wrong owner")
    case 20 Nil{}: AN.require_annotation(U32.is_eq(site, 2), "return type annotation on wrong owner")
    case 21 Nil{}: AN.require_annotation(Bool.and(U32.is_eq(site, 2), Bool.not(isStatic)), "receiver type annotation on wrong owner")
    case 22 Con{index, Nil{}}: AN.require_annotation(Bool.and(U32.is_eq(site, 2), U32.is_lt(index, arity)), "formal-parameter target out of bounds")
    case 23 Con{index, Nil{}}: AN.require_annotation(Bool.and(U32.is_eq(site, 2), U32.is_lt(index, throws)), "throws target out of bounds")
    case 64 Con{count, tail}:
      do Result<&2, &2, String, Unit>:
        AN.require_annotation(U32.is_eq(site, 3), "local-variable target on wrong owner")
        local_ranges(tail, length, locals)
    case 65 Con{count, tail}:
      do Result<&2, &2, String, Unit>:
        AN.require_annotation(U32.is_eq(site, 3), "resource-variable target on wrong owner")
        local_ranges(tail, length, locals)
    case 66 Con{index, Nil{}}: AN.require_annotation(Bool.and(U32.is_eq(site, 3), U32.is_lt(index, handlers)), "catch target out of bounds")
    case _ Con{offset, tail}: AN.require_annotation(Bool.and(U32.is_eq(site, 3), Bool.and(U32.is_le(67, target), Bool.and(U32.is_le(target, 75), U32.is_lt(offset, length)))), "instruction target out of bounds")
    case _ _: AN.invalid_annotation("type annotation target on wrong owner")

def target_check(target: U32, info: +List<U32>, context: Context, throws: U32) -> Result<&2, &2, String, Unit>:
  match context:
    case Context{+site, +arity, prefix, +interfaces, +hasParent, +isStatic, +variables, +length, +locals, +handlers}:
      target_case(target, info, site, arity, interfaces, hasParent, isStatic, variables, length, locals, handlers, throws)

def types_check(values: +List<M.TypeAnnotation>, +context: Context, +throws: U32) -> Result<&2, &2, String, Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case Con{M.TypeAnnotation{target, info, path, annotation}, tail}:
      do Result<&2, &2, String, Unit>:
        target_check(target, info, context, throws)
        types_check(tail, context, throws)

def pad_parameters(count: Nat, values: +List<+List<M.Annotation>>) -> +List<+List<M.Annotation>>:
  match count:
    case 0n: values
    case 1n+p: Con{Nil{}, pad_parameters(p, values)}

def align_parameters(+values: +List<+List<M.Annotation>>, +present: Bool, +arity: U32, prefix: U32) -> Result<&2, &2, String, +List<+List<M.Annotation>>>:
  +count = M.length(+List<M.Annotation>, values)
  do Result<&2, &2, String, +List<+List<M.Annotation>>>:
    AN.require_annotation(Bool.or(Bool.not(present), Bool.or(U32.is_eq(count, arity), U32.is_eq((count + prefix : U32), arity))), "parameter annotation count does not match descriptor")
    AN.require_annotation(U32.is_le(count, arity), "parameter annotation count exceeds descriptor")
    return pad_parameters(U32.to_nat((arity - count : U32)), values)

def normalize(metadata: M.AnnotationMetadata, +context: Context) -> Result<&2, &2, String, M.AnnotationMetadata>:
  match metadata context:
    case M.AnnotationMetadata{+flags, +exceptions, annotations, parameters, +types, defaultValue, ia, ip, +it} Context{site, +arity, +prefix, interfaces, hasParent, isStatic, variables, codeLength, locals, handlers}:
      do Result<&2, &2, String, M.AnnotationMetadata>:
        types_check(types, context, M.length(U32, exceptions))
        types_check(it, context, M.length(U32, exceptions))
        aligned : +List<+List<M.Annotation>> <- align_parameters(parameters, U32.is_ne(U32.and(flags, 4), 0), arity, prefix)
        invisible : +List<+List<M.Annotation>> <- align_parameters(ip, U32.is_ne(U32.and(flags, 8), 0), arity, prefix)
        return M.AnnotationMetadata{flags, exceptions, annotations, aligned, types, defaultValue, ia, invisible, it}

def placements(attributes: +List<M.Attribute>, +site: U32) -> Result<&2, &2, String, Unit>:
  match attributes:
    case Nil{}: Done{Unit{}}
    case Con{M.ValidatedAnnotations{metadata}, tail}: placements(tail, site)
    case Con{M.Attribute{name, bytes}, tail}:
      do Result<&2, &2, String, Unit>:
        AN.placement(AN.classify(name), site)
        placements(tail, site)

def parse_owner(+attributes: +List<M.Attribute>, +pool: +List<M.Constant>, +context: Context) -> Result<&2, &2, String, M.AnnotationMetadata>:
  match context:
    case Context{site, arity, prefix, interfaces, hasParent, isStatic, variables, codeLength, locals, handlers}:
      do Result<&2, &2, String, M.AnnotationMetadata>:
        placements(attributes, site)
        metadata : M.AnnotationMetadata <- AN.parse_attributes(attributes, pool)
        result : M.AnnotationMetadata <- normalize(metadata, context)
        return result

def code_metadata(+bytes: +List<U32>, +pool: +List<M.Constant>) -> Result<&2, &2, String, M.AnnotationMetadata>:
  do Result<&2, &2, String, M.AnnotationMetadata>:
    +stack : R.RWord <- R.read_u2(R.new(bytes))
    +locals : R.RWord <- R.read_u2(AN.word_reader(stack))
    +length : R.RWord <- R.read_u4(AN.word_reader(locals))
    after_code : R.Reader <- R.skip(AN.word_reader(length), AN.word_value(length))
    +handlers : R.RWord <- R.read_u2(after_code)
    metadata : M.AnnotationMetadata <- AN.parse_code_metadata_bytes(bytes, pool)
    checked : M.AnnotationMetadata <- normalize(metadata, Context{3, 0, 0, 0, False{}, False{}, Nil{}, AN.word_value(length), AN.word_value(locals), AN.word_value(handlers)})
    return checked

def method_code_metadata(attributes: +List<M.Attribute>, +pool: +List<M.Constant>) -> Result<&2, &2, String, M.AnnotationMetadata>:
  match attributes:
    case Nil{}: Done{M.empty_annotation_metadata()}
    case Con{M.ValidatedAnnotations{metadata}, tail}: method_code_metadata(tail, pool)
    case Con{M.Attribute{+name, bytes}, tail}:
      Bool.pick(Result<&2, &2, String, M.AnnotationMetadata>, String.eq(name, "Code"), code_metadata(bytes, pool), method_code_metadata(tail, pool))

def enclosing_prefix(fields: +List<M.Field>) -> U32:
  match fields:
    case Nil{}: 0
    case Con{M.Field{+flags, name, descriptor, constant, attributes}, tail}:
      Bool.pick(U32, Bool.and(String.eq(name, "this$0"), Bool.and(U32.is_ne(U32.and(flags, 4096), 0), U32.is_eq(U32.and(flags, 8), 0))), 1, enclosing_prefix(tail))

def fields_checked(fields: +List<M.Field>, +pool: +List<M.Constant>) -> Result<&2, &2, String, +List<M.Field>>:
  match fields:
    case Nil{}: Done{Nil{}}
    case Con{M.Field{flags, name, descriptor, constant, +attributes}, tail}:
      do Result<&2, &2, String, +List<M.Field>>:
        metadata : M.AnnotationMetadata <- parse_owner(attributes, pool, Context{1, 0, 0, 0, False{}, False{}, Nil{}, 0, 0, 0})
        rest : +List<M.Field> <- fields_checked(tail, pool)
        return Con{M.Field{flags, name, descriptor, constant, Con{M.ValidatedAnnotations{metadata}, attributes}}, rest}

def default_placement(attributes: +List<M.Attribute>, +classFlags: U32, +arity: U32, +name: String) -> Result<&2, &2, String, Unit>:
  match attributes:
    case Nil{}: Done{Unit{}}
    case Con{M.ValidatedAnnotations{metadata}, tail}: default_placement(tail, classFlags, arity, name)
    case Con{M.Attribute{kind, bytes}, tail}:
      do Result<&2, &2, String, Unit>:
        AN.require_annotation(Bool.or(Bool.not(String.eq(kind, "AnnotationDefault")), Bool.and(U32.is_ne(U32.and(classFlags, 8192), 0), Bool.and(U32.is_eq(arity, 0), Bool.and(Bool.not(String.eq(name, "<init>")), Bool.not(String.eq(name, "<clinit>")))))), "AnnotationDefault on non-annotation element")
        default_placement(tail, classFlags, arity, name)

def methods_checked(methods: +List<M.Method>, +pool: +List<M.Constant>, +classFlags: U32, +constructorPrefix: U32) -> Result<&2, &2, String, +List<M.Method>>:
  match methods:
    case Nil{}: Done{Nil{}}
    case Con{M.Method{+flags, +name, +descriptor, stack, locals, code, instructions, handlers, +attributes}, tail}:
      do Result<&2, &2, String, +List<M.Method>>:
        +parsed : M.Descriptor <- D.parse_method(descriptor)
        default_placement(attributes, classFlags, D.parameter_count(parsed), name)
        signature : String <- signature_text(attributes, pool)
        prefix : U32 = Bool.pick(U32, String.eq(name, "<init>"), Bool.pick(U32, U32.is_ne(U32.and(classFlags, 16384), 0), 2, constructorPrefix), 0)
        declaration : M.AnnotationMetadata <- parse_owner(attributes, pool, Context{2, D.parameter_count(parsed), prefix, 0, False{}, U32.is_ne(U32.and(flags, 8), 0), bounds(signature), 0, 0, 0})
        codeMetadata : M.AnnotationMetadata <- method_code_metadata(attributes, pool)
        metadata : M.AnnotationMetadata = AN.merge_code_metadata(declaration, codeMetadata)
        rest : +List<M.Method> <- methods_checked(tail, pool, classFlags, constructorPrefix)
        return Con{M.Method{flags, name, descriptor, stack, locals, code, instructions, handlers, Con{M.ValidatedAnnotations{metadata}, attributes}}, rest}

# One shared encoded-byte budget bounds all annotation nodes in a class,
# including nested Code attributes, before any structured annotation allocation.
def attributes_budget(values: +List<M.Attribute>, +budget: U32) -> Result<&2, &2, String, U32>:
  match values:
    case Nil{}: Done{budget}
    case Con{M.ValidatedAnnotations{metadata}, tail}: attributes_budget(tail, budget)
    case Con{M.Attribute{name, bytes}, tail}:
      +size = M.length(U32, bytes)
      do Result<&2, &2, String, U32>:
        AN.require_annotation(U32.is_le(size, budget), "aggregate class attribute byte budget exceeded")
        attributes_budget(tail, (budget - size : U32))

def fields_budget(values: +List<M.Field>, +budget: U32) -> Result<&2, &2, String, U32>:
  match values:
    case Nil{}: Done{budget}
    case Con{M.Field{flags, name, descriptor, constant, attributes}, tail}:
      do Result<&2, &2, String, U32>:
        next : U32 <- attributes_budget(attributes, budget)
        fields_budget(tail, next)

def methods_budget(values: +List<M.Method>, +budget: U32) -> Result<&2, &2, String, U32>:
  match values:
    case Nil{}: Done{budget}
    case Con{M.Method{flags, name, descriptor, stack, locals, code, instructions, handlers, attributes}, tail}:
      do Result<&2, &2, String, U32>:
        next : U32 <- attributes_budget(attributes, budget)
        methods_budget(tail, next)

def class_checked(value: M.ClassFile) -> Result<&2, &2, String, M.ClassFile>:
  match value:
    case M.ClassFile{minor, major, +flags, name, +parent, +interfaces, +pool, +fields, +methods, +attributes}:
      do Result<&2, &2, String, M.ClassFile>:
        fieldBudget : U32 <- fields_budget(fields, 262144)
        methodBudget : U32 <- methods_budget(methods, fieldBudget)
        remaining : U32 <- attributes_budget(attributes, methodBudget)
        signature : String <- signature_text(attributes, pool)
        metadata : M.AnnotationMetadata <- parse_owner(attributes, pool, Context{0, 0, 0, M.length(String, interfaces), Bool.not(String.is_empty(parent)), False{}, bounds(signature), 0, 0, 0})
        checkedFields : +List<M.Field> <- fields_checked(fields, pool)
        checkedMethods : +List<M.Method> <- methods_checked(methods, pool, flags, enclosing_prefix(fields))
        return M.ClassFile{minor, major, flags, name, parent, interfaces, pool, checkedFields, checkedMethods, Con{M.ValidatedAnnotations{metadata}, attributes}}

# Synthetic bootstrap definitions do not pass through the classfile parser.
# Their symbolic metadata is parsed here; ordinary classes always hit the cache.
def cached_go(attributes: +List<M.Attribute>, +original: +List<M.Attribute>, +pool: +List<M.Constant>) -> Result<&2, &2, String, M.AnnotationMetadata>:
  match attributes:
    case Nil{}: AN.parse_attributes(original, pool)
    case Con{M.ValidatedAnnotations{metadata}, tail}: Done{metadata}
    case Con{head, tail}: cached_go(tail, original, pool)

def cached(+attributes: +List<M.Attribute>, pool: +List<M.Constant>) -> Result<&2, &2, String, M.AnnotationMetadata>:
  cached_go(attributes, attributes, pool)

def cached_method_go(attributes: +List<M.Attribute>, +original: +List<M.Attribute>, +pool: +List<M.Constant>, +descriptor: String) -> Result<&2, &2, String, M.AnnotationMetadata>:
  match attributes:
    case Con{M.ValidatedAnnotations{metadata}, tail}: Done{metadata}
    case Con{head, tail}: cached_method_go(tail, original, pool, descriptor)
    case Nil{}:
      do Result<&2, &2, String, M.AnnotationMetadata>:
        parsed : M.Descriptor <- D.parse_method(descriptor)
        metadata : M.AnnotationMetadata <- AN.parse_attributes(original, pool)
        result : M.AnnotationMetadata <- normalize(metadata, Context{2, D.parameter_count(parsed), 0, 0, False{}, False{}, Nil{}, 0, 0, 0})
        return result

def cached_method(+attributes: +List<M.Attribute>, pool: +List<M.Constant>, descriptor: String) -> Result<&2, &2, String, M.AnnotationMetadata>:
  cached_method_go(attributes, attributes, pool, descriptor)
