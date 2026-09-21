# Plan: Broader JVM bytecode support

Status: planned; no runtime changes implemented.
Source: `ROADMAP.md`, milestone 4.
Related plans: [loading](01-jar-and-classpath-loading.md), [runtime expansion](02-java-runtime-expansion.md), and [reflection/metadata](03-reflection-and-metadata.md).

## Goal

Execute Java 8 bytecode using long/double values, dense and sparse switches, and dynamically linked call sites, with a Bend-owned verifier that rejects invalid programs before execution. Carry the new value types through fields, arrays, calls, intrinsics, reflection, annotations, proxies, and host transport without truncation or divergent execution paths.

| Roadmap requirement | Deliverable |
| --- | --- |
| Implement `invokedynamic` | BootstrapMethods metadata, MethodType/MethodHandle constants, general bootstrap invocation, typed CallSite targets, cached linkage, and Java 8 lambda/method-reference support |
| Complete `long` and `double` support | Exact 64-bit representation, every long/double opcode and conversion, category-two frame/storage rules, binary64 arithmetic, and integration with the existing MiniJRE |
| Add switch instructions | `tableswitch` and `lookupswitch` decoding, target resolution, verification, execution, and diagnostics |
| Improve verifier coverage and compatibility | Java 8 stack-map/type/control-flow verification on all loading paths, including uninitialized objects, exception edges, wide values, switches, and dynamic calls |

Completeness means all four rows work together, not isolated opcode cases or a lambda-only shortcut.

## Current implementation and blockers

- `model.bend:Slot` stores one U32 payload with a tag. `runtime/frame.bend` permits tags 1–3, measures stack capacity by list length, stores locals one entry at a time, and implements stack permutations assuming every value is category one.
- `classfile/descriptor.bend:slots` knows that J/D occupy two JVM slots, but `slot_tag` maps most primitives to the integer tag and `parameter_count` counts values. Calling conventions must distinguish value count from JVM slot count.
- `classfile/constant_pool.bend` already retains long/double constants as two words in PairIndex records and reserves their second constant-pool slot. MethodHandle, MethodType, and InvokeDynamic tags receive some structural validation; this is not executable support.
- `loader/catalog.bend` explicitly rejects long/double fields. The verifier rejects category-two parameter/return descriptors. Literal linking handles category-one numeric/String values, not `ldc2_w` or dynamic invocation metadata.
- `bytecode/decode.bend` has no switch formats or opcode 186 format. Its `wide` path accepts only iinc. Branches are resolved from byte offsets to instruction indices through an existing boundary map; switch edges must reuse that map.
- `verifier/instruction.bend` provides per-instruction rules and local-index checks. Repository search found no import/call integrating that module into the existing loader/runtime path; do not assume these rules currently form an enforced verifier.
- `scripts/run.py:verify_code_stack` performs a separate Python height check. It defaults unknown instruction widths to one byte and returns early for unknown effects/truncated input. Runner parse exceptions can bypass the check. This cannot be the authority for new variable-width or category-two bytecode.
- `classfile/parser.bend` skips Code subattributes, including StackMapTable. BootstrapMethods is not currently decoded into a runtime linkage table.
- `bendjvm-spec.md` documents two-U32 long representation and unavailable U64/I64/F64 capabilities in its original Bend environment. Actual compiler capabilities must be checked at implementation time; do not infer IEEE binary64 behavior from a type name.
- The earlier plans specify new loading, callback, mirror, reflection, and proxy machinery but are not evidence those features exist. Reconcile implementation state before modifying shared records/APIs.

## Scope and compatibility boundary

