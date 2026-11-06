import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../runtime/threads.bend as Th
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ../classfile/descriptor.bend as D
import ./outcome.bend as O
import ./library.bend as L

# The controlled native-library bridge (plan 05, slice 6). A `native` method
# with no MiniJRE intrinsic is bound lazily on its first call: the call becomes
# a NativeCall host effect that the host forwards to the supervised native
# helper process. Only portable values cross the boundary, flattened to words:
#   int/boolean/byte/char/short/float  one word (the raw bits)
#   long/double                        two words (high, low)
#   String                             [0] for null, else [1, n, UTF-16 units...]
#   primitive arrays                   [0] for null, else [2, n, element words...]
# Object references never leave the VM. The reply holds the result's words
# (String: [n, units...] or [0xFFFFFFFF] for null) followed by the new contents
# of every non-null array argument, which are copied back in one commit.

type Encoded is Data:
  Encoded{words: +List<U32>, arrays: +List<U32>}

def native_bit() -> U32:
  2147483648

# The intrinsic number the catalog gives an unbound native method.
def native_intrinsic(method: U32) -> U32:
  U32.or(native_bit(), method)

def is_native_intrinsic(+id: U32) -> Bool:
  U32.is_ne(U32.and(id, native_bit()), 0)

def slot_words(slot: M.Slot) -> +List<U32>:
  match slot:
    case M.Slot{tag, bits}: [bits]
    case M.Wide{tag, high, low}: [high, low]
    case M.Unusable{}: [0]

