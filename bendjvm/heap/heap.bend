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

def binding_replace(xs: +List<M.Binding>, +id: U32, +value: M.Slot) -> +List<M.Binding>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{M.Binding{+binding_id, old}, rest}:
      Con{M.Binding{binding_id, Bool.pick(M.Slot, U32.is_eq(binding_id, id), value, old)}, binding_replace(rest, id, value)}

def binding_has(xs: +List<M.Binding>, +id: U32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{M.Binding{+binding_id, old}, rest}: U32.is_eq(binding_id, id) || binding_has(rest, id)

def binding_upsert(has: Bool, +xs: +List<M.Binding>, +id: U32, +value: M.Slot) -> +List<M.Binding>:
  match has:
    case True{}: binding_replace(xs, id, value)
    case False{}: M.append(M.Binding, xs, [M.Binding{id, value}])

# Writes a binding, adding it when absent; a write is never silently dropped.
def binding_set(+xs: +List<M.Binding>, +id: U32, +value: M.Slot) -> +List<M.Binding>:
  binding_upsert(binding_has(xs, id), xs, id, value)

def get_nonnull(heap: +List<M.HeapEntry>, reference: U32, null: Bool) -> Result<&2, &2, String, M.HeapEntry>:
  match null:
    case True{}:
      Fail{"java/lang/NullPointerException"}
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
    case Con{M.LoadedClass{class_id, class_name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods}, rest}:
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
    case Some{M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods}}:
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

@unsafe def ancestry_hit(hit: Bool, fuel: Nat, +classes: +List<M.LoadedClass>, +id: U32, rest: +List<U32>, +target: U32, +visited: +List<U32>) -> Bool:
  match hit:
    case True{}:
      True{}
    case False{}:
      ancestry(fuel, classes, ancestry_next(classes, id, rest, visited, contains(visited, id)), target, Con{id, visited})

# Generated JavaScript evaluates Bool.or eagerly, so the match in ancestry_hit is
# what stops the walk at the first hit.
@unsafe def ancestry(fuel: Nat, +classes: +List<M.LoadedClass>, frontier: +List<U32>, +target: U32, +visited: +List<U32>) -> Bool:
  match fuel frontier:
    case 0n _:
      False{}
    case 1n+p Nil{}:
      False{}
    case 1n+p Con{+id, rest}:
      ancestry_hit(U32.is_eq(id, target), p, classes, id, rest, target, visited)

def hierarchy(+classes: +List<M.LoadedClass>, source: U32, target: U32) -> Bool:
  +count = M.length(M.LoadedClass, classes)
  ancestry(U32.to_nat(U32.add(U32.mul(count, U32.add(count, 1)), 1)), classes, Con{source, Nil{}}, target, Nil{})

