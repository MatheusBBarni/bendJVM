import Base
import ../model.bend as M
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ../loader/symbols.bend as Sy
import ./outcome.bend as O
import ./library.bend as L

# Stack traces (plan 05): sun.misc.BendStackTrace.frames(Throwable) (829)
# renders the (method, offset) pairs a throwable recorded at creation as
# "owner.method(File.java:line)" strings; the Java class prints them in the
# JDK's printStackTrace format. Throwable.printStackTrace (818/819) calls it.

# The line of the last LineNumberTable entry starting at or before `offset`.
def line_at(entries: +List<U32>, +offset: U32, +best: U32, +bestStart: U32, +found: Bool) -> U32:
  match entries:
    case Con{+start, Con{+line, rest}}:
      +better : Bool = U32.is_le(start, offset) && (Bool.not(found) || U32.is_ge(start, bestStart))
      line_at(rest, offset, Bool.pick(U32, better, line, best), Bool.pick(U32, better, start, bestStart), found || better)
    case _: Bool.pick(U32, found, best, 0)

def method_lines(found: Result<&2, &2, String, M.MethodMetadata>) -> +List<U32>:
  match found:
    case Done{M.MethodMetadata{owner, method, metadata, signature, parameters, lines}}: lines
    case Fail{error}: Nil{}

def class_source(found: Result<&2, &2, String, M.ClassMetadata>) -> String:
  match found:
    case Done{M.ClassMetadata{owner, flags, metadata, visible, pool, signature, nesting, source}}: source
    case Fail{error}: ""

def location(+source: String, +line: U32) -> String:
  Bool.pick(String, String.is_empty(source), "Unknown Source",
    Bool.pick(String, U32.is_eq(line, 0), source, source ++ ":" ++ U32.show(line)))

def is_init(+vm: M.VM, +method: M.LoadedMethod) -> Bool:
  String.eq(Sy.text(S.symbols(vm), M.loaded_method_name(method)), "<init>")

# A throwable's own constructor frames are not part of its trace (as on the JDK).
def throwable_ctor(+vm: M.VM, +method: M.LoadedMethod) -> Bool:
  is_init(vm, method) && H.hierarchy(S.classes(vm), M.loaded_method_owner(method), L.class_id(vm, "java/lang/Throwable"))

type Strings is Data:
  Strings{vm: M.VM, values: +List<M.Slot>}

def strings_vm(s: Strings) -> M.VM:
  match s:
    case Strings{vm, values}: vm

def strings_values(s: Strings) -> +List<M.Slot>:
  match s:
    case Strings{vm, values}: values

def array_out(allocation: H.Allocation) -> Result<&2, &2, String, O.Outcome>:
  match allocation:
    case H.Allocation{updated, reference}: L.ref_out(updated, reference)

def entry_values(entry: M.HeapEntry) -> +List<M.Slot>:
  match entry:
    case M.HeapEntry{class, kind, element, fields, values, chars}: values

def printer_found(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>, +throwable: U32, +stream: U32) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case Some{method}: Done{O.Call{vm, method, [M.Slot{3, throwable}, M.Slot{3, stream}]}}
    # The printer class is part of every launch; without it, print toString().
    case None{}: L.print_object_to(vm, throwable, True{}, U32.is_eq(stream, L.err_stream()))

def method_named(methods: +List<M.LoadedMethod>, +symbols: +List<String>, +owner: U32, +name: String, +descriptor: String) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, U32.is_eq(M.loaded_method_owner(method), owner) && String.eq(Sy.text(symbols, M.loaded_method_name(method)), name) && String.eq(Sy.text(symbols, M.loaded_method_descriptor(method)), descriptor),
        Some{method}, method_named(rest, symbols, owner, name, descriptor))

def printer(+vm: M.VM) -> Maybe<&2, M.LoadedMethod>:
  method_named(S.methods(vm), S.symbols(vm), L.class_id(vm, "sun/misc/BendStackTrace"), "print", "(Ljava/lang/Throwable;Ljava/io/PrintStream;)V")

# Throwable.printStackTrace() / printStackTrace(PrintStream).
def print_stack_trace(+vm: M.VM, +args: +List<M.Slot>, +stream: Bool) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, +throwable}, Con{M.Slot{3, +target}, rest}}:
      Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(target, 0), Fail{"java/lang/NullPointerException"}, printer_found(vm, printer(vm), throwable, target))
    case Con{M.Slot{3, +throwable}, Nil{}}: printer_found(vm, printer(vm), throwable, L.err_stream())
    case _: Fail{"InvalidState: printStackTrace arguments"}