- Keep class-file major version 52 as the supported target. Add complete long/double execution within this Java 8 VM, not automatic acceptance of newer class-file versions.
- `invokedynamic` is a general opcode with JVM bootstrap semantics. User bootstrap methods composed from the supported Java 8 API subset must execute in Bend; do not whitelist only LambdaMetafactory or inspect lambda fixture names.
- Include Java 8 LambdaMetafactory integration as a compatibility consumer of general dynamic linkage. Modern StringConcatFactory, constant-dynamic, module metadata, and newer class-file versions are separate work.
- Include all ordinary Java 8 `wide` load/store/iinc forms. Obsolete `jsr`/`ret`/`jsr_w`, invalid for the selected version's verifier, remain rejected. Do not add legacy subroutine analysis.
- Threads, monitors, synchronized methods, volatile-memory ordering across threads, JNI, JIT, and arbitrary OpenJDK library support remain outside this milestone. Supported-but-invalid bytecode and valid-but-unsupported features must produce distinct diagnostics.
- Do not claim sandbox-grade verification. Improve the selected Java 8 verifier contract with positive and adversarial evidence; document remaining unsupported JVM facilities.

## Representation and ownership decisions

### Values, stacks, locals, and storage

- Use a tagged Bend value representation with category-one payloads and two-word category-two payloads. Keep raw long/double bits as high/low U32 words; never transport a 64-bit integer through a JavaScript Number or round it through decimal floating point.
- Operand stacks contain logical values with explicit width: 1 for int/float/reference, 2 for long/double. Track consumed JVM slots without splitting a category-two value into independently manipulable operand values.
- Local arrays use JVM indices. A long/double occupies a value at index n and an unusable continuation at n+1. Writes overlapping either half invalidate the previous pair; loading a continuation or broken pair is invalid. Allow odd starting indices where bounds permit.
- max_stack/max_locals and descriptor limits count JVM slots, not value records. Method argument extraction counts values, then lays them into locals by widths plus the receiver. Interface operand counts include category-two widths and the receiver.
- Fields and array elements hold one typed logical value. Long/double array length counts elements, not words. Preserve raw bits through loads/stores, static ConstantValue initialization, default zero initialization, returns, and aliasing.
- Implement every legal `pop2`/`dup*` form and category constraint. `pop`, `dup`, `swap`, etc. cannot split/reorder half a category-two value. Keep verifier and runtime checks derived from the same documented shape rules.
- Migrate every Slot constructor/destructor and consumer: model, frames, heap, statics, descriptors, catalog, interpreter, intrinsics, API adapters, diagnostics, proofs, and the prior plans' reflection/proxy callbacks. No shadow 64-bit stack or legacy-value fallback.

### Long arithmetic

Implement in Bend over U32 limbs:

- Constants, loads/stores (normal/compact/wide), array loads/stores, return, arithmetic, comparison, shifts, bitwise operations, negation, and all conversions involving long.
- Addition/subtraction/multiplication wrap modulo 2^64. Multiplication uses bounded limb operations that do not lose carries through host number precision.
- Division truncates toward zero; remainder has the dividend's sign. Divide-by-zero throws ArithmeticException. MIN_VALUE / -1 yields MIN_VALUE and remainder zero without an overflow exception.
- Shift distances mask to six bits; arithmetic right shift propagates sign, logical right shift inserts zeros. `lcmp` compares signed values.
- `i2l` sign-extends; `l2i` retains low 32 bits. Float/double conversions use JVM rounding, NaN, overflow, and truncation rules, not a host integer cast.

### Double arithmetic and bit semantics

