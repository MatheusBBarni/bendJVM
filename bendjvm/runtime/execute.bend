import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../runtime/frame.bend as F
import ../runtime/value.bend as V
import ../heap/heap.bend as H
import ../loader/bootstrap.bend as B
import ../loader/symbols.bend as Sy
import ../java/intrinsic.bend as I

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

@unsafe def copy_arguments(values: +List<M.Slot>, +locals: +List<M.Slot>, +index: Nat) -> +List<M.Slot>:
  match values:
    case Nil{}: locals
    case Con{value, rest}:
      copy_arguments(rest, M.replace(M.Slot, locals, index, value), 1n+index)

def return_frames(+vm: M.VM, value: M.Slot, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Nil{}: S.with_result(S.with_status(vm, 1), value)
    case Con{current, rest}:
      match rest:
        case Nil{}: S.with_result(S.with_status(vm, 1), value)
        case Con{+caller, callers}:
          S.with_frames(vm, Con{S.frame_stack(caller, Con{value, S.stack(caller)}), callers})

def push_return(+vm: M.VM, value: M.Slot) -> M.VM:
  return_frames(vm, value, S.frames(vm))


def finish_return(vm: M.VM, value: M.Slot) -> M.VM:
  push_return(vm, value)

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

def finish_void(+vm: M.VM) -> M.VM:
  finish_void_frames(vm, S.frames(vm))

def invoke_frame(vm: M.VM, id: U32, maxLocals: U32, +caller: M.Frame, values: +List<M.Slot>, frames: +List<M.Frame>) -> M.VM:
  match frames:
    case Con{old, rest}:
      S.with_frames(vm, Con{M.Frame{id, 0, U32.sub(S.pc(caller), 1), copy_arguments(values, make_locals(U32.to_nat(maxLocals)), 0n), Nil{}, 4294967295}, Con{caller, rest}})
    case Nil{}:
      S.fail(vm, "InvalidState: invocation without caller")

def invoke_arguments(vm: M.VM, method: M.LoadedMethod, args: F.Arguments, frames: +List<M.Frame>) -> M.VM:
  match method:
    case M.LoadedMethod{id, owner0, name0, descriptor0, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      match args:
        case F.Arguments{caller, values}:
          invoke_frame(vm, id, maxLocals, caller, values, frames)
def intrinsic_output(+vm: M.VM, frame: M.Frame, output: Maybe<&2, String>) -> Result<&2, &2, String, M.VM>:
  match output:
    case None{}:
      Done{S.commit(vm, frame)}
    case Some{text}:
      Done{S.commit(S.emit(vm, text), frame)}

def intrinsic_args(+vm: M.VM, method: M.LoadedMethod, args: F.Arguments) -> Result<&2, &2, String, M.VM>:
  match args:
    case F.Arguments{frame, values}:
      do Result<&2, &2, String, M.VM>:
        output : Maybe<&2, String> <- I.execute(method_intrinsic(method), S.heap(vm), values)
        result : M.VM <- intrinsic_output(vm, frame, output)
        return result

def dispatch_intrinsic(+vm: M.VM, method: M.LoadedMethod, args: F.Arguments, intrinsic: U32) -> Result<&2, &2, String, M.VM>:
  match intrinsic:
    case 0: Done{invoke_arguments(vm, method, args, S.frames(vm))}
    case other: intrinsic_args(vm, method, args)

def dispatch_method(+vm: M.VM, +method: M.LoadedMethod, args: F.Arguments) -> Result<&2, &2, String, M.VM>:
  dispatch_intrinsic(vm, method, args, method_intrinsic(method))

def receiver_slot(stack: +List<M.Slot>, count: Nat) -> Maybe<&2, M.Slot>:
  match stack:
    case Nil{}: None{}
    case Con{+receiver, rest}:
      match count:
        case 0n: Some{receiver}
        case 1n+p: receiver_slot(rest, p)
def invoke_virtual_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, frame: M.Frame, count: U32) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchMethodError"}
    case Some{+method}:
      do Result<&2, &2, String, M.VM>:
        args : F.Arguments <- F.arguments(frame, U32.add(method_parameters(method), count))
        result : M.VM <- dispatch_method(vm, method, args)
        return result

def virtual_method_entry(result: Result<&2, &2, String, M.HeapEntry>, +vm: M.VM, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match result:
    case Fail{error}: find_method(S.classes(vm), S.methods(vm), owner, name, descriptor)
    case Done{entry}: find_method_id(Some{H.entry_class(entry)}, S.classes(vm), S.methods(vm), name, descriptor)

def virtual_method_stack_found(found: Maybe<&2, M.Slot>, +vm: M.VM, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{+receiver}: virtual_method_entry(H.get(S.heap(vm), V.slot_bits(receiver)), vm, owner, name, descriptor)

def virtual_method_stack_case(+vm: M.VM, +stack: +List<M.Slot>, +owner: U32, +name: U32, +descriptor: U32, count: Nat) -> Maybe<&2, M.LoadedMethod>:
  virtual_method_stack_found(receiver_slot(stack, count), vm, owner, name, descriptor)

def invoke_virtual_method(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stack: +List<M.Slot>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{method}:
      virtual_method_stack_case(vm, stack, owner, name, descriptor, U32.to_nat(method_parameters(method)))


def virtual_method_stack(+vm: M.VM, +frame: M.Frame, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedMethod>:
  invoke_virtual_method(find_method(S.classes(vm), S.methods(vm), owner, name, descriptor), vm, S.stack(frame), owner, name, descriptor)

def invoke_virtual(+vm: M.VM, +frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  invoke_virtual_found(virtual_method_stack(vm, frame, owner, name, descriptor), vm, frame, 1)
def invoke_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, frame: M.Frame) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Fail{"NoSuchMethodError"}
    case Some{+method}:
      do Result<&2, &2, String, M.VM>:
        args : F.Arguments <- F.arguments(frame, method_parameters(method))
        result : M.VM <- dispatch_method(vm, method, args)
        return result

def invoke_static(+vm: M.VM, frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  invoke_found(find_method(S.classes(vm), S.methods(vm), owner, name, descriptor), vm, frame)
def invoke_special(+vm: M.VM, frame: M.Frame, owner: U32, name: U32, descriptor: U32) -> Result<&2, &2, String, M.VM>:
  invoke_virtual_found(find_method(S.classes(vm), S.methods(vm), owner, name, descriptor), vm, frame, 1)


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
    case 4294967295: static_get_found(vm, frame, Some{field})
    case _: static_initializer_found(vm, frame, id, M.nth(M.LoadedMethod, S.methods(vm), initializer))

def static_initializer_parent_method(+vm: M.VM, +frame: M.Frame, +field: M.LoadedField, +id: U32, +initializer: U32, parent_id: U32, parent_initializer: U32) -> Result<&2, &2, String, M.VM>:
  match parent_initializer:
    case 4294967295: static_initializer_or_get(vm, frame, field, id, initializer)
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

def array_default_slot(kind: U32, element: U32, symbols: +List<String>) -> M.Slot:
  match kind:
    case 1: Bool.pick(M.Slot, U32.is_eq(element, 6), M.Slot{2, 0}, M.Slot{1, 0})
    case _: M.Slot{3, 0}

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
    case True{}: Fail{"NegativeArraySizeException"}
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
      Bool.pick(Result<&2, &2, String, M.VM>, checked, Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{3, reference}, S.stack(frame)}))}, Fail{"ClassCastException"})
    case False{}:
      Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{1, Bool.pick(U32, checked, 1, 0)}, S.stack(frame)}))}

