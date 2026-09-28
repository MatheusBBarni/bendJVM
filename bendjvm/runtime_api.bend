import Base
import ./model.bend as M
import ./runtime/state.bend as S
import ./runtime/execute.bend as X
import ./loader/symbols.bend as Sy
import ./heap/heap.bend as H

type ArgumentAllocation is Data:
  ArgumentAllocation{vm: M.VM, values: +List<M.Slot>}

type ArrayAllocation is Data:
  ArrayAllocation{vm: M.VM, reference: U32}
def method_locals(value: M.LoadedMethod) -> +List<M.Slot>:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      M.zeros(U32.to_nat(maxLocals))

def method_locals_args(value: M.LoadedMethod, argument: M.Slot) -> +List<M.Slot>:
  M.replace(M.Slot, method_locals(value), 0n, argument)

def start_class_chain_parent(fuel: Nat, +vm: M.VM, parent: U32, +tail: +List<M.Frame>, next: M.VM -> U32 -> +List<M.Frame> -> M.VM) -> M.VM:
  match parent:
    case 4294967295: S.with_frames(vm, tail)
    case parent_id: next(vm, parent_id, tail)

def start_class_chain_method(fuel: Nat, +vm: M.VM, +id: U32, parent: U32, +tail: +List<M.Frame>, result: Maybe<&2, M.LoadedMethod>, next: M.VM -> U32 -> +List<M.Frame> -> M.VM) -> M.VM:
  match result:
    case None{}: S.fail(vm, "NoSuchMethodError: <clinit>")
    case Some{+method}:
      +updated : M.VM = S.set_class_state(vm, id, 1)
      +frame : M.Frame = M.Frame{M.loaded_method_id(method), 0, 0, method_locals(method), Nil{}, id}
      +next_tail : +List<M.Frame> = Con{frame, tail}
      start_class_chain_parent(fuel, updated, parent, next_tail, next)
def start_class_chain_initializer(fuel: Nat, +vm: M.VM, id: U32, parent: U32, initializer: U32, +tail: +List<M.Frame>, next: M.VM -> U32 -> +List<M.Frame> -> M.VM) -> M.VM:
  match initializer:
    case 4294967295:
      +updated : M.VM = S.set_class_state(vm, id, 2)
      start_class_chain_parent(fuel, updated, parent, tail, next)
    case method_id:
      start_class_chain_method(fuel, vm, id, parent, tail, M.nth(M.LoadedMethod, S.methods(vm), method_id), next)


def start_class_chain_state(fuel: Nat, +vm: M.VM, id: U32, +parent: U32, initializer: U32, +state: U32, +tail: +List<M.Frame>, next: M.VM -> U32 -> +List<M.Frame> -> M.VM) -> M.VM:
  +failed : Bool = U32.is_eq(state, 3)
  +ready : Bool = U32.is_eq(state, 1) || U32.is_eq(state, 2)
  +fresh : Bool = U32.is_eq(state, 0)
  Bool.pick(M.VM, failed, S.fail(vm, "NoClassDefFoundError"),
    Bool.pick(M.VM, ready, S.with_frames(vm, tail),
      Bool.pick(M.VM, fresh, start_class_chain_initializer(fuel, vm, id, parent, initializer, tail, next), S.fail(vm, "NoClassDefFoundError"))))

def start_class_chain_class(fuel: Nat, +vm: M.VM, +tail: +List<M.Frame>, class: M.LoadedClass, next: M.VM -> U32 -> +List<M.Frame> -> M.VM) -> M.VM:
  match class:
    case M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state}:
      start_class_chain_state(fuel, vm, id, parent, initializer, state, tail, next)

def start_class_chain_found(fuel: Nat, +vm: M.VM, owner: U32, +tail: +List<M.Frame>, found: Maybe<&2, M.LoadedClass>, next: M.VM -> U32 -> +List<M.Frame> -> M.VM) -> M.VM:
  match found:
    case None{}: S.fail(vm, "NoClassDefFoundError")
    case Some{class}: start_class_chain_class(fuel, vm, tail, class, next)

def start_class_chain(fuel: Nat, +vm: M.VM, +owner: U32, +tail: +List<M.Frame>) -> M.VM:
  match fuel:
    case 0n: S.fail(vm, "NoClassDefFoundError")
    case 1n+ +remaining:
      start_class_chain_found(remaining, vm, owner, tail, M.nth(M.LoadedClass, S.classes(vm), owner),
        next_vm => next_owner => +next_tail => start_class_chain(remaining, next_vm, next_owner, next_tail))

def start_class(+vm: M.VM, mainFrame: M.Frame, owner: U32) -> M.VM:
  start_class_chain(256n, vm, owner, [mainFrame])

def entry_match(+method: M.LoadedMethod, +symbols: +List<String>) -> Bool:
  Bool.and(String.eq(Sy.text(symbols, M.loaded_method_name(method)), "main"), String.eq(Sy.text(symbols, M.loaded_method_descriptor(method)), "([Ljava/lang/String;)V"))

def public_static_entry(+method: M.LoadedMethod, +symbols: +List<String>) -> Bool:
  match method:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      Bool.and(U32.is_eq(U32.and(flags, 9), 9), entry_match(method, symbols))

def entry_method(methods: +List<M.LoadedMethod>, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, entry_match(method, symbols), Some{method}, entry_method(rest, symbols))

def entry_class(classes: +List<M.LoadedClass>, +symbols: +List<String>, +name: String) -> Maybe<&2, U32>:
  match classes:
    case Nil{}: None{}
    case Con{+class, rest}:
      Bool.pick(Maybe<&2, U32>, String.eq(Sy.text(symbols, M.loaded_class_name(class)), name), Some{M.loaded_class_id(class)}, entry_class(rest, symbols, name))

