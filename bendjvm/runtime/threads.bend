import Base
import ../model.bend as M
import ./state.bend as S

# Thread, monitor and clock records shared by the scheduler, the monitor
# bytecodes and the java.lang.Thread/Object intrinsics (plan 05). Everything
# here is a pure transition on the shared VM; no host state is involved.

def sched_current(s: M.Sched) -> U32:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: current

def current(+vm: M.VM) -> U32:
  sched_current(S.sched(vm))

def sched_threads(s: M.Sched) -> +List<M.ThreadState>:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: threads

def threads(+vm: M.VM) -> +List<M.ThreadState>:
  sched_threads(S.sched(vm))

def sched_monitors(s: M.Sched) -> +List<M.Monitor>:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: monitors

def monitors(+vm: M.VM) -> +List<M.Monitor>:
  sched_monitors(S.sched(vm))

def sched_now(s: M.Sched) -> M.Clock:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: now

def now(+vm: M.VM) -> M.Clock:
  sched_now(S.sched(vm))

def sched_wall(s: M.Sched) -> M.Clock:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: wall

def wall(+vm: M.VM) -> M.Clock:
  sched_wall(S.sched(vm))

def with_threads_in(s: M.Sched, value: +List<M.ThreadState>) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, nextSeq, value, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}

def with_threads(+vm: M.VM, value: +List<M.ThreadState>) -> M.VM:
  S.with_sched(vm, with_threads_in(S.sched(vm), value))

def with_monitors_in(s: M.Sched, value: +List<M.Monitor>) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, nextSeq, threads, value, inits, now, wall, fuel, left, mainError, mainHandler, quantum}

def with_monitors(+vm: M.VM, value: +List<M.Monitor>) -> M.VM:
  S.with_sched(vm, with_monitors_in(S.sched(vm), value))

def with_current_in(s: M.Sched, +value: U32) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{value, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}

def with_current(+vm: M.VM, +value: U32) -> M.VM:
  S.with_sched(vm, with_current_in(S.sched(vm), value))

def with_clocks_in(s: M.Sched, +value: M.Clock, +clock: M.Clock) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, value, clock, fuel, left, mainError, mainHandler, quantum}

def with_clocks(+vm: M.VM, +now: M.Clock, +wall: M.Clock) -> M.VM:
  S.with_sched(vm, with_clocks_in(S.sched(vm), now, wall))

def sched_next_thread(s: M.Sched) -> U32:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: nextThread

def bump_thread_in(s: M.Sched) -> M.Sched:
  match s:
    case M.Sched{current, +nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, U32.add(nextThread, 1), nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}

def sched_next_op(s: M.Sched) -> U32:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: nextOp

def bump_op_in(s: M.Sched) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, +nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, U32.add(nextOp, 1), nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}

def sched_next_seq(s: M.Sched) -> U32:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: nextSeq

def bump_seq_in(s: M.Sched) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, +nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, U32.add(nextSeq, 1), threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}

def sched_fuel(s: M.Sched) -> Nat:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: fuel

def fuel(+vm: M.VM) -> Nat:
  sched_fuel(S.sched(vm))

def with_fuel_in(s: M.Sched, +value: Nat) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, value, left, mainError, mainHandler, quantum}

def with_fuel(+vm: M.VM, +value: Nat) -> M.VM:
  S.with_sched(vm, with_fuel_in(S.sched(vm), value))

def sched_left(s: M.Sched) -> Nat:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: left

def left(+vm: M.VM) -> Nat:
  sched_left(S.sched(vm))

def sched_main_error(s: M.Sched) -> String:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: mainError

def main_error(+vm: M.VM) -> String:
  sched_main_error(S.sched(vm))

def with_main_error_in(s: M.Sched, +value: String) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, value, mainHandler, quantum}

def with_main_error(+vm: M.VM, +value: String) -> M.VM:
  S.with_sched(vm, with_main_error_in(S.sched(vm), value))

def sched_main_handler(s: M.Sched) -> U32:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: mainHandler

def main_handler(+vm: M.VM) -> U32:
  sched_main_handler(S.sched(vm))

def with_main_handler_in(s: M.Sched, +value: U32) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, value, quantum}

