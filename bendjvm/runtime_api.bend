import Base
import ./model.bend as M
import ./runtime/state.bend as S
import ./runtime/execute.bend as X
import ./loader/symbols.bend as Sy

def method_locals(value: M.LoadedMethod) -> +List<M.Slot>:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      M.zeros(U32.to_nat(maxLocals))

def start_initializer_found(+vm: M.VM, mainFrame: M.Frame, +owner: U32, found: Maybe<&2, M.LoadedMethod>) -> M.VM:
  match found:
    case None{}: S.with_frames(vm, [mainFrame])
    case Some{+method}:
      +id = M.loaded_method_id(method)
      +updated = S.set_class_state(vm, owner, 1)
      S.with_frames(updated, [M.Frame{id, 0, 0, method_locals(method), Nil{}, owner}, mainFrame])

def start_initializer_method(+vm: M.VM, mainFrame: M.Frame, owner: U32, initializer: U32) -> M.VM:
  start_initializer_found(vm, mainFrame, owner, M.nth(M.LoadedMethod, S.methods(vm), initializer))

def start_class_found(+vm: M.VM, mainFrame: M.Frame, found: Maybe<&2, M.LoadedClass>) -> M.VM:
  match found:
    case None{}: S.with_frames(vm, [mainFrame])
    case Some{class}:
      M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state} = class
      match initializer:
        case 4294967295: S.with_frames(vm, [mainFrame])
        case value: start_initializer_method(vm, mainFrame, id, value)

def start_class(+vm: M.VM, mainFrame: M.Frame, owner: U32) -> M.VM:
  start_class_found(vm, mainFrame, M.nth(M.LoadedClass, S.classes(vm), owner))

def entry_match(+method: M.LoadedMethod, +symbols: +List<String>) -> Bool:
  Bool.and(String.eq(Sy.text(symbols, M.loaded_method_name(method)), "main"), String.eq(Sy.text(symbols, M.loaded_method_descriptor(method)), "([Ljava/lang/String;)V"))

def entry_method(methods: +List<M.LoadedMethod>, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, entry_match(method, symbols), Some{method}, entry_method(rest, symbols))
def start_found(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>) -> M.VM:
  match found:
    case None{}: S.fail(vm, "NoSuchMethodError: main")
    case Some{+method}:
      +id = M.loaded_method_id(method)
      +owner = M.loaded_method_owner(method)
      start_class(vm, M.Frame{id, 0, 0, method_locals(method), Nil{}, 4294967295}, owner)

def start_loaded(+vm: M.VM) -> M.VM:
  start_found(vm, entry_method(S.methods(vm), S.symbols(vm)))

def run_loaded(+vm: M.VM, fuel: Nat) -> M.VM:
  X.run(start_loaded(vm), fuel)

def make_vm() -> M.VM:
  M.VM{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, 0, 0, M.Slot{0, 0}, Nil{}, "", 1, 0n}

def main() -> IO(Unit):
  result = run_loaded(make_vm(), 1n)
  IO.print(U32.show(S.status(result)))
