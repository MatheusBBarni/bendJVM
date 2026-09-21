import Base
import ../model.bend as M
import ./symbols.bend as S
import ./bootstrap.bend as B
import ../classfile/descriptor.bend as D
import ../classfile/constant_pool.bend as CP

type Catalog is Data:
  Catalog{sources: +List<M.ClassFile>, names: +List<String>, symbols: +List<String>, fields: +List<M.LoadedField>, methods: +List<M.LoadedMethod>}

def check(ok: Bool, error: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{error}

def require(-A: Data, value: Maybe<&2, A>, error: String) -> Result<&2, &2, String, A>:
  match value:
    case Some{x}: Done{x}
    case None{}: Fail{error}

def class_name(cls: M.ClassFile) -> String:
  M.ClassFile{mi, ma, fl, name, pa, it, cp, fs, ms, at} = cls
  name

def names(classes: +List<M.ClassFile>) -> +List<String>:
  match classes:
    case Nil{}: Nil{}
    case Con{h, t}: Con{class_name(h), names(t)}

def class_id(+names: +List<String>, +name: String) -> Result<&2, &2, String, U32>:
  +id = S.find(names, name)
  do Result<&2, &2, String, U32>:
    check(U32.is_ne(id, 4294967295), "MissingClass: " ++ name)
    return id

def parent_id(names: +List<String>, +name: String) -> Result<&2, &2, String, U32>:
  Bool.pick(Result<&2, &2, String, U32>, String.is_empty(name), Done{4294967295}, class_id(names, name))

def intern_texts(xs: +List<String>, +symbols: +List<String>) -> +List<String>:
  match xs:
    case Nil{}: symbols
    case Con{h, t}: intern_texts(t, S.interned_symbols(S.intern(symbols, h)))

def pool_symbols(pool: +List<M.Constant>) -> +List<String>:
  match pool:
    case Nil{}: Nil{}
    case Con{M.Utf{text}, rest}: Con{text, pool_symbols(rest)}
    case Con{other, rest}: pool_symbols(rest)

def member_symbols_fields(fields: +List<M.Field>) -> +List<String>:
  match fields:
    case Nil{}: Nil{}
    case Con{M.Field{flags, name, desc, constant, attributes}, rest}:
      Con{name, Con{desc, member_symbols_fields(rest)}}

def member_symbols_methods(methods: +List<M.Method>) -> +List<String>:
  match methods:
    case Nil{}: Nil{}
    case Con{M.Method{flags, name, desc, stack, locals, code, ins, handlers, attrs}, rest}:
      Con{name, Con{desc, member_symbols_methods(rest)}}

def symbols(classes: +List<M.ClassFile>, sy: +List<String>) -> +List<String>:
  match classes:
    case Nil{}: sy
    case Con{M.ClassFile{mi, ma, fl, name, parent, interfaces, pool, fields, methods, attrs}, rest}:
      texts = M.append(String, pool_symbols(pool), M.append(String, member_symbols_fields(fields), member_symbols_methods(methods)))
      symbols(rest, intern_texts(Con{name, texts}, sy))

def field_value(tag: U32, nextId: U32, owner: U32, +sy: +List<String>, name: String, descriptor: String, +flags: U32) -> Result<&2, &2, String, M.LoadedField>:
  match tag:
    case 1:
      Done{M.LoadedField{nextId, owner, S.find(sy, name), S.find(sy, descriptor), flags, tag}}
    case 2:
      Done{M.LoadedField{nextId, owner, S.find(sy, name), S.find(sy, descriptor), flags, tag}}
    case 3:
      Done{M.LoadedField{nextId, owner, S.find(sy, name), S.find(sy, descriptor), flags, tag}}
    case _:
      Fail{"UnsupportedFeature: long/double field"}

def field_records(fields: +List<M.Field>, +owner: U32, +sy: +List<String>, id: U32) -> Result<&2, &2, String, +List<M.LoadedField>>:
  match fields:
    case Nil{}: Done{Nil{}}
    case Con{M.Field{+flags, name, desc, constant, attrs}, rest}:
      +nextId = id
      +descriptor = desc
      do Result<&2, &2, String, +List<M.LoadedField>>:
        typ : M.JvmType <- D.parse_field(descriptor)
        check(U32.is_eq(U32.and(flags, 64), 0), "UnsupportedFeature: volatile field")
        tail : +List<M.LoadedField> <- field_records(rest, owner, sy, (nextId + 1 : U32))
        field : M.LoadedField <- field_value(D.slot_tag(typ), nextId, owner, sy, name, descriptor, flags)
        return Con{field, tail}

def text_constant(value: M.Constant) -> Result<&2, &2, String, String>:
  match value:
    case M.Utf{text}: Done{text}
    case _: Fail{"VmError.InvalidConstantPool: expected Utf8"}

def link_name_type(op: U32, offset: U32, owner: String, pair: M.Constant, +pool: +List<M.Constant>, +sy: +List<String>) -> Result<&2, &2, String, M.Instruction>:
  match pair:
    case M.PairIndex{12, name_index, descriptor_index}:
      do Result<&2, &2, String, M.Instruction>:
        name_value : M.Constant <- CP.get(pool, name_index)
        name : String <- text_constant(name_value)
        descriptor_value : M.Constant <- CP.get(pool, descriptor_index)
        descriptor : String <- text_constant(descriptor_value)
        return M.Instruction{op, S.find(sy, owner), S.find(sy, name), S.find(sy, descriptor), offset}
    case _:
      Fail{"VmError.InvalidConstantPool: expected NameAndType"}

def link_member_value(op: U32, a: U32, b: U32, c: U32, offset: U32, value: M.Constant, +pool: +List<M.Constant>, +sy: +List<String>) -> Result<&2, &2, String, M.Instruction>:
  match value:
    case M.PairIndex{+kind, first, second}:
      do Result<&2, &2, String, M.Instruction>:
        check(Bool.and(U32.is_ge(kind, 9), U32.is_le(kind, 11)), "VmError.InvalidConstantPool: expected member reference")
        owner : String <- CP.class_name(pool, first)
        pair : M.Constant <- CP.get(pool, second)
        result : M.Instruction <- link_name_type(op, offset, owner, pair, pool, sy)
        return result
    case _:
      Fail{"VmError.InvalidConstantPool: expected member reference"}
def link_member_ref(op: U32, +a: U32, b: U32, c: U32, offset: U32, +pool: +List<M.Constant>, +sy: +List<String>) -> Result<&2, &2, String, M.Instruction>:
  do Result<&2, &2, String, M.Instruction>:
    value : M.Constant <- CP.get(pool, a)
    result : M.Instruction <- link_member_value(op, a, b, c, offset, value, pool, sy)
    return result

def literal_tag(kind: U32) -> U32:
  match kind:
    case 3: 1
    case 4: 2
    case 8: 3
    case _: 0

def link_literal(op: U32, a: U32, b: U32, c: U32, offset: U32, value: M.Constant, +pool: +List<M.Constant>, +sy: +List<String>) -> Result<&2, &2, String, M.Instruction>:
  match value:
    case M.Number{kind, bits}: Done{M.Instruction{op, bits, literal_tag(kind), c, offset}}
    case M.Index{8, index}:
      do Result<&2, &2, String, M.Instruction>:
        text : String <- CP.utf(pool, index)
        return M.Instruction{op, S.find(sy, text), 3, c, offset}
    case _: Fail{"VmError.InvalidConstantPool: expected ldc constant"}

def link_literal_ref(op: U32, +a: U32, b: U32, c: U32, offset: U32, +pool: +List<M.Constant>, +sy: +List<String>) -> Result<&2, &2, String, M.Instruction>:
  do Result<&2, &2, String, M.Instruction>:
    value : M.Constant <- CP.get(pool, a)
    linked : M.Instruction <- link_literal(op, a, b, c, offset, value, pool, sy)
    return linked
def link_one(value: M.Instruction, +pool: +List<M.Constant>, +sy: +List<String>) -> Result<&2, &2, String, M.Instruction>:
  match value:
    case M.Instruction{op, a, b, c, offset}:
      match op:
        case 178: link_member_ref(op, a, b, c, offset, pool, sy)
        case 179: link_member_ref(op, a, b, c, offset, pool, sy)
        case 180: link_member_ref(op, a, b, c, offset, pool, sy)
        case 181: link_member_ref(op, a, b, c, offset, pool, sy)
        case 182: link_member_ref(op, a, b, c, offset, pool, sy)
        case 183: link_member_ref(op, a, b, c, offset, pool, sy)
        case 184: link_member_ref(op, a, b, c, offset, pool, sy)
        case 185: link_member_ref(op, a, b, c, offset, pool, sy)
        case 187:
          do Result<&2, &2, String, M.Instruction>:
            name : String <- CP.class_name(pool, a)
            return M.Instruction{op, S.find(sy, name), b, c, offset}
        case 189:
          do Result<&2, &2, String, M.Instruction>:
            name : String <- CP.class_name(pool, a)
            return M.Instruction{op, S.find(sy, name), b, c, offset}
        case 192:
          do Result<&2, &2, String, M.Instruction>:
            name : String <- CP.class_name(pool, a)
            return M.Instruction{op, S.find(sy, name), b, c, offset}
        case 193:
          do Result<&2, &2, String, M.Instruction>:
            name : String <- CP.class_name(pool, a)
            return M.Instruction{op, S.find(sy, name), b, c, offset}
        case 18: link_literal_ref(op, a, b, c, offset, pool, sy)
        case 19: link_literal_ref(op, a, b, c, offset, pool, sy)
        case _:
          Done{value}

@unsafe def link_go(values: +List<M.Instruction>, +pool: +List<M.Constant>, +sy: +List<String>) -> Result<&2, &2, String, +List<M.Instruction>>:
  match values:
    case Nil{}: Done{Nil{}}
    case Con{+value, rest}:
      do Result<&2, &2, String, +List<M.Instruction>>:
        linked : M.Instruction <- link_one(value, pool, sy)
        tail : +List<M.Instruction> <- link_go(rest, pool, sy)
        return Con{linked, tail}

def link_instructions(values: +List<M.Instruction>, +pool: +List<M.Constant>, +sy: +List<String>) -> Result<&2, &2, String, +List<M.Instruction>>:
  link_go(values, pool, sy)


def method_value(native: Bool, intrinsic: U32, nextId: U32, owner: U32, +sy: +List<String>, name: String, descriptor: String, +flags: U32, parameters: U32, resultTag: U32, maxStack: U32, maxLocals: U32, instructions: +List<M.Instruction>, handlers: +List<M.Handler>) -> Result<&2, &2, String, M.LoadedMethod>:
  match native intrinsic:
    case False{} 0:
      Done{M.LoadedMethod{nextId, owner, S.find(sy, name), S.find(sy, descriptor), flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, 0}}
    case True{} 0:
      Fail{"UnsupportedFeature: native method"}
    case _ other:
      Done{M.LoadedMethod{nextId, owner, S.find(sy, name), S.find(sy, descriptor), flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, other}}

def method_records(methods: +List<M.Method>, +owner: U32, +ownerName: String, +pool: +List<M.Constant>, +sy: +List<String>, id: U32) -> Result<&2, &2, String, +List<M.LoadedMethod>>:
  match methods:
    case Nil{}: Done{Nil{}}
    case Con{M.Method{+flags, +name, +desc, stack, locals, code, ins, handlers, attrs}, rest}:
      +nextId = id
      do Result<&2, &2, String, +List<M.LoadedMethod>>:
        +parsed : M.Descriptor <- D.parse_method(desc)
        check(U32.is_eq(U32.and(flags, 32), 0), "UnsupportedFeature: synchronized method")
        intrinsic : U32 = Bool.pick(U32, U32.is_ne(U32.and(flags, 256), 0), B.intrinsic_desc(ownerName, name, desc), 0)
        resultTag : U32 = D.slot_tag(D.result_type(parsed))
        tail : +List<M.LoadedMethod> <- method_records(rest, owner, ownerName, pool, sy, (nextId + 1 : U32))
        linked : +List<M.Instruction> <- link_instructions(ins, pool, sy)
        method : M.LoadedMethod <- method_value(U32.is_ne(U32.and(flags, 256), 0), intrinsic, nextId, owner, sy, name, desc, flags, D.parameter_count(parsed), resultTag, stack, locals, linked, handlers)
        return Con{method, tail}

def collect(classes: +List<M.ClassFile>, +all: +List<M.ClassFile>, +ns: +List<String>, +sy: +List<String>, fs: +List<M.LoadedField>, ms: +List<M.LoadedMethod>, owner: U32) -> Result<&2, &2, String, Catalog>:
  match classes:
    case Nil{}: Done{Catalog{all, ns, sy, fs, ms}}
    case Con{M.ClassFile{mi, ma, fl, name, parent, interfaces, pool, fields, methods, attrs}, rest}:
      +oldFields = fs
      +oldMethods = ms
      +cid = owner
      do Result<&2, &2, String, Catalog>:
        newFields : +List<M.LoadedField> <- field_records(fields, cid, sy, M.length(M.LoadedField, oldFields))
        newMethods : +List<M.LoadedMethod> <- method_records(methods, cid, name, pool, sy, M.length(M.LoadedMethod, oldMethods))
        collect(rest, all, ns, sy, M.append(M.LoadedField, oldFields, newFields), M.append(M.LoadedMethod, oldMethods, newMethods), (cid + 1 : U32))

def build(+classes: +List<M.ClassFile>) -> Result<&2, &2, String, Catalog>:
  collect(classes, classes, names(classes), symbols(classes, Nil{}), Nil{}, Nil{}, 0)

def own_method(methods: +List<M.LoadedMethod>, +owner: U32, +name: U32, +desc: U32) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+m, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(m), owner) && U32.is_eq(M.loaded_method_name(m), name) && U32.is_eq(M.loaded_method_descriptor(m), desc), Some{m}, own_method(rest, owner, name, desc))

