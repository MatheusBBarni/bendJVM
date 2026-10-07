import Base
import ../model.bend as M
import ../classfile/parser.bend as P
import ../classfile/descriptor.bend as D
import ../classfile/constant_pool.bend as CP
import ./catalog.bend as C
import ./bootstrap.bend as B
import ./symbols.bend as S
import ../runtime/state.bend as V

type Inspected is Data:
  Inspected{name: String, dependencies: +List<String>}


def primitive_mirror_entries(+names: +List<String>) -> +List<M.HeapEntry>:
  +mirror_class : U32 = S.find(names, "java/lang/Class")
  [M.HeapEntry{mirror_class, 8, S.find(names, "boolean"), Nil{}, Nil{}, Nil{}},
   M.HeapEntry{mirror_class, 8, S.find(names, "byte"), Nil{}, Nil{}, Nil{}},
   M.HeapEntry{mirror_class, 8, S.find(names, "char"), Nil{}, Nil{}, Nil{}},
   M.HeapEntry{mirror_class, 8, S.find(names, "short"), Nil{}, Nil{}, Nil{}},
   M.HeapEntry{mirror_class, 8, S.find(names, "int"), Nil{}, Nil{}, Nil{}},
   M.HeapEntry{mirror_class, 8, S.find(names, "long"), Nil{}, Nil{}, Nil{}},
   M.HeapEntry{mirror_class, 8, S.find(names, "float"), Nil{}, Nil{}, Nil{}},
   M.HeapEntry{mirror_class, 8, S.find(names, "double"), Nil{}, Nil{}, Nil{}},
   M.HeapEntry{mirror_class, 8, S.find(names, "void"), Nil{}, Nil{}, Nil{}}]

def bootstrap_heap(+names: +List<String>) -> +List<M.HeapEntry>:
  M.append(M.HeapEntry,
    M.append(M.HeapEntry,
      [M.HeapEntry{S.find(names, "java/io/PrintStream"), 0, 0, Nil{}, Nil{}, Nil{}},
       M.HeapEntry{S.find(names, "java/lang/OutOfMemoryError"), 0, 0, [M.Binding{0, M.Slot{3, 0}}, M.Binding{1, M.Slot{3, 0}}, M.Binding{2, M.Slot{3, 0}}, M.Binding{3, M.Slot{1, 0}}], Nil{}, Nil{}},
       M.HeapEntry{S.find(names, "java/lang/Boolean"), 0, 0, [M.Binding{0, M.Slot{1, 1}}], Nil{}, Nil{}},
       M.HeapEntry{S.find(names, "java/lang/Boolean"), 0, 0, [M.Binding{0, M.Slot{1, 0}}], Nil{}, Nil{}}],
      primitive_mirror_entries(names)),
    [M.HeapEntry{S.find(names, "java/lang/ClassLoader"), 0, 0, Nil{}, Nil{}, Nil{}}])

def set_static(xs: +List<M.Binding>, +id: U32, +value: M.Slot) -> +List<M.Binding>:
  match xs:
    case Nil{}: Nil{}
    case Con{M.Binding{+bid, old}, rest}:
      Con{M.Binding{bid, Bool.pick(M.Slot, U32.is_eq(bid, id), value, old)}, set_static(rest, id, value)}

def patch_out(fields: +List<M.LoadedField>, +symbols: +List<String>, +statics: +List<M.Binding>) -> +List<M.Binding>:
  match fields:
    case Nil{}: statics
    case Con{+field, rest}:
      patch_out(rest, symbols, Bool.pick(+List<M.Binding>, String.eq(S.text(symbols, M.loaded_field_name(field)), "out"), set_static(statics, M.loaded_field_id(field), M.Slot{3, 1}), statics))
def primitive_type_reference(+owner: String) -> U32:
  Bool.pick(U32, String.eq(owner, "java/lang/Boolean"), 5,
  Bool.pick(U32, String.eq(owner, "java/lang/Byte"), 6,
  Bool.pick(U32, String.eq(owner, "java/lang/Character"), 7,
  Bool.pick(U32, String.eq(owner, "java/lang/Short"), 8,
  Bool.pick(U32, String.eq(owner, "java/lang/Integer"), 9,
  Bool.pick(U32, String.eq(owner, "java/lang/Long"), 10,
  Bool.pick(U32, String.eq(owner, "java/lang/Float"), 11,
  Bool.pick(U32, String.eq(owner, "java/lang/Double"), 12,
  Bool.pick(U32, String.eq(owner, "java/lang/Void"), 13, 0)))))))))

