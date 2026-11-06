import Base
import ../model.bend as M
import ./state.bend as S
import ./threads.bend as Th
import ./execute.bend as X
import ../java/library.bend as L
import ../java/threads.bend as Tj
import ../java/stacktrace.bend as St

# The Java thread scheduler (plan 05). Java threads are multiplexed on the one
# Bend interpreter: the running thread's frames, status, pending exception,
# result, host effect and continuations live in the VM; every other thread's
# are saved in its ThreadState. A host round runs bounded round-robin quanta
# and returns so the host can start effects and deliver completions.
#
# VM status between rounds: 0 runnable work remains, 1 done, 3 out of fuel,
# 4 failed (`error`), 5 new host requests (threads with a fresh HostOp), 7 idle
# (every live thread waits on the host or a deadline).

# Quanta per host round: about 24,000 instructions, and at least 24 turns.
def round_quanta(+vm: M.VM) -> Nat:
  Nat.max(24n, Nat.div(24000n, Th.quantum(vm)))

def zero_clock() -> M.Clock:
  M.Clock{0, 0}

# ---- Moving a thread in and out of the interpreter -------------------------

def save_found(+vm: M.VM, found: Maybe<&2, M.ThreadState>) -> M.VM:
  match found:
    case None{}: vm
    case Some{M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}}:
      Th.put_thread(vm, M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, S.frames(vm), S.status(vm), S.exception(vm), S.result_slot(vm), S.host_effect(vm), X.host_cont(vm)})

# Copies the interpreter registers into the running thread's record.
def save(+vm: M.VM) -> M.VM:
  save_found(vm, Th.current_thread(vm))

def load(+vm: M.VM, +t: M.ThreadState) -> M.VM:
  match t:
    case M.ThreadState{id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}:
      S.with_cont(S.with_effect(S.with_result(S.with_exception(S.with_status(S.with_frames(Th.with_current(vm, id), frames), status), exception), result), effect), cont)

# Between rounds no thread is loaded and the status is the VM's.
def rest(+vm: M.VM, +status: U32) -> M.VM:
  S.with_cont(S.with_effect(S.with_status(S.with_frames(vm, Nil{}), status), M.Idle{}), Nil{})

# ---- After a thread stops running -------------------------------------------

def host_request(+vm: M.VM) -> M.VM:
  +op : U32 = Th.next_op(vm)
  save(Th.park(Th.take_op(vm), M.HostOp{op}, False{}, zero_clock()))

def effect_stop(+vm: M.VM, +effect: M.Effect) -> M.VM:
  match effect:
    case M.Park{}: save(S.with_status(vm, 8))
    case _: host_request(vm)

# main's first uncaught exception is the run's error; one escaping its
# uncaught-exception handler keeps that original report.
def terminate_report(+vm: M.VM, +main: Bool, +uncaught: Bool) -> M.VM:
  match main uncaught:
    case True{} True{}: S.with_error(Bool.pick(M.VM, String.is_empty(Th.main_error(vm)), Th.with_main_error(vm, S.error(vm)), vm), "")
    case False{} True{}: S.with_error(S.emit_error(vm, "Exception in thread \"" ++ "Thread-" ++ U32.show(Th.current(vm)) ++ "\" " ++ S.error(vm) ++ "\n"), "")
    case _ _: vm

# The thread finished (its last frame returned or an exception escaped it):
# drop its record and any monitor it still owns. Joiners notice on the next
# wake pass, since their target no longer exists.
def terminate(+vm: M.VM, +uncaught: Bool) -> M.VM:
  +id : U32 = Th.current(vm)
  +reported : M.VM = terminate_report(vm, U32.is_eq(id, 1), uncaught)
  S.with_frames(Th.remove_thread(Th.release_all(reported, id), id), Nil{})

# main() ended with an exception: like the JDK launcher, offer it to the main
# thread's or the default UncaughtExceptionHandler (Thread.mainUncaught) first.
def main_uncaught_found(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>) -> M.VM:
  match found:
    case None{}: terminate(vm, True{})
    case Some{method}:
      +frame : M.Frame = Tj.entry_frame(method, S.exception(vm))
      +handling : M.VM = Th.with_main_handler(Th.with_main_error(vm, S.error(vm)), 1)
      save(S.with_exception(S.with_status(S.with_frames(S.with_error(handling, ""), [frame]), 0), 0))

