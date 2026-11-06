import Base
import ../model.bend as M
import ./state.bend as S
import ../heap/heap.bend as H

# Stack traces (plan 05). A throwable records where it was created as
# (method id, bytecode offset) pairs in its heap entry's `values`, innermost
# first, like Throwable.fillInStackTrace. A callee frame's invokePc is its
# caller's call site, so each caller's location comes from the frame above it.

def instruction_offset(found: Maybe<&2, M.Instruction>) -> U32:
  match found:
    case Some{M.Instruction{op, a, b, c, offset}}: offset
    case None{}: 4294967295

def method_offset(found: Maybe<&2, M.LoadedMethod>, +pc: U32) -> U32:
  match found:
    case Some{M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}}:
      instruction_offset(M.nth(M.Instruction, instructions, pc))
    case None{}: 4294967295

def frames_trace(frames: +List<M.Frame>, +methods: +List<M.LoadedMethod>, +site: U32, +top: Bool) -> +List<M.Slot>:
  match frames:
    case Nil{}: Nil{}
    case Con{+frame, rest}:
      +method : U32 = S.method_id(frame)
      +pc : U32 = Bool.pick(U32, top, S.pc(frame), site)
      Con{M.Slot{1, method}, Con{M.Slot{1, method_offset(M.nth(M.LoadedMethod, methods, method), pc)}, frames_trace(rest, methods, S.invoke_pc(frame), False{})}}

# The running thread's current call stack.
def capture(+vm: M.VM) -> +List<M.Slot>:
  frames_trace(S.frames(vm), S.methods(vm), 0, True{})

def with_values(entry: M.HeapEntry, +values: +List<M.Slot>) -> M.HeapEntry:
  match entry:
    case M.HeapEntry{class, kind, element, fields, old, chars}: M.HeapEntry{class, kind, element, fields, values, chars}

# A throwable entry carrying the current stack as its trace.
def traced(+vm: M.VM, entry: M.HeapEntry) -> M.HeapEntry:
  with_values(entry, capture(vm))

# The offset recorded for a frame of a MiniJRE intrinsic (it has no bytecode).
def native_offset() -> U32:
  4294967295

def prepend_native(entry: M.HeapEntry, +method: U32) -> M.HeapEntry:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}:
      M.HeapEntry{class, kind, element, fields, Con{M.Slot{1, method}, Con{M.Slot{1, native_offset()}, values}}, chars}

def native_found(+vm: M.VM, +reference: U32, +method: U32, found: Result<&2, &2, String, M.HeapEntry>) -> M.VM:
  match found:
    case Done{entry}: H.put(vm, reference, prepend_native(entry, method))
    case Fail{error}: vm

# The pending exception was raised inside intrinsic `method`.
def with_native_frame(+vm: M.VM, +method: U32) -> M.VM:
  native_found(vm, S.exception(vm), method, H.get(S.heap(vm), S.exception(vm)))