def own_field(fields: +List<M.LoadedField>, +owner: U32, +name: U32, +desc: U32) -> Maybe<&2, M.LoadedField>:
  match fields:
    case Nil{}: None{}
    case Con{+f, rest}:
      Bool.pick(Maybe<&2, M.LoadedField>, U32.is_eq(M.loaded_field_owner(f), owner) && U32.is_eq(M.loaded_field_name(f), name) && U32.is_eq(M.loaded_field_descriptor(f), desc), Some{f}, own_field(rest, owner, name, desc))

def parent_from_class(cls: M.ClassFile, ns: +List<String>) -> Result<&2, &2, String, U32>:
  match cls:
    case M.ClassFile{mi, ma, fl, name, par, it, cp, fs, ms, at}:
      parent_id(ns, par)

def parent(classes: +List<M.ClassFile>, ns: +List<String>, owner: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    cls : M.ClassFile <- require(M.ClassFile, M.nth(M.ClassFile, classes, owner), "MissingClass: parent resolution")
    result : U32 <- parent_from_class(cls, ns)
    return result
def resolve_found(found: Maybe<&2, M.LoadedMethod>, parentId: U32, continue: U32 -> Result<&2, &2, String, M.LoadedMethod>) -> Result<&2, &2, String, M.LoadedMethod>:
  match found:
    case Some{m}: Done{m}
    case None{}:
      match parentId:
        case 4294967295: Fail{"MissingMethod: unresolved method or cyclic hierarchy"}
        case value: continue(value)

def resolve_method(fuel: Nat, +cat: Catalog, +owner: U32, +name: U32, +desc: U32) -> Result<&2, &2, String, M.LoadedMethod>:
  match fuel:
    case 0n: Fail{"MissingMethod: unresolved method or cyclic hierarchy"}
    case 1n+p:
      Catalog{+sources, +ns, sy, fields, methods} = cat
      Result.bind(&2, &2, String, U32, M.LoadedMethod, parent(sources, ns, owner), par =>
        resolve_found(own_method(methods, owner, name, desc), par, parentId => resolve_method(p, cat, parentId, name, desc)))
def field_binding(+field: M.LoadedField) -> M.Binding:
  M.Binding{M.loaded_field_id(field), M.Slot{M.loaded_field_tag(field), 0}}

@unsafe def class_fields(fields: +List<M.LoadedField>, +owner: U32, +acc: +List<M.Binding>) -> +List<M.Binding>:
  match fields:
    case Nil{}: M.reverse(M.Binding, acc)
    case Con{+field, rest}:
      class_fields(rest, owner, Bool.pick(+List<M.Binding>, U32.is_eq(M.loaded_field_owner(field), owner), Con{field_binding(field), acc}, acc))
@unsafe def static_fields(fields: +List<M.LoadedField>, +acc: +List<M.Binding>) -> +List<M.Binding>:
  match fields:
    case Nil{}: M.reverse(M.Binding, acc)
    case Con{+field, rest}:
      static_fields(rest, Bool.pick(+List<M.Binding>, U32.is_ne(U32.and(M.loaded_field_flags(field), 8), 0), Con{field_binding(field), acc}, acc))


@unsafe def class_methods(methods: +List<M.LoadedMethod>, +owner: U32, +acc: +List<U32>) -> +List<U32>:
  match methods:
    case Nil{}: M.reverse(U32, acc)
    case Con{+method, rest}:
      class_methods(rest, owner, Bool.pick(+List<U32>, U32.is_eq(M.loaded_method_owner(method), owner), Con{M.loaded_method_id(method), acc}, acc))

@unsafe def interface_ids(values: +List<String>, +names: +List<String>, acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: M.reverse(U32, acc)
    case Con{value, rest}:
      interface_ids(rest, names, Con{S.find(names, value), acc})

@unsafe def initializer_id(methods: +List<M.LoadedMethod>, +owner: U32, +clinit: U32, +void: U32) -> U32:
  match methods:
    case Nil{}: 4294967295
    case Con{+method, rest}:
      Bool.pick(U32, U32.is_eq(M.loaded_method_owner(method), owner) && U32.is_eq(M.loaded_method_name(method), clinit) && U32.is_eq(M.loaded_method_descriptor(method), void), M.loaded_method_id(method), initializer_id(rest, owner, clinit, void))

@unsafe def classes_go(classes: +List<M.ClassFile>, +names: +List<String>, +ns: +List<String>, +symbols: +List<String>, +fields: +List<M.LoadedField>, +methods: +List<M.LoadedMethod>, +owner: U32, acc: +List<M.LoadedClass>) -> Result<&2, &2, String, +List<M.LoadedClass>>:
  match classes:
    case Nil{}:
      Done{M.reverse(M.LoadedClass, acc)}
    case Con{M.ClassFile{mi, ma, fl, name, parent_name, interfaces, pool, fs, ms, attrs}, rest}:
      do Result<&2, &2, String, +List<M.LoadedClass>>:
        parentId : U32 <- parent_id(ns, parent_name)
        loaded : M.LoadedClass = M.LoadedClass{owner, S.find(symbols, name), parentId, interface_ids(interfaces, names, Nil{}), class_fields(fields, owner, Nil{}), class_methods(methods, owner, Nil{}), initializer_id(methods, owner, S.find(symbols, "<clinit>"), S.find(symbols, "()V")), 0}
        tail : +List<M.LoadedClass> <- classes_go(rest, names, ns, symbols, fields, methods, (owner + 1 : U32), Con{loaded, acc})
        return tail

def loaded_classes(value: Catalog) -> Result<&2, &2, String, +List<M.LoadedClass>>:
  match value:
    case Catalog{sources, +class_names, symbol_values, field_values, method_values}:
      classes_go(sources, class_names, class_names, symbol_values, field_values, method_values, 0, Nil{})
