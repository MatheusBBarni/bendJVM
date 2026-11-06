import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../runtime/threads.bend as Th
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ./outcome.bend as O
import ./library.bend as L

# java.lang.Thread and Object monitor intrinsics (800-817, plan 05). They only
# change thread and monitor records; the scheduler resumes parked threads.

def park_out(+vm: M.VM, +wait: M.Wait, +timed: Bool, +deadline: M.Clock) -> Result<&2, &2, String, O.Outcome>:
  Done{O.Suspend{S.with_status(S.with_effect(Th.park(vm, wait, timed, deadline), M.Park{}), 5), M.Park{}}}

def receiver_ref(args: +List<M.Slot>) -> U32:
  match args:
    case Con{M.Slot{3, reference}, rest}: reference
    case _: 0

def object_of_found(found: Maybe<&2, M.ThreadState>) -> U32:
  match found:
    case None{}: 0
    case Some{+t}: Th.thread_object(t)

# Thread.current0: the running thread's object (null for main until attached).
def current0(+vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  L.ref_out(vm, object_of_found(Th.current_thread(vm)))

def attach_main(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.void_out(Th.update_current(vm, t => Th.thread_with_object(t, receiver_ref(args))))

def method_named(methods: +List<M.LoadedMethod>, +symbols: +List<String>, +owner: U32, +name: String, +descriptor: String) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), owner) && String.eq(Sy.text(symbols, M.loaded_method_name(method)), name) && String.eq(Sy.text(symbols, M.loaded_method_descriptor(method)), descriptor),
        Some{method}, method_named(rest, symbols, owner, name, descriptor))

# The java/lang/Thread method `name``descriptor` (bendRun, mainUncaught).
def thread_method(+vm: M.VM, +name: String, +descriptor: String) -> Maybe<&2, M.LoadedMethod>:
  method_named(S.methods(vm), S.symbols(vm), L.class_id(vm, "java/lang/Thread"), name, descriptor)

def entry_frame(method: M.LoadedMethod, +object: U32) -> M.Frame:
  match method:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}:
      M.Frame{id, 0, 0, M.replace(M.Slot, M.zeros(U32.to_nat(maxLocals)), 0n, M.Slot{3, object}), Nil{}, 4294967295, 0}

def started_thread(+id: U32, +object: U32, +daemon: Bool, +interrupted: Bool, +priority: U32, +method: M.LoadedMethod) -> M.ThreadState:
  M.ThreadState{id, object, daemon, interrupted, M.NoWait{}, False{}, M.Clock{0, 0}, 0, priority, [entry_frame(method, object)], 0, 0, M.Slot{0, 0}, M.Idle{}, Nil{}}

def start_found(+vm: M.VM, +object: U32, +daemon: Bool, +interrupted: Bool, +priority: U32, found: Maybe<&2, M.LoadedMethod>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: Fail{"java/lang/InternalError: Thread.bendRun"}
    case Some{method}:
      +id : U32 = Th.next_thread_id(vm)
      L.void_out(Th.add_thread(Th.take_thread_id(vm), started_thread(id, object, daemon, interrupted, priority, method)))

# Thread.start0(daemon, interrupted, priority): a new thread whose first frame runs this.bendRun().
def start0(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, +object}, Con{M.Slot{1, daemon}, Con{M.Slot{1, interrupted}, Con{M.Slot{1, priority}, rest}}}}:
      start_found(vm, object, U32.is_ne(daemon, 0), U32.is_ne(interrupted, 0), priority, thread_method(vm, "bendRun", "()V"))
    case _: Fail{"InvalidState: Thread.start0 arguments"}

def priority_found(+vm: M.VM, found: Maybe<&2, M.ThreadState>, +priority: U32) -> M.VM:
  match found:
    case None{}: vm
    case Some{t}: Th.put_thread(vm, Th.thread_with_priority(t, priority))

# Thread.setPriority0: a live thread's scheduling weight changes at once.
def set_priority0(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, +object}, Con{M.Slot{1, +priority}, rest}}: L.void_out(priority_found(vm, Th.thread_of_object(vm, object), priority))
    case _: Fail{"InvalidState: Thread.setPriority0 arguments"}

def alive_found(found: Maybe<&2, M.ThreadState>) -> Bool:
  match found:
    case None{}: False{}
    case Some{+t}: True{}