- Default implementation: a pure Bend binary64 module using fixed-width limbs and bounded wider intermediates for IEEE-754 operations. This preserves the repository's Bend-owned semantics rather than adding a host F64 service.
- Before coding, run `bend guide` and a small capability probe. A proven Bend-native F64 implementation can replace software primitives only if raw-bit transport and required semantics are verified on the actual generated backend. Otherwise retain the software design; no unresolved host-number fallback.
- Implement dconst, ldc2_w, all loads/stores/array accesses/return, dadd/dsub/dmul/ddiv/drem/dneg, dcmpg/dcmpl, and every int/long/float/double conversion.
- Use round-to-nearest ties-to-even where required, gradual underflow/subnormals, infinities, signed zeros, and NaN behavior. Double division by zero yields IEEE results, not ArithmeticException.
- JVM `drem` is truncating-remainder behavior, not IEEE remainder-to-nearest. Test finite/infinite operands, zero divisors, NaNs, signed zero, and remainder sign.
- dcmpg returns +1 for unordered comparisons; dcmpl returns -1. Floating-to-integer conversions truncate finite values, map NaN to zero, and saturate outside representable ranges. Do not assume host F32/F64 conversion reproduces every boundary.
- Preserve stored raw bits, including negative zero and transported NaN payloads. Arithmetic NaN payload choice is not generally a portable JVM equality oracle; compare the Java contract, canonicalized conversions, or NaN class as appropriate.
- Binary64 evaluation without extended-exponent intermediates is a valid Java 8 execution choice. Respect strictfp semantics and test against a reference JVM mode with comparable rounding behavior.
- Prove bit preservation and integer subroutines where practical. Do not label a few sample results as proof of a complete floating-point implementation.

## Required opcode and MiniJRE coverage

| Group | Required coverage |
| --- | --- |
| Wide constants | lconst_0/1, dconst_0/1, ldc2_w with correct constant kinds and two-slot pool handling |
| Loads/stores | lload/dload/lstore/dstore and compact forms; all legal category-one/category-two `wide` loads/stores and signed wide iinc |
| Arrays/fields | laload/daload/lastore/dastore; newarray long/double; long/double static and instance fields, constants, defaults, and arraycopy |
| Long operations | ladd/lsub/lmul/ldiv/lrem/lneg; lshl/lshr/lushr; land/lor/lxor; lcmp; lreturn |
| Double operations | dadd/dsub/dmul/ddiv/drem/dneg; dcmpl/dcmpg; dreturn |
| Conversions | i2l/i2d, l2i/l2f/l2d, f2l/f2d, d2i/d2l/d2f plus preserved existing conversions |
| Stack forms | Every JVMS category-one/category-two form of pop/pop2/dup/dup_x1/dup_x2/dup2/dup2_x1/dup2_x2/swap |
| Control flow | tableswitch, lookupswitch, existing branches/goto_w, and exception edges |
| Dynamic linkage | invokedynamic; ldc/ldc_w MethodHandle and MethodType; BootstrapMethods; signature-polymorphic MethodHandle.invokeExact/invoke |

Extend the existing MiniJRE surfaces rather than adding independent host wrappers:

- Long and Double boxing, primitive-value accessors, TYPE, equality/hash/string conversion; Long decimal parsing and Java-required boxing identity behavior; Double.isNaN/isInfinite and doubleToRawLongBits/doubleToLongBits/longBitsToDouble.
- PrintStream println(long/double), String.valueOf(long/double), and StringBuilder.append(long/double), with Java-compatible observable numeric formatting. Implement binary64 decimal conversion correctly rather than casting to F32. Double string parsing is not required by the opcode milestone unless already promised by a preceding implementation.
- Reflection generic and typed long/double field access, legal primitive widening, call/constructor argument and result boxing, proxy handler conversion, annotation element/default materialization, equality/hash, arraycopy, and primitive array mirrors. Remove milestone 3's category-two restrictions only when all these paths work.
- Long/Double method behavior must be consistent with existing Number/wrapper hierarchy. Raw-byte/IPC formats remain lossless two-word records. Increment transport format versions and migrate callers atomically if their existing contract changes.

## Switch instructions