def values_words(values: +List<M.Slot>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{v, +rest}: M.append(U32, slot_words(v), values_words(rest))

def entry_parts(entry: M.HeapEntry) -> Encoded:
  match entry:
    case M.HeapEntry{class, +kind, element, fields, +values, +chars}:
      Bool.pick(Encoded, U32.is_eq(kind, 3), Encoded{Con{1, Con{M.length(U32, chars), chars}}, Nil{}}, Encoded{Con{2, Con{M.length(M.Slot, values), values_words(values)}}, Nil{}})

def supported_element(+tag: U32) -> Bool:
  U32.is_eq(tag, 66) || U32.is_eq(tag, 67) || U32.is_eq(tag, 68) || U32.is_eq(tag, 70) || U32.is_eq(tag, 73) || U32.is_eq(tag, 74) || U32.is_eq(tag, 83) || U32.is_eq(tag, 90)

def encoded_words(e: Encoded) -> +List<U32>:
  match e:
    case Encoded{words, arrays}: words

def reference_words(+vm: M.VM, +reference: U32, +array: Bool) -> Result<&2, &2, String, Encoded>:
  match reference:
    case 0: Done{Encoded{[0], Bool.pick(+List<U32>, array, [0], Nil{})}}
    case _:
      do Result<&2, &2, String, Encoded>:
        entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        +parts : Encoded = entry_parts(entry)
        return Encoded{encoded_words(parts), Bool.pick(+List<U32>, array, [reference], Nil{})}

def encoded_arrays(e: Encoded) -> +List<U32>:
  match e:
    case Encoded{words, arrays}: arrays

def unsupported(text: String) -> Result<&2, &2, String, Encoded>:
  Fail{"java/lang/UnsatisfiedLinkError: unsupported native parameter type " ++ text}

def encode_one(+vm: M.VM, +t: M.JvmType, +slot: M.Slot) -> Result<&2, &2, String, Encoded>:
  match t:
    case M.Primitive{tag}: Done{Encoded{slot_words(slot), Nil{}}}
    case M.ObjectType{+name}: Bool.pick(Result<&2, &2, String, Encoded>, String.eq(name, "java/lang/String"), reference_words(vm, M.slot_bits(slot), False{}), unsupported(name))
    case M.ArrayType{M.Primitive{+tag}}: Bool.pick(Result<&2, &2, String, Encoded>, supported_element(tag), reference_words(vm, M.slot_bits(slot), True{}), unsupported("array"))
    case M.ArrayType{other}: unsupported("array")

def encode_args(+vm: M.VM, +types: +List<M.JvmType>, +args: +List<M.Slot>) -> Result<&2, &2, String, Encoded>:
  match types args:
    case Nil{} _: Done{Encoded{Nil{}, Nil{}}}
    case Con{t, ts} Con{a, +rest}:
      do Result<&2, &2, String, Encoded>:
        +head : Encoded <- encode_one(vm, t, a)
        +tail : Encoded <- encode_args(vm, ts, rest)
        return Encoded{M.append(U32, encoded_words(head), encoded_words(tail)), M.append(U32, encoded_arrays(head), encoded_arrays(tail))}
    case Con{t, ts} Nil{}: Fail{"InvalidState: native argument count"}

def supported_result(t: M.JvmType) -> Bool:
  match t:
    case M.Primitive{tag}: True{}
    case M.ObjectType{+name}: String.eq(name, "java/lang/String")
    case _: False{}

# Instance natives receive no object: the receiver stays in the VM.
def explicit_args(isStatic: Bool, +args: +List<M.Slot>) -> +List<M.Slot>:
  match isStatic args:
    case True{} _: args
    case False{} Con{receiver, +rest}: rest
    case False{} Nil{}: Nil{}

def class_lock(+vm: M.VM, +owner: U32, +found: Maybe<&2, U32>) -> Result<&2, &2, String, H.Allocation>:
  match found:
    case Some{reference}: Done{H.Allocation{vm, reference}}
    case None{}: H.allocate(vm, H.class_mirror_entry(L.class_id(vm, "java/lang/Class"), owner))

def receiver_lock(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, H.Allocation>:
  match args:
    case Con{M.Slot{3, reference}, rest}: Done{H.Allocation{vm, reference}}
    case _: Fail{"InvalidState: native receiver"}

def lock_of(+vm: M.VM, +method: M.LoadedMethod, +isStatic: Bool, +args: +List<M.Slot>) -> Result<&2, &2, String, H.Allocation>:
  match isStatic:
    case True{}: class_lock(vm, M.loaded_method_owner(method), H.class_mirror(S.heap(vm), M.loaded_method_owner(method)))
    case False{}: receiver_lock(vm, args)

def suspend_call(+vm: M.VM, +effect: M.Effect) -> Result<&2, &2, String, O.Outcome>:
  Done{O.Suspend{S.with_status(S.with_effect(vm, effect), 5), effect}}

def call_effect(+vm: M.VM, +method: M.LoadedMethod, +descriptor: String, +isStatic: Bool, +encoded: Encoded, +lock: U32) -> M.Effect:
  M.NativeCall{M.loaded_method_id(method), L.class_name_text(vm, M.loaded_method_owner(method)), Sy.text(S.symbols(vm), M.loaded_method_name(method)), descriptor, isStatic, encoded_words(encoded), encoded_arrays(encoded), lock}

def call_entered(entered: Maybe<&2, M.VM>, +vm: M.VM, +method: M.LoadedMethod, +descriptor: String, +isStatic: Bool, +encoded: Encoded, +id: U32, +args: +List<M.Slot>, +object: U32) -> Result<&2, &2, String, O.Outcome>:
  match entered:
    case Some{+owned}: suspend_call(owned, call_effect(owned, method, descriptor, isStatic, encoded, object))
    case None{}: Done{L.monitor_park(vm, object, M.NeedIntrinsicRetry{id, args})}

# A synchronized native keeps its monitor until the call completes; when the
# monitor is taken the thread parks and the call is attempted again.
def call_locked(+vm: M.VM, +method: M.LoadedMethod, +descriptor: String, +isStatic: Bool, +encoded: Encoded, +id: U32, +args: +List<M.Slot>, +lock: H.Allocation) -> Result<&2, &2, String, O.Outcome>:
  match lock:
    case H.Allocation{+locked, +object}:
      call_entered(Th.enter(locked, object), locked, method, descriptor, isStatic, encoded, id, args, object)

def call_sync(synchronized: Bool, +vm: M.VM, +method: M.LoadedMethod, +descriptor: String, +isStatic: Bool, +id: U32, +args: +List<M.Slot>, +encoded: Encoded) -> Result<&2, &2, String, O.Outcome>:
  match synchronized:
    case False{}: suspend_call(vm, call_effect(vm, method, descriptor, isStatic, encoded, 0))
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        lock : H.Allocation <- lock_of(vm, method, isStatic, args)
        result : O.Outcome <- call_locked(vm, method, descriptor, isStatic, encoded, id, args, lock)
        return result

def call_encoded(+vm: M.VM, +method: M.LoadedMethod, +descriptor: String, +isStatic: Bool, +id: U32, +args: +List<M.Slot>, +encoded: Encoded) -> Result<&2, &2, String, O.Outcome>:
  call_sync(U32.is_ne(U32.and(M.loaded_method_flags(method), 32), 0), vm, method, descriptor, isStatic, id, args, encoded)

def call_parsed(+vm: M.VM, +method: M.LoadedMethod, +descriptor: String, +id: U32, +args: +List<M.Slot>, +parsed: M.Descriptor) -> Result<&2, &2, String, O.Outcome>:
  +isStatic : Bool = U32.is_ne(U32.and(M.loaded_method_flags(method), 8), 0)
  do Result<&2, &2, String, O.Outcome>:
    checked : Unit <- S.check(supported_result(D.result_type(parsed)), "java/lang/UnsatisfiedLinkError: unsupported native return type in " ++ descriptor)
    encoded : Encoded <- encode_args(vm, D.parameter_types(parsed), explicit_args(isStatic, args))
    result : O.Outcome <- call_encoded(vm, method, descriptor, isStatic, id, args, encoded)
    return result

# Intrinsic 0x80000000|method: call the plugin function bound to `method`.
def call(+id: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, M.nth(M.LoadedMethod, S.methods(vm), U32.and(id, 2147483647)), "InvalidState: native method id")
    +descriptor : String = Sy.text(S.symbols(vm), M.loaded_method_descriptor(method))
    parsed : M.Descriptor <- D.parse_method(descriptor)
    result : O.Outcome <- call_parsed(vm, method, descriptor, id, args, parsed)
    return result

# System.load (absolute path) and System.loadLibrary (logical name).
def load(+vm: M.VM, +args: +List<M.Slot>, +absolute: Bool) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, 0}, rest}: Fail{"java/lang/NullPointerException"}
    case Con{M.Slot{3, +reference}, rest}:
      do Result<&2, &2, String, O.Outcome>:
        chars : +List<U32> <- L.string_chars(vm, reference)
        +effect : M.Effect = M.LoadLibrary{L.utf16(chars, 0), absolute}
        result : O.Outcome <- suspend_call(vm, effect)
        return result
    case _: Fail{"InvalidState: System.load arguments"}

