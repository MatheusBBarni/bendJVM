import Base
import ../model.bend as M

def classes(vm: M.VM) -> +List<M.LoadedClass>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  cs

def methods(vm: M.VM) -> +List<M.LoadedMethod>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  ms

def fields(vm: M.VM) -> +List<M.LoadedField>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  fs

def symbols(vm: M.VM) -> +List<String>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  sy

def heap(vm: M.VM) -> +List<M.HeapEntry>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  hp

def statics(vm: M.VM) -> +List<M.Binding>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  st

def resources(vm: M.VM) -> +List<M.Resource>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  rs

def frames(vm: M.VM) -> +List<M.Frame>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  fr

def status(vm: M.VM) -> U32:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  stt

def exception(vm: M.VM) -> U32:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  ex

def max_heap(vm: M.VM) -> U32:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  max

def output(vm: M.VM) -> +List<String>:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  out

def error(vm: M.VM) -> String:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  err

def host(vm: M.VM) -> M.Host:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  host

def metadata_of(h: M.Host) -> M.Metadata:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: metadata

def metadata(vm: M.VM) -> M.Metadata:
  metadata_of(host(vm))

def with_classes(vm: M.VM, value: +List<M.LoadedClass>) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{value, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots}

def with_symbols(vm: M.VM, value: +List<String>) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, value, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots}

def with_heap(vm: M.VM, value: +List<M.HeapEntry>) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, value, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots}

def with_statics(vm: M.VM, value: +List<M.Binding>) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, value, rs, fr, stt, ex, result, out, err, max, steps, host, roots}

def with_frames(vm: M.VM, value: +List<M.Frame>) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, value, stt, ex, result, out, err, max, steps, host, roots}

def with_status(vm: M.VM, value: U32) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, value, ex, result, out, err, max, steps, host, roots}

def with_result(vm: M.VM, value: M.Slot) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, value, out, err, max, steps, host, roots}

def result_slot(vm: M.VM) -> M.Slot:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, value, out, err, max, steps, host, roots} = vm
  value

def with_exception(vm: M.VM, value: U32) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, value, result, out, err, max, steps, host, roots}

def host_cwd_of(h: M.Host) -> String:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: cwd

def host_caps_of(h: M.Host) -> U32:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: caps

def host_effect_of(h: M.Host) -> M.Effect:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: effect

def host_effect(vm: M.VM) -> M.Effect:
  host_effect_of(host(vm))


def host_cont_of(h: M.Host) -> +List<M.Cont>:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: cont
def dynamic_sites_of(h: M.Host) -> +List<M.DynamicSite>:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: dynamicSites
def dynamic_sites(vm: M.VM) -> +List<M.DynamicSite>:
  dynamic_sites_of(host(vm))

def with_host(vm: M.VM, value: M.Host) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, value, roots}

def with_effect_on(vm: M.VM, effect: M.Effect, h: M.Host) -> M.VM:
  match h:
    case M.Host{old, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}:
      with_host(vm, M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors})

def with_effect(+vm: M.VM, effect: M.Effect) -> M.VM:
  with_effect_on(vm, effect, host(vm))

def with_cont_on(vm: M.VM, cont: +List<M.Cont>, h: M.Host) -> M.VM:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, old_cont, metadata, dynamicSites, loaders, sched, errors}:
      with_host(vm, M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors})

def with_dynamic_sites_on(vm: M.VM, dynamicSites: +List<M.DynamicSite>, h: M.Host) -> M.VM:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, old_dynamicSites, loaders, sched, errors}:
      with_host(vm, M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors})

def with_dynamic_sites(+vm: M.VM, dynamicSites: +List<M.DynamicSite>) -> M.VM:
  with_dynamic_sites_on(vm, dynamicSites, host(vm))

def dynamic_site_find(sites: +List<M.DynamicSite>, +method: U32, +pc: U32) -> Maybe<&2, M.DynamicSite>:
  match sites:
    case Nil{}: None{}
    case Con{+site, rest}:
      match site:
        case M.DynamicSite{site_method, site_pc, owner, constant, state, callsite, failure}:
          Bool.pick(Maybe<&2, M.DynamicSite>, U32.is_eq(site_method, method) && U32.is_eq(site_pc, pc),
            Some{site}, dynamic_site_find(rest, method, pc))

def dynamic_site(vm: M.VM, method: U32, pc: U32) -> Maybe<&2, M.DynamicSite>:
  dynamic_site_find(dynamic_sites(vm), method, pc)

