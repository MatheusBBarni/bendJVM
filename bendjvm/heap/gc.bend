import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ./heap.bend as H
import ./trie.bend as T
import ./gc_core.bend as C

# Mark-and-sweep collection (plan 07): pure VM -> VM. It runs at an instruction
# boundary, where the frames, statics, root tables, pending effects, and
# continuations hold every reference the VM can still use. Only tag-3 slots and
# the named reference fields below are followed; class ids, symbols, and sizes are
# not. A field that may or may not hold a reference (NeedToString.extra) is
# followed anyway: retaining an extra object is harmless, freeing a live one is not.

def add_ref(+reference: U32, +acc: +List<U32>) -> +List<U32>:
  C.add_ref(reference, acc)

def slot_ref(value: M.Slot, +acc: +List<U32>) -> +List<U32>:
  C.slot_ref(value, acc)

def slots_refs(values: +List<M.Slot>, +acc: +List<U32>) -> +List<U32>:
  C.slots_refs(values, acc)

def bindings_refs(values: +List<M.Binding>, +acc: +List<U32>) -> +List<U32>:
  C.bindings_refs(values, acc)

def u32s_refs(values: +List<U32>, +acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: acc
    case Con{value, rest}: u32s_refs(rest, add_ref(value, acc))

@unsafe def effect_refs(effect: M.Effect, +acc: +List<U32>) -> +List<U32>:
  match effect:
    case M.ReflectConstructor{reference}: add_ref(reference, acc)
    case M.HandleConstructor{reference}: add_ref(reference, acc)
    case M.RuntimeClass{name, initialize, loader}: add_ref(loader, acc)
    case M.OpenFile{path, mode, receiver}: add_ref(receiver, acc)
    case M.ListArchive{path, receiver, op, connection, entry}: add_ref(receiver, add_ref(connection, acc))
    case M.NativeCall{method, owner, name, descriptor, isStatic, words, arrays, lock}: u32s_refs(arrays, add_ref(lock, acc))
    case M.HostIO{op, handle, arg, data, array, offset, length}: add_ref(array, acc)
    case _: acc

def text_items_refs(items: +List<M.TextItem>, +acc: +List<U32>) -> +List<U32>:
  match items:
    case Nil{}: acc
    case Con{M.TextUnits{units}, rest}: text_items_refs(rest, acc)
    case Con{M.TextCall{reference}, rest}: text_items_refs(rest, add_ref(reference, acc))
    case Con{M.TextThrow{reference}, rest}: text_items_refs(rest, add_ref(reference, acc))

@unsafe def task_refs(task: M.SerialTask, +acc: +List<U32>) -> +List<U32>:
  match task:
    case M.WContext{object, class, put}: add_ref(object, add_ref(put, acc))
    case M.WObject{value}: add_ref(value, acc)
    case M.WReplaced{original, class}: add_ref(original, acc)
    case M.WData{object, classes}: add_ref(object, acc)
    case M.WFields{object, fields}: add_ref(object, acc)
    case M.WValues{values, code}: slots_refs(values, acc)
    case M.WUnshared{value}: add_ref(value, acc)
    case M.WExternal{object}: add_ref(object, acc)
    case M.WClassBody{object}: add_ref(object, acc)
    case M.WArrayBody{object}: add_ref(object, acc)
    case M.WEnumBody{object}: add_ref(object, acc)
    case M.WInstance{object, class}: add_ref(object, acc)
    case M.WHooked{original}: add_ref(original, acc)
    case M.WSlots{fields, values}: slots_refs(values, acc)
    case M.WCaught{exception}: add_ref(exception, acc)
    case M.WThrow{exception}: add_ref(exception, acc)
    case M.RStore{object, slot, signature}: add_ref(object, acc)
    case M.RElement{array, index}: add_ref(array, acc)
    case M.RFields{object, fields}: add_ref(object, acc)
    case M.RResolve{object, handle}: add_ref(object, acc)
    case M.RPush{value}: add_ref(value, acc)
    case M.RContext{object, class}: add_ref(object, acc)
    case M.RSlot{object, class, mode}: add_ref(object, acc)
    case M.RExternal{object, block}: add_ref(object, acc)
    case M.RFill{array}: add_ref(array, acc)
    case M.RLoaded{loader, name}: add_ref(loader, acc)
    case M.RRetry{id, args}: slots_refs(args, acc)
    case M.RDescResolved{handle, desc}: add_ref(desc, acc)
    case M.RDescFinish{handle, desc, class}: add_ref(desc, acc)
    case _: acc

@unsafe def tasks_refs(tasks: +List<M.SerialTask>, +acc: +List<U32>) -> +List<U32>:
  match tasks:
    case Nil{}: acc
    case Con{task, rest}: tasks_refs(rest, task_refs(task, acc))

def define_job_ref(job: M.DefineJob, +acc: +List<U32>) -> +List<U32>:
  match job:
    case M.DefineJob{loader, namespace, file, actual, internal, supers, others, mapping, current, super}: add_ref(loader, acc)

@unsafe def cont_refs(cont: M.Cont, +acc: +List<U32>) -> +List<U32>:
  match cont:
    case M.NeedHash{map, key, op, extra}: add_ref(map, add_ref(key, slot_ref(extra, acc)))
    case M.NeedEq{map, key, hash, index, op, extra}: add_ref(map, add_ref(key, slot_ref(extra, acc)))
    case M.NeedThrowableMessage{receiver, cause}: add_ref(receiver, add_ref(cause, acc))
    case M.NeedToString{op, extra}: add_ref(extra, acc)
    case M.NeedEquals{op, left, right}: add_ref(left, add_ref(right, acc))
    case M.NeedListEq{list, query, index, op}: add_ref(list, add_ref(query, acc))
    case M.CallBoundary{depth, effect, descriptor}: effect_refs(effect, acc)
    case M.NeedIntrinsicRetry{kind, args}: slots_refs(args, acc)
    case M.NeedTextJoin{units, items}: text_items_refs(items, acc)
    case M.NeedLoaderParent{loader, name}: add_ref(loader, add_ref(name, acc))
    case M.NeedDefine{job}: define_job_ref(job, acc)
    case M.NeedResourceParent{loader, name}: add_ref(loader, add_ref(name, acc))
    case M.NeedSerialWrite{stream, tasks}: add_ref(stream, tasks_refs(tasks, acc))
    case M.NeedSerialRead{stream, tasks, values}: add_ref(stream, tasks_refs(tasks, slots_refs(values, acc)))
    case M.NeedBulkRead{stream, array, offset, length, got}: add_ref(stream, add_ref(array, acc))
    case M.HandleInvocation{depth, kind, owner, name, descriptor, method, entry, args, target, requested, max, previousEffect}: effect_refs(previousEffect, slots_refs(args, C.entry_refs(Some{entry}, acc)))
    case M.HandleInitReturn{depth, effect}: effect_refs(effect, acc)
    case M.DynamicBootstrap{depth, method, pc, owner, constant, args}: slots_refs(args, acc)
    case _: acc

@unsafe def conts_refs(conts: +List<M.Cont>, +acc: +List<U32>) -> +List<U32>:
  match conts:
    case Nil{}: acc
    case Con{cont, rest}: conts_refs(rest, cont_refs(cont, acc))

def frames_refs(frames: +List<M.Frame>, +acc: +List<U32>) -> +List<U32>:
  match frames:
    case Nil{}: acc
    case Con{M.Frame{method, pc, invoke, locals, stack, init, monitor}, rest}: frames_refs(rest, add_ref(monitor, slots_refs(stack, slots_refs(locals, acc))))

def wait_refs(wait: M.Wait, +acc: +List<U32>) -> +List<U32>:
  match wait:
    case M.EnterMonitor{object}: add_ref(object, acc)
    case M.MonitorPark{object}: add_ref(object, acc)
    case M.Joining{target}: add_ref(target, acc)
    case M.Waiting{object, depth}: add_ref(object, acc)
    case M.Reacquire{object, depth, interrupted}: add_ref(object, acc)
    case _: acc

@unsafe def thread_saved_refs(current: Bool, frames: +List<M.Frame>, exception: U32, result: M.Slot, effect: M.Effect, cont: +List<M.Cont>, +acc: +List<U32>) -> +List<U32>:
  match current:
    # The running thread's registers live in the VM; this saved copy is stale.
    case True{}: acc
    case False{}: frames_refs(frames, add_ref(exception, slot_ref(result, effect_refs(effect, conts_refs(cont, acc)))))

@unsafe def threads_refs(threads: +List<M.ThreadState>, +current: U32, +acc: +List<U32>) -> +List<U32>:
  match threads:
    case Nil{}: acc
    case Con{M.ThreadState{+id, object, daemon, interrupted, wait, timed, deadline, seq, priority, frames, status, exception, result, effect, cont}, rest}:
      threads_refs(rest, current, thread_saved_refs(U32.is_eq(id, current), frames, exception, result, effect, cont, add_ref(object, wait_refs(wait, acc))))

def monitors_refs(monitors: +List<M.Monitor>, +acc: +List<U32>) -> +List<U32>:
  match monitors:
    case Nil{}: acc
    case Con{M.Monitor{object, owner, depth}, rest}: monitors_refs(rest, add_ref(object, acc))

def sites_refs(sites: +List<M.DynamicSite>, +acc: +List<U32>) -> +List<U32>:
  match sites:
    case Nil{}: acc
    case Con{M.DynamicSite{method, pc, owner, constant, state, callsite, failure}, rest}: sites_refs(rest, add_ref(callsite, add_ref(failure, acc)))

def defined_refs(defined: +List<M.DefinedClass>, +acc: +List<U32>) -> +List<U32>:
  match defined:
    case Nil{}: acc
    case Con{M.DefinedClass{class, loader}, rest}: defined_refs(rest, add_ref(loader, acc))

def loaders_refs(loaders: M.Loaders, +acc: +List<U32>) -> +List<U32>:
  match loaders:
    case M.Loaders{next, aliases, defined, pending, defining}: defined_refs(defined, acc)

def classes_refs(classes: +List<M.LoadedClass>, +acc: +List<U32>) -> +List<U32>:
  match classes:
    case Nil{}: acc
    case Con{M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods}, rest}: classes_refs(rest, bindings_refs(fields, acc))