# Binary class names: '/' becomes '.', and a loader namespace suffix
# (U+E000 and what follows) is not shown.
@unsafe def display_units(units: +List<U32>) -> +List<U32>:
  match units:
    case Nil{}: Nil{}
    case Con{+u, rest}: display_unit(U32.is_eq(u, 57344), u, rest)

@unsafe def display_unit(stop: Bool, +u: U32, rest: +List<U32>) -> +List<U32>:
  match stop:
    case True{}: Nil{}
    case False{}: Con{Bool.pick(U32, U32.is_eq(u, 47), 46, u), display_units(rest)}

def display_name(+name: String) -> String:
  L.utf16(display_units(L.units_from_string(name)), 0)

# An intrinsic's frame: a native method of a Java-source MiniJRE class (it has
# a source file) prints as on the JDK; bootstrap intrinsics have no source.
def native_location(+source: String) -> String:
  Bool.pick(String, String.is_empty(source), "Unknown Source", "Native Method")

def located(native: Bool, +source: String, +lines: +List<U32>, +offset: U32) -> String:
  match native:
    case True{}: native_location(source)
    case False{}: location(source, line_at(lines, offset, 0, 0, False{}))

def frame_text(+vm: M.VM, +method: M.LoadedMethod, +offset: U32) -> String:
  +owner : U32 = M.loaded_method_owner(method)
  +lines : +List<U32> = method_lines(L.method_metadata_value(vm, M.loaded_method_id(method)))
  display_name(L.class_name_text(vm, owner)) ++ "." ++ Sy.text(S.symbols(vm), M.loaded_method_name(method)) ++ "(" ++ located(U32.is_eq(offset, 4294967295), class_source(L.class_metadata_value(vm, owner)), lines, offset) ++ ")"

@unsafe def frames_texts(+vm: M.VM, values: +List<M.Slot>, +skipping: Bool) -> +List<String>:
  match values:
    case Con{+m, Con{+o, rest}}: frame_found(vm, M.nth(M.LoadedMethod, S.methods(vm), M.slot_bits(m)), M.slot_bits(o), rest, skipping)
    case _: Nil{}

@unsafe def frame_kept(skip: Bool, +vm: M.VM, +method: M.LoadedMethod, +offset: U32, rest: +List<M.Slot>) -> +List<String>:
  match skip:
    case True{}: frames_texts(vm, rest, True{})
    case False{}: Con{frame_text(vm, method, offset), frames_texts(vm, rest, False{})}

@unsafe def frame_found(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>, +offset: U32, rest: +List<M.Slot>, +skipping: Bool) -> +List<String>:
  match found:
    case None{}: frames_texts(vm, rest, skipping)
    case Some{+method}: frame_kept(skipping && throwable_ctor(vm, method), vm, method, offset, rest)

@unsafe def allocate_strings(+vm: M.VM, texts: +List<String>) -> Result<&2, &2, String, Strings>:
  match texts:
    case Nil{}: Done{Strings{vm, Nil{}}}
    case Con{+text, rest}:
      do Result<&2, &2, String, Strings>:
        allocation : H.Allocation <- H.allocate(vm, H.string_entry(L.class_id(vm, "java/lang/String"), L.units_from_string(text)))
        +done : Strings <- allocate_rest(allocation, rest)
        return done

@unsafe def allocate_rest(allocation: H.Allocation, rest: +List<String>) -> Result<&2, &2, String, Strings>:
  match allocation:
    case H.Allocation{+updated, +reference}:
      do Result<&2, &2, String, Strings>:
        +tail : Strings <- allocate_strings(updated, rest)
        return Strings{strings_vm(tail), Con{M.Slot{3, reference}, strings_values(tail)}}

# BendStackTrace.frames(Throwable): its recorded frames, innermost first.
def frames(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  match args:
    case Con{M.Slot{3, 0}, rest}: Fail{"java/lang/NullPointerException"}
    case Con{M.Slot{3, +throwable}, rest}:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), throwable)
        +texts : +List<String> = frames_texts(vm, entry_values(entry), True{})
        +strings : Strings <- allocate_strings(vm, texts)
        +ready : M.VM = strings_vm(strings)
        allocation : H.Allocation <- H.allocate(ready, H.reference_array_entry(L.class_id(ready, "[Ljava/lang/String;"), L.class_id(ready, "java/lang/String"), strings_values(strings)))
        result : O.Outcome <- array_out(allocation)
        return result
    case _: Fail{"InvalidState: BendStackTrace.frames arguments"}
