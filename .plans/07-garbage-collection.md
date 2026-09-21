# Plan: Mark-and-sweep garbage collection

Status: planned; no collector is implemented.
Source: `bendjvm-spec.md` sections 64, 65, and 76, and Phase 10.
Depends on the current heap in milestone 2.
Later plans that add roots: [bytecode](04-broader-jvm-bytecode-support.md) and [concurrency](05-concurrency-and-native-integration.md).
`ROADMAP.md` does not list this work.

## Goal

Reclaim unreachable JVM objects inside the Bend-owned heap so a program can keep allocating after dropping references, without changing Java reference identity.

`--max-heap` stays a limit on live entries.
When an allocation does not fit, the VM marks from an explicit root set, sweeps everything unmarked into reusable slots, and retries that allocation once.
If the live set still does not fit, the VM throws the reserved `OutOfMemoryError`.

The collector is ordinary Bend data, as section 65 requires.
It does not call a host GC library and it does not scan raw words.

## What exists today

Section 64 still describes the heap that is running.
`heap/heap.bend:allocate` appends one `HeapEntry` and fails with `OutOfMemoryError` when `length(heap) >= maxHeap`.
Nothing frees a slot.
`README.md` lists garbage collection as unsupported, and `.plans/` has no GC plan.

References are 1-based indexes into `VM.heap`.
Reference 0 is null.
`get` reads `heap[reference - 1]`.
`put` replaces that same index.
Java `==` is equality of that `U32`.

Bootstrap (`loader/class_loader.bend:bootstrap_heap`) occupies the first two slots before `main` runs:

| Reference | Entry | Why it must stay |
| --- | --- | --- |
| 1 | `java/io/PrintStream` | `System.out` is patched to `Slot{3, 1}` |
| 2 | `java/lang/OutOfMemoryError` | `runtime/execute.bend:allocate_named_result` does `with_exception(vm, 2)` when a throwable cannot be allocated |

`scripts/test.py` already checks the monotonic limit.
`HeapLimit` retains 100 objects plus one array, so `--max-heap 16` throws and `--max-heap 256` prints `100`.
Those two runs must keep doing that after collection exists.
A retained set that does not fit is still an error.

Slot tag 3 is a reference (`classfile/descriptor.bend:slot_tag`).
Tags 0, 1, and 2 are primitives.
Host handles, sizes, and modCounts are tag 1 and are not pointers.

Heap kinds in `model.bend`, plus kind 8 which the comment omits:

| Kind | Payload | Outgoing references |
| --- | --- | --- |
| 0 object | `fields` | bindings whose slot tag is 3 |
| 1 primitive array | `values` | none |
| 2 reference array | `values` | slots whose tag is 3 |
| 3 UTF-16 string | `chars` | none |
| 4 byte stream | byte `values`, closed flag in field 0 | none |
| 5 ArrayList | element slots, size in `element` | tag-3 slots in `values` |
| 6 HashMap | key/value slots, size in `element` | tag-3 slots in `values` |
| 7 StringBuilder | `chars` | none |
| 8 Class mirror | represented class id in `element` | none |

File and socket objects are kind 0.
Field 0 is the closed flag, field 1 is the host handle, field 2 is a timeout or port.
Reader and writer wrappers are also kind 0.
Their field 0 is the inner stream (tag 3) and field 1 is the closed flag.
An iterator's field 0 is its list.
Throwable fields 0, 1, and 2 are message, cause, and the suppressed array.

There is no free list, no mark bit, and no intern table.
Three scans walk the whole heap and treat the first match as canonical:

- `heap.bend:string_intern`, used by `execute.bend:literal_string` and by `library.bend:intern_or_alloc`.
- `heap.bend:integer_intern`, used by `Integer.valueOf` for `-128..127`.
- `heap.bend:class_mirror`, used by `ldc` of a class and by `Object.getClass`.

`intern_or_alloc` also serves `substring`, `concat`, `StringBuilder.toString`, `String.valueOf`, `Integer.toString`, and `Throwable.toString`.
Those results are reused whenever any equal string is still sitting in the list.
That is an accident of the append-only heap.
Java does not intern them.
`String.intern` is not a registered native.

`LAWS.bend` only has `nat_add_zero`.
Section 76's reference law is not proved.

## Decisions

### Stable slots, mark-and-sweep

Sweep clears a dead entry in place and records its index.
The next allocation pops that index and writes the new entry there.
Live references keep their old numbers, so `==` does not change across a collection.

