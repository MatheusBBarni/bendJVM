import Base
import ../model.bend as M
import ../runtime/value.bend as V
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ./outcome.bend as O
import ./library.bend as L
import ../loader/class_loader.bend as CL
import ./loader_state.bend as LS

# User class loaders (plan 03, C6).
#
# Every ClassLoader object owns a namespace number (the system loader is 0).
# defineClass parses the bytes, resolves each class name the new class mentions
# through its defining loader (supertypes first, as JVMS 5.3.5 requires; other
# names eagerly, which JVMS 5.4 allows, with failures kept until use), renames
# the class file only where the namespace sees a different class than the global
# name, and links it. Verification waits for linking (first initialization).
# A name defined by two loaders gets an internal name ending in U+E000 k (a
# private-use character no Java source can produce, yet legal in a binary name,
# so descriptors still parse); a name a loader cannot load maps to U+E000 -k.

def bits(slot: M.Slot) -> U32:
  M.slot_bits(slot)

def none() -> U32:
  4294967295

def namespace_mark() -> String:
  String.from_list([Chr{57344}])

def parent_binding() -> U32:
  4294967040

def namespace_binding() -> U32:
  4294967041

@unsafe def arg_at(+args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, M.Slot>:
  S.require(M.Slot, M.nth(M.Slot, args, index), "InvalidState: intrinsic argument count")

@unsafe def arg_ref(+args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +slot : M.Slot <- arg_at(args, index)
    return bits(slot)

# --- Loader objects ---

@unsafe def binding_of(+vm: M.VM, +reference: U32, +index: U32) -> U32:
  binding_entry(H.get(S.heap(vm), reference), index)

@unsafe def binding_entry(result: Result<&2, &2, String, M.HeapEntry>, +index: U32) -> U32:
  match result:
    case Fail{error}: 0
    case Done{entry}: L.field_bits(L.entry_fields(entry), index)

@unsafe def namespace_of(+vm: M.VM, +loader: U32) -> U32:
  Bool.pick(U32, U32.is_eq(loader, L.system_loader_reference()) || U32.is_eq(loader, 0), 0, binding_of(vm, loader, namespace_binding()))

@unsafe def parent_of(+vm: M.VM, +loader: U32) -> U32:
  Bool.pick(U32, U32.is_eq(loader, L.system_loader_reference()), 0, binding_of(vm, loader, parent_binding()))

# ClassLoader() and ClassLoader(ClassLoader parent): a fresh namespace.
@unsafe def loader_init(+vm: M.VM, +args: +List<M.Slot>, +explicit: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +parent : U32 <- Bool.pick(Result<&2, &2, String, U32>, explicit, arg_ref(args, 1), Done{L.system_loader_reference()})
    +state : M.Loaders = S.loaders(vm)
    +namespace : U32 = LS.state_next(state)
    +numbered : M.VM = LS.update_state(vm, U32.add(namespace, 1), LS.state_aliases(state), LS.state_defined(state), LS.state_pending(state), LS.state_defining(state))
    +entry : M.HeapEntry <- H.get(S.heap(numbered), receiver)
    +fields : +List<M.Binding> = H.binding_set(H.binding_set(L.entry_fields(entry), parent_binding(), M.Slot{3, parent}), namespace_binding(), M.Slot{1, namespace})
    +result : O.Outcome <- L.void_out(H.put(numbered, receiver, H.object_entry(H.entry_class(entry), fields)))
    return result

@unsafe def loader_get_parent(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +result : O.Outcome <- L.ref_out(vm, parent_of(vm, receiver))
    return result

@unsafe def name_internal(+vm: M.VM, +name_ref: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    checked : Unit <- S.check(U32.is_ne(name_ref, 0), L.npe())
    +text : String <- L.string_text(vm, name_ref)
    return L.class_binary_name(text)

# The class a namespace already knows under `name` (defined or initiated by it).
@unsafe def loaded_in(+vm: M.VM, +loader: U32, +name: String) -> U32:
  +namespace : U32 = namespace_of(vm, loader)
  Bool.pick(U32, U32.is_eq(namespace, 0), global_loaded(vm, name), loaded_alias(LS.alias_find(LS.state_aliases(S.loaders(vm)), namespace, name)))

@unsafe def loaded_alias(found: Maybe<&2, U32>) -> U32:
  match found:
    case None{}: none()
    case Some{id}: id

# The system loader sees every class it or the bootstrap loader defined.
@unsafe def global_loaded(+vm: M.VM, +name: String) -> U32:
  +id : U32 = L.class_id(vm, name)
  Bool.pick(U32, U32.is_ne(id, none()) && is_user_defined(vm, id), none(), id)

@unsafe def is_user_defined(+vm: M.VM, +class: U32) -> Bool:
  user_loader_found(LS.defined_loader(LS.state_defined(S.loaders(vm)), class))

@unsafe def user_loader_found(found: Maybe<&2, U32>) -> Bool:
  match found:
    case None{}: False{}
    case Some{loader}: U32.is_ne(loader, L.system_loader_reference())

@unsafe def mirror_or_null(+vm: M.VM, +id: U32) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 4294967295: L.ref_out(vm, 0)
    case +class: L.class_mirror_out(vm, class)

@unsafe def loader_find_loaded(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name_ref : U32 <- arg_ref(args, 1)
    +result : O.Outcome <- find_loaded_named(vm, receiver, name_ref)
    return result

@unsafe def find_loaded_named(+vm: M.VM, +receiver: U32, +name_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  match name_ref:
    case 0: L.ref_out(vm, 0)
    case +ref:
      do Result<&2, &2, String, O.Outcome>:
        +name : String <- name_internal(vm, ref)
        +result : O.Outcome <- mirror_or_null(vm, Bool.pick(U32, String.starts_with(name, "["), none(), loaded_in(vm, receiver, name)))
        return result

@unsafe def class_not_found(+vm: M.VM, +name_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +text : String <- Bool.pick(Result<&2, &2, String, String>, U32.is_eq(name_ref, 0), Done{"null"}, L.string_text(vm, name_ref))
    return O.ThrownName{vm, "java/lang/ClassNotFoundException: " ++ text}

# ClassLoader.findClass: the default throws ClassNotFoundException.
@unsafe def loader_find_class(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +name_ref : U32 <- arg_ref(args, 1)
    +result : O.Outcome <- class_not_found(vm, name_ref)
    return result

@unsafe def virtual_call(+vm: M.VM, +receiver: U32, +name: String, +descriptor: String, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.call_virtual(vm, L.virtual_on(vm, receiver, name, descriptor), args)

# loadClass(String): this.loadClass(name, false), so subclasses overriding the
# two-argument form take part.
@unsafe def loader_load_one(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name_ref : U32 <- arg_ref(args, 1)
    +result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(receiver, L.system_loader_reference()), L.class_loader_load(vm, args),
      virtual_call(vm, receiver, "loadClass", "(Ljava/lang/String;Z)Ljava/lang/Class;", [M.Slot{3, receiver}, M.Slot{3, name_ref}, M.Slot{1, 0}]))
    return result

# loadClass(String, boolean), the JDK algorithm: findLoadedClass, then the
# parent (or the bootstrap loader), then findClass. A ClassNotFoundException
# from the parent resumes with null (the LoaderCatch boundary).
@unsafe def loader_load_two(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name_ref : U32 <- arg_ref(args, 1)
    +result : O.Outcome <- loader_load_two_receiver(U32.is_eq(receiver, L.system_loader_reference()), vm, receiver, name_ref)
    return result

@unsafe def loader_load_two_receiver(system: Bool, +vm: M.VM, +receiver: U32, +name_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  match system:
    case True{}: L.class_loader_load(vm, [M.Slot{3, receiver}, M.Slot{3, name_ref}])
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +name : String <- name_internal(vm, name_ref)
        +loaded : U32 = loaded_in(vm, receiver, name)
        +result : O.Outcome <- loader_delegate(U32.is_ne(loaded, none()), vm, receiver, name_ref, name, loaded)
        return result

@unsafe def loader_delegate(found: Bool, +vm: M.VM, +receiver: U32, +name_ref: U32, +name: String, +loaded: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case True{}: L.class_mirror_out(vm, loaded)
    case False{}: loader_parent_call(parent_of(vm, receiver), vm, receiver, name_ref, name)

@unsafe def loader_parent_call(+parent: U32, +vm: M.VM, +receiver: U32, +name_ref: U32, +name: String) -> Result<&2, &2, String, O.Outcome>:
  match parent:
    case 0: bootstrap_or_find(L.class_bootstrap_name(name), vm, receiver, name_ref, name)
    case +ref:
      catching_call(L.push_cont(vm, M.NeedLoaderParent{receiver, name_ref}), ref, "loadClass", "(Ljava/lang/String;Z)Ljava/lang/Class;", [M.Slot{3, ref}, M.Slot{3, name_ref}, M.Slot{1, 0}])

@unsafe def bootstrap_or_find(bootstrap: Bool, +vm: M.VM, +receiver: U32, +name_ref: U32, +name: String) -> Result<&2, &2, String, O.Outcome>:
  match bootstrap:
    case True{}: L.class_mirror_out(vm, L.class_id(vm, name))
    case False{}: virtual_call(vm, receiver, "findClass", "(Ljava/lang/String;)Ljava/lang/Class;", [M.Slot{3, receiver}, M.Slot{3, name_ref}])

# A virtual call whose ClassNotFoundException resumes the waiting callback with null.
@unsafe def catching_call(+vm: M.VM, +receiver: U32, +name: String, +descriptor: String, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, L.virtual_on(vm, receiver, name, descriptor), "java/lang/AbstractMethodError")
    return O.Call{S.with_effect(vm, M.LoaderCatch{}), method, args}

# The parent's answer: a class, or null after ClassNotFoundException.
@unsafe def continue_parent(+vm: M.VM, +receiver: U32, +name_ref: U32, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  continue_parent_ref(vm, receiver, name_ref, bits(value))

@unsafe def continue_parent_ref(+vm: M.VM, +receiver: U32, +name_ref: U32, +found: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case 0: virtual_call(vm, receiver, "findClass", "(Ljava/lang/String;)Ljava/lang/Class;", [M.Slot{3, receiver}, M.Slot{3, name_ref}])
    case +mirror: L.ref_out(vm, mirror)

@unsafe def loader_resolve_class(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +target : U32 <- arg_ref(args, 1)
    checked : Unit <- S.check(U32.is_ne(target, 0), L.npe())
    +result : O.Outcome <- L.void_out(vm)
    return result

@unsafe def loader_find_system(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +name_ref : U32 <- arg_ref(args, 1)
    +result : O.Outcome <- L.class_loader_load(vm, [M.Slot{3, L.system_loader_reference()}, M.Slot{3, name_ref}])
    return result

@unsafe def loader_parallel(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.bool_out(vm, True{})

@unsafe def loader_lock(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +result : O.Outcome <- L.ref_out(vm, receiver)
    return result

# --- defineClass ---

@unsafe def byte_units(+slots: +List<M.Slot>) -> +List<U32>:
  match slots:
    case Nil{}: Nil{}
    case Con{slot, rest}: Con{U32.and(bits(slot), 255), byte_units(rest)}

@unsafe def define_bytes(+vm: M.VM, +array: U32, +offset: U32, +length: U32) -> Result<&2, &2, String, +List<U32>>:
  do Result<&2, &2, String, +List<U32>>:
    checked : Unit <- S.check(U32.is_ne(array, 0), L.npe())
    +entry : M.HeapEntry <- H.get(S.heap(vm), array)
    +values : +List<M.Slot> = L.entry_values(entry)
    +count : U32 = M.length(M.Slot, values)
    bounds : Unit <- S.check(Bool.not(V.negative(offset)) && Bool.not(V.negative(length)) && U32.is_le(offset, count) && U32.is_le(length, U32.sub(count, offset)), "java/lang/ArrayIndexOutOfBoundsException")
    return byte_units(M.take(M.Slot, M.drop(M.Slot, values, U32.to_nat(offset)), U32.to_nat(length)))

@unsafe def parse_failure(result: Result<&2, &2, String, M.ClassFile>) -> Result<&2, &2, String, M.ClassFile>:
  match result:
    case Done{file}: Done{file}
    case Fail{+error}: Fail{Bool.pick(String, String.starts_with(error, "java/"), error, "java/lang/ClassFormatError: " ++ error)}

@unsafe def last_slash(+chars: +List<Char>, +index: U32, +best: U32) -> U32:
  match chars:
    case Nil{}: best
    case Con{Chr{+c}, rest}: last_slash(rest, U32.add(index, 1), Bool.pick(U32, U32.is_eq(c, 46), index, best))

# preDefineClass: no class in a java.* package outside the bootstrap loader.
@unsafe def prohibited_check(+binary: String) -> Result<&2, &2, String, Unit>:
  prohibited_select(String.starts_with(binary, "java."), binary)

@unsafe def prohibited_select(prohibited: Bool, +binary: String) -> Result<&2, &2, String, Unit>:
  match prohibited:
    case False{}: Done{Unit{}}
    case True{}: Fail{"java/lang/SecurityException: Prohibited package name: " ++ String.from_list(M.take(Char, String.to_list(binary), U32.to_nat(last_slash(String.to_list(binary), 0, 0))))}

@unsafe def wrong_name_check(+requested: String, +actual: String) -> Result<&2, &2, String, Unit>:
  wrong_name_select(String.eq(requested, actual), requested, actual)

@unsafe def wrong_name_select(same: Bool, +requested: String, +actual: String) -> Result<&2, &2, String, Unit>:
  match same:
    case True{}: Done{Unit{}}
    case False{}: Fail{"java/lang/NoClassDefFoundError: " ++ requested ++ " (wrong name: " ++ actual ++ ")"}

@unsafe def strings_without(+values: +List<String>, +drop: +List<String>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      +tail : +List<String> = strings_without(rest, drop)
      Bool.pick(+List<String>, CL.has_name(drop, value), tail, Con{value, tail})

@unsafe def class_supers(+file: M.ClassFile) -> +List<String>:
  match file:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}:
      Bool.pick(+List<String>, String.is_empty(parent), interfaces, Con{parent, interfaces})

# Every class the file names, including those only its generic signatures and
# annotations mention (their failures are kept until reflection uses them).
@unsafe def class_others(+file: M.ClassFile, +supers: +List<String>, +actual: String) -> Result<&2, &2, String, +List<String>>:
  do Result<&2, &2, String, +List<String>>:
    +inspected : CL.Inspected <- CL.class_dependencies(file)
    +named : +List<String> = attribute_names(file_pool(file), file_indices(file), inspected_names(inspected))
    return strings_without(named, Con{actual, supers})

@unsafe def file_pool(+file: M.ClassFile) -> +List<M.Constant>:
  match file:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, +pool, fields, methods, attributes}: pool

@unsafe def file_indices(+file: M.ClassFile) -> +List<U32>:
  match file:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, +fields, +methods, +attributes}:
      attribute_indices(attributes, field_indices(fields, method_indices(methods, Nil{})))

@unsafe def attribute_names(+pool: +List<M.Constant>, +indices: +List<U32>, +names: +List<String>) -> +List<String>:
  match indices:
    case Nil{}: names
    case Con{+index, rest}: attribute_names(pool, rest, add_names(signature_names(String.to_list(pool_text(pool, index)), Nil{}), names))

@unsafe def add_names(+values: +List<String>, +names: +List<String>) -> +List<String>:
  match values:
    case Nil{}: names
    case Con{+value, rest}: add_names(rest, CL.add_name(value, names))

@unsafe def inspected_names(+value: CL.Inspected) -> +List<String>:
  match value:
    case CL.Inspected{name, dependencies}: dependencies

@unsafe def define_class(+vm: M.VM, +args: +List<M.Slot>, +named: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name_ref : U32 <- Bool.pick(Result<&2, &2, String, U32>, named, arg_ref(args, 1), Done{0})
    +array : U32 <- arg_ref(args, Bool.pick(U32, named, 2, 1))
    +offset : U32 <- arg_ref(args, Bool.pick(U32, named, 3, 2))
    +length : U32 <- arg_ref(args, Bool.pick(U32, named, 4, 3))
    +binary : String <- Bool.pick(Result<&2, &2, String, String>, U32.is_eq(name_ref, 0), Done{""}, L.string_text(vm, name_ref))
    prohibited : Unit <- prohibited_check(binary)
    +bytes : +List<U32> <- define_bytes(vm, array, offset, length)
    +file : M.ClassFile <- parse_failure(CL.inspect_class(bytes))
    +actual : String = CL.class_internal_name(file)
    named_ok : Unit <- wrong_name_check(Bool.pick(String, U32.is_eq(name_ref, 0), actual, L.class_binary_name(binary)), actual)
    +namespace : U32 = namespace_of(vm, receiver)
    +state : M.Loaders = S.loaders(vm)
    +known : Bool = Bool.pick(Bool, U32.is_eq(namespace, 0), U32.is_ne(global_loaded(vm, actual), none()), U32.is_ne(loaded_alias(LS.alias_find(LS.state_aliases(state), namespace, actual)), none()))
    +busy : Bool = is_some_text(LS.defining_find(LS.state_defining(state), namespace, actual))
    unique : Unit <- S.check(Bool.not(known || busy), "java/lang/LinkageError: attempted duplicate class definition for " ++ L.class_display_name(actual))
    +taken : Bool = U32.is_ne(L.class_id(vm, actual), none()) || LS.internal_in_progress(LS.state_defining(state), actual)
    +internal : String = Bool.pick(String, taken && U32.is_ne(namespace, 0), actual ++ namespace_mark() ++ U32.show(namespace), actual)
    +supers : +List<String> = class_supers(file)
    +others : +List<String> <- class_others(file, supers, actual)
    +job : M.DefineJob = M.DefineJob{receiver, namespace, file, actual, internal, supers, others, Nil{}, "", False{}}
    +result : O.Outcome <- define_step(LS.with_defining(vm, namespace, actual, internal), job)
    return result

@unsafe def is_some_text(found: Maybe<&2, String>) -> Bool:
  match found:
    case None{}: False{}
    case Some{text}: True{}

# Resolve the next name through the defining loader, or finish.
@unsafe def define_step(+vm: M.VM, +job: M.DefineJob) -> Result<&2, &2, String, O.Outcome>:
  match job:
    case M.DefineJob{+loader, +namespace, +file, +actual, +internal, Con{+name, rest}, +others, +mapping, current, super}:
      define_resolve(vm, M.DefineJob{loader, namespace, file, actual, internal, rest, others, mapping, name, True{}}, name, True{})
    case M.DefineJob{+loader, +namespace, +file, +actual, +internal, Nil{}, Con{+name, rest}, +mapping, current, super}:
      define_resolve(vm, M.DefineJob{loader, namespace, file, actual, internal, Nil{}, rest, mapping, name, False{}}, name, False{})
    case M.DefineJob{+loader, +namespace, +file, +actual, +internal, Nil{}, Nil{}, +mapping, current, super}:
      define_finish(vm, loader, namespace, file, actual, internal, mapping)

@unsafe def job_with_mapping(+job: M.DefineJob, +internal_name: String) -> M.DefineJob:
  match job:
    case M.DefineJob{+loader, +namespace, +file, +actual, +internal, +supers, +others, +mapping, +current, +super}:
      M.DefineJob{loader, namespace, file, actual, internal, supers, others, Con{M.NameMap{current, internal_name}, mapping}, current, super}

@unsafe def job_loader(+job: M.DefineJob) -> U32:
  match job:
    case M.DefineJob{loader, namespace, file, actual, internal, supers, others, mapping, current, super}: loader

@unsafe def job_namespace(+job: M.DefineJob) -> U32:
  match job:
    case M.DefineJob{loader, namespace, file, actual, internal, supers, others, mapping, current, super}: namespace

@unsafe def job_current(+job: M.DefineJob) -> String:
  match job:
    case M.DefineJob{loader, namespace, file, actual, internal, supers, others, mapping, current, super}: current

# A name the namespace already resolved (or is defining) needs no call; the
# system namespace sees global names; others ask the loader.
@unsafe def define_resolve(+vm: M.VM, +job: M.DefineJob, +name: String, +super: Bool) -> Result<&2, &2, String, O.Outcome>:
  +namespace : U32 = job_namespace(job)
  +state : M.Loaders = S.loaders(vm)
  +aliased : U32 = loaded_alias(LS.alias_find(LS.state_aliases(state), namespace, name))
  define_resolve_alias(U32.is_ne(aliased, none()), aliased, vm, job, name, super, LS.defining_find(LS.state_defining(state), namespace, name))

@unsafe def define_resolve_alias(known: Bool, +aliased: U32, +vm: M.VM, +job: M.DefineJob, +name: String, +super: Bool, found: Maybe<&2, String>) -> Result<&2, &2, String, O.Outcome>:
  match known:
    case True{}: define_step(vm, job_with_mapping(job, L.class_name_text(vm, aliased)))
    case False{}: define_resolve_defining(found, vm, job, name, super)

@unsafe def define_resolve_defining(found: Maybe<&2, String>, +vm: M.VM, +job: M.DefineJob, +name: String, +super: Bool) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{+internal}: define_step(vm, job_with_mapping(job, internal))
    case None{}: define_resolve_call(vm, job, name, super)

@unsafe def define_resolve_call(+vm: M.VM, +job: M.DefineJob, +name: String, +super: Bool) -> Result<&2, &2, String, O.Outcome>:
  define_resolve_invoke(H.allocate(vm, H.string_entry(L.class_id(vm, "java/lang/String"), L.units_from_string(L.internal_to_binary(name)))), job, job_loader(job), super)

@unsafe def define_resolve_invoke(allocation: Result<&2, &2, String, H.Allocation>, +job: M.DefineJob, +loader: U32, +super: Bool) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+allocated, +reference}}:
      do Result<&2, &2, String, O.Outcome>:
        +ready : M.VM = L.push_cont(allocated, M.NeedDefine{job})
        +method : M.LoadedMethod <- S.require(M.LoadedMethod, L.virtual_on(ready, loader, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;"), "java/lang/AbstractMethodError")
        return O.Call{S.with_effect(ready, Bool.pick(M.Effect, super, M.LoaderSuper{job_current(job)}, M.LoaderCatch{})), method, [M.Slot{3, loader}, M.Slot{3, reference}]}

# The loader answered: a class (the namespace now initiates it) or null after
# ClassNotFoundException, which leaves the name unresolvable for this class.
@unsafe def continue_define(+vm: M.VM, +job: M.DefineJob, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  continue_define_ref(vm, job, bits(value))

@unsafe def continue_define_ref(+vm: M.VM, +job: M.DefineJob, +found: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case 0: define_step(vm, job_with_mapping(job, job_current(job) ++ namespace_mark() ++ "-" ++ U32.show(job_namespace(job))))
    case +mirror:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), mirror)
        +target : U32 = L.entry_element(entry)
        +recorded : M.VM = LS.with_alias(vm, job_namespace(job), job_current(job), target)
        +result : O.Outcome <- define_step(recorded, job_with_mapping(job, L.class_name_text(recorded, target)))
        return result

@unsafe def define_finish(+vm: M.VM, +loader: U32, +namespace: U32, +file: M.ClassFile, +actual: String, +internal: String, +mapping: +List<M.NameMap>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +renamed : M.ClassFile = rename_file(file, Con{M.NameMap{actual, internal}, mapping})
    +linked : M.VM <- CL.append_defined(LS.without_defining(vm, namespace, actual), renamed)
    +id : U32 = L.class_id(linked, internal)
    +recorded : M.VM = LS.with_defined_class(Bool.pick(M.VM, U32.is_eq(namespace, 0), linked, LS.with_alias(linked, namespace, actual, id)), id, loader, renamed)
    +result : O.Outcome <- L.class_mirror_out(recorded, id)
    return result

# --- Renaming a class file into its namespace ---

@unsafe def mapped_name(+mapping: +List<M.NameMap>, +name: String) -> String:
  match mapping:
    case Nil{}: name
    case Con{M.NameMap{+from, +to}, rest}: Bool.pick(String, String.eq(from, name), to, mapped_name(rest, name))

@unsafe def mapping_changes(+mapping: +List<M.NameMap>) -> Bool:
  match mapping:
    case Nil{}: False{}
    case Con{M.NameMap{+from, +to}, rest}: Bool.not(String.eq(from, to)) || mapping_changes(rest)

# Class names inside a descriptor or array name ("L...;" runs).
@unsafe def map_descriptor(+chars: +List<Char>, +mapping: +List<M.NameMap>) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{76}, rest}: map_descriptor_class(rest, mapping, Nil{})
    case Con{c, rest}: Con{c, map_descriptor(rest, mapping)}

@unsafe def map_descriptor_class(+chars: +List<Char>, +mapping: +List<M.NameMap>, +acc: +List<Char>) -> +List<Char>:
  match chars:
    case Nil{}: Con{Chr{76}, M.reverse(Char, acc)}
    case Con{Chr{59}, rest}: M.append(Char, Con{Chr{76}, String.to_list(mapped_name(mapping, String.from_list(M.reverse(Char, acc))))}, Con{Chr{59}, map_descriptor(rest, mapping)})
    case Con{c, rest}: map_descriptor_class(rest, mapping, Con{c, acc})

@unsafe def map_descriptor_text(+text: String, +mapping: +List<M.NameMap>) -> String:
  String.from_list(map_descriptor(String.to_list(text), mapping))

# A CONSTANT_Class name is a class name or an array descriptor.
@unsafe def map_class_text(+text: String, +mapping: +List<M.NameMap>) -> String:
  Bool.pick(String, String.starts_with(text, "["), map_descriptor_text(text, mapping), mapped_name(mapping, text))

@unsafe def rename_file(+file: M.ClassFile, +mapping: +List<M.NameMap>) -> M.ClassFile:
  rename_file_select(mapping_changes(mapping), file, mapping)

@unsafe def rename_file_select(changed: Bool, +file: M.ClassFile, +mapping: +List<M.NameMap>) -> M.ClassFile:
  match changed:
    case False{}: file
    case True{}: rename_file_changed(file, mapping)

# Signature attributes and annotation type descriptors point at Utf8 entries;
# renamed texts are appended to the pool and the attributes point at them.
@unsafe def rename_file_changed(+file: M.ClassFile, +mapping: +List<M.NameMap>) -> M.ClassFile:
  match file:
    case M.ClassFile{minor, major, flags, +name, +parent, +interfaces, +pool, +fields, +methods, +attributes}:
      +renamed : +List<M.Constant> = rename_pool(pool, mapping)
      +indices : +List<U32> = attribute_indices(attributes, field_indices(fields, method_indices(methods, Nil{})))
      +remap : Remap = index_maps(indices, pool, mapping, M.length(M.Constant, renamed), Nil{}, Nil{})
      +maps : +List<IndexMap> = remap_maps(remap)
      M.ClassFile{minor, major, flags, mapped_name(mapping, name), Bool.pick(String, String.is_empty(parent), parent, mapped_name(mapping, parent)), rename_names(interfaces, mapping),
        M.append(M.Constant, renamed, remap_extra(remap)), rename_fields(fields, mapping, maps), rename_methods(methods, mapping, maps), remap_attributes(attributes, maps)}

@unsafe def rename_names(+names: +List<String>, +mapping: +List<M.NameMap>) -> +List<String>:
  match names:
    case Nil{}: Nil{}
    case Con{+name, rest}: Con{mapped_name(mapping, name), rename_names(rest, mapping)}

@unsafe def rename_fields(+fields: +List<M.Field>, +mapping: +List<M.NameMap>, +maps: +List<IndexMap>) -> +List<M.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{M.Field{flags, name, +descriptor, constant, +attributes}, rest}: Con{M.Field{flags, name, map_descriptor_text(descriptor, mapping), constant, remap_attributes(attributes, maps)}, rename_fields(rest, mapping, maps)}

@unsafe def rename_methods(+methods: +List<M.Method>, +mapping: +List<M.NameMap>, +maps: +List<IndexMap>) -> +List<M.Method>:
  match methods:
    case Nil{}: Nil{}
    case Con{M.Method{flags, name, +descriptor, maxStack, maxLocals, code, instructions, handlers, +attributes, switches}, rest}:
      Con{M.Method{flags, name, map_descriptor_text(descriptor, mapping), maxStack, maxLocals, code, instructions, handlers, remap_attributes(attributes, maps), switches}, rename_methods(rest, mapping, maps)}

# --- Class names in generic signatures and annotations ---
# A class type is "L" name, then optional type arguments ("<...>") and
# inner-class suffixes (".Inner"), then ";". A type variable is "T" name ";",
# and a formal type parameter is an identifier ending in ':'.

@unsafe def renamed_chars(+acc: +List<Char>, +mapping: +List<M.NameMap>) -> +List<Char>:
  String.to_list(mapped_name(mapping, String.from_list(M.reverse(Char, acc))))

@unsafe def map_signature(+chars: +List<Char>, +mapping: +List<M.NameMap>) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{76}, rest}: map_signature_class(rest, mapping, Nil{})
    case Con{Chr{84}, rest}: Con{Chr{84}, map_signature_variable(rest, mapping)}
    case Con{Chr{46}, rest}: Con{Chr{46}, map_signature_simple(rest, mapping)}
    case Con{c, rest}: Con{c, map_signature(rest, mapping)}

@unsafe def map_signature_class(+chars: +List<Char>, +mapping: +List<M.NameMap>, +acc: +List<Char>) -> +List<Char>:
  match chars:
    case Nil{}: Con{Chr{76}, M.reverse(Char, acc)}
    case Con{Chr{58}, rest}: M.append(Char, Con{Chr{76}, M.reverse(Char, acc)}, Con{Chr{58}, map_signature(rest, mapping)})
    case Con{Chr{59}, rest}: M.append(Char, Con{Chr{76}, renamed_chars(acc, mapping)}, Con{Chr{59}, map_signature(rest, mapping)})
    case Con{Chr{60}, rest}: M.append(Char, Con{Chr{76}, renamed_chars(acc, mapping)}, Con{Chr{60}, map_signature(rest, mapping)})
    case Con{Chr{46}, rest}: M.append(Char, Con{Chr{76}, renamed_chars(acc, mapping)}, Con{Chr{46}, map_signature_simple(rest, mapping)})
    case Con{c, rest}: map_signature_class(rest, mapping, Con{c, acc})

@unsafe def map_signature_variable(+chars: +List<Char>, +mapping: +List<M.NameMap>) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{59}, rest}: Con{Chr{59}, map_signature(rest, mapping)}
    case Con{Chr{58}, rest}: Con{Chr{58}, map_signature(rest, mapping)}
    case Con{c, rest}: Con{c, map_signature_variable(rest, mapping)}

@unsafe def map_signature_simple(+chars: +List<Char>, +mapping: +List<M.NameMap>) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{60}, rest}: Con{Chr{60}, map_signature(rest, mapping)}
    case Con{Chr{59}, rest}: Con{Chr{59}, map_signature(rest, mapping)}
    case Con{c, rest}: Con{c, map_signature_simple(rest, mapping)}

@unsafe def acc_name(+acc: +List<Char>) -> String:
  String.from_list(M.reverse(Char, acc))

@unsafe def signature_names(+chars: +List<Char>, +names: +List<String>) -> +List<String>:
  match chars:
    case Nil{}: names
    case Con{Chr{76}, rest}: signature_names_class(rest, Nil{}, names)
    case Con{Chr{84}, rest}: signature_names_variable(rest, names)
    case Con{Chr{46}, rest}: signature_names_simple(rest, names)
    case Con{c, rest}: signature_names(rest, names)

@unsafe def signature_names_class(+chars: +List<Char>, +acc: +List<Char>, +names: +List<String>) -> +List<String>:
  match chars:
    case Nil{}: names
    case Con{Chr{58}, rest}: signature_names(rest, names)
    case Con{Chr{59}, rest}: signature_names(rest, Con{acc_name(acc), names})
    case Con{Chr{60}, rest}: signature_names(rest, Con{acc_name(acc), names})
    case Con{Chr{46}, rest}: signature_names_simple(rest, Con{acc_name(acc), names})
    case Con{c, rest}: signature_names_class(rest, Con{c, acc}, names)

@unsafe def signature_names_variable(+chars: +List<Char>, +names: +List<String>) -> +List<String>:
  match chars:
    case Nil{}: names
    case Con{Chr{59}, rest}: signature_names(rest, names)
    case Con{Chr{58}, rest}: signature_names(rest, names)
    case Con{c, rest}: signature_names_variable(rest, names)

@unsafe def signature_names_simple(+chars: +List<Char>, +names: +List<String>) -> +List<String>:
  match chars:
    case Nil{}: names
    case Con{Chr{60}, rest}: signature_names(rest, names)
    case Con{Chr{59}, rest}: signature_names(rest, names)
    case Con{c, rest}: signature_names_simple(rest, names)

# The Utf8 indices Signature attributes and annotation descriptors use.
@unsafe def signature_index(+bytes: +List<U32>) -> U32:
  match bytes:
    case Con{+high, Con{+low, rest}}: U32.or(U32.shln(high, 8n), low)
    case _: 0

@unsafe def attribute_indices(+attributes: +List<M.Attribute>, +acc: +List<U32>) -> +List<U32>:
  match attributes:
    case Nil{}: acc
    case Con{M.Attribute{+name, +bytes}, rest}: attribute_indices(rest, Bool.pick(+List<U32>, String.eq(name, "Signature"), Con{signature_index(bytes), acc}, acc))
    case Con{M.ValidatedAnnotations{+metadata}, rest}: attribute_indices(rest, metadata_indices(metadata, acc))

@unsafe def field_indices(+fields: +List<M.Field>, +acc: +List<U32>) -> +List<U32>:
  match fields:
    case Nil{}: acc
    case Con{M.Field{flags, name, descriptor, constant, +attributes}, rest}: field_indices(rest, attribute_indices(attributes, acc))

@unsafe def method_indices(+methods: +List<M.Method>, +acc: +List<U32>) -> +List<U32>:
  match methods:
    case Nil{}: acc
    case Con{M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, +attributes, switches}, rest}: method_indices(rest, attribute_indices(attributes, acc))

@unsafe def metadata_indices(+metadata: M.AnnotationMetadata, +acc: +List<U32>) -> +List<U32>:
  match metadata:
    case M.AnnotationMetadata{flags, exceptions, +annotations, +parameters, +types, +default, +hidden, +hiddenParameters, +hiddenTypes}:
      annotations_indices(annotations, nested_indices(parameters, types_indices(types, default_indices(default, annotations_indices(hidden, nested_indices(hiddenParameters, types_indices(hiddenTypes, acc)))))))

@unsafe def annotations_indices(+annotations: +List<M.Annotation>, +acc: +List<U32>) -> +List<U32>:
  match annotations:
    case Nil{}: acc
    case Con{M.Annotation{+kind, +elements}, rest}: annotations_indices(rest, Con{kind, elements_indices(elements, acc)})

@unsafe def nested_indices(+lists: +List<+List<M.Annotation>>, +acc: +List<U32>) -> +List<U32>:
  match lists:
    case Nil{}: acc
    case Con{+annotations, rest}: nested_indices(rest, annotations_indices(annotations, acc))

@unsafe def types_indices(+annotations: +List<M.TypeAnnotation>, +acc: +List<U32>) -> +List<U32>:
  match annotations:
    case Nil{}: acc
    case Con{M.TypeAnnotation{target, info, path, +annotation}, rest}: types_indices(rest, annotations_indices([annotation], acc))

@unsafe def default_indices(+found: Maybe<&2, M.AnnotationValue>, +acc: +List<U32>) -> +List<U32>:
  match found:
    case None{}: acc
    case Some{+value}: value_indices(value, acc)

@unsafe def elements_indices(+elements: +List<M.AnnotationElement>, +acc: +List<U32>) -> +List<U32>:
  match elements:
    case Nil{}: acc
    case Con{M.AnnotationElement{name, +value}, rest}: elements_indices(rest, value_indices(value, acc))

@unsafe def values_indices(+values: +List<M.AnnotationValue>, +acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: acc
    case Con{+value, rest}: values_indices(rest, value_indices(value, acc))

@unsafe def value_indices(+value: M.AnnotationValue, +acc: +List<U32>) -> +List<U32>:
  match value:
    case M.AnnotationEnum{+kind, name}: Con{kind, acc}
    case M.AnnotationClass{+descriptor}: Con{descriptor, acc}
    case M.AnnotationNested{+kind, +elements}: Con{kind, values_indices(elements, acc)}
    case M.AnnotationElementValue{name, +inner}: value_indices(inner, acc)
    case M.AnnotationArray{+values}: values_indices(values, acc)
    case _: acc

# Each index whose text the mapping changes gets a new Utf8 entry.
type IndexMap is Data:
  IndexMap{from: U32, to: U32}

type Remap is Data:
  Remap{maps: +List<IndexMap>, extra: +List<M.Constant>}

@unsafe def remap_maps(+value: Remap) -> +List<IndexMap>:
  match value:
    case Remap{+maps, extra}: maps

@unsafe def remap_extra(+value: Remap) -> +List<M.Constant>:
  match value:
    case Remap{maps, +extra}: extra

@unsafe def mapped_index(+maps: +List<IndexMap>, +index: U32) -> U32:
  match maps:
    case Nil{}: index
    case Con{IndexMap{+from, +to}, rest}: mapped_index_step(U32.is_eq(from, index), to, rest, index)

@unsafe def mapped_index_step(+hit: Bool, +to: U32, +rest: +List<IndexMap>, +index: U32) -> U32:
  match hit:
    case True{}: to
    case False{}: mapped_index(rest, index)

@unsafe def index_maps(+indices: +List<U32>, +pool: +List<M.Constant>, +mapping: +List<M.NameMap>, +next: U32, +maps: +List<IndexMap>, +extra: +List<M.Constant>) -> Remap:
  match indices:
    case Nil{}: Remap{maps, M.reverse(M.Constant, extra)}
    case Con{+index, rest}:
      +text : String = pool_text(pool, index)
      +mapped : String = String.from_list(map_signature(String.to_list(text), mapping))
      +fresh : Bool = U32.is_eq(mapped_index(maps, index), index) && Bool.not(String.eq(text, mapped))
      index_maps_step(fresh, index, mapped, rest, pool, mapping, next, maps, extra)

@unsafe def index_maps_step(+fresh: Bool, +index: U32, +mapped: String, +rest: +List<U32>, +pool: +List<M.Constant>, +mapping: +List<M.NameMap>, +next: U32, +maps: +List<IndexMap>, +extra: +List<M.Constant>) -> Remap:
  match fresh:
    case True{}: index_maps(rest, pool, mapping, U32.add(next, 1), Con{IndexMap{index, next}, maps}, Con{M.Utf{mapped}, extra})
    case False{}: index_maps(rest, pool, mapping, next, maps, extra)

@unsafe def remap_attributes(+attributes: +List<M.Attribute>, +maps: +List<IndexMap>) -> +List<M.Attribute>:
  match attributes:
    case Nil{}: Nil{}
    case Con{M.Attribute{+name, +bytes}, rest}:
      +index : U32 = mapped_index(maps, signature_index(bytes))
      Con{M.Attribute{name, Bool.pick(+List<U32>, String.eq(name, "Signature"), [U32.shrn(index, 8n), U32.and(index, 255)], bytes)}, remap_attributes(rest, maps)}
    case Con{M.ValidatedAnnotations{+metadata}, rest}: Con{M.ValidatedAnnotations{remap_metadata(metadata, maps)}, remap_attributes(rest, maps)}

@unsafe def remap_metadata(+metadata: M.AnnotationMetadata, +maps: +List<IndexMap>) -> M.AnnotationMetadata:
  match metadata:
    case M.AnnotationMetadata{+flags, +exceptions, +annotations, +parameters, +types, +default, +hidden, +hiddenParameters, +hiddenTypes}:
      M.AnnotationMetadata{flags, exceptions, remap_annotations(annotations, maps), remap_nested(parameters, maps), remap_types(types, maps), remap_default(default, maps), remap_annotations(hidden, maps), remap_nested(hiddenParameters, maps), remap_types(hiddenTypes, maps)}

@unsafe def remap_annotation(+annotation: M.Annotation, +maps: +List<IndexMap>) -> M.Annotation:
  match annotation:
    case M.Annotation{+kind, +elements}: M.Annotation{mapped_index(maps, kind), remap_elements(elements, maps)}

@unsafe def remap_annotations(+annotations: +List<M.Annotation>, +maps: +List<IndexMap>) -> +List<M.Annotation>:
  match annotations:
    case Nil{}: Nil{}
    case Con{+annotation, rest}: Con{remap_annotation(annotation, maps), remap_annotations(rest, maps)}

@unsafe def remap_nested(+lists: +List<+List<M.Annotation>>, +maps: +List<IndexMap>) -> +List<+List<M.Annotation>>:
  match lists:
    case Nil{}: Nil{}
    case Con{+annotations, rest}: Con{remap_annotations(annotations, maps), remap_nested(rest, maps)}

@unsafe def remap_types(+annotations: +List<M.TypeAnnotation>, +maps: +List<IndexMap>) -> +List<M.TypeAnnotation>:
  match annotations:
    case Nil{}: Nil{}
    case Con{M.TypeAnnotation{+target, +info, +path, +annotation}, rest}: Con{M.TypeAnnotation{target, info, path, remap_annotation(annotation, maps)}, remap_types(rest, maps)}

@unsafe def remap_default(+found: Maybe<&2, M.AnnotationValue>, +maps: +List<IndexMap>) -> Maybe<&2, M.AnnotationValue>:
  match found:
    case None{}: None{}
    case Some{+value}: Some{remap_value(value, maps)}

@unsafe def remap_elements(+elements: +List<M.AnnotationElement>, +maps: +List<IndexMap>) -> +List<M.AnnotationElement>:
  match elements:
    case Nil{}: Nil{}
    case Con{M.AnnotationElement{+name, +value}, rest}: Con{M.AnnotationElement{name, remap_value(value, maps)}, remap_elements(rest, maps)}

@unsafe def remap_values(+values: +List<M.AnnotationValue>, +maps: +List<IndexMap>) -> +List<M.AnnotationValue>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: Con{remap_value(value, maps), remap_values(rest, maps)}

@unsafe def remap_value(+value: M.AnnotationValue, +maps: +List<IndexMap>) -> M.AnnotationValue:
  match value:
    case M.AnnotationEnum{+kind, +name}: M.AnnotationEnum{mapped_index(maps, kind), name}
    case M.AnnotationClass{+descriptor}: M.AnnotationClass{mapped_index(maps, descriptor)}
    case M.AnnotationNested{+kind, +elements}: M.AnnotationNested{mapped_index(maps, kind), remap_values(elements, maps)}
    case M.AnnotationElementValue{+name, +inner}: M.AnnotationElementValue{name, remap_value(inner, maps)}
    case M.AnnotationArray{+values}: M.AnnotationArray{remap_values(values, maps)}
    case M.AnnotationConst{+tag, +index}: M.AnnotationConst{tag, index}

# Class, NameAndType and MethodType entries get renamed Utf8 entries appended
# to the pool (a Utf8 may also be a string constant, which must not change).
@unsafe def rename_pool(+pool: +List<M.Constant>, +mapping: +List<M.NameMap>) -> +List<M.Constant>:
  rename_pool_go(pool, pool, mapping, 0, M.length(M.Constant, pool), Nil{}, Nil{})

@unsafe def pool_text(+pool: +List<M.Constant>, +index: U32) -> String:
  pool_text_found(M.nth(M.Constant, pool, index))

@unsafe def pool_text_found(found: Maybe<&2, M.Constant>) -> String:
  match found:
    case Some{M.Utf{text}}: text
    case _: ""

@unsafe def rename_pool_go(+entries: +List<M.Constant>, +pool: +List<M.Constant>, +mapping: +List<M.NameMap>, +index: U32, +next: U32, +acc: +List<M.Constant>, +extra: +List<M.Constant>) -> +List<M.Constant>:
  match entries:
    case Nil{}: M.append(M.Constant, M.reverse(M.Constant, acc), M.reverse(M.Constant, extra))
    case Con{M.Index{7, +name}, rest}:
      rename_entry(pool_text(pool, name), map_class_text(pool_text(pool, name), mapping), M.Index{7, name}, M.Index{7, next}, rest, pool, mapping, index, next, acc, extra)
    case Con{M.Index{16, +descriptor}, rest}:
      rename_entry(pool_text(pool, descriptor), map_descriptor_text(pool_text(pool, descriptor), mapping), M.Index{16, descriptor}, M.Index{16, next}, rest, pool, mapping, index, next, acc, extra)
    case Con{M.PairIndex{12, +name, +descriptor}, rest}:
      rename_entry(pool_text(pool, descriptor), map_descriptor_text(pool_text(pool, descriptor), mapping), M.PairIndex{12, name, descriptor}, M.PairIndex{12, name, next}, rest, pool, mapping, index, next, acc, extra)
    case Con{+entry, rest}: rename_pool_go(rest, pool, mapping, U32.add(index, 1), next, Con{entry, acc}, extra)

@unsafe def rename_entry(+old: String, +new: String, +kept: M.Constant, +moved: M.Constant, +rest: +List<M.Constant>, +pool: +List<M.Constant>, +mapping: +List<M.NameMap>, +index: U32, +next: U32, +acc: +List<M.Constant>, +extra: +List<M.Constant>) -> +List<M.Constant>:
  rename_entry_select(String.eq(old, new), new, kept, moved, rest, pool, mapping, index, next, acc, extra)

@unsafe def rename_entry_select(same: Bool, +new: String, +kept: M.Constant, +moved: M.Constant, +rest: +List<M.Constant>, +pool: +List<M.Constant>, +mapping: +List<M.NameMap>, +index: U32, +next: U32, +acc: +List<M.Constant>, +extra: +List<M.Constant>) -> +List<M.Constant>:
  match same:
    case True{}: rename_pool_go(rest, pool, mapping, U32.add(index, 1), next, Con{kept, acc}, extra)
    case False{}: rename_pool_go(rest, pool, mapping, U32.add(index, 1), U32.add(next, 1), Con{moved, acc}, Con{M.Utf{new}, extra})

# Class.forName(name, initialize, loader) with a user loader asks the loader.
@unsafe def for_name_user(+vm: M.VM, +name_ref: U32, +initialize: Bool, +loader: U32) -> Result<&2, &2, String, O.Outcome>:
  L.call_virtual(L.push_cont(vm, M.NeedForName{initialize}), L.virtual_on(vm, loader, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;"), [M.Slot{3, loader}, M.Slot{3, name_ref}])

@unsafe def continue_for_name(+vm: M.VM, +initialize: Bool, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match initialize:
    case False{}: L.ref_out(vm, bits(value))
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), bits(value))
        +result : O.Outcome <- L.class_for_name_init(vm, L.entry_element(entry))
        return result

# --- Resources through user loaders ---
# getResource: the parent's resource (or the system class path for a null
# parent), else findResource; getResourceAsStream opens getResource's URL.

@unsafe def loader_get_resource(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name_ref : U32 <- arg_ref(args, 1)
    +result : O.Outcome <- resource_from(U32.is_eq(receiver, L.system_loader_reference()), vm, receiver, name_ref)
    return result

@unsafe def resource_from(system: Bool, +vm: M.VM, +receiver: U32, +name_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  match system:
    case True{}: L.class_loader_resource_url(vm, [M.Slot{3, receiver}, M.Slot{3, name_ref}])
    case False{}: resource_parent(parent_of(vm, receiver), vm, receiver, name_ref)

@unsafe def resource_parent(+parent: U32, +vm: M.VM, +receiver: U32, +name_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  +asked : U32 = Bool.pick(U32, U32.is_eq(parent, 0), L.system_loader_reference(), parent)
  virtual_call(L.push_cont(vm, M.NeedResourceParent{receiver, name_ref}), asked, "getResource", "(Ljava/lang/String;)Ljava/net/URL;", [M.Slot{3, asked}, M.Slot{3, name_ref}])

@unsafe def continue_resource_parent(+vm: M.VM, +receiver: U32, +name_ref: U32, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  continue_resource_found(bits(value), vm, receiver, name_ref)

@unsafe def continue_resource_found(+found: U32, +vm: M.VM, +receiver: U32, +name_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case 0: virtual_call(vm, receiver, "findResource", "(Ljava/lang/String;)Ljava/net/URL;", [M.Slot{3, receiver}, M.Slot{3, name_ref}])
    case +url: L.ref_out(vm, url)

@unsafe def loader_find_resource(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.ref_out(vm, 0)

@unsafe def loader_resource_stream(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name_ref : U32 <- arg_ref(args, 1)
    +result : O.Outcome <- stream_from(U32.is_eq(receiver, L.system_loader_reference()), vm, receiver, name_ref)
    return result

@unsafe def stream_from(system: Bool, +vm: M.VM, +receiver: U32, +name_ref: U32) -> Result<&2, &2, String, O.Outcome>:
  match system:
    case True{}: L.class_loader_resource_stream(vm, [M.Slot{3, receiver}, M.Slot{3, name_ref}])
    case False{}: virtual_call(L.push_cont(vm, M.NeedResourceStream{}), receiver, "getResource", "(Ljava/lang/String;)Ljava/net/URL;", [M.Slot{3, receiver}, M.Slot{3, name_ref}])

@unsafe def continue_resource_stream(+vm: M.VM, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  continue_stream_found(bits(value), vm)

@unsafe def continue_stream_found(+found: U32, +vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case 0: L.ref_out(vm, 0)
    case +url: virtual_call(vm, url, "openStream", "()Ljava/io/InputStream;", [M.Slot{3, url}])

# Class.forName(name) uses the caller's defining loader; the three-argument
# form uses the given loader. User loaders are asked through loadClass.
@unsafe def for_name(+vm: M.VM, +args: +List<M.Slot>, +explicit: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +name_ref : U32 <- arg_ref(args, 0)
    +initialize : U32 <- Bool.pick(Result<&2, &2, String, U32>, explicit, arg_ref(args, 1), Done{1})
    +loader : U32 <- Bool.pick(Result<&2, &2, String, U32>, explicit, arg_ref(args, 2), Done{caller_loader(vm)})
    +user : Bool = U32.is_ne(loader, 0) && U32.is_ne(loader, L.system_loader_reference())
    +result : O.Outcome <- for_name_select(user, vm, args, name_ref, U32.is_ne(initialize, 0), loader)
    return result

@unsafe def for_name_select(user: Bool, +vm: M.VM, +args: +List<M.Slot>, +name_ref: U32, +initialize: Bool, +loader: U32) -> Result<&2, &2, String, O.Outcome>:
  match user:
    case False{}: L.class_for_name(vm, args)
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        checked : Unit <- S.check(U32.is_ne(name_ref, 0), L.npe())
        +result : O.Outcome <- for_name_user(vm, name_ref, initialize, loader)
        return result

@unsafe def caller_loader(+vm: M.VM) -> U32:
  caller_loader_found(LS.defined_loader(LS.state_defined(S.loaders(vm)), L.caller_owner(vm)))

@unsafe def caller_loader_found(found: Maybe<&2, U32>) -> U32:
  match found:
    case None{}: L.system_loader_reference()
    case Some{loader}: loader