def dynamic_site_remove_keep(keep: Bool, site: M.DynamicSite, rest: +List<M.DynamicSite>) -> +List<M.DynamicSite>:
  match keep:
    case True{}: Con{site, rest}
    case False{}: rest

def dynamic_site_remove_next(site: M.DynamicSite, method: U32, pc: U32, rest: +List<M.DynamicSite>) -> +List<M.DynamicSite>:
  match site:
    case M.DynamicSite{+site_method, +site_pc, owner, constant, state, callsite, failure}:
      dynamic_site_remove_keep(Bool.not(U32.is_eq(site_method, method) && U32.is_eq(site_pc, pc)), site, rest)

def dynamic_site_remove_go(sites: +List<M.DynamicSite>, +method: U32, +pc: U32) -> +List<M.DynamicSite>:
  match sites:
    case Nil{}: Nil{}
    case Con{+site, rest}:
      dynamic_site_remove_next(site, method, pc, dynamic_site_remove_go(rest, method, pc))

def set_dynamic_site(+vm: M.VM, +site: M.DynamicSite) -> M.VM:
  match site:
    case M.DynamicSite{method, pc, owner, constant, state, callsite, failure}:
      with_dynamic_sites(vm, Con{site, dynamic_site_remove_go(dynamic_sites(vm), method, pc)})

def publish_dynamic_site_found(found: Maybe<&2, M.DynamicSite>, +vm: M.VM, +site: M.DynamicSite) -> M.VM:
  match found:
    case Some{M.DynamicSite{method, pc, owner, constant, 1, callsite, failure}}: vm
    case Some{M.DynamicSite{method, pc, owner, constant, 2, callsite, failure}}: vm
    case _: set_dynamic_site(vm, site)

# Records a linkage result unless the site already has one (linked or failed).
# A reentrant resolution of the same instruction can finish first; as in the JVM,
# the first completed result is the one every activation observes.
def publish_dynamic_site(+vm: M.VM, +site: M.DynamicSite) -> M.VM:
  match site:
    case M.DynamicSite{+method, +pc, owner, constant, state, callsite, failure}:
      publish_dynamic_site_found(dynamic_site(vm, method, pc), vm, M.DynamicSite{method, pc, owner, constant, state, callsite, failure})

def remove_dynamic_site(+vm: M.VM, method: U32, pc: U32) -> M.VM:
  with_dynamic_sites(vm, dynamic_site_remove_go(dynamic_sites(vm), method, pc))

def with_cont(+vm: M.VM, cont: +List<M.Cont>) -> M.VM:
  with_cont_on(vm, cont, host(vm))

def with_launch_on(vm: M.VM, cwd: String, caps: U32, h: M.Host) -> M.VM:
  match h:
    case M.Host{effect, old_cwd, old_caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}:
      with_host(vm, M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors})

def with_launch(+vm: M.VM, cwd: String, caps: U32) -> M.VM:
  with_launch_on(vm, cwd, caps, host(vm))

# Output is a list of chunks, newest first; println-style writers end theirs
# with a newline, print-style writers do not.
def emit_raw(vm: M.VM, text: String) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, Con{text, out}, err, max, steps, host, roots}

def emit(vm: M.VM, line: String) -> M.VM:
  emit_raw(vm, line ++ "\n")

def fail(vm: M.VM, message: String) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, 4, ex, result, out, message, max, steps, host, roots}

def tick(vm: M.VM) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, 1n+steps, host, roots}

def method_id(frame: M.Frame) -> U32:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  method

def pc(frame: M.Frame) -> U32:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  pc0

def invoke_pc(frame: M.Frame) -> U32:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  invoke

def stack(frame: M.Frame) -> +List<M.Slot>:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  stk

def locals(frame: M.Frame) -> +List<M.Slot>:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  ls

def initializing(frame: M.Frame) -> U32:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  init

def frame_initializing(frame: M.Frame, value: U32) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  M.Frame{method, pc0, invoke, ls, stk, value, mon}


def frame_stack(frame: M.Frame, value: +List<M.Slot>) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  M.Frame{method, pc0, invoke, ls, value, init, mon}

def frame_locals(frame: M.Frame, value: +List<M.Slot>) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  M.Frame{method, pc0, invoke, value, stk, init, mon}

def frame_pc(frame: M.Frame, value: U32) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  M.Frame{method, value, invoke, ls, stk, init, mon}

def advance(frame: M.Frame) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  M.Frame{method, U32.add(pc0, 1), invoke, ls, stk, init, mon}

def suspended(frame: M.Frame) -> M.Frame:
  M.Frame{method, +pc0, invoke, ls, stk, init, mon} = frame
  M.Frame{method, U32.add(pc0, 1), pc0, ls, stk, init, mon}