def patch_type_fields(fields: +List<M.LoadedField>, +symbols: +List<String>, +names: +List<String>, +statics: +List<M.Binding>) -> +List<M.Binding>:
  match fields:
    case Nil{}: statics
    case Con{+field, rest}:
      +field_name : String = S.text(symbols, M.loaded_field_name(field))
      +owner_name : String = S.text(names, M.loaded_field_owner(field))
      +reference : U32 = primitive_type_reference(owner_name)
      +next : +List<M.Binding> = patch_type_fields(rest, symbols, names, statics)
      Bool.pick(+List<M.Binding>, String.eq(field_name, "TYPE") && U32.is_ne(reference, 0), set_static(next, M.loaded_field_id(field), M.Slot{3, reference}),
      Bool.pick(+List<M.Binding>, String.eq(owner_name, "java/lang/Boolean") && String.eq(field_name, "TRUE"), set_static(next, M.loaded_field_id(field), M.Slot{3, 3}),
        Bool.pick(+List<M.Binding>, String.eq(owner_name, "java/lang/Boolean") && String.eq(field_name, "FALSE"), set_static(next, M.loaded_field_id(field), M.Slot{3, 4}), next)))


def vm_from(catalog: C.Catalog, classes: +List<M.LoadedClass>, resources: +List<M.Resource>, maxHeap: U32) -> M.VM:
  match catalog:
    case C.Catalog{sources, +names, +symbols, +fields, methods, metadata}:
      host : M.Host = M.Host{M.Idle{}, ".", 3, 16777216, Nil{}, metadata}
      statics : +List<M.Binding> = C.static_fields(fields, Nil{})
      patched : +List<M.Binding> = patch_type_fields(fields, symbols, names, patch_out(fields, symbols, statics))
      M.VM{classes, methods, fields, symbols, bootstrap_heap(names), patched, resources, Nil{}, 0, 0, M.Slot{0, 0}, Nil{}, "", maxHeap, 0n, host}

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

def without_self_acc(same: Bool, +name: String, +acc: +List<String>) -> +List<String>:
  match same:
    case True{}: acc
    case False{}: Con{name, acc}

def without_self_go(names: +List<String>, +self: String, +acc: +List<String>) -> +List<String>:
  match names:
    case Nil{}: M.reverse(String, acc)
    case Con{+head, +tail}:
      +next_acc : +List<String> = without_self_acc(String.eq(head, self), head, acc)
      without_self_go(tail, self, next_acc)

def without_self(names: +List<String>, +self: String) -> +List<String>:
  without_self_go(names, self, Nil{})



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

# Runtime publication builds only new records. The old VM is the transaction
# snapshot; no IDs, heap references, live frames, or static bindings are rebuilt.
def vm_names(classes: +List<M.LoadedClass>, +symbols: +List<String>) -> +List<String>:
  match classes:
    case Nil{}: Nil{}
    case Con{+class, rest}: Con{S.text(symbols, M.loaded_class_name(class)), vm_names(rest, symbols)}

def check_new_names(classes: +List<M.ClassFile>, +known: +List<String>) -> Result<&2, &2, String, Unit>:
  match classes:
    case Nil{}: Done{Unit{}}
    case Con{+class, rest}:
      +name : String = class_internal_name(class)
      do Result<&2, &2, String, Unit>:
        C.check(Bool.not(has_name(known, name)), "LinkageError: duplicate runtime class " ++ name)
        result : Unit <- check_new_names(rest, M.append(String, known, [name]))
        return result


def check_dependency_names(dependencies: +List<String>, +known: +List<String>) -> Result<&2, &2, String, Unit>:
  match dependencies:
    case Nil{}: Done{Unit{}}
    case Con{+name, rest}:
      do Result<&2, &2, String, Unit>:
        checked : Unit <- C.check(has_name(known, name), "MissingClass: runtime dependency " ++ name)
        result : Unit <- check_dependency_names(rest, known)
        return result