def with_main_handler(+vm: M.VM, +value: U32) -> M.VM:
  S.with_sched(vm, with_main_handler_in(S.sched(vm), value))

def sched_quantum(s: M.Sched) -> Nat:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: quantum

def quantum(+vm: M.VM) -> Nat:
  sched_quantum(S.sched(vm))

def with_quantum_in(s: M.Sched, value: Nat) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, value}

# The scheduling quantum (instructions per turn); at least one.
def with_quantum(+vm: M.VM, value: Nat) -> M.VM:
  S.with_sched(vm, with_quantum_in(S.sched(vm), Nat.max(value, 1n)))

# Allocates the next thread/operation/wait-order number.
def take_thread_id(+vm: M.VM) -> M.VM:
  S.with_sched(vm, bump_thread_in(S.sched(vm)))

def take_op(+vm: M.VM) -> M.VM:
  S.with_sched(vm, bump_op_in(S.sched(vm)))

def take_seq(+vm: M.VM) -> M.VM:
  S.with_sched(vm, bump_seq_in(S.sched(vm)))

def next_thread_id(+vm: M.VM) -> U32:
  sched_next_thread(S.sched(vm))

def next_op(+vm: M.VM) -> U32:
  sched_next_op(S.sched(vm))

def next_seq(+vm: M.VM) -> U32:
  sched_next_seq(S.sched(vm))

# ---- Thread records --------------------------------------------------------

def thread_id(t: M.ThreadState) -> U32:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: id

def thread_object(t: M.ThreadState) -> U32:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: object

def thread_daemon(t: M.ThreadState) -> Bool:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: daemon

def thread_interrupted(t: M.ThreadState) -> Bool:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: interrupted

def thread_wait(t: M.ThreadState) -> M.Wait:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: wait

def thread_timed(t: M.ThreadState) -> Bool:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: timed

def thread_deadline(t: M.ThreadState) -> M.Clock:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: deadline

def thread_seq(t: M.ThreadState) -> U32:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: seq

def thread_priority(t: M.ThreadState) -> U32:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: priority

def thread_with_priority(t: M.ThreadState, +value: U32) -> M.ThreadState:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}:
      M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, value, frames, status, exception, result, effect, cont}

def thread_status(t: M.ThreadState) -> U32:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: status

def thread_effect(t: M.ThreadState) -> M.Effect:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}: effect

def thread_with_object(t: M.ThreadState, +value: U32) -> M.ThreadState:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}:
      M.ThreadState{id, value, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}

def thread_with_interrupted(t: M.ThreadState, +value: Bool) -> M.ThreadState:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}:
      M.ThreadState{id, object, daemon, value, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}

# Parks (or readies) a thread: its wait reason, timeout and wait order.
def thread_with_wait(t: M.ThreadState, +value: M.Wait, +isTimed: Bool, +until: M.Clock, +order: U32) -> M.ThreadState:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}:
      M.ThreadState{id, object, daemon, interrupted, value, isTimed, until, order, priority, frames, status, exception, result, effect, cont}

def thread_with_status(t: M.ThreadState, +value: U32) -> M.ThreadState:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}:
      M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, value, exception, result, effect, cont}

def find_thread(ts: +List<M.ThreadState>, +id: U32) -> Maybe<&2, M.ThreadState>:
  match ts:
    case Nil{}: None{}
    case Con{+t, +rest}: Bool.pick(Maybe<&2, M.ThreadState>, U32.is_eq(thread_id(t), id), Some{t}, find_thread(rest, id))

def thread(+vm: M.VM, +id: U32) -> Maybe<&2, M.ThreadState>:
  find_thread(threads(vm), id)

# The live thread whose java.lang.Thread is `object` (none once it terminated).
def find_object(ts: +List<M.ThreadState>, +object: U32) -> Maybe<&2, M.ThreadState>:
  match ts:
    case Nil{}: None{}
    case Con{+t, +rest}: Bool.pick(Maybe<&2, M.ThreadState>, U32.is_eq(thread_object(t), object) && U32.is_ne(object, 0), Some{t}, find_object(rest, object))

def thread_of_object(+vm: M.VM, +object: U32) -> Maybe<&2, M.ThreadState>:
  find_object(threads(vm), object)

