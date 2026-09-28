import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../runtime/frame.bend as F
import ../runtime/wide.bend as W
import ../runtime/value.bend as V
import ../heap/heap.bend as H
import ../loader/bootstrap.bend as B
import ../loader/symbols.bend as Sy
import ../java/intrinsic.bend as I
import ../java/outcome.bend as O
import ../java/library.bend as L

@unsafe def class_id_by_name(classes: +List<M.LoadedClass>, +name: U32) -> Maybe<&2, U32>:
  match classes:
    case Nil{}: None{}
    case Con{+value, rest}:
      Bool.pick(Maybe<&2, U32>, U32.is_eq(M.loaded_class_name(value), name), Some{M.loaded_class_id(value)}, class_id_by_name(rest, name))

@unsafe def own_method(methods: +List<M.LoadedMethod>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+value, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(value), owner) && U32.is_eq(M.loaded_method_name(value), name) && U32.is_eq(M.loaded_method_descriptor(value), descriptor), Some{value}, own_method(rest, owner, name, descriptor))

def class_parent(value: M.LoadedClass) -> U32:
  M.loaded_class_parent(value)

def method_continue(found: Maybe<&2, M.LoadedMethod>, parent: U32, next: U32 -> Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case Some{value}: Some{value}
    case None{}:
      match parent:
        case 4294967295: None{}
        case value: next(value)

def class_parent_found(found: Maybe<&2, M.LoadedClass>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{value}: class_parent(value)

@unsafe def method_hierarchy(fuel: Nat, +classes: +List<M.LoadedClass>, +methods: +List<M.LoadedMethod>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      method_continue(own_method(methods, owner, name, descriptor), class_parent_found(M.nth(M.LoadedClass, classes, owner)), parent => method_hierarchy(p, classes, methods, parent, name, descriptor))

def find_method_id(found: Maybe<&2, U32>, classes: +List<M.LoadedClass>, methods: +List<M.LoadedMethod>, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{owner}: method_hierarchy(256n, classes, methods, owner, name, descriptor)

def find_method(+classes: +List<M.LoadedClass>, +methods: +List<M.LoadedMethod>, +owner_name: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  find_method_id(class_id_by_name(classes, owner_name), classes, methods, name, descriptor)

def method_instruction(value: M.LoadedMethod, pc: U32) -> Maybe<&2, M.Instruction>:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      M.nth(M.Instruction, instructions, pc)

def method_max_stack(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}: maxStack

def method_max_locals(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}: maxLocals

def method_result_tag(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}: resultTag

def method_parameters(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}: parameters

def method_intrinsic(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}: intrinsic

def make_locals(n: Nat) -> +List<M.Slot>:
  M.zeros(n)

def argument_width(value: M.Slot) -> Nat:
  match value:
    case M.Slot{+tag, bits}:
      Bool.pick(Nat, Bool.or(U32.is_eq(tag, 4), U32.is_eq(tag, 5)), 2n, 1n)

@unsafe def copy_arguments(values: +List<M.Slot>, +locals: +List<M.Slot>, +index: Nat) -> +List<M.Slot>:
  match values:
    case Nil{}: locals
    case Con{+value, rest}:
      copy_arguments(rest, M.replace(M.Slot, locals, index, value), Nat.add(index, argument_width(value)))

def host_cont_of(h: M.Host) -> +List<M.Cont>:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata}: cont

def host_cont(vm: M.VM) -> +List<M.Cont>:
  host_cont_of(S.host(vm))

@unsafe def return_frames(+vm: M.VM, value: M.Slot, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: S.with_result(S.with_status(vm, 1), value)
    case Con{current, rest}:
      match rest:
        case Nil{}: S.with_result(S.with_status(vm, 1), value)
        case Con{+caller, callers}:
          S.with_frames(vm, Con{S.frame_stack(caller, Con{value, S.stack(caller)}), callers})


def push_return(+vm: M.VM, value: M.Slot) -> M.VM:
  return_frames(vm, value, S.frames(vm))


def finish_reflect_outcome(+vm: M.VM, result: Result<&2, &2, String, O.Outcome>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{O.Returned{+updated, Some{value}}}:
      +frames = S.frames(updated)
      return_frames(updated, value, frames)
    case Done{O.Returned{+updated, None{}}}:
      +frames = S.frames(updated)
      return_frames(updated, M.Slot{3, 0}, frames)
    case Done{O.ThrownRef{updated, reference}}: S.with_status(S.with_exception(updated, reference), 6)
    case Done{O.ThrownName{updated, name}}: S.fail(updated, name)
    case Done{O.Suspend{updated, effect}}: S.with_effect(updated, effect)
    case Done{O.Call{updated, method, args}}: S.fail(updated, "VmError.Internal: nested reflection call")

def reflected_marker(marker: U32) -> Maybe<&2, U32>:
  +marker_ref : U32 = marker
  take : Bool = U32.is_eq(marker_ref, 4294967294)
  Bool.pick(Maybe<&2, U32>, take, Some{0}, None{})

def reflected_descriptor(frame: M.Frame) -> Maybe<&2, U32>:
  reflected_marker(S.initializing(frame))

def reflected_method_descriptor_found(found: Maybe<&2, M.LoadedMethod>) -> U32:
  match found:
    case None{}: 0
    case Some{method}: M.loaded_method_descriptor(method)

def reflected_method_descriptor(vm: M.VM, frame: M.Frame) -> U32:
  reflected_method_descriptor_found(M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)))

def finish_reflect_marked(+vm: M.VM, value: M.Slot, +current: M.Frame, +caller: M.Frame, +callers: +List<M.Frame>, descriptor: U32) -> M.VM:
  +vm_ref : M.VM = vm
  descriptor_id : U32 = reflected_method_descriptor(vm_ref, current)
  clean : M.Frame = S.frame_initializing(caller, 4294967295)
  +cleared : M.VM = S.with_cont(S.with_effect(vm, M.Idle{}), Nil{})
  +updated : M.VM = S.with_frames(cleared, Con{current, Con{clean, callers}})
  +text : String = Sy.text(S.symbols(updated), descriptor_id)
  finish_reflect_outcome(updated, L.reflect_box_return(updated, text, value))

def finish_return_found(+vm: M.VM, value: M.Slot, current: M.Frame, +caller: M.Frame, +callers: +List<M.Frame>, found: Maybe<&2, U32>) -> M.VM:
  match found:
    case None{}: push_return(vm, value)
    case Some{descriptor}: finish_reflect_marked(vm, value, current, caller, callers, descriptor)

def finish_return_marked(+vm: M.VM, value: M.Slot, +frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{current, Con{+caller, callers}}:
      finish_return_found(vm, value, current, caller, callers, reflected_descriptor(caller))
    case _: push_return(vm, value)

def proxy_return_frames(+vm: M.VM, value: M.Slot, +frames: +List<M.Frame>, +descriptor: String) -> M.VM:
  match frames:
    case Con{current, Con{+caller, callers}}:
      M.Frame{method, pc, invoke, locals, +stack, initializing} = caller
      +return_name : String = L.method_return_name(descriptor)
      +next_stack : +List<M.Slot> = Bool.pick(+List<M.Slot>, String.eq(return_name, "void"), stack, Con{value, stack})
      S.with_frames(vm, Con{M.Frame{method, pc, invoke, locals, next_stack, initializing}, callers})
    case _: S.with_result(S.with_status(vm, 1), value)

def allocate_named_result(+vm: M.VM, name: String, result: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match result:
    case Fail{error}: S.with_exception(vm, 2)
    case Done{allocation}:
      match allocation:
        case H.Allocation{updated, reference}: S.with_exception(updated, reference)

def allocate_named(+vm: M.VM, +name: String) -> M.VM:
  allocate_named_result(vm, name, H.allocate(vm, H.throwable_entry(H.named_class(S.classes(vm), S.symbols(vm), name))))

def ensure_throw(+vm: M.VM, error: String) -> M.VM:
  Bool.pick(M.VM, U32.is_ne(S.exception(vm), 0), vm, allocate_named(vm, error))

def proxy_return_failure(error: String, +vm: M.VM, +frames: +List<M.Frame>) -> M.VM:
  S.with_status(ensure_throw(vm, error), 6)

def finish_proxy_return_value(result: Result<&2, &2, String, M.Slot>, +vm: M.VM, +frames: +List<M.Frame>, +descriptor: String) -> M.VM:
  match result:
    case Fail{error}: proxy_return_failure(error, vm, frames)
    case Done{unboxed}: proxy_return_frames(vm, unboxed, frames, descriptor)

def finish_proxy_return(+vm: M.VM, value: M.Slot, +current: M.Frame, +caller: M.Frame, +callers: +List<M.Frame>, +descriptor: String) -> M.VM:
  +clean : M.Frame = S.frame_initializing(caller, 4294967295)
  +cleared : M.VM = S.with_cont(S.with_effect(vm, M.Idle{}), Nil{})
  +updated : M.VM = S.with_frames(cleared, Con{current, Con{clean, callers}})
  finish_proxy_return_value(L.proxy_return_value(updated, descriptor, value), updated, S.frames(updated), descriptor)

def finish_proxy_return_frames(+vm: M.VM, value: M.Slot, +frames: +List<M.Frame>, +descriptor: String) -> M.VM:
  match frames:
    case Con{current, Con{+caller, callers}}: finish_proxy_return(vm, value, current, caller, callers, descriptor)
    case _: push_return(vm, value)

def finish_return_effect(+vm: M.VM, value: M.Slot, +frames: +List<M.Frame>, effect: M.Effect) -> M.VM:
  match effect:
    case M.ProxyCall{descriptor, exceptions}: finish_proxy_return_frames(vm, value, frames, descriptor)
    case _: finish_return_marked(vm, value, frames)

def finish_return(+vm: M.VM, value: M.Slot) -> M.VM:
  +frames = S.frames(vm)
  finish_return_effect(vm, value, frames, S.host_effect(vm))
def void_frames(+vm: M.VM, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: S.with_status(vm, 1)
    case Con{current, rest}:
      match rest:
        case Nil{}: S.with_status(vm, 1)
        case Con{caller, callers}: S.with_frames(vm, Con{caller, callers})

def finish_void_state(+vm: M.VM, current: M.Frame, rest: +List<M.Frame>, state: U32) -> M.VM:
  match state:
    case 4294967295: void_frames(vm, Con{current, rest})
    case owner: void_frames(S.set_class_state(vm, owner, 2), Con{current, rest})

def finish_void_current(+vm: M.VM, +current: M.Frame, +rest: +List<M.Frame>) -> M.VM:
  finish_void_state(vm, current, rest, S.initializing(current))

def finish_void_frames(+vm: M.VM, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: S.with_status(vm, 1)
    case Con{current, rest}: finish_void_current(vm, current, rest)

def finish_reflect_void(+vm: M.VM, +frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{current, Con{+caller, callers}}:
      +cleared : M.VM = S.with_effect(vm, M.Idle{})
      return_frames(cleared, M.Slot{3, 0}, Con{current, Con{caller, callers}})
    case _: S.fail(vm, "InvalidState: reflective void return")

def finish_construct_frames(+vm: M.VM, reference: U32, +frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{current, Con{+caller, callers}}:
      +cleared : M.VM = S.with_effect(vm, M.Idle{})
      return_frames(cleared, M.Slot{3, reference}, Con{current, Con{caller, callers}})
    case _: S.fail(vm, "InvalidState: constructor return")

def constructor_reference_marker(marker: U32) -> Maybe<&2, U32>:
  +marker_ref : U32 = marker
  take : Bool = U32.is_le(marker_ref, 4294967292)
  Bool.pick(Maybe<&2, U32>, take, Some{U32.sub(4294967293, marker_ref)}, None{})

def constructor_reference_frame(frame: M.Frame) -> Maybe<&2, U32>:
  constructor_reference_marker(S.initializing(frame))

def invoke_class_initializer_frame(vm: M.VM, id: U32, maxLocals: U32, owner: U32, +caller: M.Frame, values: +List<M.Slot>, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{old, rest}:
      S.with_frames(vm, Con{M.Frame{id, 0, S.pc(caller), copy_arguments(values, make_locals(U32.to_nat(maxLocals)), 0n), Nil{}, owner}, Con{S.advance(caller), rest}})
    case Nil{}:
      S.fail(vm, "InvalidState: initializer invocation without caller")

def invoke_class_initializer(+vm: M.VM, method: M.LoadedMethod, +args: +List<M.Slot>, +caller: M.Frame) -> M.VM:
  match method:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      invoke_class_initializer_frame(vm, id, maxLocals, owner, caller, args, S.frames(vm))
def finish_class_for_name_call(+updated: M.VM, method: M.LoadedMethod, +args: +List<M.Slot>, +rest: +List<M.Frame>) -> M.VM:
  match rest:
    case Con{+caller, callers}:
      invoke_class_initializer(S.with_frames(updated, rest), method, args, caller)
    case Nil{}:
      S.fail(updated, "InvalidState: Class.forName continuation without caller")

def finish_class_for_name_outcome(+vm: M.VM, target: U32, +frames: +List<M.Frame>, +rest: +List<M.Frame>, outcome: O.Outcome) -> M.VM:
  match outcome:
    case O.Returned{+updated, Some{value}}:
      return_frames(S.with_effect(updated, M.Idle{}), value, frames)
    case O.Returned{updated, None{}}:
      S.fail(vm, "InvalidState: Class.forName returned no mirror")
    case O.Call{+updated, method, +args}: finish_class_for_name_call(updated, method, args, rest)
    case O.ThrownName{updated, name}:
      S.fail(updated, name)
    case O.ThrownRef{updated, reference}:
      S.with_status(S.with_exception(updated, reference), 6)
    case O.Suspend{updated, effect}:
      S.fail(updated, "InvalidState: Class.forName suspended")

def finish_class_for_name_result(+ready: M.VM, +target: U32, +frames: +List<M.Frame>, +rest: +List<M.Frame>, result: Result<&2, &2, String, O.Outcome>) -> M.VM:
  match result:
    case Fail{error}: S.fail(ready, error)
    case Done{outcome}: finish_class_for_name_outcome(ready, target, frames, rest, outcome)

def finish_class_for_name(+vm: M.VM, +frames: +List<M.Frame>, +target: U32) -> M.VM:
  match frames:
    case Con{current, rest}:
      +ready : M.VM = S.set_class_state(vm, S.initializing(current), 2)
      result : Result<&2, &2, String, O.Outcome> = L.class_for_name_continue(ready, target)
      finish_class_for_name_result(ready, target, frames, rest, result)
    case _: S.fail(vm, "InvalidState: Class.forName initializer return")

def finish_void_effect(+vm: M.VM, +frames: +List<M.Frame>, effect: M.Effect) -> M.VM:
  match effect:
    case M.ReflectCall{}: finish_reflect_void(vm, frames)
    case M.ReflectConstructor{reference}: finish_construct_frames(vm, reference, frames)
    case M.ClassForName{target}: finish_class_for_name(vm, frames, target)
    case _: finish_void_frames(vm, frames)
def finish_void_marked_found(+vm: M.VM, +frames: +List<M.Frame>, effect: M.Effect, current: M.Frame, +caller: M.Frame, +callers: +List<M.Frame>, found: Maybe<&2, U32>) -> M.VM:
  match found:
    case Some{reference}: finish_construct_frames(vm, reference, frames)
    case None{}: finish_void_effect(vm, frames, effect)
def finish_void_marked(+vm: M.VM, +frames: +List<M.Frame>, effect: M.Effect) -> M.VM:
  match frames:
    case Con{current, Con{+caller, callers}}:
      finish_void_marked_found(vm, frames, effect, current, caller, callers, constructor_reference_frame(caller))
    case _: finish_void_effect(vm, frames, effect)



def finish_void(+vm: M.VM) -> M.VM:
  +frames = S.frames(vm)
  +effect = S.host_effect(vm)
  finish_void_marked(vm, frames, effect)

def invoke_frame(vm: M.VM, id: U32, maxLocals: U32, +caller: M.Frame, values: +List<M.Slot>, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{old, rest}:
      S.with_frames(vm, Con{M.Frame{id, 0, S.pc(caller), copy_arguments(values, make_locals(U32.to_nat(maxLocals)), 0n), Nil{}, 4294967295}, Con{S.advance(caller), rest}})
    case Nil{}:
      S.fail(vm, "InvalidState: invocation without caller")

def invoke_arguments(vm: M.VM, method: M.LoadedMethod, args: F.Arguments, frames: +List<M.Frame>) -> M.VM:
  match method:
    case M.LoadedMethod{id, owner0, name0, descriptor0, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      match args:
        case F.Arguments{caller, values}:
          invoke_frame(vm, id, maxLocals, caller, values, frames)

def invoke_reflect(+vm: M.VM, +method: M.LoadedMethod, +args: +List<M.Slot>, +caller: M.Frame) -> M.VM:
  +method_ref : M.LoadedMethod = method
  +caller_ref : M.Frame = caller
  +marked : M.Frame = S.frame_initializing(caller_ref, 4294967294)
  invoke_arguments(vm, method_ref, F.Arguments{marked, args}, S.frames(vm))

def invoke_constructor(+vm: M.VM, method: M.LoadedMethod, +args: +List<M.Slot>, +caller: M.Frame, reference: U32) -> M.VM:
  +caller_ref : M.Frame = caller
  marked : M.Frame = S.frame_initializing(caller_ref, U32.sub(4294967293, reference))
  +cleared : M.VM = S.with_effect(vm, M.Idle{})
  invoke_arguments(cleared, method, F.Arguments{marked, args}, S.frames(cleared))

def invoke_proxy(+vm: M.VM, method: M.LoadedMethod, +args: +List<M.Slot>, +caller: M.Frame) -> M.VM:
  invoke_arguments(vm, method, F.Arguments{caller, args}, S.frames(vm))


def invoke_outcome_effect(+vm: M.VM, method: M.LoadedMethod, +args: +List<M.Slot>, +caller: M.Frame, effect: M.Effect) -> M.VM:
  match effect:
    case M.ReflectConstructor{reference}: invoke_constructor(vm, method, args, caller, reference)
    case M.ReflectCall{}: invoke_reflect(vm, method, args, caller)
    case M.ProxyCall{descriptor, exceptions}: invoke_proxy(vm, method, args, caller)
    case M.ClassForName{target}: invoke_class_initializer(vm, method, args, caller)
    case _: invoke_arguments(vm, method, F.Arguments{caller, args}, S.frames(vm))

def invoke_outcome(+vm: M.VM, method: M.LoadedMethod, +args: +List<M.Slot>, caller: M.Frame) -> M.VM:
  +effect = S.host_effect(vm)
  invoke_outcome_effect(vm, method, args, caller, effect)

def intrinsic_value(+vm: M.VM, frame: M.Frame, value: Maybe<&2, M.Slot>, max: U32) -> Result<&2, &2, String, M.VM>:
  match value:
    case None{}:
      Done{S.commit(vm, S.advance(frame))}
    case Some{slot}:
      do Result<&2, &2, String, M.VM>:
        pushed : M.Frame <- F.push(S.advance(frame), slot, max)
        return S.commit(vm, pushed)

def intrinsic_outcome(frame: M.Frame, max: U32, outcome: O.Outcome) -> Result<&2, &2, String, M.VM>:
  match outcome:
    case O.Returned{updated, value}:
      intrinsic_value(updated, frame, value, max)
    case O.ThrownRef{updated, reference}:
      Done{S.with_status(S.with_exception(updated, reference), 6)}
    case O.ThrownName{updated, name}:
      Fail{name}
    case O.Suspend{updated, effect}:
      Done{S.commit(updated, frame)}
    case O.Call{+updated, method, args}:
      Done{invoke_outcome(updated, method, args, frame)}

def intrinsic_result(frame: M.Frame, max: U32, result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{outcome}:
      intrinsic_outcome(frame, max, outcome)

def intrinsic_args(+vm: M.VM, +method: M.LoadedMethod, args: F.Arguments, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, values}:
      intrinsic_result(frame, max, I.execute_vm(method_intrinsic(method), vm, values))

def dispatch_intrinsic(+vm: M.VM, method: M.LoadedMethod, args: F.Arguments, intrinsic: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  match intrinsic:
    case 0: Done{invoke_arguments(vm, method, args, S.frames(vm))}
    case other: intrinsic_args(vm, method, args, max)

def dispatch_method(+vm: M.VM, +method: M.LoadedMethod, args: F.Arguments, max: U32) -> Result<&2, &2, String, M.VM>:
  dispatch_intrinsic(vm, method, args, method_intrinsic(method), max)

def receiver_slot(stack: +List<M.Slot>, count: Nat) -> Maybe<&2, M.Slot>:
  match stack:
    case Nil{}: None{}
    case Con{+receiver, rest}:
      match count:
        case 0n: Some{receiver}
        case 1n+p: receiver_slot(rest, p)
def dispatch_virtual_kind(kind: U32, +vm: M.VM, +method: M.LoadedMethod, frame: M.Frame, max: U32, +name: String, +descriptor: String, +values: +List<M.Slot>) -> Result<&2, &2, String, M.VM>:
  match kind:
    case 9: intrinsic_result(frame, max, L.annotation_invoke(vm, values, name, descriptor))
    case 10: intrinsic_result(frame, max, L.proxy_invoke(vm, method, values, name, descriptor))
    case _: dispatch_method(vm, method, F.Arguments{frame, values}, max)

def dispatch_virtual_entry(result: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM, +method: M.LoadedMethod, frame: M.Frame, max: U32, +name: String, +descriptor: String, +values: +List<M.Slot>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}: dispatch_virtual_kind(L.entry_kind(entry), vm, method, frame, max, name, descriptor, values)

def dispatch_virtual_loaded(+vm: M.VM, +method: M.LoadedMethod, args: F.Arguments, max: U32, +name: String, +descriptor: String) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, +values}:
      match values:
        case Con{receiver, rest}: dispatch_virtual_entry(H.get(S.heap(vm), V.slot_bits(receiver)), vm, method, frame, max, name, descriptor, values)
        case Nil{}: dispatch_method(vm, method, F.Arguments{frame, values}, max)

def invoke_virtual_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, frame: M.Frame, count: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchMethodError: virtual-found"}
    case Some{+method}:
      do Result<&2, &2, String, M.VM>:
        args : F.Arguments <- F.arguments(frame, U32.add(method_parameters(method), count))
        result : M.VM <- dispatch_virtual_loaded(vm, method, args, max, Sy.text(S.symbols(vm), M.loaded_method_name(method)), Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)))
        return result
def invoke_virtual_annotation_args(args: F.Arguments, +vm: M.VM, max: U32, +name: String, +descriptor: String) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, +values}: intrinsic_result(frame, max, L.annotation_invoke(vm, values, name, descriptor))

def invoke_virtual_reflect_default(args: F.Arguments, +vm: M.VM, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, +values}: intrinsic_result(frame, max, L.reflect_method_is_default(vm, values))
def invoke_virtual_reflect_generic_return(args: F.Arguments, +vm: M.VM, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, +values}: intrinsic_result(frame, max, L.reflect_method_generic_return(vm, values))

def invoke_virtual_reflect_generic_parameters(args: F.Arguments, +vm: M.VM, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, +values}: intrinsic_result(frame, max, L.reflect_method_generic_parameter_types(vm, values))
def invoke_virtual_reflect_generic_exceptions(args: F.Arguments, +vm: M.VM, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, +values}: intrinsic_result(frame, max, L.reflect_method_get_generic_exception_types(vm, values))




def invoke_virtual_missing(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, frame: M.Frame, +name: U32, +descriptor: U32, max: U32, +name_text: String, +descriptor_text: String) -> Result<&2, &2, String, M.VM>:
  match found:
    case Some{+method}: invoke_virtual_found(Some{method}, vm, frame, 1, max)
    case None{}:
      match name_text:
        case "annotationType":
          do Result<&2, &2, String, M.VM>:
            args : F.Arguments <- F.arguments(frame, 1)
            result : M.VM <- invoke_virtual_annotation_args(args, vm, max, name_text, descriptor_text)
            return result
        case "isDefault":
          do Result<&2, &2, String, M.VM>:
            args : F.Arguments <- F.arguments(frame, 1)
            result : M.VM <- invoke_virtual_reflect_default(args, vm, max)
            return result
        case "getGenericReturnType":
          do Result<&2, &2, String, M.VM>:
            args : F.Arguments <- F.arguments(frame, 1)
            result : M.VM <- invoke_virtual_reflect_generic_return(args, vm, max)
            return result
        case "getGenericParameterTypes":
          do Result<&2, &2, String, M.VM>:
            args : F.Arguments <- F.arguments(frame, 1)
            result : M.VM <- invoke_virtual_reflect_generic_parameters(args, vm, max)
            return result
        case "getGenericExceptionTypes":
          do Result<&2, &2, String, M.VM>:
            args : F.Arguments <- F.arguments(frame, 1)
            result : M.VM <- invoke_virtual_reflect_generic_exceptions(args, vm, max)
            return result
        case _: Fail{"NoSuchMethodError: " ++ name_text ++ descriptor_text}

def default_method(found: Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{+method}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(U32.and(M.loaded_method_flags(method), 1024), 0), Some{method}, None{})

def virtual_method_class(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case Some{method}: Some{method}
    case None{}: default_method(find_method_id(Some{owner}, S.classes(vm), S.methods(vm), name, descriptor))

def virtual_method_entry_kind(kind: U32, +vm: M.VM, +owner: U32, +name: U32, +descriptor: U32, entry_class: U32) -> Maybe<&2, M.LoadedMethod>:
  match kind:
    case 10: find_method(S.classes(vm), S.methods(vm), owner, name, descriptor)
    case _: virtual_method_class(find_method_id(Some{entry_class}, S.classes(vm), S.methods(vm), name, descriptor), vm, owner, name, descriptor)

def virtual_method_entry(result: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match result:
    case Fail{error}: find_method(S.classes(vm), S.methods(vm), owner, name, descriptor)
    case Done{M.HeapEntry{class_id, kind, element, fields, values, chars}}: virtual_method_entry_kind(kind, vm, owner, name, descriptor, class_id)

def virtual_method_stack_found(found: Maybe<&2, M.Slot>, +vm: M.VM, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{+receiver}: virtual_method_entry(H.get(S.heap(vm), V.slot_bits(receiver)), vm, owner, name, descriptor)

def virtual_method_stack_case(+vm: M.VM, +stack: +List<M.Slot>, +owner: U32, +name: U32, +descriptor: U32, count: Nat) -> Maybe<&2, M.LoadedMethod>:
  virtual_method_stack_found(receiver_slot(stack, count), vm, owner, name, descriptor)

def invoke_virtual_method(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stack: +List<M.Slot>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{method}: virtual_method_stack_case(vm, stack, owner, name, descriptor, U32.to_nat(method_parameters(method)))

def virtual_method_stack(+vm: M.VM, +frame: M.Frame, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  invoke_virtual_method(find_method(S.classes(vm), S.methods(vm), owner, name, descriptor), vm, S.stack(frame), owner, name, descriptor)

def invoke_virtual(+vm: M.VM, +frame: M.Frame, owner: U32, +name: U32, +descriptor: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  invoke_virtual_missing(virtual_method_stack(vm, frame, owner, name, descriptor), vm, frame, name, descriptor, max, Sy.text(S.symbols(vm), name), Sy.text(S.symbols(vm), descriptor))
def invoke_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, frame: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchMethodError"}
    case Some{+method}:
      do Result<&2, &2, String, M.VM>:
        args : F.Arguments <- F.arguments(frame, method_parameters(method))
        result : M.VM <- dispatch_method(vm, method, args, max)
        return result

def invoke_static(+vm: M.VM, frame: M.Frame, owner: U32, name: U32, descriptor: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  invoke_found(find_method(S.classes(vm), S.methods(vm), owner, name, descriptor), vm, frame, max)
def invoke_special(+vm: M.VM, frame: M.Frame, owner: U32, name: U32, descriptor: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  invoke_virtual_found(find_method(S.classes(vm), S.methods(vm), owner, name, descriptor), vm, frame, 1, max)


def store_popped(vm: M.VM, popped: F.Popped, index: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, value}:
      do Result<&2, &2, String, M.VM>:
        updated : M.Frame <- F.set_local(next, index, value)
        return S.commit(vm, S.advance(updated))

def negate_popped(vm: M.VM, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      Done{S.commit(vm, S.frame_stack(S.advance(next), Con{M.Slot{1, V.negate(V.slot_bits(value))}, S.stack(next)}))}
def drop_popped(vm: M.VM, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, value}:
      Done{S.commit(vm, S.advance(next))}

def binary_value(op: U32, left: U32, right: U32) -> U32:
  match op:
    case 96: (left + right : U32)
    case 100: (left - right : U32)
    case 104: (left * right : U32)
    case 108: V.signed_div(left, right)
    case 112: V.signed_rem(left, right)
    case 120: V.shift_left(left, right)
    case 122: V.shift_signed(left, right)
    case 124: V.shift_unsigned(left, right)
    case 126: U32.and(left, right)
    case 128: U32.or(left, right)
    case 130: U32.xor(left, right)
    case _: V.signed_rem(left, right)

def binary_zero(+op: U32, right: U32) -> Bool:
  Bool.and(U32.is_eq(right, 0), Bool.or(U32.is_eq(op, 108), U32.is_eq(op, 112)))
def binary_finish_case(vm: M.VM, +op: U32, +first_value: M.Slot, +second_frame: M.Frame, +second_value: M.Slot, zero: Bool) -> Result<&2, &2, String, M.VM>:
  match zero:
    case True{}:
      Fail{"java/lang/ArithmeticException"}
    case False{}:
      Done{S.commit(vm, S.frame_stack(S.advance(second_frame), Con{M.Slot{1, binary_value(op, V.slot_bits(second_value), V.slot_bits(first_value))}, S.stack(second_frame)}))}

def binary_finish(vm: M.VM, +op: U32, +first_value: M.Slot, second: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{+second_frame, second_value} = second
  binary_finish_case(vm, op, first_value, second_frame, second_value, binary_zero(op, V.slot_bits(first_value)))
def binary_second(frame: M.Frame, vm: M.VM, op: U32, first: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{first_frame, first_value} = first
  do Result<&2, &2, String, M.VM>:
    second : F.Popped <- F.pop(first_frame, 1)
    result : M.VM <- binary_finish(vm, op, first_value, second)
    return result

def binary_int(+frame: M.Frame, vm: M.VM, op: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    first : F.Popped <- F.pop(frame, 1)
    result : M.VM <- binary_second(frame, vm, op, first)
    return result
def compare_bool(op: U32, +left: U32, +right: U32) -> U32:
  match op:
    case 159: Bool.pick(U32, U32.is_eq(left, right), 1, 0)
    case 160: Bool.pick(U32, U32.is_ne(left, right), 1, 0)
    case 161: Bool.pick(U32, V.signed_lt(left, right), 1, 0)
    case 162: Bool.pick(U32, V.signed_lt(right, left) || U32.is_eq(left, right), 1, 0)
    case 163: Bool.pick(U32, V.signed_lt(right, left), 1, 0)
    case _: Bool.pick(U32, V.signed_lt(left, right) || U32.is_eq(left, right), 1, 0)

def compare_finish(vm: M.VM, op: U32, first_value: M.Slot, second: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{+second_frame, second_value} = second
  Done{S.commit(vm, S.frame_stack(S.advance(second_frame), Con{M.Slot{1, compare_bool(op, V.slot_bits(second_value), V.slot_bits(first_value))}, S.stack(second_frame)}))}

def compare_second(frame: M.Frame, vm: M.VM, op: U32, first: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{first_frame, first_value} = first
  do Result<&2, &2, String, M.VM>:
    second : F.Popped <- F.pop(first_frame, 1)
    result : M.VM <- compare_finish(vm, op, first_value, second)
    return result

def compare_int(+frame: M.Frame, vm: M.VM, op: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    first : F.Popped <- F.pop(frame, 1)
    result : M.VM <- compare_second(frame, vm, op, first)
    return result
def branch_compare_take(op: U32, +left: U32, +right: U32) -> Bool:
  U32.is_eq(compare_bool(op, left, right), 1)

def branch_compare_finish(vm: M.VM, target: U32, op: U32, first_value: M.Slot, second: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{+second_frame, second_value} = second
  +take = branch_compare_take(op, V.slot_bits(second_value), V.slot_bits(first_value))
  +next = Bool.pick(M.Frame, take, S.frame_pc(second_frame, target), S.advance(second_frame))
  Done{S.commit(vm, next)}

def branch_compare_second(frame: M.Frame, vm: M.VM, target: U32, op: U32, first: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{first_frame, first_value} = first
  do Result<&2, &2, String, M.VM>:
    second : F.Popped <- F.pop(first_frame, 1)
    result : M.VM <- branch_compare_finish(vm, target, op, first_value, second)
    return result

def branch_compare(+frame: M.Frame, vm: M.VM, target: U32, op: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    first : F.Popped <- F.pop(frame, 1)
    result : M.VM <- branch_compare_second(frame, vm, target, op, first)
    return result

def return_popped(vm: M.VM, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, value}:
      Done{finish_return(vm, value)}

def branch_zero_finish(vm: M.VM, target: U32, +zero: Bool, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{+popped_frame, popped_value} = popped
  do Result<&2, &2, String, M.VM>:
    take : Bool = Bool.pick(Bool, U32.is_eq(V.slot_bits(popped_value), 0), zero, Bool.not(zero))
    next : M.Frame = Bool.pick(M.Frame, take, S.frame_pc(popped_frame, target), S.advance(popped_frame))
    return S.commit(vm, next)

def branch_zero(vm: M.VM, frame: M.Frame, target: U32, zero: Bool) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- branch_zero_finish(vm, target, zero, popped)
    return result

def branch_relation(op: U32, +value: U32) -> Bool:
  match op:
    case 155: V.signed_lt(value, 0)
    case 156: Bool.not(V.signed_lt(value, 0))
    case 157: V.signed_lt(0, value)
    case _: V.signed_lt(value, 0) || U32.is_eq(value, 0)

def branch_signed_finish(vm: M.VM, target: U32, op: U32, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{+popped_frame, popped_value} = popped
  do Result<&2, &2, String, M.VM>:
    next : M.Frame = Bool.pick(M.Frame, branch_relation(op, V.slot_bits(popped_value)), S.frame_pc(popped_frame, target), S.advance(popped_frame))
    return S.commit(vm, next)

def branch_signed(vm: M.VM, frame: M.Frame, target: U32, op: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- branch_signed_finish(vm, target, op, popped)
    return result


def ref_compare_take(op: U32, +left: U32, +right: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(op, 165), U32.is_eq(left, right), U32.is_ne(left, right))

def ref_compare_finish(vm: M.VM, target: U32, op: U32, first_value: M.Slot, second: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{+second_frame, second_value} = second
  +take = ref_compare_take(op, V.slot_bits(second_value), V.slot_bits(first_value))
  +next = Bool.pick(M.Frame, take, S.frame_pc(second_frame, target), S.advance(second_frame))
  Done{S.commit(vm, next)}

def ref_compare_second(frame: M.Frame, vm: M.VM, target: U32, op: U32, first: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{first_frame, first_value} = first
  do Result<&2, &2, String, M.VM>:
    second : F.Popped <- F.pop(first_frame, 3)
    result : M.VM <- ref_compare_finish(vm, target, op, first_value, second)
    return result

def ref_compare(+frame: M.Frame, vm: M.VM, target: U32, op: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    first : F.Popped <- F.pop(frame, 3)
    result : M.VM <- ref_compare_second(frame, vm, target, op, first)
    return result

def branch_ref_zero(vm: M.VM, frame: M.Frame, target: U32, zero: Bool) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 3)
    result : M.VM <- branch_zero_finish(vm, target, zero, popped)
    return result
def branch_target(vm: M.VM, frame: M.Frame, target: U32) -> Result<&2, &2, String, M.VM>:
  Done{S.commit(vm, S.frame_pc(frame, target))}

def find_field(+fields: +List<M.LoadedField>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedField>:
  match fields:
    case Nil{}: None{}
    case Con{+field, rest}:
      Bool.pick(Maybe<&2, M.LoadedField>, U32.is_eq(M.loaded_field_owner(field), owner) && U32.is_eq(M.loaded_field_name(field), name) && U32.is_eq(M.loaded_field_descriptor(field), descriptor), Some{field}, find_field(rest, owner, name, descriptor))

def find_field_owner(found: Maybe<&2, U32>, +fields: +List<M.LoadedField>, name: U32, descriptor: U32) -> Maybe<&2, M.LoadedField>:
  match found:
    case None{}: None{}
    case Some{id}: find_field(fields, id, name, descriptor)

def find_field_ref(+vm: M.VM, owner: U32, name: U32, descriptor: U32) -> Maybe<&2, M.LoadedField>:
  find_field_owner(class_id_by_name(S.classes(vm), owner), S.fields(vm), name, descriptor)

def field_get_entry(+vm: M.VM, +popped: F.Popped, field: M.LoadedField, entry: M.HeapEntry) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, values, chars}:
          do Result<&2, &2, String, M.VM>:
            checked : Unit <- S.check(U32.is_eq(kind, 0), "IncompatibleClassChangeError")
            slot : M.Slot <- S.require(M.Slot, H.binding_find(fields, M.loaded_field_id(field)), "NoSuchFieldError")
            return S.commit(vm, S.frame_stack(S.advance(next), Con{slot, S.stack(next)}))

def field_get_result(+vm: M.VM, popped: F.Popped, field: M.LoadedField, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}: field_get_entry(vm, popped, field, entry)

def field_get_found(+vm: M.VM, +popped: F.Popped, found: Maybe<&2, M.LoadedField>) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, +value}:
      match found:
        case None{}: Fail{"NoSuchFieldError"}
        case Some{field}: field_get_result(vm, popped, field, H.get(S.heap(vm), V.slot_bits(value)))
def getfield(+vm: M.VM, frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 0)
    found : Maybe<&2, M.LoadedField> = find_field_ref(vm, owner, name, descriptor)
    result : M.VM <- field_get_found(vm, popped, found)
    return result

def putfield_entry(+vm: M.VM, +value: M.Slot, +popped: F.Popped, field: M.LoadedField, entry: M.HeapEntry) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, +object}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, values, chars}:
          do Result<&2, &2, String, M.VM>:
            checked : Unit <- S.check(U32.is_eq(kind, 0), "IncompatibleClassChangeError")
            updated : M.HeapEntry = H.object_entry(class, H.binding_set(fields, M.loaded_field_id(field), value))
            return S.commit(H.put(vm, V.slot_bits(object), updated), S.advance(next))

def putfield_result(+vm: M.VM, +value: M.Slot, +popped: F.Popped, field: M.LoadedField, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}: putfield_entry(vm, value, popped, field, entry)

def putfield_found(+vm: M.VM, +value: M.Slot, +popped: F.Popped, found: Maybe<&2, M.LoadedField>) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, +object}:
      match found:
        case None{}: Fail{"NoSuchFieldError"}
        case Some{field}: putfield_result(vm, value, popped, field, H.get(S.heap(vm), V.slot_bits(object)))

def putfield_value(+vm: M.VM, +value: M.Slot, frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 0)
    found : Maybe<&2, M.LoadedField> = find_field_ref(vm, owner, name, descriptor)
    result : M.VM <- putfield_found(vm, value, popped, found)
    return result

def putfield_start(vm: M.VM, popped: F.Popped, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, value}: putfield_value(vm, value, frame, owner, name, descriptor)

def putfield(+vm: M.VM, frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 0)
    result : M.VM <- putfield_start(vm, popped, owner, name, descriptor)
    return result

def static_get_found(+vm: M.VM, +frame: M.Frame, found: Maybe<&2, M.LoadedField>) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchFieldError"}
    case Some{field}:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- S.require(M.Slot, H.binding_find(S.statics(vm), M.loaded_field_id(field)), "NoSuchFieldError")
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
def static_initializer_found(+vm: M.VM, +frame: M.Frame, +owner: U32, found: Maybe<&2, M.LoadedMethod>) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchMethodError: <clinit>"}
    case Some{+method}:
      +updated = S.set_class_state(vm, owner, 1)
      Done{S.with_frames(updated, Con{M.Frame{M.loaded_method_id(method), 0, 0, M.zeros(U32.to_nat(method_max_locals(method))), Nil{}, owner}, S.frames(updated)})}

def static_initializer_or_get(+vm: M.VM, +frame: M.Frame, +field: M.LoadedField, id: U32, initializer: U32) -> Result<&2, &2, String, M.VM>:
  match initializer:
    case 4294967295: static_get_found(S.set_class_state(vm, id, 2), frame, Some{field})
    case _: static_initializer_found(vm, frame, id, M.nth(M.LoadedMethod, S.methods(vm), initializer))

def static_initializer_parent_method(+vm: M.VM, +frame: M.Frame, +field: M.LoadedField, +id: U32, +initializer: U32, parent_id: U32, parent_initializer: U32) -> Result<&2, &2, String, M.VM>:
  match parent_initializer:
    case 4294967295: static_initializer_or_get(S.set_class_state(vm, parent_id, 2), frame, field, id, initializer)
    case _: static_initializer_found(vm, frame, parent_id, M.nth(M.LoadedMethod, S.methods(vm), parent_initializer))

def static_initializer_parent_class(+vm: M.VM, +frame: M.Frame, +field: M.LoadedField, +id: U32, +initializer: U32, found: Maybe<&2, M.LoadedClass>) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: static_initializer_or_get(vm, frame, field, id, initializer)
    case Some{parent_class}:
      M.LoadedClass{parent_id, parent_name, parent_parent, parent_interfaces, parent_fields, parent_methods, parent_initializer, parent_state} = parent_class
      match parent_state:
        case 0: static_initializer_parent_method(vm, frame, field, id, initializer, parent_id, parent_initializer)
        case _: static_initializer_or_get(vm, frame, field, id, initializer)

def static_initializer_parent(+vm: M.VM, +frame: M.Frame, +field: M.LoadedField, +id: U32, +initializer: U32, parent: U32) -> Result<&2, &2, String, M.VM>:
  match parent:
    case 4294967295: static_initializer_or_get(vm, frame, field, id, initializer)
    case parent_id: static_initializer_parent_class(vm, frame, field, id, initializer, M.nth(M.LoadedClass, S.classes(vm), parent_id))

def static_get_class(+vm: M.VM, +frame: M.Frame, +field: M.LoadedField, found: Maybe<&2, M.LoadedClass>) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchClassError"}
    case Some{class}:
      M.LoadedClass{id, name0, parent, interfaces, fields, methods, initializer, state} = class
      match state:
        case 0: static_initializer_parent(vm, frame, field, id, initializer, parent)
        case 3: Fail{"NoClassDefFoundError"}
        case _: static_get_found(vm, frame, Some{field})

def static_get_field(+vm: M.VM, +frame: M.Frame, found: Maybe<&2, M.LoadedField>) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchFieldError"}
    case Some{+field}: static_get_class(vm, frame, field, M.nth(M.LoadedClass, S.classes(vm), M.loaded_field_owner(field)))

def getstatic(+vm: M.VM, +frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  static_get_field(vm, frame, find_field_ref(vm, owner, name, descriptor))

def static_put_value(+vm: M.VM, value: M.Slot, +popped: F.Popped, field: M.LoadedField) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, rest}: Done{S.commit(S.with_statics(vm, H.binding_set(S.statics(vm), M.loaded_field_id(field), value)), S.advance(next))}

def static_put_found(+vm: M.VM, value: M.Slot, +popped: F.Popped, found: Maybe<&2, M.LoadedField>) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, rest}:
      match found:
        case None{}: Fail{"NoSuchFieldError"}
        case Some{field}: static_put_value(vm, value, popped, field)

def putstatic_value(+vm: M.VM, value: M.Slot, frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 0)
    result : M.VM <- static_put_found(vm, value, popped, find_field_ref(vm, owner, name, descriptor))
    return result

def putstatic_start(+vm: M.VM, popped: F.Popped, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, +value}: static_put_found(vm, value, popped, find_field_ref(vm, owner, name, descriptor))

def putstatic(+vm: M.VM, frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 0)
    result : M.VM <- putstatic_start(vm, popped, owner, name, descriptor)
    return result

def class_found(found: Maybe<&2, U32>, classes: +List<M.LoadedClass>) -> Maybe<&2, M.LoadedClass>:
  match found:
    case None{}: None{}
    case Some{id}: M.nth(M.LoadedClass, classes, id)

def finish_allocation(+frame: M.Frame, allocation: H.Allocation) -> Result<&2, &2, String, M.VM>:
  match allocation:
    case H.Allocation{vm, reference}:
      Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{3, reference}, S.stack(frame)}))}
def new_object_alloc(frame: M.Frame, result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{allocation}: finish_allocation(frame, allocation)
def instance_fields(values: +List<M.LoadedField>, +classes: +List<M.LoadedClass>, +owner: U32) -> +List<M.Binding>:
  match values:
    case Nil{}:
      Nil{}
    case Con{+field, rest}:
      +tail = instance_fields(rest, classes, owner)
      +is_instance = U32.is_eq(U32.and(M.loaded_field_flags(field), 8), 0)
      +belongs = H.hierarchy(classes, owner, M.loaded_field_owner(field))
      Bool.pick(+List<M.Binding>, Bool.and(is_instance, belongs), Con{M.Binding{M.loaded_field_id(field), M.Slot{M.loaded_field_tag(field), 0}}, tail}, tail)

def new_object_found(found: Maybe<&2, M.LoadedClass>, +vm: M.VM, +frame: M.Frame) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoClassDefFoundError"}
    case Some{value}:
      M.LoadedClass{+id, name, parent, interfaces, fields, methods, initializer, state} = value
      new_object_alloc(frame, H.allocate(vm, H.object_entry(id, instance_fields(S.fields(vm), S.classes(vm), id))))

def new_object(+vm: M.VM, +frame: M.Frame, name: U32) -> Result<&2, &2, String, M.VM>:
  new_object_found(class_found(class_id_by_name(S.classes(vm), name), S.classes(vm)), vm, frame)

def array_entry(kind: U32, id: U32, element: U32, +values: +List<M.Slot>) -> M.HeapEntry:
  match kind:
    case 1: H.primitive_array_entry(id, element, values)
    case _: H.reference_array_entry(id, element, values)

def array_default_slot(kind: U32, +element: U32, symbols: +List<String>) -> M.Slot:
  match kind:
    case 1:
      Bool.pick(M.Slot, U32.is_eq(element, 11), M.Slot{4, 0},
        Bool.pick(M.Slot, U32.is_eq(element, 7), M.Slot{5, 0},
          Bool.pick(M.Slot, U32.is_eq(element, 6), M.Slot{2, 0}, M.Slot{1, 0})))
    case _:
      M.Slot{3, 0}

def new_array_entry(+vm: M.VM, +frame: M.Frame, id: U32, +element: U32, +kind: U32, count: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    values : +List<M.Slot> = H.filled(U32.to_nat(count), array_default_slot(kind, element, S.symbols(vm)))
    entry : M.HeapEntry = array_entry(kind, id, element, values)
    result : M.VM <- new_object_alloc(frame, H.allocate(vm, entry))
    return result

def new_array_found(found: Maybe<&2, M.LoadedClass>, +vm: M.VM, +frame: M.Frame, class_name: U32, element: U32, kind: U32, count: U32) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: new_array_entry(vm, frame, class_name, element, kind, count)
    case Some{value}:
      M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state} = value
      new_array_entry(vm, frame, id, element, kind, count)
def new_array_size(negative: Bool, found: Maybe<&2, M.LoadedClass>, +vm: M.VM, +frame: M.Frame, class_name: U32, element: U32, kind: U32, count: U32) -> Result<&2, &2, String, M.VM>:
  match negative:
    case True{}: Fail{"java/lang/NegativeArraySizeException"}
    case False{}: new_array_found(found, vm, frame, class_name, element, kind, count)

def new_array(+vm: M.VM, +frame: M.Frame, +class_name: U32, element: U32, kind: U32, +count: U32) -> Result<&2, &2, String, M.VM>:
  new_array_size(V.negative(count), class_found(class_id_by_name(S.classes(vm), class_name), S.classes(vm)), vm, frame, class_name, element, kind, count)
def array_count_popped(vm: M.VM, class_name: U32, element: U32, kind: U32, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}: new_array(vm, next, class_name, element, kind, V.slot_bits(value))

def array_count(vm: M.VM, frame: M.Frame, class_name: U32, element: U32, kind: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- array_count_popped(vm, class_name, element, kind, popped)
    return result

def array_length_entry(vm: M.VM, popped: F.Popped, entry: M.HeapEntry) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, values, chars}:
          do Result<&2, &2, String, M.VM>:
            checked : Unit <- S.check(U32.is_ne(kind, 0), "InvalidReference")
            return S.commit(vm, S.frame_stack(S.advance(next), Con{M.Slot{1, M.length(M.Slot, values)}, S.stack(next)}))

def array_length_loaded(vm: M.VM, popped: F.Popped, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}: array_length_entry(vm, popped, entry)
def array_length_popped(+vm: M.VM, +popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, +value}: array_length_loaded(vm, popped, H.get(S.heap(vm), V.slot_bits(value)))

def iinc(+vm: M.VM, +frame: M.Frame, +index: U32, delta: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, S.locals(frame), index), "InvalidLocalIndex")
    updated : M.Frame <- F.set_local(frame, index, M.Slot{1, (V.slot_bits(slot) + delta : U32)})
    return S.commit(vm, S.advance(updated))

def ref_assignable_checked(+vm: M.VM, reference: U32, target: U32, cast: Bool, +frame: M.Frame, checked: Bool) -> Result<&2, &2, String, M.VM>:
  match cast:
    case True{}:
      Bool.pick(Result<&2, &2, String, M.VM>, checked, Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{3, reference}, S.stack(frame)}))}, Fail{"java/lang/ClassCastException"})
    case False{}:
      Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{1, Bool.pick(U32, checked, 1, 0)}, S.stack(frame)}))}

def ref_assignable_target(+vm: M.VM, reference: U32, +target: U32, cast: Bool, +frame: M.Frame, class: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Bool.pick(Result<&2, &2, String, M.VM>, cast, Fail{"java/lang/ClassCastException"}, Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{1, 0}, S.stack(frame)}))})
    case Some{+target_id}: ref_assignable_checked(vm, reference, target_id, cast, frame, H.assignable(S.classes(vm), S.symbols(vm), class, target_id))

def ref_assignable_proxy_result(valid: Result<&2, &2, String, Bool>, +vm: M.VM, reference: U32, target: U32, cast: Bool, +frame: M.Frame) -> Result<&2, &2, String, M.VM>:
  match valid:
    case Fail{error}: Fail{error}
    case Done{ok}: ref_assignable_checked(vm, reference, target, cast, frame, ok)

def ref_assignable_kind(kind: U32, +vm: M.VM, +reference: U32, +target: U32, cast: Bool, +frame: M.Frame, class: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, M.VM>:
  match kind:
    case 10: ref_assignable_checked(vm, reference, target, cast, frame, True{})
    case _: ref_assignable_target(vm, reference, target, cast, frame, class, found)

def ref_assignable_frame(+vm: M.VM, reference: U32, +target: U32, cast: Bool, +frame: M.Frame, entry: M.HeapEntry) -> Result<&2, &2, String, M.VM>:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}: ref_assignable_kind(kind, vm, reference, target, cast, frame, class, class_id_by_name(S.classes(vm), target))

def ref_assignable(+vm: M.VM, reference: U32, target: U32, cast: Bool, +popped: F.Popped, entry: M.HeapEntry) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, value}: ref_assignable_frame(vm, reference, target, cast, frame, entry)

def ref_test_result(+vm: M.VM, +popped: F.Popped, target: U32, cast: Bool, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, value}:
      match result:
        case Fail{error}: Fail{error}
        case Done{entry}: ref_assignable(vm, V.slot_bits(value), target, cast, popped, entry)

def ref_test_null_slot(cast: Bool) -> M.Slot:
  Bool.pick(M.Slot, cast, M.Slot{3, 0}, M.Slot{1, 0})

def ref_test_popped(+vm: M.VM, +popped: F.Popped, target: U32, +cast: Bool) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, value}:
      Bool.pick(Result<&2, &2, String, M.VM>, U32.is_eq(V.slot_bits(value), 0), Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{ref_test_null_slot(cast), S.stack(frame)}))}, ref_test_result(vm, popped, target, cast, H.get(S.heap(vm), V.slot_bits(value))))

def ref_test(vm: M.VM, frame: M.Frame, target: U32, cast: Bool) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 0)
    result : M.VM <- ref_test_popped(vm, popped, target, cast)
    return result

def reference_store_loaded(+vm: M.VM, +value: M.Slot, +target: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, values, chars}:
          do Result<&2, &2, String, M.VM>:
            checked : Unit <- S.check(H.assignable(S.classes(vm), S.symbols(vm), class, target), "java/lang/ArrayStoreException")
            return vm

def array_store_kind(expected: U32) -> U32:
  match expected:
    case 3: 1
    case _: expected

def reference_component_found(found: Maybe<&2, U32>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{id}: id

def reference_component_id(classes: +List<M.LoadedClass>, element: U32) -> U32:
  reference_component_found(class_id_by_name(classes, element))

def reference_store_check(+vm: M.VM, +value: M.Slot, +target: U32) -> Result<&2, &2, String, M.VM>:
  Bool.pick(Result<&2, &2, String, M.VM>, U32.is_eq(V.slot_bits(value), 0), Done{vm}, reference_store_loaded(vm, value, target, H.get(S.heap(vm), V.slot_bits(value))))

def array_store_check(+vm: M.VM, +value: M.Slot, +expected: U32, +target: U32) -> Result<&2, &2, String, M.VM>:
  Bool.pick(Result<&2, &2, String, M.VM>, U32.is_eq(expected, 2), reference_store_check(vm, value, target), Done{vm})

def array_store_entry(+vm: M.VM, +value: M.Slot, +index: M.Slot, +popped: F.Popped, +expected: U32, entry: M.HeapEntry) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, +ref}:
      match entry:
        case M.HeapEntry{+class, +kind, +element, fields, +values, chars}:
          do Result<&2, &2, String, M.VM>:
            checked_kind : Unit <- S.check(U32.is_eq(kind, array_store_kind(expected)), "ArrayTypeMismatch")
            checked_index : Unit <- S.check(U32.is_lt(V.slot_bits(index), M.length(M.Slot, values)), "java/lang/ArrayIndexOutOfBoundsException")
            checked_vm : M.VM <- array_store_check(vm, value, expected, reference_component_id(S.classes(vm), element))
            updated : M.HeapEntry = M.HeapEntry{class, kind, element, fields, M.replace(M.Slot, values, U32.to_nat(V.slot_bits(index)), value), chars}
            return S.commit(H.put(checked_vm, V.slot_bits(ref), updated), S.advance(next))
def array_store_result(+vm: M.VM, +value: M.Slot, +index: M.Slot, popped: F.Popped, +expected: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}: array_store_entry(vm, value, index, popped, expected, entry)

def array_store_ref(+vm: M.VM, +value: M.Slot, +index: M.Slot, +popped: F.Popped, expected: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, +ref}: array_store_result(vm, value, index, popped, expected, H.get(S.heap(vm), V.slot_bits(ref)))

def array_store_index_popped(+vm: M.VM, +value: M.Slot, popped: F.Popped, expected: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, index}:
      do Result<&2, &2, String, M.VM>:
        ref : F.Popped <- F.pop(frame, 0)
        result : M.VM <- array_store_ref(vm, value, index, ref, expected)
        return result

def array_store_index(+vm: M.VM, +value: M.Slot, +frame: M.Frame, expected: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- array_store_index_popped(vm, value, popped, expected)
    return result

def array_store_value(frame: M.Frame, expected: U32) -> Result<&2, &2, String, F.Popped>:
  match expected:
    case 2: F.pop(frame, 0)
    case 3: F.pop(frame, 2)
    case 4: F.pop(frame, 4)
    case 5: F.pop(frame, 5)
    case _: F.pop(frame, 1)

def array_store_start(+vm: M.VM, popped: F.Popped, expected: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, value}: array_store_index(vm, value, frame, expected)

def array_store(+vm: M.VM, frame: M.Frame, +expected: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- array_store_value(frame, expected)
    result : M.VM <- array_store_start(vm, popped, expected)
    return result

def array_load_entry(+vm: M.VM, +index: M.Slot, +popped: F.Popped, expected: U32, entry: M.HeapEntry) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, ref}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, +values, chars}:
          do Result<&2, &2, String, M.VM>:
            checked_kind : Unit <- S.check(U32.is_eq(kind, expected), "ArrayTypeMismatch")
            checked_index : Unit <- S.check(U32.is_lt(V.slot_bits(index), M.length(M.Slot, values)), "java/lang/ArrayIndexOutOfBoundsException")
            slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, V.slot_bits(index)), "java/lang/ArrayIndexOutOfBoundsException")
            return S.commit(vm, S.frame_stack(S.advance(next), Con{slot, S.stack(next)}))

def array_load_result(+vm: M.VM, +index: M.Slot, popped: F.Popped, expected: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{entry}: array_load_entry(vm, index, popped, expected, entry)

def array_load_ref(+vm: M.VM, +index: M.Slot, +popped: F.Popped, expected: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, +ref}: array_load_result(vm, index, popped, expected, H.get(S.heap(vm), V.slot_bits(ref)))

def array_load_index(+vm: M.VM, +index: M.Slot, +frame: M.Frame, expected: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 0)
    result : M.VM <- array_load_ref(vm, index, popped, expected)
    return result

def array_load_start(+vm: M.VM, popped: F.Popped, expected: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, value}: array_load_index(vm, value, frame, expected)

def array_load(+vm: M.VM, frame: M.Frame, expected: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- array_load_start(vm, popped, expected)
    return result
def array_length(vm: M.VM, frame: M.Frame) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 3)
    result : M.VM <- array_length_popped(vm, popped)
    return result

def athrow_popped(vm: M.VM, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, +value}:
      Bool.pick(Result<&2, &2, String, M.VM>, U32.is_eq(V.slot_bits(value), 0), Fail{"java/lang/NullPointerException"}, Done{S.with_status(S.with_exception(S.commit(vm, frame), V.slot_bits(value)), 6)})

def athrow(vm: M.VM, frame: M.Frame) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 0)
    result : M.VM <- athrow_popped(vm, popped)
    return result

def string_units(values: +List<Char>) -> +List<U32>:
  match values:
    case Nil{}:
      Nil{}
    case Con{+head, tail}:
      Con{Char.to_u32(head), string_units(tail)}

def literal_class_found(+vm: M.VM, +frame: M.Frame, class: U32, target: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, M.VM>:
  match found:
    case Some{reference}:
      Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{3, reference}, S.stack(frame)}))}
    case None{}:
      new_object_alloc(frame, H.allocate(vm, H.class_mirror_entry(class, target)))
def literal_class(+vm: M.VM, +frame: M.Frame, +targetName: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    target_text : String <- S.require(String, M.nth(String, S.symbols(vm), targetName), "InvalidConstant")
    +target : U32 = H.named_class(S.classes(vm), S.symbols(vm), target_text)
    class : U32 = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/Class")
    found : Maybe<&2, U32> = H.class_mirror(S.heap(vm), target)
    result : M.VM <- literal_class_found(vm, frame, class, target, found)
    return result

def literal_string_found(+vm: M.VM, +frame: M.Frame, symbol: U32, class: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, M.VM>:
  match found:
    case Some{reference}:
      Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{3, reference}, S.stack(frame)}))}
    case None{}:
      do Result<&2, &2, String, M.VM>:
        text : String <- S.require(String, M.nth(String, S.symbols(vm), symbol), "InvalidConstant")
        chars : +List<U32> = string_units(String.to_list(text))
        result : M.VM <- new_object_alloc(frame, H.allocate(vm, H.string_entry(class, chars)))
        return result

def literal_string(+vm: M.VM, +frame: M.Frame, +symbol: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    text : String <- S.require(String, M.nth(String, S.symbols(vm), symbol), "InvalidConstant")
    class : U32 = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/String")
    chars : +List<U32> = string_units(String.to_list(text))
    found : Maybe<&2, U32> = H.string_intern(S.heap(vm), chars)
    result : M.VM <- literal_string_found(vm, frame, symbol, class, found)
    return result

def wide_read_entry(tag: U32, result: Result<&2, &2, String, M.HeapEntry>) -> Result<&2, &2, String, W.Words>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{+entry}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, values, chars}:
          do Result<&2, &2, String, W.Words>:
            valid_kind : Unit <- S.check(U32.is_eq(kind, 9), "InvalidWideValue")
            valid_tag : Unit <- S.check(U32.is_eq(element, tag), "InvalidWideValue")
            return W.Words{H.wide_high(entry), H.wide_low(entry)}

def wide_read_bits(+vm: M.VM, tag: U32, +bits: U32) -> Result<&2, &2, String, W.Words>:
  Bool.pick(Result<&2, &2, String, W.Words>, U32.is_eq(bits, 0), Done{W.Words{0, 0}}, wide_read_entry(tag, H.get(S.heap(vm), bits)))

def wide_read(+vm: M.VM, +tag: U32, slot: M.Slot) -> Result<&2, &2, String, W.Words>:
  match slot:
    case M.Slot{slot_tag, bits}:
      do Result<&2, &2, String, W.Words>:
        valid_tag : Unit <- S.check(U32.is_eq(slot_tag, tag), "InvalidWideValue")
        value : W.Words <- wide_read_bits(vm, tag, bits)
        return value

def wide_alloc(+vm: M.VM, tag: U32, value: W.Words) -> Result<&2, &2, String, H.Allocation>:
  match value:
    case W.Words{+high, +low}:
      zero : Bool = U32.is_eq(high, 0) && U32.is_eq(low, 0)
      Bool.pick(Result<&2, &2, String, H.Allocation>, zero, Done{H.Allocation{vm, 0}}, H.allocate(vm, H.wide_entry(tag, high, low)))

def wide_push_alloc(+vm: M.VM, +frame: M.Frame, tag: U32, max: U32, result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}:
      Fail{error}
    case Done{H.Allocation{updated, reference}}:
      do Result<&2, &2, String, M.VM>:
        +pushed : M.Frame <- F.push(S.advance(frame), M.Slot{tag, reference}, max)
        return S.commit(updated, S.frame_stack(pushed, S.stack(pushed)))

def wide_constant(+vm: M.VM, +frame: M.Frame, high: U32, low: U32, +tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  wide_push_alloc(vm, frame, tag, max, wide_alloc(vm, tag, W.Words{high, low}))

def wide_binary_value(op: U32, left: W.Words, right: W.Words) -> W.Words:
  match op:
    case 97: W.add(left, right)
    case 101: W.sub(left, right)
    case 105: W.mul(left, right)
    case 109: W.signed_divide(left, right)
    case 113: W.signed_remainder(left, right)
    case 103: W.double_sub(left, right)
    case 121: W.shl(left, W.long_to_int(right))
    case 125: W.sar(left, W.long_to_int(right))
    case 127: W.bit_and(left, right)
    case 129: W.bit_or(left, right)
    case 131: W.bit_xor(left, right)
    case _: W.Words{0, 0}

def wide_binary_finish(+vm: M.VM, +op: U32, +tag: U32, first_value: M.Slot, second: F.Popped, max: U32) -> Result<&2, &2, String, M.VM>:
  match second:
    case F.Popped{+second_frame, second_value}:
      do Result<&2, &2, String, M.VM>:
        +right : W.Words <- wide_read(vm, tag, first_value)
        left : W.Words <- wide_read(vm, tag, second_value)
        zero : Unit <- S.check(Bool.not(U32.is_eq(op, 109) && W.long_zero(right)) && Bool.not(U32.is_eq(op, 113) && W.long_zero(right)), "java/lang/ArithmeticException")
        result : Result<&2, &2, String, H.Allocation> = wide_alloc(vm, tag, wide_binary_value(op, left, right))
        output : M.VM <- wide_push_alloc(vm, second_frame, tag, max, result)
        return output

def wide_binary_second(frame: M.Frame, vm: M.VM, op: U32, +tag: U32, first: F.Popped, max: U32) -> Result<&2, &2, String, M.VM>:
  match first:
    case F.Popped{first_frame, first_value}:
      do Result<&2, &2, String, M.VM>:
        second : F.Popped <- F.pop(first_frame, tag)
        result : M.VM <- wide_binary_finish(vm, op, tag, first_value, second, max)
        return result

def wide_binary(+frame: M.Frame, vm: M.VM, op: U32, +tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    first : F.Popped <- F.pop(frame, tag)
    result : M.VM <- wide_binary_second(frame, vm, op, tag, first, max)
    return result

def wide_double_unary_finish(+vm: M.VM, popped: F.Popped, max: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      do Result<&2, &2, String, M.VM>:
        words : W.Words <- wide_read(vm, 5, value)
        result : Result<&2, &2, String, H.Allocation> = wide_alloc(vm, 5, W.double_neg(words))
        output : M.VM <- wide_push_alloc(vm, next, 5, max, result)
        return output

def wide_double_unary(+vm: M.VM, frame: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 5)
    result : M.VM <- wide_double_unary_finish(vm, popped, max)
    return result

def wide_unary_finish(+vm: M.VM, popped: F.Popped, +tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      do Result<&2, &2, String, M.VM>:
        words : W.Words <- wide_read(vm, tag, value)
        result : Result<&2, &2, String, H.Allocation> = wide_alloc(vm, tag, W.neg(words))
        output : M.VM <- wide_push_alloc(vm, next, tag, max, result)
        return output

def wide_unary(+vm: M.VM, frame: M.Frame, +tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, tag)
    result : M.VM <- wide_unary_finish(vm, popped, tag, max)
    return result

def wide_compare_finish(+vm: M.VM, first_value: M.Slot, second: F.Popped) -> Result<&2, &2, String, M.VM>:
  match second:
    case F.Popped{+second_frame, second_value}:
      do Result<&2, &2, String, M.VM>:
        right : W.Words <- wide_read(vm, 4, first_value)
        left : W.Words <- wide_read(vm, 4, second_value)
        return S.commit(vm, S.frame_stack(S.advance(second_frame), Con{M.Slot{1, W.long_cmp(left, right)}, S.stack(second_frame)}))

def wide_compare_start(vm: M.VM, first: F.Popped) -> Result<&2, &2, String, M.VM>:
  match first:
    case F.Popped{first_frame, first_value}:
      do Result<&2, &2, String, M.VM>:
        second : F.Popped <- F.pop(first_frame, 4)
        result : M.VM <- wide_compare_finish(vm, first_value, second)
        return result

def wide_compare(+frame: M.Frame, vm: M.VM) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    first : F.Popped <- F.pop(frame, 4)
    result : M.VM <- wide_compare_start(vm, first)
    return result
def convert_i2l_finish(+vm: M.VM, popped: F.Popped, max: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      wide_push_alloc(vm, next, 4, max, wide_alloc(vm, 4, W.int_to_long(V.slot_bits(value))))

def convert_i2l(+vm: M.VM, frame: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- convert_i2l_finish(vm, popped, max)
    return result

def convert_l2i_finish(+vm: M.VM, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      do Result<&2, &2, String, M.VM>:
        words : W.Words <- wide_read(vm, 4, value)
        return S.commit(vm, S.frame_stack(S.advance(next), Con{M.Slot{1, W.long_to_int(words)}, S.stack(next)}))

def convert_l2i(+vm: M.VM, frame: M.Frame) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 4)
    result : M.VM <- convert_l2i_finish(vm, popped)
    return result

def constant_push(+vm: M.VM, +frame: M.Frame, value: U32, tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +pushed : M.Frame <- F.push(frame, M.Slot{tag, value}, max)
    return S.commit(vm, S.frame_stack(S.advance(pushed), S.stack(pushed)))

def literal_push(+vm: M.VM, +frame: M.Frame, value: U32, tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  match tag:
    case 3: literal_string(vm, frame, value)
    case 4: literal_class(vm, frame, value)
    case _: constant_push(vm, frame, value, tag, max)

def float_operation(op: U32, +a: F32, +b: F32) -> F32:
  match op:
    case 98: F32.add(a, b)
    case 102: F32.sub(a, b)
    case 106: F32.mul(a, b)
    case 110: F32.div(a, b)
    case _: F32.mod(a, b)

def float_binary_value(op: U32, left: U32, right: U32) -> U32:
  +a = V.from_bits(left)
  +b = V.from_bits(right)
  F32.bits(float_operation(op, a, b))

def float_binary_finish(vm: M.VM, op: U32, first_value: M.Slot, second: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{+second_frame, second_value} = second
  Done{S.commit(vm, S.frame_stack(S.advance(second_frame), Con{M.Slot{2, float_binary_value(op, V.slot_bits(second_value), V.slot_bits(first_value))}, S.stack(second_frame)}))}

def float_binary_second(frame: M.Frame, vm: M.VM, op: U32, first: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{first_frame, first_value} = first
  do Result<&2, &2, String, M.VM>:
    second : F.Popped <- F.pop(first_frame, 2)
    result : M.VM <- float_binary_finish(vm, op, first_value, second)
    return result

def float_binary(+frame: M.Frame, vm: M.VM, op: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    first : F.Popped <- F.pop(frame, 2)
    result : M.VM <- float_binary_second(frame, vm, op, first)
    return result

def float_negate(vm: M.VM, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      Done{S.commit(vm, S.frame_stack(S.advance(next), Con{M.Slot{2, F32.bits(F32.neg(V.from_bits(V.slot_bits(value))))}, S.stack(next)}))}

def float_nan(+a: F32, +b: F32) -> Bool:
  Bool.or(F32.is_ne(a, a), F32.is_ne(b, b))

def float_compare_value_case(op: U32, +a: F32, +b: F32, nan: Bool) -> U32:
  match nan:
    case True{}:
      Bool.pick(U32, U32.is_eq(op, 149), 4294967295, 1)
    case False{}:
      Bool.pick(U32, F32.is_lt(a, b), 4294967295, Bool.pick(U32, F32.is_gt(a, b), 1, 0))

def float_compare_value(op: U32, left: U32, right: U32) -> U32:
  +a = V.from_bits(left)
  +b = V.from_bits(right)
  float_compare_value_case(op, a, b, float_nan(a, b))

def float_compare_finish(vm: M.VM, op: U32, first_value: M.Slot, second: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{+second_frame, second_value} = second
  Done{S.commit(vm, S.frame_stack(S.advance(second_frame), Con{M.Slot{1, float_compare_value(op, V.slot_bits(second_value), V.slot_bits(first_value))}, S.stack(second_frame)}))}

def float_compare_second(frame: M.Frame, vm: M.VM, op: U32, first: F.Popped) -> Result<&2, &2, String, M.VM>:
  F.Popped{first_frame, first_value} = first
  do Result<&2, &2, String, M.VM>:
    second : F.Popped <- F.pop(first_frame, 2)
    result : M.VM <- float_compare_finish(vm, op, first_value, second)
    return result

def float_compare(+frame: M.Frame, vm: M.VM, op: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    first : F.Popped <- F.pop(frame, 2)
    result : M.VM <- float_compare_second(frame, vm, op, first)
    return result

def convert_i2f(vm: M.VM, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      Done{S.commit(vm, S.frame_stack(S.advance(next), Con{M.Slot{2, V.int_float(V.slot_bits(value))}, S.stack(next)}))}

def convert_f2i(vm: M.VM, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      Done{S.commit(vm, S.frame_stack(S.advance(next), Con{M.Slot{1, V.float_int(V.slot_bits(value))}, S.stack(next)}))}

def narrow_value(op: U32, value: U32) -> U32:
  match op:
    case 145: V.narrow_byte(value)
    case 146: U32.and(value, 65535)
    case _: V.narrow_short(value)

def narrow_finish(vm: M.VM, popped: F.Popped, op: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}: Done{S.commit(vm, S.frame_stack(S.advance(next), Con{M.Slot{1, narrow_value(op, V.slot_bits(value))}, S.stack(next)}))}

def narrow(vm: M.VM, frame: M.Frame, op: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- narrow_finish(vm, popped, op)
    return result

def load_local(+vm: M.VM, +frame: M.Frame, index: U32, tag: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    slot : M.Slot <- F.local(frame, index, tag)
    return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))

def store_local(+vm: M.VM, +frame: M.Frame, index: U32, tag: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, tag)
    result : M.VM <- store_popped(vm, popped, index)
    return result

def step(+vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod, instruction: M.Instruction) -> Result<&2, &2, String, M.VM>:


  M.Instruction{op, +a, b, c, offset} = instruction
  match op:
    case 0: Done{S.commit(vm, S.advance(frame))}
    case 79: array_store(vm, frame, 1)
    case 80: array_store(vm, frame, 4)
    case 82: array_store(vm, frame, 5)
    case 81: array_store(vm, frame, 3)
    case 83: array_store(vm, frame, 2)
    case 84: array_store(vm, frame, 1)
    case 85: array_store(vm, frame, 1)
    case 1: constant_push(vm, frame, 0, 3, method_max_stack(method))
    case 46: array_load(vm, frame, 1)
    case 47: array_load(vm, frame, 4)
    case 49: array_load(vm, frame, 5)
    case 48: array_load(vm, frame, 1)
    case 50: array_load(vm, frame, 2)
    case 51: array_load(vm, frame, 1)
    case 52: array_load(vm, frame, 1)
    case 2: constant_push(vm, frame, 4294967295, 1, method_max_stack(method))
    case 3: constant_push(vm, frame, 0, 1, method_max_stack(method))
    case 4: constant_push(vm, frame, 1, 1, method_max_stack(method))
    case 5: constant_push(vm, frame, 2, 1, method_max_stack(method))
    case 6: constant_push(vm, frame, 3, 1, method_max_stack(method))
    case 7: constant_push(vm, frame, 4, 1, method_max_stack(method))
    case 8: constant_push(vm, frame, 5, 1, method_max_stack(method))
    case 9: wide_constant(vm, frame, 0, 0, 4, method_max_stack(method))
    case 10: wide_constant(vm, frame, 0, 1, 4, method_max_stack(method))
    case 14: wide_constant(vm, frame, 0, 0, 5, method_max_stack(method))
    case 15: wide_constant(vm, frame, 1072693248, 0, 5, method_max_stack(method))
    case 25:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, a, 3)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 42:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 0, 3)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 43:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 1, 3)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 44:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 2, 3)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 45:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 3, 3)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 16: constant_push(vm, frame, a, 1, method_max_stack(method))
    case 17: constant_push(vm, frame, a, 1, method_max_stack(method))
    case 11: constant_push(vm, frame, 0, 2, method_max_stack(method))
    case 12: constant_push(vm, frame, 1065353216, 2, method_max_stack(method))
    case 13: constant_push(vm, frame, 1073741824, 2, method_max_stack(method))
    case 18: literal_push(vm, frame, a, b, method_max_stack(method))
    case 20: wide_constant(vm, frame, a, b, c, method_max_stack(method))
    case 19: literal_push(vm, frame, a, b, method_max_stack(method))

    case 21:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, a, 1)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 22: load_local(vm, frame, a, 4)
    case 24: load_local(vm, frame, a, 5)
    case 30: load_local(vm, frame, 0, 4)
    case 31: load_local(vm, frame, 1, 4)
    case 32: load_local(vm, frame, 2, 4)
    case 33: load_local(vm, frame, 3, 4)
    case 38: load_local(vm, frame, 0, 5)
    case 39: load_local(vm, frame, 1, 5)
    case 40: load_local(vm, frame, 2, 5)
    case 41: load_local(vm, frame, 3, 5)
    case 26:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 0, 1)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 27:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 1, 1)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 28:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 2, 1)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 29:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 3, 1)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 23:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, a, 2)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 34:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 0, 2)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 35:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 1, 2)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 36:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 2, 2)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 37:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, 3, 2)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
    case 54:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 1)
        result : M.VM <- store_popped(vm, popped, a)
        return result
    case 55: store_local(vm, frame, a, 4)
    case 57: store_local(vm, frame, a, 5)
    case 63: store_local(vm, frame, 0, 4)
    case 64: store_local(vm, frame, 1, 4)
    case 65: store_local(vm, frame, 2, 4)
    case 66: store_local(vm, frame, 3, 4)
    case 71: store_local(vm, frame, 0, 5)
    case 72: store_local(vm, frame, 1, 5)
    case 73: store_local(vm, frame, 2, 5)
    case 74: store_local(vm, frame, 3, 5)
    case 132: iinc(vm, frame, a, b)
    case 59:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 1)
        result : M.VM <- store_popped(vm, popped, 0)
        return result
    case 60:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 1)
        result : M.VM <- store_popped(vm, popped, 1)
        return result
    case 61:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 1)
        result : M.VM <- store_popped(vm, popped, 2)
        return result
    case 62:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 1)
        result : M.VM <- store_popped(vm, popped, 3)
        return result
    case 56:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
        result : M.VM <- store_popped(vm, popped, a)
        return result
    case 67:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
        result : M.VM <- store_popped(vm, popped, 0)
        return result
    case 68:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
        result : M.VM <- store_popped(vm, popped, 1)
        return result
    case 69:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
        result : M.VM <- store_popped(vm, popped, 2)
        return result
    case 70:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
        result : M.VM <- store_popped(vm, popped, 3)
        return result
    case 58:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 3)
        result : M.VM <- store_popped(vm, popped, a)
        return result
    case 75:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 3)
        result : M.VM <- store_popped(vm, popped, 0)
        return result
    case 76:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 3)
        result : M.VM <- store_popped(vm, popped, 1)
        return result
    case 77:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 3)
        result : M.VM <- store_popped(vm, popped, 2)
        return result
    case 78:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 3)
        result : M.VM <- store_popped(vm, popped, 3)
        return result
    case 103: wide_binary(frame, vm, 103, 5, method_max_stack(method))
    case 119: wide_double_unary(vm, frame, method_max_stack(method))
    case 101: wide_binary(frame, vm, 101, 4, method_max_stack(method))
    case 105: wide_binary(frame, vm, 105, 4, method_max_stack(method))
    case 109: wide_binary(frame, vm, 109, 4, method_max_stack(method))
    case 113: wide_binary(frame, vm, 113, 4, method_max_stack(method))
    case 121: wide_binary(frame, vm, 121, 4, method_max_stack(method))
    case 123: wide_binary(frame, vm, 123, 4, method_max_stack(method))
    case 125: wide_binary(frame, vm, 125, 4, method_max_stack(method))
    case 127: wide_binary(frame, vm, 127, 4, method_max_stack(method))
    case 129: wide_binary(frame, vm, 129, 4, method_max_stack(method))
    case 131: wide_binary(frame, vm, 131, 4, method_max_stack(method))
    case 117: wide_unary(vm, frame, 4, method_max_stack(method))

    case 120: binary_int(frame, vm, 120)
    case 98: float_binary(frame, vm, 98)
    case 102: float_binary(frame, vm, 102)
    case 106: float_binary(frame, vm, 106)
    case 110: float_binary(frame, vm, 110)
    case 114: float_binary(frame, vm, 114)
    case 122: binary_int(frame, vm, 122)
    case 124: binary_int(frame, vm, 124)
    case 126: binary_int(frame, vm, 126)
    case 128: binary_int(frame, vm, 128)
    case 130: binary_int(frame, vm, 130)
    case 133: convert_i2l(vm, frame, method_max_stack(method))
    case 136: convert_l2i(vm, frame)
    case 134:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 1)
        result : M.VM <- convert_i2f(vm, popped)
        return result
    case 139:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
        result : M.VM <- convert_f2i(vm, popped)
        return result
    case 145: narrow(vm, frame, 145)
    case 146: narrow(vm, frame, 146)
    case 147: narrow(vm, frame, 147)
    case 96: binary_int(frame, vm, 96)
    case 100: binary_int(frame, vm, 100)
    case 104: binary_int(frame, vm, 104)
    case 108: binary_int(frame, vm, 108)
    case 112: binary_int(frame, vm, 112)
    case 116:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 1)
        result : M.VM <- negate_popped(vm, popped)
        return result
    case 118:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
        result : M.VM <- float_negate(vm, popped)
        return result
    case 89:
      do Result<&2, &2, String, M.VM>:
        updated : M.Frame <- F.stack_op(frame, op, method_max_stack(method))
        return S.commit(vm, updated)
    case 87:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 0)
        result : M.VM <- drop_popped(vm, popped)
        return result
    case 155: branch_signed(vm, frame, a, 155)
    case 190: array_length(vm, frame)
    case 156: branch_signed(vm, frame, a, 156)
    case 157: branch_signed(vm, frame, a, 157)
    case 158: branch_signed(vm, frame, a, 158)
    case 165: ref_compare(frame, vm, a, 165)
    case 166: ref_compare(frame, vm, a, 166)
    case 95:
      do Result<&2, &2, String, M.VM>:
        updated : M.Frame <- F.stack_op(frame, op, method_max_stack(method))
        return S.commit(vm, updated)
    case 153: branch_zero(vm, frame, a, True{})
    case 154: branch_zero(vm, frame, a, False{})
    case 167: branch_target(vm, frame, a)
    case 198: branch_ref_zero(vm, frame, a, True{})
    case 199: branch_ref_zero(vm, frame, a, False{})
    case 172:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 1)
        result : M.VM <- return_popped(vm, popped)
        return result
    case 159: branch_compare(frame, vm, a, 159)
    case 160: branch_compare(frame, vm, a, 160)
    case 161: branch_compare(frame, vm, a, 161)
    case 162: branch_compare(frame, vm, a, 162)
    case 163: branch_compare(frame, vm, a, 163)
    case 164: branch_compare(frame, vm, a, 164)
    case 149: float_compare(frame, vm, 149)
    case 150: float_compare(frame, vm, 150)
    case 148: wide_compare(frame, vm)
    case 173:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 4)
        result : M.VM <- return_popped(vm, popped)
        return result
    case 174:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
        result : M.VM <- return_popped(vm, popped)
        return result
    case 175:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 5)
        result : M.VM <- return_popped(vm, popped)
        return result
    case 176:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 3)
        result : M.VM <- return_popped(vm, popped)
        return result
    case 177: Done{finish_void(vm)}
    case 178: getstatic(vm, frame, a, b, c)
    case 179: putstatic(vm, frame, a, b, c)
    case 180: getfield(vm, frame, a, b, c)
    case 181: putfield(vm, frame, a, b, c)
    case 191: athrow(vm, frame)
    case 192: ref_test(vm, frame, a, True{})
    case 193: ref_test(vm, frame, a, False{})
    case 188: array_count(vm, frame, Sy.find(S.symbols(vm), B.atype_name(a)), a, 1)
    case 189: array_count(vm, frame, a, a, 2)
    case 187: new_object(vm, frame, a)
    case 182: invoke_virtual(vm, frame, a, b, c, method_max_stack(method))
    case 183: invoke_special(vm, frame, a, b, c, method_max_stack(method))
    case 184: invoke_static(vm, frame, a, b, c, method_max_stack(method))
    case 185: invoke_virtual(vm, frame, a, b, c, method_max_stack(method))
    case _: Fail{"UnsupportedOpcode: " ++ U32.show(op)}