def retrying(frame: M.Frame) -> M.Frame:
  M.Frame{method, +pc0, invoke, ls, stk, init, mon} = frame
  M.Frame{method, pc0, pc0, ls, stk, init, mon}

def restore_invoke(frame: M.Frame) -> M.Frame:
  M.Frame{method, pc0, +invoke, ls, stk, init, mon} = frame
  M.Frame{method, invoke, invoke, ls, stk, init, mon}

def location(frame: M.Frame, opcode: U32) -> String:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
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
  M.LoadedClass{id, name, parent, interfaces, fs, ms, initializer, old, bootstrapMethods} = class
  M.LoadedClass{id, name, parent, interfaces, fs, ms, initializer, state, bootstrapMethods}

def change_class_state(vm: M.VM, id: U32, state: U32, class: Maybe<&2, M.LoadedClass>) -> M.VM:
  match class:
    case None{}:
      fail(vm, "MissingClass: initialization state")
    case Some{value}:
      +v = vm
      with_classes(v, M.replace(M.LoadedClass, classes(v), U32.to_nat(id), class_state(value, state)))

def set_class_state_raw(+vm: M.VM, +id: U32, state: U32) -> M.VM:
  change_class_state(vm, id, state, M.nth(M.LoadedClass, classes(vm), id))

# ---- Scheduler state (plan 05; see runtime/threads.bend) --------------------

def host_sched_of(h: M.Host) -> M.Sched:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: sched

def sched(vm: M.VM) -> M.Sched:
  host_sched_of(host(vm))

def with_sched_on(vm: M.VM, value: M.Sched, h: M.Host) -> M.VM:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}:
      with_host(vm, M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, value, errors})

def with_sched(+vm: M.VM, value: M.Sched) -> M.VM:
  with_sched_on(vm, value, host(vm))

def host_errors_of(h: M.Host) -> +List<String>:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: errors

def with_errors_on(vm: M.VM, value: +List<String>, h: M.Host) -> M.VM:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}:
      with_host(vm, M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, value})

# Standard error chunks, newest first (System.err, uncaught-exception reports).
def emit_error(+vm: M.VM, text: String) -> M.VM:
  with_errors_on(vm, Con{text, host_errors_of(host(vm))}, host(vm))

# The host printed every chunk: start both streams afresh.
def clear_output(vm: M.VM) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, Nil{}, err, max, steps, host, roots}

def take_output(+vm: M.VM) -> M.VM:
  clear_output(with_errors_on(vm, Nil{}, host(vm)))

def with_error(vm: M.VM, message: String) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, roots} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, message, max, steps, host, roots}

def sched_with_left(s: M.Sched, value: Nat) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, value, mainError, mainHandler, quantum}

# The interpreter loop records the instruction budget a slice left unused.
def with_left(+vm: M.VM, value: Nat) -> M.VM:
  with_sched(vm, sched_with_left(sched(vm), value))

def sched_inits(s: M.Sched) -> +List<M.InitOwner>:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: inits

def sched_current_thread(s: M.Sched) -> U32:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}: current

def sched_with_inits(s: M.Sched, value: +List<M.InitOwner>) -> M.Sched:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, value, now, wall, fuel, left, mainError, mainHandler, quantum}

def init_class(owner: M.InitOwner) -> U32:
  match owner:
    case M.InitOwner{class, thread}: class

def init_thread(owner: M.InitOwner) -> U32:
  match owner:
    case M.InitOwner{class, thread}: thread

def drop_init(owners: +List<M.InitOwner>, +class: U32) -> +List<M.InitOwner>:
  match owners:
    case Nil{}: Nil{}
    case Con{+owner, +rest}: Bool.pick(+List<M.InitOwner>, U32.is_eq(init_class(owner), class), rest, Con{owner, drop_init(rest, class)})

def init_owner_found(owners: +List<M.InitOwner>, +class: U32) -> U32:
  match owners:
    case Nil{}: 0
    case Con{+owner, +rest}: Bool.pick(U32, U32.is_eq(init_class(owner), class), init_thread(owner), init_owner_found(rest, class))

# The thread running `class`'s initializer (0 when none is).
def init_owner(vm: M.VM, class: U32) -> U32:
  init_owner_found(sched_inits(sched(vm)), class)