def ref_assignable_target(+vm: M.VM, reference: U32, +target: U32, cast: Bool, +frame: M.Frame, class: U32, found: Maybe<&2, U32>) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Bool.pick(Result<&2, &2, String, M.VM>, cast, Fail{"ClassCastException"}, Done{S.commit(vm, S.frame_stack(S.advance(frame), Con{M.Slot{1, 0}, S.stack(frame)}))})
    case Some{+target_id}: ref_assignable_checked(vm, reference, target_id, cast, frame, H.assignable(S.classes(vm), S.symbols(vm), class, target_id))

def ref_assignable_frame(+vm: M.VM, reference: U32, +target: U32, cast: Bool, +frame: M.Frame, entry: M.HeapEntry) -> Result<&2, &2, String, M.VM>:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}: ref_assignable_target(vm, reference, target, cast, frame, class, class_id_by_name(S.classes(vm), target))

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
            checked : Unit <- S.check(H.assignable(S.classes(vm), S.symbols(vm), class, target), "ArrayStoreException")
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
            checked_index : Unit <- S.check(U32.is_lt(V.slot_bits(index), M.length(M.Slot, values)), "ArrayIndexOutOfBoundsException")
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
            checked_index : Unit <- S.check(U32.is_lt(V.slot_bits(index), M.length(M.Slot, values)), "ArrayIndexOutOfBoundsException")
            slot : M.Slot <- S.require(M.Slot, M.nth(M.Slot, values, V.slot_bits(index)), "ArrayIndexOutOfBoundsException")
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
    case F.Popped{frame, value}: Bool.pick(Result<&2, &2, String, M.VM>, U32.is_eq(V.slot_bits(value), 0), Fail{"NullPointerException"}, Fail{"ThrownException"})

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
    class : U32 = Sy.find(S.symbols(vm), "java/lang/String")
    chars : +List<U32> = string_units(String.to_list(text))
    found : Maybe<&2, U32> = H.string_intern(S.heap(vm), chars)
    result : M.VM <- literal_string_found(vm, frame, symbol, class, found)
    return result
