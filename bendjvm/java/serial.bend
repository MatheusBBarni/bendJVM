import Base
import ../model.bend as M
import ../runtime/value.bend as V
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ../loader/class_loader.bend as CL
import ./outcome.bend as O
import ./library.bend as L
import ../runtime/wide.bend as W
import ./loader_state.bend as LS
import ./loaders.bend as LD

# Java object serialization (plan 03, C10): the JDK stream protocol
# (java.io.ObjectStreamConstants), class descriptors with declared or computed
# serialVersionUIDs, back references, proxies, enums, arrays, and the
# writeReplace/writeObject/readObject/readResolve callbacks.
#
# ObjectOutputStream state lives in bindings of the stream object (high ids, so
# they never collide with a subclass's fields): the target stream, the handle
# table, block-data mode, the pending block-data holder, the defaultWriteObject
# context and the replacement table. Bytes go straight to a ByteArrayOutputStream
# target, and are otherwise buffered in the stream's values until flush/close.
#
# ObjectInputStream reads a ByteArrayInputStream or resource stream in place.
# Any other InputStream is read through its Java read methods into a buffer:
# each reader task is a pure step over the VM, so a step that runs out of
# buffered bytes (or meets a class no loader has loaded yet) fails with a
# request, and read_guard performs the Java call and replays the step.

def none() -> U32:
  4294967295

def bind_target() -> U32:
  4294967050

def bind_handles() -> U32:
  4294967051

def bind_block() -> U32:
  4294967052

def bind_holder() -> U32:
  4294967053

def bind_object() -> U32:
  4294967054

def bind_class() -> U32:
  4294967055

def bind_subs() -> U32:
  4294967056

def bind_left() -> U32:
  4294967057

# The byte holder read in place: the source itself, or the buffer filled from it.
def bind_source() -> U32:
  4294967058

def bind_eof() -> U32:
  4294967059

def bind_depth() -> U32:
  4294967060

# The next object written or read is unshared (writeUnshared/readUnshared).
def bind_unshared() -> U32:
  4294967061

# Stream class descriptors read so far, by local class id.
def bind_descs() -> U32:
  4294967062

# A subclass made with the protected no-argument constructor
# (writeObjectOverride/readObjectOverride).
def bind_override() -> U32:
  4294967063

# enableReplaceObject (ObjectOutputStream) / enableResolveObject (ObjectInputStream).
def bind_replace() -> U32:
  4294967064

def bind_resolve() -> U32:
  4294967064

def bind_protocol() -> U32:
  4294967065

# The current PutField (ObjectOutputStream.putFields).
def bind_put() -> U32:
  4294967066

# Set while writeFatalException writes the exception.
def bind_fatal() -> U32:
  4294967067

# registerValidation callbacks: (object, priority) pairs, highest priority first.
def bind_validations() -> U32:
  4294967068

# Requests a reader step makes instead of failing (see read_guard).
def need_prefix() -> String:
  "serial:need:"

def class_prefix() -> String:
  "serial:class:"

def init_prefix() -> String:
  "serial:init:"

type Ref is Data:
  Ref{vm: M.VM, reference: U32}

# --- SHA-1 (FIPS 180-4), for ObjectStreamClass.computeDefaultSUID ---

def rotl(+x: U32, +left: Nat, +right: Nat) -> U32:
  U32.or(U32.shln(x, left), U32.shrn(x, right))

@unsafe def be_word(+bytes: +List<U32>) -> U32:
  match bytes:
    case Con{+a, Con{+b, Con{+c, Con{+d, rest}}}}: U32.or(U32.shln(a, 24n), U32.or(U32.shln(b, 16n), U32.or(U32.shln(c, 8n), d)))
    case _: 0

@unsafe def or_zero(found: Maybe<&2, U32>) -> U32:
  match found:
    case Some{+word}: word
    case None{}: 0

@unsafe def word_at(+words: +List<U32>, +index: U32) -> U32:
  or_zero(M.nth(U32, words, index))

@unsafe def chunk_words(+bytes: +List<U32>, +count: Nat) -> +List<U32>:
  match count:
    case 0n: Nil{}
    case 1n+ +remaining: Con{be_word(bytes), chunk_words(M.drop(U32, bytes, 4n), remaining)}

# w[16..79] = rotl1(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16]).
@unsafe def extend_words(+words: +List<U32>, +index: U32, +count: Nat) -> +List<U32>:
  match count:
    case 0n: words
    case 1n+ +remaining:
      +next : U32 = rotl(U32.xor(U32.xor(word_at(words, U32.sub(index, 3)), word_at(words, U32.sub(index, 8))), U32.xor(word_at(words, U32.sub(index, 14)), word_at(words, U32.sub(index, 16)))), 1n, 31n)
      extend_words(M.append(U32, words, [next]), U32.add(index, 1), remaining)

type Sha is Data:
  Sha{a: U32, b: U32, c: U32, d: U32, e: U32}

@unsafe def round_f(+index: U32, +b: U32, +c: U32, +d: U32) -> U32:
  Bool.pick(U32, U32.is_lt(index, 20), U32.or(U32.and(b, c), U32.and(U32.xor(b, 4294967295), d)),
    Bool.pick(U32, U32.is_lt(index, 40), U32.xor(U32.xor(b, c), d),
      Bool.pick(U32, U32.is_lt(index, 60), U32.or(U32.or(U32.and(b, c), U32.and(b, d)), U32.and(c, d)), U32.xor(U32.xor(b, c), d))))

@unsafe def round_k(+index: U32) -> U32:
  Bool.pick(U32, U32.is_lt(index, 20), 1518500249, Bool.pick(U32, U32.is_lt(index, 40), 1859775393, Bool.pick(U32, U32.is_lt(index, 60), 2400959708, 3395469782)))

@unsafe def rounds(+state: Sha, +words: +List<U32>, +index: U32) -> Sha:
  match words:
    case Nil{}: state
    case Con{+word, rest}: rounds(round_step(state, word, index), rest, U32.add(index, 1))

@unsafe def round_step(+state: Sha, +word: U32, +index: U32) -> Sha:
  match state:
    case Sha{+a, +b, +c, +d, +e}:
      Sha{U32.add(U32.add(rotl(a, 5n, 27n), round_f(index, b, c, d)), U32.add(U32.add(e, round_k(index)), word)), a, rotl(b, 30n, 2n), c, d}

@unsafe def add_state(+left: Sha, +right: Sha) -> Sha:
  match left right:
    case Sha{+a, +b, +c, +d, +e} Sha{+f, +g, +h, +i, +j}: Sha{U32.add(a, f), U32.add(b, g), U32.add(c, h), U32.add(d, i), U32.add(e, j)}

@unsafe def sha_chunks(+state: Sha, +bytes: +List<U32>, +count: Nat) -> Sha:
  match count:
    case 0n: state
    case 1n+ +remaining:
      +block : +List<U32> = M.take(U32, bytes, 64n)
      sha_chunks(add_state(state, rounds(state, extend_words(chunk_words(block, 16n), 16, 64n), 0)), M.drop(U32, bytes, 64n), remaining)

@unsafe def zero_bytes(+count: Nat) -> +List<U32>:
  match count:
    case 0n: Nil{}
    case 1n+ +remaining: Con{0, zero_bytes(remaining)}

@unsafe def sha_pad(+bytes: +List<U32>) -> +List<U32>:
  +length : U32 = M.length(U32, bytes)
  +zeros : U32 = U32.and(U32.sub(55, U32.and(length, 63)), 63)
  +bits : U32 = U32.mul(length, 8)
  M.append(U32, bytes, Con{128, M.append(U32, zero_bytes(U32.to_nat(zeros)), [0, 0, 0, 0, U32.shrn(bits, 24n), U32.and(U32.shrn(bits, 16n), 255), U32.and(U32.shrn(bits, 8n), 255), U32.and(bits, 255)])})

@unsafe def word_bytes(+word: U32) -> +List<U32>:
  [U32.shrn(word, 24n), U32.and(U32.shrn(word, 16n), 255), U32.and(U32.shrn(word, 8n), 255), U32.and(word, 255)]

@unsafe def digest_bytes(+state: Sha) -> +List<U32>:
  match state:
    case Sha{+a, +b, +c, +d, +e}: M.append(U32, word_bytes(a), M.append(U32, word_bytes(b), M.append(U32, word_bytes(c), M.append(U32, word_bytes(d), word_bytes(e)))))

@unsafe def sha1(+bytes: +List<U32>) -> +List<U32>:
  +padded : +List<U32> = sha_pad(bytes)
  digest_bytes(sha_chunks(Sha{1732584193, 4023233417, 2562383102, 271733878, 3285377520}, padded, U32.to_nat(U32.shrn(M.length(U32, padded), 6n))))

# The first eight digest bytes, little-endian, as a long.
@unsafe def suid_words(+digest: +List<U32>) -> M.Slot:
  M.Wide{4, U32.or(U32.shln(word_at(digest, 7), 24n), U32.or(U32.shln(word_at(digest, 6), 16n), U32.or(U32.shln(word_at(digest, 5), 8n), word_at(digest, 4)))),
    U32.or(U32.shln(word_at(digest, 3), 24n), U32.or(U32.shln(word_at(digest, 2), 16n), U32.or(U32.shln(word_at(digest, 1), 8n), word_at(digest, 0))))}

# DataOutput.writeUTF / writeInt bytes (modified UTF-8).
@unsafe def utf_bytes(+text: String) -> +List<U32>:
  +body : +List<U32> = modified_utf8(L.units_from_string(text))
  M.append(U32, [U32.and(U32.shrn(M.length(U32, body), 8n), 255), U32.and(M.length(U32, body), 255)], body)

@unsafe def modified_utf8(+units: +List<U32>) -> +List<U32>:
  match units:
    case Nil{}: Nil{}
    case Con{+unit, rest}: M.append(U32, unit_utf8(unit), modified_utf8(rest))

@unsafe def unit_utf8(+unit: U32) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_ge(unit, 1) && U32.is_le(unit, 127), [unit],
    Bool.pick(+List<U32>, U32.is_le(unit, 2047), [U32.or(192, U32.shrn(unit, 6n)), U32.or(128, U32.and(unit, 63))],
      [U32.or(224, U32.shrn(unit, 12n)), U32.or(128, U32.and(U32.shrn(unit, 6n), 63)), U32.or(128, U32.and(unit, 63))]))

@unsafe def int_bytes(+value: U32) -> +List<U32>:
  word_bytes(value)

@unsafe def short_bytes(+value: U32) -> +List<U32>:
  [U32.and(U32.shrn(value, 8n), 255), U32.and(value, 255)]

# Modified UTF-8 back to UTF-16 units.
@unsafe def utf_text(+bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+a, rest}: utf_lead(U32.is_ge(a, 224), U32.is_ge(a, 192), a, rest)

@unsafe def utf_lead(+three: Bool, +two: Bool, +a: U32, +rest: +List<U32>) -> +List<U32>:
  match three:
    case True{}: Con{U32.or(U32.shln(U32.and(a, 15), 12n), U32.or(U32.shln(U32.and(word_at(rest, 0), 63), 6n), U32.and(word_at(rest, 1), 63))), utf_text(M.drop(U32, rest, 2n))}
    case False{}: utf_lead_two(two, a, rest)

@unsafe def utf_lead_two(+two: Bool, +a: U32, +rest: +List<U32>) -> +List<U32>:
  match two:
    case True{}: Con{U32.or(U32.shln(U32.and(a, 31), 6n), U32.and(word_at(rest, 0), 63)), utf_text(M.drop(U32, rest, 1n))}
    case False{}: Con{a, utf_text(rest)}

# --- Heap helpers ---

@unsafe def entry_or_empty(found: Result<&2, &2, String, M.HeapEntry>) -> M.HeapEntry:
  match found:
    case Fail{error}: M.HeapEntry{none(), 0, 0, Nil{}, Nil{}, Nil{}}
    case Done{+entry}: entry

@unsafe def entry_of(+vm: M.VM, +reference: U32) -> M.HeapEntry:
  entry_or_empty(H.get(S.heap(vm), reference))

@unsafe def binding_of(+vm: M.VM, +reference: U32, +index: U32) -> U32:
  L.field_bits(L.entry_fields(entry_of(vm, reference)), index)

@unsafe def values_of(+vm: M.VM, +reference: U32) -> +List<M.Slot>:
  L.entry_values(entry_of(vm, reference))

@unsafe def kind_of(+vm: M.VM, +reference: U32) -> U32:
  L.entry_kind(entry_of(vm, reference))

@unsafe def class_of(+vm: M.VM, +reference: U32) -> U32:
  H.entry_class(entry_of(vm, reference))

@unsafe def with_values(+entry: M.HeapEntry, +values: +List<M.Slot>) -> M.HeapEntry:
  M.HeapEntry{H.entry_class(entry), L.entry_kind(entry), L.entry_element(entry), L.entry_fields(entry), values, L.entry_chars(entry)}

@unsafe def with_binding(+entry: M.HeapEntry, +index: U32, +value: M.Slot) -> M.HeapEntry:
  M.HeapEntry{H.entry_class(entry), L.entry_kind(entry), L.entry_element(entry), H.binding_set(L.entry_fields(entry), index, value), L.entry_values(entry), L.entry_chars(entry)}

@unsafe def set_values(+vm: M.VM, +reference: U32, +values: +List<M.Slot>) -> M.VM:
  H.put(vm, reference, with_values(entry_of(vm, reference), values))

@unsafe def set_binding(+vm: M.VM, +reference: U32, +index: U32, +value: M.Slot) -> M.VM:
  H.put(vm, reference, with_binding(entry_of(vm, reference), index, value))

@unsafe def byte_slots(+bytes: +List<U32>) -> +List<M.Slot>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: Con{M.Slot{1, U32.and(b, 255)}, byte_slots(rest)}

@unsafe def slot_bytes(+slots: +List<M.Slot>) -> +List<U32>:
  match slots:
    case Nil{}: Nil{}
    case Con{+slot, rest}: Con{U32.and(M.slot_bits(slot), 255), slot_bytes(rest)}

@unsafe def append_values(+vm: M.VM, +reference: U32, +slots: +List<M.Slot>) -> M.VM:
  set_values(vm, reference, M.append(M.Slot, values_of(vm, reference), slots))

@unsafe def plain_entry(+vm: M.VM) -> M.HeapEntry:
  H.object_entry(L.class_id(vm, "java/lang/Object"), Nil{})

@unsafe def allocated(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, Ref>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{+vm, +reference}}: Done{Ref{vm, reference}}

@unsafe def returned_ref(result: Result<&2, &2, String, O.Outcome>) -> Result<&2, &2, String, Ref>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+outcome}: outcome_ref(outcome)

@unsafe def outcome_ref(+outcome: O.Outcome) -> Result<&2, &2, String, Ref>:
  match outcome:
    case O.Returned{+vm, Some{+slot}}: Done{Ref{vm, M.slot_bits(slot)}}
    case _: Fail{"InvalidState: serialization reference"}

@unsafe def ref_vm(+value: Ref) -> M.VM:
  match value:
    case Ref{+vm, reference}: vm

@unsafe def ref_reference(+value: Ref) -> U32:
  match value:
    case Ref{vm, +reference}: reference

@unsafe def same_bool(+left: Bool, +right: Bool) -> Bool:
  match left right:
    case True{} True{}: True{}
    case False{} False{}: True{}
    case _ _: False{}

@unsafe def is_true(+value: U32) -> Bool:
  U32.is_ne(value, 0)

@unsafe def is_reference_code(+code: U32) -> Bool:
  U32.is_eq(code, 76) || U32.is_eq(code, 91)

# --- Class descriptors (ObjectStreamClass) ---

type SerialInfo is Data:
  SerialInfo{name: String, flags: U32, fields: +List<M.SerialField>, super: U32}

@unsafe def wide(+high: U32, +low: U32) -> M.Slot:
  M.Wide{4, high, low}

@unsafe def is_serializable(+vm: M.VM, +class: U32) -> Bool:
  H.assignable(S.classes(vm), S.symbols(vm), class, L.class_id(vm, "java/io/Serializable"))

@unsafe def parent_of(+vm: M.VM, +class: U32) -> U32:
  L.class_parent_found(M.nth(M.LoadedClass, S.classes(vm), class))

@unsafe def is_enum(+vm: M.VM, +class: U32) -> Bool:
  U32.is_ne(class, L.class_id(vm, "java/lang/Enum")) && H.hierarchy(S.classes(vm), class, L.class_id(vm, "java/lang/Enum"))

# The nearest superclass, when it is serializable (ObjectStreamClass.superDesc).
@unsafe def serial_super(+vm: M.VM, +class: U32) -> U32:
  +parent : U32 = parent_of(vm, class)
  Bool.pick(U32, U32.is_ne(parent, none()) && is_serializable(vm, parent), parent, none())

@unsafe def string_fields(+names: +List<String>, +first: U32) -> +List<M.SerialField>:
  match names:
    case Nil{}: Nil{}
    case Con{+name, rest}: Con{M.SerialField{76, name, "Ljava/lang/String;", first}, string_fields(rest, U32.add(first, 1))}

@unsafe def value_slot(found: Result<&2, &2, String, U32>) -> U32:
  match found:
    case Fail{error}: 0
    case Done{+id}: id

# MiniJRE classes with the JDK's serialVersionUID and serializable fields, read
# from this VM's entry layouts (boxes keep `value` in binding 0, Long and Double
# in their declared field).
@unsafe def known_index(+name: String) -> U32:
  Bool.pick(U32, String.eq(name, "java/lang/String"), 1,
  Bool.pick(U32, String.eq(name, "java/lang/Enum"), 2,
  Bool.pick(U32, String.eq(name, "java/lang/Number"), 3,
  Bool.pick(U32, String.eq(name, "java/lang/Integer"), 4,
  Bool.pick(U32, String.eq(name, "java/lang/Long"), 5,
  Bool.pick(U32, String.eq(name, "java/lang/Short"), 6,
  Bool.pick(U32, String.eq(name, "java/lang/Byte"), 7,
  Bool.pick(U32, String.eq(name, "java/lang/Character"), 8,
  Bool.pick(U32, String.eq(name, "java/lang/Boolean"), 9,
  Bool.pick(U32, String.eq(name, "java/lang/Float"), 10,
  Bool.pick(U32, String.eq(name, "java/lang/Double"), 11,
  Bool.pick(U32, String.eq(name, "java/lang/reflect/Proxy"), 12,
  Bool.pick(U32, String.eq(name, "java/lang/invoke/SerializedLambda"), 13,
  Bool.pick(U32, String.eq(name, "java/lang/Throwable"), 14, 0))))))))))))))

@unsafe def known_suid(+index: U32) -> M.Slot:
  match index:
    case 1: wide(2700125240, 2050732866)
    case 2: wide(0, 0)
    case 3: wide(2259457309, 194306187)
    case 4: wide(316842148, 4152461112)
    case 5: wide(999023760, 3431932895)
    case 6: wide(1749890835, 878762578)
    case 7: wide(2622382212, 3998283036)
    case 8: wide(881543129, 1796875896)
    case 9: wide(3441455744, 3583834862)
    case 10: wide(3673016738, 3678204140)
    case 11: wide(2159264330, 694942468)
    case 12: wide(3777485344, 3423617995)
    case 13: wide(1868681364, 740898437)
    case 14: wide(3586536743, 964147403)
    case _: wide(0, 0)

@unsafe def known_info(+vm: M.VM, +index: U32, +name: String) -> SerialInfo:
  known_info_at(index, L.class_display_name(name), L.class_id(vm, "java/lang/Number"), vm)

@unsafe def known_info_at(+index: U32, +display: String, +number: U32, +vm: M.VM) -> SerialInfo:
  match index:
    case 1: SerialInfo{display, 2, Nil{}, none()}
    case 2: SerialInfo{display, 18, Nil{}, none()}
    case 3: SerialInfo{display, 2, Nil{}, none()}
    case 4: SerialInfo{display, 2, [M.SerialField{73, "value", "", 0}], number}
    case 5: SerialInfo{display, 2, [M.SerialField{74, "value", "", value_slot(L.wrapper_value_field_id(vm, "java/lang/Long", "J"))}], number}
    case 6: SerialInfo{display, 2, [M.SerialField{83, "value", "", 0}], number}
    case 7: SerialInfo{display, 2, [M.SerialField{66, "value", "", 0}], number}
    case 8: SerialInfo{display, 2, [M.SerialField{67, "value", "", 0}], none()}
    case 9: SerialInfo{display, 2, [M.SerialField{90, "value", "", 0}], none()}
    case 10: SerialInfo{display, 2, [M.SerialField{70, "value", "", 0}], number}
    case 11: SerialInfo{display, 2, [M.SerialField{68, "value", "", value_slot(L.wrapper_value_field_id(vm, "java/lang/Double", "D"))}], number}
    case 12: SerialInfo{display, 2, [M.SerialField{76, "h", "Ljava/lang/reflect/InvocationHandler;", 0}], none()}
    case 13: SerialInfo{display, 2, M.append(M.SerialField, [M.SerialField{73, "implMethodKind", "", 4}, M.SerialField{91, "capturedArgs", "[Ljava/lang/Object;", 9}, M.SerialField{76, "capturingClass", "Ljava/lang/Class;", 0}],
      M.append(M.SerialField, string_fields(["functionalInterfaceClass", "functionalInterfaceMethodName", "functionalInterfaceMethodSignature"], 1), string_fields(["implClass", "implMethodName", "implMethodSignature", "instantiatedMethodType"], 5))), none()}
    # Throwable keeps its message in binding 0 and its cause in binding 1.
    case 14: SerialInfo{display, 2, [M.SerialField{76, "cause", "Ljava/lang/Throwable;", 1}, M.SerialField{76, "detailMessage", "Ljava/lang/String;", 0}], none()}
    case _: SerialInfo{display, 0, Nil{}, none()}

# ObjectStreamClass.lookupAny: known MiniJRE layouts, enums, ordinary
# serializable classes (arrays included) and non-serializable classes.
@unsafe def serial_info(+vm: M.VM, +class: U32) -> SerialInfo:
  +name : String = L.class_name_text(vm, class)
  +index : U32 = known_index(name)
  serial_info_known(U32.is_ne(index, 0), vm, class, index, name)

@unsafe def serial_info_known(+known: Bool, +vm: M.VM, +class: U32, +index: U32, +name: String) -> SerialInfo:
  match known:
    case True{}: known_info(vm, index, name)
    case False{}: serial_info_enum(is_enum(vm, class), vm, class, name)

@unsafe def serial_info_enum(+enum: Bool, +vm: M.VM, +class: U32, +name: String) -> SerialInfo:
  match enum:
    case True{}: SerialInfo{L.class_display_name(name), 18, Nil{}, serial_super(vm, class)}
    case False{}: serial_info_plain(is_serializable(vm, class), vm, class, name)

@unsafe def is_externalizable(+vm: M.VM, +class: U32) -> Bool:
  H.assignable(S.classes(vm), S.symbols(vm), class, L.class_id(vm, "java/io/Externalizable"))

@unsafe def serial_info_plain(+serializable: Bool, +vm: M.VM, +class: U32, +name: String) -> SerialInfo:
  match serializable:
    case False{}: SerialInfo{L.class_display_name(name), 0, Nil{}, none()}
    case True{}: serial_info_kind(is_externalizable(vm, class), vm, class, name)

# Externalizable classes: SC_EXTERNALIZABLE | SC_BLOCK_DATA and no fields.
@unsafe def serial_info_kind(+external: Bool, +vm: M.VM, +class: U32, +name: String) -> SerialInfo:
  match external:
    case True{}: SerialInfo{L.class_display_name(name), 12, Nil{}, serial_super(vm, class)}
    case False{}:
      +custom : Bool = has_private(vm, class, "writeObject", "(Ljava/io/ObjectOutputStream;)V")
      SerialInfo{L.class_display_name(name), Bool.pick(U32, custom, 3, 2), sort_fields(class_fields(vm, class), Nil{}), serial_super(vm, class)}

# serialPersistentFields (private static final ObjectStreamField[]) when the
# class declares a non-null one, else the non-static, non-transient fields.
@unsafe def persistent_field(+vm: M.VM, +class: U32) -> Maybe<&2, U32>:
  persistent_found(L.find_declared_field(S.fields(vm), class, "serialPersistentFields", S.symbols(vm)), vm)

@unsafe def persistent_found(found: Maybe<&2, M.LoadedField>, +vm: M.VM) -> Maybe<&2, U32>:
  match found:
    case None{}: None{}
    case Some{+field}:
      +valid : Bool = U32.is_eq(U32.and(M.loaded_field_flags(field), 26), 26) && String.eq(Sy.text(S.symbols(vm), M.loaded_field_descriptor(field)), "[Ljava/io/ObjectStreamField;")
      Bool.pick(Maybe<&2, U32>, valid, Some{M.loaded_field_id(field)}, None{})

@unsafe def class_fields(+vm: M.VM, +class: U32) -> +List<M.SerialField>:
  class_fields_declared(persistent_field(vm, class), vm, class)

@unsafe def class_fields_declared(found: Maybe<&2, U32>, +vm: M.VM, +class: U32) -> +List<M.SerialField>:
  match found:
    case None{}: serial_fields(vm, S.fields(vm), class)
    case Some{+field}: class_fields_array(M.slot_bits(slot_or_null(H.binding_find(S.statics(vm), field))), vm, class)

@unsafe def class_fields_array(+array: U32, +vm: M.VM, +class: U32) -> +List<M.SerialField>:
  match array:
    case 0: serial_fields(vm, S.fields(vm), class)
    case +reference: persistent_fields(vm, class, values_of(vm, reference))

# Each ObjectStreamField binds to the class's own non-static field of the same
# name and type, if there is one.
@unsafe def persistent_fields(+vm: M.VM, +class: U32, +elements: +List<M.Slot>) -> +List<M.SerialField>:
  match elements:
    case Nil{}: Nil{}
    case Con{+element, rest}:
      +osf : U32 = M.slot_bits(element)
      +name : String = string_or_empty(L.string_text(vm, binding_of(vm, osf, 0)))
      +signature : String = string_or_empty(L.string_text(vm, binding_of(vm, osf, 2)))
      +code : U32 = field_code(signature)
      +slot : U32 = bound_field(L.find_declared_field(S.fields(vm), class, name, S.symbols(vm)), vm, signature)
      Con{M.SerialField{code, name, Bool.pick(String, is_reference_code(code), signature, ""), slot}, persistent_fields(vm, class, rest)}

@unsafe def bound_field(found: Maybe<&2, M.LoadedField>, +vm: M.VM, +signature: String) -> U32:
  match found:
    case None{}: none()
    case Some{+field}: Bool.pick(U32, U32.is_eq(U32.and(M.loaded_field_flags(field), 8), 0) && String.eq(Sy.text(S.symbols(vm), M.loaded_field_descriptor(field)), signature), M.loaded_field_id(field), none())

# A class declaring serialPersistentFields is initialized before its fields
# are read (the JDK reads the array reflectively).
@unsafe def needs_init(+vm: M.VM, +class: U32) -> Bool:
  is_some_field(persistent_field(vm, class)) && class_uninitialized(class_state_of(M.nth(M.LoadedClass, S.classes(vm), class)))

@unsafe def class_state_of(found: Maybe<&2, M.LoadedClass>) -> U32:
  match found:
    case None{}: 2
    case Some{+loaded}: M.loaded_class_state(loaded)

@unsafe def is_some_field(found: Maybe<&2, U32>) -> Bool:
  match found:
    case None{}: False{}
    case Some{field}: True{}

@unsafe def class_uninitialized(+state: U32) -> Bool:
  U32.is_ne(state, 1) && U32.is_ne(state, 2)

@unsafe def info_name(+info: SerialInfo) -> String:
  match info:
    case SerialInfo{+name, flags, fields, super}: name

@unsafe def info_flags_of(+info: SerialInfo) -> U32:
  match info:
    case SerialInfo{name, +flags, fields, super}: flags

@unsafe def info_fields_of(+info: SerialInfo) -> +List<M.SerialField>:
  match info:
    case SerialInfo{name, flags, +fields, super}: fields

@unsafe def info_super_of(+info: SerialInfo) -> U32:
  match info:
    case SerialInfo{name, flags, fields, +super}: super

@unsafe def info_flags(+vm: M.VM, +class: U32) -> U32:
  info_flags_of(serial_info(vm, class))

@unsafe def info_fields(+vm: M.VM, +class: U32) -> +List<M.SerialField>:
  info_fields_of(serial_info(vm, class))

