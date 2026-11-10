import Base
import ../model.bend as M
import ./trie.bend as T

# The pure heart of the collector: follow tag-3 slots from a seed list and sweep
# the heap. It imports only safe modules so LAWS.bend can check it by computation.
# heap/gc.bend supplies the VM's root enumeration and the host-handle policy.

def free_kind() -> U32:
  255

def free_entry() -> M.HeapEntry:
  M.HeapEntry{0, free_kind(), 0, Nil{}, Nil{}, Nil{}}

type Entries is Data:
  EntriesEmpty{}
  EntriesLeaf{key: U32, entry: M.HeapEntry}
  EntriesNode{zero: Entries, one: Entries}

def entries_set(fuel: Nat, +t: Entries, +depth: Nat, +path: U32, +key: U32, +entry: M.HeapEntry) -> Entries:
  match fuel:
    case 0n: t
    case 1n+ +p:
      match t:
        case EntriesEmpty{}: EntriesLeaf{key, entry}
        case EntriesLeaf{+k, +old}: entries_set(p, entries_set(p, EntriesNode{EntriesEmpty{}, EntriesEmpty{}}, depth, U32.shrn(k, depth), k, old), depth, path, key, entry)
        case EntriesNode{+zero, +one}:
          +low : Bool = U32.is_eq(U32.and(path, 1), 0)
          +updated : Entries = entries_set(p, Bool.pick(Entries, low, zero, one), 1n+depth, U32.shr(path), key, entry)
          EntriesNode{Bool.pick(Entries, low, updated, zero), Bool.pick(Entries, low, one, updated)}

def entries_get(fuel: Nat, +t: Entries, +path: U32, +key: U32) -> Maybe<&2, M.HeapEntry>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      match t:
        case EntriesEmpty{}: None{}
        case EntriesLeaf{k, entry}: Bool.pick(Maybe<&2, M.HeapEntry>, U32.is_eq(k, key), Some{entry}, None{})
        case EntriesNode{+zero, +one}: entries_get(p, Bool.pick(Entries, U32.is_eq(U32.and(path, 1), 0), zero, one), U32.shr(path), key)

def entries_build(heap: +List<M.HeapEntry>, +reference: U32, +tree: Entries) -> Entries:
  match heap:
    case Nil{}: tree
    case Con{+entry, rest}: entries_build(rest, U32.add(reference, 1), entries_set(T.fuel(), tree, 0n, reference, reference, entry))

# ---- Outgoing references ------------------------------------------------------

def add_ref(+reference: U32, +acc: +List<U32>) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_eq(reference, 0), acc, Con{reference, acc})

def slot_ref(value: M.Slot, +acc: +List<U32>) -> +List<U32>:
  match value:
    case M.Slot{+tag, +bits}: Bool.pick(+List<U32>, U32.is_eq(tag, 3), add_ref(bits, acc), acc)
    case M.Wide{tag, high, low}: acc
    case M.Unusable{}: acc

