# Laws over pure runtime transitions. The milestone-3 metadata, mirror and
# resource paths and the plan-05 scheduler rounds are VM/host state transitions
# built on @unsafe interpreter code, so the laws below cover the pure monitor,
# wait-set and thread-record transitions those rounds are made of.
import Base
import ./bendjvm/model.bend as M
import ./bendjvm/runtime/wide.bend as W
import ./bendjvm/runtime/threads.bend as Th
import ./bendjvm/heap/gc_core.bend as Gc

law long_low_roundtrip:
  for value: U32
  {W.long_to_int(W.int_to_long(value)) == value : U32}

law nat_add_zero:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}

# Releasing a monitor to depth 0 (monitorexit of the last acquisition, or
# Object.wait releasing every acquisition) removes its ownership record.
law monitor_release_drops_record:
  for +ms: +List<M.Monitor>
  for +object: U32
  for +owner: U32
  {Th.set_monitor_depth(ms, object, owner, 0) == Th.drop_monitor(ms, object) : +List<M.Monitor>}

# Parking records exactly the requested wait reason; it never changes the
# thread's identity, Java object, or interrupt flag.
law park_records_wait:
  for +t: M.ThreadState
  for +wait: M.Wait
  for +timed: Bool
  for +deadline: M.Clock
  for +order: U32
  {Th.thread_wait(Th.thread_with_wait(t, wait, timed, deadline, order)) == wait : M.Wait}

law park_keeps_identity:
  for +t: M.ThreadState
  for +wait: M.Wait
  for +timed: Bool
  for +deadline: M.Clock
  for +order: U32
  {Th.thread_id(Th.thread_with_wait(t, wait, timed, deadline, order)) == Th.thread_id(t) : U32}

law park_keeps_interrupt:
  for +t: M.ThreadState
  for +wait: M.Wait
  for +timed: Bool
  for +deadline: M.Clock
  for +order: U32
  {Th.thread_interrupted(Th.thread_with_wait(t, wait, timed, deadline, order)) == Th.thread_interrupted(t) : Bool}

# notify moves a waiter toward reentry with the complete recursion depth it
# released, without a timeout and without granting the monitor yet.
law notify_restores_depth:
  for +t: M.ThreadState
  for +object: U32
  for +depth: U32
  for +timed: Bool
  for +deadline: M.Clock
  for +order: U32
  {Th.thread_wait(Th.notified(Th.thread_with_wait(t, M.Waiting{object, depth}, timed, deadline, order))) == M.Reacquire{object, depth, False{}} : M.Wait}

# A thread that is not waiting is unaffected by notify.
law notify_ignores_others:
  for +t: M.ThreadState
  {Th.notified(Th.thread_with_wait(t, M.Sleeping{}, True{}, M.Clock{0, 0}, 0)) == Th.thread_with_wait(t, M.Sleeping{}, True{}, M.Clock{0, 0}, 0) : M.ThreadState}

# Clearing the interrupt flag (interrupted(), a thrown InterruptedException).
law interrupt_cleared:
  for +t: M.ThreadState
  {Th.thread_interrupted(Th.thread_with_interrupted(t, False{})) == False{} : Bool}

# Every wait reason maps to exactly one Java Thread.State.
law timed_wait_state:
  for +object: U32
  for +depth: U32
  {Th.public_state_of(M.Waiting{object, depth}, True{}) == 4 : U32}

law untimed_wait_state:
  for +object: U32
  for +depth: U32
  {Th.public_state_of(M.Waiting{object, depth}, False{}) == 3 : U32}

law reacquire_is_blocked:
  for +object: U32
  for +depth: U32
  for +interrupted: Bool
  for +timed: Bool
  {Th.public_state_of(M.Reacquire{object, depth, interrupted}, timed) == 2 : U32}

law host_wait_is_runnable:
  for +op: U32
  for +timed: Bool
  {Th.public_state_of(M.HostOp{op}, timed) == 1 : U32}

# The collector on a hand-built heap (plan 07, section 76 of the spec): object 1
# is the root, object 2 is reached by a field, object 3 only reaches itself and is
# freed. This is a check of one graph, not a proof of the general walk.
def gc_heap() -> +List<M.HeapEntry>:
  [M.HeapEntry{0, 0, 0, [M.Binding{0, M.Slot{3, 2}}], Nil{}, Nil{}},
   M.HeapEntry{0, 0, 0, Nil{}, Nil{}, Nil{}},
   M.HeapEntry{0, 0, 0, [M.Binding{0, M.Slot{3, 3}}], Nil{}, Nil{}}]

law gc_frees_unreachable_cycle:
  {Gc.swept_free(Gc.reclaim(gc_heap(), [1])) == [3] : +List<U32>}

law gc_keeps_live_entries:
  {M.take(M.HeapEntry, Gc.swept_kept(Gc.reclaim(gc_heap(), [1])), 2n) == M.take(M.HeapEntry, gc_heap(), 2n) : +List<M.HeapEntry>}