@unsafe def info_super(+vm: M.VM, +class: U32) -> U32:
  info_super_of(serial_info(vm, class))

# The serialVersionUID a descriptor carries: known, declared, or computed.
@unsafe def class_suid(+vm: M.VM, +class: U32) -> M.Slot:
  +name : String = L.class_name_text(vm, class)
  +index : U32 = known_index(name)
  class_suid_known(U32.is_ne(index, 0), vm, class, index)

@unsafe def class_suid_known(+known: Bool, +vm: M.VM, +class: U32, +index: U32) -> M.Slot:
  match known:
    case True{}: known_suid(index)
    case False{}: class_suid_kind(is_enum(vm, class) || Bool.not(is_serializable(vm, class)), vm, class)

@unsafe def class_suid_kind(+zero: Bool, +vm: M.VM, +class: U32) -> M.Slot:
  match zero:
    case True{}: wide(0, 0)
    case False{}: declared_suid(declared_suid_field(S.fields(vm), class, Sy.find(S.symbols(vm), "serialVersionUID"), Sy.find(S.symbols(vm), "J")), vm, class)

@unsafe def declared_suid(found: Maybe<&2, U32>, +vm: M.VM, +class: U32) -> M.Slot:
  match found:
    case Some{+field}: suid_static(H.binding_find(S.statics(vm), field), vm, class)
    case None{}: default_suid(vm, class)

@unsafe def suid_static(found: Maybe<&2, M.Slot>, +vm: M.VM, +class: U32) -> M.Slot:
  match found:
    case Some{M.Wide{tag, +high, +low}}: M.Wide{4, high, low}
    case _: default_suid(vm, class)

@unsafe def declared_suid_field(+fields: +List<M.LoadedField>, +class: U32, +name: U32, +descriptor: U32) -> Maybe<&2, U32>:
  match fields:
    case Nil{}: None{}
    case Con{+field, rest}:
      +hit : Bool = U32.is_eq(M.loaded_field_owner(field), class) && U32.is_eq(M.loaded_field_name(field), name) && U32.is_eq(M.loaded_field_descriptor(field), descriptor) && U32.is_eq(U32.and(M.loaded_field_flags(field), 24), 24)
      declared_suid_step(hit, field, rest, class, name, descriptor)

@unsafe def declared_suid_step(+hit: Bool, +field: M.LoadedField, +rest: +List<M.LoadedField>, +class: U32, +name: U32, +descriptor: U32) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{M.loaded_field_id(field)}
    case False{}: declared_suid_field(rest, class, name, descriptor)

@unsafe def has_private(+vm: M.VM, +class: U32, +name: String, +descriptor: String) -> Bool:
  private_method(L.own_method(S.methods(vm), class, Sy.find(S.symbols(vm), name), Sy.find(S.symbols(vm), descriptor)))

@unsafe def private_method(found: Maybe<&2, M.LoadedMethod>) -> Bool:
  match found:
    case None{}: False{}
    case Some{+method}: U32.is_ne(U32.and(M.loaded_method_flags(method), 2), 0) && U32.is_eq(U32.and(M.loaded_method_flags(method), 8), 0)

@unsafe def field_code(+descriptor: String) -> U32:
  match descriptor:
    case SCon{Chr{+c}, rest}: c
    case SNil{}: 76

# Instance fields that are neither static nor transient.
@unsafe def serial_fields(+vm: M.VM, +fields: +List<M.LoadedField>, +class: U32) -> +List<M.SerialField>:
  match fields:
    case Nil{}: Nil{}
    case Con{+field, rest}:
      +keep : Bool = U32.is_eq(M.loaded_field_owner(field), class) && U32.is_eq(U32.and(M.loaded_field_flags(field), 136), 0)
      serial_fields_step(keep, vm, field, rest, class)

@unsafe def serial_fields_step(+keep: Bool, +vm: M.VM, +field: M.LoadedField, +rest: +List<M.LoadedField>, +class: U32) -> +List<M.SerialField>:
  match keep:
    case False{}: serial_fields(vm, rest, class)
    case True{}:
      +descriptor : String = Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))
      +code : U32 = field_code(descriptor)
      Con{M.SerialField{code, Sy.text(S.symbols(vm), M.loaded_field_name(field)), Bool.pick(String, is_reference_code(code), descriptor, ""), M.loaded_field_id(field)}, serial_fields(vm, rest, class)}

@unsafe def text_before(+left: String, +right: String) -> Bool:
  V.negative(L.units_compare(L.units_from_string(left), L.units_from_string(right)))

# ObjectStreamField order: primitives first, then by name.
@unsafe def field_before(+left: M.SerialField, +right: M.SerialField) -> Bool:
  match left right:
    case M.SerialField{+lc, +ln, ls, li} M.SerialField{+rc, +rn, rs, ri}:
      +lp : Bool = Bool.not(is_reference_code(lc))
      +rp : Bool = Bool.not(is_reference_code(rc))
      Bool.pick(Bool, Bool.not(same_bool(lp, rp)), lp, text_before(ln, rn))

@unsafe def sort_fields(+fields: +List<M.SerialField>, +sorted: +List<M.SerialField>) -> +List<M.SerialField>:
  match fields:
    case Nil{}: sorted
    case Con{+field, rest}: sort_fields(rest, insert_field(field, sorted))

@unsafe def insert_field(+field: M.SerialField, +sorted: +List<M.SerialField>) -> +List<M.SerialField>:
  match sorted:
    case Nil{}: [field]
    case Con{+head, rest}: insert_field_step(field_before(field, head), field, head, rest)

@unsafe def insert_field_step(+before: Bool, +field: M.SerialField, +head: M.SerialField, +rest: +List<M.SerialField>) -> +List<M.SerialField>:
  match before:
    case True{}: Con{field, Con{head, rest}}
    case False{}: Con{head, insert_field(field, rest)}

# --- computeDefaultSUID ---

type Member is Data:
  Member{name: String, flags: U32, signature: String}

@unsafe def member_before(+left: Member, +right: Member) -> Bool:
  match left right:
    case Member{+ln, lf, +ls} Member{+rn, rf, +rs}:
      +by_name : U32 = L.units_compare(L.units_from_string(ln), L.units_from_string(rn))
      Bool.pick(Bool, U32.is_eq(by_name, 0), text_before(ls, rs), V.negative(by_name))

@unsafe def sort_members(+members: +List<Member>, +sorted: +List<Member>) -> +List<Member>:
  match members:
    case Nil{}: sorted
    case Con{+member, rest}: sort_members(rest, insert_member(member, sorted))

@unsafe def insert_member(+member: Member, +sorted: +List<Member>) -> +List<Member>:
  match sorted:
    case Nil{}: [member]
    case Con{+head, rest}: insert_member_step(member_before(member, head), member, head, rest)

@unsafe def insert_member_step(+before: Bool, +member: Member, +head: Member, +rest: +List<Member>) -> +List<Member>:
  match before:
    case True{}: Con{member, Con{head, rest}}
    case False{}: Con{head, insert_member(member, rest)}

@unsafe def member_bytes(+members: +List<Member>) -> +List<U32>:
  match members:
    case Nil{}: Nil{}
    case Con{Member{+name, +flags, +signature}, rest}: M.append(U32, utf_bytes(name), M.append(U32, int_bytes(flags), M.append(U32, utf_bytes(signature), member_bytes(rest))))

@unsafe def name_bytes(+members: +List<Member>) -> +List<U32>:
  match members:
    case Nil{}: Nil{}
    case Con{Member{+name, flags, signature}, rest}: M.append(U32, utf_bytes(name), name_bytes(rest))

@unsafe def dots(+text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{Chr{47}, rest}: SCon{Chr{46}, dots(rest)}
    case SCon{+c, rest}: SCon{c, dots(rest)}

# Fields, except private static and private transient ones.
@unsafe def suid_fields(+vm: M.VM, +fields: +List<M.LoadedField>, +class: U32) -> +List<Member>:
  match fields:
    case Nil{}: Nil{}
    case Con{+field, rest}:
      +flags : U32 = M.loaded_field_flags(field)
      +skip : Bool = U32.is_ne(U32.and(flags, 2), 0) && U32.is_ne(U32.and(flags, 136), 0)
      suid_fields_step(U32.is_eq(M.loaded_field_owner(field), class) && Bool.not(skip), vm, field, rest, class)

@unsafe def suid_fields_step(+keep: Bool, +vm: M.VM, +field: M.LoadedField, +rest: +List<M.LoadedField>, +class: U32) -> +List<Member>:
  match keep:
    case False{}: suid_fields(vm, rest, class)
    case True{}: Con{Member{Sy.text(S.symbols(vm), M.loaded_field_name(field)), U32.and(M.loaded_field_flags(field), 223), Sy.text(S.symbols(vm), M.loaded_field_descriptor(field))}, suid_fields(vm, rest, class)}

# Non-private constructors (when `constructors`) or methods, signatures dotted.
@unsafe def suid_methods(+vm: M.VM, +methods: +List<M.LoadedMethod>, +class: U32, +constructors: Bool) -> +List<Member>:
  match methods:
    case Nil{}: Nil{}
    case Con{+method, rest}:
      +name : String = Sy.text(S.symbols(vm), M.loaded_method_name(method))
      +ctor : Bool = String.eq(name, "<init>")
      +keep : Bool = U32.is_eq(M.loaded_method_owner(method), class) && U32.is_eq(U32.and(M.loaded_method_flags(method), 2), 0) && Bool.not(String.eq(name, "<clinit>")) && same_bool(constructors, ctor)
      suid_methods_step(keep, vm, method, name, rest, class, constructors)

@unsafe def suid_methods_step(+keep: Bool, +vm: M.VM, +method: M.LoadedMethod, +name: String, +rest: +List<M.LoadedMethod>, +class: U32, +constructors: Bool) -> +List<Member>:
  match keep:
    case False{}: suid_methods(vm, rest, class, constructors)
    case True{}: Con{Member{name, U32.and(M.loaded_method_flags(method), 3391), dots(Sy.text(S.symbols(vm), M.loaded_method_descriptor(method)))}, suid_methods(vm, rest, class, constructors)}

@unsafe def class_interfaces(found: Maybe<&2, M.LoadedClass>) -> +List<U32>:
  match found:
    case None{}: Nil{}
    case Some{+value}: M.loaded_class_interfaces(value)

@unsafe def interfaces_of(+vm: M.VM, +class: U32) -> +List<U32>:
  class_interfaces(M.nth(M.LoadedClass, S.classes(vm), class))

@unsafe def interface_members(+vm: M.VM, +ids: +List<U32>) -> +List<Member>:
  match ids:
    case Nil{}: Nil{}
    case Con{+id, rest}: Con{Member{L.class_display_name(L.class_name_text(vm, id)), 0, ""}, interface_members(vm, rest)}

@unsafe def class_initializer(found: Maybe<&2, M.LoadedClass>) -> Bool:
  match found:
    case None{}: False{}
    case Some{+value}: U32.is_ne(M.loaded_class_initializer(value), none())

@unsafe def has_clinit(+vm: M.VM, +class: U32) -> Bool:
  class_initializer(M.nth(M.LoadedClass, S.classes(vm), class))

@unsafe def is_empty_members(+members: +List<Member>) -> Bool:
  match members:
    case Nil{}: True{}
    case Con{member, rest}: False{}

# ObjectStreamClass.computeDefaultSUID: SHA-1 over the class name, modifiers,
# interfaces, fields, static initializer, constructors and methods.
@unsafe def default_suid(+vm: M.VM, +class: U32) -> M.Slot:
  +name : String = L.class_name_text(vm, class)
  default_suid_kind(String.starts_with(name, "["), vm, class, name)

@unsafe def default_suid_kind(+array: Bool, +vm: M.VM, +class: U32, +name: String) -> M.Slot:
  match array:
    case True{}: suid_words(sha1(M.append(U32, utf_bytes(L.class_display_name(name)), int_bytes(1041))))
    case False{}:
      +raw : U32 = U32.and(L.class_flags(vm, class), 1553)
      +methods : +List<Member> = sort_members(suid_methods(vm, S.methods(vm), class, False{}), Nil{})
      +interface : Bool = U32.is_ne(U32.and(raw, 512), 0)
      +mods : U32 = Bool.pick(U32, interface, Bool.pick(U32, is_empty_members(methods), U32.and(raw, 4294966271), U32.or(raw, 1024)), raw)
      +clinit : +List<U32> = Bool.pick(+List<U32>, has_clinit(vm, class), M.append(U32, utf_bytes("<clinit>"), M.append(U32, int_bytes(8), utf_bytes("()V"))), Nil{})
      +bytes : +List<U32> = M.append(U32, utf_bytes(L.class_display_name(name)), M.append(U32, int_bytes(mods),
        M.append(U32, name_bytes(sort_members(interface_members(vm, interfaces_of(vm, class)), Nil{})),
          M.append(U32, member_bytes(sort_members(suid_fields(vm, S.fields(vm), class), Nil{})),
            M.append(U32, clinit, M.append(U32, member_bytes(sort_members(suid_methods(vm, S.methods(vm), class, True{}), Nil{})), member_bytes(methods)))))))
      suid_words(sha1(bytes))

# The classes whose data an object carries, top-most serializable class first.
@unsafe def class_chain(+vm: M.VM, +class: U32, +acc: +List<U32>) -> +List<U32>:
  class_chain_step(U32.is_eq(class, none()), vm, class, acc)

@unsafe def class_chain_step(+done: Bool, +vm: M.VM, +class: U32, +acc: +List<U32>) -> +List<U32>:
  match done:
    case True{}: acc
    case False{}: class_chain(vm, info_super(vm, class), Con{class, acc})

@unsafe def data_classes(+vm: M.VM, +class: U32) -> +List<U32>:
  class_chain(vm, Bool.pick(U32, L.proxy_class_is_synthetic(vm, class), L.class_id(vm, "java/lang/reflect/Proxy"), class), Nil{})

# writeEnum describes the enum itself, not a constant's body class.
@unsafe def described_class(+vm: M.VM, +class: U32) -> U32:
  +parent : U32 = parent_of(vm, class)
  Bool.pick(U32, is_enum(vm, parent), parent, class)

# --- ObjectOutputStream ---

@unsafe def baos_target(+vm: M.VM, +target: U32) -> Bool:
  U32.is_eq(kind_of(vm, target), 4) && H.hierarchy(S.classes(vm), class_of(vm, target), L.class_id(vm, "java/io/ByteArrayOutputStream"))

# Stream bytes: into a ByteArrayOutputStream target, else the stream's buffer.
@unsafe def raw_emit(+vm: M.VM, +stream: U32, +bytes: +List<U32>) -> M.VM:
  +target : U32 = binding_of(vm, stream, bind_target())
  append_values(vm, Bool.pick(U32, baos_target(vm, target), target, stream), byte_slots(bytes))

@unsafe def block_mode(+vm: M.VM, +stream: U32) -> Bool:
  is_true(binding_of(vm, stream, bind_block()))

# Primitive data: into the pending block in block-data mode.
@unsafe def emit(+vm: M.VM, +stream: U32, +bytes: +List<U32>) -> M.VM:
  emit_mode(block_mode(vm, stream), vm, stream, bytes)

@unsafe def emit_mode(+block: Bool, +vm: M.VM, +stream: U32, +bytes: +List<U32>) -> M.VM:
  match block:
    case True{}: append_values(vm, binding_of(vm, stream, bind_holder()), byte_slots(bytes))
    case False{}: raw_emit(vm, stream, bytes)

# drain(): pending block data becomes TC_BLOCKDATA (up to 255 bytes) or
# TC_BLOCKDATALONG chunks of at most 1024 bytes.
@unsafe def drain(+vm: M.VM, +stream: U32) -> M.VM:
  +holder : U32 = binding_of(vm, stream, bind_holder())
  +bytes : +List<U32> = slot_bytes(values_of(vm, holder))
  drain_chunks(set_values(vm, holder, Nil{}), stream, bytes, U32.to_nat(U32.add(U32.shrn(M.length(U32, bytes), 10n), 1)))

@unsafe def drain_chunks(+vm: M.VM, +stream: U32, +bytes: +List<U32>, +budget: Nat) -> M.VM:
  match budget:
    case 0n: vm
    case 1n+ +remaining:
      +chunk : +List<U32> = M.take(U32, bytes, 1024n)
      +length : U32 = M.length(U32, chunk)
      +header : +List<U32> = Bool.pick(+List<U32>, U32.is_le(length, 255), [119, length], Con{122, int_bytes(length)})
      +emitted : M.VM = Bool.pick(M.VM, U32.is_eq(length, 0), vm, raw_emit(vm, stream, M.append(U32, header, chunk)))
      drain_chunks(emitted, stream, M.drop(U32, bytes, 1024n), remaining)

@unsafe def set_mode(+vm: M.VM, +stream: U32, +block: Bool) -> M.VM:
  +drained : M.VM = drain_if(block_mode(vm, stream) && Bool.not(block), vm, stream)
  set_binding(drained, stream, bind_block(), M.Slot{1, Bool.pick(U32, block, 1, 0)})

@unsafe def drain_if(+needed: Bool, +vm: M.VM, +stream: U32) -> M.VM:
  match needed:
    case True{}: drain(vm, stream)
    case False{}: vm

# Handles: assigned in write (and read) order from 0x7E0000.
@unsafe def handle_slots(+vm: M.VM, +stream: U32) -> +List<M.Slot>:
  values_of(vm, binding_of(vm, stream, bind_handles()))

@unsafe def same_slot(+left: M.Slot, +right: M.Slot) -> Bool:
  U32.is_eq(M.slot_tag(left), M.slot_tag(right)) && U32.is_eq(M.slot_bits(left), M.slot_bits(right))

@unsafe def handle_find(+slots: +List<M.Slot>, +wanted: M.Slot, +index: U32) -> U32:
  match slots:
    case Nil{}: none()
    case Con{+slot, rest}: handle_find_step(same_slot(slot, wanted), rest, wanted, index)

@unsafe def handle_find_step(+hit: Bool, +rest: +List<M.Slot>, +wanted: M.Slot, +index: U32) -> U32:
  match hit:
    case True{}: index
    case False{}: handle_find(rest, wanted, U32.add(index, 1))

@unsafe def handle_of(+vm: M.VM, +stream: U32, +wanted: M.Slot) -> U32:
  handle_find(handle_slots(vm, stream), wanted, 0)

@unsafe def handle_count(+vm: M.VM, +stream: U32) -> U32:
  M.length(M.Slot, handle_slots(vm, stream))

@unsafe def unshared(+vm: M.VM, +stream: U32) -> Bool:
  is_true(binding_of(vm, stream, bind_unshared()))

@unsafe def set_unshared(+vm: M.VM, +stream: U32, +value: Bool) -> M.VM:
  set_binding(vm, stream, bind_unshared(), M.Slot{1, Bool.pick(U32, value, 1, 0)})

# An unshared object's handle holds a marker no lookup matches (a back
# reference to it is an InvalidObjectException).
@unsafe def unshared_marker() -> M.Slot:
  M.Slot{2, 0}

@unsafe def is_marker(+slot: M.Slot) -> Bool:
  U32.is_eq(M.slot_tag(slot), 2)

@unsafe def assign_object(+vm: M.VM, +stream: U32, +object: U32) -> M.VM:
  +marked : Bool = unshared(vm, stream)
  assign_handle(set_unshared(vm, stream, False{}), stream, Bool.pick(M.Slot, marked, unshared_marker(), M.Slot{3, object}))

# The handle of an object written earlier, unless this write is unshared.
@unsafe def shared_handle(+vm: M.VM, +stream: U32, +object: U32) -> U32:
  Bool.pick(U32, unshared(vm, stream), none(), handle_of(vm, stream, M.Slot{3, object}))

@unsafe def assign_handle(+vm: M.VM, +stream: U32, +value: M.Slot) -> M.VM:
  append_values(vm, binding_of(vm, stream, bind_handles()), [value])

@unsafe def replace_at(+values: +List<M.Slot>, +index: U32, +value: M.Slot) -> +List<M.Slot>:
  match values:
    case Nil{}: Nil{}
    case Con{+head, rest}: replace_step(U32.is_eq(index, 0), head, rest, index, value)

@unsafe def replace_step(+here: Bool, +head: M.Slot, +rest: +List<M.Slot>, +index: U32, +value: M.Slot) -> +List<M.Slot>:
  match here:
    case True{}: Con{value, rest}
    case False{}: Con{head, replace_at(rest, U32.sub(index, 1), value)}

@unsafe def replace_handle(+vm: M.VM, +stream: U32, +index: U32, +value: M.Slot) -> M.VM:
  +table : U32 = binding_of(vm, stream, bind_handles())
  set_values(vm, table, replace_at(values_of(vm, table), index, value))

@unsafe def handle_at(+vm: M.VM, +stream: U32, +index: U32) -> M.Slot:
  slot_or_null(M.nth(M.Slot, handle_slots(vm, stream), index))

@unsafe def slot_or_null(found: Maybe<&2, M.Slot>) -> M.Slot:
  match found:
    case Some{+slot}: slot
    case None{}: M.Slot{3, 0}

@unsafe def emit_handle(+vm: M.VM, +stream: U32, +handle: U32) -> M.VM:
  raw_emit(vm, stream, Con{113, int_bytes(U32.add(8257536, handle))})

# The replacement table: (original, replacement) pairs.
@unsafe def subs_lookup(+slots: +List<M.Slot>, +object: U32) -> U32:
  match slots:
    case Con{+original, Con{+replacement, rest}}: subs_step(U32.is_eq(M.slot_bits(original), object), M.slot_bits(replacement), rest, object)
    case _: object

@unsafe def subs_step(+hit: Bool, +replacement: U32, +rest: +List<M.Slot>, +object: U32) -> U32:
  match hit:
    case True{}: replacement
    case False{}: subs_lookup(rest, object)

# writeString: TC_STRING with modified UTF-8 (TC_LONGSTRING past 65535 bytes).
# Type strings and enum names are always shared; a String written as the object
# itself may be unshared.
@unsafe def write_string(+vm: M.VM, +stream: U32, +reference: U32) -> M.VM:
  +handle : U32 = handle_of(vm, stream, M.Slot{3, reference})
  write_string_known(U32.is_eq(handle, none()), handle, vm, stream, reference, False{})

@unsafe def write_string_object(+vm: M.VM, +stream: U32, +reference: U32) -> M.VM:
  +handle : U32 = shared_handle(vm, stream, reference)
  write_string_known(U32.is_eq(handle, none()), handle, vm, stream, reference, True{})

@unsafe def write_string_known(+fresh: Bool, +handle: U32, +vm: M.VM, +stream: U32, +reference: U32, +object: Bool) -> M.VM:
  match fresh:
    case False{}: emit_handle(vm, stream, handle)
    case True{}:
      +body : +List<U32> = modified_utf8(L.entry_chars(entry_of(vm, reference)))
      +length : U32 = M.length(U32, body)
      +head : +List<U32> = Bool.pick(+List<U32>, U32.is_le(length, 65535), Con{116, short_bytes(length)}, Con{124, M.append(U32, [0, 0, 0, 0], int_bytes(length))})
      +handled : M.VM = Bool.pick(M.VM, object, assign_object(vm, stream, reference), assign_handle(vm, stream, M.Slot{3, reference}))
      raw_emit(handled, stream, M.append(U32, head, body))

@unsafe def write_text(+vm: M.VM, +stream: U32, +text: String) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +interned : Ref <- returned_ref(L.intern_or_alloc(vm, L.units_from_string(text)))
    return write_string(ref_vm(interned), stream, ref_reference(interned))

# --- Subclass hooks ---
# A protected ObjectOutputStream/ObjectInputStream method a subclass overrides
# runs as a Java callback; the MiniJRE defaults are applied directly.

@unsafe def hook_found(found: Maybe<&2, M.LoadedMethod>, +base: U32) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{+method}: Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), base), None{}, Some{method})

@unsafe def override_of(+vm: M.VM, +stream: U32, +base: String, +name: String, +descriptor: String) -> Maybe<&2, M.LoadedMethod>:
  hook_found(L.virtual_on(vm, stream, name, descriptor), L.class_id(vm, base))

@unsafe def output_hook(+vm: M.VM, +stream: U32, +name: String, +descriptor: String) -> Maybe<&2, M.LoadedMethod>:
  override_of(vm, stream, "java/io/ObjectOutputStream", name, descriptor)

@unsafe def input_hook(+vm: M.VM, +stream: U32, +name: String, +descriptor: String) -> Maybe<&2, M.LoadedMethod>:
  override_of(vm, stream, "java/io/ObjectInputStream", name, descriptor)

@unsafe def mirror_of(+vm: M.VM, +class: U32) -> Result<&2, &2, String, Ref>:
  returned_ref(L.class_mirror_out(vm, class))

@unsafe def fatal_active(+vm: M.VM, +stream: U32) -> Bool:
  is_true(binding_of(vm, stream, bind_fatal()))

