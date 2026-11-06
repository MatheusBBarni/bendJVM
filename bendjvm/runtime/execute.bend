import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../runtime/frame.bend as F
import ../runtime/wide.bend as W
import ../runtime/binary64.bend as B64
import ../runtime/value.bend as V
import ../heap/heap.bend as H
import ../loader/bootstrap.bend as B
import ../loader/symbols.bend as Sy
import ../java/intrinsic.bend as I
import ../java/outcome.bend as O
import ../java/library.bend as L
import ../classfile/constant_pool.bend as CP
import ../java/invoke.bend as MH
import ../java/files.bend as Fs
import ../classfile/descriptor.bend as D
import ./threads.bend as Th
import ./trace.bend as Tr
import ../java/hostio.bend as Hio
import ../java/natives.bend as Nb

@unsafe def class_id_hit(hit: Bool, +value: M.LoadedClass, rest: +List<M.LoadedClass>, +name: U32) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{M.loaded_class_id(value)}
    case False{}: class_id_by_name(rest, name)

# The match in class_id_hit stops at the first hit (Bool.pick would evaluate the
# recursive branch eagerly and scan the whole table).
@unsafe def class_id_by_name(classes: +List<M.LoadedClass>, +name: U32) -> Maybe<&2, U32>:
  match classes:
    case Nil{}: None{}
    case Con{+value, rest}: class_id_hit(U32.is_eq(M.loaded_class_name(value), name), value, rest, name)