A free entry uses a dedicated kind, recorded next to the kind comment in `model.bend`.
Its `fields`, `values`, and `chars` are empty.
Bend can then drop those lists.
A tombstone that still held the old payload would not release it.

`get` on a free slot fails with `InvalidReference`.
A dangling index must not silently alias the next object that reuses the slot.

Sweep walks from the high index downward and conses free indexes, so the free-list head is the lowest free index.
Reuse order is defined.

The mark phase is an explicit worklist.
A mark bit, one boolean per current heap slot, stops a cycle from being pushed twice.
List/iterator pairs, throwable cause links, and mutual fields are normal cycles.
Each object is pushed at most once, and the walk is capped at the heap length.
Hitting the cap fails the VM instead of looping.

The first implementation is a sequential worklist.
Edge lists of distinct objects can later be traced in parallel only if the mark union is deterministic and the free list is still filled in ascending index order.
Collection order is part of the test contract.

### One roots record on the VM

Add one `Roots` value to `VM` rather than several parallel fields.
It holds:

- the free list
- the reserved `OutOfMemoryError` reference, initialized to 2
- the string-literal table
- the `Integer` cache for `-128..127`
- the class-mirror table
- host handles whose Java owners were swept and still need `CloseHandle`

`allocate_named_result` reads the reserved reference from `Roots`.
The literal `2` does not stay copied at the call site.

Every `VM{...}` construct and destructure, including `runtime/state.bend`, has to take the new field in the same change.

### Occupancy is the live entry count

`--max-heap N` limits live entries, not the length of the spine.
Live count is `length(heap) - length(free list)`.
Bootstrap objects, the reserved error, interned literals, cached integers, and materialized `Class` mirrors all count.

Allocation order:

1. Pop a free index and `put` the new entry, if the free list is non-empty.
2. Append, if `length(heap) < maxHeap`.
3. Collect once, then retry from step 1.
4. Fail with `OutOfMemoryError` if the live set still does not fit.

Step 3 runs at most once per allocation.
The collector allocates no JVM objects.
Its bitmap and worklist are Bend lists.
A nested collection is a bug.

`HeapLimit` at 16 and 256 is unchanged because those objects stay reachable from the local array.

### Roots

A reference slot counts only when its tag is 3 and its bits are non-zero.
Null is not a root.
Primitive slots are not roots, including future long/double halves from plan 04, as long as those halves do not use tag 3.

The mark seeds are:

- every local and operand-stack slot of every frame
- every static binding
- `VM.exception` while it is non-zero
- `VM.result` when it is a non-null reference
- `Roots` itself: reserved error, literal table, integer cache, class-mirror table
- each `Host.cont` payload: `NeedHash` map and key, `NeedEq` map and key, `NeedToString` extra, `NeedEquals` left and right, `NeedListEq` list and query, plus `extra` when that continuation stores a `Slot` of tag 3
- the `receiver` on a pending `OpenFile`, `ConnectTcp`, `BindTcp`, or `AcceptTcp`

`ReadBytes`, `WriteBytes`, and `CloseHandle` carry host handles, not heap references.
Classpath `Resource` bytes, the symbol table, loaded method bodies, and `VM.output` are not heap roots.
`output` already holds Bend strings copied out of the JVM.

From a marked entry, follow only the outgoing references in the kind table above.
Trace every physically stored tag-3 slot, including slots a collection might have left past its logical size.
A stale slot past `size` is still a root until the write that removes it clears the slot.
`list_remove` and `list_clear` already drop or replace slots, so those paths do not leave a tail.

Class ids, field ids, and the `element` of a Class mirror are not followed.

### Literal identity has an explicit table

The heap scan stops being the intern pool.
A dead string must not be rediscovered, and a string that the program dropped must not stay canonical by lingering in the spine.

The literal table maps UTF-16 contents to one heap reference.
`execute.bend:literal_string` looks up and inserts there.
Equal literals share one object for the run, including `"same" == "same"` in `StringConstant.java` after a collection between the two loads.
The table is a root, so a literal stays live after the program drops its last local.

`substring`, `concat`, `StringBuilder.toString`, `String.valueOf`, `Integer.toString`, and `Throwable.toString` allocate a fresh string.
They stop calling `intern_or_alloc`.
Existing fixtures print those values or compare them with `equals`.
They do not require `==` on derived strings.

Add `String.intern()Ljava/lang/String;` as one native.
It inserts the receiver into the same table and returns the canonical reference.
That is the whole public intern operation.
No other `String` overloads come with it.