# A writer callback; one a top-level writeObject makes catches IOException
# (SerialCatch), so the stream can record it (writeFatalException).
@unsafe def write_callback(+vm: M.VM, +stream: U32, +method: M.LoadedMethod, +args: +List<M.Slot>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  +top : Bool = Bool.not(busy(vm, stream, True{})) && Bool.not(fatal_active(vm, stream))
  +ready : M.VM = L.push_cont(vm, M.NeedSerialWrite{stream, rest})
  Done{O.Call{Bool.pick(M.VM, top, S.with_effect(ready, M.SerialCatch{}), ready), method, args}}

# --- ObjectStreamClass and ObjectStreamField objects ---
# ObjectStreamClass bindings: 0 name, 1 class (or null), 2 serialVersionUID,
# 3 flags, 4 ObjectStreamField[], 5 superclass id, 6 local class id.
# ObjectStreamField bindings: 0 name, 1 type, 2 signature, 3 unshared, 4 the
# local binding it fills (none if none), 5 type code, 6 the local field's
# signature.

@unsafe def osc_name_ref(+vm: M.VM, +osc: U32) -> U32:
  binding_of(vm, osc, 0)

@unsafe def osc_name(+vm: M.VM, +osc: U32) -> String:
  string_or_empty(L.string_text(vm, osc_name_ref(vm, osc)))

@unsafe def string_or_empty(found: Result<&2, &2, String, String>) -> String:
  match found:
    case Done{+text}: text
    case Fail{error}: ""

@unsafe def osc_suid(+vm: M.VM, +osc: U32) -> M.Slot:
  slot_or_zero(H.binding_find(L.entry_fields(entry_of(vm, osc)), 2))

@unsafe def osc_flags(+vm: M.VM, +osc: U32) -> U32:
  binding_of(vm, osc, 3)

@unsafe def osc_array(+vm: M.VM, +osc: U32) -> U32:
  binding_of(vm, osc, 4)

@unsafe def osc_super(+vm: M.VM, +osc: U32) -> U32:
  Bool.pick(U32, U32.is_eq(osc, 0), none(), binding_of(vm, osc, 5))

# The descriptor's fields in stream order, with the local binding each fills.
@unsafe def osc_fields(+vm: M.VM, +osc: U32) -> +List<M.SerialField>:
  osf_fields(vm, values_of(vm, osc_array(vm, osc)))

@unsafe def osf_fields(+vm: M.VM, +fields: +List<M.Slot>) -> +List<M.SerialField>:
  match fields:
    case Nil{}: Nil{}
    case Con{+field, rest}:
      +osf : U32 = M.slot_bits(field)
      Con{M.SerialField{binding_of(vm, osf, 5), string_or_empty(L.string_text(vm, binding_of(vm, osf, 0))), string_or_empty(L.string_text(vm, binding_of(vm, osf, 6))), binding_of(vm, osf, 4)}, osf_fields(vm, rest)}

@unsafe def primitive_name(+code: U32) -> String:
  match code:
    case 90: "boolean"
    case 66: "byte"
    case 67: "char"
    case 83: "short"
    case 73: "int"
    case 74: "long"
    case 70: "float"
    case 68: "double"
    case _: ""

# The class a field signature names (none when no such class is loaded).
@unsafe def signature_class(+vm: M.VM, +signature: String) -> U32:
  match signature:
    case SCon{Chr{76}, +rest}: L.class_id(vm, element_name(SCon{Chr{76}, rest}))
    case SCon{Chr{91}, +rest}: L.class_id(vm, SCon{Chr{91}, rest})
    case SCon{Chr{+code}, SNil{}}: L.class_id(vm, primitive_name(code))
    case _: none()

# A local field's type; a stream field's is its primitive type or Object.
@unsafe def field_type(+vm: M.VM, +code: U32, +signature: String, +local: Bool) -> U32:
  +named : U32 = Bool.pick(U32, is_reference_code(code), Bool.pick(U32, local, signature_class(vm, signature), none()), L.class_id(vm, primitive_name(code)))
  Bool.pick(U32, U32.is_eq(named, none()), L.class_id(vm, "java/lang/Object"), named)

@unsafe def field_signature(+code: U32, +signature: String) -> String:
  Bool.pick(String, is_reference_code(code), signature, Char.show(Chr{code}))

@unsafe def new_osf(+vm: M.VM, +field: M.SerialField, +local: Bool) -> Result<&2, &2, String, Ref>:
  match field:
    case M.SerialField{+code, +name, +signature, +slot}:
      do Result<&2, &2, String, Ref>:
        +named : Ref <- new_string(vm, L.units_from_string(name))
        +signed : Ref <- new_string(ref_vm(named), L.units_from_string(field_signature(code, signature)))
        +typed : Ref <- mirror_of(ref_vm(signed), field_type(ref_vm(signed), code, signature, local))
        +entry : M.HeapEntry = H.object_entry(L.class_id(ref_vm(typed), "java/io/ObjectStreamField"), [M.Binding{0, M.Slot{3, ref_reference(named)}}, M.Binding{1, M.Slot{3, ref_reference(typed)}}, M.Binding{2, M.Slot{3, ref_reference(signed)}}, M.Binding{3, M.Slot{1, 0}}, M.Binding{4, M.Slot{1, slot}}, M.Binding{5, M.Slot{1, code}}, M.Binding{6, M.Slot{3, 0}}])
        +result : Ref <- allocated(H.allocate(ref_vm(typed), entry))
        return result

@unsafe def new_osfs(+vm: M.VM, +fields: +List<M.SerialField>, +local: Bool, +acc: +List<M.Slot>) -> Result<&2, &2, String, Refs>:
  match fields:
    case Nil{}: Done{Refs{vm, M.reverse(M.Slot, acc)}}
    case Con{+field, rest}:
      do Result<&2, &2, String, Refs>:
        +osf : Ref <- new_osf(vm, field, local)
        +result : Refs <- new_osfs(ref_vm(osf), rest, local, Con{M.Slot{3, ref_reference(osf)}, acc})
        return result

type Refs is Data:
  Refs{vm: M.VM, slots: +List<M.Slot>}

@unsafe def refs_vm(+value: Refs) -> M.VM:
  match value:
    case Refs{+vm, slots}: vm

@unsafe def refs_slots(+value: Refs) -> +List<M.Slot>:
  match value:
    case Refs{vm, +slots}: slots

@unsafe def new_osc(+vm: M.VM, +name: String, +class: U32, +suid: M.Slot, +flags: U32, +fields: +List<M.SerialField>, +super: U32, +local: Bool) -> Result<&2, &2, String, Ref>:
  do Result<&2, &2, String, Ref>:
    +named : Ref <- new_string(vm, L.units_from_string(name))
    +osfs : Refs <- new_osfs(ref_vm(named), fields, local, Nil{})
    +array : Ref <- allocated(H.allocate(refs_vm(osfs), H.reference_array_entry(L.class_id(refs_vm(osfs), "[Ljava/io/ObjectStreamField;"), L.class_id(refs_vm(osfs), "java/io/ObjectStreamField"), refs_slots(osfs))))
    +mirror : U32 <- Bool.pick(Result<&2, &2, String, U32>, U32.is_eq(class, none()), Done{0}, mirror_bits(mirror_of(ref_vm(array), class)))
    +entry : M.HeapEntry = H.object_entry(L.class_id(ref_vm(array), "java/io/ObjectStreamClass"), [M.Binding{0, M.Slot{3, ref_reference(named)}}, M.Binding{1, M.Slot{3, mirror}}, M.Binding{2, suid}, M.Binding{3, M.Slot{1, flags}}, M.Binding{4, M.Slot{3, ref_reference(array)}}, M.Binding{5, M.Slot{1, super}}, M.Binding{6, M.Slot{1, class}}])
    +result : Ref <- allocated(H.allocate(ref_vm(array), entry))
    return result

@unsafe def mirror_bits(found: Result<&2, &2, String, Ref>) -> Result<&2, &2, String, U32>:
  match found:
    case Fail{+error}: Fail{error}
    case Done{+ref}: Done{ref_reference(ref)}

# ObjectStreamClass.lookup: one descriptor per class, kept on its mirror.
@unsafe def class_osc(+vm: M.VM, +class: U32) -> Result<&2, &2, String, Ref>:
  do Result<&2, &2, String, Ref>:
    +mirror : Ref <- mirror_of(vm, class)
    +known : U32 = binding_of(ref_vm(mirror), ref_reference(mirror), bind_descs())
    +result : Ref <- class_osc_known(U32.is_ne(known, 0), known, ref_vm(mirror), class, ref_reference(mirror))
    return result

@unsafe def class_osc_known(+known: Bool, +osc: U32, +vm: M.VM, +class: U32, +mirror: U32) -> Result<&2, &2, String, Ref>:
  match known:
    case True{}: Done{Ref{vm, osc}}
    case False{}:
      do Result<&2, &2, String, Ref>:
        +info : SerialInfo = serial_info(vm, class)
        +made : Ref <- new_osc(vm, info_name(info), class, class_suid(vm, class), info_flags_of(info), info_fields_of(info), info_super_of(info), True{})
        return Ref{set_binding(ref_vm(made), mirror, bind_descs(), M.Slot{3, ref_reference(made)}), ref_reference(made)}

# --- ObjectOutputStream descriptors ---

# writeClassDesc: TC_NULL, a handle, or a new TC_PROXYCLASSDESC/TC_CLASSDESC;
# its class annotation and superclass descriptor follow as tasks.
@unsafe def write_desc(+vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  write_desc_null(U32.is_eq(class, none()), vm, stream, class, rest)

@unsafe def write_desc_null(+null: Bool, +vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match null:
    case True{}: write_run(raw_emit(vm, stream, [112]), stream, rest)
    case False{}:
      +handle : U32 = handle_of(vm, stream, M.Slot{1, class})
      write_desc_handle(U32.is_eq(handle, none()), handle, vm, stream, class, rest)

@unsafe def write_desc_handle(+fresh: Bool, +handle: U32, +vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match fresh:
    case False{}: write_run(emit_handle(vm, stream, handle), stream, rest)
    case True{}: write_desc_new(L.proxy_class_is_synthetic(vm, class), vm, stream, class, rest)

@unsafe def write_desc_new(+proxy: Bool, +vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match proxy:
    case True{}: write_proxy_desc(vm, stream, class, rest)
    case False{}: write_plain_desc(vm, stream, class, rest)

@unsafe def suid_bytes(+suid: M.Slot) -> +List<U32>:
  match suid:
    case M.Wide{tag, +high, +low}: M.append(U32, int_bytes(high), int_bytes(low))
    case _: [0, 0, 0, 0, 0, 0, 0, 0]

@unsafe def protocol_one(+vm: M.VM, +stream: U32) -> Bool:
  U32.is_eq(binding_of(vm, stream, bind_protocol()), 1)

# Protocol 1 writes Externalizable data without block-data mode.
@unsafe def stream_flags(+vm: M.VM, +stream: U32, +flags: U32) -> U32:
  Bool.pick(U32, protocol_one(vm, stream), U32.and(flags, 247), flags)

# writeNonProxyDesc: the descriptor body (writeClassDescriptor, unless protocol
# 1), the class annotation, then the superclass descriptor.
@unsafe def write_plain_desc(+vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  +started : M.VM = assign_handle(raw_emit(vm, stream, [114]), stream, M.Slot{1, class})
  +after : +List<M.SerialTask> = Con{M.WAnnotate{class, False{}}, Con{M.WDesc{info_super(started, class)}, rest}}
  write_desc_body_hook(Bool.pick(Maybe<&2, M.LoadedMethod>, protocol_one(started, stream), None{}, output_hook(started, stream, "writeClassDescriptor", "(Ljava/io/ObjectStreamClass;)V")), started, stream, class, after)

@unsafe def write_desc_body_hook(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +class: U32, +after: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}:
      do Result<&2, &2, String, O.Outcome>:
        +body : M.VM <- write_desc_body(vm, stream, serial_info(vm, class), class_suid(vm, class))
        +result : O.Outcome <- write_run(body, stream, after)
        return result
    case Some{+method}:
      do Result<&2, &2, String, O.Outcome>:
        +osc : Ref <- class_osc(vm, class)
        +result : O.Outcome <- write_callback(ref_vm(osc), stream, method, [M.Slot{3, stream}, M.Slot{3, ref_reference(osc)}], after)
        return result

# ObjectStreamClass.writeNonProxy: name, serialVersionUID, flags, fields.
@unsafe def write_desc_body(+vm: M.VM, +stream: U32, +info: SerialInfo, +suid: M.Slot) -> Result<&2, &2, String, M.VM>:
  match info:
    case SerialInfo{+name, +flags, +fields, super}:
      do Result<&2, &2, String, M.VM>:
        +named : M.VM = raw_emit(vm, stream, M.append(U32, utf_bytes(name), M.append(U32, suid_bytes(suid), Con{stream_flags(vm, stream, flags), short_bytes(M.length(M.SerialField, fields))})))
        +result : M.VM <- write_field_specs(named, stream, fields)
        return result

@unsafe def write_field_specs(+vm: M.VM, +stream: U32, +fields: +List<M.SerialField>) -> Result<&2, &2, String, M.VM>:
  match fields:
    case Nil{}: Done{vm}
    case Con{M.SerialField{+code, +name, +signature, slot}, rest}:
      do Result<&2, &2, String, M.VM>:
        +named : M.VM = raw_emit(vm, stream, Con{code, utf_bytes(name)})
        +typed : M.VM <- write_type_string(is_reference_code(code), named, stream, signature)
        +result : M.VM <- write_field_specs(typed, stream, rest)
        return result

@unsafe def write_type_string(+reference: Bool, +vm: M.VM, +stream: U32, +signature: String) -> Result<&2, &2, String, M.VM>:
  match reference:
    case False{}: Done{vm}
    case True{}: write_text(vm, stream, signature)

# TC_PROXYCLASSDESC: the interface names, the annotation, then Proxy's descriptor.
@unsafe def write_proxy_desc(+vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  +names : +List<Member> = interface_members(vm, interfaces_of(vm, class))
  +started : M.VM = assign_handle(raw_emit(vm, stream, [125]), stream, M.Slot{1, class})
  +listed : M.VM = raw_emit(started, stream, M.append(U32, int_bytes(M.length(Member, names)), name_bytes(names)))
  write_run(listed, stream, Con{M.WAnnotate{class, True{}}, Con{M.WDesc{L.class_id(listed, "java/lang/reflect/Proxy")}, rest}})

# annotateClass/annotateProxyClass write in block-data mode; TC_ENDBLOCKDATA
# ends the annotation.
@unsafe def write_annotate(+vm: M.VM, +stream: U32, +class: U32, +proxy: Bool, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  write_annotate_hook(output_hook(vm, stream, Bool.pick(String, proxy, "annotateProxyClass", "annotateClass"), "(Ljava/lang/Class;)V"), vm, stream, class, rest)

@unsafe def write_annotate_hook(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: write_run(raw_emit(vm, stream, [120]), stream, rest)
    case Some{+method}:
      do Result<&2, &2, String, O.Outcome>:
        +mirror : Ref <- mirror_of(vm, class)
        +result : O.Outcome <- write_callback(set_mode(ref_vm(mirror), stream, True{}), stream, method, [M.Slot{3, stream}, M.Slot{3, ref_reference(mirror)}], Con{M.WEndCustom{}, rest})
        return result

# --- The writer's task machine ---
# writeReplace, writeObject, writeExternal and the hooks suspend it;
# NeedSerialWrite resumes it with the callback's result. An IOException a
# top-level write meets is recorded in the stream (writeFatalException).
@unsafe def write_run(+vm: M.VM, +stream: U32, +tasks: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match tasks:
    case Nil{}: L.void_out(vm)
    case Con{+task, +rest}: write_guard(write_task(task, vm, stream, rest), vm, stream)

@unsafe def write_task(+task: M.SerialTask, +vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match task:
    case M.WMode{+block}: write_run(set_mode(vm, stream, block), stream, rest)
    case M.WContext{+object, +class, +put}: write_run(set_binding(set_context(vm, stream, object, class), stream, bind_put(), M.Slot{3, put}), stream, rest)
    case M.WEndCustom{}: write_run(raw_emit(set_mode(vm, stream, False{}), stream, [120]), stream, rest)
    case M.WObject{+value}: write_object(vm, stream, value, rest)
    case M.WData{+object, +classes}: write_data(vm, stream, object, classes, rest)
    case M.WFields{+object, +fields}: write_fields(vm, stream, object, fields, rest)
    case M.WValues{+values, +code}: write_values(vm, stream, values, code, rest)
    case M.WSend{}: write_send(vm, stream, rest)
    case M.WTarget{+name, +descriptor}: write_target_call(vm, stream, name, descriptor, rest)
    case M.WUnshared{+value}: write_object(set_unshared(vm, stream, True{}), stream, value, rest)
    case M.WExternal{+object}: write_external(vm, stream, object, rest)
    case M.WDesc{+class}: write_desc(vm, stream, class, rest)
    case M.WAnnotate{+class, +proxy}: write_annotate(vm, stream, class, proxy, rest)
    case M.WClassBody{+object}: write_run(assign_object(vm, stream, object), stream, rest)
    case M.WArrayBody{+object}: write_array_body(vm, stream, object, rest)
    case M.WEnumBody{+object}: write_run(write_string(assign_object(vm, stream, object), stream, binding_of(vm, object, 0)), stream, rest)
    case M.WInstance{+object, +class}: write_instance(assign_object(vm, stream, object), stream, object, class, rest)
    case M.WSlots{+fields, +values}: write_slots(vm, stream, fields, values, rest)
    case M.WCaught{+exception}: write_fatal(vm, stream, exception)
    case M.WClear{}: write_run(set_binding(clear_write_tables(vm, stream), stream, bind_fatal(), M.Slot{1, 0}), stream, rest)
    case M.WThrow{+exception}: Done{O.ThrownRef{vm, exception}}
    case _: write_run(vm, stream, rest)

@unsafe def set_context(+vm: M.VM, +stream: U32, +object: U32, +class: U32) -> M.VM:
  set_binding(set_binding(set_binding(vm, stream, bind_object(), M.Slot{3, object}), stream, bind_class(), M.Slot{1, class}), stream, bind_put(), M.Slot{3, 0})

@unsafe def saved_context(+vm: M.VM, +stream: U32) -> M.SerialTask:
  M.WContext{binding_of(vm, stream, bind_object()), binding_of(vm, stream, bind_class()), binding_of(vm, stream, bind_put())}

@unsafe def clear_write_tables(+vm: M.VM, +stream: U32) -> M.VM:
  set_values(set_values(vm, binding_of(vm, stream, bind_handles()), Nil{}), binding_of(vm, stream, bind_subs()), Nil{})

# The exception class an error names, when it is an IOException.
@unsafe def error_class(+vm: M.VM, +error: String) -> U32:
  L.class_id(vm, String.from_list(chars_before_colon(String.to_list(error))))

@unsafe def chars_before_colon(+chars: +List<Char>) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{58}, rest}: Nil{}
    case Con{+c, rest}: Con{c, chars_before_colon(rest)}

@unsafe def error_message(+chars: +List<Char>) -> String:
  match chars:
    case Nil{}: ""
    case Con{Chr{58}, Con{Chr{32}, +rest}}: String.from_list(rest)
    case Con{Chr{58}, +rest}: String.from_list(rest)
    case Con{c, +rest}: error_message(rest)

@unsafe def has_colon(+chars: +List<Char>) -> Bool:
  match chars:
    case Nil{}: False{}
    case Con{Chr{58}, rest}: True{}
    case Con{c, +rest}: has_colon(rest)

@unsafe def io_error(+vm: M.VM, +error: String) -> Bool:
  +class : U32 = error_class(vm, error)
  U32.is_ne(class, none()) && H.assignable(S.classes(vm), S.symbols(vm), class, L.class_id(vm, "java/io/IOException"))

@unsafe def top_write(+vm: M.VM, +stream: U32) -> Bool:
  Bool.not(busy(vm, stream, True{})) && Bool.not(fatal_active(vm, stream))

@unsafe def write_guard(result: Result<&2, &2, String, O.Outcome>, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{+error}: write_failed(io_error(vm, error) && top_write(vm, stream), error, vm, stream)
    case Done{O.ThrownName{+after, +error}}: write_thrown(io_error(after, error) && top_write(after, stream), error, after, stream)
    case Done{+outcome}: Done{outcome}

@unsafe def write_failed(+fatal: Bool, +error: String, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  match fatal:
    case False{}: Fail{error}
    case True{}: write_fatal_named(vm, stream, error)

@unsafe def write_thrown(+fatal: Bool, +error: String, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  match fatal:
    case False{}: Done{O.ThrownName{vm, error}}
    case True{}: write_fatal_named(vm, stream, error)

# The exception object an error string names, with its message.
@unsafe def error_object(+vm: M.VM, +error: String) -> Result<&2, &2, String, Ref>:
  do Result<&2, &2, String, Ref>:
    +chars : +List<Char> = String.to_list(error)
    +text : Ref <- new_string(vm, L.units_from_string(error_message(chars)))
    +message : U32 = Bool.pick(U32, has_colon(chars), ref_reference(text), 0)
    +entry : M.HeapEntry = H.throwable_entry(error_class(ref_vm(text), error))
    +result : Ref <- allocated(H.allocate(ref_vm(text), with_binding(entry, 0, M.Slot{3, message})))
    return result

@unsafe def write_fatal_named(+vm: M.VM, +stream: U32, +error: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +exception : Ref <- error_object(vm, error)
    +result : O.Outcome <- write_fatal(ref_vm(exception), stream, ref_reference(exception))
    return result

# writeFatalException: no handles, TC_EXCEPTION outside block data, the
# exception itself, no handles again, the previous mode, then rethrow.
@unsafe def write_fatal(+vm: M.VM, +stream: U32, +exception: U32) -> Result<&2, &2, String, O.Outcome>:
  +previous : Bool = block_mode(vm, stream)
  +cleared : M.VM = clear_write_tables(set_context(vm, stream, 0, none()), stream)
  +marked : M.VM = set_binding(raw_emit(set_mode(cleared, stream, False{}), stream, [123]), stream, bind_fatal(), M.Slot{1, 1})
  write_run(marked, stream, [M.WObject{exception}, M.WClear{}, M.WMode{previous}, M.WThrow{exception}])

@unsafe def write_object(+vm: M.VM, +stream: U32, +value: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  +object : U32 = subs_lookup(values_of(vm, binding_of(vm, stream, bind_subs())), value)
  write_object_null(U32.is_eq(object, 0), vm, stream, object, rest)

@unsafe def write_object_null(+null: Bool, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match null:
    case True{}: write_run(raw_emit(set_unshared(vm, stream, False{}), stream, [112]), stream, rest)
    case False{}:
      +handle : U32 = shared_handle(vm, stream, object)
      write_object_handle(U32.is_eq(handle, none()), handle, vm, stream, object, rest)

@unsafe def write_object_handle(+fresh: Bool, +handle: U32, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match fresh:
    case False{}: write_run(emit_handle(vm, stream, handle), stream, rest)
    case True{}: write_object_class(object_case(vm, object), vm, stream, object, rest)

# A Class, an ObjectStreamClass (written as its descriptor), or an object.
@unsafe def object_case(+vm: M.VM, +object: U32) -> U32:
  Bool.pick(U32, U32.is_eq(kind_of(vm, object), 8), 1, Bool.pick(U32, U32.is_eq(class_of(vm, object), L.class_id(vm, "java/io/ObjectStreamClass")), 2, 0))

@unsafe def write_object_class(+kind: U32, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match kind:
    case 1: write_class(vm, stream, object, rest)
    case 2: write_desc(vm, stream, osc_class(vm, object), rest)
    case _: replace_loop(vm, stream, object, object, rest)

@unsafe def osc_class(+vm: M.VM, +osc: U32) -> U32:
  +mirror : U32 = binding_of(vm, osc, 1)
  Bool.pick(U32, U32.is_eq(mirror, 0), none(), L.entry_element(entry_of(vm, mirror)))

# writeClass: TC_CLASS, the class's descriptor, then the handle.
@unsafe def write_class(+vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  write_desc(raw_emit(vm, stream, [118]), stream, L.entry_element(entry_of(vm, object)), Con{M.WClassBody{object}, rest})

@unsafe def write_replace_method(+vm: M.VM, +object: U32) -> Maybe<&2, M.LoadedMethod>:
  +class : U32 = class_of(vm, object)
  write_replace_lookup(is_serializable(vm, class) && U32.is_ne(kind_of(vm, object), 3), vm, object)

@unsafe def write_replace_lookup(+eligible: Bool, +vm: M.VM, +object: U32) -> Maybe<&2, M.LoadedMethod>:
  match eligible:
    case True{}: L.virtual_on(vm, object, "writeReplace", "()Ljava/lang/Object;")
    case False{}: None{}

# writeReplace repeats while each replacement has a different class.
@unsafe def replace_loop(+vm: M.VM, +stream: U32, +original: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  replace_call(write_replace_method(vm, object), vm, stream, original, object, rest)

@unsafe def replace_call(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +original: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: write_resolved(vm, stream, original, object, rest)
    case Some{+method}: write_callback(vm, stream, method, [M.Slot{3, object}], Con{M.WReplaced{original, class_of(vm, object)}, rest})

@unsafe def replaced(+vm: M.VM, +stream: U32, +original: U32, +class: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  replaced_step(U32.is_eq(object, 0) || U32.is_eq(class_of(vm, object), class), vm, stream, original, object, rest)

@unsafe def replaced_step(+settled: Bool, +vm: M.VM, +stream: U32, +original: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match settled:
    case True{}: write_resolved(vm, stream, original, object, rest)
    case False{}: replace_loop(vm, stream, original, object, rest)

# After writeReplace, replaceObject when enableReplaceObject(true) is in force.
@unsafe def write_resolved(+vm: M.VM, +stream: U32, +original: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  +hook : Maybe<&2, M.LoadedMethod> = Bool.pick(Maybe<&2, M.LoadedMethod>, is_true(binding_of(vm, stream, bind_replace())), output_hook(vm, stream, "replaceObject", "(Ljava/lang/Object;)Ljava/lang/Object;"), None{})
  write_replace_hook(hook, vm, stream, original, object, rest)

@unsafe def write_replace_hook(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +original: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: write_resolved_same(U32.is_eq(original, object), vm, stream, original, object, rest)
    case Some{+method}: write_callback(vm, stream, method, [M.Slot{3, stream}, M.Slot{3, object}], Con{M.WHooked{original}, rest})

# A replaced object is recorded, then null, handle and Class checks run again.
@unsafe def write_resolved_same(+same: Bool, +vm: M.VM, +stream: U32, +original: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match same:
    case True{}: write_kind(vm, stream, object, rest)
    case False{}:
      +recorded : M.VM = append_values(vm, binding_of(vm, stream, bind_subs()), [M.Slot{3, original}, M.Slot{3, object}])
      write_replaced_null(U32.is_eq(object, 0), recorded, stream, object, rest)

@unsafe def write_replaced_null(+null: Bool, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match null:
    case True{}: write_run(raw_emit(set_unshared(vm, stream, False{}), stream, [112]), stream, rest)
    case False{}:
      +handle : U32 = shared_handle(vm, stream, object)
      write_replaced_handle(U32.is_eq(handle, none()), handle, vm, stream, object, rest)

@unsafe def write_replaced_handle(+fresh: Bool, +handle: U32, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match fresh:
    case False{}: write_run(emit_handle(vm, stream, handle), stream, rest)
    case True{}: write_replaced_class(object_case(vm, object), vm, stream, object, rest)

@unsafe def write_replaced_class(+kind: U32, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match kind:
    case 1: write_class(vm, stream, object, rest)
    case 2: write_desc(vm, stream, osc_class(vm, object), rest)
    case _: write_kind(vm, stream, object, rest)

# String, array, enum, or Serializable object.
@unsafe def write_kind(+vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  write_kind_entry(L.entry_kind(entry_of(vm, object)), vm, stream, object, rest)

@unsafe def write_kind_entry(+kind: U32, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match kind:
    case 3: write_run(write_string_object(vm, stream, object), stream, rest)
    case 1: write_desc(raw_emit(vm, stream, [117]), stream, class_of(vm, object), Con{M.WArrayBody{object}, rest})
    case 2: write_desc(raw_emit(vm, stream, [117]), stream, class_of(vm, object), Con{M.WArrayBody{object}, rest})
    case _: write_ordinary(vm, stream, object, class_of(vm, object), rest)

@unsafe def array_code(+vm: M.VM, +class: U32) -> U32:
  array_code_of(L.class_name_text(vm, class))

@unsafe def array_code_of(+name: String) -> U32:
  match name:
    case SCon{Chr{91}, SCon{Chr{+c}, more}}: c
    case _: 76

@unsafe def write_array_body(+vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  +values : +List<M.Slot> = values_of(vm, object)
  +counted : M.VM = raw_emit(assign_object(vm, stream, object), stream, int_bytes(M.length(M.Slot, values)))
  write_values(counted, stream, values, array_code(counted, class_of(counted, object)), rest)

@unsafe def class_text(+vm: M.VM, +class: U32) -> String:
  L.class_display_name(L.class_name_text(vm, class))

@unsafe def write_ordinary(+vm: M.VM, +stream: U32, +object: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  write_ordinary_check(is_serializable(vm, class) || U32.is_ne(known_index(L.class_name_text(vm, class)), 0), vm, stream, object, class, rest)

@unsafe def write_ordinary_check(+serializable: Bool, +vm: M.VM, +stream: U32, +object: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match serializable:
    case False{}: Done{O.ThrownName{vm, "java/io/NotSerializableException: " ++ class_text(vm, class)}}
    case True{}: write_ordinary_kind(is_enum(vm, class), vm, stream, object, class, rest)

@unsafe def write_ordinary_kind(+enum: Bool, +vm: M.VM, +stream: U32, +object: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match enum:
    case True{}: write_desc(raw_emit(vm, stream, [126]), stream, described_class(vm, class), Con{M.WEnumBody{object}, rest})
    case False{}: write_desc(raw_emit(vm, stream, [115]), stream, class, Con{M.WInstance{object, class}, rest})

@unsafe def write_instance(+vm: M.VM, +stream: U32, +object: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  write_instance_kind(is_true(U32.and(info_flags(vm, class), 4)) && Bool.not(L.proxy_class_is_synthetic(vm, class)), vm, stream, object, class, rest)

@unsafe def write_instance_kind(+external: Bool, +vm: M.VM, +stream: U32, +object: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match external:
    case True{}: write_external(vm, stream, object, rest)
    case False{}: write_data(vm, stream, object, data_classes(vm, class), rest)

# writeSerialData: per class, its writeObject method in block-data mode
# (then TC_ENDBLOCKDATA), or its default fields.
@unsafe def write_data(+vm: M.VM, +stream: U32, +object: U32, +classes: +List<U32>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match classes:
    case Nil{}: write_run(vm, stream, rest)
    case Con{+class, more}:
      +next : +List<M.SerialTask> = Con{M.WData{object, more}, rest}
      write_data_class(L.own_method(S.methods(vm), class, Sy.find(S.symbols(vm), "writeObject"), Sy.find(S.symbols(vm), "(Ljava/io/ObjectOutputStream;)V")), is_true(U32.and(info_flags(vm, class), 1)), vm, stream, object, class, next)

@unsafe def write_data_class(found: Maybe<&2, M.LoadedMethod>, +custom: Bool, +vm: M.VM, +stream: U32, +object: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{+method}: write_custom(custom, method, vm, stream, object, class, rest)
    case None{}: write_fields(vm, stream, object, info_fields(vm, class), rest)

@unsafe def write_custom(+custom: Bool, +method: M.LoadedMethod, +vm: M.VM, +stream: U32, +object: U32, +class: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match custom:
    case False{}: write_fields(vm, stream, object, info_fields(vm, class), rest)
    case True{}:
      +saved : M.SerialTask = saved_context(vm, stream)
      +ready : M.VM = set_mode(set_context(vm, stream, object, class), stream, True{})
      write_callback(ready, stream, method, [M.Slot{3, object}, M.Slot{3, stream}], Con{M.WEndCustom{}, Con{saved, rest}})

# writeExternalData: writeExternal without a defaultWriteObject context, in
# block-data mode ended by TC_ENDBLOCKDATA (protocol 1: neither).
@unsafe def write_external(+vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  write_external_found(L.virtual_on(vm, object, "writeExternal", "(Ljava/io/ObjectOutput;)V"), vm, stream, object, rest)

@unsafe def write_external_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: Fail{"java/lang/AbstractMethodError: writeExternal"}
    case Some{+method}:
      +saved : M.SerialTask = saved_context(vm, stream)
      +blocked : Bool = Bool.not(protocol_one(vm, stream))
      +ready : M.VM = Bool.pick(M.VM, blocked, set_mode(set_context(vm, stream, 0, none()), stream, True{}), set_context(vm, stream, 0, none()))
      +after : +List<M.SerialTask> = Bool.pick(+List<M.SerialTask>, blocked, Con{M.WEndCustom{}, Con{saved, rest}}, Con{saved, rest})
      write_callback(ready, stream, method, [M.Slot{3, object}, M.Slot{3, stream}], after)

# defaultWriteFields: primitives in place, objects through writeObject0.
@unsafe def write_fields(+vm: M.VM, +stream: U32, +object: U32, +fields: +List<M.SerialField>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match fields:
    case Nil{}: write_run(vm, stream, rest)
    case Con{M.SerialField{+code, name, signature, +slot}, more}:
      +value : M.Slot = field_value(vm, object, slot)
      write_field_kind(is_reference_code(code), vm, stream, object, code, value, more, rest)

@unsafe def write_field_kind(+reference: Bool, +vm: M.VM, +stream: U32, +object: U32, +code: U32, +value: M.Slot, +more: +List<M.SerialField>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match reference:
    case True{}: write_object(vm, stream, M.slot_bits(value), Con{M.WFields{object, more}, rest})
    case False{}: write_fields(raw_emit(vm, stream, primitive_bytes(code, value)), stream, object, more, rest)

# PutField values, in the descriptor's field order (writeFields).
@unsafe def write_slots(+vm: M.VM, +stream: U32, +fields: +List<M.SerialField>, +values: +List<M.Slot>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match fields:
    case Nil{}: write_run(vm, stream, rest)
    case Con{M.SerialField{+code, name, signature, slot}, more}:
      +value : M.Slot = top_value(values)
      write_slot_kind(is_reference_code(code), vm, stream, code, value, more, drop_value(values), rest)

@unsafe def top_value(+values: +List<M.Slot>) -> M.Slot:
  match values:
    case Con{+slot, rest}: slot
    case Nil{}: M.Slot{1, 0}

@unsafe def drop_value(+values: +List<M.Slot>) -> +List<M.Slot>:
  match values:
    case Con{slot, +rest}: rest
    case Nil{}: Nil{}

@unsafe def write_slot_kind(+reference: Bool, +vm: M.VM, +stream: U32, +code: U32, +value: M.Slot, +more: +List<M.SerialField>, +values: +List<M.Slot>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match reference:
    case True{}: write_object(vm, stream, M.slot_bits(value), Con{M.WSlots{more, values}, rest})
    case False{}: write_slots(raw_emit(vm, stream, primitive_bytes(code, value)), stream, more, values, rest)

@unsafe def field_value(+vm: M.VM, +object: U32, +slot: U32) -> M.Slot:
  slot_or_zero(H.binding_find(L.entry_fields(entry_of(vm, object)), slot))

@unsafe def slot_or_zero(found: Maybe<&2, M.Slot>) -> M.Slot:
  match found:
    case None{}: M.Slot{1, 0}
    case Some{+slot}: slot

# Big-endian primitive encodings (DataOutput).
@unsafe def primitive_bytes(+code: U32, +value: M.Slot) -> +List<U32>:
  match code:
    case 66: [U32.and(M.slot_bits(value), 255)]
    case 90: [Bool.pick(U32, is_true(M.slot_bits(value)), 1, 0)]
    case 67: short_bytes(M.slot_bits(value))
    case 83: short_bytes(M.slot_bits(value))
    case 74: suid_bytes(value)
    case 68: suid_bytes(value)
    case _: int_bytes(M.slot_bits(value))

@unsafe def write_values(+vm: M.VM, +stream: U32, +values: +List<M.Slot>, +code: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  write_values_kind(is_reference_code(code), vm, stream, values, code, rest)

@unsafe def write_values_kind(+reference: Bool, +vm: M.VM, +stream: U32, +values: +List<M.Slot>, +code: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match reference:
    case False{}: write_run(raw_emit(vm, stream, primitive_list(values, code)), stream, rest)
    case True{}: write_elements(vm, stream, values, rest)

@unsafe def primitive_list(+values: +List<M.Slot>, +code: U32) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, more}: M.append(U32, primitive_bytes(code, value), primitive_list(more, code))

@unsafe def write_elements(+vm: M.VM, +stream: U32, +values: +List<M.Slot>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match values:
    case Nil{}: write_run(vm, stream, rest)
    case Con{+value, more}: write_object(vm, stream, M.slot_bits(value), Con{M.WValues{more, 76}, rest})

# A non-ByteArrayOutputStream target receives the buffered bytes through
# write(byte[]), then flush() or close().
@unsafe def write_send(+vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  +buffered : +List<M.Slot> = values_of(vm, stream)
  write_send_some(is_empty_slots(buffered), vm, stream, buffered, rest)

@unsafe def is_empty_slots(+slots: +List<M.Slot>) -> Bool:
  match slots:
    case Nil{}: True{}
    case Con{slot, more}: False{}

@unsafe def write_send_some(+empty: Bool, +vm: M.VM, +stream: U32, +buffered: +List<M.Slot>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: write_run(vm, stream, rest)
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +array : Ref <- allocated(H.allocate(set_values(vm, stream, Nil{}), H.primitive_array_entry(L.class_id(vm, "[B"), 8, buffered)))
        +result : O.Outcome <- target_call(ref_vm(array), stream, "write", "([B)V", [M.Slot{3, ref_reference(array)}], rest)
        return result

@unsafe def write_target_call(+vm: M.VM, +stream: U32, +name: String, +descriptor: String, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  target_call(vm, stream, name, descriptor, Nil{}, rest)

@unsafe def target_call(+vm: M.VM, +stream: U32, +name: String, +descriptor: String, +args: +List<M.Slot>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  +target : U32 = binding_of(vm, stream, bind_target())
  target_call_found(L.virtual_on(vm, target, name, descriptor), vm, stream, target, args, rest)

@unsafe def target_call_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +target: U32, +args: +List<M.Slot>, +rest: +List<M.SerialTask>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: write_run(vm, stream, rest)
    case Some{+method}: Done{O.Call{L.push_cont(vm, M.NeedSerialWrite{stream, rest}), method, Con{M.Slot{3, target}, args}}}

@unsafe def continue_write(+vm: M.VM, +stream: U32, +tasks: +List<M.SerialTask>, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match tasks:
    case Con{M.WReplaced{+original, +class}, +rest}: replaced(vm, stream, original, class, M.slot_bits(value), rest)
    case Con{M.WHooked{+original}, +rest}: write_resolved_same(U32.is_eq(original, M.slot_bits(value)), vm, stream, original, M.slot_bits(value), rest)
    case _: write_run(vm, stream, tasks)

# --- ObjectInputStream ---
# The byte holder (bind_source) is read at its element, the position MiniJRE
# input streams use: the ByteArrayInputStream or resource stream itself, or the
# buffer a Java InputStream's read methods fill.

@unsafe def source_of(+vm: M.VM, +stream: U32) -> U32:
  binding_of(vm, stream, bind_source())

@unsafe def java_source(+vm: M.VM, +stream: U32) -> Bool:
  U32.is_ne(source_of(vm, stream), binding_of(vm, stream, bind_target()))

@unsafe def position(+vm: M.VM, +stream: U32) -> U32:
  L.entry_element(entry_of(vm, source_of(vm, stream)))

@unsafe def in_byte(+vm: M.VM, +stream: U32, +offset: U32) -> U32:
  M.slot_bits(slot_or_eof(M.nth(M.Slot, values_of(vm, source_of(vm, stream)), U32.add(position(vm, stream), offset))))

@unsafe def slot_or_eof(found: Maybe<&2, M.Slot>) -> M.Slot:
  match found:
    case Some{+slot}: M.Slot{1, U32.and(M.slot_bits(slot), 255)}
    case None{}: M.Slot{1, 4294967295}

@unsafe def with_element(+entry: M.HeapEntry, +element: U32) -> M.HeapEntry:
  M.HeapEntry{H.entry_class(entry), L.entry_kind(entry), element, L.entry_fields(entry), L.entry_values(entry), L.entry_chars(entry)}

@unsafe def advance(+vm: M.VM, +stream: U32, +count: U32) -> M.VM:
  +source : U32 = source_of(vm, stream)
  +entry : M.HeapEntry = entry_of(vm, source)
  H.put(vm, source, with_element(entry, U32.add(L.entry_element(entry), count)))

@unsafe def available(+vm: M.VM, +stream: U32) -> U32:
  +total : U32 = M.length(M.Slot, values_of(vm, source_of(vm, stream)))
  +at : U32 = position(vm, stream)
  Bool.pick(U32, U32.is_le(total, at), 0, U32.sub(total, at))

@unsafe def at_eof(+vm: M.VM, +stream: U32) -> Bool:
  is_true(binding_of(vm, stream, bind_eof()))

# Done once `count` bytes are buffered, or when no more can arrive; otherwise a
# request for the missing bytes, which read_guard makes before replaying.
@unsafe def ensure(+vm: M.VM, +stream: U32, +count: U32) -> Result<&2, &2, String, M.VM>:
  +have : U32 = available(vm, stream)
  ensure_have(U32.is_le(count, have) || Bool.not(java_source(vm, stream)) || at_eof(vm, stream), vm, U32.sub(count, have))

@unsafe def ensure_have(+ready: Bool, +vm: M.VM, +missing: U32) -> Result<&2, &2, String, M.VM>:
  match ready:
    case True{}: Done{vm}
    case False{}: Fail{need_prefix() ++ U32.show(missing)}

type Taken is Data:
  Taken{vm: M.VM, bytes: +List<U32>}

@unsafe def taken_vm(+value: Taken) -> M.VM:
  match value:
    case Taken{+vm, bytes}: vm

@unsafe def taken_bytes(+value: Taken) -> +List<U32>:
  match value:
    case Taken{vm, +bytes}: bytes

# The next `count` stream bytes, outside block data.
@unsafe def take_raw(+vm: M.VM, +stream: U32, +count: U32) -> Result<&2, &2, String, Taken>:
  do Result<&2, &2, String, Taken>:
    +ready : M.VM <- ensure(vm, stream, count)
    enough : Unit <- S.check(U32.is_le(count, available(ready, stream)), "java/io/EOFException")
    +bytes : +List<U32> = slot_bytes(M.take(M.Slot, M.drop(M.Slot, values_of(ready, source_of(ready, stream)), U32.to_nat(position(ready, stream))), U32.to_nat(count)))
    return Taken{advance(ready, stream, count), bytes}

@unsafe def skip_bytes(+vm: M.VM, +stream: U32, +count: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +taken : Taken <- take_raw(vm, stream, count)
    return taken_vm(taken)

@unsafe def left_of(+vm: M.VM, +stream: U32) -> U32:
  binding_of(vm, stream, bind_left())

@unsafe def depth_of(+vm: M.VM, +stream: U32) -> U32:
  binding_of(vm, stream, bind_depth())

@unsafe def set_depth(+vm: M.VM, +stream: U32, +depth: U32) -> M.VM:
  set_binding(vm, stream, bind_depth(), M.Slot{1, depth})

@unsafe def clear_bindings(+vm: M.VM, +reference: U32) -> M.VM:
  +entry : M.HeapEntry = entry_of(vm, reference)
  H.put(vm, reference, M.HeapEntry{H.entry_class(entry), L.entry_kind(entry), L.entry_element(entry), Nil{}, L.entry_values(entry), L.entry_chars(entry)})

# TC_RESET: forget every handle and descriptor, unless an object is being read.
@unsafe def reset_handles(+vm: M.VM, +stream: U32) -> Result<&2, &2, String, M.VM>:
  +depth : U32 = depth_of(vm, stream)
  reset_at(U32.is_eq(depth, 0), depth, vm, stream)

@unsafe def reset_at(+top: Bool, +depth: U32, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, M.VM>:
  match top:
    case False{}: Fail{"java/io/StreamCorruptedException: unexpected reset; recursion depth: " ++ U32.show(depth)}
    case True{}: Done{clear_bindings(set_values(vm, binding_of(vm, stream, bind_handles()), Nil{}), binding_of(vm, stream, bind_descs()))}

# Primitive data: in block-data mode, reads cross TC_BLOCKDATA headers.
@unsafe def take_data(+vm: M.VM, +stream: U32, +count: U32) -> Result<&2, &2, String, Taken>:
  take_data_mode(block_mode(vm, stream), vm, stream, count)

@unsafe def take_data_mode(+block: Bool, +vm: M.VM, +stream: U32, +count: U32) -> Result<&2, &2, String, Taken>:
  match block:
    case False{}: take_raw(vm, stream, count)
    case True{}: take_block(vm, stream, count, Nil{}, U32.to_nat(U32.add(count, 2)))

@unsafe def take_block(+vm: M.VM, +stream: U32, +count: U32, +acc: +List<U32>, +budget: Nat) -> Result<&2, &2, String, Taken>:
  match budget:
    case 0n: Fail{"java/io/StreamCorruptedException: block data"}
    case 1n+ +remaining: take_block_step(U32.is_eq(count, 0), vm, stream, count, acc, remaining)

@unsafe def take_block_step(+done: Bool, +vm: M.VM, +stream: U32, +count: U32, +acc: +List<U32>, +budget: Nat) -> Result<&2, &2, String, Taken>:
  match done:
    case True{}: Done{Taken{vm, acc}}
    case False{}:
      +left : U32 = left_of(vm, stream)
      take_block_left(U32.is_eq(left, 0), left, vm, stream, count, acc, budget)

@unsafe def take_block_left(+empty: Bool, +left: U32, +vm: M.VM, +stream: U32, +count: U32, +acc: +List<U32>, +budget: Nat) -> Result<&2, &2, String, Taken>:
  match empty:
    case True{}:
      do Result<&2, &2, String, Taken>:
        +ready : M.VM <- ensure(vm, stream, 1)
        +result : Taken <- take_block_header(in_byte(ready, stream, 0), ready, stream, count, acc, budget)
        return result
    case False{}:
      do Result<&2, &2, String, Taken>:
        +step : U32 = Bool.pick(U32, U32.is_lt(left, count), left, count)
        +taken : Taken <- take_raw(vm, stream, step)
        +result : Taken <- take_block(set_binding(taken_vm(taken), stream, bind_left(), M.Slot{1, U32.sub(left, step)}), stream, U32.sub(count, step), M.append(U32, acc, taken_bytes(taken)), budget)
        return result

# A block header (TC_RESET may come between blocks); anything else ends the
# block data.
@unsafe def take_block_header(+tag: U32, +vm: M.VM, +stream: U32, +count: U32, +acc: +List<U32>, +budget: Nat) -> Result<&2, &2, String, Taken>:
  do Result<&2, &2, String, Taken>:
    +next : M.VM <- block_header(tag, vm, stream)
    ended : Unit <- S.check(U32.is_eq(tag, 119) || U32.is_eq(tag, 122) || U32.is_eq(tag, 121), "java/io/EOFException")
    +result : Taken <- take_block(next, stream, count, acc, budget)
    return result

# Consumes a TC_BLOCKDATA/TC_BLOCKDATALONG header (setting the block's length)
# or a TC_RESET; other tags are left in place.
@unsafe def block_header(+tag: U32, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, M.VM>:
  match tag:
    case 119:
      do Result<&2, &2, String, M.VM>:
        +header : Taken <- take_raw(vm, stream, 2)
        return set_binding(taken_vm(header), stream, bind_left(), M.Slot{1, word_at(taken_bytes(header), 1)})
    case 122:
      do Result<&2, &2, String, M.VM>:
        +header : Taken <- take_raw(vm, stream, 5)
        return set_binding(taken_vm(header), stream, bind_left(), M.Slot{1, be_word(M.drop(U32, taken_bytes(header), 1n))})
    case 121: reset_handles(advance(vm, stream, 1), stream)
    case _: Done{vm}

@unsafe def u2_of(+bytes: +List<U32>) -> U32:
  U32.or(U32.shln(word_at(bytes, 0), 8n), word_at(bytes, 1))

@unsafe def set_read_mode(+vm: M.VM, +stream: U32, +block: Bool) -> M.VM:
  set_binding(set_binding(vm, stream, bind_block(), M.Slot{1, Bool.pick(U32, block, 1, 0)}), stream, bind_left(), M.Slot{1, 0})

# --- Replaying steps after Java reads and class loads ---

@unsafe def request_kind(+error: String) -> U32:
  Bool.pick(U32, String.starts_with(error, need_prefix()), 1, Bool.pick(U32, String.starts_with(error, class_prefix()), 2, Bool.pick(U32, String.starts_with(error, init_prefix()), 3, 0)))

@unsafe def drop_text(+text: String, +count: Nat) -> String:
  String.from_list(M.drop(Char, String.to_list(text), count))

@unsafe def decimal(+chars: +List<Char>, +acc: U32) -> U32:
  match chars:
    case Nil{}: acc
    case Con{Chr{+c}, rest}: decimal(rest, U32.add(U32.mul(acc, 10), U32.sub(c, 48)))

# A step that failed with a request performs it, then `tasks` (starting with
# the failed step) replay from the state before the step.
@unsafe def read_guard(result: Result<&2, &2, String, O.Outcome>, +vm: M.VM, +stream: U32, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Done{+outcome}: Done{outcome}
    case Fail{+error}: read_request(request_kind(error), error, vm, stream, tasks, values)

@unsafe def read_request(+kind: U32, +error: String, +vm: M.VM, +stream: U32, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match kind:
    case 1: fill_call(vm, stream, decimal(String.to_list(drop_text(error, 12n)), 0), tasks, values)
    case 2: class_call(vm, stream, drop_text(error, 13n), tasks, values)
    case 3: init_call(vm, stream, decimal(String.to_list(drop_text(error, 12n)), 0), tasks, values)
    case _: Fail{error}

# Runs the class's pending initializers (JVMS 5.5) one callback at a time.
@unsafe def init_call(+vm: M.VM, +stream: U32, +class: U32, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  init_start(L.class_for_name_walk(256n, vm, class), stream, tasks, values)

@unsafe def init_start(start: Result<&2, &2, String, L.ClassForNameStart>, +stream: U32, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match start:
    case Fail{+error}: Fail{error}
    case Done{L.ClassForNameReady{+vm}}: read_run(vm, stream, tasks, values)
    case Done{L.ClassForNameCall{+vm, +owner, +method}}: Done{L.init_call(vm, owner, method, M.NeedSerialRead{stream, tasks, values})}
    case Done{L.ClassForNameBlocked{+vm, class}}: Done{L.init_park(vm, class, M.NeedSerialRead{stream, tasks, values})}

# The JDK's PeekInputStream: read() for a single byte, read(byte[], int, int)
# for more (at most a block's worth per call).
@unsafe def fill_call(+vm: M.VM, +stream: U32, +missing: U32, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +wanted : U32 = Bool.pick(U32, U32.is_lt(missing, 1024), missing, 1024)
  fill_kind(U32.is_le(wanted, 1), vm, stream, binding_of(vm, stream, bind_target()), wanted, tasks, values)

@unsafe def fill_kind(+single: Bool, +vm: M.VM, +stream: U32, +target: U32, +missing: U32, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match single:
    case True{}: L.call_virtual(L.push_cont(vm, M.NeedSerialRead{stream, Con{M.RFill{0}, tasks}, values}), L.virtual_on(vm, target, "read", "()I"), [M.Slot{3, target}])
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +array : Ref <- allocated(H.allocate(vm, H.primitive_array_entry(L.class_id(vm, "[B"), 8, H.filled(U32.to_nat(missing), M.Slot{1, 0}))))
        +ready : M.VM = L.push_cont(ref_vm(array), M.NeedSerialRead{stream, Con{M.RFill{ref_reference(array)}, tasks}, values})
        +result : O.Outcome <- L.call_virtual(ready, L.virtual_on(ready, target, "read", "([BII)I"), [M.Slot{3, target}, M.Slot{3, ref_reference(array)}, M.Slot{1, 0}, M.Slot{1, missing}])
        return result

# read() returned a byte (or -1); read(byte[], int, int) a count (or -1).
@unsafe def filled(+vm: M.VM, +stream: U32, +array: U32, +count: U32) -> M.VM:
  match count:
    case 4294967295: set_binding(vm, stream, bind_eof(), M.Slot{1, 1})
    case +n:
      +bytes : +List<U32> = Bool.pick(+List<U32>, U32.is_eq(array, 0), [n], slot_bytes(M.take(M.Slot, values_of(vm, array), U32.to_nat(n))))
      append_values(vm, source_of(vm, stream), byte_slots(bytes))

# resolveClass: Class.forName(name, false, latestUserDefinedLoader()).
@unsafe def class_call(+vm: M.VM, +stream: U32, +name: String, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +loader : U32 = latest_loader(vm)
    +text : Ref <- new_string(vm, L.units_from_string(name))
    +ready : M.VM = L.push_cont(ref_vm(text), M.NeedSerialRead{stream, Con{M.RLoaded{loader, L.class_binary_name(name)}, tasks}, values})
    +method : M.LoadedMethod <- S.require(M.LoadedMethod, L.own_method(S.methods(ready), L.class_id(ready, "java/lang/Class"), Sy.find(S.symbols(ready), "forName"), Sy.find(S.symbols(ready), "(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;")), "InvalidState: Class.forName")
    return O.Call{ready, method, [M.Slot{3, ref_reference(text)}, M.Slot{1, 0}, M.Slot{3, loader}]}

# The loader's namespace now initiates the class (JVMS 5.3.2).
@unsafe def loaded(+vm: M.VM, +loader: U32, +name: String, +mirror: U32) -> M.VM:
  +class : U32 = L.entry_element(entry_of(vm, mirror))
  +namespace : U32 = LD.namespace_of(vm, loader)
  Bool.pick(M.VM, U32.is_eq(namespace, 0), vm, LS.with_alias(vm, namespace, name, class))

# The first user-defined loader on the stack, else the system loader.
@unsafe def latest_loader(+vm: M.VM) -> U32:
  latest_in(vm, S.frames(vm))

@unsafe def latest_in(+vm: M.VM, +frames: +List<M.Frame>) -> U32:
  match frames:
    case Nil{}: L.system_loader_reference()
    case Con{+frame, rest}: latest_found(LS.defined_loader(LS.state_defined(S.loaders(vm)), L.caller_owner_method(vm, S.method_id(frame))), vm, rest)

@unsafe def latest_found(found: Maybe<&2, U32>, +vm: M.VM, +rest: +List<M.Frame>) -> U32:
  match found:
    case None{}: latest_in(vm, rest)
    case Some{+loader}: latest_user(U32.is_eq(loader, L.system_loader_reference()), loader, vm, rest)

@unsafe def latest_user(+system: Bool, +loader: U32, +vm: M.VM, +rest: +List<M.Frame>) -> U32:
  match system:
    case True{}: latest_in(vm, rest)
    case False{}: loader

# Whether a writeObject (or readObject) on this stream is in progress.
@unsafe def stream_busy(+conts: +List<M.Cont>, +stream: U32, +write: Bool) -> Bool:
  match conts:
    case Nil{}: False{}
    case Con{+cont, rest}: busy_step(busy_cont(cont, stream, write), rest, stream, write)

@unsafe def busy_cont(+cont: M.Cont, +stream: U32, +write: Bool) -> Bool:
  match cont:
    case M.NeedSerialWrite{+owner, tasks}: write && U32.is_eq(owner, stream)
    case M.NeedSerialRead{+owner, tasks, values}: Bool.not(write) && U32.is_eq(owner, stream)
    case _: False{}

@unsafe def busy_step(+hit: Bool, +rest: +List<M.Cont>, +stream: U32, +write: Bool) -> Bool:
  match hit:
    case True{}: True{}
    case False{}: stream_busy(rest, stream, write)

@unsafe def busy(+vm: M.VM, +stream: U32, +write: Bool) -> Bool:
  stream_busy(S.host_cont_of(S.host(vm)), stream, write)

# The reader's task machine: values read by RRead are pushed on `values`.
@unsafe def read_run(+vm: M.VM, +stream: U32, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match tasks:
    case Nil{}: L.ref_out(vm, M.slot_bits(top_slot(values)))
    case Con{+task, +rest}: read_guard(read_task(task, vm, stream, rest, values), vm, stream, Con{task, rest}, values)

@unsafe def read_task(+task: M.SerialTask, +vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match task:
    case M.RMode{+block}: read_run(set_read_mode(vm, stream, block), stream, rest, values)
    case M.RRead{}:
      do Result<&2, &2, String, O.Outcome>:
        +ready : M.VM <- ensure(vm, stream, 1)
        +result : O.Outcome <- read_next(in_byte(ready, stream, 0), advance(ready, stream, 1), stream, rest, values)
        return result
    case M.RStore{+object, +slot, +signature}:
      do Result<&2, &2, String, O.Outcome>:
        +stored : M.VM <- store_checked(vm, object, slot, signature, top_slot(values))
        +result : O.Outcome <- read_run(stored, stream, rest, drop_top(values))
        return result
    case M.RElement{+array, +index}: read_run(set_values(vm, array, replace_at(values_of(vm, array), index, top_slot(values))), stream, rest, drop_top(values))
    case M.RSlot{+object, +class, +mode}: read_slot(mode, vm, stream, object, class, rest, values)
    case M.RFields{+object, +fields}: read_fields(vm, stream, object, fields, rest, values)
    case M.RSkipCustom{}: read_skip(vm, stream, rest, values)
    case M.RResolve{+object, +handle}: read_resolve(vm, stream, object, handle, rest, values)
    case M.RPush{+value}: read_run(vm, stream, rest, Con{M.Slot{3, value}, values})
    case M.RContext{+object, +class}: read_run(set_read_context(vm, stream, object, class), stream, rest, values)
    case M.RExternal{+object, +block}: read_external(vm, stream, object, block, rest, values)
    case M.RDrop{}: read_run(vm, stream, rest, drop_top(values))
    case M.RLeave{}: read_run(set_depth(vm, stream, U32.sub(depth_of(vm, stream), 1)), stream, rest, values)
    case M.RRetry{+id, +args}: execute(id, vm, args)
    case M.RDesc{}: read_desc(vm, stream, rest, values)
    case M.RDescFinish{+handle, +desc, +class}: read_desc_finish(vm, stream, desc, class, rest, values)
    case M.RProxyFinish{+handle, +class}: read_proxy_finish(vm, stream, class, rest, values)
    case M.ROrdinary{}: read_ordinary(vm, stream, M.slot_bits(top_slot(values)), rest, drop_top(values))
    case M.RArray{}: read_array(vm, stream, M.slot_bits(top_slot(values)), rest, drop_top(values))
    case M.REnum{}: read_enum(vm, stream, M.slot_bits(top_slot(values)), rest, drop_top(values))
    case M.RClassObject{}:
      do Result<&2, &2, String, O.Outcome>:
        +mirror : Ref <- mirror_of(vm, M.slot_bits(top_slot(values)))
        +result : O.Outcome <- push_handled(ref_vm(mirror), stream, ref_reference(mirror), rest, drop_top(values))
        return result
    case M.RDescObject{}: read_run(vm, stream, rest, Con{M.Slot{3, desc_record(vm, stream, M.slot_bits(top_slot(values)))}, drop_top(values)})
    case M.RCheckResolve{+handle}: check_resolve(vm, stream, handle, rest, values)
    case M.RValidate{}: read_validate(vm, stream, rest, values)
    case M.RAbort{}: read_abort(vm, stream, M.slot_bits(top_slot(values)))
    case M.RVoid{}: L.void_out(vm)
    case _: read_run(vm, stream, rest, values)

# A field another class version lacks has no slot; its value is dropped.
@unsafe def store_slot(+vm: M.VM, +object: U32, +slot: U32, +value: M.Slot) -> M.VM:
  Bool.pick(M.VM, U32.is_eq(slot, none()), vm, set_binding(vm, object, slot, value))

# An object field's value must be an instance of the local field's type
# (ObjectStreamClass.FieldReflector.setObjFieldValues).
@unsafe def store_checked(+vm: M.VM, +object: U32, +slot: U32, +signature: String, +value: M.Slot) -> Result<&2, &2, String, M.VM>:
  +reference : U32 = M.slot_bits(value)
  +unchecked : Bool = U32.is_eq(slot, none()) || U32.is_eq(reference, 0) || String.is_empty(signature)
  +target : U32 = signature_class(vm, signature)
  +fits : Bool = unchecked || (U32.is_ne(target, none()) && H.assignable(S.classes(vm), S.symbols(vm), class_of(vm, reference), target))
  Bool.pick(Result<&2, &2, String, M.VM>, fits, Done{store_slot(vm, object, slot, value)}, Fail{"java/lang/ClassCastException: " ++ cast_message(vm, object, slot, signature, reference)})

@unsafe def cast_message(+vm: M.VM, +object: U32, +slot: U32, +signature: String, +reference: U32) -> String:
  +field : M.LoadedField = field_or_first(M.nth(M.LoadedField, S.fields(vm), slot), vm)
  "cannot assign instance of " ++ class_text(vm, class_of(vm, reference)) ++ " to field " ++ class_text(vm, M.loaded_field_owner(field)) ++ "." ++ Sy.text(S.symbols(vm), M.loaded_field_name(field)) ++ " of type " ++ L.class_display_name(signature_type_name(signature)) ++ " in instance of " ++ class_text(vm, class_of(vm, object))

@unsafe def field_or_first(found: Maybe<&2, M.LoadedField>, +vm: M.VM) -> M.LoadedField:
  match found:
    case Some{+field}: field
    case None{}: M.LoadedField{0, 0, 0, 0, 0, 0}

@unsafe def signature_type_name(+signature: String) -> String:
  match signature:
    case SCon{Chr{76}, +rest}: element_name(SCon{Chr{76}, rest})
    case _: signature

# resolveObject, when enableResolveObject(true) is in force, replaces a
# string, array, enum or ordinary object and its handle.
@unsafe def check_resolve(+vm: M.VM, +stream: U32, +handle: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +hook : Maybe<&2, M.LoadedMethod> = Bool.pick(Maybe<&2, M.LoadedMethod>, is_true(binding_of(vm, stream, bind_resolve())), input_hook(vm, stream, "resolveObject", "(Ljava/lang/Object;)Ljava/lang/Object;"), None{})
  check_resolve_hook(hook, vm, stream, handle, rest, values)

@unsafe def check_resolve_hook(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +handle: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: read_run(vm, stream, rest, values)
    case Some{+method}: Done{O.Call{L.push_cont(vm, M.NeedSerialRead{stream, Con{M.RResolved{handle}, rest}, drop_top(values)}), method, [M.Slot{3, stream}, top_slot(values)]}}

# ObjectInputValidation callbacks, highest priority first, once the top-level
# readObject has read its object.
@unsafe def read_validate(+vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +list : U32 = binding_of(vm, stream, bind_validations())
  read_validate_next(values_of(vm, list), vm, stream, list, rest, values)

@unsafe def read_validate_next(+pending: +List<M.Slot>, +vm: M.VM, +stream: U32, +list: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match pending:
    case Con{+callback, Con{priority, +more}}:
      +object : U32 = M.slot_bits(callback)
      +ready : M.VM = L.push_cont(set_values(vm, list, more), M.NeedSerialRead{stream, Con{M.RValidate{}, rest}, values})
      L.call_virtual(ready, L.virtual_on(ready, object, "validateObject", "()V"), [M.Slot{3, object}])
    case _: read_run(vm, stream, rest, values)

@unsafe def clear_read_tables(+vm: M.VM, +stream: U32) -> M.VM:
  clear_bindings(set_values(vm, binding_of(vm, stream, bind_handles()), Nil{}), binding_of(vm, stream, bind_descs()))

# TC_EXCEPTION (readFatalException): the exception a writer recorded becomes
# the cause of a WriteAbortedException.
@unsafe def read_abort(+vm: M.VM, +stream: U32, +exception: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +aborted : Ref <- aborted(clear_read_tables(vm, stream), "writing aborted", exception)
    return O.ThrownRef{ref_vm(aborted), ref_reference(aborted)}

# Throwable.toString for a MiniJRE throwable: its class, then ": " message.
@unsafe def throwable_text(+vm: M.VM, +exception: U32) -> String:
  +message : U32 = binding_of(vm, exception, 0)
  class_text(vm, class_of(vm, exception)) ++ Bool.pick(String, U32.is_eq(message, 0), "", ": " ++ string_or_empty(L.string_text(vm, message)))

# WriteAbortedException's message ends with its detail's toString.
@unsafe def aborted(+vm: M.VM, +message: String, +exception: U32) -> Result<&2, &2, String, Ref>:
  do Result<&2, &2, String, Ref>:
    +text : Ref <- new_string(vm, L.units_from_string(message ++ Bool.pick(String, U32.is_eq(exception, 0), "", "; " ++ throwable_text(vm, exception))))
    +entry : M.HeapEntry = with_binding(with_binding(H.throwable_entry(L.class_id(ref_vm(text), "java/io/WriteAbortedException")), 0, M.Slot{3, ref_reference(text)}), 1, M.Slot{3, exception})
    +result : Ref <- allocated(H.allocate(ref_vm(text), entry))
    return result

@unsafe def set_read_context(+vm: M.VM, +stream: U32, +object: U32, +class: U32) -> M.VM:
  set_binding(set_binding(vm, stream, bind_object(), M.Slot{3, object}), stream, bind_class(), M.Slot{1, class})

@unsafe def top_slot(+values: +List<M.Slot>) -> M.Slot:
  match values:
    case Con{+slot, rest}: slot
    case Nil{}: M.Slot{3, 0}

@unsafe def drop_top(+values: +List<M.Slot>) -> +List<M.Slot>:
  match values:
    case Con{slot, +rest}: rest
    case Nil{}: Nil{}

@unsafe def push_handled(+vm: M.VM, +stream: U32, +reference: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_run(assign_object(vm, stream, reference), stream, rest, Con{M.Slot{3, reference}, values})

# readObject0: TC_RESET is handled before the depth count; every other tag
# reads one value at depth + 1.
@unsafe def read_next(+tag: U32, +vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match tag:
    case 121:
      do Result<&2, &2, String, O.Outcome>:
        +reset : M.VM <- reset_handles(vm, stream)
        +result : O.Outcome <- read_run(reset, stream, Con{M.RRead{}, rest}, values)
        return result
    case +other: read_tag(other, set_depth(vm, stream, U32.add(depth_of(vm, stream), 1)), stream, Con{M.RLeave{}, rest}, values)

@unsafe def handle_text(+handle: U32) -> String:
  upper_hex(U32.add(handle, 8257536), 8n)

@unsafe def read_tag(+tag: U32, +vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match tag:
    case 112: read_run(set_unshared(vm, stream, False{}), stream, rest, Con{M.Slot{3, 0}, values})
    case 113:
      do Result<&2, &2, String, O.Outcome>:
        +taken : Taken <- take_raw(vm, stream, 4)
        +index : U32 = U32.sub(be_word(taken_bytes(taken)), 8257536)
        +after : M.VM = taken_vm(taken)
        valid : Unit <- S.check(U32.is_lt(index, handle_count(after, stream)), "java/io/StreamCorruptedException: invalid handle value: " ++ handle_text(index))
        shared : Unit <- S.check(Bool.not(unshared(after, stream)), "java/io/InvalidObjectException: cannot read back reference as unshared")
        +handle : M.Slot = handle_at(after, stream, index)
        linked : Unit <- S.check(Bool.not(is_marker(handle)), "java/io/InvalidObjectException: cannot read back reference to unshared object")
        +result : O.Outcome <- read_run(after, stream, rest, Con{M.Slot{3, M.slot_bits(handle)}, values})
        return result
    case 116: read_string(vm, stream, False{}, rest, values)
    case 124: read_string(vm, stream, True{}, rest, values)
    case 118: read_run(vm, stream, Con{M.RDesc{}, Con{M.RClassObject{}, rest}}, values)
    case 117: read_run(vm, stream, Con{M.RDesc{}, Con{M.RArray{}, rest}}, values)
    case 126: read_run(vm, stream, Con{M.RDesc{}, Con{M.REnum{}, rest}}, values)
    case 115: read_run(vm, stream, Con{M.RDesc{}, Con{M.ROrdinary{}, rest}}, values)
    case 114: read_desc_tag(114, vm, stream, Con{M.RDescObject{}, rest}, values)
    case 125: read_desc_tag(125, vm, stream, Con{M.RDescObject{}, rest}, values)
    case 123: read_run(clear_read_tables(vm, stream), stream, [M.RRead{}, M.RAbort{}], Nil{})
    case 119: Fail{"java/io/OptionalDataException"}
    case 122: Fail{"java/io/OptionalDataException"}
    case 120: Fail{"java/io/OptionalDataException"}
    case 4294967295: Fail{"java/io/EOFException"}
    case _: Fail{"java/io/StreamCorruptedException: invalid type code: " ++ upper_hex2(tag)}

@unsafe def hex_digit(+value: U32) -> String:
  Char.show(Chr{Bool.pick(U32, U32.is_lt(value, 10), U32.add(48, value), U32.add(55, value))})

@unsafe def upper_hex2(+value: U32) -> String:
  hex_digit(U32.and(U32.shrn(value, 4n), 15)) ++ hex_digit(U32.and(value, 15))

@unsafe def upper_hex(+value: U32, +digits: Nat) -> String:
  match digits:
    case 0n: ""
    case 1n+ +remaining: upper_hex(U32.shrn(value, 4n), remaining) ++ hex_digit(U32.and(value, 15))

@unsafe def new_string(+vm: M.VM, +units: +List<U32>) -> Result<&2, &2, String, Ref>:
  allocated(H.allocate(vm, H.string_entry(L.class_id(vm, "java/lang/String"), units)))

@unsafe def read_string(+vm: M.VM, +stream: U32, +long: Bool, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +handle : U32 = handle_count(vm, stream)
    +text : Ref <- read_string_value(vm, stream, long)
    +result : O.Outcome <- push_handled(ref_vm(text), stream, ref_reference(text), Con{M.RCheckResolve{handle}, rest}, values)
    return result

@unsafe def read_string_value(+vm: M.VM, +stream: U32, +long: Bool) -> Result<&2, &2, String, Ref>:
  do Result<&2, &2, String, Ref>:
    +head : Taken <- take_raw(vm, stream, Bool.pick(U32, long, 8, 2))
    +length : U32 = Bool.pick(U32, long, be_word(M.drop(U32, taken_bytes(head), 4n)), u2_of(taken_bytes(head)))
    +body : Taken <- take_raw(taken_vm(head), stream, length)
    +result : Ref <- new_string(taken_vm(body), utf_text(taken_bytes(body)))
    return result

type Utf is Data:
  Utf{vm: M.VM, text: String}

@unsafe def read_utf(+vm: M.VM, +stream: U32) -> Result<&2, &2, String, Utf>:
  do Result<&2, &2, String, Utf>:
    +head : Taken <- take_raw(vm, stream, 2)
    +body : Taken <- take_raw(taken_vm(head), stream, u2_of(taken_bytes(head)))
    return Utf{taken_vm(body), L.name_text(utf_text(taken_bytes(body)))}

@unsafe def utf_vm(+value: Utf) -> M.VM:
  match value:
    case Utf{+vm, text}: vm

@unsafe def utf_text_of(+value: Utf) -> String:
  match value:
    case Utf{vm, +text}: text

# --- Resolving stream classes ---

# The element class of an array name ("" for primitive elements); a plain
# class name is its own element.
@unsafe def element_of(+internal: String) -> String:
  match internal:
    case SCon{Chr{91}, +rest}: array_element(rest)
    case _: internal

@unsafe def array_element(+rest: String) -> String:
  match rest:
    case SCon{Chr{91}, +more}: array_element(more)
    case SCon{Chr{76}, +more}: element_name(SCon{Chr{76}, more})
    case _: ""

@unsafe def array_prefix(+internal: String) -> String:
  match internal:
    case SCon{Chr{91}, +rest}: "[" ++ array_prefix(rest)
    case _: ""

# The class a stream class name denotes for latestUserDefinedLoader(): known
# to its namespace, or a request to load it (see class_call).
@unsafe def local_class(+vm: M.VM, +name: String) -> Result<&2, &2, String, Ref>:
  +internal : String = L.class_binary_name(name)
  +element : String = element_of(internal)
  +primitive : Bool = String.is_empty(element)
  +found : U32 = Bool.pick(U32, primitive, none(), LD.loaded_in(vm, latest_loader(vm), element))
  local_class_found(primitive || U32.is_ne(found, none()), primitive, found, vm, internal, element)

@unsafe def local_class_found(+known: Bool, +primitive: Bool, +found: U32, +vm: M.VM, +internal: String, +element: String) -> Result<&2, &2, String, Ref>:
  match known:
    case False{}: Fail{class_prefix() ++ L.internal_to_binary(element)}
    case True{}: local_array(String.starts_with(internal, "["), primitive, found, vm, internal)

@unsafe def local_array(+array: Bool, +primitive: Bool, +found: U32, +vm: M.VM, +internal: String) -> Result<&2, &2, String, Ref>:
  match array:
    case False{}: Done{Ref{vm, found}}
    case True{}:
      do Result<&2, &2, String, Ref>:
        +name : String = Bool.pick(String, primitive, internal, array_prefix(internal) ++ "L" ++ L.class_name_text(vm, found) ++ ";")
        +ready : M.VM <- CL.ensure_array_class(vm, name)
        return Ref{ready, L.class_id(ready, name)}

# --- Class descriptors ---
# Each descriptor read is an ObjectStreamClass, recorded by local class: its
# stream name, serialVersionUID, flags and fields (each with the local binding
# it fills, none for a field the local class lacks), and its stream superclass.

@unsafe def descs_of(+vm: M.VM, +stream: U32) -> U32:
  binding_of(vm, stream, bind_descs())

@unsafe def desc_record(+vm: M.VM, +stream: U32, +class: U32) -> U32:
  binding_of(vm, descs_of(vm, stream), class)

@unsafe def record_desc(+vm: M.VM, +stream: U32, +class: U32, +osc: U32) -> M.VM:
  set_binding(vm, descs_of(vm, stream), class, M.Slot{3, osc})

# readClassDesc: TC_NULL, a handle, TC_CLASSDESC or TC_PROXYCLASSDESC; the
# class id is pushed on the values.
@unsafe def read_desc(+vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +ready : M.VM <- ensure(vm, stream, 1)
    +result : O.Outcome <- read_desc_tag(in_byte(ready, stream, 0), advance(ready, stream, 1), stream, rest, values)
    return result

@unsafe def read_desc_tag(+tag: U32, +vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match tag:
    case 112: read_run(vm, stream, rest, Con{M.Slot{1, none()}, values})
    case 113:
      do Result<&2, &2, String, O.Outcome>:
        +taken : Taken <- take_raw(vm, stream, 4)
        +class : U32 = M.slot_bits(handle_at(taken_vm(taken), stream, U32.sub(be_word(taken_bytes(taken)), 8257536)))
        +result : O.Outcome <- read_run(taken_vm(taken), stream, rest, Con{M.Slot{1, class}, values})
        return result
    case 114: read_plain_desc(vm, stream, rest, values)
    case 125: read_proxy_desc(vm, stream, rest, values)
    case _: Fail{"java/io/StreamCorruptedException: invalid type code: " ++ upper_hex2(tag)}

# readNonProxyDesc: readClassDescriptor, then (in block-data mode)
# resolveClass, the class annotation, and the superclass descriptor.
@unsafe def read_plain_desc(+vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +handle : U32 = handle_count(vm, stream)
  +placeholder : M.VM = assign_handle(vm, stream, M.Slot{1, none()})
  read_desc_hook(input_hook(placeholder, stream, "readClassDescriptor", "()Ljava/io/ObjectStreamClass;"), placeholder, stream, handle, rest, values)

@unsafe def read_desc_hook(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +handle: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{+method}: Done{O.Call{L.push_cont(vm, M.NeedSerialRead{stream, Con{M.RDescRead{handle}, rest}, values}), method, [M.Slot{3, stream}]}}
    case None{}:
      do Result<&2, &2, String, O.Outcome>:
        +osc : Ref <- parse_desc(vm, stream)
        +result : O.Outcome <- read_desc_read(ref_vm(osc), stream, handle, ref_reference(osc), rest, values)
        return result

@unsafe def read_desc_read(+vm: M.VM, +stream: U32, +handle: U32, +osc: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +block : M.VM = set_read_mode(vm, stream, True{})
  read_resolve_hook(input_hook(block, stream, "resolveClass", "(Ljava/io/ObjectStreamClass;)Ljava/lang/Class;"), block, stream, handle, osc, rest, values)

@unsafe def read_resolve_hook(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +handle: U32, +osc: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{+method}: Done{O.Call{L.push_cont(vm, M.NeedSerialRead{stream, Con{M.RDescResolved{handle, osc}, rest}, values}), method, [M.Slot{3, stream}, M.Slot{3, osc}]}}
    case None{}:
      do Result<&2, &2, String, O.Outcome>:
        +local : Ref <- local_class(vm, osc_name(vm, osc))
        +result : O.Outcome <- read_desc_resolved(ref_vm(local), stream, handle, osc, ref_reference(local), rest, values)
        return result

@unsafe def read_desc_resolved(+vm: M.VM, +stream: U32, +handle: U32, +osc: U32, +class: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_run(replace_handle(vm, stream, handle, M.Slot{1, class}), stream, Con{M.RSkipCustom{}, Con{M.RDesc{}, Con{M.RDescFinish{handle, osc, class}, rest}}}, values)

# resolveClass returned a Class (null is a ClassNotFoundException).
@unsafe def resolved_mirror(+vm: M.VM, +stream: U32, +handle: U32, +osc: U32, +mirror: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match mirror:
    case 0: Fail{"java/lang/ClassNotFoundException: null class"}
    case +reference: read_desc_resolved(vm, stream, handle, osc, L.entry_element(entry_of(vm, reference)), rest, values)

# ObjectStreamClass.initNonProxy: the checks against the local class, the
# field matching, then the class's descriptor record.
@unsafe def read_desc_finish(+vm: M.VM, +stream: U32, +osc: U32, +class: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +super : U32 = M.slot_bits(top_slot(values))
  +below : +List<M.Slot> = drop_top(values)
  do Result<&2, &2, String, O.Outcome>:
    ready : Unit <- S.check(Bool.not(needs_init(vm, class)), init_prefix() ++ U32.show(class))
    +checked : M.VM <- check_desc(vm, class, osc_flags(vm, osc), suid_bytes(osc_suid(vm, osc)), osc_name(vm, osc))
    +matched : M.VM <- match_fields(checked, info_fields(checked, class), values_of(checked, osc_array(checked, osc)), osc_name(checked, osc))
    +mirror : Ref <- mirror_of(matched, class)
    +bound : M.VM = set_binding(set_binding(set_binding(ref_vm(mirror), osc, 1, M.Slot{3, ref_reference(mirror)}), osc, 5, M.Slot{1, super}), osc, 6, M.Slot{1, class})
    +result : O.Outcome <- read_run(record_desc(bound, stream, class, osc), stream, rest, Con{M.Slot{1, class}, below})
    return result

# ObjectStreamClass.readNonProxy: name, serialVersionUID, flags, fields.
@unsafe def parse_desc(+vm: M.VM, +stream: U32) -> Result<&2, &2, String, Ref>:
  do Result<&2, &2, String, Ref>:
    +name : Utf <- read_utf(vm, stream)
    +named : Utf = name
    +head : Taken <- take_raw(utf_vm(named), stream, 11)
    +info : +List<U32> = taken_bytes(head)
    +flags : U32 = word_at(info, 8)
    conflict : Unit <- S.check(Bool.not(is_true(U32.and(flags, 4)) && is_true(U32.and(flags, 2))), "java/io/InvalidClassException: " ++ utf_text_of(named) ++ "; serializable and externalizable flags conflict")
    +specs : Specs <- read_specs(taken_vm(head), stream, U32.to_nat(u2_of(M.drop(U32, info, 9n))), Nil{})
    +result : Ref <- new_osc(specs_vm(specs), utf_text_of(named), none(), M.Wide{4, be_word(info), be_word(M.drop(U32, info, 4n))}, flags, specs_fields(specs), none(), False{})
    return result

type Specs is Data:
  Specs{vm: M.VM, fields: +List<M.SerialField>}

@unsafe def specs_vm(+value: Specs) -> M.VM:
  match value:
    case Specs{+vm, fields}: vm

@unsafe def specs_fields(+value: Specs) -> +List<M.SerialField>:
  match value:
    case Specs{vm, +fields}: fields

@unsafe def read_specs(+vm: M.VM, +stream: U32, +count: Nat, +acc: +List<M.SerialField>) -> Result<&2, &2, String, Specs>:
  match count:
    case 0n: Done{Specs{vm, M.reverse(M.SerialField, acc)}}
    case 1n+ +remaining:
      do Result<&2, &2, String, Specs>:
        +code : Taken <- take_raw(vm, stream, 1)
        +c : U32 = word_at(taken_bytes(code), 0)
        +named : Utf <- read_utf(taken_vm(code), stream)
        +typed : Typed <- type_string(is_reference_code(c), utf_vm(named), stream)
        +result : Specs <- read_specs(typed_vm(typed), stream, remaining, Con{M.SerialField{c, utf_text_of(named), typed_text(typed), none()}, acc})
        return result

type Typed is Data:
  Typed{vm: M.VM, text: String}

@unsafe def typed_vm(+value: Typed) -> M.VM:
  match value:
    case Typed{+vm, text}: vm

@unsafe def typed_text(+value: Typed) -> String:
  match value:
    case Typed{vm, +text}: text

# Object and array fields carry their type as a String object (or a handle).
@unsafe def type_string(+reference: Bool, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, Typed>:
  match reference:
    case False{}: Done{Typed{vm, ""}}
    case True{}:
      do Result<&2, &2, String, Typed>:
        +ready : M.VM <- ensure(vm, stream, 1)
        +result : Typed <- read_type_string(in_byte(ready, stream, 0), ready, stream)
        return result

@unsafe def read_type_string(+tag: U32, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, Typed>:
  match tag:
    case 113:
      do Result<&2, &2, String, Typed>:
        +taken : Taken <- take_raw(vm, stream, 5)
        +reference : U32 = M.slot_bits(handle_at(taken_vm(taken), stream, U32.sub(be_word(M.drop(U32, taken_bytes(taken), 1n)), 8257536)))
        return Typed{taken_vm(taken), string_or_empty(L.string_text(taken_vm(taken), reference))}
    case 116: read_type_text(advance(vm, stream, 1), stream, False{})
    case 124: read_type_text(advance(vm, stream, 1), stream, True{})
    case _: Fail{"java/io/StreamCorruptedException: invalid type code: " ++ upper_hex2(tag)}

@unsafe def read_type_text(+vm: M.VM, +stream: U32, +long: Bool) -> Result<&2, &2, String, Typed>:
  do Result<&2, &2, String, Typed>:
    +text : Ref <- read_string_value(vm, stream, long)
    +handled : M.VM = assign_handle(ref_vm(text), stream, M.Slot{3, ref_reference(text)})
    return Typed{handled, string_or_empty(L.string_text(handled, ref_reference(text)))}

# Classes the JDK serializes that this VM's MiniJRE models directly count as
# serializable.
@unsafe def local_serializable(+vm: M.VM, +class: U32) -> Bool:
  is_serializable(vm, class) || U32.is_ne(known_index(L.class_name_text(vm, class)), 0)

# ObjectStreamClass.initNonProxy's checks against the local class (an enum is
# any class assignable to java.lang.Enum, Enum included).
@unsafe def check_desc(+vm: M.VM, +class: U32, +flags: U32, +info: +List<U32>, +name: String) -> Result<&2, &2, String, M.VM>:
  +stream_external : Bool = is_true(U32.and(flags, 4))
  +stream_serial : Bool = stream_external || is_true(U32.and(flags, 2))
  +stream_enum : Bool = is_true(U32.and(flags, 16))
  +local_enum : Bool = is_enum(vm, class) || U32.is_eq(class, L.class_id(vm, "java/lang/Enum"))
  +local_serial : Bool = local_serializable(vm, class)
  +local_external : Bool = is_externalizable(vm, class)
  +same_serial : Bool = same_bool(local_serial, stream_serial)
  do Result<&2, &2, String, M.VM>:
    enum : Unit <- S.check(same_bool(local_enum, stream_enum), "java/io/InvalidClassException: " ++ Bool.pick(String, local_enum, "cannot bind non-enum descriptor to an enum class", "cannot bind enum descriptor to a non-enum class"))
    +suid : M.VM <- check_suid_exempt(String.starts_with(L.class_name_text(vm, class), "[") || local_enum || Bool.not(same_serial), vm, class, info, name)
    kind : Unit <- S.check(local_enum || Bool.not(same_serial) || same_bool(local_external, stream_external), "java/io/InvalidClassException: " ++ name ++ "; Serializable incompatible with Externalizable")
    return suid

# InvalidClassException when the stream's serialVersionUID differs from the
# local class's.
@unsafe def check_suid_exempt(+exempt: Bool, +vm: M.VM, +class: U32, +head: +List<U32>, +name: String) -> Result<&2, &2, String, M.VM>:
  match exempt:
    case True{}: Done{vm}
    case False{}:
      +local : +List<U32> = suid_bytes(class_suid(vm, class))
      +stream_high : U32 = be_word(head)
      +stream_low : U32 = be_word(M.drop(U32, head, 4n))
      +same : Bool = U32.is_eq(stream_high, be_word(local)) && U32.is_eq(stream_low, be_word(M.drop(U32, local, 4n)))
      Bool.pick(Result<&2, &2, String, M.VM>, same, Done{vm}, Fail{"java/io/InvalidClassException: " ++ name ++ "; local class incompatible: stream classdesc serialVersionUID = " ++ long_text(stream_high, stream_low) ++ ", local class serialVersionUID = " ++ long_text(be_word(local), be_word(M.drop(U32, local, 4n)))})

@unsafe def long_text(+high: U32, +low: U32) -> String:
  W.long_show(W.Words{high, low})

@unsafe def is_primitive_code(+code: U32) -> Bool:
  Bool.not(is_reference_code(code))

# ObjectStreamClass.matchFields: stream fields by name; a primitive on either
# side must have the same type code. Each stream field records the local
# binding it fills and that field's signature.
@unsafe def match_fields(+vm: M.VM, +local: +List<M.SerialField>, +fields: +List<M.Slot>, +name: String) -> Result<&2, &2, String, M.VM>:
  match fields:
    case Nil{}: Done{vm}
    case Con{+field, rest}:
      do Result<&2, &2, String, M.VM>:
        +osf : U32 = M.slot_bits(field)
        +text : String = string_or_empty(L.string_text(vm, binding_of(vm, osf, 0)))
        +matched : M.VM <- match_field(local_named(local, text), vm, osf, binding_of(vm, osf, 5), text, name)
        +result : M.VM <- match_fields(matched, local, rest, name)
        return result

@unsafe def local_named(+local: +List<M.SerialField>, +field: String) -> Maybe<&2, M.SerialField>:
  match local:
    case Nil{}: None{}
    case Con{M.SerialField{+code, +name, +signature, +slot}, rest}: local_named_step(String.eq(name, field), M.SerialField{code, name, signature, slot}, rest, field)

@unsafe def local_named_step(+hit: Bool, +candidate: M.SerialField, +rest: +List<M.SerialField>, +field: String) -> Maybe<&2, M.SerialField>:
  match hit:
    case True{}: Some{candidate}
    case False{}: local_named(rest, field)

@unsafe def match_field(found: Maybe<&2, M.SerialField>, +vm: M.VM, +osf: U32, +code: U32, +field: String, +name: String) -> Result<&2, &2, String, M.VM>:
  match found:
    case None{}: Done{set_binding(vm, osf, 4, M.Slot{1, none()})}
    case Some{M.SerialField{+local_code, local_name, +signature, +slot}}:
      do Result<&2, &2, String, M.VM>:
        typed : Unit <- S.check(Bool.not((is_primitive_code(code) || is_primitive_code(local_code)) && U32.is_ne(code, local_code)), "java/io/InvalidClassException: " ++ name ++ "; incompatible types for field " ++ field)
        +text : Ref <- new_string(vm, L.units_from_string(signature))
        return set_binding(set_binding(ref_vm(text), osf, 4, M.Slot{1, slot}), osf, 6, M.Slot{3, ref_reference(text)})

# readProxyDesc: the interface names, then (in block-data mode)
# resolveProxyClass, the class annotation, and Proxy's descriptor.
@unsafe def read_proxy_desc(+vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +handle : U32 = handle_count(vm, stream)
    +placeholder : M.VM = assign_handle(vm, stream, M.Slot{1, none()})
    +count : Taken <- take_raw(placeholder, stream, 4)
    +names : Names <- read_names(taken_vm(count), stream, U32.to_nat(be_word(taken_bytes(count))), Nil{})
    +block : M.VM = set_read_mode(names_vm(names), stream, True{})
    +result : O.Outcome <- read_proxy_hook(input_hook(block, stream, "resolveProxyClass", "([Ljava/lang/String;)Ljava/lang/Class;"), block, stream, handle, names_list(names), rest, values)
    return result

type Names is Data:
  Names{vm: M.VM, list: +List<String>}

@unsafe def names_vm(+value: Names) -> M.VM:
  match value:
    case Names{+vm, list}: vm

@unsafe def names_list(+value: Names) -> +List<String>:
  match value:
    case Names{vm, +list}: list

@unsafe def read_names(+vm: M.VM, +stream: U32, +count: Nat, +acc: +List<String>) -> Result<&2, &2, String, Names>:
  match count:
    case 0n: Done{Names{vm, M.reverse(String, acc)}}
    case 1n+ +remaining:
      do Result<&2, &2, String, Names>:
        +name : Utf <- read_utf(vm, stream)
        +result : Names <- read_names(utf_vm(name), stream, remaining, Con{utf_text_of(name), acc})
        return result

@unsafe def read_proxy_hook(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +handle: U32, +names: +List<String>, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{+method}:
      do Result<&2, &2, String, O.Outcome>:
        +array : Ref <- string_array(vm, names)
        return O.Call{L.push_cont(ref_vm(array), M.NeedSerialRead{stream, Con{M.RProxyResolved{handle}, rest}, values}), method, [M.Slot{3, stream}, M.Slot{3, ref_reference(array)}]}
    case None{}:
      do Result<&2, &2, String, O.Outcome>:
        +proxied : Ref <- proxy_class(vm, names)
        +result : O.Outcome <- read_proxy_resolved(ref_vm(proxied), stream, handle, ref_reference(proxied), rest, values)
        return result

# resolveProxyClass's default: the interfaces through latestUserDefinedLoader().
@unsafe def proxy_class(+vm: M.VM, +names: +List<String>) -> Result<&2, &2, String, Ref>:
  do Result<&2, &2, String, Ref>:
    +mirrors : L.ReflectRefs <- resolve_interfaces(vm, names, Nil{})
    +array : Ref <- class_array(mirrors)
    +catalog : L.ProxyClassResult <- L.proxy_catalog(ref_vm(array), latest_loader(ref_vm(array)), ref_reference(array))
    return proxy_ref(catalog)

@unsafe def string_array(+vm: M.VM, +names: +List<String>) -> Result<&2, &2, String, Ref>:
  do Result<&2, &2, String, Ref>:
    +strings : Refs <- new_strings(vm, names, Nil{})
    +result : Ref <- allocated(H.allocate(refs_vm(strings), H.reference_array_entry(L.class_id(refs_vm(strings), "[Ljava/lang/String;"), L.class_id(refs_vm(strings), "java/lang/String"), refs_slots(strings))))
    return result

@unsafe def new_strings(+vm: M.VM, +names: +List<String>, +acc: +List<M.Slot>) -> Result<&2, &2, String, Refs>:
  match names:
    case Nil{}: Done{Refs{vm, M.reverse(M.Slot, acc)}}
    case Con{+name, rest}:
      do Result<&2, &2, String, Refs>:
        +text : Ref <- new_string(vm, L.units_from_string(name))
        +result : Refs <- new_strings(ref_vm(text), rest, Con{M.Slot{3, ref_reference(text)}, acc})
        return result

@unsafe def read_proxy_resolved(+vm: M.VM, +stream: U32, +handle: U32, +class: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_run(replace_handle(vm, stream, handle, M.Slot{1, class}), stream, Con{M.RSkipCustom{}, Con{M.RDesc{}, Con{M.RProxyFinish{handle, class}, rest}}}, values)

@unsafe def read_proxy_finish(+vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +super : U32 = M.slot_bits(top_slot(values))
  +below : +List<M.Slot> = drop_top(values)
  do Result<&2, &2, String, O.Outcome>:
    +osc : Ref <- new_osc(vm, class_text(vm, class), class, M.Wide{4, 0, 0}, 2, Nil{}, super, True{})
    +result : O.Outcome <- read_run(record_desc(ref_vm(osc), stream, class, ref_reference(osc)), stream, rest, Con{M.Slot{1, class}, below})
    return result

@unsafe def resolved_proxy(+vm: M.VM, +stream: U32, +handle: U32, +mirror: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match mirror:
    case 0: Fail{"java/lang/ClassNotFoundException: null class"}
    case +reference: read_proxy_resolved(vm, stream, handle, L.entry_element(entry_of(vm, reference)), rest, values)

@unsafe def proxy_ref(+catalog: L.ProxyClassResult) -> Ref:
  match catalog:
    case L.ProxyClassResult{+vm, +class}: Ref{vm, class}

@unsafe def resolve_interfaces(+vm: M.VM, +names: +List<String>, +acc: +List<U32>) -> Result<&2, &2, String, L.ReflectRefs>:
  match names:
    case Nil{}: Done{L.ReflectRefs{vm, M.reverse(U32, acc)}}
    case Con{+name, rest}:
      do Result<&2, &2, String, L.ReflectRefs>:
        +local : Ref <- local_class(vm, name)
        +mirror : Ref <- mirror_of(ref_vm(local), ref_reference(local))
        +result : L.ReflectRefs <- resolve_interfaces(ref_vm(mirror), rest, Con{ref_reference(mirror), acc})
        return result

@unsafe def class_array(+refs: L.ReflectRefs) -> Result<&2, &2, String, Ref>:
  match refs:
    case L.ReflectRefs{+vm, +list}: allocated(H.allocate(vm, H.reference_array_entry(L.class_id(vm, "[Ljava/lang/Class;"), L.class_id(vm, "java/lang/Class"), ref_slots(list))))

@unsafe def ref_slots(+refs: +List<U32>) -> +List<M.Slot>:
  match refs:
    case Nil{}: Nil{}
    case Con{+ref, rest}: Con{M.Slot{3, ref}, ref_slots(rest)}

# The interfaces Class[] a proxy instance keeps in binding 1.
@unsafe def interface_mirrors(+vm: M.VM, +ids: +List<U32>, +acc: +List<U32>) -> Result<&2, &2, String, L.ReflectRefs>:
  match ids:
    case Nil{}: Done{L.ReflectRefs{vm, M.reverse(U32, acc)}}
    case Con{+id, rest}:
      do Result<&2, &2, String, L.ReflectRefs>:
        +mirror : Ref <- returned_ref(L.class_mirror_out(vm, id))
        +result : L.ReflectRefs <- interface_mirrors(ref_vm(mirror), rest, Con{ref_reference(mirror), acc})
        return result

# Arrays: primitives in place, references through RRead/RElement.
@unsafe def component_class(+vm: M.VM, +class: U32) -> U32:
  component_of(vm, L.class_name_text(vm, class))

@unsafe def component_of(+vm: M.VM, +name: String) -> U32:
  match name:
    case SCon{Chr{91}, +rest}: L.class_id(vm, element_name(rest))
    case _: none()

@unsafe def element_name(+name: String) -> String:
  match name:
    case SCon{Chr{76}, +rest}: String.from_list(M.take(Char, String.to_list(rest), U32.to_nat(U32.sub(M.length(Char, String.to_list(rest)), 1))))
    case _: name

@unsafe def read_array(+vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +count : Taken <- take_raw(vm, stream, 4)
    +code : U32 = array_code(taken_vm(count), class)
    +result : O.Outcome <- read_array_kind(is_reference_code(code), taken_vm(count), stream, class, code, be_word(taken_bytes(count)), rest, values)
    return result

@unsafe def read_array_kind(+references: Bool, +vm: M.VM, +stream: U32, +class: U32, +code: U32, +length: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match references:
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +array : Ref <- allocated(H.allocate(vm, H.reference_array_entry(class, component_class(vm, class), H.filled(U32.to_nat(length), M.Slot{3, 0}))))
        +reference : U32 = ref_reference(array)
        +handle : U32 = handle_count(ref_vm(array), stream)
        +result : O.Outcome <- read_run(assign_object(ref_vm(array), stream, reference), stream, M.append(M.SerialTask, element_tasks(reference, 0, U32.to_nat(length)), Con{M.RPush{reference}, Con{M.RCheckResolve{handle}, rest}}), values)
        return result
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +width : U32 = primitive_width(code)
        +taken : Taken <- take_raw(vm, stream, U32.mul(width, length))
        +array : Ref <- allocated(H.allocate(taken_vm(taken), H.primitive_array_entry(class, atype_of(code), primitive_slots(code, width, taken_bytes(taken), U32.to_nat(length)))))
        +handle : U32 = handle_count(ref_vm(array), stream)
        +result : O.Outcome <- push_handled(ref_vm(array), stream, ref_reference(array), Con{M.RCheckResolve{handle}, rest}, values)
        return result

@unsafe def element_tasks(+array: U32, +index: U32, +count: Nat) -> +List<M.SerialTask>:
  match count:
    case 0n: Nil{}
    case 1n+ +remaining: Con{M.RRead{}, Con{M.RElement{array, index}, element_tasks(array, U32.add(index, 1), remaining)}}

@unsafe def primitive_width(+code: U32) -> U32:
  match code:
    case 66: 1
    case 90: 1
    case 67: 2
    case 83: 2
    case 74: 8
    case 68: 8
    case _: 4

@unsafe def sign_extend(+value: U32, +bit: U32, +fill: U32) -> U32:
  Bool.pick(U32, U32.is_ge(value, bit), U32.or(value, fill), value)

@unsafe def primitive_slot(+code: U32, +bytes: +List<U32>) -> M.Slot:
  match code:
    case 66: M.Slot{1, sign_extend(word_at(bytes, 0), 128, 4294967040)}
    case 90: M.Slot{1, Bool.pick(U32, is_true(word_at(bytes, 0)), 1, 0)}
    case 67: M.Slot{1, u2_of(bytes)}
    case 83: M.Slot{1, sign_extend(u2_of(bytes), 32768, 4294901760)}
    case 74: M.Wide{4, be_word(bytes), be_word(M.drop(U32, bytes, 4n))}
    case 68: M.Wide{5, be_word(bytes), be_word(M.drop(U32, bytes, 4n))}
    case 70: M.Slot{2, be_word(bytes)}
    case _: M.Slot{1, be_word(bytes)}

@unsafe def primitive_slots(+code: U32, +width: U32, +bytes: +List<U32>, +count: Nat) -> +List<M.Slot>:
  match count:
    case 0n: Nil{}
    case 1n+ +remaining: Con{primitive_slot(code, M.take(U32, bytes, U32.to_nat(width))), primitive_slots(code, width, M.drop(U32, bytes, U32.to_nat(width)), remaining)}

@unsafe def atype_of(+code: U32) -> U32:
  match code:
    case 90: 4
    case 67: 5
    case 70: 6
    case 68: 7
    case 66: 8
    case 83: 9
    case 73: 10
    case _: 11

# TC_ENUM: the constant the name string names.
@unsafe def read_enum(+vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +handle : U32 = handle_count(vm, stream)
    +marked : Bool = unshared(vm, stream)
    +placeholder : M.VM = assign_object(vm, stream, 0)
    +ready : M.VM <- ensure(placeholder, stream, 1)
    +name : Ref <- read_enum_name(in_byte(ready, stream, 0), ready, stream)
    +text : String <- L.string_text(ref_vm(name), ref_reference(name))
    +constant : U32 <- enum_constant(ref_vm(name), class, text)
    +bound : M.VM = Bool.pick(M.VM, marked, ref_vm(name), replace_handle(ref_vm(name), stream, handle, M.Slot{3, constant}))
    +result : O.Outcome <- read_run(bound, stream, Con{M.RCheckResolve{handle}, rest}, Con{M.Slot{3, constant}, values})
    return result

@unsafe def read_enum_name(+tag: U32, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, Ref>:
  match tag:
    case 113:
      do Result<&2, &2, String, Ref>:
        +taken : Taken <- take_raw(advance(vm, stream, 1), stream, 4)
        return Ref{taken_vm(taken), M.slot_bits(handle_at(taken_vm(taken), stream, U32.sub(be_word(taken_bytes(taken)), 8257536)))}
    case 116:
      do Result<&2, &2, String, Ref>:
        +text : Ref <- read_string_value(advance(vm, stream, 1), stream, False{})
        return Ref{assign_handle(ref_vm(text), stream, M.Slot{3, ref_reference(text)}), ref_reference(text)}
    case _: Fail{"java/io/StreamCorruptedException: invalid type code: " ++ upper_hex2(tag)}

@unsafe def enum_constant(+vm: M.VM, +class: U32, +name: String) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +field : M.LoadedField <- S.require(M.LoadedField, L.find_own_public_field(S.fields(vm), class, name, S.symbols(vm)), "java/io/InvalidObjectException: enum constant " ++ name ++ " does not exist in " ++ class_text(vm, class))
    +value : M.Slot <- S.require(M.Slot, H.binding_find(S.statics(vm), M.loaded_field_id(field)), "java/io/InvalidObjectException: enum constant " ++ name ++ " does not exist in " ++ class_text(vm, class))
    return M.slot_bits(value)

# TC_OBJECT. A class whose local and stream forms disagree on Serializable or
# Externalizable is invalid for deserialization.
@unsafe def read_ordinary(+vm: M.VM, +stream: U32, +class: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +flags : U32 = osc_flags(vm, desc_record(vm, stream, class))
  +stream_external : Bool = is_true(U32.and(flags, 4))
  +stream_serial : Bool = stream_external || is_true(U32.and(flags, 2))
  +local_serial : Bool = local_serializable(vm, class)
  +valid : Bool = local_serial && same_bool(local_serial, stream_serial) && same_bool(is_externalizable(vm, class), stream_external)
  read_ordinary_check(valid, vm, stream, class, flags, rest, values)

@unsafe def read_ordinary_check(+valid: Bool, +vm: M.VM, +stream: U32, +class: U32, +flags: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match valid:
    case False{}: Fail{"java/io/InvalidClassException: " ++ class_text(vm, class) ++ "; class invalid for deserialization"}
    case True{}: read_ordinary_kind(L.proxy_class_is_synthetic(vm, class), vm, stream, class, flags, rest, values)

@unsafe def read_ordinary_kind(+proxy: Bool, +vm: M.VM, +stream: U32, +class: U32, +flags: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match proxy:
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +mirrors : L.ReflectRefs <- interface_mirrors(vm, interfaces_of(vm, class), Nil{})
        +array : Ref <- class_array(mirrors)
        +object : Ref <- allocated(H.allocate(ref_vm(array), M.HeapEntry{class, 10, 0, [M.Binding{0, M.Slot{3, 0}}, M.Binding{1, M.Slot{3, ref_reference(array)}}, M.Binding{2, M.Slot{1, class}}], Nil{}, Nil{}}))
        +result : O.Outcome <- read_object_data(ref_vm(object), stream, ref_reference(object), class, Nil{}, rest, values)
        return result
    case False{}: read_instance(is_true(U32.and(flags, 4)), vm, stream, class, flags, rest, values)

@unsafe def read_instance(+external: Bool, +vm: M.VM, +stream: U32, +class: U32, +flags: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match external:
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +constructor : M.LoadedMethod <- S.require(M.LoadedMethod, public_constructor(L.own_method(S.methods(vm), class, Sy.find(S.symbols(vm), "<init>"), Sy.find(S.symbols(vm), "()V"))), "java/io/InvalidClassException: " ++ class_text(vm, class) ++ "; no valid constructor")
        +object : Ref <- allocated(H.allocate(vm, H.object_entry(class, L.reflect_instance_fields(S.fields(vm), S.classes(vm), class))))
        +reference : U32 = ref_reference(object)
        +handle : U32 = handle_count(ref_vm(object), stream)
        +handled : M.VM = assign_object(ref_vm(object), stream, reference)
        +tasks : +List<M.SerialTask> = Con{M.RExternal{reference, is_true(U32.and(flags, 8))}, Con{M.RResolve{reference, handle}, Con{M.RCheckResolve{handle}, rest}}}
        +result : O.Outcome <- read_construct([constructor], handled, stream, reference, tasks, values)
        return result
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +constructor : +List<M.LoadedMethod> <- constructor_of(vm, class)
        +object : Ref <- allocated(H.allocate(vm, H.object_entry(class, L.reflect_instance_fields(S.fields(vm), S.classes(vm), class))))
        +result : O.Outcome <- read_object_data(ref_vm(object), stream, ref_reference(object), class, constructor, rest, values)
        return result

@unsafe def public_constructor(found: Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{+method}: Bool.pick(Maybe<&2, M.LoadedMethod>, is_true(U32.and(M.loaded_method_flags(method), 1)), Some{method}, None{})

# The no-arg constructor of the first non-serializable superclass (none for
# java.lang.Object); it must be accessible from the class.
@unsafe def constructor_of(+vm: M.VM, +class: U32) -> Result<&2, &2, String, +List<M.LoadedMethod>>:
  constructor_walk(vm, class, class, 64n)

@unsafe def constructor_walk(+vm: M.VM, +class: U32, +current: U32, +budget: Nat) -> Result<&2, &2, String, +List<M.LoadedMethod>>:
  match budget:
    case 0n: Done{Nil{}}
    case 1n+ +remaining: constructor_step(is_serializable(vm, current) && U32.is_ne(current, none()), vm, class, current, remaining)

@unsafe def constructor_step(+serializable: Bool, +vm: M.VM, +class: U32, +current: U32, +budget: Nat) -> Result<&2, &2, String, +List<M.LoadedMethod>>:
  match serializable:
    case True{}: constructor_walk(vm, class, parent_of(vm, current), budget)
    case False{}: constructor_found(U32.is_eq(current, L.class_id(vm, "java/lang/Object")) || U32.is_eq(current, none()), vm, class, current)

@unsafe def constructor_found(+trivial: Bool, +vm: M.VM, +class: U32, +current: U32) -> Result<&2, &2, String, +List<M.LoadedMethod>>:
  match trivial:
    case True{}: Done{Nil{}}
    case False{}: constructor_access(L.own_method(S.methods(vm), current, Sy.find(S.symbols(vm), "<init>"), Sy.find(S.symbols(vm), "()V")), vm, class, current)

@unsafe def constructor_access(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +class: U32, +current: U32) -> Result<&2, &2, String, +List<M.LoadedMethod>>:
  match found:
    case None{}: Fail{"java/io/InvalidClassException: " ++ class_text(vm, class) ++ "; no valid constructor"}
    case Some{+method}:
      +flags : U32 = M.loaded_method_flags(method)
      +accessible : Bool = U32.is_eq(U32.and(flags, 2), 0) && (is_true(U32.and(flags, 5)) || L.same_package(vm, class, current))
      Bool.pick(Result<&2, &2, String, +List<M.LoadedMethod>>, accessible, Done{[method]}, Fail{"java/io/InvalidClassException: " ++ class_text(vm, class) ++ "; no valid constructor"})

# The handle, then the constructor, then each class's data as
# ObjectStreamClass.getClassDataLayout pairs stream and local classes.
@unsafe def read_object_data(+vm: M.VM, +stream: U32, +object: U32, +class: U32, +constructor: +List<M.LoadedMethod>, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +handle : U32 = handle_count(vm, stream)
  +handled : M.VM = assign_object(vm, stream, object)
  +slots : +List<M.SerialTask> = layout(object, stream_chain(handled, stream, class, 64n), M.reverse(U32, data_classes(handled, class)), Nil{})
  read_construct(constructor, handled, stream, object, M.append(M.SerialTask, slots, Con{M.RResolve{object, handle}, Con{M.RCheckResolve{handle}, rest}}), values)

# The stream's descriptors for the object, most derived first.
@unsafe def stream_chain(+vm: M.VM, +stream: U32, +class: U32, +budget: Nat) -> +List<U32>:
  match budget:
    case 0n: Nil{}
    case 1n+ +remaining: stream_chain_step(U32.is_eq(class, none()), vm, stream, class, remaining)

@unsafe def stream_chain_step(+done: Bool, +vm: M.VM, +stream: U32, +class: U32, +budget: Nat) -> +List<U32>:
  match done:
    case True{}: Nil{}
    case False{}: Con{class, stream_chain(vm, stream, osc_super(vm, desc_record(vm, stream, class)), budget)}

@unsafe def has_class(+classes: +List<U32>, +class: U32) -> Bool:
  match classes:
    case Nil{}: False{}
    case Con{+head, rest}: has_class_step(U32.is_eq(head, class), rest, class)

@unsafe def has_class_step(+hit: Bool, +rest: +List<U32>, +class: U32) -> Bool:
  match hit:
    case True{}: True{}
    case False{}: has_class(rest, class)

# Walks the stream descriptors (most derived first) against the local
# serializable classes; `acc` collects slots so the result is top-most first.
@unsafe def layout(+object: U32, +streamed: +List<U32>, +local: +List<U32>, +acc: +List<M.SerialTask>) -> +List<M.SerialTask>:
  match streamed:
    case Nil{}: no_data(object, local, acc)
    case Con{+class, more}: layout_match(has_class(local, class), object, class, more, local, acc)

@unsafe def layout_match(+found: Bool, +object: U32, +class: U32, +more: +List<U32>, +local: +List<U32>, +acc: +List<M.SerialTask>) -> +List<M.SerialTask>:
  match found:
    case False{}: layout(object, more, local, Con{M.RSlot{object, class, 2}, acc})
    case True{}: layout_local(local, object, class, more, acc)

# Local classes below the matched one have no data in the stream.
@unsafe def layout_local(+local: +List<U32>, +object: U32, +class: U32, +more: +List<U32>, +acc: +List<M.SerialTask>) -> +List<M.SerialTask>:
  match local:
    case Nil{}: layout(object, more, Nil{}, Con{M.RSlot{object, class, 1}, acc})
    case Con{+head, rest}: layout_local_step(U32.is_eq(head, class), head, rest, object, class, more, acc)

@unsafe def layout_local_step(+hit: Bool, +head: U32, +rest: +List<U32>, +object: U32, +class: U32, +more: +List<U32>, +acc: +List<M.SerialTask>) -> +List<M.SerialTask>:
  match hit:
    case True{}: layout(object, more, rest, Con{M.RSlot{object, class, 1}, acc})
    case False{}: layout_local(rest, object, class, more, Con{M.RSlot{object, head, 0}, acc})

@unsafe def no_data(+object: U32, +local: +List<U32>, +acc: +List<M.SerialTask>) -> +List<M.SerialTask>:
  match local:
    case Nil{}: acc
    case Con{+class, rest}: no_data(object, rest, Con{M.RSlot{object, class, 0}, acc})

@unsafe def read_construct(+constructor: +List<M.LoadedMethod>, +vm: M.VM, +stream: U32, +object: U32, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match constructor:
    case Nil{}: read_run(vm, stream, tasks, values)
    case Con{+method, more}: Done{O.Call{L.push_cont(vm, M.NeedSerialRead{stream, tasks, values}), method, [M.Slot{3, object}]}}

@unsafe def private_found(found: Maybe<&2, M.LoadedMethod>) -> Maybe<&2, M.LoadedMethod>:
  match found:
    case None{}: None{}
    case Some{+method}: Bool.pick(Maybe<&2, M.LoadedMethod>, private_method(Some{method}), Some{method}, None{})

@unsafe def private_of(+vm: M.VM, +class: U32, +name: String, +descriptor: String) -> Maybe<&2, M.LoadedMethod>:
  private_found(L.own_method(S.methods(vm), class, Sy.find(S.symbols(vm), name), Sy.find(S.symbols(vm), descriptor)))

# One class's data: readObjectNoData when the stream has none, readObject
# (in block-data mode) or the default fields, or fields dropped for a class
# the object lacks. Data written by writeObject is skipped up to
# TC_ENDBLOCKDATA afterwards.
@unsafe def read_slot(+mode: U32, +vm: M.VM, +stream: U32, +object: U32, +class: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match mode:
    case 0: read_no_data(private_of(vm, class, "readObjectNoData", "()V"), vm, stream, object, rest, values)
    case 1:
      +record : U32 = desc_record(vm, stream, class)
      read_custom(private_of(vm, class, "readObject", "(Ljava/io/ObjectInputStream;)V"), is_true(U32.and(osc_flags(vm, record), 1)), osc_fields(vm, record), vm, stream, object, class, rest, values)
    case _:
      +record : U32 = desc_record(vm, stream, class)
      read_custom(None{}, is_true(U32.and(osc_flags(vm, record), 1)), dropped(osc_fields(vm, record)), vm, stream, object, class, rest, values)

@unsafe def dropped(+fields: +List<M.SerialField>) -> +List<M.SerialField>:
  match fields:
    case Nil{}: Nil{}
    case Con{M.SerialField{+code, +name, +signature, slot}, rest}: Con{M.SerialField{code, name, signature, none()}, dropped(rest)}

@unsafe def read_no_data(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: read_run(vm, stream, rest, values)
    case Some{+method}: Done{O.Call{L.push_cont(vm, M.NeedSerialRead{stream, rest, values}), method, [M.Slot{3, object}]}}

@unsafe def read_custom(found: Maybe<&2, M.LoadedMethod>, +written: Bool, +fields: +List<M.SerialField>, +vm: M.VM, +stream: U32, +object: U32, +class: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: read_fields(vm, stream, object, fields, Bool.pick(+List<M.SerialTask>, written, Con{M.RMode{True{}}, Con{M.RSkipCustom{}, rest}}, rest), values)
    case Some{+method}:
      +saved : M.SerialTask = M.RContext{binding_of(vm, stream, bind_object()), binding_of(vm, stream, bind_class())}
      +ready : M.VM = set_read_mode(set_read_context(vm, stream, object, class), stream, True{})
      +after : M.SerialTask = Bool.pick(M.SerialTask, written, M.RSkipCustom{}, M.RMode{False{}})
      Done{O.Call{L.push_cont(ready, M.NeedSerialRead{stream, Con{after, Con{saved, rest}}, values}), method, [M.Slot{3, object}, M.Slot{3, stream}]}}

# readExternalData: readExternal without a defaultReadObject context, in
# block-data mode when the stream wrote it so (then skipped to its end).
@unsafe def read_external(+vm: M.VM, +stream: U32, +object: U32, +block: Bool, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_external_found(L.virtual_on(vm, object, "readExternal", "(Ljava/io/ObjectInput;)V"), vm, stream, object, block, rest, values)

@unsafe def read_external_found(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32, +object: U32, +block: Bool, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: Fail{"java/lang/AbstractMethodError: readExternal"}
    case Some{+method}:
      +saved : M.SerialTask = M.RContext{binding_of(vm, stream, bind_object()), binding_of(vm, stream, bind_class())}
      +ready : M.VM = Bool.pick(M.VM, block, set_read_mode(set_read_context(vm, stream, 0, none()), stream, True{}), set_read_context(vm, stream, 0, none()))
      +after : +List<M.SerialTask> = Bool.pick(+List<M.SerialTask>, block, Con{M.RSkipCustom{}, Con{saved, rest}}, Con{saved, rest})
      Done{O.Call{L.push_cont(ready, M.NeedSerialRead{stream, after, values}), method, [M.Slot{3, object}, M.Slot{3, stream}]}}

# skipCustomData: block data and objects up to TC_ENDBLOCKDATA.
@unsafe def read_skip(+vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +skipped : M.VM <- skip_bytes(vm, stream, left_of(vm, stream))
    +plain : M.VM = set_read_mode(skipped, stream, False{})
    +ready : M.VM <- ensure(plain, stream, 1)
    +result : O.Outcome <- skip_tag(in_byte(ready, stream, 0), ready, stream, rest, values)
    return result

@unsafe def skip_tag(+tag: U32, +vm: M.VM, +stream: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match tag:
    case 120: read_run(advance(vm, stream, 1), stream, rest, values)
    case 119:
      do Result<&2, &2, String, O.Outcome>:
        +header : M.VM <- block_header(119, vm, stream)
        +result : O.Outcome <- read_skip(header, stream, rest, values)
        return result
    case 122:
      do Result<&2, &2, String, O.Outcome>:
        +header : M.VM <- block_header(122, vm, stream)
        +result : O.Outcome <- read_skip(header, stream, rest, values)
        return result
    case _: read_run(vm, stream, Con{M.RRead{}, Con{M.RDrop{}, Con{M.RSkipCustom{}, rest}}}, values)

@unsafe def read_fields(+vm: M.VM, +stream: U32, +object: U32, +fields: +List<M.SerialField>, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match fields:
    case Nil{}: read_run(vm, stream, rest, values)
    case Con{M.SerialField{+code, name, +signature, +slot}, more}: read_field_kind(is_reference_code(code), vm, stream, object, code, slot, signature, more, rest, values)

@unsafe def read_field_kind(+reference: Bool, +vm: M.VM, +stream: U32, +object: U32, +code: U32, +slot: U32, +signature: String, +more: +List<M.SerialField>, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match reference:
    case True{}: read_run(vm, stream, Con{M.RRead{}, Con{M.RStore{object, slot, signature}, Con{M.RFields{object, more}, rest}}}, values)
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +taken : Taken <- take_raw(vm, stream, primitive_width(code))
        +result : O.Outcome <- read_fields(store_slot(taken_vm(taken), object, slot, primitive_slot(code, taken_bytes(taken))), stream, object, more, rest, values)
        return result

# readResolve replaces the object and its handle; a SerializedLambda resolves
# through its capturing class's $deserializeLambda$.
@unsafe def read_resolve(+vm: M.VM, +stream: U32, +object: U32, +handle: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_resolve_lambda(U32.is_eq(class_of(vm, object), L.class_id(vm, "java/lang/invoke/SerializedLambda")), vm, stream, object, handle, rest, values)

@unsafe def read_resolve_lambda(+lambda: Bool, +vm: M.VM, +stream: U32, +object: U32, +handle: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match lambda:
    case True{}:
      +capturing : U32 = L.entry_element(entry_of(vm, binding_of(vm, object, 0)))
      +found : Maybe<&2, M.LoadedMethod> = L.own_method(S.methods(vm), capturing, Sy.find(S.symbols(vm), "$deserializeLambda$"), Sy.find(S.symbols(vm), "(Ljava/lang/invoke/SerializedLambda;)Ljava/lang/Object;"))
      read_resolve_call(found, True{}, vm, stream, object, handle, rest, values)
    case False{}: read_resolve_call(L.virtual_on(vm, object, "readResolve", "()Ljava/lang/Object;"), False{}, vm, stream, object, handle, rest, values)

@unsafe def read_resolve_call(found: Maybe<&2, M.LoadedMethod>, +lambda: Bool, +vm: M.VM, +stream: U32, +object: U32, +handle: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: read_resolve_missing(lambda, vm, stream, object, rest, values)
    case Some{+method}: Done{O.Call{L.push_cont(vm, M.NeedSerialRead{stream, Con{M.RResolved{handle}, rest}, values}), method, [M.Slot{3, object}]}}

@unsafe def read_resolve_missing(+lambda: Bool, +vm: M.VM, +stream: U32, +object: U32, +rest: +List<M.SerialTask>, +values: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match lambda:
    case True{}: Fail{"java/io/InvalidObjectException: ReflectiveOperationException during deserialization"}
    case False{}: read_run(vm, stream, rest, Con{M.Slot{3, object}, values})

@unsafe def continue_read(+vm: M.VM, +stream: U32, +tasks: +List<M.SerialTask>, +values: +List<M.Slot>, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match tasks:
    case Con{M.RResolved{+handle}, +rest}: read_run(replace_handle(vm, stream, handle, value), stream, rest, Con{value, values})
    case Con{M.RFill{+array}, +rest}: read_run(filled(vm, stream, array, M.slot_bits(value)), stream, rest, values)
    case Con{M.RLoaded{+loader, +name}, +rest}: read_run(loaded(vm, loader, name, M.slot_bits(value)), stream, rest, values)
    case Con{M.RDescRead{+handle}, +rest}: read_desc_read(vm, stream, handle, M.slot_bits(value), rest, values)
    case Con{M.RDescResolved{+handle, +desc}, +rest}: resolved_mirror(vm, stream, handle, desc, M.slot_bits(value), rest, values)
    case Con{M.RProxyResolved{+handle}, +rest}: resolved_proxy(vm, stream, handle, M.slot_bits(value), rest, values)
    case _: read_run(vm, stream, tasks, values)

# --- Java entry points ---

@unsafe def receiver_and(+args: +List<M.Slot>) -> U32:
  M.slot_bits(slot_or_null(M.nth(M.Slot, args, 0)))

@unsafe def arg_bits(+args: +List<M.Slot>, +index: U32) -> U32:
  M.slot_bits(slot_or_null(M.nth(M.Slot, args, index)))

@unsafe def arg_slot(+args: +List<M.Slot>, +index: U32) -> M.Slot:
  slot_or_null(M.nth(M.Slot, args, index))

@unsafe def new_table(+vm: M.VM) -> Result<&2, &2, String, Ref>:
  allocated(H.allocate(vm, plain_entry(vm)))

@unsafe def oos_setup(+vm: M.VM, +stream: U32, +target: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +handles : Ref <- new_table(vm)
    +holder : Ref <- new_table(ref_vm(handles))
    +subs : Ref <- new_table(ref_vm(holder))
    +bound : M.VM = set_binding(set_binding(set_binding(set_binding(ref_vm(subs), stream, bind_target(), M.Slot{3, target}), stream, bind_handles(), M.Slot{3, ref_reference(handles)}), stream, bind_holder(), M.Slot{3, ref_reference(holder)}), stream, bind_subs(), M.Slot{3, ref_reference(subs)})
    return set_binding(set_context(bound, stream, 0, none()), stream, bind_block(), M.Slot{1, 0})

@unsafe def stream_header() -> +List<U32>:
  [172, 237, 0, 5]

# ObjectOutputStream(OutputStream): writeStreamHeader, then block-data mode.
@unsafe def oos_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    +target : U32 = arg_bits(args, 1)
    checked : Unit <- S.check(U32.is_ne(target, 0), L.npe())
    +ready : M.VM <- oos_setup(vm, stream, target)
    +result : O.Outcome <- oos_header(output_hook(ready, stream, "writeStreamHeader", "()V"), ready, stream)
    return result

@unsafe def oos_header(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: L.void_out(set_mode(raw_emit(vm, stream, stream_header()), stream, True{}))
    case Some{+method}: Done{O.Call{L.push_cont(vm, M.NeedSerialWrite{stream, [M.WMode{True{}}]}), method, [M.Slot{3, stream}]}}

# The protected constructor: a subclass writes through writeObjectOverride.
@unsafe def oos_override_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    +ready : M.VM <- oos_setup(vm, stream, 0)
    result : O.Outcome <- L.void_out(set_binding(ready, stream, bind_override(), M.Slot{1, 1}))
    return result

# writeObject/writeUnshared: outside block data, then back to the previous mode.
@unsafe def oos_write_object(+vm: M.VM, +args: +List<M.Slot>, +shared: Bool) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  oos_write_mode(is_true(binding_of(vm, stream, bind_override())) && shared, vm, args, shared)

@unsafe def oos_write_mode(+override: Bool, +vm: M.VM, +args: +List<M.Slot>, +shared: Bool) -> Result<&2, &2, String, O.Outcome>:
  match override:
    case True{}: L.call_virtual(vm, L.virtual_on(vm, arg_bits(args, 0), "writeObjectOverride", "(Ljava/lang/Object;)V"), [M.Slot{3, arg_bits(args, 0)}, M.Slot{3, arg_bits(args, 1)}])
    case False{}: oos_write_plain(vm, args, shared)

@unsafe def oos_write_plain(+vm: M.VM, +args: +List<M.Slot>, +shared: Bool) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  +previous : Bool = block_mode(vm, stream)
  +value : U32 = arg_bits(args, 1)
  write_run(set_mode(vm, stream, False{}), stream, [Bool.pick(M.SerialTask, shared, M.WObject{value}, M.WUnshared{value}), M.WMode{previous}])

@unsafe def oos_default_write(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  +object : U32 = binding_of(vm, stream, bind_object())
  oos_default_active(U32.is_ne(object, 0), vm, stream, object)

@unsafe def oos_default_active(+active: Bool, +vm: M.VM, +stream: U32, +object: U32) -> Result<&2, &2, String, O.Outcome>:
  match active:
    case False{}: Fail{"java/io/NotActiveException: not in call to writeObject"}
    case True{}: write_run(set_mode(vm, stream, False{}), stream, [M.WFields{object, info_fields(vm, binding_of(vm, stream, bind_class()))}, M.WMode{True{}}])

@unsafe def oos_emit(+vm: M.VM, +args: +List<M.Slot>, +bytes: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  L.void_out(emit(vm, arg_bits(args, 0), bytes))

@unsafe def oos_write_utf(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +text : U32 = arg_bits(args, 1)
    checked : Unit <- S.check(U32.is_ne(text, 0), L.npe())
    +body : +List<U32> = modified_utf8(L.entry_chars(entry_of(vm, text)))
    long : Unit <- S.check(U32.is_le(M.length(U32, body), 65535), "java/io/UTFDataFormatException")
    result : O.Outcome <- oos_emit(vm, args, M.append(U32, short_bytes(M.length(U32, body)), body))
    return result

@unsafe def low_bytes(+units: +List<U32>) -> +List<U32>:
  match units:
    case Nil{}: Nil{}
    case Con{+unit, rest}: Con{U32.and(unit, 255), low_bytes(rest)}

@unsafe def char_bytes(+units: +List<U32>) -> +List<U32>:
  match units:
    case Nil{}: Nil{}
    case Con{+unit, rest}: M.append(U32, short_bytes(unit), char_bytes(rest))

# writeBytes (each char's low byte) and writeChars (each char, big-endian).
@unsafe def oos_write_text(+vm: M.VM, +args: +List<M.Slot>, +wide: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +text : U32 = arg_bits(args, 1)
    checked : Unit <- S.check(U32.is_ne(text, 0), L.npe())
    +units : +List<U32> = L.entry_chars(entry_of(vm, text))
    result : O.Outcome <- oos_emit(vm, args, Bool.pick(+List<U32>, wide, char_bytes(units), low_bytes(units)))
    return result

@unsafe def array_bytes(+vm: M.VM, +array: U32, +offset: U32, +length: U32) -> +List<U32>:
  slot_bytes(M.take(M.Slot, M.drop(M.Slot, values_of(vm, array), U32.to_nat(offset)), U32.to_nat(length)))

@unsafe def oos_write_array(+vm: M.VM, +args: +List<M.Slot>, +ranged: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +array : U32 = arg_bits(args, 1)
    checked : Unit <- S.check(U32.is_ne(array, 0), L.npe())
    +total : U32 = M.length(M.Slot, values_of(vm, array))
    +offset : U32 = Bool.pick(U32, ranged, arg_bits(args, 2), 0)
    +length : U32 = Bool.pick(U32, ranged, arg_bits(args, 3), total)
    bounds : Unit <- S.check(Bool.not(V.negative(offset)) && Bool.not(V.negative(length)) && U32.is_le(U32.add(offset, length), total), "java/lang/IndexOutOfBoundsException")
    result : O.Outcome <- oos_emit(vm, args, array_bytes(vm, array, offset, length))
    return result

# reset(): TC_RESET outside block data, then no handles or replacements.
@unsafe def oos_reset(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  oos_reset_idle(busy(vm, stream, True{}), vm, stream)

@unsafe def oos_reset_idle(+active: Bool, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  match active:
    case True{}: Fail{"java/io/IOException: stream active"}
    case False{}:
      +marked : M.VM = raw_emit(set_mode(vm, stream, False{}), stream, [121])
      +cleared : M.VM = set_values(set_values(marked, binding_of(marked, stream, bind_handles()), Nil{}), binding_of(marked, stream, bind_subs()), Nil{})
      L.void_out(set_mode(cleared, stream, True{}))

# flush/close: drain block data; a non-ByteArrayOutputStream target receives
# the buffered bytes, then flush() or close().
@unsafe def oos_finish(+vm: M.VM, +args: +List<M.Slot>, +name: String) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  +drained : M.VM = drain(vm, stream)
  oos_finish_target(baos_target(drained, binding_of(drained, stream, bind_target())), drained, stream, name)

@unsafe def oos_finish_target(+baos: Bool, +vm: M.VM, +stream: U32, +name: String) -> Result<&2, &2, String, O.Outcome>:
  match baos:
    case True{}: L.void_out(vm)
    case False{}: write_run(vm, stream, [M.WSend{}, M.WTarget{name, "()V"}])

# ByteArrayInputStream and resource streams are read in place; any other
# InputStream through its read methods.
@unsafe def in_place_source(+vm: M.VM, +source: U32) -> Bool:
  +name : String = L.class_name_text(vm, class_of(vm, source))
  U32.is_eq(kind_of(vm, source), 4) && (String.eq(name, "java/io/ByteArrayInputStream") || String.eq(name, "java/io/InputStream"))

@unsafe def new_buffer(+vm: M.VM, +source: U32, +in_place: Bool) -> Result<&2, &2, String, Ref>:
  match in_place:
    case True{}: Done{Ref{vm, source}}
    case False{}: allocated(H.allocate(vm, H.stream_entry(L.class_id(vm, "java/lang/Object"), Nil{})))

# ObjectInputStream(InputStream): the state, then the stream header.
@unsafe def ois_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    +source : U32 = arg_bits(args, 1)
    checked : Unit <- S.check(U32.is_ne(source, 0), L.npe())
    +handles : Ref <- new_table(vm)
    +descs : Ref <- new_table(ref_vm(handles))
    +buffer : Ref <- new_buffer(ref_vm(descs), source, in_place_source(ref_vm(descs), source))
    +bound : M.VM = set_binding(set_binding(set_binding(set_binding(ref_vm(buffer), stream, bind_target(), M.Slot{3, source}), stream, bind_handles(), M.Slot{3, ref_reference(handles)}), stream, bind_descs(), M.Slot{3, ref_reference(descs)}), stream, bind_source(), M.Slot{3, ref_reference(buffer)})
    +validations : Ref <- new_table(bound)
    +listed : M.VM = set_binding(ref_vm(validations), stream, bind_validations(), M.Slot{3, ref_reference(validations)})
    +state : M.VM = set_unshared(set_depth(set_binding(listed, stream, bind_eof(), M.Slot{1, 0}), stream, 0), stream, False{})
    +context : M.VM = set_read_mode(set_read_context(state, stream, 0, none()), stream, False{})
    result : O.Outcome <- ois_header_hook(input_hook(context, stream, "readStreamHeader", "()V"), context, stream)
    return result

# readStreamHeader, then block-data mode.
@unsafe def ois_header_hook(found: Maybe<&2, M.LoadedMethod>, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: ois_header(vm, [M.Slot{3, stream}])
    case Some{+method}: Done{O.Call{L.push_cont(vm, M.NeedSerialRead{stream, [M.RMode{True{}}, M.RVoid{}], Nil{}}), method, [M.Slot{3, stream}]}}

@unsafe def ois_header(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_header_read(vm, arg_bits(args, 0), True{}), vm, arg_bits(args, 0), 724, args)

# readStreamHeader's default: the magic number and version.
@unsafe def ois_read_header(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_header_read(vm, arg_bits(args, 0), False{}), vm, arg_bits(args, 0), 740, args)

@unsafe def ois_header_read(+vm: M.VM, +stream: U32, +block: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +header : Taken <- take_raw(vm, stream, 4)
    +bytes : +List<U32> = taken_bytes(header)
    magic : Unit <- S.check(U32.is_eq(u2_of(bytes), 44269) && U32.is_eq(u2_of(M.drop(U32, bytes, 2n)), 5), "java/io/StreamCorruptedException: invalid stream header: " ++ upper_hex(be_word(bytes), 8n))
    result : O.Outcome <- L.void_out(Bool.pick(M.VM, block, set_read_mode(taken_vm(header), stream, True{}), taken_vm(header)))
    return result

# The protected constructor: a subclass reads through readObjectOverride.
@unsafe def ois_override_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    +handles : Ref <- new_table(vm)
    +descs : Ref <- new_table(ref_vm(handles))
    +buffer : Ref <- new_buffer(ref_vm(descs), 0, False{})
    +validations : Ref <- new_table(ref_vm(buffer))
    +bound : M.VM = set_binding(set_binding(set_binding(set_binding(ref_vm(validations), stream, bind_handles(), M.Slot{3, ref_reference(handles)}), stream, bind_descs(), M.Slot{3, ref_reference(descs)}), stream, bind_source(), M.Slot{3, ref_reference(buffer)}), stream, bind_validations(), M.Slot{3, ref_reference(validations)})
    result : O.Outcome <- L.void_out(set_binding(set_read_context(bound, stream, 0, none()), stream, bind_override(), M.Slot{1, 1}))
    return result

# An intrinsic that reads outside the task machine: a request replays it
# (intrinsic `id`) once the bytes arrive.
@unsafe def read_once(result: Result<&2, &2, String, O.Outcome>, +vm: M.VM, +stream: U32, +id: U32, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_guard(result, vm, stream, [M.RRetry{id, args}], Nil{})

# readObject/readUnshared: unread block data is an OptionalDataException. A
# call that is not nested in another read of this stream starts at depth 0.
@unsafe def ois_read_object(+vm: M.VM, +args: +List<M.Slot>, +shared: Bool) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  ois_read_mode(is_true(binding_of(vm, stream, bind_override())) && shared, vm, stream, shared)

@unsafe def ois_read_mode(+override: Bool, +vm: M.VM, +stream: U32, +shared: Bool) -> Result<&2, &2, String, O.Outcome>:
  match override:
    case True{}: L.call_virtual(vm, L.virtual_on(vm, stream, "readObjectOverride", "()Ljava/lang/Object;"), [M.Slot{3, stream}])
    case False{}:
      +previous : Bool = block_mode(vm, stream)
      +nested : Bool = busy(vm, stream, False{})
      +fresh : M.VM = Bool.pick(M.VM, nested, vm, set_depth(vm, stream, 0))
      ois_read_ready(U32.is_eq(left_of(fresh, stream), 0), previous, nested, set_unshared(fresh, stream, Bool.not(shared)), stream)

# The top-level call runs the registered validations after its object.
@unsafe def ois_read_ready(+ready: Bool, +previous: Bool, +nested: Bool, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  match ready:
    case False{}: Fail{"java/io/OptionalDataException"}
    case True{}: read_run(set_read_mode(vm, stream, False{}), stream, Con{M.RRead{}, Con{M.RMode{previous}, Bool.pick(+List<M.SerialTask>, nested, Nil{}, [M.RValidate{}])}}, Nil{})

@unsafe def ois_default_read(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  +object : U32 = binding_of(vm, stream, bind_object())
  ois_default_active(U32.is_ne(object, 0), vm, stream, object)

@unsafe def ois_default_active(+active: Bool, +vm: M.VM, +stream: U32, +object: U32) -> Result<&2, &2, String, O.Outcome>:
  match active:
    case False{}: Fail{"java/io/NotActiveException: not in call to readObject"}
    case True{}: read_run(set_read_mode(vm, stream, False{}), stream, [M.RFields{object, osc_fields(vm, desc_record(vm, stream, binding_of(vm, stream, bind_class())))}, M.RMode{True{}}, M.RVoid{}], Nil{})

@unsafe def ois_data(+vm: M.VM, +args: +List<M.Slot>, +id: U32, +code: U32) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_data_read(vm, args, code), vm, arg_bits(args, 0), id, args)

@unsafe def ois_data_read(+vm: M.VM, +args: +List<M.Slot>, +code: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +taken : Taken <- take_data(vm, arg_bits(args, 0), primitive_width(code))
    result : O.Outcome <- L.returned(taken_vm(taken), Some{primitive_slot(code, taken_bytes(taken))})
    return result

@unsafe def ois_unsigned(+vm: M.VM, +args: +List<M.Slot>, +id: U32, +width: U32) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_unsigned_read(vm, args, width), vm, arg_bits(args, 0), id, args)

@unsafe def ois_unsigned_read(+vm: M.VM, +args: +List<M.Slot>, +width: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +taken : Taken <- take_data(vm, arg_bits(args, 0), width)
    result : O.Outcome <- L.int_out(taken_vm(taken), Bool.pick(U32, U32.is_eq(width, 1), word_at(taken_bytes(taken), 0), u2_of(taken_bytes(taken))))
    return result

@unsafe def ois_read_utf(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_read_utf_data(vm, args), vm, arg_bits(args, 0), 702, args)

@unsafe def ois_read_utf_data(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    +head : Taken <- take_data(vm, stream, 2)
    +body : Taken <- take_data(taken_vm(head), stream, u2_of(taken_bytes(head)))
    +text : Ref <- new_string(taken_vm(body), utf_text(taken_bytes(body)))
    result : O.Outcome <- L.ref_out(ref_vm(text), ref_reference(text))
    return result

# read(): one byte of block data, or -1 at its end.
@unsafe def ois_read_byte(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_read_byte_result(take_data(vm, arg_bits(args, 0), 1), vm), vm, arg_bits(args, 0), 710, args)

@unsafe def ois_read_byte_result(result: Result<&2, &2, String, Taken>, +vm: M.VM) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Done{+taken}: L.int_out(taken_vm(taken), word_at(taken_bytes(taken), 0))
    case Fail{+error}: Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(request_kind(error), 0), L.int_out(vm, 4294967295), Fail{error})

@unsafe def array_range(+vm: M.VM, +array: U32, +offset: U32, +length: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    checked : Unit <- S.check(U32.is_ne(array, 0), L.npe())
    +total : U32 = M.length(M.Slot, values_of(vm, array))
    bounds : Unit <- S.check(Bool.not(V.negative(offset)) && Bool.not(V.negative(length)) && U32.is_le(U32.add(offset, length), total), "java/lang/IndexOutOfBoundsException")
    return Unit{}

@unsafe def store_bytes(+vm: M.VM, +array: U32, +offset: U32, +bytes: +List<U32>) -> M.VM:
  +target : +List<M.Slot> = values_of(vm, array)
  +count : U32 = M.length(U32, bytes)
  set_values(vm, array, M.append(M.Slot, M.take(M.Slot, target, U32.to_nat(offset)), M.append(M.Slot, signed_bytes(bytes), M.drop(M.Slot, target, U32.to_nat(U32.add(offset, count))))))

# readFully(byte[]) and readFully(byte[], int, int).
@unsafe def ois_read_fully(+vm: M.VM, +args: +List<M.Slot>, +id: U32, +ranged: Bool) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_read_fully_data(vm, args, ranged), vm, arg_bits(args, 0), id, args)

@unsafe def ois_read_fully_data(+vm: M.VM, +args: +List<M.Slot>, +ranged: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +array : U32 = arg_bits(args, 1)
    +offset : U32 = Bool.pick(U32, ranged, arg_bits(args, 2), 0)
    +length : U32 = Bool.pick(U32, ranged, arg_bits(args, 3), M.length(M.Slot, values_of(vm, array)))
    checked : Unit <- array_range(vm, array, offset, length)
    +taken : Taken <- take_data(vm, arg_bits(args, 0), length)
    result : O.Outcome <- L.void_out(store_bytes(taken_vm(taken), array, offset, taken_bytes(taken)))
    return result

# How many block-data bytes a read can return now: the rest of the current
# block, after a header when the next one is already buffered.
@unsafe def block_ready(+vm: M.VM, +stream: U32) -> M.VM:
  +tag : U32 = in_byte(vm, stream, 0)
  +whole : Bool = (U32.is_eq(tag, 119) && U32.is_le(2, available(vm, stream))) || (U32.is_eq(tag, 122) && U32.is_le(5, available(vm, stream)))
  Bool.pick(M.VM, U32.is_eq(left_of(vm, stream), 0) && block_mode(vm, stream) && whole, header_or_same(block_header(tag, vm, stream), vm), vm)

@unsafe def header_or_same(result: Result<&2, &2, String, M.VM>, +vm: M.VM) -> M.VM:
  match result:
    case Done{+ready}: ready
    case Fail{error}: vm

@unsafe def readable(+vm: M.VM, +stream: U32) -> U32:
  +left : U32 = left_of(vm, stream)
  +buffered : U32 = available(vm, stream)
  Bool.pick(U32, block_mode(vm, stream), Bool.pick(U32, U32.is_lt(buffered, left), buffered, left), buffered)

@unsafe def ois_available(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  +ready : M.VM = block_ready(vm, stream)
  L.int_out(ready, readable(ready, stream))

# read(byte[], int, int): up to `length` bytes of the current block (at least
# one), or -1 at the end of the block data; skipBytes discards the same way.
@unsafe def ois_read_some(+vm: M.VM, +args: +List<M.Slot>, +id: U32, +skip: Bool) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_read_some_data(vm, args, skip), vm, arg_bits(args, 0), id, args)

@unsafe def ois_read_some_data(+vm: M.VM, +args: +List<M.Slot>, +skip: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    +array : U32 = Bool.pick(U32, skip, 0, arg_bits(args, 1))
    +offset : U32 = Bool.pick(U32, skip, 0, arg_bits(args, 2))
    +length : U32 = Bool.pick(U32, skip, arg_bits(args, 1), arg_bits(args, 3))
    checked : Unit <- Bool.pick(Result<&2, &2, String, Unit>, skip, Done{Unit{}}, array_range(vm, array, offset, length))
    +first : Result<&2, &2, String, Taken> = take_data(vm, stream, Bool.pick(U32, U32.is_eq(length, 0) || V.negative(length), 0, 1))
    +result : O.Outcome <- ois_read_some_first(first, vm, stream, array, offset, length, skip)
    return result

@unsafe def ois_read_some_first(first: Result<&2, &2, String, Taken>, +vm: M.VM, +stream: U32, +array: U32, +offset: U32, +length: U32, +skip: Bool) -> Result<&2, &2, String, O.Outcome>:
  match first:
    case Fail{+error}: Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(request_kind(error), 0), L.int_out(vm, Bool.pick(U32, skip, 0, 4294967295)), Fail{error})
    case Done{+taken}:
      do Result<&2, &2, String, O.Outcome>:
        +after : M.VM = taken_vm(taken)
        +wanted : U32 = Bool.pick(U32, U32.is_eq(length, 0) || V.negative(length), 0, U32.sub(length, 1))
        +more : U32 = Bool.pick(U32, U32.is_lt(readable(after, stream), wanted), readable(after, stream), wanted)
        +rest : Taken <- take_data(after, stream, more)
        +bytes : +List<U32> = M.append(U32, taken_bytes(taken), taken_bytes(rest))
        +count : U32 = M.length(U32, bytes)
        result : O.Outcome <- L.int_out(Bool.pick(M.VM, skip, taken_vm(rest), store_bytes(taken_vm(rest), array, offset, bytes)), count)
        return result

@unsafe def signed_bytes(+bytes: +List<U32>) -> +List<M.Slot>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b, rest}: Con{M.Slot{1, sign_extend(b, 128, 4294967040)}, signed_bytes(rest)}

# close(): the source stream is closed too.
@unsafe def ois_close(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  +target : U32 = binding_of(vm, stream, bind_target())
  L.call_virtual(L.push_cont(vm, M.NeedSerialRead{stream, [M.RVoid{}], Nil{}}), L.virtual_on(vm, target, "close", "()V"), [M.Slot{3, target}])

# --- Hook defaults and stream state ---

@unsafe def bool_slot(+value: Bool) -> M.Slot:
  M.Slot{1, Bool.pick(U32, value, 1, 0)}

# enableReplaceObject/enableResolveObject: the previous setting.
@unsafe def enable_flag(+vm: M.VM, +args: +List<M.Slot>, +binding: U32) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  +previous : U32 = binding_of(vm, stream, binding)
  L.int_out(set_binding(vm, stream, binding, bool_slot(is_true(arg_bits(args, 1)))), Bool.pick(U32, is_true(previous), 1, 0))

@unsafe def return_argument(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.ref_out(vm, arg_bits(args, 1))

# useProtocolVersion: before anything is written, 1 or 2.
@unsafe def oos_protocol(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    +version : U32 = arg_bits(args, 1)
    empty : Unit <- S.check(U32.is_eq(handle_count(vm, stream), 0), "java/lang/IllegalStateException: stream non-empty")
    known : Unit <- S.check(U32.is_eq(version, 1) || U32.is_eq(version, 2), "java/lang/IllegalArgumentException: unknown version: " ++ V.int_show(version))
    result : O.Outcome <- L.void_out(set_binding(vm, stream, bind_protocol(), M.Slot{1, version}))
    return result

# writeClassDescriptor's default: the descriptor's body.
@unsafe def osc_info(+vm: M.VM, +osc: U32) -> SerialInfo:
  SerialInfo{osc_name(vm, osc), osc_flags(vm, osc), osf_specs(vm, values_of(vm, osc_array(vm, osc))), none()}

@unsafe def osf_specs(+vm: M.VM, +fields: +List<M.Slot>) -> +List<M.SerialField>:
  match fields:
    case Nil{}: Nil{}
    case Con{+field, rest}:
      +osf : U32 = M.slot_bits(field)
      Con{M.SerialField{binding_of(vm, osf, 5), string_or_empty(L.string_text(vm, binding_of(vm, osf, 0))), string_or_empty(L.string_text(vm, binding_of(vm, osf, 2))), binding_of(vm, osf, 4)}, osf_specs(vm, rest)}

@unsafe def oos_write_descriptor(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +osc : U32 = arg_bits(args, 1)
    checked : Unit <- S.check(U32.is_ne(osc, 0), L.npe())
    +written : M.VM <- write_desc_body(vm, arg_bits(args, 0), osc_info(vm, osc), osc_suid(vm, osc))
    result : O.Outcome <- L.void_out(written)
    return result

# readClassDescriptor's default: the descriptor's body, as an ObjectStreamClass.
@unsafe def ois_read_descriptor(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_read_descriptor_data(vm, arg_bits(args, 0)), vm, arg_bits(args, 0), 741, args)

@unsafe def ois_read_descriptor_data(+vm: M.VM, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +osc : Ref <- parse_desc(vm, stream)
    result : O.Outcome <- L.ref_out(ref_vm(osc), ref_reference(osc))
    return result

# resolveClass's default: Class.forName(name, false,
# latestUserDefinedLoader()), or a primitive type's class.
@unsafe def ois_resolve_class(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +osc : U32 = arg_bits(args, 1)
    checked : Unit <- S.check(U32.is_ne(osc, 0), L.npe())
    +name : String = osc_name(vm, osc)
    +primitive : U32 = primitive_class(vm, name)
    +result : O.Outcome <- resolve_named(U32.is_ne(primitive, none()), primitive, vm, osc)
    return result

@unsafe def primitive_class(+vm: M.VM, +name: String) -> U32:
  +known : Bool = String.eq(name, "boolean") || String.eq(name, "byte") || String.eq(name, "char") || String.eq(name, "short") || String.eq(name, "int") || String.eq(name, "long") || String.eq(name, "float") || String.eq(name, "double") || String.eq(name, "void")
  Bool.pick(U32, known, L.class_id(vm, name), none())

@unsafe def resolve_named(+primitive: Bool, +class: U32, +vm: M.VM, +osc: U32) -> Result<&2, &2, String, O.Outcome>:
  match primitive:
    case True{}: L.class_mirror_out(vm, class)
    case False{}: LD.for_name(vm, [M.Slot{3, osc_name_ref(vm, osc)}, M.Slot{1, 0}, M.Slot{3, latest_loader(vm)}], True{})

# resolveProxyClass's default.
@unsafe def ois_resolve_proxy(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  read_once(ois_resolve_proxy_data(vm, args), vm, arg_bits(args, 0), 743, args)

@unsafe def ois_resolve_proxy_data(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +array : U32 = arg_bits(args, 1)
    checked : Unit <- S.check(U32.is_ne(array, 0), L.npe())
    +proxied : Ref <- proxy_class(vm, slot_texts(vm, values_of(vm, array)))
    +mirror : Ref <- mirror_of(ref_vm(proxied), ref_reference(proxied))
    result : O.Outcome <- L.ref_out(ref_vm(mirror), ref_reference(mirror))
    return result

@unsafe def slot_texts(+vm: M.VM, +slots: +List<M.Slot>) -> +List<String>:
  match slots:
    case Nil{}: Nil{}
    case Con{+slot, rest}: Con{string_or_empty(L.string_text(vm, M.slot_bits(slot))), slot_texts(vm, rest)}

# registerValidation: during a readObject, by descending priority (a later
# callback goes before earlier ones of the same priority).
@unsafe def ois_register(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    +callback : U32 = arg_bits(args, 1)
    active : Unit <- S.check(U32.is_ne(depth_of(vm, stream), 0), "java/io/NotActiveException: stream inactive")
    present : Unit <- S.check(U32.is_ne(callback, 0), "java/io/InvalidObjectException: null callback")
    +list : U32 = binding_of(vm, stream, bind_validations())
    result : O.Outcome <- L.void_out(set_values(vm, list, insert_validation(values_of(vm, list), callback, arg_bits(args, 2))))
    return result

@unsafe def insert_validation(+pending: +List<M.Slot>, +callback: U32, +priority: U32) -> +List<M.Slot>:
  match pending:
    case Con{+object, Con{+current, +more}}: insert_validation_step(V.signed_lt(priority, M.slot_bits(current)), object, current, more, callback, priority)
    case _: [M.Slot{3, callback}, M.Slot{1, priority}]

@unsafe def insert_validation_step(+later: Bool, +object: M.Slot, +current: M.Slot, +more: +List<M.Slot>, +callback: U32, +priority: U32) -> +List<M.Slot>:
  match later:
    case True{}: Con{object, Con{current, insert_validation(more, callback, priority)}}
    case False{}: Con{M.Slot{3, callback}, Con{M.Slot{1, priority}, Con{object, Con{current, more}}}}

# --- PutField ---
# Bindings: the class (put_class), the stream (put_stream); values in the
# class's serializable field order.

def put_class() -> U32:
  4294967000

def put_stream() -> U32:
  4294967001

@unsafe def zero_slot(+code: U32) -> M.Slot:
  match code:
    case 74: M.Wide{4, 0, 0}
    case 68: M.Wide{5, 0, 0}
    case 70: M.Slot{2, 0}
    case 76: M.Slot{3, 0}
    case 91: M.Slot{3, 0}
    case _: M.Slot{1, 0}

@unsafe def zero_slots(+fields: +List<M.SerialField>) -> +List<M.Slot>:
  match fields:
    case Nil{}: Nil{}
    case Con{M.SerialField{+code, name, signature, slot}, rest}: Con{zero_slot(code), zero_slots(rest)}

# putFields: one PutField per writeObject call.
@unsafe def oos_put_fields(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +stream : U32 = arg_bits(args, 0)
  +put : U32 = binding_of(vm, stream, bind_put())
  oos_put_known(U32.is_ne(put, 0), put, vm, stream)

@unsafe def oos_put_known(+known: Bool, +put: U32, +vm: M.VM, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  match known:
    case True{}: L.ref_out(vm, put)
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        active : Unit <- S.check(U32.is_ne(binding_of(vm, stream, bind_object()), 0), "java/io/NotActiveException: not in call to writeObject")
        +class : U32 = binding_of(vm, stream, bind_class())
        +entry : M.HeapEntry = with_values(H.object_entry(L.class_id(vm, "java/io/ObjectOutputStream$PutField"), [M.Binding{put_class(), M.Slot{1, class}}, M.Binding{put_stream(), M.Slot{3, stream}}]), zero_slots(info_fields(vm, class)))
        +made : Ref <- allocated(H.allocate(vm, entry))
        result : O.Outcome <- L.ref_out(set_binding(ref_vm(made), stream, bind_put(), M.Slot{3, ref_reference(made)}), ref_reference(made))
        return result

# writeFields: the PutField's values outside block data.
@unsafe def oos_write_fields(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    +put : U32 = binding_of(vm, stream, bind_put())
    current : Unit <- S.check(U32.is_ne(put, 0), "java/io/NotActiveException: no current PutField object")
    +fields : +List<M.SerialField> = info_fields(vm, binding_of(vm, put, put_class()))
    result : O.Outcome <- write_run(set_mode(vm, stream, False{}), stream, [M.WSlots{fields, values_of(vm, put)}, M.WMode{True{}}])
    return result

# ObjectStreamClass.getField(name, type): a primitive type matches its code,
# Object any reference field, and no type (code 0) any field.
@unsafe def type_matches(+field: U32, +wanted: U32) -> Bool:
  U32.is_eq(wanted, 0) || U32.is_eq(field, wanted) || (U32.is_eq(wanted, 76) && is_reference_code(field))

@unsafe def field_index(+fields: +List<M.SerialField>, +name: String, +code: U32, +index: U32) -> U32:
  match fields:
    case Nil{}: none()
    case Con{M.SerialField{+field, +text, signature, slot}, rest}: field_index_step(String.eq(text, name) && type_matches(field, code), rest, name, code, index)

@unsafe def field_index_step(+hit: Bool, +rest: +List<M.SerialField>, +name: String, +code: U32, +index: U32) -> U32:
  match hit:
    case True{}: index
    case False{}: field_index(rest, name, code, U32.add(index, 1))

@unsafe def type_text(+code: U32) -> String:
  match code:
    case 0: "null"
    case 76: "class java.lang.Object"
    case +other: primitive_name(other)

@unsafe def no_such_field(+name: String, +code: U32) -> String:
  "java/lang/IllegalArgumentException: no such field " ++ name ++ " with type " ++ type_text(code)

# PutField.put(name, value).
@unsafe def put_value(+vm: M.VM, +args: +List<M.Slot>, +code: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +put : U32 = arg_bits(args, 0)
    +name : String = string_or_empty(L.string_text(vm, arg_bits(args, 1)))
    +index : U32 = field_index(info_fields(vm, binding_of(vm, put, put_class())), name, code, 0)
    found : Unit <- S.check(U32.is_ne(index, none()), no_such_field(name, code))
    result : O.Outcome <- L.void_out(set_values(vm, put, replace_at(values_of(vm, put), index, arg_slot(args, 2))))
    return result

# PutField.write(ObjectOutput), deprecated: the primitives as data, then each
# object through writeObject.
@unsafe def put_write(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +put : U32 = arg_bits(args, 0)
    +stream : U32 = binding_of(vm, put, put_stream())
    same : Unit <- S.check(U32.is_eq(stream, arg_bits(args, 1)), "java/lang/IllegalArgumentException: wrong stream")
    +fields : +List<M.SerialField> = info_fields(vm, binding_of(vm, put, put_class()))
    +values : +List<M.Slot> = values_of(vm, put)
    +emitted : M.VM = emit(vm, stream, put_primitives(fields, values))
    result : O.Outcome <- write_run(emitted, stream, put_objects(fields, values, block_mode(emitted, stream)))
    return result

@unsafe def put_primitives(+fields: +List<M.SerialField>, +values: +List<M.Slot>) -> +List<U32>:
  match fields:
    case Nil{}: Nil{}
    case Con{M.SerialField{+code, name, signature, slot}, more}:
      +rest : +List<U32> = put_primitives(more, drop_value(values))
      Bool.pick(+List<U32>, is_reference_code(code), rest, M.append(U32, primitive_bytes(code, top_value(values)), rest))

@unsafe def put_objects(+fields: +List<M.SerialField>, +values: +List<M.Slot>, +block: Bool) -> +List<M.SerialTask>:
  match fields:
    case Nil{}: Nil{}
    case Con{M.SerialField{+code, name, signature, slot}, more}:
      +rest : +List<M.SerialTask> = put_objects(more, drop_value(values), block)
      Bool.pick(+List<M.SerialTask>, is_reference_code(code), Con{M.WMode{False{}}, Con{M.WObject{M.slot_bits(top_value(values))}, Con{M.WMode{block}, rest}}}, rest)

# --- GetField ---
# Bindings: the local class (put_class), the stream descriptor (put_stream),
# and each stream field's value under its index.

@unsafe def indexed(+fields: +List<M.SerialField>, +index: U32) -> +List<M.SerialField>:
  match fields:
    case Nil{}: Nil{}
    case Con{M.SerialField{+code, +name, signature, slot}, rest}: Con{M.SerialField{code, name, "", index}, indexed(rest, U32.add(index, 1))}

# readFields: every stream field of the current class, outside block data.
@unsafe def ois_read_fields(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +stream : U32 = arg_bits(args, 0)
    active : Unit <- S.check(U32.is_ne(binding_of(vm, stream, bind_object()), 0), "java/io/NotActiveException: not in call to readObject")
    +class : U32 = binding_of(vm, stream, bind_class())
    +osc : U32 = desc_record(vm, stream, class)
    +made : Ref <- allocated(H.allocate(vm, H.object_entry(L.class_id(vm, "java/io/ObjectInputStream$GetField"), [M.Binding{put_class(), M.Slot{1, class}}, M.Binding{put_stream(), M.Slot{3, osc}}])))
    +get : U32 = ref_reference(made)
    result : O.Outcome <- read_run(set_read_mode(ref_vm(made), stream, False{}), stream, [M.RFields{get, indexed(osc_fields(ref_vm(made), osc), 0)}, M.RMode{True{}}, M.RPush{get}], Nil{})
    return result

# GetField.get(name, default) and defaulted(name): a stream field's value;
# the default for a field only the local class has.
@unsafe def get_lookup(+vm: M.VM, +get: U32, +name: String, +code: U32) -> Result<&2, &2, String, U32>:
  +index : U32 = field_index(osc_fields(vm, binding_of(vm, get, put_stream())), name, code, 0)
  +local : Bool = U32.is_ne(field_index(info_fields(vm, binding_of(vm, get, put_class())), name, code, 0), none())
  Bool.pick(Result<&2, &2, String, U32>, U32.is_ne(index, none()) || local, Done{index}, Fail{no_such_field(name, code)})

@unsafe def get_value(+vm: M.VM, +args: +List<M.Slot>, +code: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +get : U32 = arg_bits(args, 0)
    +index : U32 <- get_lookup(vm, get, string_or_empty(L.string_text(vm, arg_bits(args, 1))), code)
    +value : M.Slot = Bool.pick(M.Slot, U32.is_eq(index, none()), arg_slot(args, 2), slot_or_zero(H.binding_find(L.entry_fields(entry_of(vm, get)), index)))
    result : O.Outcome <- L.returned(vm, Some{value})
    return result

@unsafe def get_defaulted(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +get : U32 = arg_bits(args, 0)
    +index : U32 <- get_lookup(vm, get, string_or_empty(L.string_text(vm, arg_bits(args, 1))), 0)
    result : O.Outcome <- L.bool_out(vm, U32.is_eq(index, none()))
    return result

# --- ObjectStreamClass and ObjectStreamField methods ---

@unsafe def osc_lookup(+vm: M.VM, +args: +List<M.Slot>, +any: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +mirror : U32 = arg_bits(args, 0)
    checked : Unit <- S.check(U32.is_ne(mirror, 0), L.npe())
    +class : U32 = L.entry_element(entry_of(vm, mirror))
    +result : O.Outcome <- osc_lookup_class(any || local_serializable(vm, class), vm, class)
    return result

@unsafe def osc_lookup_class(+described: Bool, +vm: M.VM, +class: U32) -> Result<&2, &2, String, O.Outcome>:
  match described:
    case False{}: L.ref_out(vm, 0)
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +osc : Ref <- class_osc(vm, class)
        result : O.Outcome <- L.ref_out(ref_vm(osc), ref_reference(osc))
        return result

@unsafe def binding_out(+vm: M.VM, +args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, O.Outcome>:
  L.ref_out(vm, binding_of(vm, arg_bits(args, 0), index))

@unsafe def osc_get_fields(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +array : U32 = osc_array(vm, arg_bits(args, 0))
    +copy : Ref <- allocated(H.allocate(vm, entry_of(vm, array)))
    result : O.Outcome <- L.ref_out(ref_vm(copy), ref_reference(copy))
    return result

@unsafe def osc_get_field(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +fields : +List<M.Slot> = values_of(vm, osc_array(vm, arg_bits(args, 0)))
  +index : U32 = field_index(osf_specs(vm, fields), string_or_empty(L.string_text(vm, arg_bits(args, 1))), 0, 0)
  L.ref_out(vm, Bool.pick(U32, U32.is_eq(index, none()), 0, M.slot_bits(slot_or_null(M.nth(M.Slot, fields, index)))))

@unsafe def text_out(+vm: M.VM, +text: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +made : Ref <- new_string(vm, L.units_from_string(text))
    result : O.Outcome <- L.ref_out(ref_vm(made), ref_reference(made))
    return result

@unsafe def osc_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +osc : U32 = arg_bits(args, 0)
  +suid : +List<U32> = suid_bytes(osc_suid(vm, osc))
  text_out(vm, osc_name(vm, osc) ++ ": static final long serialVersionUID = " ++ long_text(be_word(suid), be_word(M.drop(U32, suid, 4n))) ++ "L;")

# ObjectStreamField(String name, Class<?> type[, boolean unshared]).
@unsafe def type_signature(+vm: M.VM, +class: U32) -> String:
  +name : String = L.class_name_text(vm, class)
  +code : U32 = primitive_code(name)
  Bool.pick(String, U32.is_ne(code, 0), Char.show(Chr{code}), Bool.pick(String, String.starts_with(name, "["), name, "L" ++ name ++ ";"))

@unsafe def primitive_code(+name: String) -> U32:
  Bool.pick(U32, String.eq(name, "boolean"), 90, Bool.pick(U32, String.eq(name, "byte"), 66, Bool.pick(U32, String.eq(name, "char"), 67, Bool.pick(U32, String.eq(name, "short"), 83,
  Bool.pick(U32, String.eq(name, "int"), 73, Bool.pick(U32, String.eq(name, "long"), 74, Bool.pick(U32, String.eq(name, "float"), 70, Bool.pick(U32, String.eq(name, "double"), 68, 0))))))))

@unsafe def osf_init(+vm: M.VM, +args: +List<M.Slot>, +flagged: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 = arg_bits(args, 0)
    +name : U32 = arg_bits(args, 1)
    +mirror : U32 = arg_bits(args, 2)
    named : Unit <- S.check(U32.is_ne(name, 0) && U32.is_ne(mirror, 0), L.npe())
    +signature : String = type_signature(vm, L.entry_element(entry_of(vm, mirror)))
    +signed : Ref <- new_string(vm, L.units_from_string(signature))
    +unshared : U32 = Bool.pick(U32, flagged, arg_bits(args, 3), 0)
    +bindings : +List<M.Binding> = [M.Binding{0, M.Slot{3, name}}, M.Binding{1, M.Slot{3, mirror}}, M.Binding{2, M.Slot{3, ref_reference(signed)}}, M.Binding{3, M.Slot{1, unshared}}, M.Binding{4, M.Slot{1, none()}}, M.Binding{5, M.Slot{1, field_code(signature)}}, M.Binding{6, M.Slot{3, 0}}]
    result : O.Outcome <- L.void_out(H.put(ref_vm(signed), receiver, H.object_entry(class_of(ref_vm(signed), receiver), bindings)))
    return result

@unsafe def osf_code(+vm: M.VM, +args: +List<M.Slot>) -> U32:
  binding_of(vm, arg_bits(args, 0), 5)

@unsafe def osf_type_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.ref_out(vm, Bool.pick(U32, is_reference_code(osf_code(vm, args)), binding_of(vm, arg_bits(args, 0), 2), 0))

@unsafe def osf_to_string(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +osf : U32 = arg_bits(args, 0)
  text_out(vm, string_or_empty(L.string_text(vm, binding_of(vm, osf, 2))) ++ " " ++ string_or_empty(L.string_text(vm, binding_of(vm, osf, 0))))

# compareTo: primitives first, then by name.
@unsafe def osf_compare(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  +left : U32 = arg_bits(args, 0)
  +right : U32 = arg_bits(args, 1)
  +left_primitive : Bool = Bool.not(is_reference_code(binding_of(vm, left, 5)))
  +right_primitive : Bool = Bool.not(is_reference_code(binding_of(vm, right, 5)))
  +order : U32 = Bool.pick(U32, same_bool(left_primitive, right_primitive), units_compare(L.entry_chars(entry_of(vm, binding_of(vm, left, 0))), L.entry_chars(entry_of(vm, binding_of(vm, right, 0)))), Bool.pick(U32, left_primitive, 4294967295, 1))
  L.int_out(vm, order)

# String.compareTo over UTF-16 units.
@unsafe def units_compare(+left: +List<U32>, +right: +List<U32>) -> U32:
  match left:
    case Nil{}: U32.sub(0, M.length(U32, right))
    case Con{+a, +more}: units_compare_head(right, a, more)

@unsafe def units_compare_head(+right: +List<U32>, +a: U32, +more: +List<U32>) -> U32:
  match right:
    case Nil{}: U32.add(M.length(U32, more), 1)
    case Con{+b, +others}: units_compare_step(U32.is_eq(a, b), a, b, more, others)

@unsafe def units_compare_step(+same: Bool, +a: U32, +b: U32, +more: +List<U32>, +others: +List<U32>) -> U32:
  match same:
    case True{}: units_compare(more, others)
    case False{}: U32.sub(a, b)

# WriteAbortedException(String, Exception).
@unsafe def aborted_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 = arg_bits(args, 0)
    +detail : U32 = arg_bits(args, 2)
    +message : String = Bool.pick(String, U32.is_eq(arg_bits(args, 1), 0), "null", string_or_empty(L.string_text(vm, arg_bits(args, 1))))
    +made : Ref <- aborted(vm, message, detail)
    +entry : M.HeapEntry = entry_of(ref_vm(made), ref_reference(made))
    result : O.Outcome <- L.void_out(H.put(ref_vm(made), receiver, M.HeapEntry{class_of(ref_vm(made), receiver), L.entry_kind(entry), L.entry_element(entry), L.entry_fields(entry), Nil{}, Nil{}}))
    return result

# Intrinsic ids 681-788 (bootstrap Sigs); 724 replays the stream header.
@unsafe def execute(+id: U32, +vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match id:
    case 681: oos_init(vm, args)
    case 682: oos_write_object(vm, args, True{})
    case 683: oos_default_write(vm, args)
    case 684: oos_emit(vm, args, int_bytes(arg_bits(args, 1)))
    case 685: oos_write_utf(vm, args)
    case 686: oos_emit(vm, args, suid_bytes(arg_slot(args, 1)))
    case 687: oos_emit(vm, args, [Bool.pick(U32, is_true(arg_bits(args, 1)), 1, 0)])
    case 688: oos_emit(vm, args, [U32.and(arg_bits(args, 1), 255)])
    case 689: oos_emit(vm, args, short_bytes(arg_bits(args, 1)))
    case 690: oos_emit(vm, args, short_bytes(arg_bits(args, 1)))
    case 691: oos_emit(vm, args, int_bytes(arg_bits(args, 1)))
    case 692: oos_emit(vm, args, suid_bytes(arg_slot(args, 1)))
    case 693: oos_emit(vm, args, [U32.and(arg_bits(args, 1), 255)])
    case 694: oos_write_array(vm, args, False{})
    case 695: oos_write_array(vm, args, True{})
    case 696: oos_finish(vm, args, "flush")
    case 697: oos_finish(vm, args, "close")
    case 698: ois_init(vm, args)
    case 699: ois_read_object(vm, args, True{})
    case 700: ois_default_read(vm, args)
    case 701: ois_data(vm, args, 701, 73)
    case 702: ois_read_utf(vm, args)
    case 703: ois_data(vm, args, 703, 74)
    case 704: ois_data(vm, args, 704, 90)
    case 705: ois_data(vm, args, 705, 66)
    case 706: ois_data(vm, args, 706, 83)
    case 707: ois_data(vm, args, 707, 67)
    case 708: ois_data(vm, args, 708, 70)
    case 709: ois_data(vm, args, 709, 68)
    case 710: ois_read_byte(vm, args)
    case 711: ois_close(vm, args)
    case 712: ois_unsigned(vm, args, 712, 1)
    case 713: ois_unsigned(vm, args, 713, 2)
    case 714: ois_read_fully(vm, args, 714, False{})
    case 715: oos_write_object(vm, args, False{})
    case 716: oos_reset(vm, args)
    case 717: oos_write_text(vm, args, False{})
    case 718: oos_write_text(vm, args, True{})
    case 719: ois_read_object(vm, args, False{})
    case 720: ois_read_some(vm, args, 720, False{})
    case 721: ois_read_fully(vm, args, 721, True{})
    case 722: ois_read_some(vm, args, 722, True{})
    case 723: ois_available(vm, args)
    case 724: ois_header(vm, args)
    case 726: oos_override_init(vm, args)
    case 727: L.void_out(vm)
    case 728: L.void_out(emit(vm, arg_bits(args, 0), stream_header()))
    case 729: oos_write_descriptor(vm, args)
    case 730: L.void_out(vm)
    case 731: L.void_out(vm)
    case 732: return_argument(vm, args)
    case 733: enable_flag(vm, args, bind_replace())
    case 734: oos_protocol(vm, args)
    case 735: L.void_out(drain(vm, arg_bits(args, 0)))
    case 736: oos_put_fields(vm, args)
    case 737: oos_write_fields(vm, args)
    case 738: ois_override_init(vm, args)
    case 739: L.ref_out(vm, 0)
    case 740: ois_read_header(vm, args)
    case 741: ois_read_descriptor(vm, args)
    case 742: ois_resolve_class(vm, args)
    case 743: ois_resolve_proxy(vm, args)
    case 744: return_argument(vm, args)
    case 745: enable_flag(vm, args, bind_resolve())
    case 746: ois_register(vm, args)
    case 747: ois_read_fields(vm, args)
    case 748: osc_lookup(vm, args, False{})
    case 749: osc_lookup(vm, args, True{})
    case 750: binding_out(vm, args, 0)
    case 751: L.returned(vm, Some{osc_suid(vm, arg_bits(args, 0))})
    case 752: binding_out(vm, args, 1)
    case 753: osc_get_fields(vm, args)
    case 754: osc_get_field(vm, args)
    case 755: osc_to_string(vm, args)
    case 756: osf_init(vm, args, False{})
    case 757: osf_init(vm, args, True{})
    case 758: binding_out(vm, args, 0)
    case 759: binding_out(vm, args, 1)
    case 760: L.int_out(vm, osf_code(vm, args))
    case 761: osf_type_string(vm, args)
    case 762: L.bool_out(vm, Bool.not(is_reference_code(osf_code(vm, args))))
    case 763: L.bool_out(vm, is_true(binding_of(vm, arg_bits(args, 0), 3)))
    case 764: osf_to_string(vm, args)
    case 765: osf_compare(vm, args)
    case 766: L.int_out(vm, 0)
    case 767: put_value(vm, args, 90)
    case 768: put_value(vm, args, 66)
    case 769: put_value(vm, args, 67)
    case 770: put_value(vm, args, 83)
    case 771: put_value(vm, args, 73)
    case 772: put_value(vm, args, 74)
    case 773: put_value(vm, args, 70)
    case 774: put_value(vm, args, 68)
    case 775: put_value(vm, args, 76)
    case 776: put_write(vm, args)
    case 777: binding_out(vm, args, put_stream())
    case 778: get_defaulted(vm, args)
    case 779: get_value(vm, args, 90)
    case 780: get_value(vm, args, 66)
    case 781: get_value(vm, args, 67)
    case 782: get_value(vm, args, 83)
    case 783: get_value(vm, args, 73)
    case 784: get_value(vm, args, 74)
    case 785: get_value(vm, args, 70)
    case 786: get_value(vm, args, 68)
    case 787: get_value(vm, args, 76)
    case 788: aborted_init(vm, args)
    case _: Fail{"InvalidState: serialization intrinsic"}

@unsafe def continue_java(+vm: M.VM, +cont: M.Cont, +value: M.Slot) -> Result<&2, &2, String, O.Outcome>:
  match cont:
    case M.NeedSerialWrite{+stream, +tasks}: continue_write(vm, stream, tasks, value)
    case M.NeedSerialRead{+stream, +tasks, +values}: continue_read(vm, stream, tasks, values, value)
    case _: Fail{"InvalidState: serialization continuation"}
