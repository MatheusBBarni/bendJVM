# Proofs of LAWS.bend. Thread-record laws hold by unfolding the record; the
# monitor law by computing the depth-0 case of set_monitor_depth.
import Base
import ./LAWS.bend as Laws
import ./bendjvm/model.bend as M

def Laws.nat_add_zero(x):
  match x:
    case 0n:
      {==}
    case 1n+p:
      %Laws.nat_add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}


def Laws.long_low_roundtrip(value):
  {==}

def Laws.monitor_release_drops_record(ms, object, owner):
  {==}

def Laws.park_records_wait(t, wait, timed, deadline, order):
  match t:
    case M.ThreadState{id, object, daemon, interrupted, w, tm, d, seq, priority, frames, status, exception, result, effect, cont}:
      {==}

def Laws.park_keeps_identity(t, wait, timed, deadline, order):
  match t:
    case M.ThreadState{id, object, daemon, interrupted, w, tm, d, seq, priority, frames, status, exception, result, effect, cont}:
      {==}

def Laws.park_keeps_interrupt(t, wait, timed, deadline, order):
  match t:
    case M.ThreadState{id, object, daemon, interrupted, w, tm, d, seq, priority, frames, status, exception, result, effect, cont}:
      {==}

def Laws.notify_restores_depth(t, object, depth, timed, deadline, order):
  match t:
    case M.ThreadState{id, o, daemon, interrupted, w, tm, d, seq, priority, frames, status, exception, result, effect, cont}:
      {==}

def Laws.notify_ignores_others(t):
  match t:
    case M.ThreadState{id, object, daemon, interrupted, w, tm, d, seq, priority, frames, status, exception, result, effect, cont}:
      {==}

def Laws.interrupt_cleared(t):
  match t:
    case M.ThreadState{id, object, daemon, interrupted, w, tm, d, seq, priority, frames, status, exception, result, effect, cont}:
      {==}

def Laws.timed_wait_state(object, depth):
  {==}

def Laws.untimed_wait_state(object, depth):
  {==}

def Laws.reacquire_is_blocked(object, depth, interrupted, timed):
  {==}

def Laws.host_wait_is_runnable(op, timed):
  {==}
