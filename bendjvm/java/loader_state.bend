import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../loader/class_loader.bend as CL
import ../loader/symbols.bend as Sy

# Class loader namespace state (plan 03, C6): aliases, defining loaders,
# deferred verification and names being defined. See java/loaders.bend.

def none() -> U32:
  4294967295

@unsafe def class_text(+vm: M.VM, +class: U32) -> String:
  class_text_found(M.nth(M.LoadedClass, S.classes(vm), class), S.symbols(vm))

@unsafe def class_text_found(found: Maybe<&2, M.LoadedClass>, +symbols: +List<String>) -> String:
  match found:
    case None{}: ""
    case Some{value}: Sy.text(symbols, M.loaded_class_name(value))

# --- Loader state ---

@unsafe def state_aliases(+state: M.Loaders) -> +List<M.LoaderAlias>:
  match state:
    case M.Loaders{next, aliases, defined, pending, defining}: aliases

@unsafe def state_defined(+state: M.Loaders) -> +List<M.DefinedClass>:
  match state:
    case M.Loaders{next, aliases, defined, pending, defining}: defined

@unsafe def state_pending(+state: M.Loaders) -> +List<M.PendingVerify>:
  match state:
    case M.Loaders{next, aliases, defined, pending, defining}: pending

@unsafe def state_defining(+state: M.Loaders) -> +List<M.DefiningName>:
  match state:
    case M.Loaders{next, aliases, defined, pending, defining}: defining

@unsafe def alias_find(+aliases: +List<M.LoaderAlias>, +namespace: U32, +name: String) -> Maybe<&2, U32>:
  match aliases:
    case Nil{}: None{}
    case Con{M.LoaderAlias{+space, +alias, +target}, rest}: alias_step(U32.is_eq(space, namespace) && String.eq(alias, name), target, rest, namespace, name)

@unsafe def alias_step(hit: Bool, +target: U32, +rest: +List<M.LoaderAlias>, +namespace: U32, +name: String) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{target}
    case False{}: alias_find(rest, namespace, name)

@unsafe def defining_find(+values: +List<M.DefiningName>, +namespace: U32, +name: String) -> Maybe<&2, String>:
  match values:
    case Nil{}: None{}
    case Con{M.DefiningName{+space, +defined, +internal}, rest}: defining_step(U32.is_eq(space, namespace) && String.eq(defined, name), internal, rest, namespace, name)

@unsafe def defining_step(hit: Bool, +internal: String, +rest: +List<M.DefiningName>, +namespace: U32, +name: String) -> Maybe<&2, String>:
  match hit:
    case True{}: Some{internal}
    case False{}: defining_find(rest, namespace, name)