def method_handlers(value: M.LoadedMethod) -> +List<M.Handler>:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}: handlers

def java_fault(error: String) -> Bool:
  String.starts_with(error, "java/")

def thrown_class_entry(result: Result<&2, &2, String, M.HeapEntry>) -> U32:
  match result:
    case Fail{error}: 0
    case Done{entry}: H.entry_class(entry)

def thrown_class_of(+vm: M.VM) -> U32:
  thrown_class_entry(H.get(S.heap(vm), S.exception(vm)))

def catch_matches_id(+vm: M.VM, +thrown: U32, found: Maybe<&2, U32>) -> Bool:
  match found:
    case None{}: False{}
    case Some{id}: H.assignable(S.classes(vm), S.symbols(vm), thrown, id)

def catch_matches(+vm: M.VM, +thrown: U32, catch: U32) -> Bool:
  match catch:
    case 0: True{}
    case _:
      catch_matches_id(vm, thrown, class_id_by_name(S.classes(vm), catch))

def exception_handler(+vm: M.VM, +pc: U32, +thrown: U32, +handlers: +List<M.Handler>) -> Maybe<&2, U32>:
  match handlers:
    case Nil{}: None{}
    case Con{M.Handler{start, end, target, catch}, rest}:
      Bool.pick(Maybe<&2, U32>, U32.is_ge(pc, start) && U32.is_lt(pc, end) && catch_matches(vm, thrown, catch), Some{target}, exception_handler(vm, pc, thrown, rest))