def alive0(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.bool_out(vm, alive_found(Th.thread_of_object(vm, receiver_ref(args))))

def state_found(found: Maybe<&2, M.ThreadState>) -> U32:
  match found:
    case None{}: 5
    case Some{+t}: Th.public_state(t)

# Thread.state0: 1 RUNNABLE, 2 BLOCKED, 3 WAITING, 4 TIMED_WAITING, 5 TERMINATED.
def state0(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.int_out(vm, state_found(Th.thread_of_object(vm, receiver_ref(args))))

def interrupt_found(+vm: M.VM, found: Maybe<&2, M.ThreadState>) -> M.VM:
  match found:
    case None{}: vm
    case Some{+t}: Th.put_thread(vm, Th.thread_with_interrupted(t, True{}))

# Thread.interrupt0: set the flag; a sleeping, joining or waiting thread sees
# it on the next wake pass and throws InterruptedException.
def interrupt0(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.void_out(interrupt_found(vm, Th.thread_of_object(vm, receiver_ref(args))))

def interrupted_found(+vm: M.VM, found: Maybe<&2, M.ThreadState>, +clear: Bool) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: L.bool_out(vm, False{})
    case Some{+t}:
      +flag : Bool = Th.thread_interrupted(t)
      L.bool_out(Bool.pick(M.VM, clear, Th.put_thread(vm, Th.thread_with_interrupted(t, False{})), vm), flag)

def interrupted0(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, +object}, Con{M.Slot{1, clear}, rest}}: interrupted_found(vm, Th.thread_of_object(vm, object), U32.is_ne(clear, 0))
    case _: Fail{"InvalidState: Thread.interrupted0 arguments"}

def nanos_zero(high: U32, +low: U32) -> Bool:
  U32.is_eq(high, 0) && U32.is_eq(low, 0)

def sleep_ready(+vm: M.VM, +high: U32, +low: U32, +interrupted: Bool) -> Result<&2, &2, String, O.Outcome>:
  match interrupted:
    case True{}: L.throw_name(vm, "java/lang/InterruptedException: sleep interrupted")
    case False{}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, nanos_zero(high, low),
        park_out(vm, M.Yielding{}, False{}, M.Clock{0, 0}),
        park_out(vm, M.Sleeping{}, True{}, Th.deadline_after(vm, high, low)))

# Thread.sleep0(nanos): an interrupted thread throws (clearing the flag);
# sleep(0) only yields; monitors stay owned while sleeping.
def sleep0(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Wide{4, high, low}, rest}:
      +interrupted : Bool = Th.current_interrupted(vm)
      sleep_ready(Bool.pick(M.VM, interrupted, Th.clear_interrupt(vm), vm), high, low, interrupted)
    case _: Fail{"InvalidState: Thread.sleep0 arguments"}

def join_live(+vm: M.VM, +target: U32, +high: U32, +low: U32, +interrupted: Bool) -> Result<&2, &2, String, O.Outcome>:
  match interrupted:
    case True{}: L.throw_name(vm, "java/lang/InterruptedException")
    case False{}: park_out(vm, M.Joining{target}, Bool.not(nanos_zero(high, low)), Th.deadline_after(vm, high, low))

def join_found(+vm: M.VM, found: Maybe<&2, M.ThreadState>, +high: U32, +low: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    # A terminated (or never started) thread is joined at once.
    case None{}: L.void_out(vm)
    case Some{+t}:
      +interrupted : Bool = Th.current_interrupted(vm)
      join_live(Bool.pick(M.VM, interrupted, Th.clear_interrupt(vm), vm), Th.thread_id(t), high, low, interrupted)

# Thread.join0(nanos): park until the target terminates (0 = no timeout).
def join0(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, +object}, Con{M.Wide{4, high, low}, rest}}: join_found(vm, Th.thread_of_object(vm, object), high, low)
    case _: Fail{"InvalidState: Thread.join0 arguments"}

def yield0(+vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  park_out(vm, M.Yielding{}, False{}, M.Clock{0, 0})

def holds_lock(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, 0}, rest}: Fail{"java/lang/NullPointerException"}
    case Con{M.Slot{3, +object}, rest}: L.bool_out(vm, U32.is_ne(Th.held(vm, object, Th.current(vm)), 0))
    case _: Fail{"InvalidState: Thread.holdsLock arguments"}

# ---- Object.wait/notify ------------------------------------------------------

def wait_interrupted(+vm: M.VM, +object: U32, +high: U32, +low: U32, +interrupted: Bool) -> Result<&2, &2, String, O.Outcome>:
  match interrupted:
    case True{}: L.throw_name(vm, "java/lang/InterruptedException")
    case False{}:
      Done{O.Suspend{S.with_status(S.with_effect(Th.wait_on(vm, object, Bool.not(nanos_zero(high, low)), Th.deadline_after(vm, high, low)), M.Park{}), 5), M.Park{}}}

def wait_owned(+vm: M.VM, +object: U32, +high: U32, +low: U32, +owned: Bool) -> Result<&2, &2, String, O.Outcome>:
  match owned:
    case False{}: Fail{"java/lang/IllegalMonitorStateException: current thread is not owner"}
    case True{}:
      +interrupted : Bool = Th.current_interrupted(vm)
      wait_interrupted(Bool.pick(M.VM, interrupted, Th.clear_interrupt(vm), vm), object, high, low, interrupted)

# Object.wait with a timeout of (high, low) nanoseconds, 0 meaning none.
def wait_nanos(+vm: M.VM, +object: U32, +high: U32, +low: U32) -> Result<&2, &2, String, O.Outcome>:
  match object:
    case 0: Fail{"java/lang/NullPointerException"}
    case _: wait_owned(vm, object, high, low, U32.is_ne(Th.held(vm, object, Th.current(vm)), 0))

def negative_long(high: U32) -> Bool:
  U32.is_ne(U32.and(high, 2147483648), 0)

# The high word of the 64-bit product of two 32-bit words.
def mul_high(+a: U32, +b: U32) -> U32:
  +a_lo : U32 = U32.and(a, 65535)
  +a_hi : U32 = U32.shrn(a, 16n)
  +b_lo : U32 = U32.and(b, 65535)
  +b_hi : U32 = U32.shrn(b, 16n)
  +lo_lo : U32 = U32.mul(a_lo, b_lo)
  +mid1 : U32 = U32.mul(a_hi, b_lo)
  +mid2 : U32 = U32.mul(a_lo, b_hi)
  +carry : U32 = U32.shrn(U32.add(U32.add(U32.shrn(lo_lo, 16n), U32.and(mid1, 65535)), U32.and(mid2, 65535)), 16n)
  U32.add(U32.add(U32.add(U32.mul(a_hi, b_hi), U32.shrn(mid1, 16n)), U32.shrn(mid2, 16n)), carry)

# millis * 1_000_000 as (high, low) nanoseconds, saturating near Long.MAX_VALUE.
def millis_nanos_high(+high: U32, +low: U32) -> U32:
  Bool.pick(U32, U32.is_ge(high, 2147), 2147483647, U32.add(U32.mul(high, 1000000), mul_high(low, 1000000)))

def millis_nanos_low(+high: U32, +low: U32) -> U32:
  Bool.pick(U32, U32.is_ge(high, 2147), 4294967295, U32.mul(low, 1000000))

def wait_millis(+vm: M.VM, +object: U32, +high: U32, +low: U32) -> Result<&2, &2, String, O.Outcome>:
  Bool.pick(Result<&2, &2, String, O.Outcome>, negative_long(high), Fail{"java/lang/IllegalArgumentException: timeout value is negative"},
    wait_nanos(vm, object, millis_nanos_high(high, low), millis_nanos_low(high, low)))

def wait_timed(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, +object}, Con{M.Wide{4, high, low}, rest}}: wait_millis(vm, object, high, low)
    case _: Fail{"InvalidState: Object.wait arguments"}

