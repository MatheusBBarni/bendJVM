import Base
import ../model.bend as M
import ../runtime/state.bend as S

type Allocation is Data:
  Allocation{vm: M.VM, reference: U32}

def binding_find(xs: +List<M.Binding>, +id: U32) -> Maybe<&2, M.Slot>:
  match xs:
    case Nil{}:
      None{}
    case Con{M.Binding{binding_id, value}, rest}:
      Bool.pick(Maybe<&2, M.Slot>, U32.is_eq(binding_id, id), Some{value}, binding_find(rest, id))

def binding_set(xs: +List<M.Binding>, +id: U32, +value: M.Slot) -> +List<M.Binding>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{M.Binding{+binding_id, old}, rest}:
      Con{M.Binding{binding_id, Bool.pick(M.Slot, U32.is_eq(binding_id, id), value, old)}, binding_set(rest, id, value)}

def get_nonnull(heap: +List<M.HeapEntry>, reference: U32, null: Bool) -> Result<&2, &2, String, M.HeapEntry>:
  match null:
    case True{}:
      Fail{"NullPointerException"}
    case False{}:
      S.require(M.HeapEntry, M.nth(M.HeapEntry, heap, U32.sub(reference, 1)), "InvalidReference")

def get(heap: +List<M.HeapEntry>, +reference: U32) -> Result<&2, &2, String, M.HeapEntry>:
  get_nonnull(heap, reference, U32.is_eq(reference, 0))

def put(+vm: M.VM, reference: U32, entry: M.HeapEntry) -> M.VM:
  S.with_heap(vm, M.replace(M.HeapEntry, S.heap(vm), U32.to_nat(U32.sub(reference, 1)), entry))

def allocate_room(+vm: M.VM, entry: M.HeapEntry, room: Bool) -> Result<&2, &2, String, Allocation>:
  match room:
    case False{}:
      Fail{"OutOfMemoryError"}
    case True{}:
      +heap = S.heap(vm)
      Done{Allocation{S.with_heap(vm, M.append(M.HeapEntry, heap, Con{entry, Nil{}})), U32.add(M.length(M.HeapEntry, heap), 1)}}

def allocate(+vm: M.VM, entry: M.HeapEntry) -> Result<&2, &2, String, Allocation>:
  allocate_room(vm, entry, U32.is_lt(M.length(M.HeapEntry, S.heap(vm)), S.max_heap(vm)))

def filled(n: Nat, +value: M.Slot) -> +List<M.Slot>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{value, filled(p, value)}

def symbol_equal(value: Maybe<&2, String>, name: String) -> Bool:
  match value:
    case None{}:
      False{}
    case Some{text}:
      String.eq(text, name)

def named_class(classes: +List<M.LoadedClass>, +symbols: +List<String>, +name: String) -> U32:
  match classes:
    case Nil{}:
      4294967295
    case Con{M.LoadedClass{class_id, class_name, parent, interfaces, fields, methods, initializer, state}, rest}:
      Bool.pick(U32, symbol_equal(M.nth(String, symbols, class_name), name), class_id, named_class(rest, symbols, name))

def name_value(value: Maybe<&2, String>) -> String:
  match value:
    case None{}:
      ""
    case Some{text}:
      text

# A bounded worklist covers superclass and interface edges, including diamonds.
def ancestry_expand(class: Maybe<&2, M.LoadedClass>, rest: +List<U32>) -> +List<U32>:
  match class:
    case None{}:
      rest
    case Some{M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state}}:
      Con{parent, M.append(U32, interfaces, rest)}

def contains(xs: +List<U32>, +value: U32) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      Bool.or(U32.is_eq(h, value), contains(t, value))

def ancestry_next(+classes: +List<M.LoadedClass>, +id: U32, rest: +List<U32>, visited: +List<U32>, seen: Bool) -> +List<U32>:
  match seen:
    case True{}:
      rest
    case False{}:
      ancestry_expand(M.nth(M.LoadedClass, classes, id), rest)

def ancestry(fuel: Nat, +classes: +List<M.LoadedClass>, frontier: +List<U32>, +target: U32, +visited: +List<U32>) -> Bool:
  match fuel frontier:
    case 0n _:
      False{}
    case 1n+p Nil{}:
      False{}
    case 1n+p Con{+id, rest}:
      Bool.or(U32.is_eq(id, target), ancestry(p, classes, ancestry_next(classes, id, rest, visited, contains(visited, id)), target, Con{id, visited}))