def pinned_refs(count: Nat, +reference: U32, +acc: +List<U32>) -> +List<U32>:
  match count:
    case 0n: acc
    case 1n+p: pinned_refs(p, U32.add(reference, 1), Con{reference, acc})

@unsafe def sched_refs(s: M.Sched, +acc: +List<U32>) -> +List<U32>:
  match s:
    case M.Sched{current, nextThread, nextOp, nextSeq, threads, monitors, inits, now, wall, fuel, left, mainError, mainHandler, quantum}:
      threads_refs(threads, current, monitors_refs(monitors, acc))

@unsafe def host_refs(h: M.Host, +acc: +List<U32>) -> +List<U32>:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}:
      effect_refs(effect, conts_refs(cont, sites_refs(dynamicSites, loaders_refs(loaders, sched_refs(sched, acc)))))

@unsafe def tables_refs(r: M.Roots, +acc: +List<U32>) -> +List<U32>:
  match r:
    case M.Roots{free, live, spine, gc, stress, countdown, pinned, oom, literals, integers, longs, mirrors, closes}:
      add_ref(oom, T.values(literals, T.values(integers, T.values(longs, T.values(mirrors, pinned_refs(U32.to_nat(pinned), 1, acc))))))

# The whole root set. `frames` is passed in so a later parallel scheduler can hand
# every thread's stack to the same walk.
@unsafe def seed_refs(+vm: M.VM, frames: +List<M.Frame>) -> +List<U32>:
  frames_refs(frames, add_ref(S.exception(vm), slot_ref(S.result_slot(vm), bindings_refs(S.statics(vm), classes_refs(S.classes(vm), host_refs(S.host(vm), tables_refs(S.roots(vm), Nil{})))))))

