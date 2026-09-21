import Base
import ../model.bend as M
import ../classfile/parser.bend as P
import ../classfile/descriptor.bend as D
import ../classfile/constant_pool.bend as CP
import ./catalog.bend as C
import ./bootstrap.bend as B
import ./symbols.bend as S

type Inspected is Data:
  Inspected{name: String, dependencies: +List<String>}

def bootstrap_heap(+names: +List<String>) -> +List<M.HeapEntry>:
  [M.HeapEntry{S.find(names, "java/io/PrintStream"), 0, 0, Nil{}, Nil{}, Nil{}}]

def vm_from(catalog: C.Catalog, classes: +List<M.LoadedClass>, resources: +List<M.Resource>, maxHeap: U32) -> M.VM:
  match catalog:
    case C.Catalog{sources, names, symbols, +fields, methods}:
      M.VM{classes, methods, fields, symbols, bootstrap_heap(names), C.static_fields(fields, Nil{}), resources, Nil{}, 0, 0, M.Slot{0, 0}, Nil{}, "", maxHeap, 0n}

def parse_classes(values: +List<+List<U32>>, +acc: +List<M.ClassFile>) -> Result<&2, &2, String, +List<M.ClassFile>>:
  match values:
    case Nil{}:
      Done{M.reverse(M.ClassFile, acc)}
    case Con{+bytes, rest}:
      do Result<&2, &2, String, +List<M.ClassFile>>:
        class : M.ClassFile <- P.parse(bytes)
        tail : +List<M.ClassFile> <- parse_classes(rest, Con{class, acc})
        return tail

def load_many_with_resources(values: +List<+List<U32>>, resources: +List<M.Resource>, maxHeap: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    parsed : +List<M.ClassFile> <- parse_classes(values, Nil{})
    all : +List<M.ClassFile> = M.append(M.ClassFile, parsed, B.classes())
    +catalog : C.Catalog <- C.build(all)
    classes : +List<M.LoadedClass> <- C.loaded_classes(catalog)
    return vm_from(catalog, classes, resources, maxHeap)

def load_many(values: +List<+List<U32>>, maxHeap: U32) -> Result<&2, &2, String, M.VM>:
  load_many_with_resources(values, Nil{}, maxHeap)

def load_bytes(+bytes: +List<U32>, maxHeap: U32) -> Result<&2, &2, String, M.VM>:
  load_many(Con{bytes, Nil{}}, maxHeap)
def inspect_class(+bytes: +List<U32>) -> Result<&2, &2, String, M.ClassFile>:
  P.parse(bytes)

def class_internal_name(value: M.ClassFile) -> String:
  M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes} = value
  name

def inspect_class_name(+bytes: +List<U32>) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    value : M.ClassFile <- inspect_class(bytes)
    return class_internal_name(value)

def has_name(xs: +List<String>, +name: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, t}: Bool.or(String.eq(h, name), has_name(t, name))

def add_name(+name: String, +acc: +List<String>) -> +List<String>:
  Bool.pick(+List<String>, Bool.or(String.is_empty(name), has_name(acc, name)), acc, Con{name, acc})

def take_until_semicolon(text: String, acc: String) -> String:
  match text:
    case SNil{}: String.reverse(acc)
    case SCon{Chr{59}, t}: String.reverse(acc)
    case SCon{h, t}: take_until_semicolon(t, SCon{h, acc})

def array_loadable(text: String) -> String:
  match text:
    case SCon{Chr{91}, t}: array_loadable(t)
    case SCon{Chr{76}, t}: take_until_semicolon(t, SNil{})
    case _: ""

def loadable_name(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{91}, t}: array_loadable(t)
    case _: text

def jvm_type_name(value: M.JvmType) -> String:
  match value:
    case M.Primitive{tag}: ""
    case M.ObjectType{name}: name
    case M.ArrayType{element}: jvm_type_name(element)

def add_type_name(value: M.JvmType, acc: +List<String>) -> +List<String>:
  add_name(jvm_type_name(value), acc)