# ---- Completion --------------------------------------------------------------

type Decoded is Data:
  Decoded{vm: M.VM, value: Maybe<&2, M.Slot>, rest: +List<U32>}

def decoded_vm(d: Decoded) -> M.VM:
  match d:
    case Decoded{vm, value, rest}: vm

def decoded_value(d: Decoded) -> Maybe<&2, M.Slot>:
  match d:
    case Decoded{vm, value, rest}: value

def decoded_rest(d: Decoded) -> +List<U32>:
  match d:
    case Decoded{vm, value, rest}: rest

def short_reply() -> String:
  "java/lang/InternalError: truncated native reply"

def allocated_string(allocation: H.Allocation, rest: +List<U32>) -> Decoded:
  match allocation:
    case H.Allocation{vm, reference}: Decoded{vm, Some{M.Slot{3, reference}}, rest}

def decode_string(+vm: M.VM, +words: +List<U32>) -> Result<&2, &2, String, Decoded>:
  match words:
    case Con{4294967295, +rest}: Done{Decoded{vm, Some{M.Slot{3, 0}}, rest}}
    case Con{+n, +rest}:
      do Result<&2, &2, String, Decoded>:
        checked : Unit <- S.check(U32.is_le(n, M.length(U32, rest)), short_reply())
        allocation : H.Allocation <- H.allocate(vm, H.string_entry(L.class_id(vm, "java/lang/String"), M.take(U32, rest, U32.to_nat(n))))
        result : Decoded = allocated_string(allocation, M.drop(U32, rest, U32.to_nat(n)))
        return result
    case Nil{}: Fail{short_reply()}

# Results are normalized like the matching Java conversions.
def narrow(+tag: U32, +bits: U32) -> U32:
  match tag:
    case 90: Bool.pick(U32, U32.is_eq(bits, 0), 0, 1)
    case 66: Bool.pick(U32, U32.is_ge(U32.and(bits, 255), 128), U32.or(U32.and(bits, 255), 4294967040), U32.and(bits, 255))
    case 67: U32.and(bits, 65535)
    case 83: Bool.pick(U32, U32.is_ge(U32.and(bits, 65535), 32768), U32.or(U32.and(bits, 65535), 4294901760), U32.and(bits, 65535))
    case _: bits

def decode_primitive(+vm: M.VM, +tag: U32, +words: +List<U32>) -> Result<&2, &2, String, Decoded>:
  match tag words:
    case 86 _: Done{Decoded{vm, None{}, words}}
    case 74 Con{high, Con{low, +rest}}: Done{Decoded{vm, Some{M.Wide{4, high, low}}, rest}}
    case 68 Con{high, Con{low, +rest}}: Done{Decoded{vm, Some{M.Wide{5, high, low}}, rest}}
    case 70 Con{bits, +rest}: Done{Decoded{vm, Some{M.Slot{2, bits}}, rest}}
    case _ Con{bits, +rest}: Done{Decoded{vm, Some{M.Slot{1, narrow(tag, bits)}}, rest}}
    case _ Nil{}: Fail{short_reply()}

def decode_result(+vm: M.VM, +t: M.JvmType, +words: +List<U32>) -> Result<&2, &2, String, Decoded>:
  match t:
    case M.Primitive{tag}: decode_primitive(vm, tag, words)
    case _: decode_string(vm, words)

type Element is Data:
  Element{value: M.Slot, rest: +List<U32>}