# ---- Host handles of swept owners ----------------------------------------------

def field_named(fields: +List<M.LoadedField>, +owner: U32, +name: String, +symbols: +List<String>) -> U32:
  match fields:
    case Nil{}: 4294967295
    case Con{+field, rest}: Bool.pick(U32, U32.is_eq(M.loaded_field_owner(field), owner) && H.symbol_equal(M.nth(String, symbols, M.loaded_field_name(field)), name), M.loaded_field_id(field), field_named(rest, owner, name, symbols))

def owner_for(+vm: M.VM, +class: String) -> C.Owner:
  +id : U32 = H.named_class(S.classes(vm), S.symbols(vm), class)
  C.Owner{field_named(S.fields(vm), id, "handle", S.symbols(vm)), field_named(S.fields(vm), id, "closed", S.symbols(vm))}

def socket_owners(+vm: M.VM) -> +List<C.Owner>:
  [owner_for(vm, "java/net/Socket"), owner_for(vm, "java/net/ServerSocket"), owner_for(vm, "java/nio/channels/SocketChannel"), owner_for(vm, "java/nio/channels/ServerSocketChannel")]

# ---- Sweep ---------------------------------------------------------------------

def sweep_finish(swept: C.Swept, reuse: Bool, +vm: M.VM, gc: U32) -> M.VM:
  match swept:
    case C.Swept{kept, free, live, closes}:
      S.with_roots(S.with_heap(vm, M.reverse(M.HeapEntry, kept)), S.roots_swept(S.roots(vm), Bool.pick(+List<U32>, reuse, M.reverse(U32, free), Nil{}), live, closes, gc))