def check_inspected_dependencies(value: Inspected, +known: +List<String>) -> Result<&2, &2, String, Unit>:
  match value:
    case Inspected{name, dependencies}: check_dependency_names(dependencies, known)

def check_dependencies(classes: +List<M.ClassFile>, +known: +List<String>) -> Result<&2, &2, String, Unit>:
  match classes:
    case Nil{}: Done{Unit{}}
    case Con{class, rest}:
      do Result<&2, &2, String, Unit>:
        inspected : Inspected <- class_dependencies(class)
        checked : Unit <- check_inspected_dependencies(inspected, known)
        result : Unit <- check_dependencies(rest, known)
        return result


def published(+vm: M.VM, +appended: +List<M.LoadedClass>, +fields: +List<M.LoadedField>, +methods: +List<M.LoadedMethod>, +symbols: +List<String>, metadata: M.Metadata, oldFields: U32) -> M.VM:
  match vm:
    case M.VM{+classes, old_methods, old_fields, old_symbols, heap, +statics, resources, frames, status, exception, result, output, error, maxHeap, steps, M.Host{effect, cwd, caps, maxPayload, cont, old_metadata}}:
      +fresh : +List<M.Binding> = C.static_fields(M.drop(M.LoadedField, fields, U32.to_nat(oldFields)), Nil{})
      M.VM{M.append(M.LoadedClass, classes, appended), methods, fields, symbols, heap, M.append(M.Binding, statics, fresh), resources, frames, status, exception, result, output, error, maxHeap, steps, M.Host{effect, cwd, caps, maxPayload, cont, metadata}}

def publish_catalog(+vm: M.VM, catalog: C.Catalog, oldClasses: U32, oldFields: U32) -> Result<&2, &2, String, M.VM>:
  match catalog:
    case C.Catalog{+sources, +names, +symbols, +fields, +methods, metadata}:
      do Result<&2, &2, String, M.VM>:
        appended : +List<M.LoadedClass> <- C.classes_go(sources, names, names, symbols, fields, methods, oldClasses, Nil{})
        return published(vm, appended, fields, methods, symbols, metadata, oldFields)

def append_parsed(+vm: M.VM, +parsed: +List<M.ClassFile>) -> Result<&2, &2, String, M.VM>:
  +known : +List<String> = vm_names(V.classes(vm), V.symbols(vm))
  +all_names : +List<String> = M.append(String, known, C.names(parsed))
  +fields : +List<M.LoadedField> = V.fields(vm)
  +methods : +List<M.LoadedMethod> = V.methods(vm)
  do Result<&2, &2, String, M.VM>:
    unique : Unit <- check_new_names(parsed, known)
    closure : Unit <- check_dependencies(parsed, all_names)
    catalog : C.Catalog <- C.collect(parsed, parsed, all_names, C.symbols(parsed, V.symbols(vm)), fields, methods, V.metadata(vm), M.length(M.LoadedClass, V.classes(vm)))
    updated : M.VM <- publish_catalog(vm, catalog, M.length(M.LoadedClass, V.classes(vm)), M.length(M.LoadedField, fields))
    return updated

def new_array_sources_go(values: +List<M.ClassFile>, +known: +List<String>, +acc: +List<M.ClassFile>) -> +List<M.ClassFile>:
  match values:
    case Nil{}: M.reverse(M.ClassFile, acc)
    case Con{+value, +rest}:
      +next : +List<M.ClassFile> = Bool.pick(+List<M.ClassFile>, has_name(known, class_internal_name(value)), acc, Con{value, acc})
      new_array_sources_go(rest, known, next)

def new_array_sources(values: +List<M.ClassFile>, +known: +List<String>) -> +List<M.ClassFile>:
  new_array_sources_go(values, known, Nil{})

def append_augmented(+vm: M.VM, value: C.AugmentedClasses) -> Result<&2, &2, String, M.VM>:
  match value:
    case C.AugmentedClasses{classes, arrays}:
      append_parsed(vm, M.append(M.ClassFile, classes, new_array_sources(arrays, vm_names(V.classes(vm), V.symbols(vm)))))

def append_runtime(+vm: M.VM, values: +List<+List<U32>>) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    parsed : +List<M.ClassFile> <- parse_classes(values, Nil{})
    updated : M.VM <- append_augmented(vm, C.augment_classes(parsed, Nil{}, Nil{}))
    return updated