- Decode variable-length layouts using padding relative to the beginning of the method code array: the first 32-bit operand begins on a four-byte boundary after the opcode. Validate required zero padding and truncated prefixes.
- Parse signed 32-bit default/case displacements relative to the opcode offset. Validate arithmetic without U32 wraparound accidentally making an invalid target appear in range.
- tableswitch: validate high >= low, compute high-low+1 with overflow-safe bounds, and verify the complete payload fits before allocating a case vector.
- lookupswitch: require nonnegative npairs, bounded payload, and strictly increasing signed match keys. Reject duplicate/unsorted keys.
- Resolve every target against the existing instruction-boundary map; reject jumps into padding/operands, outside code, or exactly to code_length. The code_length sentinel remains legal only where the format permits it, such as exception end_pc.
- Store decoded switch data once per method and reference it from an instruction; do not cram a variable-length table into the three scalar operands or reparse code while executing.
- tableswitch uses direct bounded indexing; lookupswitch uses an indexed/searchable decoded representation rather than rescanning bytes. Preserve deterministic target selection and fuel accounting.
- The verifier consumes the int key and considers default plus every case successor. Diagnostics/disassembly retain original byte offsets and display signed keys and targets.

## Authoritative Java 8 verification

### Placement and cutover

- Add a method/class verifier under `bendjvm/verifier/` using the existing instruction contracts as a starting point, not as proof that verification already occurs.
- Enforce verification before class publication/execution for standalone startup, dependency closure, runtime Class.forName loading, bootstrap targets, and synthesized proxy/lambda methods. Internal synthetic representations require equivalent validated invariants, not an unchecked back door.
- Remove the Python class-byte/stack verification implementation and its runner bypasses once the Bend verifier covers its observable contracts. The host retains I/O/transport validation only. Do not maintain two semantic verifiers with different opcode tables.
- Keep diagnostics actionable: class, method/descriptor, original byte offset, and error category. Invalid code cannot emit application output before rejection.

### Type states and control flow

- Track typed locals/operand values, slot widths, null, reference/array types, top/unusable locals, uninitializedThis, and uninitialized objects keyed by the `new` instruction offset.
- Implement a terminating control-flow worklist with checked merges. Operand heights/widths and primitive types must agree; reference merges follow class/interface/array assignability, without initializing classes. Uninitialized identities cannot be merged or used as arbitrary initialized references.
- Enforce descriptor-based arguments/returns, receiver constraints, correct field/method constant-pool kinds, category-two bounds/overlap, constructor rules, stack permutation forms, return opcode/type, and absence of fallthrough past Code.
- Constructors may initialize the correct object/super constructor only once according to verifier rules; aliases of an initialized allocation transition together. Validate uses of uninitializedThis, including constructor-specific field access and exceptional edges, against Java 8 rules rather than a blanket ban on all pre-super operations.
- Include every switch/conditional/fallthrough successor and exception-handler entry. Handler stacks contain exactly the appropriate throwable reference and required local state. Validate catch types/ranges and constructor initialization state on exceptional flow.
- Abstract/native methods follow Code-attribute rules rather than pretending to have an empty executable body. Validate method flags, argument/local capacity, and JVM descriptor slot limits including receivers where required.

### StackMapTable

- Stop discarding Code metadata. Decode every Java 8 StackMapTable frame form, offset_delta, verification_type_info, object CP reference, and uninitialized offset with bounds and exact consumption checks.
- Interpret category-two entries correctly: they are one verification value but two local/stack slots. Distinguish a real Top local from the reserved continuation of a wide value.
- Check supplied frames against the method entry state, instruction boundaries, control-flow obligations, exception edges, and computed transitions using Java 8 verification rules.
- For version 52, an absent StackMapTable has the specified implicit empty table; it is not permission to ignore required branch-target frames or fall back to permissive type inference after failure.
- Reject inconsistent frames, wrong object kinds, duplicate/invalid attributes, invalid uninitialized offsets, category mismatches, and reachable invalid instructions deterministically. Apply structural checks even to unreachable code as the format requires.
- Preserve unsupported-feature errors for monitors and other excluded valid constructs. Never relabel unsupported bytecode as successfully verified because the worklist did not visit it.

## General invokedynamic architecture

### Metadata and resolution