def replace_thread_in(ts: +List<M.ThreadState>, +t: M.ThreadState) -> +List<M.ThreadState>:
  match ts:
    case Nil{}: Nil{}
    case Con{+old, +rest}: Bool.pick(+List<M.ThreadState>, U32.is_eq(thread_id(old), thread_id(t)), Con{t, rest}, Con{old, replace_thread_in(rest, t)})

def put_thread(+vm: M.VM, +t: M.ThreadState) -> M.VM:
  with_threads(vm, replace_thread_in(threads(vm), t))

# Threads stay ordered by id; a new thread always has the largest id.
def add_thread(+vm: M.VM, +t: M.ThreadState) -> M.VM:
  with_threads(vm, M.append(M.ThreadState, threads(vm), [t]))

def remove_thread_in(ts: +List<M.ThreadState>, +id: U32) -> +List<M.ThreadState>:
  match ts:
    case Nil{}: Nil{}
    case Con{+t, +rest}: Bool.pick(+List<M.ThreadState>, U32.is_eq(thread_id(t), id), rest, Con{t, remove_thread_in(rest, id)})

def remove_thread(+vm: M.VM, +id: U32) -> M.VM:
  with_threads(vm, remove_thread_in(threads(vm), id))

def update_found(+vm: M.VM, found: Maybe<&2, M.ThreadState>, change: M.ThreadState -> M.ThreadState) -> M.VM:
  match found:
    case None{}: vm
    case Some{+t}: put_thread(vm, change(t))

# Applies `change` to thread `id`'s record (no-op when it has terminated).
def update_thread(+vm: M.VM, +id: U32, change: M.ThreadState -> M.ThreadState) -> M.VM:
  update_found(vm, thread(vm, id), change)

def update_current(+vm: M.VM, change: M.ThreadState -> M.ThreadState) -> M.VM:
  update_thread(vm, current(vm), change)

def current_thread(+vm: M.VM) -> Maybe<&2, M.ThreadState>:
  thread(vm, current(vm))

def current_interrupted_found(found: Maybe<&2, M.ThreadState>) -> Bool:
  match found:
    case None{}: False{}
    case Some{+t}: thread_interrupted(t)

def current_interrupted(+vm: M.VM) -> Bool:
  current_interrupted_found(current_thread(vm))

def clear_interrupt(+vm: M.VM) -> M.VM:
  update_current(vm, t => thread_with_interrupted(t, False{}))

# Parks the running thread with `wait` until woken (see the scheduler).
def park(+vm: M.VM, +wait: M.Wait, +timed: Bool, +deadline: M.Clock) -> M.VM:
  +order : U32 = next_seq(vm)
  update_current(take_seq(vm), t => thread_with_wait(t, wait, timed, deadline, order))

def ready(+vm: M.VM, +id: U32) -> M.VM:
  update_thread(vm, id, t => thread_with_wait(t, M.NoWait{}, False{}, M.Clock{0, 0}, 0))

# ---- Clocks ----------------------------------------------------------------

def clock_le(a: M.Clock, +b: M.Clock) -> Bool:
  match a b:
    case M.Clock{+ah, +al} M.Clock{+bh, +bl}: U32.is_lt(ah, bh) || (U32.is_eq(ah, bh) && U32.is_le(al, bl))

# a + (high, low), saturating at the largest clock value.
def clock_add(a: M.Clock, +high: U32, +low: U32) -> M.Clock:
  match a:
    case M.Clock{+ah, +al}:
      +sum : U32 = U32.add(al, low)
      +carry : U32 = Bool.pick(U32, U32.is_lt(sum, al), 1, 0)
      +room : U32 = U32.sub(4294967295, ah)
      Bool.pick(M.Clock, U32.is_gt(high, room) || (U32.is_eq(high, room) && U32.is_eq(carry, 1)),
        M.Clock{4294967295, 4294967295}, M.Clock{U32.add(U32.add(ah, high), carry), sum})

def deadline_after(+vm: M.VM, +high: U32, +low: U32) -> M.Clock:
  clock_add(now(vm), high, low)

# ---- Monitors --------------------------------------------------------------

def monitor_object(m: M.Monitor) -> U32:
  match m:
    case M.Monitor{object, owner, depth}: object

def monitor_owner(m: M.Monitor) -> U32:
  match m:
    case M.Monitor{object, owner, depth}: owner