def frame_exception_handler_found(+vm: M.VM, +frame: M.Frame, pc: U32, thrown: U32, found: Maybe<&2, M.LoadedMethod>) -> Maybe<&2, U32>:
  match found:
    case None{}: None{}
    case Some{method}: exception_handler(vm, pc, thrown, method_handlers(method))

def frame_exception_handler(+vm: M.VM, +frame: M.Frame, pc: U32) -> Maybe<&2, U32>:
  frame_exception_handler_found(vm, frame, pc, thrown_class_of(vm), M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)))

def enter_handler(+vm: M.VM, frame: M.Frame, target: U32, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  +resumed = S.tick(S.with_status(S.commit(vm, S.frame_stack(S.frame_pc(frame, target), Con{M.Slot{3, S.exception(vm)}, Nil{}})), 0))
  +cleared = S.with_exception(resumed, 0)
  continue(S.status(cleared), fuel, cleared)
def reflective_exception_fill(+entry: M.HeapEntry, original: U32) -> M.HeapEntry:
  match entry:
    case M.HeapEntry{kind_class, kind, element, +fields, values, chars}:
      M.HeapEntry{kind_class, kind, element, H.binding_set(fields, 1, M.Slot{3, original}), values, chars}

def reflective_exception_entry(class: U32, original: U32) -> M.HeapEntry:
  reflective_exception_fill(H.throwable_entry(class), original)

def reflective_exception_wrap_alloc(+vm: M.VM, result: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{H.Allocation{vm, reference}}: S.with_exception(vm, reference)

def reflective_exception_wrap(+vm: M.VM, effect: M.Effect, caller: M.Frame) -> M.VM:
  match effect:
    case M.ReflectCall{}:
      Bool.pick(M.VM, U32.is_eq(S.initializing(caller), 4294967294),
        reflective_exception_wrap_alloc(vm, H.allocate(vm, reflective_exception_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/reflect/InvocationTargetException"), S.exception(vm)))),
        vm)
    case M.ReflectConstructor{reference}:
      Bool.pick(M.VM, U32.is_le(S.initializing(caller), 4294967292),
        reflective_exception_wrap_alloc(vm, H.allocate(vm, reflective_exception_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/reflect/InvocationTargetException"), S.exception(vm)))),
        vm)
    case _:
      vm


def fail_initializer_state(+vm: M.VM, owner: U32) -> M.VM:
  match owner:
    case 4294967295: vm
    case value: S.set_class_state(vm, value, 3)

def fail_initializer(+vm: M.VM, frame: M.Frame) -> M.VM:
  fail_initializer_state(vm, S.initializing(frame))
def uncaught(+vm: M.VM, error: String) -> M.VM:
  S.fail(vm, error)

def handler_target(found: Maybe<&2, U32>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{target}: target

@unsafe def exception_unwind_miss(+error: String, +vm: M.VM, +caller: M.Frame, callers: +List<M.Frame>, +fuel: Nat, +k: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match callers:
    case Nil{}: uncaught(fail_initializer(vm, caller), error)
    case Con{+next_caller, +next_callers}:
      +next = S.with_frames(fail_initializer(vm, caller), Con{next_caller, next_callers})
      +wrapped = reflective_exception_wrap(next, S.host_effect(next), next_caller)
      +target = handler_target(frame_exception_handler(wrapped, next_caller, S.invoke_pc(caller)))
      Bool.pick(M.VM, U32.is_eq(target, 4294967295), exception_unwind_miss(error, wrapped, next_caller, next_callers, fuel, k), enter_handler(wrapped, next_caller, target, fuel, k))


def exception_unwind_choice(miss: Bool, error: String, +vm: M.VM, +frame: M.Frame, frames: +List<M.Frame>, fuel: Nat, k: U32 -> Nat -> M.VM -> M.VM, target: U32) -> M.VM:
  match miss:
    case True{}: exception_unwind_miss(error, vm, frame, frames, fuel, k)
    case False{}: enter_handler(vm, frame, target, fuel, k)

def exception_unwind(+error: String, +vm: M.VM, +frames: +List<M.Frame>, +fuel: Nat, k: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match frames:
    case Nil{}: uncaught(vm, error)
    case Con{+current, rest}:
      match rest:
        case Nil{}: uncaught(fail_initializer(vm, current), error)
        case Con{+caller, callers}:
          +next = S.with_frames(fail_initializer(vm, current), Con{caller, callers})
          +wrapped = reflective_exception_wrap(next, S.host_effect(next), caller)
          +target = handler_target(frame_exception_handler(wrapped, caller, S.invoke_pc(current)))
          exception_unwind_choice(U32.is_eq(target, 4294967295), error, wrapped, caller, callers, fuel, k, target)


def exception_resume_found(error: String, +vm: M.VM, +frame: M.Frame, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM, found: Maybe<&2, U32>) -> M.VM:
  match found:
    case None{}: exception_unwind(error, vm, S.frames(vm), fuel, continue)
    case Some{target}: enter_handler(vm, frame, target, fuel, continue)

def proxy_exception_entry_found(original: U32, entry: M.HeapEntry) -> M.HeapEntry:
  M.HeapEntry{kind_class, kind, element, fields, values, chars} = entry
  M.HeapEntry{kind_class, kind, element, H.binding_set(fields, 1, M.Slot{3, original}), values, chars}

def proxy_exception_entry(class: U32, original: U32) -> M.HeapEntry:
  proxy_exception_entry_found(original, H.throwable_entry(class))

def proxy_wrap_exception_alloc(+vm: M.VM, result: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{H.Allocation{vm, reference}}: S.with_exception(vm, reference)

def proxy_declared_exception(fuel: Nat, +thrown: U32, +exceptions: +List<U32>, +classes: +List<M.LoadedClass>, +symbols: +List<String>) -> Bool:
  match fuel exceptions:
    case 0n _: False{}
    case 1n+remaining Nil{}: False{}
    case 1n+remaining Con{declared, rest}:
      H.assignable(classes, symbols, thrown, declared) || proxy_declared_exception(remaining, thrown, rest, classes, symbols)

def proxy_wrap_exception_effect(effect: M.Effect, +vm: M.VM, +error: String) -> M.VM:
  match effect:
    case M.ProxyCall{descriptor, +exceptions}:
      +thrown = thrown_class_of(vm)
      +runtime = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/RuntimeException")
      +error_class = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/Error")
      unchecked : Bool = H.assignable(S.classes(vm), S.symbols(vm), thrown, runtime) || H.assignable(S.classes(vm), S.symbols(vm), thrown, error_class)
      declared : Bool = proxy_declared_exception(256n, thrown, exceptions, S.classes(vm), S.symbols(vm))
      +original = S.exception(vm)
      +wrapper_class = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/reflect/UndeclaredThrowableException")
      wrapper_entry : M.HeapEntry = proxy_exception_entry(wrapper_class, original)
      Bool.pick(M.VM, unchecked || declared, vm, proxy_wrap_exception_alloc(vm, H.allocate(vm, wrapper_entry)))
    case _: vm

def proxy_wrap_exception(+vm: M.VM, +error: String) -> M.VM:
  proxy_wrap_exception_effect(S.host_effect(vm), vm, error)

def exception_resume_java(+error: String, +vm: M.VM, +frame: M.Frame, method: M.LoadedMethod, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  +ready = ensure_throw(vm, error)
  +wrapped = proxy_wrap_exception(ready, error)
  exception_resume_found(error, wrapped, frame, fuel, continue, exception_handler(wrapped, S.pc(frame), thrown_class_of(wrapped), method_handlers(method)))

def exception_resume_kind(java: Bool, error: String, +vm: M.VM, +frame: M.Frame, method: M.LoadedMethod, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match java:
    case True{}: exception_resume_java(error, vm, frame, method, fuel, continue)
    case False{}: S.fail(vm, error)

def exception_resume(+error: String, +vm: M.VM, +frame: M.Frame, method: M.LoadedMethod, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  exception_resume_kind(java_fault(error), error, vm, frame, method, fuel, continue)

def step_continue(result: Result<&2, &2, String, M.VM>, fuel: Nat, +vm: M.VM, +frame: M.Frame, method: M.LoadedMethod, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match result:
    case Done{+next}:
      +next = S.tick(next)
      continue(S.status(next), fuel, next)
    case Fail{error}: exception_resume(error, vm, frame, method, fuel, continue)

def run_instruction(found: Maybe<&2, M.Instruction>, fuel: Nat, +vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match found:
    case None{}: exception_resume("InvalidState: program counter", vm, frame, method, fuel, continue)
    case Some{instruction}: step_continue(step(vm, frame, method, instruction), fuel, vm, frame, method, continue)

def run_method(found: Maybe<&2, M.LoadedMethod>, fuel: Nat, +vm: M.VM, +frame: M.Frame, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match found:
    case None{}: S.fail(vm, "InvalidState: method id")
    case Some{+method}: run_instruction(method_instruction(method, S.pc(frame)), fuel, vm, frame, method, continue)

def run_frames(fuel: Nat, +vm: M.VM, frames: +List<M.Frame>, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match frames:
    case Nil{}: S.with_status(vm, 1)
    case Con{+frame, rest}: run_method(M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)), fuel, vm, frame, continue)

@unsafe def loop_with(mode: U32, status: U32, +fuel: Nat, +vm: M.VM, +frames: +List<M.Frame>, found: Maybe<&2, M.LoadedMethod>, +frame: M.Frame) -> M.VM:
  match mode:
    case 0:
      match status:
        case 1: vm
        case 4: vm
        case 3: vm
        case 5: vm
        case 6:
          match frames:
            case Nil{}: uncaught(vm, "java/lang/Throwable")
            case Con{+cur, rest}:
              loop_with(1, status, fuel, vm, Con{cur, rest}, M.nth(M.LoadedMethod, S.methods(vm), S.method_id(cur)), cur)
        case _:
          match fuel:
            case 0n: S.with_status(vm, 3)
            case 1n+p: run_frames(p, vm, frames, nextStatus => nextFuel => +nextVm => loop_with(0, nextStatus, nextFuel, nextVm, S.frames(nextVm), None{}, frame))
    case _:
      match found:
        case None{}: uncaught(vm, "java/lang/Throwable")
        case Some{method}:
          exception_resume_java("java/lang/Throwable", vm, frame, method, fuel, nextStatus => nextFuel => +nextVm => loop_with(0, nextStatus, nextFuel, nextVm, S.frames(nextVm), None{}, frame))

@unsafe def loop(fuel: Nat, +vm: M.VM) -> M.VM:
  loop_with(0, S.status(vm), fuel, vm, S.frames(vm), None{}, M.Frame{0, 0, 0, Nil{}, Nil{}, 4294967295})

def run(vm: M.VM, fuel: Nat) -> M.VM:
  loop(fuel, vm)

def resume_clear(+vm: M.VM) -> M.VM:
  S.with_effect(S.with_status(vm, 0), M.Idle{})

def resume_void_frames(+vm: M.VM, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: resume_clear(vm)
    case Con{frame, rest}: resume_clear(S.commit(vm, S.advance(frame)))

def resume_void(+vm: M.VM) -> M.VM:
  resume_void_frames(vm, S.frames(vm))

def resume_push_done(+vm: M.VM, result: Result<&2, &2, String, M.Frame>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{pushed}: resume_clear(S.commit(vm, pushed))

def resume_push_frames(+vm: M.VM, value: M.Slot, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: resume_clear(vm)
    case Con{frame, rest}: resume_push_done(vm, F.push(S.advance(frame), value, 256))

def resume_push(+vm: M.VM, value: M.Slot) -> M.VM:
  resume_push_frames(vm, value, S.frames(vm))

def resume_int(+vm: M.VM, bits: U32) -> M.VM:
  resume_push(vm, M.Slot{1, bits})

def resume_ref(+vm: M.VM, reference: U32) -> M.VM:
  resume_push(vm, M.Slot{3, reference})


def put_handle_entry(+vm: M.VM, +reference: U32, +handle: U32, extra: U32, entry: M.HeapEntry) -> M.VM:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  H.put(vm, reference, M.HeapEntry{class, kind, element, [M.Binding{0, M.Slot{1, 0}}, M.Binding{1, M.Slot{1, handle}}, M.Binding{2, M.Slot{1, extra}}], values, chars})

def put_handle_found(+vm: M.VM, +reference: U32, +handle: U32, extra: U32, result: Result<&2, &2, String, M.HeapEntry>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{entry}: put_handle_entry(vm, reference, handle, extra, entry)

def put_handle(+vm: M.VM, +reference: U32, +handle: U32, extra: U32) -> M.VM:
  put_handle_found(vm, reference, handle, extra, H.get(S.heap(vm), reference))

def resume_open_to(+vm: M.VM, +handle: U32, +receiver: U32) -> M.VM:
  resume_void(put_handle(vm, receiver, handle, 0))

def resume_bind_to(+vm: M.VM, +handle: U32, +port: U32, +receiver: U32) -> M.VM:
  resume_void(put_handle(vm, receiver, handle, port))

def resume_accept_alloc(+vm: M.VM, +handle: U32, result: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{allocation}:
      match allocation:
        case H.Allocation{updated, reference}: resume_ref(updated, reference)

def resume_accept_to(+vm: M.VM, +handle: U32) -> M.VM:
  resume_accept_alloc(vm, handle, H.allocate(vm, M.HeapEntry{H.named_class(S.classes(vm), S.symbols(vm), "java/net/Socket"), 0, 0, [M.Binding{0, M.Slot{1, 0}}, M.Binding{1, M.Slot{1, handle}}, M.Binding{2, M.Slot{1, 0}}], Nil{}, Nil{}}))

def resume_read_bytes(values: +List<U32>, +vm: M.VM) -> M.VM:
  match values:
    case Nil{}: resume_int(vm, 4294967295)
    case Con{b, rest}: resume_int(vm, U32.and(b, 255))

def resume_ok_effect(+vm: M.VM, +handle: U32, extra: U32, bytes: +List<U32>, effect: M.Effect) -> M.VM:
  match effect:
    case M.Idle{}: resume_clear(vm)
    case M.ReflectCall{}: resume_clear(vm)
    case M.ReflectConstructor{reference}: resume_clear(vm)
    case M.ProxyCall{descriptor, exceptions}: resume_clear(vm)
    case M.ClassForName{target}: resume_clear(vm)
    case M.OpenFile{path, mode, receiver}: resume_open_to(vm, handle, receiver)
    case M.StatPath{path, op}: resume_int(vm, extra)
    case M.ReadBytes{old, count, timeout}: resume_read_bytes(bytes, vm)
    case M.WriteBytes{old, data}: resume_void(vm)
    case M.CloseHandle{old}: resume_void(vm)
    case M.ConnectTcp{host, port, timeout, receiver}: resume_open_to(vm, handle, receiver)
    case M.BindTcp{port, receiver}: resume_bind_to(vm, handle, extra, receiver)
    case M.AcceptTcp{old, timeout, receiver}: resume_accept_to(vm, handle)

def resume_ok(+vm: M.VM, +handle: U32, extra: U32, bytes: +List<U32>) -> M.VM:
  resume_ok_effect(vm, handle, extra, bytes, S.host_effect(vm))

def resume_fail(+vm: M.VM, name: String) -> M.VM:
  S.with_effect(S.with_status(ensure_throw(vm, name), 6), M.Idle{})

def continue_run(vm: M.VM, fuel: Nat) -> M.VM:
  loop(fuel, vm)