# JDK 8 rounds a sub-millisecond part up to the next millisecond.
def wait_rounded(+vm: M.VM, +object: U32, +high: U32, +low: U32, +nanos: U32) -> Result<&2, &2, String, O.Outcome>:
  +bump : Bool = U32.is_ge(nanos, 500000) || (U32.is_ne(nanos, 0) && nanos_zero(high, low))
  +next_low : U32 = Bool.pick(U32, bump, U32.add(low, 1), low)
  +next_high : U32 = Bool.pick(U32, bump && U32.is_eq(next_low, 0), U32.add(high, 1), high)
  wait_millis(vm, object, next_high, next_low)

def wait_timed_nanos(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, +object}, Con{M.Wide{4, +high, +low}, Con{M.Slot{1, +nanos}, rest}}}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, negative_long(high), Fail{"java/lang/IllegalArgumentException: timeout value is negative"},
        Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_gt(nanos, 999999), Fail{"java/lang/IllegalArgumentException: nanosecond timeout value out of range"},
          wait_rounded(vm, object, high, low, nanos)))
    case _: Fail{"InvalidState: Object.wait arguments"}

def notify_out(+vm: M.VM, +args: +List<M.Slot>, +all: Bool) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, 0}, rest}: Fail{"java/lang/NullPointerException"}
    case Con{M.Slot{3, +object}, rest}:
      do Result<&2, &2, String, O.Outcome>:
        updated : M.VM <- Th.notify(vm, object, all)
        result : O.Outcome <- L.void_out(updated)
        return result
    case _: Fail{"InvalidState: Object.notify arguments"}

# ---- Clocks ----------------------------------------------------------------

def clock_out(+vm: M.VM, +clock: M.Clock) -> Result<&2, &2, String, O.Outcome>:
  match clock:
    case M.Clock{high, low}: L.returned(vm, Some{M.Wide{4, high, low}})

def execute(id: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 800: current0(vm)
    case 801: attach_main(vm, args)
    case 802: start0(vm, args)
    case 803: alive0(vm, args)
    case 804: state0(vm, args)
    case 805: interrupt0(vm, args)
    case 806: interrupted0(vm, args)
    case 807: sleep0(vm, args)
    case 808: join0(vm, args)
    case 809: yield0(vm)
    case 810: holds_lock(vm, args)
    case 811: wait_nanos(vm, receiver_ref(args), 0, 0)
    case 812: wait_timed(vm, args)
    case 813: wait_timed_nanos(vm, args)
    case 814: notify_out(vm, args, False{})
    case 815: notify_out(vm, args, True{})
    case 816: clock_out(vm, Th.now(vm))
    case 817: clock_out(vm, Th.wall(vm))
    case 830: set_priority0(vm, args)
    case _: Fail{"MissingMethod: unknown thread intrinsic"}