def monitor_depth(m: M.Monitor) -> U32:
  match m:
    case M.Monitor{object, owner, depth}: depth

def find_monitor(ms: +List<M.Monitor>, +object: U32) -> Maybe<&2, M.Monitor>:
  match ms:
    case Nil{}: None{}
    case Con{+m, +rest}: Bool.pick(Maybe<&2, M.Monitor>, U32.is_eq(monitor_object(m), object), Some{m}, find_monitor(rest, object))

def owner_found(found: Maybe<&2, M.Monitor>) -> U32:
  match found:
    case None{}: 0
    case Some{+m}: monitor_owner(m)

# The thread owning `object`'s monitor, 0 when it is free.
def owner(+vm: M.VM, +object: U32) -> U32:
  owner_found(find_monitor(monitors(vm), object))

def depth_found(found: Maybe<&2, M.Monitor>, +thread: U32) -> U32:
  match found:
    case None{}: 0
    case Some{+m}: Bool.pick(U32, U32.is_eq(monitor_owner(m), thread), monitor_depth(m), 0)

# How many times `thread` holds `object`'s monitor.
def held(+vm: M.VM, +object: U32, +thread: U32) -> U32:
  depth_found(find_monitor(monitors(vm), object), thread)

def drop_monitor(ms: +List<M.Monitor>, +object: U32) -> +List<M.Monitor>:
  match ms:
    case Nil{}: Nil{}
    case Con{+m, +rest}: Bool.pick(+List<M.Monitor>, U32.is_eq(monitor_object(m), object), rest, Con{m, drop_monitor(rest, object)})

def set_monitor_depth(+ms: +List<M.Monitor>, +object: U32, +owner: U32, +depth: U32) -> +List<M.Monitor>:
  Bool.pick(+List<M.Monitor>, U32.is_eq(depth, 0), drop_monitor(ms, object), Con{M.Monitor{object, owner, depth}, drop_monitor(ms, object)})

# Gives `thread` the monitor of `object` `depth` times over (it must be free
# or already its own).
def grant(+vm: M.VM, +object: U32, +thread: U32, +depth: U32) -> M.VM:
  with_monitors(vm, set_monitor_depth(monitors(vm), object, thread, depth))

def enter_owned(+vm: M.VM, +object: U32, +thread: U32, +owner: U32) -> Maybe<&2, M.VM>:
  Bool.pick(Maybe<&2, M.VM>, U32.is_eq(owner, 0) || U32.is_eq(owner, thread),
    Some{grant(vm, object, thread, U32.add(held(vm, object, thread), 1))}, None{})

# monitorenter for the running thread: None when another thread owns it.
def enter(+vm: M.VM, +object: U32) -> Maybe<&2, M.VM>:
  +thread : U32 = current(vm)
  enter_owned(vm, object, thread, owner(vm, object))

def exit_held(+vm: M.VM, +object: U32, +thread: U32, +depth: U32) -> Result<&2, &2, String, M.VM>:
  match depth:
    case 0: Fail{"java/lang/IllegalMonitorStateException"}
    case _: Done{grant(vm, object, thread, U32.sub(depth, 1))}

# monitorexit for the running thread (JVMS 6.5): the owner releases once.
def exit(+vm: M.VM, +object: U32) -> Result<&2, &2, String, M.VM>:
  +thread : U32 = current(vm)
  exit_held(vm, object, thread, held(vm, object, thread))

def release_owned(ms: +List<M.Monitor>, +thread: U32) -> +List<M.Monitor>:
  match ms:
    case Nil{}: Nil{}
    case Con{+m, +rest}: Bool.pick(+List<M.Monitor>, U32.is_eq(monitor_owner(m), thread), release_owned(rest, thread), Con{m, release_owned(rest, thread)})

# A terminating thread gives up any monitor it still owns.
def release_all(+vm: M.VM, +thread: U32) -> M.VM:
  with_monitors(vm, release_owned(monitors(vm), thread))

# ---- Wait sets -------------------------------------------------------------

def waiting_on(wait: M.Wait, +object: U32) -> Bool:
  match wait:
    case M.Waiting{waited, depth}: U32.is_eq(waited, object)
    case _: False{}