@unsafe def internal_in_progress(+values: +List<M.DefiningName>, +internal: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{M.DefiningName{+space, +defined, +candidate}, rest}: String.eq(candidate, internal) || internal_in_progress(rest, internal)

# The defining loader of a user-defined class, if any.
@unsafe def defined_loader(+values: +List<M.DefinedClass>, +class: U32) -> Maybe<&2, U32>:
  match values:
    case Nil{}: None{}
    case Con{M.DefinedClass{+id, +loader}, rest}: defined_step(U32.is_eq(id, class), loader, rest, class)

@unsafe def defined_step(hit: Bool, +loader: U32, +rest: +List<M.DefinedClass>, +class: U32) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{loader}
    case False{}: defined_loader(rest, class)

@unsafe def pending_find(+values: +List<M.PendingVerify>, +class: U32) -> Maybe<&2, M.ClassFile>:
  match values:
    case Nil{}: None{}
    case Con{M.PendingVerify{+id, +file}, rest}: pending_step(U32.is_eq(id, class), file, rest, class)

@unsafe def pending_step(hit: Bool, +file: M.ClassFile, +rest: +List<M.PendingVerify>, +class: U32) -> Maybe<&2, M.ClassFile>:
  match hit:
    case True{}: Some{file}
    case False{}: pending_find(rest, class)

@unsafe def pending_without(+values: +List<M.PendingVerify>, +class: U32) -> +List<M.PendingVerify>:
  match values:
    case Nil{}: Nil{}
    case Con{M.PendingVerify{+id, +file}, rest}:
      +tail : +List<M.PendingVerify> = pending_without(rest, class)
      Bool.pick(+List<M.PendingVerify>, U32.is_eq(id, class), tail, Con{M.PendingVerify{id, file}, tail})

@unsafe def defining_without(+values: +List<M.DefiningName>, +namespace: U32, +name: String) -> +List<M.DefiningName>:
  match values:
    case Nil{}: Nil{}
    case Con{M.DefiningName{+space, +defined, +internal}, rest}:
      +tail : +List<M.DefiningName> = defining_without(rest, namespace, name)
      Bool.pick(+List<M.DefiningName>, U32.is_eq(space, namespace) && String.eq(defined, name), tail, Con{M.DefiningName{space, defined, internal}, tail})

@unsafe def update_state(+vm: M.VM, +next: U32, +aliases: +List<M.LoaderAlias>, +defined: +List<M.DefinedClass>, +pending: +List<M.PendingVerify>, +defining: +List<M.DefiningName>) -> M.VM:
  S.with_loaders(vm, M.Loaders{next, aliases, defined, pending, defining})

@unsafe def state_next(+state: M.Loaders) -> U32:
  match state:
    case M.Loaders{next, aliases, defined, pending, defining}: next

@unsafe def with_alias(+vm: M.VM, +namespace: U32, +name: String, +target: U32) -> M.VM:
  +state : M.Loaders = S.loaders(vm)
  update_state(vm, state_next(state), Con{M.LoaderAlias{namespace, name, target}, state_aliases(state)}, state_defined(state), state_pending(state), state_defining(state))

@unsafe def with_defined_class(+vm: M.VM, +class: U32, +loader: U32, +file: M.ClassFile) -> M.VM:
  +state : M.Loaders = S.loaders(vm)
  update_state(vm, state_next(state), state_aliases(state), Con{M.DefinedClass{class, loader}, state_defined(state)}, Con{M.PendingVerify{class, file}, state_pending(state)}, state_defining(state))

@unsafe def with_defining(+vm: M.VM, +namespace: U32, +name: String, +internal: String) -> M.VM:
  +state : M.Loaders = S.loaders(vm)
  update_state(vm, state_next(state), state_aliases(state), state_defined(state), state_pending(state), Con{M.DefiningName{namespace, name, internal}, state_defining(state)})

@unsafe def without_defining(+vm: M.VM, +namespace: U32, +name: String) -> M.VM:
  +state : M.Loaders = S.loaders(vm)
  update_state(vm, state_next(state), state_aliases(state), state_defined(state), state_pending(state), defining_without(state_defining(state), namespace, name))

@unsafe def without_pending(+vm: M.VM, +class: U32) -> M.VM:
  +state : M.Loaders = S.loaders(vm)
  update_state(vm, state_next(state), state_aliases(state), state_defined(state), pending_without(state_pending(state), class), state_defining(state))

# --- Linking: deferred verification and loader identity ---

# Verify a user-defined class before its first initialization (JVMS 5.4.1):
# a failure is a VerifyError at that point, every time it is attempted.
@unsafe def verify_pending(+vm: M.VM, +class: U32) -> Result<&2, &2, String, M.VM>:
  verify_pending_found(pending_find(state_pending(S.loaders(vm)), class), vm, class)

@unsafe def verify_pending_found(found: Maybe<&2, M.ClassFile>, +vm: M.VM, +class: U32) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Done{vm}
    case Some{+file}: verify_pending_result(CL.verify_parsed([file], S.classes(vm), S.methods(vm), S.symbols(vm), S.metadata(vm)), vm, class)

@unsafe def verify_pending_result(result: Result<&2, &2, String, Unit>, +vm: M.VM, +class: U32) -> Result<&2, &2, String, M.VM>:
  match result:
    case Done{unit}: Done{without_pending(vm, class)}
    case Fail{+error}: Fail{Bool.pick(String, String.starts_with(error, "java/"), error, "java/lang/VerifyError: " ++ error)}

# Class.getClassLoader: the defining loader of a user-defined class (arrays
# report their element class's loader).
@unsafe def defining_loader_of(+vm: M.VM, +class: U32) -> Maybe<&2, U32>:
  defined_loader(state_defined(S.loaders(vm)), element_class(vm, class))

@unsafe def element_class(+vm: M.VM, +class: U32) -> U32:
  +name : String = class_text(vm, class)
  Bool.pick(U32, String.starts_with(name, "["), element_of_name(vm, name), class)

@unsafe def element_of_name(+vm: M.VM, +name: String) -> U32:
  match name:
    case SCon{Chr{91}, rest}: element_of_name(vm, rest)
    case SCon{Chr{76}, rest}: H.named_class(S.classes(vm), S.symbols(vm), CL.take_until_semicolon(rest, ""))
    case _: none()