def constant_push(+vm: M.VM, +frame: M.Frame, value: U32, tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +pushed : M.Frame <- F.push(frame, M.Slot{tag, value}, max)
    return S.commit(vm, S.frame_stack(S.advance(pushed), S.stack(pushed)))

def literal_push(+vm: M.VM, +frame: M.Frame, value: U32, tag: U32, max: U32) -> Result<&2, &2, String, M.VM>:
  match tag:
    case 3: literal_string(vm, frame, value)
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

def step(+vm: M.VM, +frame: M.Frame, +method: M.LoadedMethod, instruction: M.Instruction) -> Result<&2, &2, String, M.VM>:


  M.Instruction{op, +a, b, c, offset} = instruction
  match op:
    case 0: Done{S.commit(vm, S.advance(frame))}
    case 79: array_store(vm, frame, 1)
    case 81: array_store(vm, frame, 3)
    case 83: array_store(vm, frame, 2)
    case 1: constant_push(vm, frame, 0, 3, method_max_stack(method))
    case 46: array_load(vm, frame, 1)
    case 48: array_load(vm, frame, 1)
    case 50: array_load(vm, frame, 2)
    case 2: constant_push(vm, frame, 4294967295, 1, method_max_stack(method))
    case 3: constant_push(vm, frame, 0, 1, method_max_stack(method))
    case 4: constant_push(vm, frame, 1, 1, method_max_stack(method))
    case 5: constant_push(vm, frame, 2, 1, method_max_stack(method))
    case 6: constant_push(vm, frame, 3, 1, method_max_stack(method))
    case 7: constant_push(vm, frame, 4, 1, method_max_stack(method))
    case 8: constant_push(vm, frame, 5, 1, method_max_stack(method))
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
    case 19: literal_push(vm, frame, a, b, method_max_stack(method))

    case 21:
      do Result<&2, &2, String, M.VM>:
        slot : M.Slot <- F.local(frame, a, 1)
        return S.commit(vm, S.frame_stack(S.advance(frame), Con{slot, S.stack(frame)}))
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
    case 175:
      do Result<&2, &2, String, M.VM>:
        popped : F.Popped <- F.pop(frame, 2)
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
    case 182: invoke_virtual(vm, S.advance(frame), a, b, c)
    case 183: invoke_special(vm, S.advance(frame), a, b, c)
    case 184: invoke_static(vm, S.advance(frame), a, b, c)
    case _: Fail{"UnsupportedOpcode: " ++ U32.show(op)}
def method_handlers(value: M.LoadedMethod) -> +List<M.Handler>:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}: handlers