def waiter_depth(wait: M.Wait) -> U32:
  match wait:
    case M.Waiting{waited, depth}: depth
    case _: 0

def notified_wait(wait: M.Wait, +t: M.ThreadState) -> M.ThreadState:
  match wait:
    case M.Waiting{object, depth}: thread_with_wait(t, M.Reacquire{object, depth, False{}}, False{}, M.Clock{0, 0}, thread_seq(t))
    case _: t

def notified(+t: M.ThreadState) -> M.ThreadState:
  notified_wait(thread_wait(t), t)

def notify_all_in(ts: +List<M.ThreadState>, +object: U32) -> +List<M.ThreadState>:
  match ts:
    case Nil{}: Nil{}
    case Con{+t, +rest}: Bool.pick(+List<M.ThreadState>, waiting_on(thread_wait(t), object), Con{notified(t), notify_all_in(rest, object)}, Con{t, notify_all_in(rest, object)})

# The longest-waiting thread in `object`'s wait set (0 when it is empty).
def first_waiter(ts: +List<M.ThreadState>, +object: U32, +best: U32, +bestSeq: U32) -> U32:
  match ts:
    case Nil{}: best
    case Con{+t, rest}:
      +better : Bool = waiting_on(thread_wait(t), object) && (U32.is_eq(best, 0) || U32.is_lt(thread_seq(t), bestSeq))
      first_waiter(rest, object, Bool.pick(U32, better, thread_id(t), best), Bool.pick(U32, better, thread_seq(t), bestSeq))

def notify_one_in(ts: +List<M.ThreadState>, +id: U32) -> +List<M.ThreadState>:
  match ts:
    case Nil{}: Nil{}
    case Con{+t, +rest}: Bool.pick(+List<M.ThreadState>, U32.is_eq(thread_id(t), id), Con{notified(t), rest}, Con{t, notify_one_in(rest, id)})

# Object.notify/notifyAll: the owner moves waiters toward monitor reentry; the
# notifier keeps its lock and nothing is recorded when nobody waits.
def notify(+vm: M.VM, +object: U32, +all: Bool) -> Result<&2, &2, String, M.VM>:
  match all:
    case True{}:
      Bool.pick(Result<&2, &2, String, M.VM>, U32.is_eq(held(vm, object, current(vm)), 0),
        Fail{"java/lang/IllegalMonitorStateException: current thread is not owner"},
        Done{with_threads(vm, notify_all_in(threads(vm), object))})
    case False{}:
      Bool.pick(Result<&2, &2, String, M.VM>, U32.is_eq(held(vm, object, current(vm)), 0),
        Fail{"java/lang/IllegalMonitorStateException: current thread is not owner"},
        Done{with_threads(vm, notify_one_in(threads(vm), first_waiter(threads(vm), object, 0, 0)))})

# Object.wait: release every acquisition of `object` and join its wait set;
# the depth comes back when the thread reacquires the monitor.
def wait_on(+vm: M.VM, +object: U32, +timed: Bool, +deadline: M.Clock) -> M.VM:
  +depth : U32 = held(vm, object, current(vm))
  park(grant(vm, object, current(vm), 0), M.Waiting{object, depth}, timed, deadline)

# ---- Liveness --------------------------------------------------------------

def any_user_thread(ts: +List<M.ThreadState>) -> Bool:
  match ts:
    case Nil{}: False{}
    case Con{+t, rest}: Bool.not(thread_daemon(t)) || any_user_thread(rest)

# Java thread states (Thread.State ordinals + 1, as Thread.state0 reports them).
def public_state_of(w: M.Wait, +timed: Bool) -> U32:
  match w:
    case M.EnterMonitor{object}: 2
    case M.Reacquire{object, depth, interrupted}: 2
    case M.InitWait{class}: 3
    case M.InitPark{class}: 3
    case M.HandleInitWait{class}: 3
    case M.MonitorPark{object}: 2
    case M.Sleeping{}: 4
    case M.Joining{target}: Bool.pick(U32, timed, 4, 3)
    case M.Waiting{object, depth}: Bool.pick(U32, timed, 4, 3)
    case _: 1

def public_state(+t: M.ThreadState) -> U32:
  public_state_of(thread_wait(t), thread_timed(t))