def add_types(values: +List<M.JvmType>, acc: +List<String>) -> +List<String>:
  match values:
    case Nil{}: acc
    case Con{h, t}: add_types(t, add_type_name(h, acc))

def add_field_descriptor(+text: String, acc: +List<String>) -> Result<&2, &2, String, +List<String>>:
  do Result<&2, &2, String, +List<String>>:
    typ : M.JvmType <- D.parse_field(text)
    return add_type_name(typ, acc)

def add_parsed_method(parsed: M.Descriptor, acc: +List<String>) -> +List<String>:
  match parsed:
    case M.Descriptor{parameters, result}:
      add_types(parameters, add_type_name(result, acc))

def add_method_descriptor(+text: String, acc: +List<String>) -> Result<&2, &2, String, +List<String>>:
  do Result<&2, &2, String, +List<String>>:
    parsed : M.Descriptor <- D.parse_method(text)
    return add_parsed_method(parsed, acc)

def add_fields(fields: +List<M.Field>, acc: +List<String>) -> Result<&2, &2, String, +List<String>>:
  match fields:
    case Nil{}: Done{acc}
    case Con{M.Field{flags, name, +descriptor, constant, attributes}, rest}:
      do Result<&2, &2, String, +List<String>>:
        next : +List<String> <- add_field_descriptor(descriptor, acc)
        result : +List<String> <- add_fields(rest, next)
        return result

def add_methods(methods: +List<M.Method>, acc: +List<String>) -> Result<&2, &2, String, +List<String>>:
  match methods:
    case Nil{}: Done{acc}
    case Con{M.Method{flags, name, +descriptor, maxStack, maxLocals, code, instructions, handlers, attributes}, rest}:
      do Result<&2, &2, String, +List<String>>:
        next : +List<String> <- add_method_descriptor(descriptor, acc)
        result : +List<String> <- add_methods(rest, next)
        return result

def add_strings(values: +List<String>, acc: +List<String>) -> +List<String>:
  match values:
    case Nil{}: acc
    case Con{+h, t}: add_strings(t, add_name(loadable_name(h), acc))

def add_pool_entry(+pool: +List<M.Constant>, entry: M.Constant, acc: +List<String>) -> Result<&2, &2, String, +List<String>>:
  match entry:
    case M.Index{7, index}:
      do Result<&2, &2, String, +List<String>>:
        text : String <- CP.utf(pool, index)
        return add_name(loadable_name(text), acc)
    case _:
      Done{acc}

def add_pool(entries: +List<M.Constant>, +pool: +List<M.Constant>, acc: +List<String>) -> Result<&2, &2, String, +List<String>>:
  match entries:
    case Nil{}: Done{acc}
    case Con{h, t}:
      do Result<&2, &2, String, +List<String>>:
        next : +List<String> <- add_pool_entry(pool, h, acc)
        result : +List<String> <- add_pool(t, pool, next)
        return result

def without_self(names: +List<String>, +self: String) -> +List<String>:
  match names:
    case Nil{}: Nil{}
    case Con{+h, +t}:
      Bool.pick(+List<String>, String.eq(h, self), without_self(t, self), Con{h, without_self(t, self)})

def class_dependencies(value: M.ClassFile) -> Result<&2, &2, String, Inspected>:
  M.ClassFile{minor, major, flags, +name, +parent, +interfaces, +pool, +fields, +methods, attributes} = value
  do Result<&2, &2, String, Inspected>:
    named : +List<String> = add_strings(Con{parent, interfaces}, Nil{})
    from_pool : +List<String> <- add_pool(pool, pool, named)
    from_fields : +List<String> <- add_fields(fields, from_pool)
    from_methods : +List<String> <- add_methods(methods, from_fields)
    return Inspected{name, without_self(from_methods, name)}

def inspect_class_info(+bytes: +List<U32>) -> Result<&2, &2, String, Inspected>:
  do Result<&2, &2, String, Inspected>:
    value : M.ClassFile <- inspect_class(bytes)
    result : Inspected <- class_dependencies(value)
    return result