- Parse class-level BootstrapMethods once, validate count/index bounds and legal bootstrap arguments, and retain stable references. Validate InvokeDynamic name/type and bootstrap indices separately from executing the bootstrap.
- Decode opcode 186's two-byte CP index and two zero reserved bytes. Verify the dynamic call descriptor's stack effects, including category-two parameters/results; there is no receiver slot.
- Materialize MethodType and all nine Java 8 direct MethodHandle reference kinds with correct descriptors, receiver/constructor behavior, access checks, and class initialization rules. Reuse milestone 3 mirrors and access checks, not host Java reflection.
- Maintain linkage state per dynamic call-site instruction, not merely per shared InvokeDynamic constant-pool entry. Separate unresolved, linking, linked, and failed states; retain a stable target or recorded linkage failure as required by the JVM contract.
- On first execution, resolve and invoke the bootstrap through normal Bend VM calls, passing the caller Lookup, name, MethodType, and resolved static arguments. Support the standard bootstrap argument adaptation/varargs rules.
- Validate returned CallSite and exact target MethodType before publication. Bootstrap target code may itself load classes, invoke methods, throw, or use dynamic sites; preserve normal fuel/heap/initialization state through all continuations.
- Match Java 8 BootstrapMethodError/error propagation and failure caching, including wrong/null results, wrong target type, failing static arguments, and recursive/reentrant linkage. Do not return a fabricated call site to break recursion.
- Once linked, invoke the target directly through typed VM machinery; do not rerun the bootstrap on every call or silently relink a failed site.

### Minimal java.lang.invoke surface

Document exact descriptors for these APIs and implement them as real Bend operations:

- MethodType creation from Class mirrors and fromMethodDescriptorString; returnType, parameterCount/parameterType/parameterArray, equals/hashCode, and toMethodDescriptorString.
- MethodHandles.lookup/publicLookup; Lookup.lookupClass/lookupModes/in and findStatic/findVirtual/findSpecial/findConstructor/findGetter/findSetter/findStaticGetter/findStaticSetter with caller-sensitive Java 8 access rules.
- MethodHandle.type, signature-polymorphic invokeExact/invoke, asType, bindTo, asVarargsCollector/asFixedArity/isVarargsCollector. Treat signature-polymorphic callsite descriptors specially in linker/verifier/invocation; do not search for an ordinary method with the arbitrary call-site descriptor.
- MethodHandles.constant, identity, and insertArguments as a small usable bootstrap construction surface. Other combinators remain explicitly unsupported, not no-op adapters.
- CallSite.type/getTarget/setTarget/dynamicInvoker; ConstantCallSite(MethodHandle), MutableCallSite(MethodHandle)/MutableCallSite(MethodType), and VolatileCallSite corresponding constructors. Constant sites reject mutation; mutable/volatile sites enforce exact target type. MutableCallSite.syncAll has the documented single-thread behavior until milestone 5 supplies a memory model.
- MethodType/handle mismatch and resolution errors use WrongMethodTypeException, relevant reflective/access errors, and BootstrapMethodError as required. Direct handle target exceptions propagate directly, not through reflection's InvocationTargetException wrapper.
- Implement unboxing/boxing, reference casts, primitive widening, return dropping/defaulting, and permitted invoke/asType adaptations against the Java 8 contracts. Exact invocation does not coerce a merely convertible signature.

This is a usable method-handle subset for general bootstraps, not a claim that every OpenJDK combinator or lookup feature is present.

### Lambda compatibility