def slots_refs(values: +List<M.Slot>, +acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: acc
    case Con{value, rest}: slots_refs(rest, slot_ref(value, acc))

def bindings_refs(values: +List<M.Binding>, +acc: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: acc
    case Con{M.Binding{id, value}, rest}: bindings_refs(rest, slot_ref(value, acc))

def entry_refs(entry: Maybe<&2, M.HeapEntry>, +acc: +List<U32>) -> +List<U32>:
  match entry:
    case None{}: acc
    case Some{M.HeapEntry{class, kind, element, fields, values, chars}}: slots_refs(values, bindings_refs(fields, acc))

# ---- Mark ---------------------------------------------------------------------

type Mark is Data:
  Mark{seen: M.Trie, work: +List<U32>}

def mark_add(fresh: Bool, +seen: M.Trie, +work: +List<U32>, +reference: U32) -> Mark:
  match fresh:
    case True{}: Mark{T.set(seen, reference, 1), Con{reference, work}}
    case False{}: Mark{seen, work}

def mark_one(+mark: Mark, +spine: U32, +reference: U32) -> Mark:
  match mark:
    case Mark{+seen, work}: mark_add(U32.is_le(reference, spine) && U32.is_eq(T.get(seen, reference), 0), seen, work, reference)

# Marking at push time keeps each object on the worklist at most once, cycles included.
def mark_all(refs: +List<U32>, +spine: U32, +mark: Mark) -> Mark:
  match refs:
    case Nil{}: mark
    case Con{reference, rest}: mark_all(rest, spine, mark_one(mark, spine, reference))

# Each object enters the worklist at most once, so `fuel` (the heap length plus one)
# always suffices; running out means the walk is broken and the VM fails.
def mark_loop(fuel: Nat, +tree: Entries, +spine: U32, +mark: Mark) -> Maybe<&2, M.Trie>:
  match fuel:
    case 0n: None{}
    case 1n+p:
      match mark:
        case Mark{+seen, work}:
          match work:
            case Nil{}: Some{seen}
            case Con{+reference, rest}: mark_loop(p, tree, spine, mark_all(entry_refs(entries_get(T.fuel(), tree, reference, reference), Nil{}), spine, Mark{seen, rest}))

# ---- Host handles of swept owners ----------------------------------------------

# Field ids of the int `handle` and boolean `closed` of a Java-source socket class.
type Owner is Data:
  Owner{handle: U32, closed: U32}

def binding_find(xs: +List<M.Binding>, +id: U32) -> Maybe<&2, M.Slot>:
  match xs:
    case Nil{}: None{}
    case Con{M.Binding{binding_id, value}, rest}: Bool.pick(Maybe<&2, M.Slot>, U32.is_eq(binding_id, id), Some{value}, binding_find(rest, id))

def binding_bits(found: Maybe<&2, M.Slot>) -> U32:
  match found:
    case None{}: 0
    case Some{value}: M.slot_bits(value)

def has_binding(found: Maybe<&2, M.Slot>) -> Bool:
  match found:
    case None{}: False{}
    case Some{value}: True{}

def owned_handle(+fields: +List<M.Binding>, +handle: U32, +closed: U32) -> U32:
  Bool.pick(U32, U32.is_eq(binding_bits(binding_find(fields, closed)), 0), binding_bits(binding_find(fields, handle)), 0)

# A swept socket's handle, or 0. Binding ids are field ids, so a subclass such as
# SSLSocket answers through the field it inherited.
def socket_handle(owners: +List<Owner>, +fields: +List<M.Binding>) -> U32:
  match owners:
    case Nil{}: 0
    case Con{Owner{+handle, +closed}, rest}:
      Bool.pick(U32, has_binding(binding_find(fields, handle)), owned_handle(fields, handle, closed), socket_handle(rest, fields))

# A file stream is tagged with element 1 when the runner opens it (closed flag in
# binding 0, handle in binding 1). Sockets are Java-source and found by field id.
def dead_handle(entry: M.HeapEntry, +owners: +List<Owner>) -> U32:
  match entry:
    case M.HeapEntry{class, +kind, +element, +fields, values, chars}:
      Bool.pick(U32, U32.is_ne(kind, 0), 0, Bool.pick(U32, U32.is_eq(element, 1), owned_handle(fields, 1, 0), socket_handle(owners, fields)))

# ---- Sweep ---------------------------------------------------------------------

# `kept` and `free` are built low index first, consed, so both end up reversed.
type Swept is Data:
  Swept{kept: +List<M.HeapEntry>, free: +List<U32>, live: U32, closes: +List<U32>}

def sweep_dead(+handle: U32, +reference: U32, +swept: Swept) -> Swept:
  match swept:
    case Swept{kept, free, live, closes}: Swept{Con{free_entry(), kept}, Con{reference, free}, live, add_ref(handle, closes)}

def sweep_live(entry: M.HeapEntry, +swept: Swept) -> Swept:
  match swept:
    case Swept{kept, free, +live, closes}: Swept{Con{entry, kept}, free, U32.add(live, 1), closes}

def sweep_entry(marked: Bool, entry: M.HeapEntry, +owners: +List<Owner>, +reference: U32, +swept: Swept) -> Swept:
  match marked:
    case True{}: sweep_live(entry, swept)
    case False{}: sweep_dead(dead_handle(entry, owners), reference, swept)

# `owners` names the socket fields that may hold a host handle for dead objects.
def sweep_go(heap: +List<M.HeapEntry>, +reference: U32, +seen: M.Trie, +owners: +List<Owner>, +swept: Swept) -> Swept:
  match heap:
    case Nil{}: swept
    case Con{entry, rest}: sweep_go(rest, U32.add(reference, 1), seen, owners, sweep_entry(U32.is_ne(T.get(seen, reference), 0), entry, owners, reference, swept))

def empty_swept(+closes: +List<U32>) -> Swept:
  Swept{Nil{}, Nil{}, 0, closes}

def reclaim_marked(found: Maybe<&2, M.Trie>, +heap: +List<M.HeapEntry>) -> Maybe<&2, Swept>:
  match found:
    case None{}: None{}
    case Some{+seen}: Some{sweep_go(heap, 1, seen, Nil{}, empty_swept(Nil{}))}

def mark_heap(+heap: +List<M.HeapEntry>, +seeds: +List<U32>, +spine: U32) -> Maybe<&2, M.Trie>:
  mark_loop(1n+U32.to_nat(spine), entries_build(heap, 1, EntriesEmpty{}), spine, mark_all(seeds, spine, Mark{M.TrieEmpty{}, Nil{}}))

# Mark from `seeds`, then sweep. The law in LAWS.bend checks this on a small heap.
def reclaim(+heap: +List<M.HeapEntry>, +seeds: +List<U32>) -> Maybe<&2, Swept>:
  reclaim_marked(mark_heap(heap, seeds, M.length(M.HeapEntry, heap)), heap)

def swept_free(found: Maybe<&2, Swept>) -> +List<U32>:
  match found:
    case None{}: Nil{}
    case Some{Swept{kept, free, live, closes}}: M.reverse(U32, free)

def swept_kept(found: Maybe<&2, Swept>) -> +List<M.HeapEntry>:
  match found:
    case None{}: Nil{}
    case Some{Swept{kept, free, live, closes}}: M.reverse(M.HeapEntry, kept)