`Integer.valueOf` for `-128..127` reads and fills a 256-slot cache on `Roots`.
The first call allocates.
Later calls return that same reference, which is what `ObjectStringInteger.java` checks with `x == y`.
Values outside the range allocate a new `Integer` every time.
The collector does not search the heap for an integer with matching bits.

The first `Class` mirror for a loaded class is stored in the mirror table, keyed by class id.
`ldc` of a class and `Object.getClass` use that table.
`obj.getClass() == String.class` still holds after both references have been dropped and a collection has run.
The mirror's `element` field stays a class id.

### Swept host handles are closed by the runner

Sweep of an unmarked file, socket, or server socket with a non-zero handle and a clear closed flag appends that handle to `Roots` and does not run Java code.
No `finalize`, `Cleaner`, or resurrection.
Wrapper objects do not own the handle.
Their inner stream is a tag-3 field, so it is swept on its own and closed once.

Memory streams (kind 4) have no host handle.
Closing them is only a flag on a live object.

`scripts/run.py` owns the handles in the generated host, and `closeAll` runs at process exit.
Drain the pending-close list with the same close path whenever that host receives the VM back: the next effect boundary, and the final return.
A collection during straight-line bytecode can sit until that return.
The process-exit sweep still closes anything left.

### Safe point

The only safe point in this milestone is `allocate`, before it reports `OutOfMemoryError`.
Frames, statics, the pending effect, and continuations are complete at that point.
No instruction handler needs its own collection call.

Plan 05's scheduler must collect only at a safe point where every thread's frames and parked continuations are visible, on the single shared heap.
This milestone does not add threads.
The root walk takes a list of frames so a later thread list can pass every stack into the same function.

Plan 03's reflective field access uses the same slots and bindings.
New caches in that plan belong in `Roots` or on a reached object.
They must not be a side table the marker never sees.

## Work sequence

1. Add `Roots`, the free kind, and free-list allocation.
   `get` rejects a free slot.
   Live count replaces the length check in `allocate`.
   No object is freed yet, so current programs behave as they do today.
   Point the OOM failure path at `Roots.oom`.
2. Add the literal table, integer cache, and class-mirror table.
   Switch `literal_string`, `Integer.valueOf`, and class `ldc` / `getClass` over to them.
   Allocate fresh strings at the former `intern_or_alloc` call sites.
   Register `String.intern`.
3. Implement mark and sweep as pure VM-to-VM functions in `bendjvm/heap/`.
   Call them from `allocate` when neither the free list nor the spine has room.
   Sweep writes empty free entries and pushes indexes.
4. Record swept host handles and drain them in the generated runner in `scripts/run.py`.
5. Add the fixtures and the Bend law below.
   Update the `--max-heap` wording in `README.md` so it says live entries, and says collection runs when an allocation would exceed the limit.
   Add this milestone to `ROADMAP.md`.
   In spec section 64, say the monotonic heap was the pre-GC milestone and point at this plan.

## Tests and proofs

Keep the current suite green, including `HeapLimit` at 16 and 256, `StringConstant`, and `ObjectStringInteger`.
Run `python3 scripts/test.py` and `bend PROOF.bend` before calling the work done.

Add Java fixtures under `bendjvm/tests/fixtures/`:

- A loop that allocates many objects, keeps one, and finishes under a `--max-heap` smaller than the number of allocations.
  The retained object's fields are still readable.
- Two objects that point at each other, then become unreachable, then the same tight heap accepts further allocation.
- `"same" == "same"`, `Integer.valueOf(40) == Integer.valueOf(40)`, and `String.class == String.class` after enough garbage to force a collection.
- `String.intern` returns one object for equal receivers, and a string built by `concat` or `StringBuilder.toString` is collectable when the program keeps no reference to it.
- A dropped `FileInputStream` produces a pending close that the runner applies before process-exit `closeAll`.
  The assertion has to tell that close apart from the final sweep.

Add one Bend law over a hand-built three-object heap: one root, one object reached by a field, one object reached only by a cycle that the root does not touch.
After collection the root and the reached object are the same entries, and the third slot is free.
A follow-up allocation reuses that index.
This is the section 76 check for the collector.
It is not a proof of the general graph walk.

## Out of scope

- Moving or compacting collection.
- Reference counting.
- Generational collection, write barriers, and JIT stack maps.
- `System.gc`.
  Tests force a collection by filling `--max-heap`.
- Soft, weak, and phantom references.
- User finalizers and `java.lang.ref.Cleaner`.
- Scanning every `U32` in the VM.
- Counting classpath resources or Bend symbol strings against `--max-heap`.
- A host-side collector.
- Running this ahead of plans 03 through 06.
  Those plans must add their new roots when they land.