- Implement LambdaMetafactory.metafactory and altMetafactory using the general bootstrap mechanism. Support capturing/noncapturing lambdas, static/bound/unbound/constructor method references, erased SAM descriptors, captured arguments, and legal boxing/widening/reference adaptations.
- Synthesize Bend-owned SAM implementation classes using the append-only registry and interface dispatch from prior milestones. Do not create host closures that bypass Java frames or special-case javac-generated names.
- Implement altMetafactory marker-interface and bridge-method flags and validate additional arguments. For the serializable flag, generate the required serializable identity/writeReplace metadata and a minimal SerializedLambda representation; ObjectOutputStream serialization remains excluded and must not be advertised as working.
- Validate lookup privileges, interface/SAM shape, implementation handle kind, parameter counts, and return adaptation. Route default interface methods only within the already-supported runtime contract; this milestone does not silently add general default-method resolution.
- No lambda identity guarantee beyond Java's requirements: tests must not demand cached instance identity. Invocation behavior and capture isolation are the contract.
- Use user-defined functional interfaces in baseline fixtures; add only the java.util.function interfaces explicitly needed by additional examples, rather than promising the entire streams ecosystem.

## Ordered implementation slices

### 1. Migrate value categories and calling conventions

Targets: `model.bend`, descriptor helpers, runtime frame/state/execute modules, heap/catalog records, every intrinsic/API/transport consumer, and meaningful proofs.

- Introduce two-word values and category-aware stack/local accounting.
- Update arguments, returns, fields, arrays, and all legal stack permutations together.
- Inventory exported-symbol references with an available language server; migrate every caller without old/new ABI shims.

Acceptance: category-one fixtures remain correct; mixed-width calls occupy correct local indices; two-slot bounds, odd-index locals, overlapping stores, and every legal/illegal stack shape behave correctly. Host round trips preserve words beyond 2^53 without numeric coercion.

### 2. Implement complete long execution

Targets: a focused U32-limb numeric module, constant linking, decoder/executor/verifier rules, long array/field helpers, and Long-related MiniJRE methods.

- Implement long arithmetic/conversions, constants, normal/compact/wide loads/stores, returns, shifts/comparison, arrays/fields, and decimal formatting/parsing.
- Add exact boundary vectors and deterministic randomized differential cases; remove long-specific rejection paths only after their replacement works.

Acceptance: all long opcode families work through normal Java calls and mutable storage. Cover carries, sign extension, MIN/MAX, multiplication wrap, divide-by-zero, MIN/-1, negative remainder, and shift counts 0/31/32/63/64/negative. Validate byte/word persistence across the generated backend.

### 3. Implement binary64 and wide-value API integration

Targets: pure Bend binary64 primitives, runtime conversions, Double/printing/StringBuilder methods, prior reflection/annotation/proxy paths, and long/double arrays.

- Verify backend numeric capabilities, then implement the selected Bend-owned binary64 primitives with explicit rounding.
- Complete all double arithmetic/conversions and decimal output. Add raw-bit observation methods for exact verification without relying only on formatted strings.
- Remove prior metadata-only/category-two restrictions from reflection, proxies, annotations, and boxing once they use the common representation.

Acceptance: normal/subnormal/zero/infinity/NaN vectors and rounding ties match Java semantics; conversions around 2^24, 2^53, int/long saturation boundaries, and signed-zero operations behave correctly. Wide values pass through reflection, annotation defaults, proxy callbacks, fields, arrays, and ordinary calls without loss.

### 4. Decode and execute switches and remaining wide forms

Targets: `bytecode/decode.bend`, instruction/method payload representation, runtime dispatch, diagnostics, and CFG successor extraction.

- Add bounded variable-width decoding and decode-once case payloads.
- Resolve all targets through the boundary map and implement dense/sparse signed-key dispatch.
- Complete ordinary wide loads/stores/iinc and preserve goto_w correctness.

Acceptance: dense, sparse, negative, default-only lookup, nested, enum, and String switches compiled for Java 8 work where their library prerequisites are supported. Exercise every padding alignment, boundary key, repeated target, backward edge, large local index, and malformed/truncated/overflowing table. Switches inside try/catch use correct handler PCs.

### 5. Enforce the Bend type/stack-map verifier and remove the Python checker

Targets: new method/class dataflow modules under `verifier/`, existing rule definitions, StackMapTable parsing, loader publication gates, and `scripts/run.py`.