def first_found(found: Maybe<&2, M.LoadedMethod>, +fallback: Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case Some{method}: Some{method}
    case None{}: fallback

# Without java.lang.Thread loaded, BendStackTrace.mainUncaught prints the
# JDK's default "Exception in thread "main"" report with the stack trace.
def ended_uncaught(main: Bool, +vm: M.VM) -> M.VM:
  match main:
    case True{}: main_uncaught_found(vm, first_found(Tj.thread_method(vm, "mainUncaught", "(Ljava/lang/Throwable;)Z"), St.method_named(S.methods(vm), S.symbols(vm), L.class_id(vm, "sun/misc/BendStackTrace"), "mainUncaught", "(Ljava/lang/Throwable;)Z")))
    case False{}: terminate(vm, True{})

# Thread.mainUncaught returned: true when a Java handler took the exception.
def handler_done(+vm: M.VM, +handled: Bool) -> M.VM:
  match handled:
    case True{}: Th.with_main_error(Th.with_main_handler(vm, 2), "")
    case False{}: Th.with_main_handler(vm, 0)

def ended_normally(running: Bool, +vm: M.VM) -> M.VM:
  match running:
    case True{}: terminate(handler_done(vm, U32.is_ne(M.slot_bits(S.result_slot(vm)), 0)), False{})
    case False{}: terminate(vm, False{})

def settle_status(status: U32, +vm: M.VM) -> M.VM:
  match status:
    case 3: save(S.with_status(vm, 0))
    case 1: ended_normally(U32.is_eq(Th.current(vm), 1) && U32.is_eq(Th.main_handler(vm), 1), vm)
    case 9: ended_uncaught(U32.is_eq(Th.current(vm), 1) && U32.is_eq(Th.main_handler(vm), 0), vm)
    case 4: vm
    case 5: effect_stop(vm, S.host_effect(vm))
    case _: save(vm)

# Records why the running thread stopped (preempted, finished, parked or
# waiting on the host) and saves it.
def settle(+vm: M.VM) -> M.VM:
  settle_status(S.status(vm), vm)

# ---- Waking parked threads --------------------------------------------------

def expired(+vm: M.VM, +t: M.ThreadState) -> Bool:
  Th.thread_timed(t) && Th.clock_le(Th.thread_deadline(t), Th.now(vm))

# kind: 0 return normally, 1 throw InterruptedException("sleep interrupted"),
# 2 throw InterruptedException.
# 3: an interrupted Selector.select returns 0; 4: an interrupted blocking
# channel operation throws ClosedByInterruptException. Both keep the flag.
@unsafe def resume_kind(+vm: M.VM, +kind: U32) -> M.VM:
  match kind:
    case 0: X.resume_void(vm)
    case 1: X.resume_fail_message(vm, "java/lang/InterruptedException", "sleep interrupted")
    case 2: X.resume_fail(vm, "java/lang/InterruptedException")
    case 3: X.resume_int(vm, 0)
    case 5: X.resume_handle_init(vm)
    case _: X.resume_fail(vm, "java/nio/channels/ClosedByInterruptException")

@unsafe def resume_parked(+vm: M.VM, +t: M.ThreadState, +kind: U32) -> M.VM:
  +ready : M.ThreadState = Th.thread_with_wait(t, M.NoWait{}, False{}, zero_clock(), 0)
  +interrupt : Bool = U32.is_eq(kind, 1) || U32.is_eq(kind, 2)
  +cleared : M.ThreadState = Bool.pick(M.ThreadState, interrupt, Th.thread_with_interrupted(ready, False{}), ready)
  settle(resume_kind(load(Th.put_thread(vm, cleared), cleared), kind))

def make_ready(+vm: M.VM, +t: M.ThreadState) -> M.VM:
  Th.put_thread(vm, Th.thread_with_status(Th.thread_with_wait(t, M.NoWait{}, False{}, zero_clock(), 0), 0))

def to_reacquire(+vm: M.VM, +t: M.ThreadState, +object: U32, +depth: U32, +interrupted: Bool) -> M.VM:
  +order : U32 = Th.thread_seq(t)
  +moved : M.ThreadState = Th.thread_with_wait(t, M.Reacquire{object, depth, interrupted}, False{}, zero_clock(), order)
  Th.put_thread(vm, Bool.pick(M.ThreadState, interrupted, Th.thread_with_interrupted(moved, False{}), moved))

def class_initializing(+vm: M.VM, +class: U32) -> Bool:
  U32.is_eq(S.class_state_of(vm, class), 1)

@unsafe def wake_blocked(+vm: M.VM, +t: M.ThreadState, +wait: M.Wait) -> M.VM:
  match wait:
    case M.EnterMonitor{object}: Bool.pick(M.VM, U32.is_eq(Th.owner(vm, object), 0), make_ready(vm, t), vm)
    case M.InitWait{class}: Bool.pick(M.VM, class_initializing(vm, class), vm, make_ready(vm, t))
    case _: vm

@unsafe def wake_handle(due: Bool, +vm: M.VM, +t: M.ThreadState) -> M.VM:
  match due:
    case True{}: resume_parked(vm, t, 5)
    case False{}: vm

@unsafe def wake_if(due: Bool, +vm: M.VM, +t: M.ThreadState) -> M.VM:
  match due:
    case True{}: resume_parked(vm, t, 0)
    case False{}: vm

@unsafe def wake_sleeper_flag(interrupted: Bool, +vm: M.VM, +t: M.ThreadState) -> M.VM:
  match interrupted:
    case True{}: resume_parked(vm, t, 1)
    case False{}: wake_if(expired(vm, t), vm, t)

@unsafe def wake_sleeper(+vm: M.VM, +t: M.ThreadState) -> M.VM:
  wake_sleeper_flag(Th.thread_interrupted(t), vm, t)

@unsafe def wake_joiner(+vm: M.VM, +t: M.ThreadState, +target: U32, +alive: Bool) -> M.VM:
  wake_joiner_flags(Th.thread_interrupted(t), alive, vm, t)

@unsafe def wake_joiner_flags(interrupted: Bool, alive: Bool, +vm: M.VM, +t: M.ThreadState) -> M.VM:
  match interrupted alive:
    case True{} True{}: resume_parked(vm, t, 2)
    case _ False{}: resume_parked(vm, t, 0)
    case False{} True{}: wake_if(expired(vm, t), vm, t)

# A woken waiter tries to take its monitor back at once.
@unsafe def wake_waiter_flags(interrupted: Bool, timedOut: Bool, +vm: M.VM, +t: M.ThreadState, +object: U32, +depth: U32) -> M.VM:
  match interrupted timedOut:
    case True{} _: reacquire_again(to_reacquire(vm, t, object, depth, True{}), Th.thread_id(t), object, depth, True{})
    case False{} True{}: reacquire_again(to_reacquire(vm, t, object, depth, False{}), Th.thread_id(t), object, depth, False{})
    case False{} False{}: vm

@unsafe def reacquire_again(+vm: M.VM, +id: U32, +object: U32, +depth: U32, +interrupted: Bool) -> M.VM:
  reacquire_found(Th.thread(vm, id), vm, object, depth, interrupted)

@unsafe def reacquire_found(found: Maybe<&2, M.ThreadState>, +vm: M.VM, +object: U32, +depth: U32, +interrupted: Bool) -> M.VM:
  match found:
    case None{}: vm
    case Some{+moved}: reacquire(vm, moved, object, depth, interrupted)

@unsafe def wake_waiter(+vm: M.VM, +t: M.ThreadState, +object: U32, +depth: U32) -> M.VM:
  wake_waiter_flags(Th.thread_interrupted(t), expired(vm, t), vm, t, object, depth)

@unsafe def reacquire_free(free: Bool, +vm: M.VM, +t: M.ThreadState, +object: U32, +depth: U32, +interrupted: Bool) -> M.VM:
  match free:
    case False{}: vm
    case True{}: resume_parked(Th.grant(vm, object, Th.thread_id(t), depth), t, Bool.pick(U32, interrupted, 2, 0))

# A notified, timed-out or interrupted waiter takes the monitor back with its
# full recursion depth as soon as nobody owns it.
@unsafe def reacquire(+vm: M.VM, +t: M.ThreadState, +object: U32, +depth: U32, +interrupted: Bool) -> M.VM:
  reacquire_free(U32.is_eq(Th.owner(vm, object), 0), vm, t, object, depth, interrupted)

def alive_found(found: Maybe<&2, M.ThreadState>) -> Bool:
  match found:
    case None{}: False{}
    case Some{t}: True{}

def joined_alive(+vm: M.VM, +target: U32) -> Bool:
  alive_found(Th.thread(vm, target))

@unsafe def wake_parked(+vm: M.VM, +t: M.ThreadState, +wait: M.Wait) -> M.VM:
  match wait:
    case M.Sleeping{}: wake_sleeper(vm, t)
    case M.Joining{target}: wake_joiner(vm, t, target, joined_alive(vm, target))
    case M.Waiting{object, depth}: wake_waiter(vm, t, object, depth)
    case M.Reacquire{object, depth, interrupted}: reacquire(vm, t, object, depth, interrupted)
    case M.Yielding{}: resume_parked(vm, t, 0)
    case M.InitPark{class}: wake_if(Bool.not(class_initializing(vm, class)), vm, t)
    case M.MonitorPark{object}: wake_if(U32.is_eq(Th.owner(vm, object), 0), vm, t)
    case M.HandleInitWait{class}: wake_handle(Bool.not(class_initializing(vm, class)), vm, t)
    case _: vm

# HostIO.call ops flagged interruptible (arg bit 30) stop waiting when their
# thread is interrupted; the host's later completion is then stale.
@unsafe def wake_hostio(due: Bool, +select: Bool, +vm: M.VM, +t: M.ThreadState) -> M.VM:
  match due:
    case False{}: vm
    case True{}: resume_parked(vm, t, Bool.pick(U32, select, 3, 4))

@unsafe def wake_host(+vm: M.VM, +t: M.ThreadState, effect: M.Effect) -> M.VM:
  match effect:
    case M.HostIO{op, handle, arg, data, array, offset, length}:
      wake_hostio(Th.thread_interrupted(t) && U32.is_ne(U32.and(arg, 1073741824), 0), U32.is_eq(op, 12), vm, t)
    case _: vm

@unsafe def wake_thread(+vm: M.VM, +t: M.ThreadState, +status: U32) -> M.VM:
  match status:
    case 5: wake_host(vm, t, Th.thread_effect(t))
    case 7: wake_blocked(vm, t, Th.thread_wait(t))
    case 8: wake_parked(vm, t, Th.thread_wait(t))
    case _: vm

@unsafe def wake_found(+vm: M.VM, found: Maybe<&2, M.ThreadState>) -> M.VM:
  match found:
    case None{}: vm
    case Some{+t}: wake_thread(vm, t, Th.thread_status(t))

def thread_ids(ts: +List<M.ThreadState>) -> +List<U32>:
  match ts:
    case Nil{}: Nil{}
    case Con{+t, rest}: Con{Th.thread_id(t), thread_ids(rest)}

@unsafe def wake_ids(ids: +List<U32>, +vm: M.VM) -> M.VM:
  match ids:
    case Nil{}: vm
    case Con{id, rest}: wake_ids(rest, wake_found(vm, Th.thread(vm, id)))

# Re-evaluates every parked thread's wake condition against the shared state
# (monitor owners, live threads, class states, deadlines, interrupt flags), so
# a wakeup can never be lost between the notifier and the waiter.
@unsafe def wake(+vm: M.VM) -> M.VM:
  wake_ids(thread_ids(Th.threads(vm)), vm)

# ---- Choosing the next thread -----------------------------------------------

def runnable(t: M.ThreadState) -> Bool:
  +status : U32 = Th.thread_status(t)
  U32.is_eq(status, 0) || U32.is_eq(status, 6)

def pick_after(ts: +List<M.ThreadState>, +after: U32) -> Maybe<&2, M.ThreadState>:
  match ts:
    case Nil{}: None{}
    case Con{+t, +rest}: Bool.pick(Maybe<&2, M.ThreadState>, runnable(t) && U32.is_gt(Th.thread_id(t), after), Some{t}, pick_after(rest, after))

def pick_first(found: Maybe<&2, M.ThreadState>, +ts: +List<M.ThreadState>) -> Maybe<&2, M.ThreadState>:
  match found:
    case Some{+t}: Some{t}
    case None{}: pick_after(ts, 0)

# Round-robin: the next runnable thread after the one that ran last.
def pick(+vm: M.VM) -> Maybe<&2, M.ThreadState>:
  pick_first(pick_after(Th.threads(vm), Th.current(vm)), Th.threads(vm))

def waits_on_host(ts: +List<M.ThreadState>) -> Bool:
  match ts:
    case Nil{}: False{}
    case Con{+t, rest}: U32.is_eq(Th.thread_status(t), 5) || Th.thread_timed(t) || waits_on_host(rest)

def wait_text(wait: M.Wait) -> String:
  match wait:
    case M.EnterMonitor{object}: "waiting to lock object " ++ U32.show(object)
    case M.MonitorPark{object}: "waiting to lock object " ++ U32.show(object)
    case M.Reacquire{object, depth, interrupted}: "waiting to relock object " ++ U32.show(object)
    case M.Waiting{object, depth}: "waiting on object " ++ U32.show(object)
    case M.Joining{target}: "joining thread " ++ U32.show(target)
    case M.InitWait{class}: "waiting for class initialization " ++ U32.show(class)
    case M.InitPark{class}: "waiting for class initialization " ++ U32.show(class)
    case M.HandleInitWait{class}: "waiting for class initialization " ++ U32.show(class)
    case _: "parked"

def deadlock_report(ts: +List<M.ThreadState>) -> String:
  match ts:
    case Nil{}: ""
    case Con{+t, rest}: " thread " ++ U32.show(Th.thread_id(t)) ++ " (" ++ wait_text(Th.thread_wait(t)) ++ ")" ++ deadlock_report(rest)

# A handled main exception still fails the run (exit status 1), silently.
def finish_clean(clean: Bool, +vm: M.VM, +error: String) -> M.VM:
  match clean:
    case True{}: Bool.pick(M.VM, U32.is_eq(Th.main_handler(vm), 2), S.fail(rest(vm, 4), ""), rest(vm, 1))
    case False{}: S.fail(rest(vm, 4), error)

# Every non-daemon thread ended; an exception that ended main fails the run.
def finish(+vm: M.VM, +error: String) -> M.VM:
  finish_clean(String.eq(error, ""), vm, error)

# No thread can run: wait for the host, or report a deadlock (the JVM would hang).
def idle_waiting(waiting: Bool, +vm: M.VM) -> M.VM:
  match waiting:
    case True{}: rest(vm, 7)
    case False{}: S.fail(rest(vm, 4), "Deadlock: no thread can make progress;" ++ deadlock_report(Th.threads(vm)))

def idle(+vm: M.VM) -> M.VM:
  idle_waiting(waits_on_host(Th.threads(vm)), vm)

# ---- Rounds -----------------------------------------------------------------

# Thread priorities weight the round-robin: a turn lasts quantum * priority / 5
# instructions (NORM_PRIORITY 5 runs one quantum), at least one.
def weighted(+quantum: Nat, +priority: U32) -> Nat:
  Nat.max(1n, Nat.div(Nat.mul(quantum, U32.to_nat(priority)), 5n))

@unsafe def run_slice(+vm: M.VM, +t: M.ThreadState) -> M.VM:
  +budget : Nat = Nat.min(weighted(Th.quantum(vm), Th.thread_priority(t)), Th.fuel(vm))
  +ran : M.VM = X.loop(budget, load(vm, t))
  +used : Nat = Nat.sub(budget, Th.left(ran))
  settle(Th.with_fuel(ran, Nat.sub(Th.fuel(ran), used)))

@unsafe def after_slice(+rounds: Nat, +vm: M.VM, +before: U32) -> M.VM:
  after_slice_status(S.status(vm), rounds, vm, before)

@unsafe def after_slice_status(status: U32, +rounds: Nat, +vm: M.VM, +before: U32) -> M.VM:
  match status:
    case 4: vm
    case _: after_slice_fuel(Nat.is_eq(Th.fuel(vm), 0n), U32.is_eq(Th.next_op(vm), before), rounds, vm)

@unsafe def after_slice_fuel(spent: Bool, quiet: Bool, +rounds: Nat, +vm: M.VM) -> M.VM:
  match spent quiet:
    case True{} _: rest(vm, 3)
    case False{} True{}: round(rounds, vm)
    case False{} False{}: rest(vm, 5)

@unsafe def decide(+rounds: Nat, +vm: M.VM, +alive: Bool, next: Maybe<&2, M.ThreadState>) -> M.VM:
  match alive:
    case False{}: finish(vm, Th.main_error(vm))
    case True{}:
      match next:
        case None{}: idle(vm)
        case Some{+t}: after_slice(rounds, run_slice(vm, t), Th.next_op(vm))

# Up to `rounds` quanta; the VM returns to the host after them, after a thread
# requests a host effect, or when nothing can run.
@unsafe def round(rounds: Nat, +vm: M.VM) -> M.VM:
  match rounds:
    case 0n: rest(vm, 0)
    case 1n+p:
      +woke : M.VM = wake(vm)
      decide(p, woke, Th.any_user_thread(Th.threads(woke)), pick(woke))

# ---- Entry points ------------------------------------------------------------

def main_thread(+vm: M.VM) -> M.ThreadState:
  M.ThreadState{1, 0, False{}, False{}, M.NoWait{}, False{}, zero_clock(), 0, 5, S.frames(vm), S.status(vm), S.exception(vm), S.result_slot(vm), S.host_effect(vm), X.host_cont(vm)}

@unsafe def start_status(status: U32, +vm: M.VM, +fuel: Nat, +now: M.Clock, +wall: M.Clock) -> M.VM:
  match status:
    case 4: vm
    case _:
      +clocked : M.VM = Th.with_fuel(Th.with_clocks(vm, now, wall), fuel)
      round(round_quanta(clocked), Th.with_current(Th.add_thread(Th.take_thread_id(clocked), main_thread(clocked)), 1))

# The main thread starts with the frames start_loaded_entry prepared.
@unsafe def start(+vm: M.VM, +fuel: Nat, +now: M.Clock, +wall: M.Clock) -> M.VM:
  start_status(S.status(vm), vm, fuel, now, wall)

def halted(+status: U32) -> Bool:
  U32.is_eq(status, 1) || U32.is_eq(status, 3) || U32.is_eq(status, 4)

@unsafe def continue_run(+vm: M.VM, +now: M.Clock, +wall: M.Clock) -> M.VM:
  continue_halted(halted(S.status(vm)), vm, now, wall)

@unsafe def continue_halted(stopped: Bool, +vm: M.VM, +now: M.Clock, +wall: M.Clock) -> M.VM:
  match stopped:
    case True{}: vm
    case False{}: round(round_quanta(vm), Th.with_clocks(vm, now, wall))

def op_of(wait: M.Wait) -> U32:
  match wait:
    case M.HostOp{op}: op
    case _: 0

def find_op(ts: +List<M.ThreadState>, +op: U32) -> Maybe<&2, M.ThreadState>:
  match ts:
    case Nil{}: None{}
    case Con{+t, +rest}: Bool.pick(Maybe<&2, M.ThreadState>, U32.is_eq(Th.thread_status(t), 5) && U32.is_eq(op_of(Th.thread_wait(t)), op), Some{t}, find_op(rest, op))

def complete_status(status: U32, +vm: M.VM, +before: U32) -> M.VM:
  match status:
    case 4: vm
    case _: rest(vm, Bool.pick(U32, U32.is_eq(Th.next_op(vm), before), 0, 5))

def complete_done(+vm: M.VM, +before: U32) -> M.VM:
  complete_status(S.status(vm), vm, before)

@unsafe def complete_found(+vm: M.VM, found: Maybe<&2, M.ThreadState>, resume: M.VM -> M.VM) -> M.VM:
  match found:
    case None{}: vm
    case Some{+t}:
      +ready : M.ThreadState = Th.thread_with_wait(t, M.NoWait{}, False{}, zero_clock(), 0)
      +before : U32 = Th.next_op(vm)
      complete_done(settle(resume(load(Th.put_thread(vm, ready), ready))), before)

# Delivers host operation `op`'s result to the thread waiting for it. A stale
# completion (cancelled, its thread gone, or delivered twice) changes nothing.
@unsafe def complete(+vm: M.VM, +op: U32, resume: M.VM -> M.VM) -> M.VM:
  complete_halted(halted(S.status(vm)), vm, op, resume)

@unsafe def complete_halted(stopped: Bool, +vm: M.VM, +op: U32, resume: M.VM -> M.VM) -> M.VM:
  match stopped:
    case True{}: vm
    case False{}: complete_found(vm, find_op(Th.threads(vm), op), resume)