def entry_method_owner(methods: +List<M.LoadedMethod>, +symbols: +List<String>, +owner: U32) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      match method:
        case M.LoadedMethod{id, method_owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
          Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(method_owner, owner) && public_static_entry(method, symbols), Some{method}, entry_method_owner(rest, symbols, owner))

def start_found_args(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>, +argument: M.Slot) -> M.VM:
  match found:
    case None{}: S.fail(vm, "NoSuchMethodError: main")
    case Some{+method}:
      +id = M.loaded_method_id(method)
      +owner = M.loaded_method_owner(method)
      start_class(vm, M.Frame{id, 0, 0, method_locals_args(method, argument), Nil{}, 4294967295}, owner)

def start_found(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>) -> M.VM:
  match found:
    case None{}: S.fail(vm, "NoSuchMethodError: main")
    case Some{+method}:
      +id = M.loaded_method_id(method)
      +owner = M.loaded_method_owner(method)
      start_class(vm, M.Frame{id, 0, 0, method_locals(method), Nil{}, 4294967295}, owner)

def start_loaded(+vm: M.VM) -> M.VM:
  start_found(vm, entry_method(S.methods(vm), S.symbols(vm)))

def string_units(values: +List<Char>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{+head, tail}: Con{Char.to_u32(head), string_units(tail)}
def allocation_parts(allocation: H.Allocation, +acc: +List<M.Slot>) -> ArgumentAllocation:
  match allocation:
    case H.Allocation{updated, reference}:
      ArgumentAllocation{updated, Con{M.Slot{3, reference}, acc}}

def argument_vm(value: ArgumentAllocation) -> M.VM:
  ArgumentAllocation{vm, values} = value
  vm

def argument_values(value: ArgumentAllocation) -> +List<M.Slot>:
  ArgumentAllocation{vm, values} = value
  values

def allocate_argument_strings(args: +List<String>, +vm: M.VM, +acc: +List<M.Slot>) -> Result<&2, &2, String, ArgumentAllocation>:
  match args:
    case Nil{}:
      Done{ArgumentAllocation{vm, M.reverse(M.Slot, acc)}}
    case Con{arg, rest}:
      do Result<&2, &2, String, ArgumentAllocation>:
        allocation : H.Allocation <- H.allocate(vm, H.string_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/String"), string_units(String.to_list(arg))))
        +parts : ArgumentAllocation = allocation_parts(allocation, acc)
        result : ArgumentAllocation <- allocate_argument_strings(rest, argument_vm(parts), argument_values(parts))
        return result

def allocate_argument_array_allocation(+vm: M.VM, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, ArrayAllocation>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{allocation_value}:
      match allocation_value:
        case H.Allocation{updated, reference}: Done{ArrayAllocation{updated, reference}}

def allocate_argument_array(+vm: M.VM, +values: +List<M.Slot>) -> Result<&2, &2, String, ArrayAllocation>:
  allocate_argument_array_allocation(vm, H.allocate(vm, H.reference_array_entry(H.named_class(S.classes(vm), S.symbols(vm), "[Ljava/lang/String;"), H.named_class(S.classes(vm), S.symbols(vm), "java/lang/String"), values)))

def class_id_or_missing_found(found: Maybe<&2, U32>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{id}: id

def class_id_or_missing(classes: +List<M.LoadedClass>, symbols: +List<String>, name: String) -> U32:
  class_id_or_missing_found(entry_class(classes, symbols, name))
def start_array_alloc(+vm: M.VM, name: String, result: Result<&2, &2, String, ArrayAllocation>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{array_value}:
      match array_value:
        case ArrayAllocation{+with_array, reference}:
          start_found_args(with_array, entry_method_owner(S.methods(with_array), S.symbols(with_array), class_id_or_missing(S.classes(with_array), S.symbols(with_array), name)), M.Slot{3, reference})

def start_entry_alloc(+vm: M.VM, name: String, +args: +List<String>, allocated: Result<&2, &2, String, ArgumentAllocation>) -> M.VM:
  match allocated:
    case Fail{error}: S.fail(vm, error)
    case Done{argument_value}:
      match argument_value:
        case ArgumentAllocation{+updated, values}:
          start_array_alloc(updated, name, allocate_argument_array(updated, values))


def start_loaded_entry(+vm: M.VM, name: String, +args: +List<String>) -> M.VM:
  start_entry_alloc(vm, name, args, allocate_argument_strings(args, vm, Nil{}))

def run_loaded(+vm: M.VM, fuel: Nat) -> M.VM:
  X.run(start_loaded(vm), fuel)

def run_loaded_entry(+vm: M.VM, fuel: Nat, entryBinaryName: String, applicationArgs: +List<String>) -> M.VM:
  X.run(start_loaded_entry(vm, entryBinaryName, applicationArgs), fuel)

def continue_run(vm: M.VM, fuel: Nat) -> M.VM:
  X.continue_run(vm, fuel)

def resume_ok(+vm: M.VM, handle: U32, extra: U32, bytes: +List<U32>) -> M.VM:
  X.resume_ok(vm, handle, extra, bytes)

def resume_fail(+vm: M.VM, name: String) -> M.VM:
  X.resume_fail(vm, name)

def make_vm() -> M.VM:
  M.VM{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, 0, 0, M.Slot{0, 0}, Nil{}, "", 1, 0n, M.idle_host()}

def keep_host_api(vm: M.VM) -> M.VM:
  continue_run(resume_ok(resume_fail(vm, ""), 0, 0, Nil{}), 0n)

def main() -> IO(Unit):
  result = run_loaded_entry(keep_host_api(make_vm()), 1n, "", Nil{})
  IO.print(U32.show(S.status(result)))