def element_slot(+tag: U32, +words: +List<U32>) -> Result<&2, &2, String, Element>:
  match tag words:
    case 74 Con{high, Con{low, +rest}}: Done{Element{M.Wide{4, high, low}, rest}}
    case 68 Con{high, Con{low, +rest}}: Done{Element{M.Wide{5, high, low}, rest}}
    case 70 Con{bits, +rest}: Done{Element{M.Slot{2, bits}, rest}}
    case _ Con{bits, +rest}: Done{Element{M.Slot{1, narrow(tag, bits)}, rest}}
    case _ Nil{}: Fail{short_reply()}

type Elements is Data:
  Elements{values: +List<M.Slot>, rest: +List<U32>}

def element_cons(one: Element, +more: Elements) -> Elements:
  match one more:
    case Element{value, r} Elements{values, rest}: Elements{Con{value, values}, rest}

def element_rest(one: Element) -> +List<U32>:
  match one:
    case Element{value, rest}: rest

def elements(n: Nat, +tag: U32, +words: +List<U32>) -> Result<&2, &2, String, Elements>:
  match n:
    case 0n: Done{Elements{Nil{}, words}}
    case 1n+p:
      do Result<&2, &2, String, Elements>:
        +one : Element <- element_slot(tag, words)
        more : Elements <- elements(p, tag, element_rest(one))
        return element_cons(one, more)

def replace_values(entry: M.HeapEntry, +values: +List<M.Slot>) -> M.HeapEntry:
  match entry:
    case M.HeapEntry{class, kind, element, fields, old, chars}: M.HeapEntry{class, kind, element, fields, values, chars}

def entry_size(entry: M.HeapEntry) -> U32:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}: M.length(M.Slot, values)

def copied(+vm: M.VM, +reference: U32, +entry: M.HeapEntry, +filled: Elements) -> Decoded:
  match filled:
    case Elements{values, rest}: Decoded{H.put(vm, reference, replace_values(entry, values)), None{}, rest}

def copy_array(+vm: M.VM, +reference: U32, +tag: U32, +words: +List<U32>) -> Result<&2, &2, String, Decoded>:
  match reference:
    case 0: Done{Decoded{vm, None{}, words}}
    case _:
      do Result<&2, &2, String, Decoded>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        filled : Elements <- elements(U32.to_nat(entry_size(entry)), tag, words)
        result : Decoded = copied(vm, reference, entry, filled)
        return result

def array_tag(t: M.JvmType) -> U32:
  match t:
    case M.ArrayType{M.Primitive{tag}}: tag
    case _: 0

@unsafe def copy_back(+vm: M.VM, +types: +List<M.JvmType>, +arrays: +List<U32>, +words: +List<U32>) -> Result<&2, &2, String, M.VM>:
  match types:
    case Nil{}: Done{vm}
    case Con{t, ts}: copy_back_tag(array_tag(t), arrays, vm, ts, words)

@unsafe def copy_back_tag(+tag: U32, +arrays: +List<U32>, +vm: M.VM, ts: +List<M.JvmType>, +words: +List<U32>) -> Result<&2, &2, String, M.VM>:
  match tag arrays:
    case 0 _: copy_back(vm, ts, arrays, words)
    case _ Con{reference, more}:
      do Result<&2, &2, String, M.VM>:
        +done : Decoded <- copy_array(vm, reference, tag, words)
        result : M.VM <- copy_back(decoded_vm(done), ts, more, decoded_rest(done))
        return result
    case _ Nil{}: Done{vm}

type Finished is Data:
  Finished{vm: M.VM, value: Maybe<&2, M.Slot>}

def finish_parsed(+vm: M.VM, +arrays: +List<U32>, +words: +List<U32>, +parsed: M.Descriptor) -> Result<&2, &2, String, Finished>:
  do Result<&2, &2, String, Finished>:
    +result : Decoded <- decode_result(vm, D.result_type(parsed), words)
    updated : M.VM <- copy_back(decoded_vm(result), D.parameter_types(parsed), arrays, decoded_rest(result))
    return Finished{updated, decoded_value(result)}

def release(+vm: M.VM, +lock: U32) -> Result<&2, &2, String, M.VM>:
  match lock:
    case 0: Done{vm}
    case _: Th.exit(vm, lock)

# Decodes a completed NativeCall: the result value and copied-back arrays,
# committed together, and the synchronized monitor released.
def finish(+vm: M.VM, +descriptor: String, +arrays: +List<U32>, +lock: U32, +words: +List<U32>) -> Result<&2, &2, String, Finished>:
  do Result<&2, &2, String, Finished>:
    parsed : M.Descriptor <- D.parse_method(descriptor)
    released : M.VM <- release(vm, lock)
    result : Finished <- finish_parsed(released, arrays, words, parsed)
    return result