- Implement typed CFG propagation, stack-map validation, constructor/uninitialized-object rules, exception edges, and category-aware bounds.
- Enforce verification on every class ingestion path, including runtime append and synthesized class validation.
- Replace runner-side semantic checks with the authoritative Bend result; preserve useful error categories without swallowing malformed-input errors.

Acceptance: valid javac Java 8 programs with merges, wide values, switches, constructors, interfaces, and handlers pass. Mutated bad frames, illegal pair overlap, mismatched return, uninitialized escape, invalid branch/handler edges, and bad descriptors fail before output. No loader path bypasses verification. Existing malformed fixtures remain meaningful; regenerate valid frames for positive fixtures rather than weakening validation.

### 6. Method types, direct handles, and general dynamic linkage

Targets: BootstrapMethods parser/metadata, java.lang.invoke MiniJRE modules, catalog/runtime linker, opcode 186, callsite state, continuations, and verifier rules.

- Implement the stated MethodType/Lookup/MethodHandle/CallSite surface and access/type adaptation rules.
- Resolve/bootstrap/cache real dynamic sites through normal VM invocation; support mutable targets within the single-thread model.
- Add generated class-file fixtures because javac cannot express arbitrary custom invokedynamic sites in ordinary Java source. Extend existing Python fixture machinery rather than requiring an external bytecode package.

Acceptance: a user bootstrap returns a constant site; a second returns a mutable site whose target changes; arguments/results include wide values and reference conversions. Verify bootstrap-once behavior, independent instruction sites sharing one CP entry, cached failures, incorrect target types/results, bootstrap exceptions, access denial, reentrant linkage, and invokeExact versus invoke adaptation. Run the same generated classes on OpenJDK with verification enabled.

### 7. Java 8 lambdas and method references

Targets: LambdaMetafactory/SerializedLambda support, append-only synthetic class generation, bridge/marker metadata, and regular interface dispatch.

- Build lambda support on slice 6 instead of adding an alternate special interpreter for opcode 186.
- Support captures, bound/unbound/static/constructor references, return/argument adaptations, marker interfaces, and bridges; preserve normal call stacks and exceptions.

Acceptance: ordinary javac `--release 8` fixtures exercise each form, including long/double captures and results, captured mutable references, thrown target exceptions, generic SAM bridges, and altMetafactory metadata. Synthetic classes remain valid through reflection/type checks without asserting implementation-specific names or lambda identity.

### 8. Integrated compatibility corpus and milestone gates

Targets: `scripts/test.py`, reusable Java fixtures and deterministic classfile generators, runner/Bend diagnostics, README/spec/roadmap, LAWS/PROOF.

- Run one packaged application combining long/double calculations, both switch formats, lambda invocation, custom dynamic linkage, and the previous milestones' reflection/resource paths.
- Expand existing harness groups for numeric edge cases, verifier mutations, and bootstrap lifecycle behavior. Seed all generated cases and bound code sizes/worklists.
- Update disassembly/trace mnemonics and operand rendering; method/PC labels must remain useful after variable-width decoding.
- Document exact Java 8 instruction/API coverage, new representation/limits, remaining exclusions, and the removal of partial host verification. Mark roadmap completion only after all four rows pass.

Acceptance: the integrated program and existing milestone corpus pass; every named opcode/API contract is exercised through the real generated runtime, malformed inputs fail predictably, and docs do not overstate Java-version/JDK/concurrency coverage.

## Dependency and parallel-work map

- Slice 1 is the shared representation boundary. Long and binary64 arithmetic kernels can then be developed independently under fixed high/low-word and result/error contracts; float-to-long/double conversions have one integration owner.
- Switch decoding and StackMapTable parsing can proceed concurrently once the decoded instruction payload contract is fixed. The verifier and runtime must share that representation, not duplicate byte parsing.
- Slice 5 consumes final numeric/switch rules and gates publication; slice 6 extends it for dynamic calls; slice 7 consumes general linkage and prior interface/synthetic-class support; slice 8 integrates all work.
- One owner controls model/descriptor/calling-convention edits, catalog IDs, shared opcode dispatch, generated adapter ABI, and harness registration. Parallel writers own numeric kernels, focused parser modules, or fixture generation—not conflicting shared registries.
- Within Bend, parallelize independent method verification/metadata work where practical, preserving deterministic diagnostics and declaration order. Bootstrap invocation, call-site publication, class initialization, and application effects remain sequenced. No Java concurrency is implied.