def collected_gc(+old: U32) -> U32:
  Bool.pick(U32, U32.is_eq(old, 3), 3, 0)

@unsafe def collect_marked(found: Maybe<&2, M.Trie>, +vm: M.VM) -> M.VM:
  match found:
    case None{}: S.fail(vm, "InvalidState: collection exceeded the heap length")
    case Some{+seen}:
      +roots : M.Roots = S.roots(vm)
      +mode : U32 = S.roots_gc(roots)
      sweep_finish(C.sweep_go(S.heap(vm), 1, seen, socket_owners(vm), C.empty_swept(S.roots_closes(roots))), U32.is_ne(mode, 3), vm, collected_gc(mode))

@unsafe def collect_with(+vm: M.VM, +spine: U32) -> M.VM:
  collect_marked(C.mark_heap(S.heap(vm), seed_refs(vm, S.frames(vm)), spine), vm)

# Collects every object the roots do not reach. Identity is stable: live objects
# keep their reference numbers; the slots of dead ones go on the free list.
@unsafe def collect(+vm: M.VM) -> M.VM:
  collect_with(vm, S.roots_spine(S.roots(vm)))

def with_gc(+vm: M.VM, value: U32) -> M.VM:
  S.with_roots(vm, S.roots_with_gc(S.roots(vm), value))

# Mode 2 turns allocation failures back on for the redo of an instruction.
@unsafe def strict(+vm: M.VM) -> M.VM:
  with_gc(collect(vm), 2)

def clear_strict(+vm: M.VM) -> M.VM:
  with_gc(vm, 0)

def fits(+vm: M.VM) -> Bool:
  U32.is_le(S.roots_live(S.roots(vm)), S.max_heap(vm))

def stress_tick(+vm: M.VM) -> M.VM:
  S.with_roots(vm, S.roots_with_countdown(S.roots(vm), U32.sub(S.roots_countdown(S.roots(vm)), 1)))

@unsafe def stress_due(due: Bool, +vm: M.VM) -> M.VM:
  match due:
    case True{}:
      +after : M.VM = collect(vm)
      S.with_roots(after, S.roots_with_countdown(S.roots(after), S.roots_stress(S.roots(after))))
    case False{}: stress_tick(vm)

# Stress mode (--gc-stress N): collect every N instructions and never reuse a
# slot, so a missing root surfaces as InvalidReference. Testing only.
@unsafe def stress(+vm: M.VM) -> M.VM:
  stress_due(U32.is_eq(S.roots_countdown(S.roots(vm)), 0), vm)
