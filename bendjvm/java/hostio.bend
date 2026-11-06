import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ./outcome.bend as O
import ./library.bend as L

# sun.nio.ch.HostIO.call(op, handle, arg, data, off, len) (intrinsic 820, plan 05).
# One host-effect gateway for the Java-source NIO, socket-channel, selector and
# TLS classes: the request carries data[off, off+len) and the host's reply
# bytes are copied back into the same range before `call` returns its int.
# Only the calling thread parks; the scheduler keeps running the others.

def entry_values(entry: M.HeapEntry) -> +List<M.Slot>:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}: values

def slot_byte(slot: M.Slot) -> U32:
  U32.and(M.slot_bits(slot), 255)

def slot_bytes(slots: +List<M.Slot>) -> +List<U32>:
  match slots:
    case Nil{}: Nil{}
    case Con{slot, rest}: Con{slot_byte(slot), slot_bytes(rest)}

def range_ok(+off: U32, +len: U32, +size: U32) -> Bool:
  U32.is_le(off, size) && U32.is_le(len, U32.sub(size, off)) && U32.is_lt(off, 2147483648) && U32.is_lt(len, 2147483648)

def request_bytes(+vm: M.VM, +array: U32, +off: U32, +len: U32) -> Result<&2, &2, String, +List<U32>>:
  match array:
    case 0: Done{Nil{}}
    case _:
      do Result<&2, &2, String, +List<U32>>:
        entry : M.HeapEntry <- H.get(S.heap(vm), array)
        +values : +List<M.Slot> = entry_values(entry)
        checked : Unit <- S.check(range_ok(off, len, M.length(M.Slot, values)), "java/lang/IndexOutOfBoundsException")
        return slot_bytes(M.take(M.Slot, M.drop(M.Slot, values, U32.to_nat(off)), U32.to_nat(len)))

def call(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{1, +op}, Con{M.Slot{1, +handle}, Con{M.Slot{1, +arg}, Con{M.Slot{3, +array}, Con{M.Slot{1, +off}, Con{M.Slot{1, +len}, rest}}}}}}:
      do Result<&2, &2, String, O.Outcome>:
        data : +List<U32> <- request_bytes(vm, array, off, len)
        +effect : M.Effect = M.HostIO{op, handle, arg, data, array, off, len}
        return O.Suspend{S.with_status(S.with_effect(vm, effect), 5), effect}
    case _: Fail{"InvalidState: HostIO.call arguments"}

def sign_byte(+b: U32) -> M.Slot:
  M.Slot{1, Bool.pick(U32, U32.is_ge(U32.and(b, 255), 128), U32.or(U32.and(b, 255), 4294967040), U32.and(b, 255))}

def overwrite_here(bytes: +List<U32>, values: +List<M.Slot>) -> +List<M.Slot>:
  match bytes values:
    case Nil{} _: values
    case Con{b, more} Con{v, rest}: Con{sign_byte(b), overwrite_here(more, rest)}
    case _ Nil{}: Nil{}

def overwrite(off: Nat, values: +List<M.Slot>, bytes: +List<U32>) -> +List<M.Slot>:
  match off values:
    case 0n _: overwrite_here(bytes, values)
    case 1n+p Con{v, rest}: Con{v, overwrite(p, rest, bytes)}
    case 1n+p Nil{}: Nil{}

def fill_entry(+vm: M.VM, +array: U32, +off: U32, +len: U32, bytes: +List<U32>, entry: M.HeapEntry) -> M.VM:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}:
      H.put(vm, array, M.HeapEntry{class, kind, element, fields, overwrite(U32.to_nat(off), values, M.take(U32, bytes, U32.to_nat(len))), chars})

def fill_found(+vm: M.VM, +array: U32, +off: U32, +len: U32, bytes: +List<U32>, found: Result<&2, &2, String, M.HeapEntry>) -> M.VM:
  match found:
    case Fail{error}: vm
    case Done{entry}: fill_entry(vm, array, off, len, bytes, entry)

# Copies the host's reply into data[off, off+len) (at most len bytes).
def fill(+vm: M.VM, +array: U32, +off: U32, +len: U32, bytes: +List<U32>) -> M.VM:
  match array:
    case 0: vm
    case _: fill_found(vm, array, off, len, bytes, H.get(S.heap(vm), array))