def hierarchy(+classes: +List<M.LoadedClass>, source: U32, target: U32) -> Bool:
  +count = M.length(M.LoadedClass, classes)
  ancestry(U32.to_nat(U32.add(U32.mul(count, U32.add(count, 1)), 1)), classes, Con{source, Nil{}}, target, Nil{})

def object_descriptor(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{59}, tail}:
      ""
    case SCon{h, tail}:
      SCon{h, object_descriptor(tail)}

def descriptor_assignable(source: String, target: String, +classes: +List<M.LoadedClass>, +symbols: +List<String>) -> Bool:
  match source target:
    case SCon{Chr{91}, a} SCon{Chr{91}, b}:
      descriptor_assignable(a, b, classes, symbols)
    case SCon{Chr{76}, a} SCon{Chr{76}, b}:
      hierarchy(classes, named_class(classes, symbols, object_descriptor(a)), named_class(classes, symbols, object_descriptor(b)))
    case SCon{Chr{91}, a} SCon{Chr{76}, b}:
      +name = object_descriptor(b)
      Bool.or(String.eq(name, "java/lang/Object"), Bool.or(String.eq(name, "java/lang/Cloneable"), String.eq(name, "java/io/Serializable")))
    case a b:
      String.eq(a, b)

def array_assignable(source: String, target: String, classes: +List<M.LoadedClass>, symbols: +List<String>) -> Bool:
  match source target:
    case SCon{Chr{91}, a} SCon{Chr{91}, b}:
      descriptor_assignable(a, b, classes, symbols)
    case _ _:
      False{}


def class_symbol(class: Maybe<&2, M.LoadedClass>) -> U32:
  match class:
    case None{}:
      4294967295
    case Some{M.LoadedClass{id, class_name, parent, interfaces, fields, methods, initializer, state}}:
      class_name

def assignable(+classes: +List<M.LoadedClass>, +symbols: +List<String>, +source: U32, +target: U32) -> Bool:
  Bool.or(hierarchy(classes, source, target), array_assignable(name_value(M.nth(String, symbols, class_symbol(M.nth(M.LoadedClass, classes, source)))), name_value(M.nth(String, symbols, class_symbol(M.nth(M.LoadedClass, classes, target)))), classes, symbols))

def entry_class(entry: M.HeapEntry) -> U32:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  class

def object_entry(class: U32, fields: +List<M.Binding>) -> M.HeapEntry:
  M.HeapEntry{class, 0, 0, fields, Nil{}, Nil{}}

def primitive_array_entry(class: U32, element: U32, values: +List<M.Slot>) -> M.HeapEntry:
  M.HeapEntry{class, 1, element, Nil{}, values, Nil{}}

def reference_array_entry(class: U32, element: U32, values: +List<M.Slot>) -> M.HeapEntry:
  M.HeapEntry{class, 2, element, Nil{}, values, Nil{}}

def string_entry(class: U32, chars: +List<U32>) -> M.HeapEntry:
  M.HeapEntry{class, 3, 0, Nil{}, Nil{}, chars}

def units_equal(left: +List<U32>, right: +List<U32>) -> Bool:
  match left right:
    case Nil{} Nil{}:
      True{}
    case Con{a, at} Con{b, bt}:
      Bool.and(U32.is_eq(a, b), units_equal(at, bt))
    case _ _:
      False{}

def string_intern_scan(entries: +List<M.HeapEntry>, +chars: +List<U32>, +reference: U32) -> Maybe<&2, U32>:
  match entries:
    case Nil{}:
      None{}
    case Con{entry, rest}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, values, +entry_chars}:
          Bool.pick(Maybe<&2, U32>, U32.is_eq(kind, 3) && units_equal(entry_chars, chars), Some{reference}, string_intern_scan(rest, chars, (reference + 1 : U32)))

def string_intern(+heap: +List<M.HeapEntry>, +chars: +List<U32>) -> Maybe<&2, U32>:
  string_intern_scan(heap, chars, 1)
def byte_slots(bytes: +List<U32>) -> +List<M.Slot>:
  match bytes:
    case Nil{}: Nil{}
    case Con{byte, rest}: Con{M.Slot{1, U32.and(byte, 255)}, byte_slots(rest)}

def stream_entry(class: U32, bytes: +List<U32>) -> M.HeapEntry:
  M.HeapEntry{class, 4, 0, [M.Binding{0, M.Slot{1, 0}}], byte_slots(bytes), Nil{}}

def stream_closed_found(found: Maybe<&2, M.Slot>) -> Bool:
  match found:
    case None{}: False{}
    case Some{M.Slot{tag, bits}}: U32.is_ne(bits, 0)

def stream_closed(fields: +List<M.Binding>) -> Bool:
  stream_closed_found(binding_find(fields, 0))