## Verification strategy

Before implementation, run `bend guide`, check backend capabilities with a throwaway numeric probe, and map symbol references before exported API changes. Re-read all shared state definitions because earlier milestones may have changed the source since this plan was written.

Use the existing harness and OpenJDK as behavioral oracle:

- Compile positive sources with `javac --release 8`; inspect actual opcodes/StackMapTable/BootstrapMethods with `javap -v -c -s` when establishing coverage.
- Use `java -Xverify:all` for generated/mutated bytecode compatibility checks. Compare validity/error families, not JVM-specific diagnostics or exact rejection timing beyond the promised pre-execution gate.
- Numeric tests compare exact integer words and raw floating bits where specified; canonicalize allowed arithmetic NaN variability. Include deterministic randomized arithmetic/conversion inputs in addition to hand-picked hard rounding cases. Decimal formatting requires independent output comparisons as well as bit-level checks.
- Exercise legal and illegal forms of every category-sensitive stack operation; parser-only smoke checks do not establish stack or runtime correctness.
- Verify dynamic sites with observable bootstrap counters, changed targets, and target/exception behavior, not by asserting internal cache record layouts.
- Preserve tests for real boundaries and plausible defects. Do not add source-text/dispatch-table existence assertions or tautological round trips as substitutes for a reference oracle.
- Keep malformed corpus construction format-aware: code mutations affecting frames/offsets must produce a valid positive control before the intended corruption is applied.

Final commands:

```sh
python3 scripts/run.py --prepare
python3 scripts/test.py --fast
python3 scripts/test.py --full
bend PROOF.bend
```

Extend `--fast` with representative long/double, switch, verifier, and lambda/custom-bootstrap cases. `--full` covers all opcode families, edge-case arithmetic, StackMapTable mutations, and linkage lifecycle cases. Run the packaged integrated application through the actual CLI as well as harness checks; include fuel/heap exhaustion during bootstrap execution and wide-value allocation.

Candidate laws: two-word encode/decode preservation, add/sub carry correctness, category width conservation under legal permutations, local-pair overwrite invariants, valid resolved switch targets, stable IDs during synthetic publication, and exactly-once successful callsite publication in the single-thread model. State proof scope honestly; a partial arithmetic law is not full IEEE conformance. Run `bend PROOF.bend` before committing.

## Completion checklist

- General invokedynamic links and invokes user bootstrap targets; lambda support uses that path rather than replacing it.
- Every long/double opcode, conversion, stack form, field/array/call path, and promised MiniJRE integration works without lossy host transport.
- Binary64 behavior covers IEEE exceptional values, signed zero, subnormals, rounding, remainder, and integer-conversion limits.
- Both switch formats are decoded once, validated, verified, executed, and rendered correctly.
- Bend verification is enforced on all loading/publication paths; no partial Python semantic checker or permissive fallback remains.
- Prior loading/runtime/reflection/resource behavior survives the representation cutover. Reflection/annotations/proxies no longer have stale category-two restrictions.
- Named acceptance cases and API surfaces are implemented or scope is changed with explicit user approval; no hard-coded bootstrap successes, placeholder numeric operations, or skipped malformed-input checks.
- Documentation and meaningful laws/proofs reflect observed behavior. Remove throwaway probes/generated artifacts after verification; retain reusable fixtures/generators and deterministic regression cases.

Planning verification: grounded in current model/frame/descriptor/constant-pool/decoder/verifier/runner code and preceding plans. This document does not claim implemented bytecode support or passing runtime tests.