@unsafe def declared_field(+fields: +List<M.LoadedField>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedField>:
  match fields:
    case Nil{}:
      None{}
    case Con{+field, rest}:
      declared_field_match(U32.is_eq(M.loaded_field_owner(field), owner) && U32.is_eq(M.loaded_field_name(field), name) && U32.is_eq(M.loaded_field_descriptor(field), descriptor), field, rest, owner, name, descriptor)

@unsafe def declared_field_match(hit: Bool, +field: M.LoadedField, +rest: +List<M.LoadedField>, +owner: U32, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedField>:
  match hit:
    case True{}:
      Some{field}
    case False{}:
      declared_field(rest, owner, name, descriptor)

# JVMS 5.4.3.2 search order after the class itself: direct superinterfaces
# (each followed by its own superinterfaces), then the superclass chain.
def parent_then(parent: U32, rest: +List<U32>) -> +List<U32>:
  match parent:
    case 4294967295:
      rest
    case value:
      Con{value, rest}

def field_lookup_supers(class: Maybe<&2, M.LoadedClass>, rest: +List<U32>) -> +List<U32>:
  match class:
    case None{}:
      rest
    case Some{M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods}}:
      M.append(U32, interfaces, parent_then(parent, rest))

@unsafe def resolve_field_found(found: Maybe<&2, M.LoadedField>, fuel: Nat, +classes: +List<M.LoadedClass>, +fields: +List<M.LoadedField>, +id: U32, +rest: +List<U32>, +visited: +List<U32>, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedField>:
  match found:
    case Some{field}:
      Some{field}
    case None{}:
      resolve_field_go(fuel, classes, fields, field_lookup_supers(M.nth(M.LoadedClass, classes, id), rest), Con{id, visited}, name, descriptor)

@unsafe def resolve_field_visit(seen: Bool, fuel: Nat, +classes: +List<M.LoadedClass>, +fields: +List<M.LoadedField>, +id: U32, +rest: +List<U32>, +visited: +List<U32>, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedField>:
  match seen:
    case True{}:
      resolve_field_go(fuel, classes, fields, rest, visited, name, descriptor)
    case False{}:
      resolve_field_found(declared_field(fields, id, name, descriptor), fuel, classes, fields, id, rest, visited, name, descriptor)

# Interfaces reached twice through a diamond are searched once.
@unsafe def resolve_field_go(fuel: Nat, +classes: +List<M.LoadedClass>, +fields: +List<M.LoadedField>, +queue: +List<U32>, +visited: +List<U32>, +name: U32, +descriptor: U32) -> Maybe<&2, M.LoadedField>:
  match fuel queue:
    case 0n _:
      None{}
    case 1n+p Nil{}:
      None{}
    case 1n+p Con{+id, rest}:
      resolve_field_visit(contains(visited, id), p, classes, fields, id, rest, visited, name, descriptor)

# Field resolution (JVMS 5.4.3.2) starting at class id `owner`; the result's
# owner is the declaring class, which is the one a static access initializes.
def resolve_field(+classes: +List<M.LoadedClass>, +fields: +List<M.LoadedField>, owner: U32, name: U32, descriptor: U32) -> Maybe<&2, M.LoadedField>:
  +count = M.length(M.LoadedClass, classes)
  resolve_field_go(U32.to_nat(U32.add(U32.mul(count, U32.add(count, 1)), 1)), classes, fields, Con{owner, Nil{}}, Nil{}, name, descriptor)

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
    case Some{M.LoadedClass{id, class_name, parent, interfaces, fields, methods, initializer, state, bootstrapMethods}}:
      class_name

def assignable(+classes: +List<M.LoadedClass>, +symbols: +List<String>, +source: U32, +target: U32) -> Bool:
  Bool.or(hierarchy(classes, source, target), array_assignable(name_value(M.nth(String, symbols, class_symbol(M.nth(M.LoadedClass, classes, source)))), name_value(M.nth(String, symbols, class_symbol(M.nth(M.LoadedClass, classes, target)))), classes, symbols))

def entry_class(entry: M.HeapEntry) -> U32:
  M.HeapEntry{class, kind, element, fields, values, chars} = entry
  class

# HeapEntry.kind registry. Dispatch, reflection, and intrinsics branch on the
# kind alone, so every value must stay unique across modules:
#   0 object or throwable    1 primitive array        2 reference array
#   3 String                  4 byte stream            5 ArrayList
#   6 HashMap                 7 StringBuilder          8 Class mirror
#   9 annotation instance    10 dynamic proxy         11 pending annotation value
#   20-24 java.lang.invoke objects, named below.
def kind_method_type() -> U32:
  20

def kind_method_handle() -> U32:
  21

def kind_call_site() -> U32:
  22

def kind_lookup() -> U32:
  23

def kind_lambda_plan() -> U32:
  24

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
def class_mirror_scan(entries: +List<M.HeapEntry>, +target: U32, +reference: U32) -> Maybe<&2, U32>:
  match entries:
    case Nil{}:
      None{}
    case Con{+entry, rest}:
      match entry:
        case M.HeapEntry{class, kind, element, fields, values, chars}:
          Bool.pick(Maybe<&2, U32>, U32.is_eq(kind, 8) && U32.is_eq(element, target), Some{reference}, class_mirror_scan(rest, target, (reference + 1 : U32)))

def class_mirror(heap: +List<M.HeapEntry>, +target: U32) -> Maybe<&2, U32>:
  class_mirror_scan(heap, target, 1)

def class_mirror_entry(mirror_class: U32, target: U32) -> M.HeapEntry:
  M.HeapEntry{mirror_class, 8, target, Nil{}, Nil{}, Nil{}}

def byte_slots(bytes: +List<U32>) -> +List<M.Slot>:
  match bytes:
    case Nil{}: Nil{}
    case Con{byte, rest}: Con{M.Slot{1, U32.and(byte, 255)}, byte_slots(rest)}

def stream_entry(class: U32, bytes: +List<U32>) -> M.HeapEntry:
  M.HeapEntry{class, 4, 0, [M.Binding{0, M.Slot{1, 0}}], byte_slots(bytes), Nil{}}

def stream_closed_found(found: Maybe<&2, M.Slot>) -> Bool:
  match found:
    case None{}: False{}
    case Some{slot}: U32.is_ne(M.slot_bits(slot), 0)

def stream_closed(fields: +List<M.Binding>) -> Bool:
  stream_closed_found(binding_find(fields, 0))

def throwable_entry(class: U32) -> M.HeapEntry:
  M.HeapEntry{class, 0, 0, [M.Binding{0, M.Slot{3, 0}}, M.Binding{1, M.Slot{3, 0}}, M.Binding{2, M.Slot{3, 0}}, M.Binding{3, M.Slot{1, 0}}], Nil{}, Nil{}}

def builder_entry(class: U32, chars: +List<U32>) -> M.HeapEntry:
  M.HeapEntry{class, 7, 0, Nil{}, Nil{}, chars}

def list_entry(class: U32, values: +List<M.Slot>, size: U32, mod: U32) -> M.HeapEntry:
  M.HeapEntry{class, 5, size, [M.Binding{0, M.Slot{1, mod}}], values, Nil{}}

def map_entry(class: U32, values: +List<M.Slot>, size: U32, mod: U32) -> M.HeapEntry:
  M.HeapEntry{class, 6, size, [M.Binding{0, M.Slot{1, mod}}], values, Nil{}}

def slice_slots(xs: +List<M.Slot>, n: Nat) -> +List<M.Slot>:
  M.take(M.Slot, xs, n)

def drop_slots(xs: +List<M.Slot>, n: Nat) -> +List<M.Slot>:
  M.drop(M.Slot, xs, n)

def slice_chars(xs: +List<U32>, n: Nat) -> +List<U32>:
  M.take(U32, xs, n)

def drop_chars(xs: +List<U32>, n: Nat) -> +List<U32>:
  M.drop(U32, xs, n)

def integer_value_found(found: Maybe<&2, M.Slot>) -> U32:
  match found:
    case None{}: 0
    case Some{slot}: M.slot_bits(slot)

def integer_value(fields: +List<M.Binding>) -> U32:
  integer_value_found(binding_find(fields, 0))

def integer_intern_scan(entries: +List<M.HeapEntry>, +class: U32, +bits: U32, +reference: U32) -> Maybe<&2, U32>:
  match entries:
    case Nil{}: None{}
    case Con{entry, rest}:
      match entry:
        case M.HeapEntry{+cls, kind, element, +fields, values, chars}:
          Bool.pick(Maybe<&2, U32>, U32.is_eq(kind, 0) && U32.is_eq(cls, class) && U32.is_eq(integer_value(fields), bits), Some{reference}, integer_intern_scan(rest, class, bits, (reference + 1 : U32)))

def integer_intern(+heap: +List<M.HeapEntry>, class: U32, bits: U32) -> Maybe<&2, U32>:
  integer_intern_scan(heap, class, bits, 1)