def exception_handler(+pc: U32, +handlers: +List<M.Handler>) -> Maybe<&2, U32>:
  match handlers:
    case Nil{}: None{}
    case Con{M.Handler{start, end, target, catch}, rest}:
      Bool.pick(Maybe<&2, U32>, U32.is_ge(pc, start) && U32.is_lt(pc, end), Some{target}, exception_handler(pc, rest))

def frame_exception_handler_found(+frame: M.Frame, pc: U32, found: Maybe<&2, M.LoadedMethod>) -> Maybe<&2, U32>:
  match found:
    case None{}: None{}
    case Some{method}: exception_handler(pc, method_handlers(method))

def frame_exception_handler(vm: M.VM, +frame: M.Frame, pc: U32) -> Maybe<&2, U32>:
  frame_exception_handler_found(frame, pc, M.nth(M.LoadedMethod, S.methods(vm), S.method_id(frame)))

def exception_unwind_frame(error: String, +vm: M.VM, +caller: M.Frame, callers: +List<M.Frame>, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM, +found: Maybe<&2, U32>) -> M.VM:
  match found:
    case None{}: S.fail(vm, error)
    case Some{target}:
      +resumed = S.tick(S.commit(vm, S.frame_stack(S.frame_pc(caller, target), Con{M.Slot{3, 0}, Nil{}})))
      continue(S.status(resumed), fuel, resumed)

def exception_unwind(error: String, +vm: M.VM, +frames: +List<M.Frame>, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  match frames:
    case Nil{}: S.fail(vm, error)
    case Con{+current, rest}:
      match rest:
        case Nil{}: S.fail(vm, error)
        case Con{+caller, callers}:
          +next = S.with_frames(vm, Con{caller, callers})
          exception_unwind_frame(error, next, caller, callers, fuel, continue, frame_exception_handler(next, caller, S.invoke_pc(current)))

def exception_resume_found(error: String, +vm: M.VM, +frame: M.Frame, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM, found: Maybe<&2, U32>) -> M.VM:
  match found:
    case None{}: exception_unwind(error, vm, S.frames(vm), fuel, continue)
    case Some{target}:
      +next = S.tick(S.commit(vm, S.frame_stack(S.frame_pc(frame, target), Con{M.Slot{3, 0}, Nil{}})))
      continue(S.status(next), fuel, next)

def exception_resume(error: String, +vm: M.VM, +frame: M.Frame, method: M.LoadedMethod, fuel: Nat, continue: U32 -> Nat -> M.VM -> M.VM) -> M.VM:
  exception_resume_found(error, vm, frame, fuel, continue, exception_handler(S.pc(frame), method_handlers(method)))

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

@unsafe def loop_status(status: U32, fuel: Nat, +vm: M.VM) -> M.VM:
  match status:
    case 1: vm
    case 4: vm
    case 3: vm
    case _:
      match fuel:
        case 0n: S.with_status(vm, 3)
        case 1n+p: run_frames(p, vm, S.frames(vm), nextStatus => nextFuel => nextVm => loop_status(nextStatus, nextFuel, nextVm))

@unsafe def loop(fuel: Nat, +vm: M.VM) -> M.VM:
  loop_status(S.status(vm), fuel, vm)

def run(vm: M.VM, fuel: Nat) -> M.VM:
  loop(fuel, vm)