def track_init(+vm: M.VM, +id: U32, +state: U32) -> M.VM:
  +s : M.Sched = sched(vm)
  +rest : +List<M.InitOwner> = drop_init(sched_inits(s), id)
  with_sched(vm, sched_with_inits(s, Bool.pick(+List<M.InitOwner>, U32.is_eq(state, 1), Con{M.InitOwner{id, sched_current_thread(s)}, rest}, rest)))

# Class states also record which thread is initializing a class (JVMS 5.5),
# so other threads wait for it instead of observing a partial class.
def set_class_state(+vm: M.VM, +id: U32, +state: U32) -> M.VM:
  track_init(set_class_state_raw(vm, id, state), id, state)

def class_state_found(found: Maybe<&2, M.LoadedClass>) -> U32:
  match found:
    case None{}: 0
    case Some{class}: M.loaded_class_state(class)

def class_state_of(vm: M.VM, id: U32) -> U32:
  class_state_found(M.nth(M.LoadedClass, classes(vm), id))

def frame_monitor(frame: M.Frame) -> U32:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  mon

def frame_with_monitor(frame: M.Frame, value: U32) -> M.Frame:
  M.Frame{method, pc0, invoke, ls, stk, init, mon} = frame
  M.Frame{method, pc0, invoke, ls, stk, init, value}

def loaders_of(h: M.Host) -> M.Loaders:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: loaders

def loaders(vm: M.VM) -> M.Loaders:
  loaders_of(host(vm))

def with_loaders_on(vm: M.VM, loaders: M.Loaders, h: M.Host) -> M.VM:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, old_loaders, sched, errors}:
      with_host(vm, M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors})

def with_loaders(+vm: M.VM, loaders: M.Loaders) -> M.VM:
  with_loaders_on(vm, loaders, host(vm))

# ---- Collector state (plan 07; see heap/gc.bend) ------------------------------

def roots(vm: M.VM) -> M.Roots:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, value} = vm
  value

def with_roots(vm: M.VM, value: M.Roots) -> M.VM:
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, old} = vm
  M.VM{cs, ms, fs, sy, hp, st, rs, fr, stt, ex, result, out, err, max, steps, host, value}

def roots_free(r: M.Roots) -> +List<U32>:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: free

def roots_live(r: M.Roots) -> U32:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: live

def roots_spine(r: M.Roots) -> U32:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: spine

def roots_gc(r: M.Roots) -> U32:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: gc

def roots_stress(r: M.Roots) -> U32:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: stress

def roots_countdown(r: M.Roots) -> U32:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: countdown

def roots_pinned(r: M.Roots) -> U32:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: pinned

def roots_oom(r: M.Roots) -> U32:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: oom

def roots_literals(r: M.Roots) -> M.Trie:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: literals

def roots_integers(r: M.Roots) -> M.Trie:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: integers

def roots_longs(r: M.Roots) -> M.Trie:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: longs

def roots_mirrors(r: M.Roots) -> M.Trie:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: mirrors

def roots_closes(r: M.Roots) -> +List<U32>:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}: closes

def roots_with_literals(r: M.Roots, value: M.Trie) -> M.Roots:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, value, integers, longs, mirrors, closes}

def roots_with_integers(r: M.Roots, value: M.Trie) -> M.Roots:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, value, longs, mirrors, closes}

def roots_with_longs(r: M.Roots, value: M.Trie) -> M.Roots:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, value, mirrors, closes}

def roots_with_mirrors(r: M.Roots, value: M.Trie) -> M.Roots:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, value, closes}

def roots_with_gc(r: M.Roots, value: U32) -> M.Roots:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      M.Roots{free, live, spine, value, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}

def roots_with_countdown(r: M.Roots, value: U32) -> M.Roots:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      M.Roots{free, live, spine, gc, stress, value, pinned, oom, literals, integers, longs, mirrors, closes}

def roots_with_closes(r: M.Roots, value: +List<U32>) -> M.Roots:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, value}

def roots_appended(r: M.Roots) -> M.Roots:
  match r:
    case M.Roots{free, +live, +spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      M.Roots{free, U32.add(live, 1), U32.add(spine, 1), gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}

def roots_reused(r: M.Roots, rest: +List<U32>) -> M.Roots:
  match r:
    case M.Roots{free, +live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      M.Roots{rest, U32.add(live, 1), spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}

def roots_swept(r: M.Roots, free: +List<U32>, live: U32, closes: +List<U32>, gc: U32) -> M.Roots:
  match r:
    case M.Roots{old_free, old_live, spine, old_gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, old_closes}:
      M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}

# The runner closed these handles; a later collection starts a new list.
def take_closes(+vm: M.VM) -> M.VM:
  with_roots(vm, roots_with_closes(roots(vm), Nil{}))