@unsafe def own_method_hit(hit: Bool, +value: M.LoadedMethod, rest: +List<M.LoadedMethod>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match hit:
    case True{}: Some{value}
    case False{}: own_method(rest, owner, name, descriptor)

@unsafe def own_method(methods: +List<M.LoadedMethod>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+value, rest}: own_method_hit(U32.is_eq(M.loaded_method_owner(value), owner) && U32.is_eq(M.loaded_method_name(value), name) && U32.is_eq(M.loaded_method_descriptor(value), descriptor), value, rest, owner, name, descriptor)

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

@unsafe def ancestor_ids_visit(seen: Bool, fuel: Nat, +classes: +List<M.LoadedClass>, +id: U32, +rest: +List<U32>, +visited: +List<U32>) -> +List<U32>:
  match seen:
    case True{}: ancestor_ids(fuel, classes, rest, visited)
    case False{}: ancestor_ids(fuel, classes, H.field_lookup_supers(M.nth(M.LoadedClass, classes, id), rest), Con{id, visited})

# Every superclass and superinterface reachable from the queue, each once.
@unsafe def ancestor_ids(fuel: Nat, +classes: +List<M.LoadedClass>, +queue: +List<U32>, +visited: +List<U32>) -> +List<U32>:
  match fuel queue:
    case 0n _: visited
    case 1n+p Nil{}: visited
    case 1n+p Con{+id, rest}: ancestor_ids_visit(H.contains(visited, id), p, classes, id, rest, visited)

def interface_candidate(+method: M.LoadedMethod, +ancestors: +List<U32>, +name: U32, +descriptor: U32) -> Bool:
  U32.is_eq(M.loaded_method_name(method), name) && U32.is_eq(M.loaded_method_descriptor(method), descriptor) &&
    U32.is_eq(U32.and(M.loaded_method_flags(method), 10), 0) && H.contains(ancestors, M.loaded_method_owner(method))

def interface_candidates(+methods: +List<M.LoadedMethod>, +ancestors: +List<U32>, +name: U32, +descriptor: U32) -> +List<M.LoadedMethod>:
  match methods:
    case Nil{}: Nil{}
    case Con{+method, rest}:
      +tail = interface_candidates(rest, ancestors, name, descriptor)
      Bool.pick(+List<M.LoadedMethod>, interface_candidate(method, ancestors, name, descriptor), Con{method, tail}, tail)

# A candidate is maximally specific when no other candidate's owner is a
# subinterface of its owner (JVMS 5.4.3.3).
def dominated(+classes: +List<M.LoadedClass>, +owner: U32, others: +List<M.LoadedMethod>) -> Bool:
  match others:
    case Nil{}: False{}
    case Con{+other, rest}:
      +theirs = M.loaded_method_owner(other)
      (U32.is_ne(theirs, owner) && H.hierarchy(classes, theirs, owner)) || dominated(classes, owner, rest)

def maximal_methods(+classes: +List<M.LoadedClass>, values: +List<M.LoadedMethod>, +all: +List<M.LoadedMethod>) -> +List<M.LoadedMethod>:
  match values:
    case Nil{}: Nil{}
    case Con{+method, rest}:
      +tail = maximal_methods(classes, rest, all)
      Bool.pick(+List<M.LoadedMethod>, dominated(classes, M.loaded_method_owner(method), all), tail, Con{method, tail})

def first_concrete(values: +List<M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match values:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(U32.and(M.loaded_method_flags(method), 1024), 0), Some{method}, first_concrete(rest))

def first_method(values: +List<M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match values:
    case Nil{}: None{}
    case Con{method, rest}: Some{method}

def prefer_concrete(found: Maybe<&2, M.LoadedMethod>, +values: +List<M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case Some{method}: Some{method}
    case None{}: first_method(values)

# After the superclass chain, resolution takes a maximally specific
# superinterface method that is neither static nor private, preferring a
# default (non-abstract) one.
def interface_resolution(+classes: +List<M.LoadedClass>, +methods: +List<M.LoadedMethod>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  +count = M.length(M.LoadedClass, classes)
  +ancestors = ancestor_ids(U32.to_nat(U32.add(U32.mul(count, U32.add(count, 1)), 1)), classes, Con{owner, Nil{}}, Nil{})
  +candidates = interface_candidates(methods, ancestors, name, descriptor)
  +maximal = maximal_methods(classes, candidates, candidates)
  prefer_concrete(first_concrete(maximal), maximal)

def find_method_resolved(found: Maybe<&2, M.LoadedMethod>, +classes: +List<M.LoadedClass>, +methods: +List<M.LoadedMethod>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case Some{method}: Some{method}
    case None{}: interface_resolution(classes, methods, owner, name, descriptor)

def find_method_id(found: Maybe<&2, U32>, +classes: +List<M.LoadedClass>, +methods: +List<M.LoadedMethod>, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{+owner}: find_method_resolved(method_hierarchy(256n, classes, methods, owner, name, descriptor), classes, methods, owner, name, descriptor)

def find_method(+classes: +List<M.LoadedClass>, +methods: +List<M.LoadedMethod>, +owner_name: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  find_method_id(class_id_by_name(classes, owner_name), classes, methods, name, descriptor)
def class_superclass_of(fuel: Nat, +classes: +List<M.LoadedClass>, owner: U32, +target: U32) -> Bool:
  match fuel:
    case 0n: False{}
    case 1n+remaining:
      +parent = class_parent_found(M.nth(M.LoadedClass, classes, owner))
      U32.is_eq(parent, target) || (U32.is_ne(parent, 4294967295) && class_superclass_of(remaining, classes, parent, target))

def invokespecial_caller(caller_class: Maybe<&2, M.LoadedClass>, +vm: M.VM, +symbolic_owner: U32, name: U32, descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match caller_class:
    case None{}: None{}
    case Some{+caller_value}:
      +parent = M.loaded_class_parent(caller_value)
      super_flag = U32.is_ne(U32.and(L.class_flags(vm, M.loaded_class_id(caller_value)), 32), 0)
      owner_is_ancestor = super_flag && U32.is_ne(parent, 4294967295) && class_superclass_of(256n, S.classes(vm), parent, symbolic_owner)
      lookup_owner = Bool.pick(U32, owner_is_ancestor, parent, symbolic_owner)
      find_method_id(Some{lookup_owner}, S.classes(vm), S.methods(vm), name, descriptor)
def invokespecial_method(+vm: M.VM, symbolic_owner: U32, caller: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  invokespecial_caller(M.nth(M.LoadedClass, S.classes(vm), caller), vm, symbolic_owner, name, descriptor)


def method_instruction(value: M.LoadedMethod, pc: U32) -> Maybe<&2, M.Instruction>:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}:
      M.nth(M.Instruction, instructions, pc)

def method_max_stack(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}: maxStack

def method_max_locals(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}: maxLocals

def method_result_tag(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}: resultTag

def method_parameters(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}: parameters

def method_intrinsic(value: M.LoadedMethod) -> U32:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}: intrinsic

def make_locals(n: Nat) -> +List<M.Slot>:
  M.zeros(n)


@unsafe def copy_arguments(values: +List<M.Slot>, +locals: +List<M.Slot>, +index: U32) -> +List<M.Slot>:
  match values:
    case Nil{}: locals
    case Con{+value, rest}:
      +next_locals : +List<M.Slot> = F.local_set_raw(locals, index, value)
      copy_arguments(rest, next_locals, U32.add(index, M.slot_width(value)))
def host_cont_of(h: M.Host) -> +List<M.Cont>:
  match h:
    case M.Host{effect, cwd, caps, maxPayload, cont, metadata, dynamicSites, loaders, sched, errors}: cont

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


def void_frames(+vm: M.VM, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: S.with_status(vm, 1)
    case Con{current, rest}:
      match rest:
        case Nil{}: S.with_status(vm, 1)
        case Con{caller, callers}: S.with_frames(vm, Con{caller, callers})
def allocate_named_result(+vm: M.VM, name: String, result: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match result:
    case Fail{error}: S.with_exception(vm, 2)
    case Done{H.Allocation{updated, reference}}: S.with_exception(updated, reference)

def allocate_named(+vm: M.VM, +name: String) -> M.VM:
  allocate_named_result(vm, name, H.allocate(vm, Tr.traced(vm, H.throwable_entry(H.named_class(S.classes(vm), S.symbols(vm), name)))))

def entry_with_message(entry: M.HeapEntry, message: U32) -> M.HeapEntry:
  M.HeapEntry{owner, kind, element, fields, values, chars} = entry
  M.HeapEntry{owner, kind, element, H.binding_set(fields, 0, M.Slot{3, message}), values, chars}

def throwable_with_message(class: U32, message: U32) -> M.HeapEntry:
  entry_with_message(H.throwable_entry(class), message)

def allocate_message_result(+vm: M.VM, +name: String, result: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match result:
    case Fail{error}: allocate_named(vm, name)
    case Done{H.Allocation{+updated, reference}}:
      allocate_named_result(updated, name, H.allocate(updated, Tr.traced(updated, throwable_with_message(H.named_class(S.classes(updated), S.symbols(updated), name), reference))))

# Raise a VM-detected Java error whose getMessage() carries the diagnostic.
def throw_with_message(+vm: M.VM, +name: String, message: String) -> M.VM:
  allocate_message_result(vm, name, H.allocate(vm, H.string_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/String"), L.units_from_string(message))))

# Failures naming a Java class are thrown as Java exceptions; others are VM faults.
def java_fault(error: String) -> Bool:
  String.starts_with(error, "java/")

type FaultParts is Data:
  FaultParts{name: String, message: String}

# VM faults name a Java class, optionally followed by ": detail" for getMessage().
def fault_split(text: String, acc: String) -> FaultParts:
  match text:
    case SNil{}: FaultParts{String.reverse(acc), ""}
    case SCon{Chr{58}, SCon{Chr{32}, rest}}: FaultParts{String.reverse(acc), rest}
    case SCon{head, rest}: fault_split(rest, SCon{head, acc})

def throw_fault_message(empty: Bool, +vm: M.VM, +name: String, message: String) -> M.VM:
  match empty:
    case True{}: allocate_named(vm, name)
    case False{}: throw_with_message(vm, name, message)

def throw_fault(+vm: M.VM, parts: FaultParts) -> M.VM:
  match parts:
    case FaultParts{+name, +message}: throw_fault_message(String.is_empty(message), vm, name, message)

def ensure_throw_state(has_exception: Bool, +vm: M.VM, error: String) -> M.VM:
  match has_exception:
    case True{}: vm
    case False{}: throw_fault(vm, fault_split(error, ""))

def ensure_throw(+vm: M.VM, error: String) -> M.VM:
  ensure_throw_state(U32.is_ne(S.exception(vm), 0), vm, error)

@unsafe def finish_reflect_outcome(+vm: M.VM, result: Result<&2, &2, String, O.Outcome>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{O.Returned{+updated, Some{value}}}:
      +frames = S.frames(updated)
      return_frames(updated, value, frames)
    case Done{O.Returned{+updated, None{}}}:
      +frames = S.frames(updated)
      void_frames(updated, frames)
    case Done{O.ThrownRef{updated, reference}}: S.with_status(S.with_exception(updated, reference), 6)
    case Done{O.ThrownName{updated, name}}: S.with_status(ensure_throw(updated, name), 6)
    case Done{O.Suspend{updated, effect}}: S.with_effect(updated, effect)
    case Done{O.Call{+updated, method, args}}: chained_call(updated, method, args, S.frames(updated))

def boundary_push(+vm: M.VM, effect: M.Effect, descriptor: U32) -> M.VM:
  S.with_cont(S.with_effect(vm, M.Idle{}), Con{M.CallBoundary{M.length(M.Frame, S.frames(vm)), effect, descriptor}, host_cont(vm)})

def proxy_return_exception(is_java_exception: Bool, +vm: M.VM, +error: String) -> Result<&2, &2, String, O.Outcome>:
  match is_java_exception:
    case True{}: Done{O.ThrownName{vm, error}}
    case False{}: Fail{error}
def proxy_return_value_result(+vm: M.VM, +text: String, converted: Result<&2, &2, String, M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match converted:
    case Fail{+error}: proxy_return_exception(String.eq(error, "java/lang/NullPointerException") || String.eq(error, "java/lang/ClassCastException"), vm, error)
    case Done{slot}: Done{O.Returned{vm, Bool.pick(Maybe<&2, M.Slot>, String.eq(L.method_return_name(text), "void"), None{}, Some{slot})}}


type AdaptedSlot is Data:
  AdaptedSlot{vm: M.VM, value: M.Slot}

def descriptor_code_chars(characters: +List<Char>) -> U32:
  match characters:
    case Con{Chr{code}, rest}: code
    case Nil{}: 86
def descriptor_code(text: String) -> U32:
  descriptor_code_chars(String.to_list(text))


def return_default(descriptor: String) -> M.Slot:
  match descriptor:
    case "V": M.Slot{3, 0}
    case "F": M.Slot{2, 0}
    case "J": M.Wide{4, 0, 0}
    case "D": M.Wide{5, 0, 0}
    case "Z": M.Slot{1, 0}
    case "B": M.Slot{1, 0}
    case "C": M.Slot{1, 0}
    case "S": M.Slot{1, 0}
    case "I": M.Slot{1, 0}
    case _: M.Slot{3, 0}

def wrapper_name_for_descriptor(descriptor: String) -> String:
  match descriptor:
    case "Z": "java/lang/Boolean"
    case "B": "java/lang/Byte"
    case "C": "java/lang/Character"
    case "S": "java/lang/Short"
    case "I": "java/lang/Integer"
    case "J": "java/lang/Long"
    case "F": "java/lang/Float"
    case _: "java/lang/Double"
def handle_box_return_alloc_result(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}: L.ref_out(updated, reference)

def handle_box_return_alloc(+vm: M.VM, descriptor: String, value: M.Slot, field: U32) -> Result<&2, &2, String, O.Outcome>:
  handle_box_return_alloc_result(H.allocate(vm, H.object_entry(H.named_class(S.classes(vm), S.symbols(vm), wrapper_name_for_descriptor(descriptor)), [M.Binding{field, value}])))

def handle_box_return_field(+vm: M.VM, descriptor: String, value: M.Slot, result: Result<&2, &2, String, U32>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{field}: handle_box_return_alloc(vm, descriptor, value, field)

def handle_box_return_cast_reference(result: Result<&2, &2, String, M.Slot>, +vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{_}: Fail{"java/lang/ClassCastException"}
    case Done{converted}: Done{O.Returned{vm, Some{converted}}}
def handle_box_return_cast(result: Result<&2, &2, String, O.Outcome>, requested: String) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{+vm, Some{reference}}}:
      handle_box_return_cast_reference(L.reflect_convert_reference(vm, requested, reference), vm)
    case Done{other}: Done{other}

def handle_return_reference_result(result: Result<&2, &2, String, M.Slot>, +vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{_}: Fail{"java/lang/ClassCastException"}
    case Done{converted}: Done{O.Returned{vm, Some{converted}}}

def handle_return_primitive_result(result: Result<&2, &2, String, M.Slot>, +vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{converted}: Done{O.Returned{vm, Some{converted}}}

def handle_return_widen_result(result: Result<&2, &2, String, M.Slot>, +vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{_}: Fail{"java/lang/invoke/WrongMethodTypeException"}
    case Done{converted}: Done{O.Returned{vm, Some{converted}}}

# Method-handle boxing follows Java's valueOf semantics through the shared MiniJRE boxer.
def handle_return_box_primitive(+vm: M.VM, +source: String, requested: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  handle_box_return_cast(L.reflect_box_value(vm, MH.primitive_name(source), value), requested)

def descriptor_is_reference_chars(chars: +List<Char>) -> Bool:
  match chars:
    case Con{Chr{76}, rest}: True{}
    case Con{Chr{91}, rest}: True{}
    case _: False{}

def descriptor_is_reference(text: String) -> Bool:
  descriptor_is_reference_chars(String.to_list(text))
def handle_return_nonvoid(+vm: M.VM, +source: String, +requested: String, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  source_reference = descriptor_is_reference(source)
  +requested_reference = descriptor_is_reference(requested)
  Bool.pick(Result<&2, &2, String, O.Outcome>, source_reference,
    Bool.pick(Result<&2, &2, String, O.Outcome>, requested_reference,
      handle_return_reference_result(L.reflect_convert_reference(vm, requested, value), vm),
      handle_return_primitive_result(L.reflect_convert_primitive(vm, descriptor_code(requested), value), vm)),
    Bool.pick(Result<&2, &2, String, O.Outcome>, requested_reference,
      handle_return_box_primitive(vm, source, requested, value),
      handle_return_widen_result(L.reflect_widen(descriptor_code(source), descriptor_code(requested), value), vm)))

def handle_return_convert(+vm: M.VM, source: String, requested: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match source requested:
    case _ "V": Done{O.Returned{vm, None{}}}
    case "V" _:
      Done{O.Returned{vm, Some{return_default(requested)}}}
    case _ _: handle_return_nonvoid(vm, source, requested, value)

def handle_return_target(vm: M.VM, target_return: String, requested_return: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match target_return:
    case "V": Done{O.Returned{vm, Some{return_default(requested_return)}}}
    case _: handle_return_convert(vm, target_return, requested_return, value)
def handle_return_requested(vm: M.VM, target_return: String, requested_return: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match requested_return:
    case "V": Done{O.Returned{vm, None{}}}
    case _: handle_return_target(vm, target_return, requested_return, value)
def handle_return_result(+vm: M.VM, target_descriptor: String, requested_descriptor: String, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  target_return = String.from_list(MH.chars_after(String.to_list(target_descriptor), 41, False{}))
  requested_return = String.from_list(MH.chars_after(String.to_list(requested_descriptor), 41, False{}))
  handle_return_requested(vm, target_return, requested_return, value)


def boundary_value(+vm: M.VM, effect: M.Effect, descriptor: U32, value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match effect:
    case M.ReflectCall{}: L.reflect_box_return(vm, Sy.text(S.symbols(vm), descriptor), value)
    case M.ReflectConstructor{reference}: Done{O.Returned{vm, Some{M.Slot{3, reference}}}}
    case M.ProxyCall{+text, method_id, owners}:
      proxy_return_value_result(vm, text, L.proxy_return_value(vm, text, value))
    case M.HandleAdapter{targetDescriptor, requestedDescriptor}:
      handle_return_result(vm, Sy.text(S.symbols(vm), targetDescriptor), Sy.text(S.symbols(vm), requestedDescriptor), value)
    case M.HandleConstructor{reference}: Done{O.Returned{vm, Some{M.Slot{3, reference}}}}
    case _: Done{O.Returned{vm, Some{value}}}

type AdaptedArguments is Data:
  AdaptedArguments{vm: M.VM, values: +List<M.Slot>}

def handle_box_slot_alloc_result(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, AdaptedSlot>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}:
      Done{AdaptedSlot{updated, M.Slot{3, reference}}}

def handle_box_slot_alloc(+vm: M.VM, descriptor: String, value: M.Slot, field: U32) -> Result<&2, &2, String, AdaptedSlot>:
  class = H.named_class(S.classes(vm), S.symbols(vm), wrapper_name_for_descriptor(descriptor))
  handle_box_slot_alloc_result(H.allocate(vm, H.object_entry(class, [M.Binding{field, value}])))



def handle_box_slot_field(+vm: M.VM, descriptor: String, value: M.Slot, result: Result<&2, &2, String, U32>) -> Result<&2, &2, String, AdaptedSlot>:
  match result:
    case Fail{error}: Fail{error}
    case Done{field}: handle_box_slot_alloc(vm, descriptor, value, field)

# Class.cast's message: "Cannot cast <value class> to <target class>".
def handle_adapt_slot_reference(result: Result<&2, &2, String, M.Slot>, +vm: M.VM, value: M.Slot, target: String) -> Result<&2, &2, String, AdaptedSlot>:
  match result:
    case Fail{_}: Fail{L.cast_failure(vm, M.slot_bits(value), target)}
    case Done{converted}: Done{AdaptedSlot{vm, converted}}

def handle_adapt_slot_primitive(result: Result<&2, &2, String, M.Slot>, +vm: M.VM) -> Result<&2, &2, String, AdaptedSlot>:
  match result:
    case Fail{error}: Fail{error}
    case Done{converted}: Done{AdaptedSlot{vm, converted}}

def handle_adapt_slot_unbox(result: Result<&2, &2, String, M.Slot>, value: M.Slot, +vm: M.VM) -> Result<&2, &2, String, AdaptedSlot>:
  match result:
    case Fail{_}:
      Bool.pick(Result<&2, &2, String, AdaptedSlot>, U32.is_eq(M.slot_bits(value), 0),
        Fail{"java/lang/NullPointerException"}, Fail{"java/lang/ClassCastException"})
    case Done{converted}: Done{AdaptedSlot{vm, converted}}

def handle_adapt_slot_widen(result: Result<&2, &2, String, M.Slot>, +vm: M.VM) -> Result<&2, &2, String, AdaptedSlot>:
  match result:
    case Fail{_}: Fail{"java/lang/invoke/WrongMethodTypeException"}
    case Done{converted}: Done{AdaptedSlot{vm, converted}}

def handle_adapt_slot_boxed_reference(boxed: AdaptedSlot, +target: String) -> Result<&2, &2, String, AdaptedSlot>:
  match boxed:
    case AdaptedSlot{+updated, +reference}:
      handle_adapt_slot_reference(L.reflect_convert_reference(updated, target, reference), updated, reference, target)

def handle_box_outcome_slot(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, AdaptedSlot>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{vm, Some{slot}}}: Done{AdaptedSlot{vm, slot}}
    case Done{_}: Fail{"InvalidState: primitive boxing produced no value"}

def handle_adapt_slot_box_reference(+vm: M.VM, +source: String, target: String, value: M.Slot) -> Result<&2, &2, String, AdaptedSlot>:
  do Result<&2, &2, String, AdaptedSlot>:
    boxed : AdaptedSlot <- handle_box_outcome_slot(L.reflect_box_value(vm, MH.primitive_name(source), value))
    result : AdaptedSlot <- handle_adapt_slot_boxed_reference(boxed, target)
    return result

def handle_adapt_slot_distinct(+vm: M.VM, +source: String, +target: String, +value: M.Slot) -> Result<&2, &2, String, AdaptedSlot>:
  source_reference = descriptor_is_reference(source)
  +target_reference = descriptor_is_reference(target)
  Bool.pick(Result<&2, &2, String, AdaptedSlot>, source_reference,
    Bool.pick(Result<&2, &2, String, AdaptedSlot>, target_reference,
      handle_adapt_slot_reference(L.reflect_convert_reference(vm, target, value), vm, value, target),
      handle_adapt_slot_unbox(L.reflect_convert_primitive(vm, descriptor_code(target), value), value, vm)),
    Bool.pick(Result<&2, &2, String, AdaptedSlot>, target_reference,
      handle_adapt_slot_box_reference(vm, source, target, value),
      handle_adapt_slot_widen(L.reflect_widen(descriptor_code(source), descriptor_code(target), value), vm)))

def handle_adapt_slot(+vm: M.VM, +source: String, +target: String, +value: M.Slot) -> Result<&2, &2, String, AdaptedSlot>:
  Bool.pick(Result<&2, &2, String, AdaptedSlot>, String.eq(source, target),
    Done{AdaptedSlot{vm, value}}, handle_adapt_slot_distinct(vm, source, target, value))
type HandleAdaptWork is Data:
  HandleAdaptInput{vm: M.VM, sources: +List<String>, targets: +List<String>, values: +List<M.Slot>, acc: +List<M.Slot>}
  HandleAdaptResult{converted: Result<&2, &2, String, AdaptedSlot>, sources: +List<String>, targets: +List<String>, values: +List<M.Slot>, acc: +List<M.Slot>}

@unsafe def handle_adapt_arguments_work(work: HandleAdaptWork) -> Result<&2, &2, String, AdaptedArguments>:
  match work:
    case HandleAdaptInput{vm, sources, targets, values, acc}:
      match sources targets values:
        case Nil{} Nil{} Nil{}: Done{AdaptedArguments{vm, M.reverse(M.Slot, acc)}}
        case Con{source, source_rest} Con{target, target_rest} Con{value, value_rest}:
          handle_adapt_arguments_work(HandleAdaptResult{handle_adapt_slot(vm, source, target, value), source_rest, target_rest, value_rest, acc})
        case _ _ _: Fail{"java/lang/invoke/WrongMethodTypeException"}
    case HandleAdaptResult{converted, sources, targets, values, acc}:
      match converted:
        case Fail{error}: Fail{error}
        case Done{AdaptedSlot{updated, slot}}:
          handle_adapt_arguments_work(HandleAdaptInput{updated, sources, targets, values, Con{slot, acc}})


def handle_adapt_arguments(+vm: M.VM, source: String, target: String, values: +List<M.Slot>) -> Result<&2, &2, String, AdaptedArguments>:
  sources = MH.descriptor_tokens(MH.descriptor_params(source), Nil{})
  targets = MH.descriptor_tokens(MH.descriptor_params(target), Nil{})
  handle_adapt_arguments_work(HandleAdaptInput{vm, sources, targets, values, Nil{}})

type HandleVarargsArray is Data:
  HandleVarargsArray{vm: M.VM, reference: U32}

def handle_type_descriptor(value: M.JvmType) -> String:
  match value:
    case M.Primitive{tag}: String.from_list([Chr{tag}])
    case M.ObjectType{name}: "L" ++ name ++ ";"
    case M.ArrayType{element}: "[" ++ handle_type_descriptor(element)

def handle_parameter_descriptor(types: +List<M.JvmType>) -> String:
  match types:
    case Nil{}: ""
    case Con{value, rest}: handle_type_descriptor(value) ++ handle_parameter_descriptor(rest)

@unsafe def handle_repeat_descriptor(+descriptor: String, count: U32) -> String:
  match count:
    case 0: ""
    case _: descriptor ++ handle_repeat_descriptor(descriptor, U32.sub(count, 1))

def handle_array_atype(tag: U32) -> U32:
  match tag:
    case 90: 4
    case 67: 5
    case 70: 6
    case 68: 7
    case 66: 8
    case 83: 9
    case 73: 10
    case 74: 11
    case _: 0

def handle_varargs_array_result(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, HandleVarargsArray>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}: Done{HandleVarargsArray{updated, reference}}


def handle_varargs_primitive_array(vm: M.VM, array_class: U32, tag: U32, values: +List<M.Slot>) -> Result<&2, &2, String, HandleVarargsArray>:
  do Result<&2, &2, String, HandleVarargsArray>:
    +atype : U32 = handle_array_atype(tag)
    checked : Unit <- S.check(U32.is_ne(atype, 0), "java/lang/invoke/WrongMethodTypeException")
    result : HandleVarargsArray <- handle_varargs_array_result(H.allocate(vm, H.primitive_array_entry(array_class, atype, values)))
    return result

def handle_varargs_reference_array(+vm: M.VM, array_class: U32, component_name: String, values: +List<M.Slot>) -> Result<&2, &2, String, HandleVarargsArray>:
  do Result<&2, &2, String, HandleVarargsArray>:
    +component_class : U32 = H.named_class(S.classes(vm), S.symbols(vm), component_name)
    checked : Unit <- S.check(U32.is_ne(component_class, 4294967295), "java/lang/NoClassDefFoundError")
    result : HandleVarargsArray <- handle_varargs_array_result(H.allocate(vm, H.reference_array_entry(array_class, component_class, values)))
    return result
def handle_varargs_array_component(vm: M.VM, array_class: U32, component: M.JvmType, values: +List<M.Slot>) -> Result<&2, &2, String, HandleVarargsArray>:
  match component:
    case M.Primitive{tag}: handle_varargs_primitive_array(vm, array_class, tag, values)
    case M.ObjectType{name}: handle_varargs_reference_array(vm, array_class, name, values)
    case M.ArrayType{element}: handle_varargs_reference_array(vm, array_class, handle_type_descriptor(component), values)
def handle_varargs_array(+vm: M.VM, array_descriptor: String, component: M.JvmType, values: +List<M.Slot>) -> Result<&2, &2, String, HandleVarargsArray>:
  do Result<&2, &2, String, HandleVarargsArray>:
    +array_class : U32 = H.named_class(S.classes(vm), S.symbols(vm), array_descriptor)
    checked : Unit <- S.check(U32.is_ne(array_class, 4294967295), "java/lang/NoClassDefFoundError")
    result : HandleVarargsArray <- handle_varargs_array_component(vm, array_class, component, values)
    return result


def handle_varargs_last_array_result(found: Maybe<&2, M.JvmType>, +vm: M.VM, target_array: String) -> Bool:
  match found:
    case None{}: False{}
    case Some{source_last}:
      source_descriptor = handle_type_descriptor(source_last)
      H.descriptor_assignable(source_descriptor, target_array, S.classes(vm), S.symbols(vm))

def handle_varargs_last_array_compatible(vm: M.VM, source: +List<M.JvmType>, count: U32, target_array: String) -> Bool:
  handle_varargs_last_array_result(M.nth(M.JvmType, source, U32.sub(count, 1)), vm, target_array)

def handle_varargs_pack_array(result: Result<&2, &2, String, HandleVarargsArray>, prefix_values: +List<M.Slot>) -> Result<&2, &2, String, AdaptedArguments>:
  match result:
    case Fail{error}: Fail{error}
    case Done{HandleVarargsArray{vm, reference}}: Done{AdaptedArguments{vm, M.append(M.Slot, prefix_values, [M.Slot{3, reference}])}}
def handle_varargs_pack_tail(result: Result<&2, &2, String, AdaptedArguments>, prefix_values: +List<M.Slot>, target_array: String, component: M.JvmType) -> Result<&2, &2, String, AdaptedArguments>:
  match result:
    case Fail{error}: Fail{error}
    case Done{AdaptedArguments{vm, tail_values}}:
      handle_varargs_pack_array(handle_varargs_array(vm, target_array, component, tail_values), prefix_values)
def handle_varargs_pack_fixed(fixed: AdaptedArguments, source_descriptor: String, target_descriptor: String, values: +List<M.Slot>, target_array: String, component: M.JvmType) -> Result<&2, &2, String, AdaptedArguments>:
  match fixed:
    case AdaptedArguments{vm, prefix_values}:
      handle_varargs_pack_tail(handle_adapt_arguments(vm, source_descriptor, target_descriptor, values), prefix_values, target_array, component)
def handle_varargs_pack(+vm: M.VM, source_descriptor: String, +source: +List<M.JvmType>, target: +List<M.JvmType>, +values: +List<M.Slot>, +fixed_count: U32, target_array: String, +component: M.JvmType) -> Result<&2, &2, String, AdaptedArguments>:
  do Result<&2, &2, String, AdaptedArguments>:
    source_count : U32 = M.length(M.JvmType, source)
    checked : Unit <- S.check(U32.is_ge(source_count, fixed_count), "java/lang/invoke/WrongMethodTypeException")
    fixed_source : +List<M.JvmType> = M.take(M.JvmType, source, U32.to_nat(fixed_count))
    fixed_target : +List<M.JvmType> = M.take(M.JvmType, target, U32.to_nat(fixed_count))
    fixed_values : +List<M.Slot> = M.take(M.Slot, values, U32.to_nat(fixed_count))
    source_prefix : String = "(" ++ handle_parameter_descriptor(fixed_source) ++ ")V"
    target_prefix : String = "(" ++ handle_parameter_descriptor(fixed_target) ++ ")V"
    fixed : AdaptedArguments <- handle_adapt_arguments(vm, source_prefix, target_prefix, fixed_values)
    +source_tail : +List<M.JvmType> = M.drop(M.JvmType, source, U32.to_nat(fixed_count))
    values_tail : +List<M.Slot> = M.drop(M.Slot, values, U32.to_nat(fixed_count))
    tail_count : U32 = M.length(M.JvmType, source_tail)
    component_descriptor : String = handle_type_descriptor(component)
    source_tail_descriptor : String = "(" ++ handle_parameter_descriptor(source_tail) ++ ")V"
    target_tail_descriptor : String = "(" ++ handle_repeat_descriptor(component_descriptor, tail_count) ++ ")V"
    result : AdaptedArguments <- handle_varargs_pack_fixed(fixed, source_tail_descriptor, target_tail_descriptor, values_tail, target_array, component)
    return result


def handle_varargs_target_adapt(+vm: M.VM, +source_descriptor: String, +target_descriptor: String, +source: +List<M.JvmType>, +target: +List<M.JvmType>, +values: +List<M.Slot>, +source_count: U32, +target_count: U32, last: M.JvmType) -> Result<&2, &2, String, AdaptedArguments>:
  match last:
    case M.ArrayType{+element}:
      +target_array = handle_type_descriptor(last)
      compatible = U32.is_eq(source_count, target_count) && handle_varargs_last_array_compatible(vm, source, source_count, target_array)
      Bool.pick(Result<&2, &2, String, AdaptedArguments>, compatible,
        handle_adapt_arguments(vm, source_descriptor, target_descriptor, values),
        handle_varargs_pack(vm, source_descriptor, source, target, values, U32.sub(target_count, 1), target_array, element))
    case _: Fail{"java/lang/invoke/WrongMethodTypeException"}

def handle_varargs_adapt(+vm: M.VM, +source_descriptor: String, +target_descriptor: String, values: +List<M.Slot>) -> Result<&2, &2, String, AdaptedArguments>:
  do Result<&2, &2, String, AdaptedArguments>:
    source_method : M.Descriptor <- D.parse_method(source_descriptor)
    target_method : M.Descriptor <- D.parse_method(target_descriptor)
    +source : +List<M.JvmType> = D.parameter_types(source_method)
    +target : +List<M.JvmType> = D.parameter_types(target_method)
    source_count : U32 = M.length(M.JvmType, source)
    +target_count : U32 = M.length(M.JvmType, target)
    checked : Unit <- S.check(U32.is_gt(target_count, 0), "java/lang/invoke/WrongMethodTypeException")
    last : M.JvmType <- S.require(M.JvmType, M.nth(M.JvmType, target, U32.sub(target_count, 1)), "java/lang/invoke/WrongMethodTypeException")
    result : AdaptedArguments <- handle_varargs_target_adapt(vm, source_descriptor, target_descriptor, source, target, values, source_count, target_count, last)
    return result

def handle_is_varargs_found(found: Maybe<&2, M.Slot>) -> Bool:
  match found:
    case None{}: False{}
    case Some{slot}: U32.is_ne(M.slot_bits(slot), 0)
def handle_is_varargs(entry: M.HeapEntry) -> Bool:
  handle_is_varargs_found(H.binding_find(L.entry_fields(entry), 4294967295))


def handle_adapt_target_kind(vm: M.VM, source_descriptor: String, target_descriptor: String, values: +List<M.Slot>, varargs: Bool) -> Result<&2, &2, String, AdaptedArguments>:
  match varargs:
    case True{}: handle_varargs_adapt(vm, source_descriptor, target_descriptor, values)
    case False{}: handle_adapt_arguments(vm, source_descriptor, target_descriptor, values)
def handle_adapt_target(+vm: M.VM, reference: U32, source_descriptor: String, target_descriptor: String, values: +List<M.Slot>) -> Result<&2, &2, String, AdaptedArguments>:
  do Result<&2, &2, String, AdaptedArguments>:
    entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    varargs : Bool = handle_is_varargs(entry)
    result : AdaptedArguments <- handle_adapt_target_kind(vm, source_descriptor, target_descriptor, values, varargs)
    return result


def handle_boundary_push_effect(+vm: M.VM, effect: M.Effect, descriptor: U32) -> M.VM:
  S.with_cont(vm, Con{M.CallBoundary{M.length(M.Frame, S.frames(vm)), effect, descriptor}, host_cont(vm)})

def handle_boundary_push_same(+vm: M.VM, target: String, requested: String, same: Bool) -> M.VM:
  match same:
    case True{}: vm
    case False{}:
      +target_intern = Sy.intern(S.symbols(vm), target)
      +vm1 = S.with_symbols(vm, Sy.interned_symbols(target_intern))
      +requested_intern = Sy.intern(S.symbols(vm1), requested)
      vm2 = S.with_symbols(vm1, Sy.interned_symbols(requested_intern))
      target_id = MH.interned_id(target_intern)
      +requested_id = MH.interned_id(requested_intern)
      handle_boundary_push_effect(vm2, M.HandleAdapter{target_id, requested_id}, requested_id)
def handle_boundary_push(+vm: M.VM, +target: String, +requested: String) -> M.VM:
  handle_boundary_push_same(vm, target, requested, String.eq(target, requested))


def handle_value_binding(entry: M.HeapEntry, index: U32) -> Result<&2, &2, String, M.Slot>:
  S.require(M.Slot, H.binding_find(L.entry_fields(entry), index), "java/lang/IllegalStateException")

def handle_instance_fields(values: +List<M.LoadedField>, +classes: +List<M.LoadedClass>, +owner: U32) -> +List<M.Binding>:
  match values:
    case Nil{}: Nil{}
    case Con{+field, rest}:
      +tail = handle_instance_fields(rest, classes, owner)
      include = U32.is_eq(U32.and(M.loaded_field_flags(field), 8), 0) && H.hierarchy(classes, owner, M.loaded_field_owner(field))
      Bool.pick(+List<M.Binding>, include,
        Con{M.Binding{M.loaded_field_id(field), M.default_slot(M.loaded_field_tag(field))}, tail}, tail)

def handle_caller_owner(vm: M.VM, frame: M.Frame) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)), "InvalidState: handle caller")
    return M.loaded_method_owner(method)

def handle_frame_push_frames(frames: +List<M.Frame>, vm: M.VM, id: U32, maxLocals: U32, args: +List<M.Slot>, +caller: M.Frame) -> M.VM:
  match frames:
    case Con{current, rest}:
      S.with_frames(vm, Con{M.Frame{id, 0, S.pc(caller), copy_arguments(args, make_locals(U32.to_nat(maxLocals)), 0), Nil{}, 4294967295, 0}, Con{S.advance(caller), rest}})
    case Nil{}: S.fail(vm, "InvalidState: method handle invocation without caller")
def handle_bytecode_push(+vm: M.VM, method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame) -> M.VM:
  match method:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}:
      handle_frame_push_frames(S.frames(vm), vm, id, maxLocals, args, caller)

# Method-handle targets may be bytecode, MiniJRE intrinsics, or lambda SAM
# bridges; the shared dispatcher selects the right execution path.
@unsafe def handle_frame_push(+vm: M.VM, +method: M.LoadedMethod, +args: +List<M.Slot>, caller: M.Frame) -> M.VM:
  invoke_job(vm, JDispatch{method, args, caller})

@unsafe def handle_frame_push_exact(+vm: M.VM, +method: M.LoadedMethod, +args: +List<M.Slot>, caller: M.Frame) -> M.VM:
  invoke_job(vm, JDispatchExact{method, args, caller, method_intrinsic(method)})


def handle_initializer_frames(frames: +List<M.Frame>, vm: M.VM, owner: U32) -> M.VM:
  match frames:
    case Con{frame, rest}: S.with_frames(vm, Con{S.frame_initializing(frame, owner), rest})
    case Nil{}: S.fail(vm, "InvalidState: initializer invocation without caller")
def handle_initializer_push(+vm: M.VM, method: M.LoadedMethod, owner: U32, +caller: M.Frame) -> M.VM:
  +pushed = handle_bytecode_push(vm, method, Nil{}, caller)
  handle_initializer_frames(S.frames(pushed), pushed, owner)



def handle_method_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +caller: M.Frame, args: +List<M.Slot>, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchMethodError"}
    case Some{method}:
      vm2 = handle_boundary_push(vm, target, requested)
      Done{handle_frame_push(vm2, method, args, caller)}

# Handle access was checked when the handle was looked up, not at invocation.
def handle_field_access(+vm: M.VM, caller: M.Frame, +field: M.LoadedField, +static: Bool) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    field_static : Bool = U32.is_ne(U32.and(M.loaded_field_flags(field), 8), 0)
    checked : Unit <- S.check(Bool.pick(Bool, field_static, static, Bool.not(static)), "IncompatibleClassChangeError")
    return Unit{}

def handle_static_outcome(outcome: O.Outcome, vm: M.VM, caller: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  match outcome:
    case O.Returned{updated, Some{value}}:
      do Result<&2, &2, String, M.VM>:
        pushed : M.Frame <- F.push(S.advance(caller), value, max)
        return S.commit(updated, pushed)
    case O.Returned{updated, None{}}: Done{S.commit(updated, S.advance(caller))}
    case O.ThrownName{updated, name}: Done{S.with_status(ensure_throw(updated, name), 6)}
    case O.ThrownRef{updated, reference}: Done{S.with_status(S.with_exception(updated, reference), 6)}
    case _: Fail{"InvalidState: handle field result"}
# Field handles finish without a callee frame, so they return through the
# boundary machinery (handle_immediate) and pending asType adapters apply.
@unsafe def handle_static_result(+vm: M.VM, +caller: M.Frame, field: M.LoadedField, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    slot : M.Slot <- S.require(M.Slot, H.binding_find(S.statics(vm), M.loaded_field_id(field)), "NoSuchFieldError")
    return handle_immediate(vm, caller, slot)



def handle_field_value(+vm: M.VM, +caller: M.Frame, field: M.LoadedField, +reference: U32) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    checked : Unit <- S.check(U32.is_ne(reference, 0), "java/lang/NullPointerException")
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), 0), "java/lang/IncompatibleClassChangeError")
    slot : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(entry), M.loaded_field_id(field)), "NoSuchFieldError")
    return slot

def handle_instance_outcome(outcome: O.Outcome, vm: M.VM, caller: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  match outcome:
    case O.Returned{updated, Some{value}}:
      do Result<&2, &2, String, M.VM>:
        pushed : M.Frame <- F.push(S.advance(caller), value, max)
        return S.commit(updated, pushed)
    case O.Returned{updated, None{}}: Done{S.commit(updated, S.advance(caller))}
    case O.ThrownName{updated, name}: Done{S.with_status(ensure_throw(updated, name), 6)}
    case O.ThrownRef{updated, reference}: Done{S.with_status(S.with_exception(updated, reference), 6)}
    case _: Fail{"InvalidState: handle field result"}
@unsafe def handle_instance_result(+vm: M.VM, +caller: M.Frame, field: M.LoadedField, reference: U32, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    slot : M.Slot <- handle_field_value(vm, caller, field, reference)
    return handle_immediate(vm, caller, slot)


@unsafe def handle_field_store(+vm: M.VM, +caller: M.Frame, +field: M.LoadedField, +reference: U32, +value: M.Slot, static: Bool) -> Result<&2, &2, String, M.VM>:
  match static:
    case True{}:
      Done{handle_immediate_void(S.with_statics(vm, H.binding_set(S.statics(vm), M.loaded_field_id(field), value)), caller)}
    case False{}:
      do Result<&2, &2, String, M.VM>:
        checked : Unit <- S.check(U32.is_ne(reference, 0), "java/lang/NullPointerException")
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), 0), "java/lang/IncompatibleClassChangeError")
        updated : M.HeapEntry = M.HeapEntry{H.entry_class(entry), 0, 0, H.binding_set(L.entry_fields(entry), M.loaded_field_id(field), value), Nil{}, Nil{}}
        return handle_immediate_void(H.put(vm, reference, updated), caller)


def handle_field_get_instance(args: +List<M.Slot>, vm: M.VM, caller: M.Frame, field: M.LoadedField, +descriptor: String, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case Con{M.Slot{3, reference}, Nil{}}: handle_instance_result(vm, caller, field, reference, descriptor, descriptor, max)
    case _: Fail{"java/lang/invoke/WrongMethodTypeException"}

def handle_field_put_instance(args: +List<M.Slot>, vm: M.VM, caller: M.Frame, field: M.LoadedField) -> Result<&2, &2, String, M.VM>:
  match args:
    case Con{M.Slot{3, reference}, Con{value, Nil{}}}: handle_field_store(vm, caller, field, reference, value, False{})
    case _: Fail{"java/lang/invoke/WrongMethodTypeException"}

def handle_field_put_static(args: +List<M.Slot>, vm: M.VM, caller: M.Frame, field: M.LoadedField) -> Result<&2, &2, String, M.VM>:
  match args:
    case Con{value, Nil{}}: handle_field_store(vm, caller, field, 0, value, True{})
    case _: Fail{"java/lang/invoke/WrongMethodTypeException"}
def handle_field_invoke_kind(kind: U32, +vm: M.VM, +caller: M.Frame, +field: M.LoadedField, +args: +List<M.Slot>, +descriptor: String, +max: U32) -> Result<&2, &2, String, M.VM>:
  match kind:
    case 1: handle_field_get_instance(args, vm, caller, field, descriptor, max)
    case 2: handle_static_result(vm, caller, field, descriptor, descriptor, max)
    case 3: handle_field_put_instance(args, vm, caller, field)
    case 4: handle_field_put_static(args, vm, caller, field)
    case _: Fail{"java/lang/invoke/WrongMethodTypeException"}
def handle_field_invoke(+vm: M.VM, +caller: M.Frame, +entry: M.HeapEntry, args: +List<M.Slot>, +kind: U32, descriptor: String, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    owner_slot : M.Slot <- handle_value_binding(entry, 0)
    name_slot : M.Slot <- handle_value_binding(entry, 1)
    desc_slot : M.Slot <- handle_value_binding(entry, 2)
    owner : U32 = M.slot_bits(owner_slot)
    name : U32 = M.slot_bits(name_slot)
    field_desc : U32 = M.slot_bits(desc_slot)
    +field : M.LoadedField <- S.require(M.LoadedField,
      H.resolve_field(S.classes(vm), S.fields(vm), owner, name, field_desc), "NoSuchFieldError")
    static : Bool = U32.is_eq(kind, 2) || U32.is_eq(kind, 4)
    checked : Unit <- handle_field_access(vm, caller, field, static)
    result : M.VM <- handle_field_invoke_kind(kind, vm, caller, field, args, descriptor, max)
    return result


# Virtual selection: the receiver's superclass chain, then maximally specific
# superinterface methods (default methods), as invokevirtual/invokeinterface do.
def handle_virtual_entry(result: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM, name: U32, descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match result:
    case Done{entry}: find_method_id(Some{H.entry_class(entry)}, S.classes(vm), S.methods(vm), name, descriptor)
    case _: None{}

def handle_virtual_receiver(args: +List<M.Slot>, +vm: M.VM, name: U32, descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match args:
    case Con{M.Slot{3, reference}, rest}: handle_virtual_entry(H.get(S.heap(vm), reference), vm, name, descriptor)
    case _: None{}

def handle_virtual_method(vm: M.VM, owner_name: U32, name: U32, descriptor: U32, args: +List<M.Slot>) -> Maybe<&2, M.LoadedMethod>:
  handle_virtual_receiver(args, vm, name, descriptor)

def handle_constructor_allocation(allocation: Result<&2, &2, String, H.Allocation>, caller: M.Frame, +method: M.LoadedMethod, args: +List<M.Slot>) -> Result<&2, &2, String, M.VM>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, +reference}}:
      method_desc_id = M.loaded_method_descriptor(method)
      vm2 = handle_boundary_push_effect(updated, M.HandleConstructor{reference}, method_desc_id)
      Done{handle_frame_push(vm2, method, Con{M.Slot{3, reference}, args}, caller)}
def handle_constructor_start(+vm: M.VM, +caller: M.Frame, method: M.LoadedMethod, +owner: U32, args: +List<M.Slot>, descriptor: String) -> Result<&2, &2, String, M.VM>:
  handle_constructor_allocation(H.allocate(vm, H.object_entry(owner, handle_instance_fields(S.fields(vm), S.classes(vm), owner))), caller, method, args)

def handle_initialized_dispatch(+vm: M.VM, +caller: M.Frame, kind: U32, owner: U32, name: U32, descriptor: U32, +method_id: U32, +entry: M.HeapEntry, +args: +List<M.Slot>, +target: String, +requested: String, +max: U32) -> Result<&2, &2, String, M.VM>:
  match kind:
    case 2: handle_field_invoke(vm, caller, entry, args, kind, requested, max)
    case 4: handle_field_invoke(vm, caller, entry, args, kind, requested, max)
    case 6:
      do Result<&2, &2, String, M.VM>:
        method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), method_id), "NoSuchMethodError")
        result : M.VM <- handle_method_found(Some{method}, vm, caller, args, target, requested, max)
        return result
    case 8:
      do Result<&2, &2, String, M.VM>:
        method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), method_id), "NoSuchMethodError")
        result : M.VM <- handle_constructor_start(vm, caller, method, owner, args, target)
        return result
    case _: Fail{"java/lang/invoke/WrongMethodTypeException"}

def handle_class_init_start(start: L.ClassForNameStart, +caller: M.Frame, kind: U32, owner: U32, name: U32, descriptor: U32, method_id: U32, entry: M.HeapEntry, args: +List<M.Slot>, target_descriptor: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  match start:
    case L.ClassForNameReady{+vm}:
      handle_initialized_dispatch(vm, caller, kind, owner, name, descriptor, method_id, entry, args, target_descriptor, requested, max)
    case L.ClassForNameBlocked{+vm, class}: Done{S.with_status(Th.park(vm, M.InitWait{class}, False{}, M.Clock{0, 0}), 7)}
    case L.ClassForNameCall{+vm, +target, +method}:
      do Result<&2, &2, String, M.VM>:
        previous : M.Effect = S.host_effect(vm)
        +vm1 : M.VM = S.with_effect(S.set_class_state(vm, target, 1), M.Idle{})
        depth : U32 = M.length(M.Frame, S.frames(vm1))
        continuation : M.Cont = M.HandleInvocation{depth, kind, owner, name, descriptor, method_id, entry, args, target_descriptor, requested, max, previous}
        vm2 : M.VM = S.with_cont(vm1, Con{continuation, host_cont(vm1)})
        return handle_initializer_push(vm2, method, target, caller)

def handle_class_init(+vm: M.VM, +caller: M.Frame, kind: U32, +owner: U32, name: U32, descriptor: U32, method_id: U32, entry: M.HeapEntry, args: +List<M.Slot>, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    start : L.ClassForNameStart <- L.class_for_name_walk(256n, vm, owner)
    result : M.VM <- handle_class_init_start(start, caller, kind, owner, name, descriptor, method_id, entry, args, target, requested, max)
    return result

def handle_static_field_init(+vm: M.VM, +caller: M.Frame, +entry: M.HeapEntry, args: +List<M.Slot>, kind: U32, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    owner_slot : M.Slot <- handle_value_binding(entry, 0)
    name_slot : M.Slot <- handle_value_binding(entry, 1)
    desc_slot : M.Slot <- handle_value_binding(entry, 2)
    owner : U32 = M.slot_bits(owner_slot)
    +name : U32 = M.slot_bits(name_slot)
    +descriptor : U32 = M.slot_bits(desc_slot)
    +field : M.LoadedField <- S.require(M.LoadedField,
      H.resolve_field(S.classes(vm), S.fields(vm), owner, name, descriptor), "NoSuchFieldError")
    checked : Unit <- handle_field_access(vm, caller, field, True{})
    result : M.VM <- handle_class_init(vm, caller, kind, M.loaded_field_owner(field), name, descriptor, 0, entry, args, target, requested, max)
    return result




def handle_direct_special_slot(vm: M.VM, owner: U32, name: U32, descriptor: U32, result: Result<&2, &2, String, M.Slot>) -> Maybe<&2, M.LoadedMethod>:
  match result:
    case Fail{error}: None{}
    case Done{slot}: invokespecial_method(vm, owner, M.slot_bits(slot), name, descriptor)

def handle_direct_special_candidate(vm: M.VM, entry: M.HeapEntry, owner: U32, name: U32, descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  handle_direct_special_slot(vm, owner, name, descriptor, handle_value_binding(entry, 3))

def handle_direct_method_candidate(+vm: M.VM, entry: M.HeapEntry, kind: U32, owner: U32, owner_name: U32, name: U32, descriptor: U32, args: +List<M.Slot>) -> Maybe<&2, M.LoadedMethod>:
  match kind:
    case 5: handle_virtual_method(vm, owner_name, name, descriptor, args)
    case 9: handle_virtual_method(vm, owner_name, name, descriptor, args)
    case 7: handle_direct_special_candidate(vm, entry, owner, name, descriptor)
    case _: find_method(S.classes(vm), S.methods(vm), owner_name, name, descriptor)

def handle_direct_static_method(+vm: M.VM, +caller: M.Frame, +method: M.LoadedMethod, kind: U32, name: U32, descriptor: U32, +entry: M.HeapEntry, args: +List<M.Slot>, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    checked : Unit <- S.check(U32.is_ne(U32.and(M.loaded_method_flags(method), 8), 0), "IncompatibleClassChangeError")
    result : M.VM <- handle_class_init(vm, caller, kind, M.loaded_method_owner(method), name, descriptor, M.loaded_method_id(method), entry, args, target, requested, max)
    return result

def handle_direct_instance_method(+vm: M.VM, +caller: M.Frame, +method: M.LoadedMethod, args: +List<M.Slot>, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    checked : Unit <- S.check(U32.is_eq(U32.and(M.loaded_method_flags(method), 8), 0), "IncompatibleClassChangeError")
    result : M.VM <- handle_method_found(Some{method}, vm, caller, args, target, requested, max)
    return result

# invokespecial handles (findSpecial, unreflectSpecial, unreflect of a private
# method) run the selected body; they never re-dispatch on a proxy receiver.
@unsafe def handle_direct_special_method(+vm: M.VM, +caller: M.Frame, +method: M.LoadedMethod, args: +List<M.Slot>, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    checked : Unit <- S.check(U32.is_eq(U32.and(M.loaded_method_flags(method), 8), 0), "IncompatibleClassChangeError")
    abstract : Unit <- S.check(U32.is_eq(U32.and(M.loaded_method_flags(method), 1024), 0), "java/lang/AbstractMethodError")
    vm2 : M.VM = handle_boundary_push(vm, target, requested)
    return handle_frame_push_exact(vm2, method, args, caller)

def handle_direct_method_selected(+vm: M.VM, +caller: M.Frame, method: M.LoadedMethod, kind: U32, owner: U32, name: U32, descriptor: U32, +entry: M.HeapEntry, args: +List<M.Slot>, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  match kind:
    case 7: handle_direct_special_method(vm, caller, method, args, target, requested, max)
    case 8: handle_class_init(vm, caller, kind, owner, name, descriptor, M.loaded_method_id(method), entry, args, target, requested, max)
    case 6: handle_direct_static_method(vm, caller, method, kind, name, descriptor, entry, args, target, requested, max)
    case _: handle_direct_instance_method(vm, caller, method, args, target, requested, max)

def handle_direct_method_lookup(+vm: M.VM, +caller: M.Frame, +entry: M.HeapEntry, +args: +List<M.Slot>, +kind: U32, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    owner_slot : M.Slot <- handle_value_binding(entry, 0)
    name_slot : M.Slot <- handle_value_binding(entry, 1)
    desc_slot : M.Slot <- handle_value_binding(entry, 2)
    +owner : U32 = M.slot_bits(owner_slot)
    +name : U32 = M.slot_bits(name_slot)
    +method_desc : U32 = M.slot_bits(desc_slot)
    owner_class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), owner), "NoClassDefFoundError")
    owner_name : U32 = M.loaded_class_name(owner_class)
    found : Maybe<&2, M.LoadedMethod> = handle_direct_method_candidate(vm, entry, kind, owner, owner_name, name, method_desc, args)
    method : M.LoadedMethod <- S.require(M.LoadedMethod, found, "NoSuchMethodError")
    result : M.VM <- handle_direct_method_selected(vm, caller, method, kind, owner, name, method_desc, entry, args, target, requested, max)
    return result

def handle_direct_method(+vm: M.VM, +caller: M.Frame, +entry: M.HeapEntry, args: +List<M.Slot>, kind: U32, target: String, requested: String, max: U32) -> Result<&2, &2, String, M.VM>:
  match kind:
    case 1: handle_field_invoke(vm, caller, entry, args, kind, requested, max)
    case 2: handle_static_field_init(vm, caller, entry, args, kind, target, requested, max)
    case 3: handle_field_invoke(vm, caller, entry, args, kind, requested, max)
    case 4: handle_static_field_init(vm, caller, entry, args, kind, target, requested, max)
    case _: handle_direct_method_lookup(vm, caller, entry, args, kind, target, requested, max)

type HandleInsertState is Data:
  HandleInsertState{position: U32, args: +List<M.Slot>, inserted: +List<M.Slot>}


@unsafe def insert_handle_values_state(state: HandleInsertState) -> +List<M.Slot>:
  match state:
    case HandleInsertState{0, +args, +inserted}:
      M.append(M.Slot, inserted, args)
    case HandleInsertState{position, Con{head, rest}, +inserted}:
      Con{head, insert_handle_values_state(HandleInsertState{U32.sub(position, 1), rest, inserted})}
    case HandleInsertState{_, Nil{}, +inserted}:
      inserted
@unsafe def insert_handle_values(args: +List<M.Slot>, position: U32, inserted: +List<M.Slot>) -> +List<M.Slot>:
  insert_handle_values_state(HandleInsertState{position, args, inserted})

@unsafe def stored_handle_values(+entry: M.HeapEntry, +index: U32, count: U32, acc: +List<M.Slot>) -> Result<&2, &2, String, +List<M.Slot>>:
  match count:
    case 0: Done{M.reverse(M.Slot, acc)}
    case _:
      do Result<&2, &2, String, +List<M.Slot>>:
        value : M.Slot <- handle_value_binding(entry, U32.add(index, 9))
        tail : +List<M.Slot> <- stored_handle_values(entry, U32.add(index, 1), U32.sub(count, 1), Con{value, acc})
        return tail



type InvokeHandleWork is Data:
  InvokeHandleResolve{+vm: M.VM, +caller: M.Frame, reference: U32, +args: +List<M.Slot>, +descriptor: String, max: U32}
  InvokeHandleDispatch{+vm: M.VM, +caller: M.Frame, reference: U32, +entry: M.HeapEntry, +args: +List<M.Slot>, +descriptor: String, max: U32, mode: U32}
  InvokeHandleFailed{error: String}

def invoke_handle_adapted_work(result: Result<&2, &2, String, AdaptedArguments>, +caller: M.Frame, reference: U32, +target_descriptor: String, +call_descriptor: String, max: U32) -> InvokeHandleWork:
  match result:
    case Fail{error}: InvokeHandleFailed{error}
    case Done{AdaptedArguments{+updated, +values}}:
      wrapped : M.VM = handle_boundary_push(updated, target_descriptor, call_descriptor)
      InvokeHandleResolve{wrapped, caller, reference, values, target_descriptor, max}

# Handles that produce their result without a callee frame (constant, identity,
# lambda factory) still return through the boundary machinery, so pending
# asType adapters and host continuations at this depth are applied in order.
@unsafe def handle_immediate(+vm: M.VM, +caller: M.Frame, value: M.Slot) -> M.VM:
  +ready : M.VM = S.commit(vm, caller)
  boundary_intrinsic_return(ready, caller, boundary_result(ready, value, M.length(M.Frame, S.frames(ready)), host_cont(ready)))

@unsafe def handle_immediate_void(+vm: M.VM, +caller: M.Frame) -> M.VM:
  +ready : M.VM = S.commit(vm, caller)
  boundary_intrinsic_return(ready, caller, boundary_job(ready, BVoid{M.length(M.Frame, S.frames(ready)), host_cont(ready)}))

@unsafe def invoke_handle_single(+vm: M.VM, +caller: M.Frame, args: +List<M.Slot>, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case Con{value, Nil{}}: Done{handle_immediate(vm, caller, value)}
    case _: Fail{"java/lang/invoke/WrongMethodTypeException"}

@unsafe def invoke_lambda_factory_result(result: Result<&2, &2, String, O.Outcome>, +caller: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{+updated, Some{value}}}: Done{handle_immediate(updated, caller, value)}
    case Done{O.Returned{+updated, None{}}}: Done{handle_immediate_void(updated, caller)}
    case Done{O.ThrownRef{+updated, reference}}: Done{S.with_status(S.with_exception(updated, reference), 6)}
    case Done{O.ThrownName{_, error}}: Fail{error}
    case Done{O.Suspend{updated, effect}}: Done{S.commit(updated, caller)}
    case Done{O.Call{_, _, _}}: Fail{"InvalidState: lambda factory requested nested call"}

@unsafe def invoke_handle_work(work: InvokeHandleWork) -> Result<&2, &2, String, M.VM>:
  match work:
    case InvokeHandleFailed{error}: Fail{error}
    case InvokeHandleResolve{+vm, +caller, +reference, +args, +descriptor, max}:
      do Result<&2, &2, String, M.VM>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_method_handle()), "java/lang/IllegalArgumentException")
        mode_slot : M.Slot <- handle_value_binding(entry, 4)
        mode : U32 = M.slot_bits(mode_slot)
        result : M.VM <- invoke_handle_work(InvokeHandleDispatch{vm, caller, reference, entry, args, descriptor, max, mode})
        return result
    case InvokeHandleDispatch{+vm, +caller, _, +entry, +args, +descriptor, max, 1}:
      do Result<&2, &2, String, M.VM>:
        target_slot : M.Slot <- handle_value_binding(entry, 5)
        +target_reference : U32 = M.slot_bits(target_slot)
        +target_descriptor : String <- MH.handle_descriptor(vm, target_reference)
        adapted : Result<&2, &2, String, AdaptedArguments> = handle_adapt_arguments(vm, descriptor, target_descriptor, args)
        next : InvokeHandleWork = invoke_handle_adapted_work(adapted, caller, target_reference, target_descriptor, descriptor, max)
        result : M.VM <- invoke_handle_work(next)
        return result
    case InvokeHandleDispatch{+vm, +caller, _, +entry, +args, +descriptor, max, 2}:
      do Result<&2, &2, String, M.VM>:
        target_slot : M.Slot <- handle_value_binding(entry, 5)
        bound_slot : M.Slot <- handle_value_binding(entry, 6)
        +target_reference : U32 = M.slot_bits(target_slot)
        +target_descriptor : String <- MH.handle_descriptor(vm, target_reference)
        wrapped : M.VM = handle_boundary_push(vm, target_descriptor, descriptor)
        result : M.VM <- invoke_handle_work(InvokeHandleResolve{wrapped, caller, target_reference, Con{bound_slot, args}, target_descriptor, max})
        return result
    case InvokeHandleDispatch{+vm, +caller, _, +entry, +args, +descriptor, max, 5}:
      do Result<&2, &2, String, M.VM>:
        site_slot : M.Slot <- handle_value_binding(entry, 5)
        site_entry : M.HeapEntry <- H.get(S.heap(vm), M.slot_bits(site_slot))
        target : M.Slot <- S.require(M.Slot, H.binding_find(L.entry_fields(site_entry), 0), "java/lang/BootstrapMethodError")
        +target_reference : U32 = M.slot_bits(target)
        checked : Unit <- S.check(U32.is_ne(target_reference, 0), "java/lang/BootstrapMethodError")
        +target_descriptor : String <- MH.handle_descriptor(vm, target_reference)
        checked : Unit <- S.check(String.eq(target_descriptor, descriptor), "java/lang/invoke/WrongMethodTypeException")
        result : M.VM <- invoke_handle_work(InvokeHandleResolve{vm, caller, target_reference, args, target_descriptor, max})
        return result
    case InvokeHandleDispatch{+vm, +caller, _, +entry, +args, +descriptor, max, 6}:
      do Result<&2, &2, String, M.VM>:
        target_slot : M.Slot <- handle_value_binding(entry, 5)
        position_slot : M.Slot <- handle_value_binding(entry, 6)
        count_slot : M.Slot <- handle_value_binding(entry, 7)
        +target_reference : U32 = M.slot_bits(target_slot)
        position : U32 = M.slot_bits(position_slot)
        count : U32 = M.slot_bits(count_slot)
        +target_descriptor : String <- MH.handle_descriptor(vm, target_reference)
        values : +List<M.Slot> <- stored_handle_values(entry, 0, count, Nil{})
        combined : +List<M.Slot> = insert_handle_values(args, position, values)
        wrapped : M.VM = handle_boundary_push(vm, target_descriptor, descriptor)
        result : M.VM <- invoke_handle_work(InvokeHandleResolve{wrapped, caller, target_reference, combined, target_descriptor, max})
        return result
    case InvokeHandleDispatch{+vm, +caller, _, +entry, _, _, max, 7}:
      do Result<&2, &2, String, M.VM>:
        value_slot : M.Slot <- handle_value_binding(entry, 6)
        return handle_immediate(vm, caller, value_slot)
    case InvokeHandleDispatch{+vm, +caller, _, _, +args, _, max, 8}:
      invoke_handle_single(vm, caller, args, max)
    case InvokeHandleDispatch{+vm, +caller, reference, _, +args, _, max, 9}:
      invoke_lambda_factory_result(MH.lambda_factory_handle(vm, reference, args), caller, max)
    case InvokeHandleDispatch{+vm, +caller, _, +entry, +args, +descriptor, max, _}:
      handle_direct_method(vm, caller, entry, args, L.entry_element(entry), descriptor, descriptor, max)

@unsafe def invoke_handle_typed(+vm: M.VM, +caller: M.Frame, reference: U32, +args: +List<M.Slot>, +descriptor: String, max: U32) -> Result<&2, &2, String, M.VM>:
  invoke_handle_work(InvokeHandleResolve{vm, caller, reference, args, descriptor, max})

def invoke_handle_call_adapted(result: Result<&2, &2, String, AdaptedArguments>, +caller: M.Frame, reference: U32, +target_descriptor: String, call_descriptor: String, max: U32) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{AdaptedArguments{+updated, +values}}:
      wrapped : M.VM = handle_boundary_push(updated, target_descriptor, call_descriptor)
      invoke_handle_typed(wrapped, caller, reference, values, target_descriptor, max)

def invoke_handle_call_kind(+vm: M.VM, +caller: M.Frame, +reference: U32, args: +List<M.Slot>, +target_descriptor: String, +call_descriptor: String, same_descriptor: Bool, max: U32) -> Result<&2, &2, String, M.VM>:
  match same_descriptor:
    case True{}:
      invoke_handle_call_adapted(Done{AdaptedArguments{vm, args}}, caller, reference, target_descriptor, call_descriptor, max)
    case False{}:
      invoke_handle_call_adapted(handle_adapt_target(vm, reference, call_descriptor, target_descriptor, args), caller, reference, target_descriptor, call_descriptor, max)

def invoke_handle_call(+vm: M.VM, +caller: M.Frame, +reference: U32, args: +List<M.Slot>, +call_descriptor: String, exact: Bool, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    checked : Unit <- S.check(U32.is_eq(L.entry_kind(entry), H.kind_method_handle()), "java/lang/IllegalArgumentException")
    +target_descriptor : String <- MH.handle_method_descriptor(vm, entry)
    checked : Unit <- S.check(Bool.not(exact) || String.eq(target_descriptor, call_descriptor), "java/lang/invoke/WrongMethodTypeException")
    same_descriptor : Bool = String.eq(target_descriptor, call_descriptor)
    result : M.VM <- invoke_handle_call_kind(vm, caller, reference, args, target_descriptor, call_descriptor, same_descriptor, max)
    return result

type DynamicInfo is Data:
  DynamicInfo{name: String, descriptor: String, bootstrap: M.BootstrapMethod, pool: +List<M.Constant>}

type DynamicMaterialized is Data:
  DynamicMaterialized{vm: M.VM, value: M.Slot, descriptor: String}

type DynamicInputs is Data:
  DynamicInputs{vm: M.VM, reversedValues: +List<M.Slot>, descriptor: String}



def class_pool_owner(+pool: +List<M.Constant>, owner: U32, metadata_owner: U32) -> Result<&2, &2, String, +List<M.Constant>>:
  do Result<&2, &2, String, +List<M.Constant>>:
    checked : Unit <- S.check(U32.is_eq(owner, metadata_owner), "InvalidState: dynamic metadata owner")
    return pool

def class_pool_from_class(found: Maybe<&2, M.ClassMetadata>, owner: U32) -> Result<&2, &2, String, +List<M.Constant>>:
  match found:
    case None{}: Fail{"InvalidState: dynamic class metadata"}
    case Some{M.ClassMetadata{metadata_owner, flags, annotations, visible, +pool, signature, nesting, source}}:
      class_pool_owner(pool, owner, metadata_owner)

def class_pool_from_metadata(metadata: M.Metadata, +owner: U32) -> Result<&2, &2, String, +List<M.Constant>>:
  match metadata:
    case M.Metadata{classes, fields, methods}:
      class_pool_from_class(M.nth(M.ClassMetadata, classes, owner), owner)

def class_pool_for_owner(+vm: M.VM, owner: U32) -> Result<&2, &2, String, +List<M.Constant>>:
  class_pool_from_metadata(S.metadata(vm), owner)
def dynamic_info_bootstrap(found: Maybe<&2, M.BootstrapMethod>, name: String, descriptor: String, +pool: +List<M.Constant>) -> Result<&2, &2, String, DynamicInfo>:
  match found:
    case None{}: Fail{"java/lang/BootstrapMethodError"}
    case Some{bootstrap}: Done{DynamicInfo{name, descriptor, bootstrap, pool}}


def dynamic_info_class_metadata(+vm: M.VM, owner: U32, bootstrap_index: U32, +pool: +List<M.Constant>, name: String, descriptor: String) -> Result<&2, &2, String, DynamicInfo>:
  do Result<&2, &2, String, DynamicInfo>:
    class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), owner), "NoClassDefFoundError")
    result : DynamicInfo <- dynamic_info_bootstrap(M.nth(M.BootstrapMethod, M.loaded_class_bootstrap_methods(class), bootstrap_index), name, descriptor, pool)
    return result

def dynamic_info_name_type(vm: M.VM, owner: U32, bootstrap_index: U32, +pool: +List<M.Constant>, result: Result<&2, &2, String, CP.NameType>) -> Result<&2, &2, String, DynamicInfo>:
  match result:
    case Fail{error}: Fail{error}
    case Done{CP.NameType{name, descriptor}}:
      dynamic_info_class_metadata(vm, owner, bootstrap_index, pool, name, descriptor)

def dynamic_info_constant(vm: M.VM, owner: U32, +pool: +List<M.Constant>, value: M.Constant) -> Result<&2, &2, String, DynamicInfo>:
  match value:
    case M.PairIndex{18, bootstrap_index, name_type_index}:
      dynamic_info_name_type(vm, owner, bootstrap_index, pool, CP.name_type(pool, name_type_index))
    case _: Fail{"VmError.InvalidConstantPool: expected InvokeDynamic"}

def dynamic_info(+vm: M.VM, +owner: U32, constant: U32) -> Result<&2, &2, String, DynamicInfo>:
  do Result<&2, &2, String, DynamicInfo>:
    +pool : +List<M.Constant> <- class_pool_for_owner(vm, owner)
    value : M.Constant <- CP.get(pool, constant)
    result : DynamicInfo <- dynamic_info_constant(vm, owner, pool, value)
    return result

def dynamic_units_chars(chars: +List<Char>) -> +List<U32>:
  match chars:
    case Nil{}: Nil{}
    case Con{character, rest}: Con{Char.to_u32(character), dynamic_units_chars(rest)}

def dynamic_units(text: String) -> +List<U32>:
  dynamic_units_chars(String.to_list(text))

def dynamic_materialized_outcome(+vm: M.VM, descriptor: String, result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, DynamicMaterialized>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{updated, Some{value}}}: Done{DynamicMaterialized{updated, value, descriptor}}
    case Done{_}: Fail{"java/lang/BootstrapMethodError"}

def dynamic_class_name(name: String) -> String:
  match name:
    case "Z": "boolean"
    case "B": "byte"
    case "C": "char"
    case "S": "short"
    case "I": "int"
    case "J": "long"
    case "F": "float"
    case "D": "double"
    case "V": "void"
    case _: name



def dynamic_handle_constructor_access(kind: U32, +member: CP.Member) -> Result<&2, &2, String, Unit>:
  match kind:
    case 8: S.check(String.eq(CP.member_name(member), "<init>") && String.ends_with(CP.member_descriptor(member), ")V"), "NoSuchMethodError")
    case _: S.check(Bool.not(String.eq(CP.member_name(member), "<init>")), "NoSuchMethodError")

def dynamic_handle_method_candidate(+vm: M.VM, kind: U32, owner: U32, owner_name: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(kind, 8),
    own_method(S.methods(vm), owner, name, descriptor), find_method(S.classes(vm), S.methods(vm), owner_name, name, descriptor))

def dynamic_handle_field_access(+vm: M.VM, caller: U32, +kind: U32, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    +field : M.LoadedField <- S.require(M.LoadedField, H.resolve_field(S.classes(vm), S.fields(vm), owner, name, descriptor), "NoSuchFieldError")
    +flags : U32 = M.loaded_field_flags(field)
    is_static : Bool = U32.is_eq(kind, 2) || U32.is_eq(kind, 4)
    +has_static : Bool = U32.is_ne(U32.and(flags, 8), 0)
    checked : Unit <- S.check(Bool.pick(Bool, is_static, has_static, Bool.not(has_static)), "IncompatibleClassChangeError")
    checked : Unit <- S.check(L.member_accessible(vm, caller, M.loaded_field_owner(field), flags), "java/lang/IllegalAccessError")
    return Unit{}

def dynamic_handle_method_access(+vm: M.VM, caller: U32, +kind: U32, member: CP.Member, +owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    owner_class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), owner), "java/lang/NoClassDefFoundError")
    method_owner : U32 = M.loaded_class_name(owner_class)
    found : Maybe<&2, M.LoadedMethod> = dynamic_handle_method_candidate(vm, kind, owner, method_owner, name, descriptor)
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, found, "NoSuchMethodError")
    +flags : U32 = M.loaded_method_flags(method)
    is_static : Bool = U32.is_ne(U32.and(flags, 8), 0)
    checked : Unit <- S.check(Bool.pick(Bool, is_static, U32.is_eq(kind, 6), U32.is_ne(kind, 6)), "IncompatibleClassChangeError")
    checked : Unit <- S.check(L.member_accessible(vm, caller, M.loaded_method_owner(method), flags), "java/lang/IllegalAccessError")
    result : Unit <- dynamic_handle_constructor_access(kind, member)
    return result

def dynamic_handle_access_kind(+vm: M.VM, caller: U32, kind: U32, member: CP.Member, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, Unit>:
  match kind:
    case 1: dynamic_handle_field_access(vm, caller, kind, owner, name, descriptor)
    case 2: dynamic_handle_field_access(vm, caller, kind, owner, name, descriptor)
    case 3: dynamic_handle_field_access(vm, caller, kind, owner, name, descriptor)
    case 4: dynamic_handle_field_access(vm, caller, kind, owner, name, descriptor)
    case _: dynamic_handle_method_access(vm, caller, kind, member, owner, name, descriptor)

def dynamic_handle_access(+vm: M.VM, caller: U32, kind: U32, +member: CP.Member) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    owner_text : String = CP.member_owner(member)
    +owner : U32 = H.named_class(S.classes(vm), S.symbols(vm), owner_text)
    checked : Unit <- S.check(U32.is_ne(owner, 4294967295), "java/lang/NoClassDefFoundError")
    name : U32 = Sy.find(S.symbols(vm), CP.member_name(member))
    descriptor : U32 = Sy.find(S.symbols(vm), CP.member_descriptor(member))
    result : Unit <- dynamic_handle_access_kind(vm, caller, kind, member, owner, name, descriptor)
    return result
def dynamic_type_resolved(+vm: M.VM, value: M.JvmType) -> Bool:
  match value:
    case M.ObjectType{name}: U32.is_ne(H.named_class(S.classes(vm), S.symbols(vm), name), 4294967295)
    case M.ArrayType{element}: dynamic_type_resolved(vm, element)
    case _: True{}

@unsafe def dynamic_types_resolved(+vm: M.VM, values: +List<M.JvmType>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{value, rest}: dynamic_type_resolved(vm, value) && dynamic_types_resolved(vm, rest)

def dynamic_method_type_resolved_result(+vm: M.VM, result: Result<&2, &2, String, M.Descriptor>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{+parsed}: dynamic_types_resolved(vm, D.parameter_types(parsed)) && dynamic_type_resolved(vm, D.result_type(parsed))

def dynamic_method_type_resolved(+vm: M.VM, descriptor: String) -> Bool:
  dynamic_method_type_resolved_result(vm, D.parse_method(descriptor))


def dynamic_method_handle_alloc(+vm: M.VM, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, DynamicMaterialized>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}:
      Done{DynamicMaterialized{updated, M.Slot{3, reference}, "Ljava/lang/invoke/MethodHandle;"}}

def dynamic_method_handle_value(+vm: M.VM, +pool: +List<M.Constant>, reference: U32, +kind: U32, +caller_owner: U32) -> Result<&2, &2, String, DynamicMaterialized>:
  do Result<&2, &2, String, DynamicMaterialized>:
    +member : CP.Member <- CP.member(pool, reference)
    checked : Unit <- dynamic_handle_access(vm, caller_owner, kind, member)
    owner : U32 = H.named_class(S.classes(vm), S.symbols(vm), CP.member_owner(member))
    name : U32 = Sy.find(S.symbols(vm), CP.member_name(member))
    descriptor : U32 = Sy.find(S.symbols(vm), CP.member_descriptor(member))
    special : U32 = Bool.pick(U32, U32.is_eq(kind, 7), caller_owner, 4294967295)
    class : U32 = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/invoke/MethodHandle")
    handle_entry : M.HeapEntry = MH.handle_entry(class, kind, owner, name, descriptor, special)
    result : DynamicMaterialized <- dynamic_method_handle_alloc(vm, H.allocate(vm, handle_entry))
    return result
def dynamic_materialize(+vm: M.VM, +pool: +List<M.Constant>, +argument: M.BootstrapArgument, caller_owner: U32) -> Result<&2, &2, String, DynamicMaterialized>:
  match argument:
    case M.BootstrapArgument{argumentIndex, constantIndex, tag, value}:
      match value:
        case M.Number{3, bits}: Done{DynamicMaterialized{vm, M.Slot{1, bits}, "I"}}
        case M.Number{4, bits}: Done{DynamicMaterialized{vm, M.Slot{2, bits}, "F"}}
        case M.PairIndex{5, high, low}: Done{DynamicMaterialized{vm, M.Wide{4, high, low}, "J"}}
        case M.PairIndex{6, high, low}: Done{DynamicMaterialized{vm, M.Wide{5, high, low}, "D"}}
        case M.Index{8, string_index}:
          do Result<&2, &2, String, DynamicMaterialized>:
            text : String <- CP.string(pool, constantIndex)
            result : DynamicMaterialized <- dynamic_materialized_outcome(vm, "Ljava/lang/String;", L.intern_or_alloc(vm, dynamic_units(text)))
            return result
        case M.Index{7, class_index}:
          do Result<&2, &2, String, DynamicMaterialized>:
            class_text : String <- CP.class_name(pool, constantIndex)
            +target : U32 = H.named_class(S.classes(vm), S.symbols(vm), dynamic_class_name(class_text))
            checked : Unit <- S.check(U32.is_ne(target, 4294967295), "java/lang/NoClassDefFoundError")
            result : DynamicMaterialized <- dynamic_materialized_outcome(vm, "Ljava/lang/Class;", L.class_mirror_out(vm, target))
            return result
        case M.Index{16, descriptor_index}:
          do Result<&2, &2, String, DynamicMaterialized>:
            +descriptor : String <- CP.utf(pool, descriptor_index)
            checked : Unit <- S.check(dynamic_method_type_resolved(vm, descriptor), "java/lang/NoClassDefFoundError")
            result : DynamicMaterialized <- dynamic_materialized_outcome(vm, "Ljava/lang/invoke/MethodType;", MH.alloc_type(vm, descriptor))
            return result
        case M.PairIndex{15, kind, reference}:
          dynamic_method_handle_value(vm, pool, reference, kind, caller_owner)
        case _: Fail{"java/lang/BootstrapMethodError"}

def bootstrap_arguments(value: M.BootstrapMethod) -> +List<M.BootstrapArgument>:
  match value:
    case M.BootstrapMethod{index, methodRef, handleKind, handleReference, +arguments}: arguments

type DynamicArgumentWork is Data:
  DynamicArgumentGo{+vm: M.VM, +pool: +List<M.Constant>, +arguments: +List<M.BootstrapArgument>, +caller_owner: U32, +acc: +List<M.Slot>, +descriptor: String}
  DynamicArgumentFailed{error: String}

def dynamic_argument_after(result: Result<&2, &2, String, DynamicMaterialized>, +pool: +List<M.Constant>, +rest: +List<M.BootstrapArgument>, +caller_owner: U32, +acc: +List<M.Slot>, +descriptor: String) -> DynamicArgumentWork:
  match result:
    case Fail{error}: DynamicArgumentFailed{error}
    case Done{DynamicMaterialized{+updated, value, type_descriptor}}:
      DynamicArgumentGo{updated, pool, rest, caller_owner, Con{value, acc}, descriptor ++ type_descriptor}

@unsafe def dynamic_argument_work(work: DynamicArgumentWork) -> Result<&2, &2, String, DynamicInputs>:
  match work:
    case DynamicArgumentFailed{error}: Fail{error}
    case DynamicArgumentGo{+vm, +pool, Nil{}, +caller_owner, +acc, +descriptor}:
      Done{DynamicInputs{vm, M.reverse(M.Slot, acc), descriptor}}
    case DynamicArgumentGo{+vm, +pool, Con{argument, rest}, +caller_owner, +acc, +descriptor}:
      dynamic_argument_work(dynamic_argument_after(dynamic_materialize(vm, pool, argument, caller_owner), pool, rest, caller_owner, acc, descriptor))

@unsafe def dynamic_arguments_go(+vm: M.VM, +pool: +List<M.Constant>, +arguments: +List<M.BootstrapArgument>, +caller_owner: U32, +acc: +List<M.Slot>, +descriptor: String) -> Result<&2, &2, String, DynamicInputs>:
  dynamic_argument_work(DynamicArgumentGo{vm, pool, arguments, caller_owner, acc, descriptor})


def dynamic_inputs_type_result(result: Result<&2, &2, String, DynamicMaterialized>, caller_owner: U32, bootstrap: M.BootstrapMethod, +pool: +List<M.Constant>, lookup: M.Slot, lookup_descriptor: String, name_slot: M.Slot, name_descriptor: String) -> Result<&2, &2, String, DynamicInputs>:
  match result:
    case Fail{error}: Fail{error}
    case Done{DynamicMaterialized{+updated, type_slot, type_descriptor}}:
      first_values : +List<M.Slot> = [type_slot, name_slot, lookup]
      prefix : String = lookup_descriptor ++ name_descriptor ++ type_descriptor
      dynamic_arguments_go(updated, pool, bootstrap_arguments(bootstrap), caller_owner, first_values, prefix)

def dynamic_inputs_type(+vm: M.VM, caller: M.Frame, caller_owner: U32, descriptor: String, bootstrap: M.BootstrapMethod, +pool: +List<M.Constant>, lookup: M.Slot, lookup_descriptor: String, name_slot: M.Slot, name_descriptor: String) -> Result<&2, &2, String, DynamicInputs>:
  dynamic_inputs_type_result(dynamic_materialized_outcome(vm, "Ljava/lang/invoke/MethodType;", MH.alloc_type(vm, descriptor)), caller_owner, bootstrap, pool, lookup, lookup_descriptor, name_slot, name_descriptor)

def dynamic_inputs_name_result(result: Result<&2, &2, String, DynamicMaterialized>, caller: M.Frame, caller_owner: U32, descriptor: String, bootstrap: M.BootstrapMethod, +pool: +List<M.Constant>, lookup: M.Slot, lookup_descriptor: String) -> Result<&2, &2, String, DynamicInputs>:
  match result:
    case Fail{error}: Fail{error}
    case Done{DynamicMaterialized{+updated, name_slot, name_descriptor}}:
      dynamic_inputs_type(updated, caller, caller_owner, descriptor, bootstrap, pool, lookup, lookup_descriptor, name_slot, name_descriptor)

def dynamic_inputs_name(+vm: M.VM, caller: M.Frame, caller_owner: U32, name: String, descriptor: String, bootstrap: M.BootstrapMethod, +pool: +List<M.Constant>, lookup: M.Slot, lookup_descriptor: String) -> Result<&2, &2, String, DynamicInputs>:
  dynamic_inputs_name_result(dynamic_materialized_outcome(vm, "Ljava/lang/String;", L.intern_or_alloc(vm, dynamic_units(name))), caller, caller_owner, descriptor, bootstrap, pool, lookup, lookup_descriptor)

def dynamic_inputs_lookup_alloc(caller: M.Frame, caller_owner: U32, name: String, descriptor: String, bootstrap: M.BootstrapMethod, +pool: +List<M.Constant>, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, DynamicInputs>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}:
      dynamic_inputs_name(updated, caller, caller_owner, name, descriptor, bootstrap, pool, M.Slot{3, reference}, "Ljava/lang/invoke/MethodHandles$Lookup;")

def dynamic_inputs_lookup(+vm: M.VM, +caller: M.Frame, name: String, descriptor: String, bootstrap: M.BootstrapMethod, +pool: +List<M.Constant>) -> Result<&2, &2, String, DynamicInputs>:
  do Result<&2, &2, String, DynamicInputs>:
    lookup_class : U32 = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/invoke/MethodHandles$Lookup")
    +caller_owner : U32 <- handle_caller_owner(vm, caller)
    result : DynamicInputs <- dynamic_inputs_lookup_alloc(caller, caller_owner, name, descriptor, bootstrap, pool, H.allocate(vm, MH.lookup_entry(lookup_class, caller_owner, 15)))
    return result

def dynamic_inputs(+vm: M.VM, +caller: M.Frame, owner: U32, info: DynamicInfo) -> Result<&2, &2, String, DynamicInputs>:
  match info:
    case DynamicInfo{name, descriptor, bootstrap, +pool}:
      dynamic_inputs_lookup(vm, caller, name, descriptor, bootstrap, pool)


def dynamic_target_method_entry(+vm: M.VM, +kind: U32, +owner: U32, name: U32, descriptor: U32, flags: U32) -> M.HeapEntry:
  class : U32 = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/invoke/MethodHandle")
  special : U32 = Bool.pick(U32, U32.is_eq(kind, 7), owner, 4294967295)
  +handle : M.HeapEntry = MH.handle_entry(class, kind, owner, name, descriptor, special)
  varargs : Bool = U32.is_ne(U32.and(flags, 128), 0)
  fields : +List<M.Binding> = H.binding_set(L.entry_fields(handle), 4294967295, M.Slot{1, Bool.pick(U32, varargs, 1, 0)})
  M.HeapEntry{H.entry_class(handle), L.entry_kind(handle), L.entry_element(handle), fields, Nil{}, Nil{}}

def dynamic_target_method_candidate(+vm: M.VM, kind: U32, owner: U32, +name: U32, +descriptor: U32, owner_name: U32) -> Maybe<&2, M.LoadedMethod>:
  Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(kind, 8),
    own_method(S.methods(vm), owner, name, descriptor), find_method(S.classes(vm), S.methods(vm), owner_name, name, descriptor))

def dynamic_target_method_member(+vm: M.VM, +pool: +List<M.Constant>, reference: U32, +kind: U32, caller: U32) -> Result<&2, &2, String, M.HeapEntry>:
  do Result<&2, &2, String, M.HeapEntry>:
    +member : CP.Member <- CP.member(pool, reference)
    owner_text : String = CP.member_owner(member)
    +owner : U32 = H.named_class(S.classes(vm), S.symbols(vm), owner_text)
    checked : Unit <- S.check(U32.is_ne(owner, 4294967295), "java/lang/NoClassDefFoundError")
    owner_class : M.LoadedClass <- S.require(M.LoadedClass, M.nth(M.LoadedClass, S.classes(vm), owner), "java/lang/NoClassDefFoundError")
    +name : U32 = Sy.find(S.symbols(vm), CP.member_name(member))
    +descriptor : U32 = Sy.find(S.symbols(vm), CP.member_descriptor(member))
    owner_name : U32 = M.loaded_class_name(owner_class)
    found : Maybe<&2, M.LoadedMethod> = dynamic_target_method_candidate(vm, kind, owner, name, descriptor, owner_name)
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, found, "NoSuchMethodError")
    +flags : U32 = M.loaded_method_flags(method)
    checked : Unit <- S.check(U32.is_eq(kind, 6) || U32.is_eq(kind, 8), "java/lang/BootstrapMethodError")
    checked : Unit <- S.check(Bool.pick(Bool, U32.is_ne(U32.and(flags, 8), 0), U32.is_eq(kind, 6), U32.is_ne(kind, 6)), "java/lang/IncompatibleClassChangeError")
    checked : Unit <- S.check(L.member_accessible(vm, caller, M.loaded_method_owner(method), flags), "java/lang/IllegalAccessError")
    result : M.HeapEntry = dynamic_target_method_entry(vm, kind, owner, name, descriptor, flags)
    return result

def dynamic_target_method(+vm: M.VM, +pool: +List<M.Constant>, bootstrap: M.BootstrapMethod, caller: U32) -> Result<&2, &2, String, M.HeapEntry>:
  match bootstrap:
    case M.BootstrapMethod{index, methodRef, handleKind, handleReference, arguments}:
      dynamic_target_method_member(vm, pool, handleReference, handleKind, caller)


def dynamic_bootstrap_adapted(result: Result<&2, &2, String, AdaptedArguments>, +caller: M.Frame, owner: U32, constant: U32, dynamic_args: +List<M.Slot>, max: U32, reference: U32, target_descriptor: String) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{AdaptedArguments{+ready, +arguments}}:
      depth : U32 = M.length(M.Frame, S.frames(ready))
      method : U32 = S.method_id(caller)
      pc : U32 = S.pc(caller)
      cont : M.Cont = M.DynamicBootstrap{depth, method, pc, owner, constant, dynamic_args}
      linked : M.VM = S.with_cont(ready, Con{cont, host_cont(ready)})
      invoke_handle_call(linked, caller, reference, arguments, target_descriptor, True{}, max)

def dynamic_bootstrap_adapt(+vm: M.VM, +caller: M.Frame, owner: U32, constant: U32, +dynamic_args: +List<M.Slot>, max: U32, +reference: U32, +values: +List<M.Slot>, source_parameters: String) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +target_descriptor : String <- MH.handle_descriptor(vm, reference)
    source_descriptor : String = "(" ++ source_parameters ++ ")V"
    result : M.VM <- dynamic_bootstrap_adapted(handle_adapt_target(vm, reference, source_descriptor, target_descriptor, values), caller, owner, constant, dynamic_args, max, reference, target_descriptor)
    return result

def dynamic_bootstrap_alloc(+caller: M.Frame, owner: U32, constant: U32, dynamic_args: +List<M.Slot>, max: U32, +values: +List<M.Slot>, source_parameters: String, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, M.VM>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}:
      dynamic_bootstrap_adapt(updated, caller, owner, constant, dynamic_args, max, reference, values, source_parameters)

def dynamic_bootstrap_target(+vm: M.VM, +caller: M.Frame, owner: U32, constant: U32, +dynamic_args: +List<M.Slot>, max: U32, bootstrap: M.BootstrapMethod, +pool: +List<M.Constant>, +values: +List<M.Slot>, source_parameters: String) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    caller_owner : U32 <- handle_caller_owner(vm, caller)
    target_entry : M.HeapEntry <- dynamic_target_method(vm, pool, bootstrap, caller_owner)
    result : M.VM <- dynamic_bootstrap_alloc(caller, owner, constant, dynamic_args, max, values, source_parameters, H.allocate(vm, target_entry))
    return result

def dynamic_bootstrap_inputs(+caller: M.Frame, owner: U32, constant: U32, +dynamic_args: +List<M.Slot>, max: U32, bootstrap: M.BootstrapMethod, +pool: +List<M.Constant>, inputs: DynamicInputs) -> Result<&2, &2, String, M.VM>:
  match inputs:
    case DynamicInputs{+vm, +values, source_parameters}:
      dynamic_bootstrap_target(vm, caller, owner, constant, dynamic_args, max, bootstrap, pool, values, source_parameters)

def dynamic_bootstrap_frame(+caller: M.Frame, owner: U32, constant: U32, +dynamic_args: +List<M.Slot>, max: U32, info: DynamicInfo, inputs: DynamicInputs) -> Result<&2, &2, String, M.VM>:
  match info:
    case DynamicInfo{name, descriptor, bootstrap, +pool}:
      dynamic_bootstrap_inputs(caller, owner, constant, dynamic_args, max, bootstrap, pool, inputs)
def dynamic_bme_class(+vm: M.VM) -> U32:
  H.named_class(S.classes(vm), S.symbols(vm), "java/lang/BootstrapMethodError")


def dynamic_callsite_descriptor_valid(result: Result<&2, &2, String, String>, descriptor: String) -> Bool:
  match result:
    case Done{actual}: String.eq(actual, descriptor)
    case Fail{_}: False{}

def dynamic_callsite_valid_type(+vm: M.VM, entry: M.HeapEntry, descriptor: String, is_callsite: Bool) -> Bool:
  match is_callsite:
    case False{}: False{}
    case True{}: dynamic_callsite_descriptor_valid(MH.callsite_descriptor(vm, entry), descriptor)

def dynamic_callsite_valid_entry(+vm: M.VM, descriptor: String, result: Result<&2, &2, String, M.HeapEntry>) -> Bool:
  match result:
    case Fail{_}: False{}
    case Done{+entry}:
      callsite_class : U32 = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/invoke/CallSite")
      is_callsite : Bool = H.assignable(S.classes(vm), S.symbols(vm), H.entry_class(entry), callsite_class) && U32.is_eq(L.entry_kind(entry), H.kind_call_site())
      dynamic_callsite_valid_type(vm, entry, descriptor, is_callsite)

def dynamic_callsite_valid_null(+vm: M.VM, +reference: U32, descriptor: String, is_null: Bool) -> Bool:
  match is_null:
    case True{}: False{}
    case False{}: dynamic_callsite_valid_entry(vm, descriptor, H.get(S.heap(vm), reference))

def dynamic_callsite_valid(+vm: M.VM, +reference: U32, descriptor: String) -> Bool:
  dynamic_callsite_valid_null(vm, reference, descriptor, U32.is_eq(reference, 0))

def dynamic_callsite_target_slot(binding: Maybe<&2, M.Slot>) -> Maybe<&2, U32>:
  match binding:
    case Some{M.Slot{3, +target}}:
      Bool.pick(Maybe<&2, U32>, U32.is_ne(target, 0), Some{target}, None{})
    case _: None{}

def dynamic_callsite_target_entry(result: Result<&2, &2, String, M.HeapEntry>) -> Maybe<&2, U32>:
  match result:
    case Fail{_}: None{}
    case Done{entry}: dynamic_callsite_target_slot(H.binding_find(L.entry_fields(entry), 0))

def dynamic_callsite_target(+vm: M.VM, reference: U32) -> Maybe<&2, U32>:
  dynamic_callsite_target_entry(H.get(S.heap(vm), reference))

def dynamic_linked_target(+vm: M.VM, +caller: M.Frame, +site: M.DynamicSite, +args: +List<M.Slot>, descriptor: String, max: U32) -> Result<&2, &2, String, M.VM>:
  match site:
    case M.DynamicSite{method, pc, owner, constant, 1, callsite, failure}:
      do Result<&2, &2, String, M.VM>:
        target : U32 <- S.require(U32, dynamic_callsite_target(vm, callsite), "java/lang/BootstrapMethodError")
        result : M.VM <- invoke_handle_call(vm, caller, target, args, descriptor, True{}, max)
        return result
    case _: Fail{"InvalidState: linked dynamic site"}

def dynamic_failure_entry(entry: M.HeapEntry, cause: U32) -> M.HeapEntry:
  match entry:
    case M.HeapEntry{class, kind, element, +fields, values, chars}:
      M.HeapEntry{class, kind, element, H.binding_set(fields, 1, M.Slot{3, cause}), values, chars}


def dynamic_failure_outcome_alloc(+vm: M.VM, owner: U32, method: U32, pc: U32, constant: U32, +rest: +List<M.Cont>, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, +reference}}:
      site : M.DynamicSite = M.DynamicSite{method, pc, owner, constant, 2, 0, reference}
      failed : M.VM = S.with_cont(S.publish_dynamic_site(updated, site), rest)
      Done{O.ThrownRef{failed, reference}}

def dynamic_failure_outcome(+vm: M.VM, owner: U32, method: U32, pc: U32, constant: U32, +rest: +List<M.Cont>) -> Result<&2, &2, String, O.Outcome>:
  dynamic_failure_outcome_alloc(vm, owner, method, pc, constant, rest, H.allocate(vm, dynamic_failure_entry(H.throwable_entry(dynamic_bme_class(vm)), S.exception(vm))))

type DynamicFailure is Data:
  DynamicFailure{method: U32, pc: U32, owner: U32, constant: U32, rest: +List<M.Cont>}


type DynamicFailureWork is Data:
  DynamicFailureSearch{+conts: +List<M.Cont>, depth: U32, +prefix: +List<M.Cont>}
  DynamicFailureInspect{cont: M.Cont, +rest: +List<M.Cont>, +depth: U32, +prefix: +List<M.Cont>}
  DynamicFailureCompare{same_depth: Bool, +cont: M.Cont, +rest: +List<M.Cont>, +depth: U32, +prefix: +List<M.Cont>, method: U32, pc: U32, owner: U32, constant: U32}

@unsafe def dynamic_failure_work(work: DynamicFailureWork) -> Maybe<&2, DynamicFailure>:
  match work:
    case DynamicFailureSearch{Nil{}, depth, +prefix}: None{}
    case DynamicFailureSearch{Con{cont, rest}, depth, +prefix}:
      dynamic_failure_work(DynamicFailureInspect{cont, rest, depth, prefix})
    case DynamicFailureInspect{M.DynamicBootstrap{+expected, +method, +pc, +owner, +constant, +args}, +rest, +depth, +prefix}:
      dynamic_failure_work(DynamicFailureCompare{U32.is_eq(expected, depth), M.DynamicBootstrap{expected, method, pc, owner, constant, args}, rest, depth, prefix, method, pc, owner, constant})
    case DynamicFailureInspect{cont, +rest, +depth, +prefix}:
      dynamic_failure_work(DynamicFailureSearch{rest, depth, Con{cont, prefix}})
    case DynamicFailureCompare{True{}, _, +rest, _, +prefix, method, pc, owner, constant}:
      Some{DynamicFailure{method, pc, owner, constant, M.append(M.Cont, M.reverse(M.Cont, prefix), rest)}}
    case DynamicFailureCompare{False{}, +cont, +rest, +depth, +prefix, _, _, _, _}:
      dynamic_failure_work(DynamicFailureSearch{rest, depth, Con{cont, prefix}})

def dynamic_failure_conts(+conts: +List<M.Cont>, depth: U32, +prefix: +List<M.Cont>) -> Maybe<&2, DynamicFailure>:
  dynamic_failure_work(DynamicFailureSearch{conts, depth, prefix})


def dynamic_exception_wrap_alloc(+vm: M.VM, method: U32, pc: U32, owner: U32, constant: U32, +rest: +List<M.Cont>, allocation: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match allocation:
    case Fail{error}: S.fail(vm, error)
    case Done{H.Allocation{updated, +reference}}:
      site : M.DynamicSite = M.DynamicSite{method, pc, owner, constant, 2, 0, reference}
      S.with_cont(S.with_exception(S.publish_dynamic_site(updated, site), reference), rest)

def dynamic_exception_wrap_message(+vm: M.VM, method: U32, pc: U32, owner: U32, constant: U32, +rest: +List<M.Cont>, message: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match message:
    case Fail{error}: S.fail(vm, error)
    case Done{H.Allocation{+updated, text}}:
      dynamic_exception_wrap_alloc(updated, method, pc, owner, constant, rest, H.allocate(updated, dynamic_failure_entry(throwable_with_message(dynamic_bme_class(updated), text), S.exception(updated))))

# Matches the JDK: a bootstrap method that throws is wrapped in a
# BootstrapMethodError whose cause is the original throwable.
def dynamic_exception_wrap_result(+vm: M.VM, failure: Maybe<&2, DynamicFailure>) -> M.VM:
  match failure:
    case None{}: vm
    case Some{DynamicFailure{method, pc, owner, constant, +rest}}:
      dynamic_exception_wrap_message(vm, method, pc, owner, constant, rest, H.allocate(vm, H.string_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/String"), L.units_from_string("bootstrap method initialization exception"))))

def dynamic_exception_wrap(+vm: M.VM) -> M.VM:
  dynamic_exception_wrap_result(vm, dynamic_failure_conts(host_cont(vm), M.length(M.Frame, S.frames(vm)), Nil{}))


def dynamic_failure_step_alloc(+vm: M.VM, +frame: M.Frame, owner: U32, constant: U32, allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, M.VM>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, +reference}}:
      method : U32 = S.method_id(frame)
      pc : U32 = S.pc(frame)
      site : M.DynamicSite = M.DynamicSite{method, pc, owner, constant, 2, 0, reference}
      failed : M.VM = S.publish_dynamic_site(updated, site)
      thrown : M.VM = S.with_status(S.with_exception(S.commit(failed, frame), reference), 6)
      Done{thrown}

def dynamic_failure_message_entry(+vm: M.VM, message: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, H.Allocation>:
  match message:
    case Fail{error}: H.allocate(vm, dynamic_failure_entry(H.throwable_entry(dynamic_bme_class(vm)), 0))
    case Done{H.Allocation{+updated, reference}}:
      H.allocate(updated, entry_with_message(dynamic_failure_entry(H.throwable_entry(dynamic_bme_class(updated)), 0), reference))

# Linkage failures raise BootstrapMethodError whose message records the cause.
def dynamic_failure_step(+vm: M.VM, +frame: M.Frame, owner: U32, constant: U32, error: String) -> Result<&2, &2, String, M.VM>:
  dynamic_failure_step_alloc(vm, frame, owner, constant, dynamic_failure_message_entry(vm, H.allocate(vm, H.string_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/String"), L.units_from_string(error)))))



def dynamic_bootstrap_invoked(+vm: M.VM, owner: U32, method: U32, pc: U32, constant: U32, +rest: +List<M.Cont>, invoked: Result<&2, &2, String, M.VM>) -> Result<&2, &2, String, O.Outcome>:
  match invoked:
    case Done{invoked}: Done{O.Suspend{invoked, M.Idle{}}}
    # The site is linked; a Java exception from invoking its target propagates as-is.
    case Fail{+error}: Bool.pick(Result<&2, &2, String, O.Outcome>, java_fault(error), Done{O.ThrownName{vm, error}}, Fail{error})

def dynamic_bootstrap_method(+vm: M.VM, +call_vm: M.VM, +site_caller: M.Frame, target: U32, method: U32, pc: U32, owner: U32, constant: U32, +args: +List<M.Slot>, +rest: +List<M.Cont>, descriptor: String, method_result: Result<&2, &2, String, M.LoadedMethod>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    method_value : M.LoadedMethod <- method_result
    outcome : O.Outcome <- dynamic_bootstrap_invoked(vm, owner, method, pc, constant, rest, invoke_handle_call(call_vm, site_caller, target, args, descriptor, True{}, method_max_stack(method_value)))
    return outcome

# A bytecode bootstrap leaves its finished frame above the call site (depth + 1
# frames); an intrinsic bootstrap such as LambdaMetafactory leaves none.
def dynamic_bootstrap_frames(+vm: M.VM, +ready: M.VM, target: U32, +method: U32, +pc: U32, owner: U32, constant: U32, +args: +List<M.Slot>, +rest: +List<M.Cont>, descriptor: String, hasBootstrapFrame: Bool, frames: +List<M.Frame>) -> Result<&2, &2, String, O.Outcome>:
  match hasBootstrapFrame frames:
    case True{} Con{bootstrap_frame, Con{caller_frame, callers}}:
      +site_caller : M.Frame = S.frame_pc(caller_frame, pc)
      call_vm : M.VM = S.with_frames(ready, Con{site_caller, callers})
      dynamic_bootstrap_method(vm, call_vm, site_caller, target, method, pc, owner, constant, args, rest, descriptor, S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), method), "InvalidState: dynamic caller method"))
    case False{} Con{caller_frame, callers}:
      +site_caller : M.Frame = S.frame_pc(caller_frame, pc)
      call_vm : M.VM = S.with_frames(ready, Con{site_caller, callers})
      dynamic_bootstrap_method(vm, call_vm, site_caller, target, method, pc, owner, constant, args, rest, descriptor, S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), method), "InvalidState: dynamic caller method"))
    case _ _: Fail{"InvalidState: dynamic bootstrap frames"}

def dynamic_bootstrap_callsite_target(+vm: M.VM, callsite: U32, +method: U32, +pc: U32, +owner: U32, +constant: U32, +args: +List<M.Slot>, +rest: +List<M.Cont>, descriptor: String, +depth: U32, target: Maybe<&2, U32>) -> Result<&2, &2, String, O.Outcome>:
  match target:
    case None{}: dynamic_failure_outcome(vm, owner, method, pc, constant, rest)
    case Some{target}:
      updated : M.VM = S.publish_dynamic_site(vm, M.DynamicSite{method, pc, owner, constant, 1, callsite, 0})
      +ready : M.VM = S.with_cont(updated, rest)
      dynamic_bootstrap_frames(vm, ready, target, method, pc, owner, constant, args, rest, descriptor, U32.is_eq(M.length(M.Frame, S.frames(ready)), U32.add(depth, 1)), S.frames(ready))

def dynamic_bootstrap_callsite(+vm: M.VM, +callsite: U32, +method: U32, +pc: U32, +owner: U32, +constant: U32, +args: +List<M.Slot>, +rest: +List<M.Cont>, +descriptor: String, +depth: U32, valid: Bool) -> Result<&2, &2, String, O.Outcome>:
  match valid:
    case False{}: dynamic_failure_outcome(vm, owner, method, pc, constant, rest)
    case True{}:
      dynamic_bootstrap_callsite_target(vm, callsite, method, pc, owner, constant, args, rest, descriptor, depth, dynamic_callsite_target(vm, callsite))

def dynamic_bootstrap_fresh(+vm: M.VM, value: M.Slot, +method: U32, +pc: U32, +owner: U32, +constant: U32, +args: +List<M.Slot>, +rest: +List<M.Cont>, +descriptor: String, +depth: U32) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case M.Slot{3, +callsite}:
      dynamic_bootstrap_callsite(vm, callsite, method, pc, owner, constant, args, rest, descriptor, depth, dynamic_callsite_valid(vm, callsite, descriptor))
    case _: dynamic_failure_outcome(vm, owner, method, pc, constant, rest)

def dynamic_bootstrap_published(found: Maybe<&2, M.DynamicSite>, +vm: M.VM, value: M.Slot, +method: U32, +pc: U32, +owner: U32, +constant: U32, +args: +List<M.Slot>, +rest: +List<M.Cont>, +descriptor: String, +depth: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{M.DynamicSite{m, p, o, c, 1, +callsite, f}}:
      dynamic_bootstrap_callsite_target(vm, callsite, method, pc, owner, constant, args, rest, descriptor, depth, dynamic_callsite_target(vm, callsite))
    case Some{M.DynamicSite{m, p, o, c, 2, callsite, +failure}}:
      Done{O.ThrownRef{S.with_cont(vm, rest), failure}}
    case _: dynamic_bootstrap_fresh(vm, value, method, pc, owner, constant, args, rest, descriptor, depth)

# A reentrant resolution may already have published this site; its result wins
# and the CallSite returned by this (later) bootstrap activation is discarded.
def dynamic_bootstrap_value(+vm: M.VM, value: M.Slot, +method: U32, +pc: U32, +owner: U32, +constant: U32, +args: +List<M.Slot>, +rest: +List<M.Cont>, +descriptor: String, +depth: U32) -> Result<&2, &2, String, O.Outcome>:
  dynamic_bootstrap_published(S.dynamic_site(vm, method, pc), vm, value, method, pc, owner, constant, args, rest, descriptor, depth)

def dynamic_bootstrap_info(+vm: M.VM, value: M.Slot, method: U32, pc: U32, owner: U32, constant: U32, +args: +List<M.Slot>, +rest: +List<M.Cont>, +depth: U32, result: Result<&2, &2, String, DynamicInfo>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{_}: dynamic_failure_outcome(vm, owner, method, pc, constant, rest)
    case Done{DynamicInfo{name, descriptor, bootstrap, pool}}:
      dynamic_bootstrap_value(vm, value, method, pc, owner, constant, args, rest, descriptor, depth)

def dynamic_bootstrap_depth(+vm: M.VM, +value: M.Slot, +depth: U32, +method: U32, +pc: U32, +owner: U32, +constant: U32, +args: +List<M.Slot>, +rest: +List<M.Cont>, same_depth: Bool) -> Result<&2, &2, String, O.Outcome>:
  match same_depth:
    case False{}: Done{O.Returned{vm, Some{value}}}
    case True{}:
      dynamic_bootstrap_info(vm, value, method, pc, owner, constant, args, rest, depth, dynamic_info(vm, owner, constant))

def dynamic_bootstrap_result(+vm: M.VM, +value: M.Slot, +depth: U32, cont: M.Cont, +rest: +List<M.Cont>) -> Result<&2, &2, String, O.Outcome>:
  match cont:
    case M.DynamicBootstrap{expected, method, pc, owner, constant, args}:
      dynamic_bootstrap_depth(vm, value, depth, method, pc, owner, constant, args, rest, U32.is_eq(depth, expected))
    case _: Done{O.Returned{vm, Some{value}}}


def dynamic_start_frame(+vm: M.VM, +frame: M.Frame, owner: U32, constant: U32, max: U32, info: DynamicInfo, args: +List<M.Slot>, result: Result<&2, &2, String, M.VM>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: dynamic_failure_step(vm, frame, owner, constant, error)
    case Done{started}: Done{started}

def dynamic_start_inputs(+vm: M.VM, +frame: M.Frame, +owner: U32, +constant: U32, +max: U32, +info: DynamicInfo, +args: +List<M.Slot>, result: Result<&2, &2, String, DynamicInputs>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: dynamic_failure_step(vm, frame, owner, constant, error)
    case Done{DynamicInputs{+updated, +values, source_parameters}}:
      linking : M.VM = S.set_dynamic_site(updated, M.DynamicSite{S.method_id(frame), S.pc(frame), owner, constant, 0, 0, 0})
      prepared : DynamicInputs = DynamicInputs{linking, values, source_parameters}
      dynamic_start_frame(vm, frame, owner, constant, max, info, args, dynamic_bootstrap_frame(frame, owner, constant, args, max, info, prepared))

def dynamic_start(+vm: M.VM, +frame: M.Frame, +owner: U32, +constant: U32, +max: U32, +info: DynamicInfo, +args: +List<M.Slot>) -> Result<&2, &2, String, M.VM>:
  dynamic_start_inputs(vm, frame, owner, constant, max, info, args, dynamic_inputs(vm, frame, owner, info))

def dynamic_site_info(+vm: M.VM, +frame: M.Frame, owner: U32, constant: U32, max: U32, descriptor: String, +args: +List<M.Slot>, result: Result<&2, &2, String, DynamicInfo>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: dynamic_failure_step(vm, frame, owner, constant, error)
    case Done{info}: dynamic_start(vm, frame, owner, constant, max, info, args)

def dynamic_site_dispatch(site: M.DynamicSite, +vm: M.VM, +frame: M.Frame, +owner: U32, +constant: U32, +max: U32, +descriptor: String, +args: +List<M.Slot>) -> Result<&2, &2, String, M.VM>:
  match site:
    # Reentrant resolution while the bootstrap is still running: the JVM simply
    # runs the bootstrap again (JVMS 6.5 invokedynamic; first result wins).
    case M.DynamicSite{method, pc, owner0, constant0, 0, callsite, failure}:
      dynamic_site_info(vm, frame, owner, constant, max, descriptor, args, dynamic_info(vm, owner, constant))
    case M.DynamicSite{method, pc, owner0, constant0, 1, callsite, failure}:
      dynamic_linked_target(vm, frame, site, args, descriptor, max)
    case M.DynamicSite{method, pc, owner0, constant0, 2, callsite, failure}:
      Done{S.with_status(S.with_exception(S.commit(vm, frame), failure), 6)}
    case _:
      dynamic_failure_step(vm, frame, owner, constant, "invalid call site state")

def dynamic_site_step(found: Maybe<&2, M.DynamicSite>, +vm: M.VM, +frame: M.Frame, +owner: U32, +constant: U32, +max: U32, +descriptor: String, +args: +List<M.Slot>) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}:
      dynamic_site_info(vm, frame, owner, constant, max, descriptor, args, dynamic_info(vm, owner, constant))
    case Some{site}:
      dynamic_site_dispatch(site, vm, frame, owner, constant, max, descriptor, args)

def dynamic_arguments_result(result: Result<&2, &2, String, F.Arguments>, +vm: M.VM, +frame: M.Frame, method: M.LoadedMethod, owner: U32, constant: U32, max: U32, descriptor: String) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: dynamic_failure_step(vm, frame, owner, constant, error)
    case Done{F.Arguments{+caller, +values}}:
      dynamic_site_step(S.dynamic_site(vm, M.loaded_method_id(method), S.pc(frame)), vm, caller, owner, constant, max, descriptor, values)


def execute_indy_parsed(+vm: M.VM, +frame: M.Frame, constant: U32, max: U32, method: M.LoadedMethod, owner: U32, descriptor: String, parsed: Result<&2, &2, String, M.Descriptor>) -> Result<&2, &2, String, M.VM>:
  match parsed:
    case Fail{error}: dynamic_failure_step(vm, frame, owner, constant, error)
    case Done{signature}:
      dynamic_arguments_result(F.arguments(frame, D.parameter_count(signature)), vm, frame, method, owner, constant, max, descriptor)

def execute_indy_descriptor(+vm: M.VM, +frame: M.Frame, constant: U32, max: U32, method: M.LoadedMethod, owner: U32, +info: DynamicInfo) -> Result<&2, &2, String, M.VM>:
  match info:
    case DynamicInfo{name, descriptor, bootstrap, pool}:
      execute_indy_parsed(vm, frame, constant, max, method, owner, descriptor, D.parse_method(descriptor))

def execute_indy_info(+vm: M.VM, +frame: M.Frame, constant: U32, max: U32, +method: M.LoadedMethod, owner: U32, result: Result<&2, &2, String, DynamicInfo>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: dynamic_failure_step(vm, frame, owner, constant, error)
    case Done{info}: execute_indy_descriptor(vm, frame, constant, max, method, owner, info)

def execute_indy_method(+vm: M.VM, +frame: M.Frame, +constant: U32, max: U32, method_result: Maybe<&2, M.LoadedMethod>) -> Result<&2, &2, String, M.VM>:
  match method_result:
    case None{}: Fail{"InvalidState: invokedynamic method"}
    case Some{+method}:
      +owner : U32 = M.loaded_method_owner(method)
      execute_indy_info(vm, frame, constant, max, method, owner, dynamic_info(vm, owner, constant))

def execute_indy(+vm: M.VM, +frame: M.Frame, constant: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  execute_indy_method(vm, frame, constant, max, M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)))
type BoundaryJob is Data:
  BValues{result: Result<&2, &2, String, O.Outcome>, depth: U32}
  BResult{value: M.Slot, depth: U32, conts: +List<M.Cont>}
  BSame{value: M.Slot, depth: U32, effect: M.Effect, descriptor: U32, rest: +List<M.Cont>, same: Bool}
  BVoid{depth: U32, conts: +List<M.Cont>}
  BVoidSame{depth: U32, same: Bool}
  BInitResult{value: M.Slot, depth: U32, effect: M.Effect, rest: +List<M.Cont>, same: Bool}
  BDynamicResult{value: M.Slot, depth: U32, method: U32, pc: U32, owner: U32, constant: U32, args: +List<M.Slot>, rest: +List<M.Cont>, same: Bool}
  BVoidInitResult{depth: U32, effect: M.Effect, rest: +List<M.Cont>, same: Bool}
  BVoidDynamicResult{depth: U32, method: U32, pc: U32, owner: U32, constant: U32, rest: +List<M.Cont>, same: Bool}
  BHostResume{value: M.Slot, depth: U32, cont: M.Cont, rest: +List<M.Cont>, same: Bool}

# A returning bytecode callback is still the top frame while its continuation
# runs. Detach it so the continuation observes the depth its intrinsic started
# at (chained push_cont calls record that depth), then reattach it so the
# ordinary frame-return path pops it.
def reattach_callee(+callee: M.Frame, result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{+updated, value}}: Done{O.Returned{S.with_frames(updated, Con{callee, S.frames(updated)}), value}}
    case Done{O.Call{+updated, method, args}}: Done{O.Call{S.with_frames(updated, Con{callee, S.frames(updated)}), method, args}}
    case Done{O.ThrownRef{+updated, reference}}: Done{O.ThrownRef{S.with_frames(updated, Con{callee, S.frames(updated)}), reference}}
    case Done{O.ThrownName{+updated, name}}: Done{O.ThrownName{S.with_frames(updated, Con{callee, S.frames(updated)}), name}}
    case Done{O.Suspend{+updated, effect}}: Done{O.Suspend{S.with_frames(updated, Con{callee, S.frames(updated)}), effect}}

def callback_resume_frames(+vm: M.VM, cont: M.Cont, value: M.Slot, hasCallee: Bool, frames: +List<M.Frame>) -> Result<&2, &2, String, O.Outcome>:
  match hasCallee frames:
    case True{} Con{+callee, below}: reattach_callee(callee, I.continue_java(S.with_frames(vm, below), cont, value))
    case _ _: I.continue_java(vm, cont, value)

def callback_resume(+vm: M.VM, cont: M.Cont, value: M.Slot, depth: U32) -> Result<&2, &2, String, O.Outcome>:
  callback_resume_frames(vm, cont, value, U32.is_eq(M.length(M.Frame, S.frames(vm)), U32.add(depth, 1)), S.frames(vm))

@unsafe def boundary_job(+vm: M.VM, job: BoundaryJob) -> Result<&2, &2, String, O.Outcome>:
  match job:
    case BValues{result, depth}:
      match result:
        case Done{O.Returned{+vm, Some{value}}}: boundary_job(vm, BResult{value, depth, host_cont(vm)})
        case Done{O.Returned{+vm, None{}}}: boundary_job(vm, BVoid{depth, host_cont(vm)})
        case other: other
    case BResult{value, +current_depth, conts}:
      match conts:
        case Con{M.CallBoundary{+expected, effect, descriptor}, rest}:
          boundary_job(vm, BSame{value, current_depth, effect, descriptor, rest, U32.is_eq(expected, current_depth)})
        case Con{M.HandleInitReturn{expected, effect}, rest}:
          boundary_job(vm, BInitResult{value, current_depth, effect, rest, U32.is_eq(expected, current_depth)})
        case Con{M.HandleInvocation{_, kind, owner, name, descriptor, method, entry, args, target, requested, max, previousEffect}, rest}:
          boundary_job(vm, BResult{value, current_depth, rest})
        case Con{M.DynamicBootstrap{expected, method, pc, owner, constant, args}, rest}:
          boundary_job(vm, BDynamicResult{value, current_depth, method, pc, owner, constant, args, rest, U32.is_eq(expected, current_depth)})
        case Con{M.HostCallback{expected}, Con{cont, rest}}:
          boundary_job(vm, BHostResume{value, current_depth, cont, rest, U32.is_eq(expected, current_depth)})
        case _: Done{O.Returned{vm, Some{value}}}
    case BHostResume{value, +depth, cont, rest, True{}}:
      boundary_job(vm, BValues{callback_resume(S.with_cont(vm, rest), cont, value, depth), depth})
    case BHostResume{value, depth, cont, rest, False{}}: Done{O.Returned{vm, Some{value}}}
    case BSame{value, +depth, effect, descriptor, rest, True{}}:
      boundary_job(vm, BValues{boundary_value(S.with_cont(vm, rest), effect, descriptor, value), depth})
    case BSame{value, depth, effect, descriptor, rest, False{}}: Done{O.Returned{vm, Some{value}}}
    case BVoid{+current_depth, conts}:
      match conts:
        case Con{M.CallBoundary{+expected, effect, descriptor}, rest}:
          boundary_job(vm, BVoidSame{current_depth, U32.is_eq(expected, current_depth)})
        case Con{M.HandleInitReturn{expected, effect}, rest}:
          boundary_job(vm, BVoidInitResult{current_depth, effect, rest, U32.is_eq(expected, current_depth)})
        case Con{M.HandleInvocation{_, kind, owner, name, descriptor, method, entry, args, target, requested, max, previousEffect}, rest}:
          boundary_job(vm, BVoid{current_depth, rest})
        case Con{M.DynamicBootstrap{expected, method, pc, owner, constant, args}, rest}:
          boundary_job(vm, BVoidDynamicResult{current_depth, method, pc, owner, constant, rest, U32.is_eq(expected, current_depth)})
        # A void callback resumes its continuation with null.
        case Con{M.HostCallback{expected}, Con{cont, rest}}:
          boundary_job(vm, BHostResume{M.Slot{3, 0}, current_depth, cont, rest, U32.is_eq(expected, current_depth)})
        case _: Done{O.Returned{vm, None{}}}
    case BVoidSame{+depth, True{}}: boundary_job(vm, BResult{M.Slot{3, 0}, depth, host_cont(vm)})
    case BVoidSame{depth, False{}}: Done{O.Returned{vm, None{}}}
    case BInitResult{value, depth, effect, rest, True{}}:
      Done{O.Returned{S.with_effect(S.with_cont(vm, rest), effect), Some{value}}}
    case BInitResult{value, depth, effect, rest, False{}}: boundary_job(vm, BResult{value, depth, rest})
    case BDynamicResult{+value, +depth, method, pc, owner, constant, +args, +rest, True{}}:
      dynamic_bootstrap_depth(vm, value, depth, method, pc, owner, constant, args, rest, True{})
    case BDynamicResult{value, depth, method, pc, owner, constant, args, rest, False{}}:
      boundary_job(vm, BResult{value, depth, rest})
    case BVoidInitResult{depth, effect, rest, True{}}:
      Done{O.Returned{S.with_effect(S.with_cont(vm, rest), effect), None{}}}
    case BVoidInitResult{depth, effect, rest, False{}}: boundary_job(vm, BVoid{depth, rest})
    case BVoidDynamicResult{depth, method, pc, owner, constant, rest, True{}}:
      dynamic_failure_outcome(vm, owner, method, pc, constant, rest)
    case BVoidDynamicResult{depth, method, pc, owner, constant, rest, False{}}: boundary_job(vm, BVoid{depth, rest})


def boundary_result(+vm: M.VM, value: M.Slot, +depth: U32, conts: +List<M.Cont>) -> Result<&2, &2, String, O.Outcome>:
  boundary_job(vm, BResult{value, depth, conts})

def finish_return(+vm: M.VM, value: M.Slot) -> M.VM:
  finish_reflect_outcome(vm, boundary_result(vm, value, U32.sub(M.length(M.Frame, S.frames(vm)), 1), host_cont(vm)))



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

def finish_boundary_void(+vm: M.VM) -> M.VM:
  finish_reflect_outcome(vm, boundary_result(vm, M.Slot{3, 0}, U32.sub(M.length(M.Frame, S.frames(vm)), 1), host_cont(vm)))

def invoke_class_initializer_frame(vm: M.VM, id: U32, maxLocals: U32, owner: U32, +caller: M.Frame, values: +List<M.Slot>, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{old, rest}:
      S.with_frames(vm, Con{M.Frame{id, 0, S.pc(caller), copy_arguments(values, make_locals(U32.to_nat(maxLocals)), 0), Nil{}, owner, 0}, Con{S.advance(caller), rest}})
    case Nil{}:
      S.fail(vm, "InvalidState: initializer invocation without caller")
def handle_init_dispatch_failed_conts(+vm: M.VM, +error: String, previousEffect: M.Effect, continuations: +List<M.Cont>) -> M.VM:
  match continuations:
    case Con{M.HandleInitReturn{depth, effect}, rest}:
      clean = S.with_effect(S.with_cont(vm, rest), effect)
      S.with_status(ensure_throw(clean, error), 6)
    case _: S.with_status(S.with_effect(ensure_throw(vm, error), previousEffect), 6)
def handle_init_dispatch_failed(+vm: M.VM, +error: String, previousEffect: M.Effect) -> M.VM:
  handle_init_dispatch_failed_conts(vm, error, previousEffect, host_cont(vm))


def handle_init_dispatch_result(+vm: M.VM, result: Result<&2, &2, String, M.VM>, previousEffect: M.Effect) -> M.VM:
  match result:
    case Done{vm}: vm
    case Fail{error}: handle_init_dispatch_failed(vm, error, previousEffect)

def finish_handle_invocation_ready(+vm: M.VM, +caller: M.Frame, kind: U32, owner: U32, name: U32, descriptor: U32, method_id: U32, entry: M.HeapEntry, args: +List<M.Slot>, target: String, requested: String, max: U32, +previousEffect: M.Effect, +rest_cont: +List<M.Cont>) -> M.VM:
  +idle = S.with_effect(vm, M.Idle{})
  depth = M.length(M.Frame, S.frames(idle))
  return_cont : M.Cont = M.HandleInitReturn{depth, previousEffect}
  +ready = S.with_cont(idle, Con{return_cont, rest_cont})
  result = handle_initialized_dispatch(ready, caller, kind, owner, name, descriptor, method_id, entry, args, target, requested, max)
  handle_init_dispatch_result(ready, result, previousEffect)

def finish_handle_invocation_start(start: L.ClassForNameStart, +vm: M.VM, +caller: M.Frame, kind: U32, owner: U32, name: U32, descriptor: U32, method_id: U32, entry: M.HeapEntry, args: +List<M.Slot>, target_descriptor: String, requested: String, max: U32, previousEffect: M.Effect, +rest_cont: +List<M.Cont>) -> M.VM:
  match start:
    case L.ClassForNameReady{+vm}:
      finish_handle_invocation_ready(vm, caller, kind, owner, name, descriptor, method_id, entry, args, target_descriptor, requested, max, previousEffect, rest_cont)
    # Another thread is initializing the next class: keep the continuation and
    # park; resume_handle_init re-walks from it once that class is settled.
    case L.ClassForNameBlocked{+vm, class}:
      +depth : U32 = M.length(M.Frame, S.frames(vm))
      +kept : M.VM = S.with_cont(vm, Con{M.HandleInvocation{depth, kind, owner, name, descriptor, method_id, entry, args, target_descriptor, requested, max, previousEffect}, rest_cont})
      S.with_status(Th.park(kept, M.HandleInitWait{class}, False{}, M.Clock{0, 0}), 8)
    case L.ClassForNameCall{+vm, +target, +method}:
      +vm1 = S.with_effect(S.set_class_state(vm, target, 1), M.Idle{})
      depth = M.length(M.Frame, S.frames(vm1))
      continuation : M.Cont = M.HandleInvocation{depth, kind, owner, name, descriptor, method_id, entry, args, target_descriptor, requested, max, previousEffect}
      vm2 = S.with_cont(vm1, Con{continuation, rest_cont})
      handle_initializer_push(vm2, method, target, caller)
def finish_handle_invocation_init(+completed: M.VM, +caller: M.Frame, kind: U32, owner: U32, name: U32, descriptor: U32, method_id: U32, entry: M.HeapEntry, args: +List<M.Slot>, target: String, requested: String, max: U32, previousEffect: M.Effect, +rest_cont: +List<M.Cont>, init_result: Result<&2, &2, String, L.ClassForNameStart>) -> M.VM:
  match init_result:
    case Fail{error}:
      clean = S.with_effect(S.with_cont(completed, rest_cont), previousEffect)
      S.with_status(ensure_throw(clean, error), 6)
    case Done{start}:
      finish_handle_invocation_start(start, completed, caller, kind, owner, name, descriptor, method_id, entry, args, target, requested, max, previousEffect, rest_cont)

def finish_handle_invocation_caller(+vm: M.VM, current: M.Frame, +frames: +List<M.Frame>, kind: U32, +owner: U32, name: U32, descriptor: U32, method_id: U32, entry: M.HeapEntry, args: +List<M.Slot>, target: String, requested: String, max: U32, previousEffect: M.Effect, +rest_cont: +List<M.Cont>, caller_result: Maybe<&2, M.Frame>) -> M.VM:
  match caller_result:
    case None{}: S.fail(vm, "InvalidState: handle initializer caller")
    case Some{caller}:
      +completed = finish_void_current(vm, current, frames)
      finish_handle_invocation_init(completed, caller, kind, owner, name, descriptor, method_id, entry, args, target, requested, max, previousEffect, rest_cont, L.class_for_name_walk(256n, completed, owner))

def finish_handle_invocation(+vm: M.VM, current: M.Frame, +frames: +List<M.Frame>, kind: U32, owner: U32, name: U32, descriptor: U32, method_id: U32, entry: M.HeapEntry, args: +List<M.Slot>, target: String, requested: String, max: U32, previousEffect: M.Effect, +rest_cont: +List<M.Cont>) -> M.VM:
  finish_handle_invocation_caller(vm, current, frames, kind, owner, name, descriptor, method_id, entry, args, target, requested, max, previousEffect, rest_cont, M.nth(M.Frame, frames, 0))

@unsafe def resume_handle_conts(+vm: M.VM, conts: +List<M.Cont>, frames: +List<M.Frame>) -> M.VM:
  match conts frames:
    case Con{M.HandleInvocation{depth, kind, +owner, name, descriptor, method, entry, args, target, requested, max, previousEffect}, rest} Con{+caller, more}:
      +ready : M.VM = S.with_status(vm, 0)
      finish_handle_invocation_init(ready, caller, kind, owner, name, descriptor, method, entry, args, target, requested, max, previousEffect, rest, L.class_for_name_walk(256n, ready, owner))
    case _ _: S.fail(vm, "InvalidState: method handle initialization resume")

# A method handle's initialization chain waited for another thread's <clinit>.
@unsafe def resume_handle_init(+vm: M.VM) -> M.VM:
  resume_handle_conts(vm, host_cont(vm), S.frames(vm))

def invoke_class_initializer(+vm: M.VM, method: M.LoadedMethod, +args: +List<M.Slot>, +caller: M.Frame) -> M.VM:
  match method:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}:
      invoke_class_initializer_frame(vm, id, maxLocals, owner, caller, args, S.frames(vm))
def finish_void_same(+vm: M.VM, same: Bool) -> M.VM:
  match same:
    case True{}: finish_boundary_void(vm)
    case False{}: finish_void_frames(vm, S.frames(vm))

def finish_void_handle_frames(+vm: M.VM, depth: U32, kind: U32, owner: U32, name: U32, descriptor: U32, method: U32, entry: M.HeapEntry, +args: +List<M.Slot>, target: String, requested: String, max: U32, previousEffect: M.Effect, +rest_cont: +List<M.Cont>, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{current, rest_frames}:
      finish_handle_invocation(vm, current, rest_frames, kind, owner, name, descriptor, method, entry, args, target, requested, max, previousEffect, rest_cont)
    case Nil{}: S.fail(vm, "InvalidState: handle initializer return")

def finish_void_handle(+vm: M.VM, depth: U32, kind: U32, owner: U32, name: U32, descriptor: U32, method: U32, entry: M.HeapEntry, +args: +List<M.Slot>, target: String, requested: String, max: U32, previousEffect: M.Effect, +rest_cont: +List<M.Cont>, same_depth: Bool) -> M.VM:
  match same_depth:
    case False{}: finish_void_frames(vm, S.frames(vm))
    case True{}: finish_void_handle_frames(vm, depth, kind, owner, name, descriptor, method, entry, args, target, requested, max, previousEffect, rest_cont, S.frames(vm))

def initialized_owner(+vm: M.VM, owner: U32) -> M.VM:
  match owner:
    case 4294967295: vm
    case value: S.set_class_state(vm, value, 2)

def initialized_top(+vm: M.VM, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: vm
    case Con{current, rest}: initialized_owner(vm, S.initializing(current))

# A void Java callback (a <clinit> requested by an intrinsic) resumes its
# continuation; the finished initializer's class is marked initialized first so
# the continuation's re-walk sees it.
def finish_void_callback(+vm: M.VM, same: Bool) -> M.VM:
  match same:
    case True{}: finish_boundary_void(initialized_top(vm, S.frames(vm)))
    case False{}: finish_void_frames(vm, S.frames(vm))

def finish_void_cont(+vm: M.VM, conts: +List<M.Cont>) -> M.VM:
  match conts:
    case Con{M.HandleInvocation{+depth, kind, owner, name, descriptor, method, entry, +args, target, requested, max, previousEffect}, rest_cont}:
      finish_void_handle(vm, depth, kind, owner, name, descriptor, method, entry, args, target, requested, max, previousEffect, rest_cont, U32.is_eq(M.length(M.Frame, S.frames(vm)), U32.add(depth, 1)))
    case Con{M.HandleInitReturn{depth, effect}, rest}:
      finish_void_same(vm, U32.is_eq(M.length(M.Frame, S.frames(vm)), U32.add(depth, 1)))
    case Con{M.CallBoundary{+depth, effect, descriptor}, rest}:
      finish_void_same(vm, U32.is_eq(M.length(M.Frame, S.frames(vm)), U32.add(depth, 1)))
    case Con{M.HostCallback{+depth}, rest}:
      finish_void_callback(vm, U32.is_eq(M.length(M.Frame, S.frames(vm)), U32.add(depth, 1)))
    case _: finish_void_frames(vm, S.frames(vm))

def finish_void(+vm: M.VM) -> M.VM:
  finish_void_cont(vm, host_cont(vm))


# Instance methods that the JDK dispatches to a proxy's handler or that an
# annotation implements itself.
def receiver_entry_kind(result: Result<&2, &2, String, M.HeapEntry>) -> U32:
  match result:
    case Fail{error}: 0
    case Done{entry}: L.entry_kind(entry)

def object_dispatched(+name: String, +flags: U32) -> Bool:
  U32.is_eq(U32.and(flags, 8), 0) && (String.eq(name, "toString") || String.eq(name, "hashCode") || String.eq(name, "equals"))

def invoke_frame(vm: M.VM, id: U32, maxLocals: U32, +caller: M.Frame, values: +List<M.Slot>, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{old, rest}:
      S.with_frames(vm, Con{M.Frame{id, 0, S.pc(caller), copy_arguments(values, make_locals(U32.to_nat(maxLocals)), 0), Nil{}, 4294967295, 0}, Con{S.advance(caller), rest}})
    case Nil{}:
      S.fail(vm, "InvalidState: invocation without caller")

def invoke_arguments(vm: M.VM, method: M.LoadedMethod, args: F.Arguments, frames: +List<M.Frame>) -> M.VM:
  match method:
    case M.LoadedMethod{id, owner0, name0, descriptor0, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}:
      match args:
        case F.Arguments{caller, values}:
          invoke_frame(vm, id, maxLocals, caller, values, frames)

def thrown_class_entry(result: Result<&2, &2, String, M.HeapEntry>) -> U32:
  match result:
    case Fail{error}: 0
    case Done{entry}: H.entry_class(entry)

def thrown_class_of(+vm: M.VM) -> U32:
  thrown_class_entry(H.get(S.heap(vm), S.exception(vm)))
def proxy_exception_entry_found(original: U32, entry: M.HeapEntry) -> M.HeapEntry:
  M.HeapEntry{kind_class, kind, element, fields, values, chars} = entry
  M.HeapEntry{kind_class, kind, element, H.binding_set(fields, 1, M.Slot{3, original}), values, chars}

def proxy_exception_entry(class: U32, original: U32) -> M.HeapEntry:
  proxy_exception_entry_found(original, H.throwable_entry(class))

def proxy_wrap_exception_alloc(+vm: M.VM, result: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{H.Allocation{vm, reference}}: S.with_exception(vm, reference)

def proxy_declared_exception_group_select(group_missing: Bool, next: Unit -> Bool) -> Bool:
  match group_missing:
    case True{}: False{}
    case False{}: next(Unit{})

def proxy_declared_exception_groups(fuel: Nat, +thrown: U32, +groups: +List<U32>, +classes: +List<M.LoadedClass>, +symbols: +List<String>, seen: Bool, matched: Bool) -> Bool:
  match fuel groups:
    case 0n _: False{}
    case 1n+remaining Nil{}: seen && matched
    case 1n+remaining Con{0, rest}:
      match rest:
        case Nil{}: seen && matched
        case Con{head, tail}:
          proxy_declared_exception_group_select(seen && Bool.not(matched), unit => proxy_declared_exception_groups(remaining, thrown, Con{head, tail}, classes, symbols, True{}, False{}))
    case 1n+remaining Con{declared, rest}:
      proxy_declared_exception_groups(remaining, thrown, rest, classes, symbols, True{}, matched || H.assignable(classes, symbols, thrown, declared))

def proxy_declared_exception(fuel: Nat, +thrown: U32, +exceptions: +List<U32>, +classes: +List<M.LoadedClass>, +symbols: +List<String>) -> Bool:
  proxy_declared_exception_groups(fuel, thrown, exceptions, classes, symbols, False{}, False{})
def proxy_wrap_exception_policy(result: Result<&2, &2, String, +List<U32>>, +vm: M.VM, thrown: U32, original: U32, wrapper_class: U32) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{+exceptions}:
      +declared : Bool = proxy_declared_exception(100000n, thrown, exceptions, S.classes(vm), S.symbols(vm))
      +wrapper_entry : M.HeapEntry = proxy_exception_entry(wrapper_class, original)
      Bool.pick(M.VM, declared, vm, proxy_wrap_exception_alloc(vm, H.allocate(vm, wrapper_entry)))

def proxy_wrap_exception_checked(+vm: M.VM, thrown: U32, method_id: U32, +owners: +List<U32>) -> M.VM:
  +original = S.exception(vm)
  +wrapper_class = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/reflect/UndeclaredThrowableException")
  proxy_wrap_exception_policy(L.proxy_exception_policy(vm, method_id, owners), vm, thrown, original, wrapper_class)

def proxy_wrap_exception_effect(effect: M.Effect, +vm: M.VM, +error: String) -> M.VM:
  match effect:
    case M.ProxyCall{descriptor, method_id, +owners}:
      +thrown = thrown_class_of(vm)
      +runtime = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/RuntimeException")
      +error_class = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/Error")
      unchecked : Bool = H.assignable(S.classes(vm), S.symbols(vm), thrown, runtime) || H.assignable(S.classes(vm), S.symbols(vm), thrown, error_class)
      Bool.pick(M.VM, unchecked, vm, proxy_wrap_exception_checked(vm, thrown, method_id, owners))
    case _: vm
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

def privileged_exception_fill(+entry: M.HeapEntry, original: U32) -> M.HeapEntry:
  match entry:
    case M.HeapEntry{kind_class, kind, element, +fields, values, chars}:
      M.HeapEntry{kind_class, kind, element, H.binding_set(H.binding_set(fields, 1, M.Slot{3, original}), 3, M.Slot{1, 1}), values, chars}

def privileged_exception_entry(class: U32, original: U32) -> M.HeapEntry:
  privileged_exception_fill(H.throwable_entry(class), original)

def privileged_wrap_select(unchecked: Bool, +vm: M.VM) -> M.VM:
  match unchecked:
    case True{}: vm
    case False{}: reflective_exception_wrap_alloc(vm, H.allocate(vm, privileged_exception_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/security/PrivilegedActionException"), S.exception(vm))))

# A checked exception leaving PrivilegedExceptionAction.run becomes the cause of
# a PrivilegedActionException; runtime exceptions and errors pass through.
def privileged_wrap(+vm: M.VM) -> M.VM:
  +thrown = thrown_class_of(vm)
  +runtime = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/RuntimeException")
  +error_class = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/Error")
  unchecked : Bool = H.assignable(S.classes(vm), S.symbols(vm), thrown, runtime) || H.assignable(S.classes(vm), S.symbols(vm), thrown, error_class)
  privileged_wrap_select(unchecked, vm)

def class_not_found_thrown(+vm: M.VM) -> Bool:
  H.assignable(S.classes(vm), S.symbols(vm), thrown_class_of(vm), H.named_class(S.classes(vm), S.symbols(vm), "java/lang/ClassNotFoundException"))

# LoaderCatch: a ClassNotFoundException from the callee resumes the waiting
# callback with null, as a normal return at the boundary's depth would; other
# throwables keep unwinding.
@unsafe def loader_catch(caught: Bool, +vm: M.VM, +depth: U32) -> M.VM:
  match caught:
    case False{}: boundary_throw_job(vm, ThrowStart{depth})
    case True{}: loader_catch_frames(S.with_status(S.with_exception(vm, 0), 0), S.frames(vm))

@unsafe def loader_catch_frames(+vm: M.VM, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{caller, rest}: handle_immediate(vm, caller, M.Slot{3, 0})
    case Nil{}: S.fail(vm, "InvalidState: loader catch without caller")

@unsafe def io_exception_thrown(+vm: M.VM) -> Bool:
  H.assignable(S.classes(vm), S.symbols(vm), thrown_class_of(vm), H.named_class(S.classes(vm), S.symbols(vm), "java/io/IOException"))

# SerialCatch: an IOException from a top-level writeObject callback resumes the
# waiting ObjectOutputStream continuation, told the exception (WCaught), so it
# can write TC_EXCEPTION before rethrowing; other throwables keep unwinding.
@unsafe def serial_catch(caught: Bool, +vm: M.VM, +depth: U32) -> M.VM:
  match caught:
    case False{}: boundary_throw_job(vm, ThrowStart{depth})
    case True{}: serial_catch_conts(S.exception(vm), host_cont(vm), vm, depth)

@unsafe def serial_catch_conts(+exception: U32, conts: +List<M.Cont>, +vm: M.VM, +depth: U32) -> M.VM:
  match conts:
    case Con{M.HostCallback{+expected}, Con{M.NeedSerialWrite{+stream, +tasks}, +rest}}:
      +resumed : M.VM = S.with_cont(vm, Con{M.HostCallback{expected}, Con{M.NeedSerialWrite{stream, Con{M.WCaught{exception}, tasks}}, rest}})
      loader_catch_frames(S.with_status(S.with_exception(resumed, 0), 0), S.frames(resumed))
    case _: boundary_throw_job(vm, ThrowStart{depth})

# LoaderSuper: a supertype defineClass needs could not be loaded.
@unsafe def loader_super_wrap(missing: Bool, +vm: M.VM, +name: String) -> M.VM:
  match missing:
    case False{}: vm
    case True{}: loader_super_alloc(vm, S.exception(vm), H.allocate(vm, H.string_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/String"), L.units_from_string(name))))

@unsafe def loader_super_alloc(+vm: M.VM, +cause: U32, result: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{H.Allocation{+updated, +message}}: reflective_exception_wrap_alloc(updated, H.allocate(updated, entry_with_message(throwable_with_cause(H.throwable_entry(H.named_class(S.classes(updated), S.symbols(updated), "java/lang/NoClassDefFoundError")), cause), message)))

def boundary_exception(+vm: M.VM, effect: M.Effect) -> M.VM:
  match effect:
    case M.PrivilegedCall{}: privileged_wrap(vm)
    case M.LoaderSuper{name}: loader_super_wrap(class_not_found_thrown(vm), vm, name)
    case M.ReflectCall{}: reflective_exception_wrap_alloc(vm, H.allocate(vm, reflective_exception_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/reflect/InvocationTargetException"), S.exception(vm))))
    case M.ReflectConstructor{reference}: reflective_exception_wrap_alloc(vm, H.allocate(vm, reflective_exception_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/reflect/InvocationTargetException"), S.exception(vm))))
    case _: proxy_wrap_exception_effect(effect, vm, "java/lang/Throwable")

type ThrowJob is Data:
  ThrowStart{depth: U32}
  ThrowCont{depth: U32, conts: +List<M.Cont>}
  ThrowSame{depth: U32, effect: M.Effect, rest: +List<M.Cont>, same: Bool}
  ThrowHandle{depth: U32, previousEffect: M.Effect, rest: +List<M.Cont>, same: Bool}
  ThrowInit{depth: U32, effect: M.Effect, rest: +List<M.Cont>, same: Bool}
  ThrowDynamic{depth: U32, rest: +List<M.Cont>, same: Bool}
  ThrowHost{depth: U32, rest: +List<M.Cont>, same: Bool}

@unsafe def boundary_throw_job(+vm: M.VM, job: ThrowJob) -> M.VM:
  match job:
    case ThrowStart{depth}: boundary_throw_job(S.with_status(vm, 6), ThrowCont{depth, host_cont(vm)})
    case ThrowCont{+depth, conts}:
      match conts:
        case Con{M.CallBoundary{+expected, effect, descriptor}, rest}:
          boundary_throw_job(vm, ThrowSame{depth, effect, rest, U32.is_eq(expected, depth)})
        case Con{M.HandleInvocation{expected, kind, owner, name, descriptor, method, entry, args, target, requested, max, previousEffect}, rest}:
          boundary_throw_job(vm, ThrowHandle{depth, previousEffect, rest, U32.is_eq(expected, depth)})
        case Con{M.HandleInitReturn{expected, effect}, rest}:
          boundary_throw_job(vm, ThrowInit{depth, effect, rest, U32.is_eq(expected, depth)})
        case Con{M.DynamicBootstrap{expected, method, pc, owner, constant, args}, rest}:
          boundary_throw_job(vm, ThrowDynamic{depth, rest, U32.is_eq(expected, depth)})
        # An exception escaping a callback discards the continuation awaiting it.
        case Con{M.HostCallback{expected}, Con{cont, rest}}:
          boundary_throw_job(vm, ThrowHost{depth, rest, U32.is_eq(expected, depth)})
        case Con{_, rest}: boundary_throw_job(vm, ThrowCont{depth, rest})
        case Nil{}: vm
    case ThrowHost{+depth, rest, True{}}:
      boundary_throw_job(S.with_cont(vm, rest), ThrowStart{depth})
    case ThrowHost{depth, rest, False{}}: vm
    case ThrowSame{+depth, M.LoaderCatch{}, rest, True{}}:
      loader_catch(class_not_found_thrown(vm), S.with_cont(vm, rest), depth)
    case ThrowSame{+depth, M.SerialCatch{}, rest, True{}}:
      +unwound : M.VM = S.with_cont(vm, rest)
      serial_catch(io_exception_thrown(unwound), unwound, depth)
    case ThrowSame{+depth, effect, rest, True{}}:
      boundary_throw_job(boundary_exception(S.with_cont(vm, rest), effect), ThrowStart{depth})
    case ThrowSame{depth, effect, rest, False{}}: vm
    case ThrowHandle{+depth, previousEffect, rest, True{}}:
      boundary_throw_job(S.with_effect(S.with_cont(vm, rest), previousEffect), ThrowStart{depth})
    case ThrowHandle{depth, previousEffect, rest, False{}}: vm
    case ThrowInit{+depth, effect, rest, True{}}:
      boundary_throw_job(S.with_effect(S.with_cont(vm, rest), effect), ThrowStart{depth})
    case ThrowInit{depth, effect, rest, False{}}: vm
    case ThrowDynamic{+depth, rest, True{}}:
      boundary_throw_job(dynamic_exception_wrap(vm), ThrowStart{depth})
    case ThrowDynamic{depth, rest, False{}}: vm

def boundary_throw(+vm: M.VM, depth: U32) -> M.VM:
  boundary_throw_job(vm, ThrowStart{depth})


def boundary_intrinsic_value(result: Result<&2, &2, String, M.VM>, updated: M.VM) -> M.VM:
  match result:
    case Done{vm}: vm
    case Fail{error}: S.fail(updated, error)

def intrinsic_value(+vm: M.VM, frame: M.Frame, value: Maybe<&2, M.Slot>, max: U32) -> Result<&2, &2, String, M.VM>:
  match value:
    case None{}:
      Done{S.commit(vm, S.advance(frame))}
    case Some{slot}:
      do Result<&2, &2, String, M.VM>:
        pushed : M.Frame <- F.push(S.advance(frame), slot, max)
        return S.commit(vm, pushed)
# A host continuation may finish, throw, suspend, or request another Java call.
@unsafe def boundary_intrinsic_return(+vm: M.VM, caller: M.Frame, result: Result<&2, &2, String, O.Outcome>) -> M.VM:
  match result:
    case Done{O.Returned{+updated, value}}: boundary_intrinsic_value(intrinsic_value(updated, caller, value, 65535), updated)
    case Done{O.Call{+updated, method, args}}: invoke_outcome(updated, method, args, caller)
    case Done{O.ThrownRef{+updated, reference}}: boundary_throw(S.with_status(S.with_exception(updated, reference), 6), M.length(M.Frame, S.frames(updated)))
    case Done{O.ThrownName{+updated, error}}: boundary_throw(ensure_throw(updated, error), M.length(M.Frame, S.frames(updated)))
    case Done{O.Suspend{updated, effect}}: S.with_effect(updated, effect)
    case Fail{error}: S.with_status(ensure_throw(vm, error), 6)


type InvokeJob is Data:
  JResult{caller: M.Frame, result: Result<&2, &2, String, O.Outcome>}
  JReceiverKind{method: M.LoadedMethod, caller: M.Frame, reference: U32, rest: +List<M.Slot>, kind: U32}
  JReceiverEntry{method: M.LoadedMethod, caller: M.Frame, reference: U32, rest: +List<M.Slot>, result: Result<&2, &2, String, M.HeapEntry>}
  JDispatchReceiver{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame}
  JIntrinsicReceiver{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame, kind: U32, objectMethod: Bool}
  JIntrinsicArgs{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame, kind: U32}
  JIntrinsicReceiverEntry{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame, kind: U32, receiverKind: U32}
  # A non-virtual (invokespecial) call: bytecode runs even on a proxy receiver.
  JDispatchExact{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame, kind: U32}
  JDispatchKind{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame, kind: U32}
  JDispatchBytecode{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame, isStatic: Bool}
  JDispatchIntrinsic{method: M.LoadedMethod, args: +List<M.Slot>, ready: M.VM, caller: M.Frame, kind: U32}
  JDispatch{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame}
  JBoundary{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame, effect: M.Effect}
  JOutcomeEffect{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame, effect: M.Effect}
  JOutcome{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame}
  JOutcomeRoute{method: M.LoadedMethod, args: +List<M.Slot>, caller: M.Frame, initializer: Bool}

def dispatched_vm(+vm: M.VM, result: Result<&2, &2, String, M.VM>) -> M.VM:
  match result:
    case Done{updated}: updated
    case Fail{error}: boundary_throw(ensure_throw(vm, error), M.length(M.Frame, S.frames(vm)))

# A call requested together with a NeedIntrinsicRetry/NeedClassMirror callback
# at the current depth is a <clinit>; it gets an initializer frame.
def initializer_request(conts: +List<M.Cont>, depth: U32) -> Bool:
  match conts:
    case Con{M.HostCallback{expected}, Con{M.NeedIntrinsicRetry{kind, args}, rest}}: U32.is_eq(expected, depth)
    case Con{M.HostCallback{expected}, Con{M.NeedClassMirror{target}, rest}}: U32.is_eq(expected, depth)
    case _: False{}

# An exception a MiniJRE intrinsic raises gets the intrinsic method as its
# innermost stack frame, as the JDK's own frame would be.
def native_thrown(+vm: M.VM, +method: U32, +error: String) -> O.Outcome:
  +thrown : M.VM = ensure_throw(S.with_exception(vm, 0), error)
  O.ThrownRef{Tr.with_native_frame(thrown, method), S.exception(thrown)}

def native_fault(java: Bool, +vm: M.VM, +method: U32, +error: String) -> Result<&2, &2, String, O.Outcome>:
  match java:
    case True{}: Done{native_thrown(vm, method, error)}
    case False{}: Fail{error}

def native_outcome(+vm: M.VM, +method: M.LoadedMethod, result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{+error}: native_fault(java_fault(error), vm, M.loaded_method_id(method), error)
    case Done{O.ThrownName{+updated, +name}}: Done{native_thrown(updated, M.loaded_method_id(method), name)}
    case Done{other}: Done{other}

@unsafe def invoke_job(+vm: M.VM, job: InvokeJob) -> M.VM:
  match job:
    case JResult{+caller, result}:
      match result:
        case Fail{error}: boundary_throw(ensure_throw(vm, error), M.length(M.Frame, S.frames(vm)))
        case Done{O.Returned{+updated, Some{value}}}:
          boundary_intrinsic_return(updated, caller, boundary_result(updated, value, M.length(M.Frame, S.frames(updated)), host_cont(updated)))
        case Done{O.Returned{+updated, None{}}}:
          boundary_intrinsic_return(updated, caller, boundary_result(updated, M.Slot{3, 0}, M.length(M.Frame, S.frames(updated)), host_cont(updated)))
        case Done{O.Call{+updated, method, args}}: invoke_job(updated, JOutcome{method, args, caller})
        case Done{O.ThrownRef{+updated, reference}}: boundary_throw(S.with_status(S.with_exception(updated, reference), 6), M.length(M.Frame, S.frames(updated)))
        case Done{O.ThrownName{+updated, error}}: boundary_throw(ensure_throw(updated, error), M.length(M.Frame, S.frames(updated)))
        case Done{O.Suspend{updated, effect}}: S.with_effect(updated, effect)
    case JReceiverKind{+method, caller, +reference, +rest, kind}:
      match kind:
        case 10: invoke_job(vm, JResult{caller, L.proxy_invoke(vm, method, Con{M.Slot{3, reference}, rest}, Sy.text(S.symbols(vm), M.loaded_method_name(method)), Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)))})
        # Annotation objects answer their members, equals/hashCode/toString and
        # annotationType natively, from callbacks as from bytecode calls.
        case 9: invoke_job(vm, JResult{caller, L.annotation_invoke(vm, Con{M.Slot{3, reference}, rest}, Sy.text(S.symbols(vm), M.loaded_method_name(method)), Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)))})
        case _: invoke_arguments(vm, method, F.Arguments{caller, Con{M.Slot{3, reference}, rest}}, S.frames(vm))
    case JReceiverEntry{+method, caller, +reference, +rest, result}:
      match result:
        case Done{entry}: invoke_job(vm, JReceiverKind{method, caller, reference, rest, L.entry_kind(entry)})
        case _: invoke_arguments(vm, method, F.Arguments{caller, Con{M.Slot{3, reference}, rest}}, S.frames(vm))
    case JDispatchExact{+method, +args, caller, kind}:
      match kind:
        case 0: invoke_arguments(vm, method, F.Arguments{caller, args}, S.frames(vm))
        case _: invoke_job(vm, JDispatch{method, args, caller})
    case JDispatchReceiver{+method, +args, caller}:
      match args:
        case Con{M.Slot{3, +reference}, rest}: invoke_job(vm, JReceiverEntry{method, caller, reference, rest, H.get(S.heap(vm), reference)})
        case _: invoke_arguments(vm, method, F.Arguments{caller, args}, S.frames(vm))
    case JDispatchKind{+method, +args, +caller, kind}:
      match kind:
        case 450: dispatched_vm(vm, lambda_dispatch_method(vm, method, F.Arguments{caller, args}, 65535))
        # Only instance methods dispatch on their receiver's proxy/annotation kind.
        case 0: invoke_job(vm, JDispatchBytecode{method, args, caller, U32.is_ne(U32.and(M.loaded_method_flags(method), 8), 0)})
        # Commit the caller (arguments already popped) so continuations resumed
        # by the intrinsic's result observe the real call-site frame.
        case _: invoke_job(vm, JIntrinsicReceiver{method, args, caller, kind, object_dispatched(Sy.text(S.symbols(vm), M.loaded_method_name(method)), M.loaded_method_flags(method))})
    # Object's toString/hashCode/equals on a proxy or annotation receiver are
    # answered by the proxy handler or the annotation, as in the JDK.
    case JIntrinsicReceiver{+method, +args, +caller, +kind, objectMethod}:
      match objectMethod:
        case False{}: invoke_job(vm, JDispatchIntrinsic{method, args, S.commit(vm, caller), caller, kind})
        case True{}: invoke_job(vm, JIntrinsicArgs{method, args, caller, kind})
    case JIntrinsicArgs{+method, +args, +caller, +kind}:
      match args:
        case Con{M.Slot{3, +reference}, rest}: invoke_job(vm, JIntrinsicReceiverEntry{method, Con{M.Slot{3, reference}, rest}, caller, kind, receiver_entry_kind(H.get(S.heap(vm), reference))})
        case _: invoke_job(vm, JDispatchIntrinsic{method, args, S.commit(vm, caller), caller, kind})
    case JIntrinsicReceiverEntry{+method, +args, +caller, +kind, receiverKind}:
      match receiverKind:
        case 9: invoke_job(vm, JResult{caller, L.annotation_invoke(vm, args, Sy.text(S.symbols(vm), M.loaded_method_name(method)), Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)))})
        case 10: invoke_job(vm, JResult{caller, L.proxy_invoke(vm, method, args, Sy.text(S.symbols(vm), M.loaded_method_name(method)), Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)))})
        case _: invoke_job(vm, JDispatchIntrinsic{method, args, S.commit(vm, caller), caller, kind})
    case JDispatchIntrinsic{+method, +args, +ready, caller, kind}: invoke_job(ready, JResult{caller, native_outcome(ready, method, I.execute_vm(kind, ready, args))})
    case JDispatchBytecode{+method, +args, caller, isStatic}:
      match isStatic:
        case True{}: invoke_arguments(vm, method, F.Arguments{caller, args}, S.frames(vm))
        case False{}: invoke_job(vm, JDispatchReceiver{method, args, caller})
    case JDispatch{+method, +args, caller}: invoke_job(vm, JDispatchKind{method, args, caller, method_intrinsic(method)})
    case JBoundary{+method, +args, caller, effect}: invoke_job(boundary_push(vm, effect, M.loaded_method_descriptor(method)), JDispatch{method, args, caller})
    case JOutcomeEffect{+method, +args, +caller, effect}:
      match effect:
        case M.ReflectConstructor{reference}: invoke_job(vm, JBoundary{method, args, caller, M.ReflectConstructor{reference}})
        case M.ReflectCall{}: invoke_job(vm, JBoundary{method, args, caller, M.ReflectCall{}})
        case M.PrivilegedCall{}: invoke_job(vm, JBoundary{method, args, caller, M.PrivilegedCall{}})
        case M.LoaderCatch{}: invoke_job(vm, JBoundary{method, args, caller, M.LoaderCatch{}})
        case M.LoaderSuper{name}: invoke_job(vm, JBoundary{method, args, caller, M.LoaderSuper{name}})
        case M.SerialCatch{}: invoke_job(vm, JBoundary{method, args, caller, M.SerialCatch{}})
        # Class.newInstance: return the new object; constructor exceptions pass through.
        case M.HandleConstructor{reference}: invoke_job(vm, JBoundary{method, args, caller, M.HandleConstructor{reference}})
        case M.ProxyCall{descriptor, method_id, owners}: invoke_job(vm, JBoundary{method, args, caller, S.host_effect(vm)})
        # Calls requested by intrinsics may target intrinsic or bytecode methods.
        case _: invoke_job(vm, JDispatch{method, args, caller})
    case JOutcome{+method, +args, caller}:
      invoke_job(vm, JOutcomeRoute{method, args, caller, initializer_request(host_cont(vm), M.length(M.Frame, S.frames(vm)))})
    case JOutcomeRoute{+method, +args, caller, True{}}: invoke_class_initializer(vm, method, args, caller)
    case JOutcomeRoute{+method, +args, caller, False{}}: invoke_job(vm, JOutcomeEffect{method, args, caller, S.host_effect(vm)})

def invoke_outcome(+vm: M.VM, method: M.LoadedMethod, +args: +List<M.Slot>, caller: M.Frame) -> M.VM:
  invoke_job(vm, JOutcome{method, args, caller})

# After a callback frame returns, its host continuation may request another
# call. Re-enter at the caller's original call site (recorded in the finished
# frame) so the new call returns into the same continuation chain.
def chained_call(+vm: M.VM, method: M.LoadedMethod, +args: +List<M.Slot>, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{current, Con{caller, callers}}:
      +site : M.Frame = S.frame_pc(caller, S.invoke_pc(current))
      invoke_outcome(S.with_frames(vm, Con{site, callers}), method, args, site)
    case _: S.fail(vm, "InvalidState: chained call without caller")


def intrinsic_outcome(frame: M.Frame, max: U32, outcome: O.Outcome) -> Result<&2, &2, String, M.VM>:
  match outcome:
    case O.Returned{updated, value}:
      intrinsic_value(updated, frame, value, max)
    case O.ThrownRef{updated, reference}:
      Done{S.with_status(S.with_exception(updated, reference), 6)}
    # The intrinsic's own state changes (a cleared interrupt flag, ...) stay.
    case O.ThrownName{+updated, name}:
      Done{S.with_status(ensure_throw(updated, name), 6)}
    case O.Suspend{updated, effect}:
      Done{S.commit(updated, frame)}
    case O.Call{+updated, method, args}:
      Done{invoke_outcome(updated, method, args, frame)}

def intrinsic_result(frame: M.Frame, max: U32, result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{outcome}:
      intrinsic_outcome(frame, max, outcome)
def initializer_invoke_pc(frames: +List<M.Frame>) -> U32:
  match frames:
    case Nil{}: 0
    case Con{caller, rest}: S.pc(caller)

# The trigger's frame is left unadvanced, so the instruction re-executes once
# <clinit> returns. invokePc is the trigger's pc: an exception escaping the
# initializer is matched against the trigger's handlers.
def initialize_retry_start(start: L.ClassForNameStart) -> Result<&2, &2, String, M.VM>:
  match start:
    case L.ClassForNameReady{vm}: Done{vm}
    # Another thread is initializing the class: block, then re-execute.
    case L.ClassForNameBlocked{+vm, class}: Done{S.with_status(Th.park(vm, M.InitWait{class}, False{}, M.Clock{0, 0}), 7)}
    case L.ClassForNameCall{+vm, +owner, +method}:
      +ready : M.VM = S.set_class_state(vm, owner, 1)
      +frames = S.frames(ready)
      Done{S.with_frames(ready, Con{M.Frame{M.loaded_method_id(method), 0, initializer_invoke_pc(frames), M.zeros(U32.to_nat(method_max_locals(method))), Nil{}, owner, 0}, frames})}
def initialize_retry(+vm: M.VM, target: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    start : L.ClassForNameStart <- L.class_for_name_walk(256n, vm, target)
    result : M.VM <- initialize_retry_start(start)
    return result


def intrinsic_args(+vm: M.VM, +method: M.LoadedMethod, args: F.Arguments, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, +values}:
      intrinsic_result(frame, max, native_outcome(vm, method, I.execute_vm(method_intrinsic(method), vm, values)))


def lambda_dispatch_result(+vm: M.VM, +frame: M.Frame, max: U32, result: Result<&2, &2, String, MH.LambdaDispatch>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{MH.LambdaDispatch{+updated, handle, +targetDescriptor, +instantiatedDescriptor, samDescriptor, +arguments}}:
      sam_adapter : M.VM = handle_boundary_push(updated, instantiatedDescriptor, samDescriptor)
      wrapped : M.VM = handle_boundary_push(sam_adapter, targetDescriptor, instantiatedDescriptor)
      invoke_handle_call(wrapped, frame, handle, arguments, targetDescriptor, True{}, max)

def lambda_dispatch_values(+vm: M.VM, method: M.LoadedMethod, frame: M.Frame, +values: +List<M.Slot>, max: U32) -> Result<&2, &2, String, M.VM>:
  match values:
    case Con{M.Slot{3, receiver}, target_args}:
      lambda_dispatch_result(vm, frame, max, MH.lambda_dispatch(vm, receiver, Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)), target_args))
    case Con{_, _}: Fail{"java/lang/IllegalArgumentException"}
    case Nil{}: Fail{"java/lang/IllegalArgumentException"}

def lambda_dispatch_method(+vm: M.VM, method: M.LoadedMethod, args: F.Arguments, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, +values}: lambda_dispatch_values(vm, method, frame, values, max)

def dispatch_intrinsic(+vm: M.VM, method: M.LoadedMethod, args: F.Arguments, intrinsic: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  match intrinsic:
    case 0: Done{invoke_arguments(vm, method, args, S.frames(vm))}
    case 450: lambda_dispatch_method(vm, method, args, max)
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

def invoke_signature_values(+vm: M.VM, +caller: M.Frame, +values: +List<M.Slot>, max: U32, exact: Bool, descriptor_text: String) -> Result<&2, &2, String, M.VM>:
  match values:
    case Con{M.Slot{3, reference}, target_args}:
      do Result<&2, &2, String, M.VM>:
        checked : Unit <- S.check(U32.is_ne(reference, 0), "java/lang/NullPointerException")
        result : M.VM <- invoke_handle_call(vm, caller, reference, target_args, descriptor_text, exact, max)
        return result
    case _: Fail{"java/lang/invoke/WrongMethodTypeException"}

def invoke_signature_arguments(+vm: M.VM, args: F.Arguments, max: U32, name_text: String, descriptor_text: String) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{+caller, +values}:
      invoke_signature_values(vm, caller, values, max, String.eq(name_text, "invokeExact"), descriptor_text)

def invoke_signature_polymorphic(+vm: M.VM, +frame: M.Frame, +name: U32, descriptor: U32, max: U32, name_text: String, +descriptor_text: String) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    parsed : M.Descriptor <- D.parse_method(descriptor_text)
    args : F.Arguments <- F.arguments(frame, U32.add(D.parameter_count(parsed), 1))
    result : M.VM <- invoke_signature_arguments(vm, args, max, name_text, descriptor_text)
    return result

# MethodHandle.invokeWithArguments spreads its array (or MiniJRE list) into a
# generic invocation, as asType(genericMethodType(n)).invokeExact(...) does.
def spread_container(+vm: M.VM, +container: U32) -> Result<&2, &2, String, +List<M.Slot>>:
  match container:
    case 0: Done{Nil{}}
    case +reference:
      do Result<&2, &2, String, +List<M.Slot>>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        +kind : U32 = L.entry_kind(entry)
        checked : Unit <- S.check(U32.is_eq(kind, 2) || U32.is_eq(kind, 5), "java/lang/IllegalArgumentException")
        return Bool.pick(+List<M.Slot>, U32.is_eq(kind, 5), M.take(M.Slot, L.entry_values(entry), U32.to_nat(L.entry_element(entry))), L.entry_values(entry))

def generic_descriptor(+count: Nat, +acc: String) -> String:
  match count:
    case 0n: "(" ++ acc ++ ")Ljava/lang/Object;"
    case 1n+p: generic_descriptor(p, acc ++ "Ljava/lang/Object;")

def invoke_with_arguments_values(+vm: M.VM, +caller: M.Frame, +values: +List<M.Slot>, max: U32) -> Result<&2, &2, String, M.VM>:
  match values:
    case Con{M.Slot{3, +handle}, Con{M.Slot{3, +container}, Nil{}}}:
      do Result<&2, &2, String, M.VM>:
        checked : Unit <- S.check(U32.is_ne(handle, 0), "java/lang/NullPointerException")
        +spread : +List<M.Slot> <- spread_container(vm, container)
        result : M.VM <- invoke_handle_call(vm, caller, handle, spread, generic_descriptor(U32.to_nat(M.length(M.Slot, spread)), ""), False{}, max)
        return result
    case _: Fail{"java/lang/invoke/WrongMethodTypeException"}

@unsafe def invoke_with_arguments(+vm: M.VM, +frame: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +args : F.Arguments <- F.arguments(frame, 2)
    result : M.VM <- invoke_with_arguments_split(vm, args, max)
    return result

def invoke_with_arguments_split(+vm: M.VM, args: F.Arguments, max: U32) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{+caller, +values}: invoke_with_arguments_values(vm, caller, values, max)

def handle_virtual_kind(+owner: String, +name: String) -> U32:
  +handle_owner : Bool = String.eq(owner, "java/lang/invoke/MethodHandle")
  Bool.pick(U32, handle_owner && (String.eq(name, "invoke") || String.eq(name, "invokeExact")), 1,
    Bool.pick(U32, handle_owner && String.eq(name, "invokeWithArguments"), 2, 0))

def invoke_virtual_kind(kind: U32, +vm: M.VM, +frame: M.Frame, +owner: U32, +name: U32, +descriptor: U32, +max: U32) -> Result<&2, &2, String, M.VM>:
  match kind:
    case 1: invoke_signature_polymorphic(vm, frame, name, descriptor, max, Sy.text(S.symbols(vm), name), Sy.text(S.symbols(vm), descriptor))
    case 2: invoke_with_arguments(vm, frame, max)
    case _: invoke_virtual_missing(virtual_method_stack(vm, frame, owner, name, descriptor), vm, frame, name, descriptor, max, Sy.text(S.symbols(vm), name), Sy.text(S.symbols(vm), descriptor))

def invoke_virtual(+vm: M.VM, +frame: M.Frame, +owner: U32, +name: U32, +descriptor: U32, +max: U32) -> Result<&2, &2, String, M.VM>:
  invoke_virtual_kind(handle_virtual_kind(Sy.text(S.symbols(vm), owner), Sy.text(S.symbols(vm), name)), vm, frame, owner, name, descriptor, max)
def invoke_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, frame: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchMethodError"}
    case Some{+method}:
      do Result<&2, &2, String, M.VM>:
        args : F.Arguments <- F.arguments(frame, method_parameters(method))
        result : M.VM <- dispatch_method(vm, method, args, max)
        return result

def invoke_static_ready(start: L.ClassForNameStart, +method: M.LoadedMethod, frame: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  match start:
    case L.ClassForNameReady{+vm}: invoke_found(Some{method}, vm, frame, max)
    case _: initialize_retry_start(start)

def invoke_static_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, frame: M.Frame, max: U32) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"java/lang/NoSuchMethodError"}
    case Some{+method}:
      do Result<&2, &2, String, M.VM>:
        start : L.ClassForNameStart <- L.class_for_name_walk(256n, vm, M.loaded_method_owner(method))
        result : M.VM <- invoke_static_ready(start, method, frame, max)
        return result

# invokestatic initializes the class that declares the resolved method.
def invoke_static(+vm: M.VM, frame: M.Frame, owner: U32, name: U32, descriptor: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  invoke_static_found(find_method(S.classes(vm), S.methods(vm), owner, name, descriptor), vm, frame, max)
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
      Fail{"java/lang/ArithmeticException: / by zero"}
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

def resolve_field_owner(found: Maybe<&2, U32>, +vm: M.VM, name: U32, descriptor: U32) -> Maybe<&2, M.LoadedField>:
  match found:
    case None{}: None{}
    case Some{id}: H.resolve_field(S.classes(vm), S.fields(vm), id, name, descriptor)

# Field references resolve per JVMS 5.4.3.2, so `Sub.inherited` finds the field
# declared by a superclass or superinterface.
def find_field_ref(+vm: M.VM, owner: U32, name: U32, descriptor: U32) -> Maybe<&2, M.LoadedField>:
  resolve_field_owner(class_id_by_name(S.classes(vm), owner), vm, name, descriptor)

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
        case Some{field}:
          entry = H.get(S.heap(vm), V.slot_bits(value))
          field_get_result(vm, popped, field, entry)
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
        case Some{field}:
          entry = H.get(S.heap(vm), V.slot_bits(object))
          putfield_result(vm, value, popped, field, entry)

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
def static_field(found: Maybe<&2, M.LoadedField>) -> Result<&2, &2, String, M.LoadedField>:
  match found:
    case None{}: Fail{"java/lang/NoSuchFieldError"}
    case Some{+field}:
      Bool.pick(Result<&2, &2, String, M.LoadedField>, U32.is_eq(U32.and(M.loaded_field_flags(field), 8), 0), Fail{"java/lang/IncompatibleClassChangeError: expected static field"}, Done{field})

def static_get_ready(start: L.ClassForNameStart, +frame: M.Frame, field: M.LoadedField) -> Result<&2, &2, String, M.VM>:
  match start:
    case L.ClassForNameReady{+vm}: static_get_found(vm, frame, Some{field})
    case _: initialize_retry_start(start)

# getstatic initializes the field's declaring class (JVMS 5.5), which is not
# necessarily the class named by the instruction.
def getstatic(+vm: M.VM, +frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +field : M.LoadedField <- static_field(find_field_ref(vm, owner, name, descriptor))
    start : L.ClassForNameStart <- L.class_for_name_walk(256n, vm, M.loaded_field_owner(field))
    result : M.VM <- static_get_ready(start, frame, field)
    return result

def static_put_value(+vm: M.VM, value: M.Slot, +popped: F.Popped, field: M.LoadedField) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{next, rest}: Done{S.commit(S.with_statics(vm, H.binding_set(S.statics(vm), M.loaded_field_id(field), value)), S.advance(next))}

def static_put_ready(start: L.ClassForNameStart, value: M.Slot, +popped: F.Popped, field: M.LoadedField) -> Result<&2, &2, String, M.VM>:
  match start:
    case L.ClassForNameReady{+vm}: static_put_value(vm, value, popped, field)
    case _: initialize_retry_start(start)

def putstatic_start(+vm: M.VM, +popped: F.Popped, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, +value}:
      do Result<&2, &2, String, M.VM>:
        +field : M.LoadedField <- static_field(find_field_ref(vm, owner, name, descriptor))
        start : L.ClassForNameStart <- L.class_for_name_walk(256n, vm, M.loaded_field_owner(field))
        result : M.VM <- static_put_ready(start, value, F.Popped{frame, value}, field)
        return result

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
      Bool.pick(+List<M.Binding>, Bool.and(is_instance, belongs), Con{M.Binding{M.loaded_field_id(field), M.default_slot(M.loaded_field_tag(field))}, tail}, tail)

def new_object_ready(start: L.ClassForNameStart, +frame: M.Frame, +id: U32) -> Result<&2, &2, String, M.VM>:
  match start:
    case L.ClassForNameReady{+vm}:
      fields = instance_fields(S.fields(vm), S.classes(vm), id)
      new_object_alloc(frame, H.allocate(vm, H.object_entry(id, fields)))
    case _: initialize_retry_start(start)

def new_object_found(found: Maybe<&2, M.LoadedClass>, +vm: M.VM, +frame: M.Frame) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"java/lang/NoClassDefFoundError"}
    case Some{value}:
      +id : U32 = M.loaded_class_id(value)
      do Result<&2, &2, String, M.VM>:
        start : L.ClassForNameStart <- L.class_for_name_walk(256n, vm, id)
        result : M.VM <- new_object_ready(start, frame, id)
        return result

def new_object(+vm: M.VM, +frame: M.Frame, name: U32) -> Result<&2, &2, String, M.VM>:
  new_object_found(class_found(class_id_by_name(S.classes(vm), name), S.classes(vm)), vm, frame)

def array_entry(kind: U32, id: U32, element: U32, +values: +List<M.Slot>) -> M.HeapEntry:
  match kind:
    case 1: H.primitive_array_entry(id, element, values)
    case _: H.reference_array_entry(id, element, values)

def array_default_slot(kind: U32, +element: U32, symbols: +List<String>) -> M.Slot:
  match kind:
    case 1:
      Bool.pick(M.Slot, U32.is_eq(element, 11), M.default_slot(4),
        Bool.pick(M.Slot, U32.is_eq(element, 7), M.default_slot(5),
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
      M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods} = value
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

type ReflectChildren is Data:
  ReflectChildren{vm: M.VM, refs: +List<U32>}

type CountsPopped is Data:
  CountsPopped{frame: M.Frame, counts: +List<U32>}

def array_type_of(component: String) -> String:
  match component:
    case SCon{Chr{91}, rest}: "[" ++ component
    case _: "[L" ++ component ++ ";"

def until_semicolon(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{59}, rest}: ""
    case SCon{c, rest}: SCon{c, until_semicolon(rest)}

# The component of an array class name: "[[I" -> "[I", "[LFoo;" -> "Foo", "[I" -> "I".
def array_component_text(name: String) -> String:
  match name:
    case SCon{Chr{91}, SCon{Chr{76}, rest}}: until_semicolon(rest)
    case SCon{Chr{91}, rest}: rest
    case other: other

def primitive_atype(descriptor: String) -> U32:
  match descriptor:
    case "Z": 4
    case "C": 5
    case "F": 6
    case "D": 7
    case "B": 8
    case "S": 9
    case "I": 10
    case "J": 11
    case _: 0

# A one-level array of `name` filled with `count` default elements.
def array_level_entry(+vm: M.VM, +name: String, count: U32, +values: +List<M.Slot>) -> M.HeapEntry:
  +class : U32 = H.named_class(S.classes(vm), S.symbols(vm), name)
  +component : String = array_component_text(name)
  +atype : U32 = primitive_atype(component)
  Bool.pick(M.HeapEntry, U32.is_ne(atype, 0) && Bool.not(String.starts_with(component, "[")),
    H.primitive_array_entry(class, atype, H.filled(U32.to_nat(count), array_default_slot(1, atype, S.symbols(vm)))),
    H.reference_array_entry(class, H.named_class(S.classes(vm), S.symbols(vm), component), values))

def anewarray_popped(+vm: M.VM, +name: String, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      do Result<&2, &2, String, M.VM>:
        +count : U32 = V.slot_bits(value)
        sized : Unit <- S.check(Bool.not(V.negative(count)), "java/lang/NegativeArraySizeException: " ++ U32.show(count))
        +ready : M.VM <- L.ensure_array_class(vm, name)
        result : M.VM <- new_object_alloc(next, H.allocate(ready, array_level_entry(ready, name, count, H.filled(U32.to_nat(count), M.Slot{3, 0}))))
        return result

# anewarray: the result's class is the array class of the operand (created on
# first use), and `element` records the component class.
def anewarray(+vm: M.VM, +frame: M.Frame, +component: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    text : String <- S.require(String, M.nth(String, S.symbols(vm), component), "InvalidConstant")
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- anewarray_popped(vm, array_type_of(text), popped)
    return result

type Built is Data:
  Built{vm: M.VM, reference: U32}

def built_slots(refs: +List<U32>) -> +List<M.Slot>:
  match refs:
    case Nil{}: Nil{}
    case Con{reference, rest}: Con{M.Slot{3, reference}, built_slots(rest)}

@unsafe def multi_level_alloc(allocation: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, Built>:
  match allocation:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{updated, reference}}: Done{Built{updated, reference}}

@unsafe def multi_children(fuel: Nat, +vm: M.VM, +name: String, +counts: +List<U32>, +acc: +List<U32>) -> Result<&2, &2, String, ReflectChildren>:
  match fuel:
    case 0n: Done{ReflectChildren{vm, M.reverse(U32, acc)}}
    case 1n+p: multi_child_next(multi_build(vm, name, counts), p, name, counts, acc)

@unsafe def multi_child_next(built: Result<&2, &2, String, Built>, fuel: Nat, +name: String, +counts: +List<U32>, +acc: +List<U32>) -> Result<&2, &2, String, ReflectChildren>:
  match built:
    case Fail{error}: Fail{error}
    case Done{Built{next, reference}}: multi_children(fuel, next, name, counts, Con{reference, acc})

@unsafe def multi_outer(children: Result<&2, &2, String, ReflectChildren>, +name: String, count: U32) -> Result<&2, &2, String, Built>:
  match children:
    case Fail{error}: Fail{error}
    case Done{ReflectChildren{+vm, refs}}: multi_level_alloc(H.allocate(vm, array_level_entry(vm, name, count, built_slots(refs))))

# multianewarray (JVMS 6.5): one array per counted dimension; a zero count
# stops allocation of the dimensions below it.
@unsafe def multi_build(+vm: M.VM, +name: String, +counts: +List<U32>) -> Result<&2, &2, String, Built>:
  match counts:
    case Nil{}: Fail{"InvalidState: multianewarray without dimensions"}
    case Con{count, Nil{}}: multi_level_alloc(H.allocate(vm, array_level_entry(vm, name, count, H.filled(U32.to_nat(count), M.Slot{3, 0}))))
    case Con{count, rest}: multi_outer(multi_children(U32.to_nat(count), vm, array_component_text(name), rest, Nil{}), name, count)

@unsafe def pop_counts(fuel: Nat, frame: M.Frame, +acc: +List<U32>) -> Result<&2, &2, String, CountsPopped>:
  match fuel:
    case 0n: Done{CountsPopped{frame, acc}}
    case 1n+p: pop_counts_next(F.pop(frame, 1), p, acc)

@unsafe def pop_counts_next(popped: Result<&2, &2, String, F.Popped>, fuel: Nat, +acc: +List<U32>) -> Result<&2, &2, String, CountsPopped>:
  match popped:
    case Fail{error}: Fail{error}
    case Done{F.Popped{next, value}}: pop_counts(fuel, next, Con{V.slot_bits(value), acc})

def any_negative(counts: +List<U32>) -> Bool:
  match counts:
    case Nil{}: False{}
    case Con{count, rest}: V.negative(count) || any_negative(rest)

def multianewarray_built(+frame: M.Frame, built: Built) -> Result<&2, &2, String, M.VM>:
  match built:
    case Built{vm, reference}: Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{3, reference}, S.stack(frame)}))}

def multianewarray_counts(+vm: M.VM, +name: String, popped: CountsPopped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case CountsPopped{+frame, +counts}:
      do Result<&2, &2, String, M.VM>:
        sized : Unit <- S.check(Bool.not(any_negative(counts)), "java/lang/NegativeArraySizeException")
        +ready : M.VM <- L.ensure_array_class(vm, name)
        built : Built <- multi_build(ready, name, counts)
        result : M.VM <- multianewarray_built(frame, built)
        return result

def multianewarray(+vm: M.VM, +frame: M.Frame, +type_name: U32, +dimensions: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    text : String <- S.require(String, M.nth(String, S.symbols(vm), type_name), "InvalidConstant")
    popped : CountsPopped <- pop_counts(U32.to_nat(dimensions), frame, Nil{})
    result : M.VM <- multianewarray_counts(vm, text, popped)
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
    case F.Popped{next, +value}:
      entry = H.get(S.heap(vm), V.slot_bits(value))
      array_length_loaded(vm, popped, entry)

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

def ensure_target_class(+vm: M.VM, found: Maybe<&2, String>) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Done{vm}
    case Some{+name}: L.ensure_array_class(vm, name)

# instanceof/checkcast against an array type create that array class first, so
# the test is structural (JVMS 6.5 checkcast) rather than "class not loaded".
def ref_test(+vm: M.VM, frame: M.Frame, +target: U32, cast: Bool) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +ready : M.VM <- ensure_target_class(vm, M.nth(String, S.symbols(vm), target))
    popped : F.Popped <- F.pop(frame, 0)
    result : M.VM <- ref_test_popped(ready, popped, target, cast)
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

# Array opcodes pass a value category (1 int, 2 reference, 3 float store,
# 4 long, 5 double); every primitive array lives in heap kind 1.
def array_heap_kind(expected: U32) -> U32:
  match expected:
    case 2: 2
    case _: 1

def reference_component_found(found: Maybe<&2, U32>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{id}: id

# Reference arrays record their component class id in `element`.
def reference_component_id(classes: +List<M.LoadedClass>, element: U32) -> U32:
  element

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
            checked_kind : Unit <- S.check(U32.is_eq(kind, array_heap_kind(expected)), "ArrayTypeMismatch")
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
            checked_kind : Unit <- S.check(U32.is_eq(kind, array_heap_kind(expected)), "ArrayTypeMismatch")
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

def class_pool_for_frame_owner(+pool: +List<M.Constant>, owner: U32, metadata_owner: U32) -> Result<&2, &2, String, +List<M.Constant>>:
  do Result<&2, &2, String, +List<M.Constant>>:
    checked : Unit <- S.check(U32.is_eq(owner, metadata_owner), "InvalidState: class metadata owner")
    return pool

def class_pool_for_frame_class(found: Maybe<&2, M.ClassMetadata>, owner: U32) -> Result<&2, &2, String, +List<M.Constant>>:
  match found:
    case None{}: Fail{"InvalidState: class metadata"}
    case Some{M.ClassMetadata{metadata_owner, flags, annotations, visible, +pool, signature, nesting, source}}:
      class_pool_for_frame_owner(pool, owner, metadata_owner)

def class_pool_for_frame_metadata(metadata: M.Metadata, +owner: U32) -> Result<&2, &2, String, +List<M.Constant>>:
  match metadata:
    case M.Metadata{classes, fields, methods}:
      class_pool_for_frame_class(M.nth(M.ClassMetadata, classes, owner), owner)

def class_pool_for_frame_method(+vm: M.VM, method: M.LoadedMethod) -> Result<&2, &2, String, +List<M.Constant>>:
  class_pool_for_frame_metadata(S.metadata(vm), M.loaded_method_owner(method))

def class_pool_for_frame(+vm: M.VM, frame: M.Frame) -> Result<&2, &2, String, +List<M.Constant>>:
  do Result<&2, &2, String, +List<M.Constant>>:
    method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)), "InvalidState: constant pool owner")
    pool : +List<M.Constant> <- class_pool_for_frame_method(vm, method)
    return pool

def literal_handle_field_access(+vm: M.VM, caller: U32, +kind: U32, +field: M.LoadedField) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    is_static : Bool = U32.is_ne(U32.and(M.loaded_field_flags(field), 8), 0)
    expected_static : Bool = U32.is_eq(kind, 2) || U32.is_eq(kind, 4)
    checked : Unit <- S.check(U32.is_eq(Bool.to_u32(is_static), Bool.to_u32(expected_static)), "IncompatibleClassChangeError")
    checked : Unit <- S.check(L.member_accessible(vm, caller, M.loaded_field_owner(field), M.loaded_field_flags(field)), "java/lang/IllegalAccessError")
    return Unit{}

def literal_handle_method_kind(+vm: M.VM, kind: U32, +method: M.LoadedMethod) -> Result<&2, &2, String, Unit>:
  match kind:
    case 8:
      S.check(String.eq(Sy.text(S.symbols(vm), M.loaded_method_name(method)), "<init>") &&
        String.ends_with(Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)), ")V"), "NoSuchMethodError")
    case _:
      S.check(Bool.not(String.eq(Sy.text(S.symbols(vm), M.loaded_method_name(method)), "<init>")), "NoSuchMethodError")

def handle_method_access(+vm: M.VM, caller: U32, +kind: U32, +method: M.LoadedMethod) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    is_static : Bool = U32.is_ne(U32.and(M.loaded_method_flags(method), 8), 0)
    checked : Unit <- S.check(Bool.pick(Bool, is_static, U32.is_eq(kind, 6), U32.is_ne(kind, 6)), "IncompatibleClassChangeError")
    checked : Unit <- S.check(L.member_accessible(vm, caller, M.loaded_method_owner(method), M.loaded_method_flags(method)), "java/lang/IllegalAccessError")
    result : Unit <- literal_handle_method_kind(vm, kind, method)
    return result

def literal_method_varargs_found(found: Maybe<&2, M.LoadedMethod>) -> Bool:
  match found:
    case None{}: False{}
    case Some{method}: U32.is_ne(U32.and(M.loaded_method_flags(method), 128), 0)

def literal_method_varargs_owner(found: Maybe<&2, M.LoadedClass>, +vm: M.VM, name: U32, descriptor: U32) -> Bool:
  match found:
    case None{}: False{}
    case Some{owner_class}:
      literal_method_varargs_found(find_method(S.classes(vm), S.methods(vm), M.loaded_class_name(owner_class), name, descriptor))

def literal_method_varargs(+vm: M.VM, owner: U32, name: U32, descriptor: U32) -> Bool:
  literal_method_varargs_owner(M.nth(M.LoadedClass, S.classes(vm), owner), vm, name, descriptor)

def literal_method_handle_field(+vm: M.VM, caller: U32, kind: U32, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    field : M.LoadedField <- S.require(M.LoadedField, H.resolve_field(S.classes(vm), S.fields(vm), owner, name, descriptor), "NoSuchFieldError")
    checked : Unit <- literal_handle_field_access(vm, caller, kind, field)
    return Unit{}

def literal_method_handle_method(+vm: M.VM, caller: U32, kind: U32, owner_name: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    method : M.LoadedMethod <- S.require(M.LoadedMethod, find_method(S.classes(vm), S.methods(vm), owner_name, name, descriptor), "NoSuchMethodError")
    checked : Unit <- handle_method_access(vm, caller, kind, method)
    return Unit{}

def literal_method_handle_validate(+vm: M.VM, caller: U32, +kind: U32, owner: U32, owner_name: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, Unit>:
  match kind:
    case 1: literal_method_handle_field(vm, caller, kind, owner, name, descriptor)
    case 2: literal_method_handle_field(vm, caller, kind, owner, name, descriptor)
    case 3: literal_method_handle_field(vm, caller, kind, owner, name, descriptor)
    case 4: literal_method_handle_field(vm, caller, kind, owner, name, descriptor)
    case _: literal_method_handle_method(vm, caller, kind, owner_name, name, descriptor)
def literal_method_handle_entry(+vm: M.VM, +frame: M.Frame, pool: +List<M.Constant>, index: U32, +kind: U32, reference: U32) -> Result<&2, &2, String, H.Allocation>:
  do Result<&2, &2, String, H.Allocation>:
    +member : CP.Member <- CP.member(pool, reference)
    +owner_text : String = CP.member_owner(member)
    name_text : String = CP.member_name(member)
    descriptor_text : String = CP.member_descriptor(member)
    owner_name : U32 = Sy.find(S.symbols(vm), owner_text)
    +name : U32 = Sy.find(S.symbols(vm), name_text)
    +descriptor : U32 = Sy.find(S.symbols(vm), descriptor_text)
    +owner : U32 = H.named_class(S.classes(vm), S.symbols(vm), owner_text)
    caller_method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)), "InvalidState: method handle caller")
    +caller_owner : U32 = M.loaded_method_owner(caller_method)
    checked : Unit <- S.check(U32.is_ne(owner, 4294967295), "NoClassDefFoundError")
    checked : Unit <- literal_method_handle_validate(vm, caller_owner, kind, owner, owner_name, name, descriptor)
    special : U32 = Bool.pick(U32, U32.is_eq(kind, 7), caller_owner, 4294967295)
    class : U32 = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/invoke/MethodHandle")
    +handle : M.HeapEntry = MH.handle_entry(class, kind, owner, name, descriptor, special)
    varargs : Bool = literal_method_varargs(vm, owner, name, descriptor)
    fields : +List<M.Binding> = H.binding_set(L.entry_fields(handle), 4294967295, M.Slot{1, Bool.pick(U32, varargs, 1, 0)})
    updated : M.HeapEntry = M.HeapEntry{H.entry_class(handle), L.entry_kind(handle), L.entry_element(handle), fields, L.entry_values(handle), L.entry_chars(handle)}
    allocation : H.Allocation <- H.allocate(vm, updated)
    return allocation

def literal_method_handle_result(+vm: M.VM, +frame: M.Frame, max: U32, result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{allocation}: new_object_alloc(frame, Done{allocation})

def literal_method_handle_constant(+vm: M.VM, +frame: M.Frame, +pool: +List<M.Constant>, index: U32, max: U32, constant: M.Constant) -> Result<&2, &2, String, M.VM>:
  match constant:
    case M.PairIndex{15, kind, reference}:
      literal_method_handle_result(vm, frame, max, literal_method_handle_entry(vm, frame, pool, index, kind, reference))
    case _: Fail{"VmError.InvalidConstantPool: expected MethodHandle"}

def literal_method_handle(+vm: M.VM, +frame: M.Frame, +index: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +pool : +List<M.Constant> <- class_pool_for_frame(vm, frame)
    constant : M.Constant <- CP.get(pool, index)
    result : M.VM <- literal_method_handle_constant(vm, frame, pool, index, max, constant)
    return result

def literal_method_type_result(+frame: M.Frame, max: U32, result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{O.Returned{updated, Some{M.Slot{3, reference}}}}:
      do Result<&2, &2, String, M.VM>:
        pushed : M.Frame <- F.push(S.advance(frame), M.Slot{3, reference}, max)
        return S.commit(updated, pushed)
    case Done{O.Returned{updated, _}}: Fail{"InvalidState: MethodType allocation"}
    case _: Fail{"InvalidState: MethodType allocation"}

def literal_method_type_descriptor(+vm: M.VM, +frame: M.Frame, max: U32, result: Result<&2, &2, String, String>) -> Result<&2, &2, String, M.VM>:
  match result:
    case Fail{error}: Fail{error}
    case Done{descriptor}: literal_method_type_result(frame, max, MH.alloc_type(vm, descriptor))

def literal_method_type_constant(+vm: M.VM, +frame: M.Frame, +pool: +List<M.Constant>, max: U32, constant: M.Constant) -> Result<&2, &2, String, M.VM>:
  match constant:
    case M.Index{16, descriptor_index}:
      literal_method_type_descriptor(vm, frame, max, CP.utf(pool, descriptor_index))
    case _: Fail{"VmError.InvalidConstantPool: expected MethodType"}

def literal_method_type(+vm: M.VM, +frame: M.Frame, +index: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +pool : +List<M.Constant> <- class_pool_for_frame(vm, frame)
    constant : M.Constant <- CP.get(pool, index)
    result : M.VM <- literal_method_type_constant(vm, frame, pool, max, constant)
    return result
def literal_class_found(+vm: M.VM, +frame: M.Frame, class: U32, target: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, M.VM>:
  match found:
    case Some{reference}:
      Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{3, reference}, S.stack(frame)}))}
    case None{}:
      new_object_alloc(frame, H.allocate(vm, H.class_mirror_entry(class, target)))
def literal_class(+vm0: M.VM, +frame: M.Frame, +targetName: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +target_text : String <- S.require(String, M.nth(String, S.symbols(vm0), targetName), "InvalidConstant")
    +vm : M.VM <- L.ensure_array_class(vm0, target_text)
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

def wide_read(+tag: U32, slot: M.Slot) -> Result<&2, &2, String, W.Words>:
  match slot:
    case M.Wide{actual, high, low}:
      do Result<&2, &2, String, W.Words>:
        valid_tag : Unit <- S.check(U32.is_eq(actual, tag), "InvalidWideValue")
        return W.Words{high, low}
    case _: Fail{"InvalidWideValue"}

def wide_push_words(+vm: M.VM, +frame: M.Frame, tag: U32, max: U32, value: W.Words) -> Result<&2, &2, String, M.VM>:
  match value:
    case W.Words{high, low}:
      do Result<&2, &2, String, M.VM>:
        +pushed : M.Frame <- F.push(S.advance(frame), M.Wide{tag, high, low}, max)
        return S.commit(vm, S.frame_stack(pushed, S.stack(pushed)))

def wide_constant(+vm: M.VM, +frame: M.Frame, high: U32, low: U32, +tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  wide_push_words(vm, frame, tag, max, W.Words{high, low})

def wide_long_binary(op: U32, left: W.Words, right: W.Words) -> Result<&2, &2, String, W.Words>:
  match op:
    case 97: Done{W.add(left, right)}
    case 101: Done{W.sub(left, right)}
    case 105: Done{W.mul(left, right)}
    case 109: Done{W.signed_divide(left, right)}
    case 113: Done{W.signed_remainder(left, right)}
    case 127: Done{W.bit_and(left, right)}
    case 129: Done{W.bit_or(left, right)}
    case 131: Done{W.bit_xor(left, right)}
    case _: Fail{"InvalidWideOpcode"}

def wide_double_binary(op: U32, left: W.Words, right: W.Words) -> Result<&2, &2, String, W.Words>:
  match op:
    case 99: Done{B64.add(left, right)}
    case 103: Done{B64.sub(left, right)}
    case 107: Done{B64.multiply(left, right)}
    case 111: Done{B64.div(left, right)}
    case 115: Done{B64.rem(left, right)}
    case _: Fail{"InvalidWideOpcode"}

def wide_binary_tag(tag: U32, op: U32, left: W.Words, right: W.Words) -> Result<&2, &2, String, W.Words>:
  match tag:
    case 4: wide_long_binary(op, left, right)
    case 5: wide_double_binary(op, left, right)
    case _: Fail{"InvalidWideOpcode"}

def wide_binary_value(op: U32, tag: U32, left: W.Words, right: W.Words) -> Result<&2, &2, String, W.Words>:
  wide_binary_tag(tag, op, left, right)

def wide_binary_finish(+vm: M.VM, +op: U32, +tag: U32, first_value: M.Slot, second: F.Popped, max: U32) -> Result<&2, &2, String, M.VM>:
  match second:
    case F.Popped{+second_frame, second_value}:
      do Result<&2, &2, String, M.VM>:
        +right : W.Words <- wide_read(tag, first_value)
        left : W.Words <- wide_read(tag, second_value)
        divide_by_zero : Bool = U32.is_eq(tag, 4) && (U32.is_eq(op, 109) || U32.is_eq(op, 113)) && W.long_zero(right)
        valid_divisor : Unit <- S.check(Bool.not(divide_by_zero), "java/lang/ArithmeticException: / by zero")
        result : W.Words <- wide_binary_value(op, tag, left, right)
        output : M.VM <- wide_push_words(vm, second_frame, tag, max, result)
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

# lshl/lshr/lushr pop an int distance above a long value (JVMS 6.5); the
# distance is masked to six bits by the shift kernels.
def wide_shift_value(op: U32, value: W.Words, distance: U32) -> W.Words:
  match op:
    case 121: W.shl(value, distance)
    case 123: W.sar(value, distance)
    case _: W.shr(value, distance)

def wide_shift_finish(+vm: M.VM, op: U32, distance: M.Slot, popped: F.Popped, max: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      do Result<&2, &2, String, M.VM>:
        words : W.Words <- wide_read(4, value)
        output : M.VM <- wide_push_words(vm, next, 4, max, wide_shift_value(op, words, V.slot_bits(distance)))
        return output

def wide_shift_distance(+vm: M.VM, op: U32, max: U32, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{frame, distance}:
      do Result<&2, &2, String, M.VM>:
        value : F.Popped <- F.pop(frame, 4)
        result : M.VM <- wide_shift_finish(vm, op, distance, value, max)
        return result

def wide_shift(frame: M.Frame, vm: M.VM, op: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- wide_shift_distance(vm, op, max, popped)
    return result

def wide_unary_value(tag: U32, value: W.Words) -> Result<&2, &2, String, W.Words>:
  match tag:
    case 4: Done{W.neg(value)}
    case 5: Done{B64.neg(value)}
    case _: Fail{"InvalidWideType"}

def wide_unary_finish(+vm: M.VM, popped: F.Popped, +tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      do Result<&2, &2, String, M.VM>:
        words : W.Words <- wide_read(tag, value)
        result : W.Words <- wide_unary_value(tag, words)
        output : M.VM <- wide_push_words(vm, next, tag, max, result)
        return output

def wide_unary(+vm: M.VM, frame: M.Frame, +tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, tag)
    result : M.VM <- wide_unary_finish(vm, popped, tag, max)
    return result

def wide_compare_value(op: U32, left: W.Words, right: W.Words) -> U32:
  match op:
    case 148: W.long_cmp(left, right)
    case 151: B64.cmpg(left, right)
    case _: B64.cmpl(left, right)

def wide_compare_finish(+vm: M.VM, op: U32, +tag: U32, first_value: M.Slot, second: F.Popped, max: U32) -> Result<&2, &2, String, M.VM>:
  match second:
    case F.Popped{+second_frame, second_value}:
      do Result<&2, &2, String, M.VM>:
        right : W.Words <- wide_read(tag, first_value)
        left : W.Words <- wide_read(tag, second_value)
        result : U32 = wide_compare_value(op, left, right)
        +pushed : M.Frame <- F.push(S.advance(second_frame), M.Slot{1, result}, max)
        return S.commit(vm, S.frame_stack(pushed, S.stack(pushed)))

def wide_compare_start(vm: M.VM, op: U32, +tag: U32, first: F.Popped, max: U32) -> Result<&2, &2, String, M.VM>:
  match first:
    case F.Popped{first_frame, first_value}:
      do Result<&2, &2, String, M.VM>:
        second : F.Popped <- F.pop(first_frame, tag)
        result : M.VM <- wide_compare_finish(vm, op, tag, first_value, second, max)
        return result

def wide_compare(+frame: M.Frame, vm: M.VM, +op: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  +tag : U32 = Bool.pick(U32, U32.is_eq(op, 148), 4, 5)
  do Result<&2, &2, String, M.VM>:
    first : F.Popped <- F.pop(frame, tag)
    result : M.VM <- wide_compare_start(vm, op, tag, first, max)
    return result

def wide_slot(tag: U32, value: W.Words) -> M.Slot:
  match value:
    case W.Words{high, low}: M.Wide{tag, high, low}

def convert_integer_opcode(op: U32, bits: U32) -> Result<&2, &2, String, M.Slot>:
  match op:
    case 133: Done{wide_slot(4, W.int_to_long(bits))}
    case 134: Done{M.Slot{2, V.int_float(bits)}}
    case 135: Done{wide_slot(5, B64.int_to_double(bits))}
    case _: Fail{"InvalidConversion"}

def convert_integer_source(op: U32, actual: U32, bits: U32) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    valid : Unit <- S.check(U32.is_eq(actual, 1), "InvalidState: integer conversion source")
    converted : M.Slot <- convert_integer_opcode(op, bits)
    return converted

def convert_integer_value(op: U32, value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  match value:
    case M.Slot{actual, bits}: convert_integer_source(op, actual, bits)
    case _: Fail{"InvalidConversionSource"}

def convert_float_opcode(op: U32, bits: U32) -> Result<&2, &2, String, M.Slot>:
  match op:
    case 139: Done{M.Slot{1, V.float_int(bits)}}
    case 140: Done{wide_slot(4, B64.float_to_long(bits))}
    case 141: Done{wide_slot(5, B64.f32_bits_to_double(bits))}
    case _: Fail{"InvalidConversion"}

def convert_float_source(op: U32, actual: U32, bits: U32) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    valid : Unit <- S.check(U32.is_eq(actual, 2), "InvalidState: float conversion source")
    converted : M.Slot <- convert_float_opcode(op, bits)
    return converted

def convert_float_value(op: U32, value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  match value:
    case M.Slot{actual, bits}: convert_float_source(op, actual, bits)
    case _: Fail{"InvalidConversionSource"}

def convert_long_opcode(op: U32, words: W.Words) -> Result<&2, &2, String, M.Slot>:
  match op:
    case 136: Done{M.Slot{1, W.long_to_int(words)}}
    case 137: Done{M.Slot{2, B64.long_to_float(words)}}
    case 138: Done{wide_slot(5, B64.long_to_double(words))}
    case _: Fail{"InvalidConversion"}

def convert_long_value(op: U32, value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    words : W.Words <- wide_read(4, value)
    converted : M.Slot <- convert_long_opcode(op, words)
    return converted

def convert_double_opcode(op: U32, words: W.Words) -> Result<&2, &2, String, M.Slot>:
  match op:
    case 142: Done{M.Slot{1, B64.double_to_int(words)}}
    case 143: Done{wide_slot(4, B64.double_to_long(words))}
    case 144: Done{M.Slot{2, B64.double_to_f32(words)}}
    case _: Fail{"InvalidConversion"}

def convert_double_value(op: U32, value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  do Result<&2, &2, String, M.Slot>:
    words : W.Words <- wide_read(5, value)
    converted : M.Slot <- convert_double_opcode(op, words)
    return converted

def convert_numeric_value(op: U32, value: M.Slot) -> Result<&2, &2, String, M.Slot>:
  match op:
    case 133: convert_integer_value(op, value)
    case 134: convert_integer_value(op, value)
    case 135: convert_integer_value(op, value)
    case 136: convert_long_value(op, value)
    case 137: convert_long_value(op, value)
    case 138: convert_long_value(op, value)
    case 139: convert_float_value(op, value)
    case 140: convert_float_value(op, value)
    case 141: convert_float_value(op, value)
    case 142: convert_double_value(op, value)
    case 143: convert_double_value(op, value)
    case 144: convert_double_value(op, value)
    case _: Fail{"InvalidConversion"}

def conversion_source(op: U32) -> U32:
  match op:
    case 133: 1
    case 134: 1
    case 135: 1
    case 136: 4
    case 137: 4
    case 138: 4
    case 139: 2
    case 140: 2
    case 141: 2
    case 142: 5
    case 143: 5
    case 144: 5
    case _: 0

def convert_numeric_finish(+vm: M.VM, op: U32, popped: F.Popped, max: U32) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}:
      do Result<&2, &2, String, M.VM>:
        converted : M.Slot <- convert_numeric_value(op, value)
        +pushed : M.Frame <- F.push(S.advance(next), converted, max)
        return S.commit(vm, S.frame_stack(pushed, S.stack(pushed)))

def convert_numeric(+vm: M.VM, +frame: M.Frame, +op: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +source : U32 = conversion_source(op)
    valid : Unit <- S.check(U32.is_ne(source, 0), "InvalidConversion")
    popped : F.Popped <- F.pop(frame, source)
    result : M.VM <- convert_numeric_finish(vm, op, popped, max)
    return result

def constant_push(+vm: M.VM, +frame: M.Frame, value: U32, tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +pushed : M.Frame <- F.push(frame, M.Slot{tag, value}, max)
    return S.commit(vm, S.frame_stack(S.advance(pushed), S.stack(pushed)))

def literal_push(+vm: M.VM, +frame: M.Frame, value: U32, tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  match tag:
    case 3: literal_string(vm, frame, value)
    case 4: literal_class(vm, frame, value)
    case 6: literal_method_handle(vm, frame, value, max)
    case 7: literal_method_type(vm, frame, value, max)
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

def stack_instruction(+vm: M.VM, +frame: M.Frame, op: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    updated : M.Frame <- F.stack_op(frame, op, max)
    return S.commit(vm, updated)

def method_switches(value: M.LoadedMethod) -> +List<M.SwitchTable>:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}: switches

type LookupSwitchWork is Data:
  LookupSwitchScan{key: U32, keys: +List<U32>, targets: +List<U32>, default: U32}
  LookupSwitchCompare{key: U32, candidate: U32, target: U32, keys: +List<U32>, targets: +List<U32>, default: U32, equal: Bool}
  LookupSwitchOrder{key: U32, keys: +List<U32>, targets: +List<U32>, default: U32, less: Bool}

@unsafe def lookup_switch_work(work: LookupSwitchWork) -> Result<&2, &2, String, U32>:
  match work:
    case LookupSwitchScan{+key, +keys, +targets, default}:
      match keys targets:
        case Nil{} Nil{}: Done{default}
        case Con{candidate, key_tail} Con{target, target_tail}:
          lookup_switch_work(LookupSwitchCompare{key, candidate, target, key_tail, target_tail, default, U32.is_eq(key, candidate)})
        case _ _:
          Fail{"InvalidState: malformed lookupswitch table"}
    case LookupSwitchCompare{+key, +candidate, target, +keys, +targets, default, equal}:
      match equal:
        case True{}: Done{target}
        case False{}:
          lookup_switch_work(LookupSwitchOrder{key, keys, targets, default, V.signed_lt(key, candidate)})
    case LookupSwitchOrder{key, +keys, +targets, default, less}:
      match less:
        case True{}: Done{default}
        case False{}:
          lookup_switch_work(LookupSwitchScan{key, keys, targets, default})

def lookup_switch_target(key: U32, +keys: +List<U32>, +targets: +List<U32>, default: U32) -> Result<&2, &2, String, U32>:
  lookup_switch_work(LookupSwitchScan{key, keys, targets, default})

def switch_table_dense_range(key: U32, low: U32, high: U32, default: U32, +targets: +List<U32>, out_of_range: Bool) -> Result<&2, &2, String, U32>:
  match out_of_range:
    case True{}: Done{default}
    case False{}: S.require(U32, M.nth(U32, targets, U32.sub(key, low)), "InvalidState: malformed tableswitch table")

def switch_table_target(+key: U32, +default: U32, table: M.SwitchTable) -> Result<&2, &2, String, U32>:
  match table:
    case M.SwitchTable{170, +low, +high, +keys, +targets}:
      switch_table_dense_range(key, low, high, default, targets, V.signed_lt(key, low) || V.signed_lt(high, key))
    case M.SwitchTable{171, low, high, +keys, +targets}:
      lookup_switch_target(key, keys, targets, default)
    case _:
      Fail{"InvalidState: malformed switch kind"}

def switch_step_popped(+vm: M.VM, table: M.SwitchTable, default: U32, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, key}:
      do Result<&2, &2, String, M.VM>:
        target : U32 <- switch_table_target(V.slot_bits(key), default, table)
        return S.commit(vm, S.frame_pc(next, target))

def switch_step(+vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod, default: U32, index: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    table : M.SwitchTable <- S.require(M.SwitchTable, M.nth(M.SwitchTable, method_switches(method), index), "InvalidState: switch table index")
    popped : F.Popped <- F.pop(frame, 1)
    result : M.VM <- switch_step_popped(vm, table, default, popped)
    return result

# A synchronized method's return releases its entry lock (JVMS 6.5 *return):
# returning without owning it throws IllegalMonitorStateException.
def return_release(+vm: M.VM, +lock: U32) -> Result<&2, &2, String, M.VM>:
  match lock:
    case 0: Done{vm}
    case _: Th.exit(vm, lock)

def monitor_entered(entered: Maybe<&2, M.VM>, +vm: M.VM, +frame: M.Frame, +next: M.Frame, +object: U32) -> Result<&2, &2, String, M.VM>:
  match entered:
    case Some{+owned}: Done{S.commit(owned, S.advance(next))}
    # Contended: park until the owner releases, then re-execute monitorenter.
    case None{}: Done{S.with_status(Th.park(vm, M.EnterMonitor{object}, False{}, M.Clock{0, 0}), 7)}

def monitor_enter_ref(+object: U32, +vm: M.VM, +frame: M.Frame, +next: M.Frame) -> Result<&2, &2, String, M.VM>:
  match object:
    case 0: Fail{"java/lang/NullPointerException"}
    case _: monitor_entered(Th.enter(vm, object), vm, frame, next, object)

def monitor_enter_popped(+vm: M.VM, +frame: M.Frame, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}: monitor_enter_ref(M.slot_bits(value), vm, frame, next)

def monitor_enter(+vm: M.VM, +frame: M.Frame) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 3)
    result : M.VM <- monitor_enter_popped(vm, frame, popped)
    return result

def monitor_exit_ref(+object: U32, +vm: M.VM, +next: M.Frame) -> Result<&2, &2, String, M.VM>:
  match object:
    case 0: Fail{"java/lang/NullPointerException"}
    case _:
      do Result<&2, &2, String, M.VM>:
        released : M.VM <- Th.exit(vm, object)
        return S.commit(released, S.advance(next))

def monitor_exit_popped(+vm: M.VM, popped: F.Popped) -> Result<&2, &2, String, M.VM>:
  match popped:
    case F.Popped{+next, value}: monitor_exit_ref(M.slot_bits(value), vm, next)

def monitor_exit(+vm: M.VM, +frame: M.Frame) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    popped : F.Popped <- F.pop(frame, 3)
    result : M.VM <- monitor_exit_popped(vm, popped)
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
    case 97: wide_binary(frame, vm, 97, 4, method_max_stack(method))
    case 99: wide_binary(frame, vm, 99, 5, method_max_stack(method))
    case 101: wide_binary(frame, vm, 101, 4, method_max_stack(method))
    case 103: wide_binary(frame, vm, 103, 5, method_max_stack(method))
    case 105: wide_binary(frame, vm, 105, 4, method_max_stack(method))
    case 107: wide_binary(frame, vm, 107, 5, method_max_stack(method))
    case 109: wide_binary(frame, vm, 109, 4, method_max_stack(method))
    case 111: wide_binary(frame, vm, 111, 5, method_max_stack(method))
    case 113: wide_binary(frame, vm, 113, 4, method_max_stack(method))
    case 115: wide_binary(frame, vm, 115, 5, method_max_stack(method))
    case 117: wide_unary(vm, frame, 4, method_max_stack(method))
    case 119: wide_unary(vm, frame, 5, method_max_stack(method))
    case 121: wide_shift(frame, vm, 121, method_max_stack(method))
    case 123: wide_shift(frame, vm, 123, method_max_stack(method))
    case 125: wide_shift(frame, vm, 125, method_max_stack(method))
    case 127: wide_binary(frame, vm, 127, 4, method_max_stack(method))
    case 129: wide_binary(frame, vm, 129, 4, method_max_stack(method))
    case 131: wide_binary(frame, vm, 131, 4, method_max_stack(method))

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
    case 133: convert_numeric(vm, frame, 133, method_max_stack(method))
    case 134: convert_numeric(vm, frame, 134, method_max_stack(method))
    case 135: convert_numeric(vm, frame, 135, method_max_stack(method))
    case 136: convert_numeric(vm, frame, 136, method_max_stack(method))
    case 137: convert_numeric(vm, frame, 137, method_max_stack(method))
    case 138: convert_numeric(vm, frame, 138, method_max_stack(method))
    case 139: convert_numeric(vm, frame, 139, method_max_stack(method))
    case 140: convert_numeric(vm, frame, 140, method_max_stack(method))
    case 141: convert_numeric(vm, frame, 141, method_max_stack(method))
    case 142: convert_numeric(vm, frame, 142, method_max_stack(method))
    case 143: convert_numeric(vm, frame, 143, method_max_stack(method))
    case 144: convert_numeric(vm, frame, 144, method_max_stack(method))
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
    case 89: stack_instruction(vm, frame, op, method_max_stack(method))
    case 87: stack_instruction(vm, frame, op, method_max_stack(method))
    case 88: stack_instruction(vm, frame, op, method_max_stack(method))
    case 90: stack_instruction(vm, frame, op, method_max_stack(method))
    case 91: stack_instruction(vm, frame, op, method_max_stack(method))
    case 92: stack_instruction(vm, frame, op, method_max_stack(method))
    case 93: stack_instruction(vm, frame, op, method_max_stack(method))
    case 94: stack_instruction(vm, frame, op, method_max_stack(method))
    case 155: branch_signed(vm, frame, a, 155)
    case 190: array_length(vm, frame)
    case 156: branch_signed(vm, frame, a, 156)
    case 157: branch_signed(vm, frame, a, 157)
    case 158: branch_signed(vm, frame, a, 158)
    case 165: ref_compare(frame, vm, a, 165)
    case 166: ref_compare(frame, vm, a, 166)
    case 95: stack_instruction(vm, frame, op, method_max_stack(method))
    case 153: branch_zero(vm, frame, a, True{})
    case 154: branch_zero(vm, frame, a, False{})
    case 167: branch_target(vm, frame, a)
    case 200: branch_target(vm, frame, a)
    case 198: branch_ref_zero(vm, frame, a, True{})
    case 199: branch_ref_zero(vm, frame, a, False{})
    case 172:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 1)
        released : M.VM <- return_release(vm, S.frame_monitor(frame))
        result : M.VM <- return_popped(released, popped)
        return result
    case 159: branch_compare(frame, vm, a, 159)
    case 160: branch_compare(frame, vm, a, 160)
    case 161: branch_compare(frame, vm, a, 161)
    case 162: branch_compare(frame, vm, a, 162)
    case 163: branch_compare(frame, vm, a, 163)
    case 164: branch_compare(frame, vm, a, 164)
    case 149: float_compare(frame, vm, 149)
    case 150: float_compare(frame, vm, 150)
    case 148: wide_compare(frame, vm, 148, method_max_stack(method))
    case 151: wide_compare(frame, vm, 151, method_max_stack(method))
    case 152: wide_compare(frame, vm, 152, method_max_stack(method))
    case 173:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 4)
        released : M.VM <- return_release(vm, S.frame_monitor(frame))
        result : M.VM <- return_popped(released, popped)
        return result
    case 174:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
        released : M.VM <- return_release(vm, S.frame_monitor(frame))
        result : M.VM <- return_popped(released, popped)
        return result
    case 175:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 5)
        released : M.VM <- return_release(vm, S.frame_monitor(frame))
        result : M.VM <- return_popped(released, popped)
        return result
    case 176:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 3)
        released : M.VM <- return_release(vm, S.frame_monitor(frame))
        result : M.VM <- return_popped(released, popped)
        return result
    case 177:
      do Result<&2, &2, String, M.VM>:
        released : M.VM <- return_release(vm, S.frame_monitor(frame))
        return finish_void(released)
    case 194: monitor_enter(vm, frame)
    case 195: monitor_exit(vm, frame)
    case 178: getstatic(vm, frame, a, b, c)
    case 179: putstatic(vm, frame, a, b, c)
    case 180: getfield(vm, frame, a, b, c)
    case 181: putfield(vm, frame, a, b, c)
    case 191: athrow(vm, frame)
    case 192: ref_test(vm, frame, a, True{})
    case 193: ref_test(vm, frame, a, False{})
    case 188: array_count(vm, frame, Sy.find(S.symbols(vm), B.atype_name(a)), a, 1)
    case 189: anewarray(vm, frame, a)
    case 197: multianewarray(vm, frame, a, b)
    case 187: new_object(vm, frame, a)
    case 182: invoke_virtual(vm, frame, a, b, c, method_max_stack(method))
    case 183: invoke_special(vm, frame, a, b, c, method_max_stack(method))
    case 184: invoke_static(vm, frame, a, b, c, method_max_stack(method))
    case 185: invoke_virtual(vm, frame, a, b, c, method_max_stack(method))
    case 186: execute_indy(vm, frame, a, method_max_stack(method))
    case 170: switch_step(vm, frame, method, a, b)
    case 171: switch_step(vm, frame, method, a, b)
    case _: Fail{"UnsupportedOpcode: " ++ U32.show(op)}
def method_handlers(value: M.LoadedMethod) -> +List<M.Handler>:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic, switches}: handlers


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


def throwable_with_cause(entry: M.HeapEntry, cause: U32) -> M.HeapEntry:
  match entry:
    case M.HeapEntry{class, kind, element, +fields, values, chars}:
      M.HeapEntry{class, kind, element, H.binding_set(fields, 1, M.Slot{3, cause}), values, chars}

def initializer_error_alloc(+vm: M.VM, allocation: Result<&2, &2, String, H.Allocation>) -> M.VM:
  match allocation:
    case Fail{error}: S.fail(vm, error)
    case Done{H.Allocation{updated, reference}}: S.with_exception(updated, reference)

def initializer_error_wrap(is_error: Bool, +vm: M.VM) -> M.VM:
  match is_error:
    case True{}: vm
    case False{}:
      +class = H.named_class(S.classes(vm), S.symbols(vm), "java/lang/ExceptionInInitializerError")
      initializer_error_alloc(vm, H.allocate(vm, throwable_with_cause(H.throwable_entry(class), S.exception(vm))))

# JVMS 5.5 step 11: an exception escaping <clinit> marks the class erroneous;
# anything that is not an Error is replaced by ExceptionInInitializerError
# carrying it as the cause.
def fail_initializer_state(+vm: M.VM, owner: U32) -> M.VM:
  match owner:
    case 4294967295: vm
    case value:
      +failed = S.set_class_state(vm, value, 3)
      +classes = S.classes(failed)
      initializer_error_wrap(U32.is_eq(S.exception(failed), 0) || H.hierarchy(classes, thrown_class_of(failed), H.named_class(classes, S.symbols(failed), "java/lang/Error")), failed)

# An unwound synchronized frame gives back the monitor it took on entry.
def unwind_release_held(+vm: M.VM, +lock: U32, +depth: U32) -> M.VM:
  match depth:
    case 0: vm
    case _: Th.grant(vm, lock, Th.current(vm), U32.sub(depth, 1))

def unwind_release(+vm: M.VM, +lock: U32) -> M.VM:
  match lock:
    case 0: vm
    case _: unwind_release_held(vm, lock, Th.held(vm, lock, Th.current(vm)))

def fail_initializer(+vm: M.VM, +frame: M.Frame) -> M.VM:
  fail_initializer_state(unwind_release(vm, S.frame_monitor(frame)), S.initializing(frame))
# Uncaught Java exceptions report their runtime class instead of a generic Throwable.
def pending_exception_class(found: Maybe<&2, M.LoadedClass>, +vm: M.VM) -> String:
  match found:
    case None{}: "java/lang/Throwable"
    case Some{class}: Sy.text(S.symbols(vm), M.loaded_class_name(class))

def pending_exception_name(+vm: M.VM) -> String:
  pending_exception_class(M.nth(M.LoadedClass, S.classes(vm), thrown_class_of(vm)), vm)

def pending_message_text(found: Result<&2, &2, String, M.HeapEntry>) -> String:
  match found:
    case Done{+entry}: Bool.pick(String, U32.is_eq(L.entry_kind(entry), 3), ": " ++ L.utf16(L.entry_chars(entry), 0), "")
    case Fail{error}: ""

def pending_message_reference(+reference: U32, +vm: M.VM) -> String:
  match reference:
    case 0: ""
    case _: pending_message_text(H.get(S.heap(vm), reference))

def pending_message_entry(found: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM) -> String:
  match found:
    case Done{entry}: pending_message_reference(L.field_bits(L.entry_fields(entry), 0), vm)
    case Fail{error}: ""

def throwable_class_text(found: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM) -> String:
  match found:
    case Done{entry}: pending_exception_class(M.nth(M.LoadedClass, S.classes(vm), H.entry_class(entry)), vm)
    case Fail{error}: "java/lang/Throwable"

def throwable_cause(found: Result<&2, &2, String, M.HeapEntry>) -> U32:
  match found:
    case Done{entry}: L.field_bits(L.entry_fields(entry), 1)
    case Fail{error}: 0

# "Class: message" followed by the JDK-style cause chain (bounded, cycle-safe).
@unsafe def throwable_cause_report(stop: Bool, fuel: Nat, +vm: M.VM, cause: U32) -> String:
  match stop:
    case True{}: ""
    case False{}: "\nCaused by: " ++ throwable_report(fuel, vm, cause)

@unsafe def throwable_report(fuel: Nat, +vm: M.VM, +reference: U32) -> String:
  match fuel:
    case 0n: ""
    case 1n+rest:
      +found : Result<&2, &2, String, M.HeapEntry> = H.get(S.heap(vm), reference)
      +cause : U32 = throwable_cause(found)
      head : String = throwable_class_text(found, vm) ++ pending_message_entry(found, vm)
      head ++ throwable_cause_report(U32.is_eq(cause, 0) || U32.is_eq(cause, reference), rest, vm, cause)

def pending_exception_report(+vm: M.VM) -> String:
  throwable_report(8n, vm, S.exception(vm))

def uncaught_report(pending: Bool, +vm: M.VM, error: String) -> M.VM:
  match pending:
    # The thread ends with an uncaught exception (status 9); the scheduler
    # reports it and keeps the other threads running.
    case True{}: S.with_status(S.with_error(vm, pending_exception_report(vm)), 9)
    case False{}: S.fail(vm, error)

# Unwinding can replace the pending exception (a bootstrap failure is wrapped in
# BootstrapMethodError), so the pending throwable wins over the original message.
def uncaught(+vm: M.VM, error: String) -> M.VM:
  uncaught_report(U32.is_ne(S.exception(vm), 0), vm, error)

def handler_target(found: Maybe<&2, U32>) -> U32:
  match found:
    case None{}: 4294967295
    case Some{target}: target

@unsafe def exception_unwind_miss(+error: String, +vm: M.VM, +caller: M.Frame, callers: +List<M.Frame>, +fuel: Nat, +k: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match callers:
    case Nil{}: uncaught(fail_initializer(vm, caller), error)
    case Con{+next_caller, +next_callers}:
      +next = S.with_frames(fail_initializer(vm, caller), Con{next_caller, next_callers})
      +wrapped = dynamic_exception_wrap(boundary_throw(next, M.length(M.Frame, S.frames(next))))
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
          +wrapped = dynamic_exception_wrap(boundary_throw(next, M.length(M.Frame, S.frames(next))))
          +target = handler_target(frame_exception_handler(wrapped, caller, S.invoke_pc(current)))
          exception_unwind_choice(U32.is_eq(target, 4294967295), error, wrapped, caller, callers, fuel, k, target)


def exception_resume_found(error: String, +vm: M.VM, +frame: M.Frame, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM, found: Maybe<&2, U32>) -> M.VM:
  match found:
    case None{}: exception_unwind(error, vm, S.frames(vm), fuel, continue)
    case Some{target}: enter_handler(vm, frame, target, fuel, continue)



def exception_resume_java(+error: String, +vm: M.VM, +frame: M.Frame, method: M.LoadedMethod, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  +ready = ensure_throw(vm, error)
  exception_resume_found(error, ready, frame, fuel, continue, exception_handler(ready, S.pc(frame), thrown_class_of(ready), method_handlers(method)))

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

def run_native_initializer(fuel: Nat, +vm: M.VM, frame: M.Frame, method: M.LoadedMethod, continue: U32 -> Nat -> M.VM -> M.VM, result: Result<&2, &2, String, O.Outcome>) -> M.VM:
  match result:
    case Done{O.Returned{+updated, value}}:
      +next : M.VM = finish_void(S.set_class_state(updated, M.loaded_method_owner(method), 2))
      continue(S.status(next), fuel, next)
    case Fail{error}: exception_resume(error, vm, frame, method, fuel, continue)
    case _: S.fail(vm, "InvalidState: native initializer outcome")
def run_method_intrinsic(intrinsic: U32, fuel: Nat, +vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match intrinsic:
    case 317: run_native_initializer(fuel, vm, frame, method, continue, L.standard_enum_clinit(vm, Nil{}, M.loaded_method_owner(method)))
    case _: run_instruction(method_instruction(method, S.pc(frame)), fuel, vm, frame, method, continue)
# A synchronized method's frame locks before its first instruction runs: the
# receiver, or the declaring class's mirror for a static method (JVMS 2.11.10).
def entry_lock_needed(+method: M.LoadedMethod, +frame: M.Frame) -> Bool:
  U32.is_ne(U32.and(M.loaded_method_flags(method), 32), 0) && U32.is_eq(S.frame_monitor(frame), 0) && U32.is_eq(S.pc(frame), 0) && U32.is_eq(method_intrinsic(method), 0)

def class_lock_found(+vm: M.VM, +owner: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, H.Allocation>:
  match found:
    case Some{reference}: Done{H.Allocation{vm, reference}}
    case None{}: H.allocate(vm, H.class_mirror_entry(H.named_class(S.classes(vm), S.symbols(vm), "java/lang/Class"), owner))

def receiver_lock(+vm: M.VM, locals: +List<M.Slot>) -> Result<&2, &2, String, H.Allocation>:
  match locals:
    case Con{M.Slot{3, reference}, rest}: Done{H.Allocation{vm, reference}}
    case _: Fail{"InvalidState: synchronized method without receiver"}

# The object a synchronized method locks.
def entry_lock_kind(isStatic: Bool, +vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod) -> Result<&2, &2, String, H.Allocation>:
  match isStatic:
    case True{}: class_lock_found(vm, M.loaded_method_owner(method), H.class_mirror(S.heap(vm), M.loaded_method_owner(method)))
    case False{}: receiver_lock(vm, S.locals(frame))

def entry_lock(+vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod) -> Result<&2, &2, String, H.Allocation>:
  entry_lock_kind(U32.is_ne(U32.and(M.loaded_method_flags(method), 8), 0), vm, frame, method)

def run_method_locked(entered: Maybe<&2, M.VM>, fuel: Nat, +vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod, +lock: U32, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match entered:
    case Some{+owned}: run_method_intrinsic(method_intrinsic(method), fuel, owned, S.frame_with_monitor(frame, lock), method, continue)
    # Another thread owns the monitor: block and retry the entry once it is free.
    case None{}: continue(7, fuel, S.with_status(Th.park(vm, M.EnterMonitor{lock}, False{}, M.Clock{0, 0}), 7))

def run_method_lock(result: Result<&2, &2, String, H.Allocation>, fuel: Nat, +vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{H.Allocation{+updated, +lock}}: run_method_locked(Th.enter(updated, lock), fuel, updated, frame, method, lock, continue)

def run_method_entry(needed: Bool, fuel: Nat, +vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match needed:
    case False{}: run_method_intrinsic(method_intrinsic(method), fuel, vm, frame, method, continue)
    case True{}: run_method_lock(entry_lock(vm, frame, method), fuel, vm, frame, method, continue)

def run_method(found: Maybe<&2, M.LoadedMethod>, fuel: Nat, +vm: M.VM, +frame: M.Frame, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match found:
    case None{}: S.fail(vm, "InvalidState: method id")
    case Some{+method}: run_method_entry(entry_lock_needed(method, frame), fuel, vm, frame, method, continue)



def run_frames(fuel: Nat, +vm: M.VM, frames: +List<M.Frame>, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match frames:
    case Nil{}: S.with_status(vm, 1)
    case Con{+frame, rest}: run_method(M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)), fuel, vm, frame, continue)

@unsafe def loop_with(mode: U32, status: U32, +fuel: Nat, +vm: M.VM, +frames: +List<M.Frame>, found: Maybe<&2, M.LoadedMethod>, +frame: M.Frame) -> M.VM:
  match mode:
    case 0:
      match status:
        case 1: S.with_left(vm, fuel)
        case 4: S.with_left(vm, fuel)
        case 3: S.with_left(vm, fuel)
        case 5: S.with_left(vm, fuel)
        case 7: S.with_left(vm, fuel)
        case 8: S.with_left(vm, fuel)
        case 9: S.with_left(vm, fuel)
        case 6:
          match frames:
            case Nil{}: uncaught(vm, pending_exception_report(vm))
            case Con{+cur, rest}:
              loop_with(1, status, fuel, vm, Con{cur, rest}, M.nth(M.LoadedMethod, S.methods(vm), S.method_id(cur)), cur)
        case _:
          match fuel:
            case 0n: S.with_left(S.with_status(vm, 3), 0n)
            case 1n+p: run_frames(p, vm, frames, nextStatus => nextFuel => +nextVm => loop_with(0, nextStatus, nextFuel, nextVm, S.frames(nextVm), None{}, frame))
    case _:
      match found:
        case None{}: uncaught(vm, pending_exception_report(vm))
        case Some{method}:
          exception_resume_java(pending_exception_report(vm), vm, frame, method, fuel, nextStatus => nextFuel => +nextVm => loop_with(0, nextStatus, nextFuel, nextVm, S.frames(nextVm), None{}, frame))

@unsafe def loop(fuel: Nat, +vm: M.VM) -> M.VM:
  loop_with(0, S.status(vm), fuel, vm, S.frames(vm), None{}, M.Frame{0, 0, 0, Nil{}, Nil{}, 4294967295, 0})

def run(vm: M.VM, fuel: Nat) -> M.VM:
  loop(fuel, vm)

def resume_clear(+vm: M.VM) -> M.VM:
  S.with_effect(S.with_status(vm, 0), M.Idle{})

# A host effect a native requested while an intrinsic's callback ran (a
# HostCallback marker at the current depth) resumes that intrinsic's
# continuation, not the instruction of the frame below.
def callback_pending(conts: +List<M.Cont>, depth: U32) -> Bool:
  match conts:
    case Con{M.HostCallback{expected}, rest}: U32.is_eq(expected, depth)
    case _: False{}

@unsafe def resume_callback(+vm: M.VM, frame: M.Frame, value: Maybe<&2, M.Slot>) -> M.VM:
  +ready : M.VM = resume_clear(vm)
  invoke_job(ready, JResult{frame, Done{O.Returned{ready, value}}})

@unsafe def resume_void_frames(+vm: M.VM, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: resume_clear(vm)
    case Con{+frame, +rest}: resume_void_route(callback_pending(host_cont(vm), M.length(M.Frame, Con{frame, rest})), vm, frame)

@unsafe def resume_void_route(pending: Bool, +vm: M.VM, frame: M.Frame) -> M.VM:
  match pending:
    case True{}: resume_callback(vm, frame, None{})
    case False{}: resume_clear(S.commit(vm, S.advance(frame)))

def resume_void(+vm: M.VM) -> M.VM:
  resume_void_frames(vm, S.frames(vm))

def resume_push_done(+vm: M.VM, result: Result<&2, &2, String, M.Frame>) -> M.VM:
  match result:
    case Fail{error}: S.fail(vm, error)
    case Done{pushed}: resume_clear(S.commit(vm, pushed))

@unsafe def resume_push_frames(+vm: M.VM, value: M.Slot, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: resume_clear(vm)
    case Con{+frame, +rest}: resume_push_route(callback_pending(host_cont(vm), M.length(M.Frame, Con{frame, rest})), vm, value, frame)

@unsafe def resume_push_route(pending: Bool, +vm: M.VM, value: M.Slot, frame: M.Frame) -> M.VM:
  match pending:
    case True{}: resume_callback(vm, frame, Some{value})
    case False{}: resume_push_done(vm, F.push(S.advance(frame), value, 256))

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

def resume_read_bytes(values: +List<U32>, +vm: M.VM) -> M.VM:
  match values:
    case Nil{}: resume_int(vm, 4294967295)
    case Con{b, rest}: resume_int(vm, U32.and(b, 255))

@unsafe def resume_ok_effect(+vm: M.VM, +handle: U32, extra: U32, bytes: +List<U32>, effect: M.Effect) -> M.VM:
  match effect:
    case M.Idle{}: resume_clear(vm)
    case M.HandleAdapter{targetDescriptor, requestedDescriptor}: S.fail(vm, "InvalidState: internal HandleAdapter is not a host effect")
    case M.HandleConstructor{reference}: S.fail(vm, "InvalidState: internal HandleConstructor is not a host effect")
    case M.ReflectCall{}: resume_clear(vm)
    case M.ReflectConstructor{reference}: resume_clear(vm)
    case M.ProxyCall{descriptor, method_id, owners}: resume_clear(vm)
    case M.RuntimeClass{name, initialize, loader}: resume_clear(vm)
    case M.ReadResource{name, origin}: resume_clear(vm)
    case M.OpenFile{path, mode, receiver}: resume_open_to(vm, handle, receiver)
    case M.StatPath{path, op}: resume_int(vm, extra)
    case M.ReadBytes{old, count, timeout}: resume_read_bytes(bytes, vm)
    case M.WriteBytes{old, data}: resume_void(vm)
    case M.CloseHandle{old}: resume_void(vm)
    case M.PrivilegedCall{}: resume_clear(vm)
    case M.ListDirectory{path, parent, files}: resume_directory_result(vm, Fs.resume_directory(vm, parent, files, extra, bytes))
    case M.ListArchive{path, receiver, op, connection, entry}: resume_outcome(vm, Fs.resume_archive(vm, receiver, op, connection, entry, bytes))
    case M.ReadPathBytes{path, entry}: resume_clear(vm)
    case M.LoaderCatch{}: resume_clear(vm)
    case M.LoaderSuper{name}: resume_clear(vm)
    case M.SerialCatch{}: resume_clear(vm)
    case M.Park{}: resume_void(vm)
    case M.HostIO{op, h, arg, data, array, offset, length}: resume_int(Hio.fill(vm, array, offset, length, bytes), handle)
    case M.NativeCall{method, owner, name, descriptor, isStatic, words, arrays, lock}: resume_native(vm, Nb.finish(vm, descriptor, arrays, lock, bytes))
    case M.LoadLibrary{name, absolute}: resume_void(vm)

@unsafe def resume_native(+vm: M.VM, result: Result<&2, &2, String, Nb.Finished>) -> M.VM:
  match result:
    case Fail{error}: resume_fail(vm, error)
    case Done{Nb.Finished{updated, None{}}}: resume_void(updated)
    case Done{Nb.Finished{updated, Some{value}}}: resume_push(updated, value)

@unsafe def resume_directory_result(+vm: M.VM, result: Result<&2, &2, String, Fs.Allocated>) -> M.VM:
  match result:
    case Fail{error}: resume_fail(vm, error)
    case Done{Fs.Allocated{updated, reference}}: resume_ref(updated, reference)

# Finish a host effect whose resumption is an intrinsic outcome.
@unsafe def resume_outcome(+vm: M.VM, result: Result<&2, &2, String, O.Outcome>) -> M.VM:
  match result:
    case Fail{error}: resume_fail(vm, error)
    case Done{O.Returned{updated, None{}}}: resume_void(updated)
    case Done{O.Returned{updated, Some{value}}}: resume_push(updated, value)
    case Done{O.ThrownName{updated, name}}: resume_fail(updated, name)
    case Done{O.ThrownRef{updated, reference}}: S.with_effect(S.with_status(S.with_exception(updated, reference), 6), M.Idle{})
    case Done{_}: S.fail(vm, "InvalidState: host resumption requested a call")

def resume_ok(+vm: M.VM, +handle: U32, extra: U32, bytes: +List<U32>) -> M.VM:
  resume_ok_effect(vm, handle, extra, bytes, S.host_effect(vm))

# A host effect failed: the exception starts at the suspended intrinsic, so any
# boundary at the current depth (reflection, loaders, privileged actions) sees
# it before the caller's handlers do.
# A failed synchronized native call still gives its monitor back.
def native_unlock(+vm: M.VM, effect: M.Effect) -> M.VM:
  match effect:
    case M.NativeCall{method, owner, name, descriptor, isStatic, words, arrays, lock}: unwind_release(vm, lock)
    case _: vm

# The method a suspended frame was calling: an exception that completes a host
# effect starts in that intrinsic (FileInputStream.<init>, HostIO.call, ...).
def resolved_id(found: Maybe<&2, M.LoadedMethod>) -> U32:
  match found:
    case Some{method}: M.loaded_method_id(method)
    case None{}: 4294967295

# Call instructions name the owner, method name and descriptor symbols.
def call_site_resolve(call: Bool, +vm: M.VM, +owner: U32, +name: U32, +descriptor: U32) -> U32:
  match call:
    case True{}: resolved_id(find_method(S.classes(vm), S.methods(vm), owner, name, descriptor))
    case False{}: 4294967295

def call_site_instruction(+vm: M.VM, found: Maybe<&2, M.Instruction>) -> U32:
  match found:
    case Some{M.Instruction{+op, a, b, c, offset}}: call_site_resolve(U32.is_ge(op, 182) && U32.is_le(op, 185), vm, a, b, c)
    case None{}: 4294967295

def call_site_method(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>, +pc: U32) -> U32:
  match found:
    case Some{+method}: call_site_instruction(vm, method_instruction(method, pc))
    case None{}: 4294967295

def call_site_frames(+vm: M.VM, frames: +List<M.Frame>) -> U32:
  match frames:
    case Con{+frame, rest}: call_site_method(vm, M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)), S.pc(frame))
    case Nil{}: 4294967295

def with_call_site(+vm: M.VM, +site: U32, fresh: Bool) -> M.VM:
  match fresh:
    case False{}: vm
    case True{}: Bool.pick(M.VM, U32.is_eq(site, 4294967295), vm, Tr.with_native_frame(vm, site))

# A host effect failed: the new exception's innermost frame is the intrinsic
# that suspended, unless a Java callback chain owns the top of the stack.
def host_failed(+before: M.VM, +thrown: M.VM) -> M.VM:
  with_call_site(thrown, call_site_frames(before, S.frames(before)), U32.is_eq(S.exception(before), 0) && Bool.not(callback_pending(host_cont(before), M.length(M.Frame, S.frames(before)))))

@unsafe def resume_fail(+vm: M.VM, name: String) -> M.VM:
  +thrown : M.VM = S.with_effect(S.with_status(host_failed(vm, ensure_throw(native_unlock(vm, S.host_effect(vm)), name)), 6), M.Idle{})
  boundary_throw(thrown, M.length(M.Frame, S.frames(thrown)))

@unsafe def resume_fail_message(+vm: M.VM, +name: String, message: String) -> M.VM:
  +thrown : M.VM = S.with_effect(S.with_status(host_failed(vm, throw_with_message(vm, name, message)), 6), M.Idle{})
  boundary_throw(thrown, M.length(M.Frame, S.frames(thrown)))

def continue_run(vm: M.VM, fuel: Nat) -> M.VM:
  loop(fuel, vm)

