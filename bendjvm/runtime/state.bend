import Base
import ../model.bend as M

def classes(vm: M.VM) -> +List<M.LoadedClass>:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  cs

def methods(vm: M.VM) -> +List<M.LoadedMethod>:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  ms

def fields(vm: M.VM) -> +List<M.LoadedField>:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  fs

def symbols(vm: M.VM) -> +List<String>:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  sy

def heap(vm: M.VM) -> +List<M.HeapEntry>:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  hp

def statics(vm: M.VM) -> +List<M.Binding>:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  st

def frames(vm: M.VM) -> +List<M.Frame>:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  fr

def status(vm: M.VM) -> U32:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  stt

def max_heap(vm: M.VM) -> U32:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  max

def output(vm: M.VM) -> +List<String>:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  out

def error(vm: M.VM) -> String:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  err

def with_classes(vm: M.VM, value: +List<M.LoadedClass>) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{value, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps}

def with_heap(vm: M.VM, value: +List<M.HeapEntry>) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{cs, ms, fs, sy, value, st, fr, stt, ex, result, out, err, max, steps}

def with_statics(vm: M.VM, value: +List<M.Binding>) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{cs, ms, fs, sy, hp, value, fr, stt, ex, result, out, err, max, steps}

def with_frames(vm: M.VM, value: +List<M.Frame>) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{cs, ms, fs, sy, hp, st, value, stt, ex, result, out, err, max, steps}

def with_status(vm: M.VM, value: U32) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{cs, ms, fs, sy, hp, st, fr, value, ex, result, out, err, max, steps}

def with_result(vm: M.VM, value: M.Slot) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, value, out, err, max, steps}
def result_slot(vm: M.VM) -> M.Slot:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, value, out, err, max, steps} = vm
  value


def with_exception(vm: M.VM, value: U32) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, value, result, out, err, max, steps}

def emit(vm: M.VM, line: String) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, Con{line, out}, err, max, steps}

def fail(vm: M.VM, message: String) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{cs, ms, fs, sy, hp, st, fr, 4, ex, result, out, message, max, steps}

def tick(vm: M.VM) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, steps} = vm
  M.VM{cs, ms, fs, sy, hp, st, fr, stt, ex, result, out, err, max, 1n+steps}

def method_id(frame: M.Frame) -> U32:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  method

def pc(frame: M.Frame) -> U32:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  pc0

def invoke_pc(frame: M.Frame) -> U32:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  invoke

def stack(frame: M.Frame) -> +List<M.Slot>:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  stk

def locals(frame: M.Frame) -> +List<M.Slot>:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  ls

def initializing(frame: M.Frame) -> U32:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  init

def frame_stack(frame: M.Frame, value: +List<M.Slot>) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  M.Frame{method, pc0, invoke, ls, value, init}

def frame_locals(frame: M.Frame, value: +List<M.Slot>) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  M.Frame{method, pc0, invoke, value, stk, init}

def frame_pc(frame: M.Frame, value: U32) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  M.Frame{method, value, invoke, ls, stk, init}

def advance(frame: M.Frame) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  M.Frame{method, U32.add(pc0, 1), invoke, ls, stk, init}

def suspended(frame: M.Frame) -> M.Frame:
  M.Frame{method, +pc0, invoke, ls, stk, init} = frame
  M.Frame{method, U32.add(pc0, 1), pc0, ls, stk, init}

def retrying(frame: M.Frame) -> M.Frame:
  M.Frame{method, +pc0, invoke, ls, stk, init} = frame
  M.Frame{method, pc0, pc0, ls, stk, init}

def restore_invoke(frame: M.Frame) -> M.Frame:
  M.Frame{method, pc0, +invoke, ls, stk, init} = frame
  M.Frame{method, invoke, invoke, ls, stk, init}

def location(frame: M.Frame, opcode: U32) -> String:
  M.Frame{method, pc0, invoke, ls, stk, init} = frame
  " opcode=" ++ U32.show(opcode) ++ " pc=" ++ U32.show(pc0) ++ " method=" ++ U32.show(method)

def commit_frames(vm: M.VM, frame: M.Frame, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}:
      fail(vm, "InvalidState: no current frame")
    case Con{old, rest}:
      with_frames(vm, Con{frame, rest})

def commit(+vm: M.VM, frame: M.Frame) -> M.VM:
  commit_frames(vm, frame, frames(vm))

def require(-A: Data, value: Maybe<&2, A>, error: String) -> Result<&2, &2, String, A>:
  match value:
    case None{}:
      Fail{error}
    case Some{x}:
      Done{x}

def check(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}:
      Done{Unit{}}
    case False{}:
      Fail{message}

def class_state(class: M.LoadedClass, state: U32) -> M.LoadedClass:
  M.LoadedClass{id, name, parent, interfaces, fs, ms, initializer, old} = class
  M.LoadedClass{id, name, parent, interfaces, fs, ms, initializer, state}

def change_class_state(vm: M.VM, id: U32, state: U32, class: Maybe<&2, M.LoadedClass>) -> M.VM:
  match class:
    case None{}:
      fail(vm, "MissingClass: initialization state")
    case Some{value}:
      +v = vm
      with_classes(v, M.replace(M.LoadedClass, classes(v), U32.to_nat(id), class_state(value, state)))

def set_class_state(+vm: M.VM, +id: U32, state: U32) -> M.VM:
  change_class_state(vm, id, state, M.nth(M.LoadedClass, classes(vm), id))
