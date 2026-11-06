import Base
import ../model.bend as M
import ../runtime/value.bend as V
import ../runtime/state.bend as S
import ../heap/heap.bend as H
import ./outcome.bend as O
import ./library.bend as L

# java.io.File paths, java.net.URI/URL parsing, URL connections and jar files:
# the surface classpath scanning uses (Spring's PathMatchingResourcePatternResolver).

def bits(slot: M.Slot) -> U32:
  M.slot_bits(slot)

def none() -> U32:
  4294967295

@unsafe def arg_at(+args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, M.Slot>:
  S.require(M.Slot, M.nth(M.Slot, args, index), "InvalidState: intrinsic argument count")

@unsafe def arg_ref(+args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +slot : M.Slot <- arg_at(args, index)
    return bits(slot)

@unsafe def text_arg(+vm: M.VM, +args: +List<M.Slot>, +index: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +reference : U32 <- arg_ref(args, index)
    checked : Unit <- S.check(U32.is_ne(reference, 0), L.npe())
    +text : String <- L.string_text(vm, reference)
    return text

@unsafe def binding_ref(+vm: M.VM, +reference: U32, +index: U32) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    return L.field_bits(L.entry_fields(entry), index)

@unsafe def binding_text(+vm: M.VM, +reference: U32, +index: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +value : U32 <- binding_ref(vm, reference, index)
    +text : String <- L.string_text(vm, value)
    return text

@unsafe def text_out(+vm: M.VM, +text: String) -> Result<&2, &2, String, O.Outcome>:
  L.intern_or_alloc(vm, L.units_from_string(text))

type Allocated is Data:
  Allocated{vm: M.VM, reference: U32}

@unsafe def allocated(result: Result<&2, &2, String, H.Allocation>) -> Result<&2, &2, String, Allocated>:
  match result:
    case Fail{error}: Fail{error}
    case Done{H.Allocation{vm, reference}}: Done{Allocated{vm, reference}}

@unsafe def alloc_string(+vm: M.VM, +text: String) -> Result<&2, &2, String, Allocated>:
  allocated(H.allocate(vm, H.string_entry(L.class_id(vm, "java/lang/String"), L.units_from_string(text))))

# An object whose bindings are strings, allocated after its strings.
@unsafe def alloc_text_object(+vm: M.VM, +class: String, +texts: +List<String>, +extra: +List<M.Binding>) -> Result<&2, &2, String, Allocated>:
  alloc_text_object_go(vm, class, texts, 0, extra)

@unsafe def alloc_text_object_go(+vm: M.VM, +class: String, +texts: +List<String>, +index: U32, +acc: +List<M.Binding>) -> Result<&2, &2, String, Allocated>:
  match texts:
    case Nil{}: allocated(H.allocate(vm, H.object_entry(L.class_id(vm, class), acc)))
    case Con{+text, rest}:
      do Result<&2, &2, String, Allocated>:
        +value : Allocated <- alloc_string(vm, text)
        +result : Allocated <- alloc_text_object_next(value, class, rest, index, acc)
        return result

@unsafe def alloc_text_object_next(+value: Allocated, +class: String, +rest: +List<String>, +index: U32, +acc: +List<M.Binding>) -> Result<&2, &2, String, Allocated>:
  match value:
    case Allocated{+vm, +reference}: alloc_text_object_go(vm, class, rest, U32.add(index, 1), Con{M.Binding{index, M.Slot{3, reference}}, acc})

@unsafe def allocated_out(result: Result<&2, &2, String, Allocated>) -> Result<&2, &2, String, O.Outcome>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Allocated{vm, reference}}: L.ref_out(vm, reference)

# --- Text helpers on Bend strings ---

@unsafe def last_index(+chars: +List<Char>, +target: U32, +index: U32, +best: U32) -> U32:
  match chars:
    case Nil{}: best
    case Con{Chr{+c}, rest}: last_index(rest, target, U32.add(index, 1), Bool.pick(U32, U32.is_eq(c, target), index, best))

@unsafe def first_index(+chars: +List<Char>, +target: U32, +index: U32) -> U32:
  match chars:
    case Nil{}: none()
    case Con{Chr{+c}, rest}: first_index_step(U32.is_eq(c, target), index, rest, target)

@unsafe def first_index_step(hit: Bool, +index: U32, +rest: +List<Char>, +target: U32) -> U32:
  match hit:
    case True{}: index
    case False{}: first_index(rest, target, U32.add(index, 1))

@unsafe def take_text(+text: String, +count: U32) -> String:
  String.from_list(M.take(Char, String.to_list(text), U32.to_nat(count)))

@unsafe def drop_text(+text: String, +count: U32) -> String:
  String.from_list(M.drop(Char, String.to_list(text), U32.to_nat(count)))

@unsafe def text_length(+text: String) -> U32:
  M.length(Char, String.to_list(text))

# Index of "!/" in a jar URL or origin, or none.
@unsafe def bang_slash(+chars: +List<Char>, +index: U32) -> U32:
  match chars:
    case Nil{}: none()
    case Con{Chr{33}, Con{Chr{47}, rest}}: index
    case Con{c, rest}: bang_slash(rest, U32.add(index, 1))

# --- java.io.File (UnixFileSystem) ---

@unsafe def collapse_slashes(+chars: +List<Char>, +previous: Bool) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{47}, rest}: collapse_slash(previous, rest)
    case Con{c, rest}: Con{c, collapse_slashes(rest, False{})}

@unsafe def collapse_slash(previous: Bool, +rest: +List<Char>) -> +List<Char>:
  match previous:
    case True{}: collapse_slashes(rest, True{})
    case False{}: Con{Chr{47}, collapse_slashes(rest, True{})}

# normalize: no repeated '/', and no trailing '/' except for the root.
@unsafe def file_normalize(+path: String) -> String:
  +collapsed : String = String.from_list(collapse_slashes(String.to_list(path), False{}))
  Bool.pick(String, String.ends_with(collapsed, "/") && U32.is_gt(text_length(collapsed), 1), take_text(collapsed, U32.sub(text_length(collapsed), 1)), collapsed)

# resolve(parent, child) for normalized paths.
@unsafe def file_resolve(+parent: String, +child: String) -> String:
  Bool.pick(String, String.is_empty(child), parent,
    Bool.pick(String, String.starts_with(child, "/"), Bool.pick(String, String.eq(parent, "/"), child, parent ++ child),
      Bool.pick(String, String.eq(parent, "/"), parent ++ child, parent ++ "/" ++ child)))

@unsafe def file_child_path(+parent: String, +child: String) -> String:
  Bool.pick(String, String.is_empty(parent), file_resolve("/", file_normalize(child)), file_resolve(file_normalize(parent), file_normalize(child)))

@unsafe def set_file_path(+vm: M.VM, +receiver: U32, +path: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +value : Allocated <- alloc_string(vm, path)
    +result : O.Outcome <- set_file_path_ref(value, receiver)
    return result

@unsafe def set_file_path_ref(+value: Allocated, +receiver: U32) -> Result<&2, &2, String, O.Outcome>:
  match value:
    case Allocated{+vm, +reference}:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), receiver)
        +result : O.Outcome <- L.void_out(H.put(vm, receiver, H.object_entry(H.entry_class(entry), [M.Binding{0, M.Slot{3, reference}}])))
        return result

@unsafe def file_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +path : String <- text_arg(vm, args, 1)
    +result : O.Outcome <- set_file_path(vm, receiver, file_normalize(path))
    return result

# File(String parent, String child): a null parent means File(child).
@unsafe def file_init_parent_text(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +parent : U32 <- arg_ref(args, 1)
    +child : String <- text_arg(vm, args, 2)
    +parent_text : String <- optional_text(vm, parent)
    +result : O.Outcome <- set_file_path(vm, receiver, Bool.pick(String, U32.is_eq(parent, 0), file_normalize(child), file_child_path(parent_text, child)))
    return result

@unsafe def optional_text(+vm: M.VM, +reference: U32) -> Result<&2, &2, String, String>:
  match reference:
    case 0: Done{""}
    case +ref: L.string_text(vm, ref)

@unsafe def file_path_of(+vm: M.VM, +file: U32) -> Result<&2, &2, String, String>:
  match file:
    case 0: Done{""}
    case +ref: binding_text(vm, ref, 0)

@unsafe def file_init_parent_file(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +parent : U32 <- arg_ref(args, 1)
    +child : String <- text_arg(vm, args, 2)
    +parent_text : String <- file_path_of(vm, parent)
    +result : O.Outcome <- set_file_path(vm, receiver, Bool.pick(String, U32.is_eq(parent, 0), file_normalize(child), file_child_path(parent_text, child)))
    return result

# File(URI): an absolute, hierarchical "file" URI without authority or query.
@unsafe def file_init_uri(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +uri_ref : U32 <- arg_ref(args, 1)
    checked : Unit <- S.check(U32.is_ne(uri_ref, 0), L.npe())
    +text : String <- binding_text(vm, uri_ref, 0)
    +parts : UriParts = uri_parse(text)
    absolute : Unit <- S.check(uri_has_scheme(parts), "java/lang/IllegalArgumentException: URI is not absolute")
    hierarchical : Unit <- S.check(Bool.not(uri_opaque(parts)), "java/lang/IllegalArgumentException: URI is not hierarchical")
    scheme : Unit <- S.check(String.eq(String.from_list(lower_chars(String.to_list(uri_scheme(parts)))), "file"), "java/lang/IllegalArgumentException: URI scheme is not \"file\"")
    authority : Unit <- S.check(String.is_empty(uri_authority(parts)), "java/lang/IllegalArgumentException: URI has an authority component")
    +path : String = percent_decode(uri_path(parts))
    empty : Unit <- S.check(Bool.not(String.is_empty(path)), "java/lang/IllegalArgumentException: URI path component is empty")
    +result : O.Outcome <- set_file_path(vm, receiver, file_normalize(path))
    return result

@unsafe def file_name_text(+path: String) -> String:
  drop_text(path, U32.add(last_index(String.to_list(path), 47, 0, none()), 1))

@unsafe def file_get_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +path : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- text_out(vm, file_name_text(path))
    return result

# getParent: everything before the last separator ("/" for a child of the
# root), or null without one.
@unsafe def file_parent_text(+path: String) -> Maybe<&2, String>:
  +index : U32 = last_index(String.to_list(path), 47, 0, none())
  Bool.pick(Maybe<&2, String>, U32.is_eq(index, none()), None{},
    Some{Bool.pick(String, U32.is_eq(index, 0), Bool.pick(String, U32.is_gt(text_length(path), 1), "/", ""), take_text(path, index))})

@unsafe def file_parent_out(+vm: M.VM, found: Maybe<&2, String>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: L.ref_out(vm, 0)
    case Some{+text}: Bool.pick(Result<&2, &2, String, O.Outcome>, String.is_empty(text), L.ref_out(vm, 0), text_out(vm, text))

@unsafe def file_get_parent(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +path : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- file_parent_out(vm, file_parent_text(path))
    return result

@unsafe def file_absolute_text(+vm: M.VM, +path: String) -> String:
  Bool.pick(String, String.starts_with(path, "/"), path, file_resolve(file_normalize(S.host_cwd_of(S.host(vm))), path))

@unsafe def file_get_absolute_path(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +path : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- text_out(vm, file_absolute_text(vm, path))
    return result

@unsafe def new_file(+vm: M.VM, +path: String) -> Result<&2, &2, String, Allocated>:
  alloc_text_object(vm, "java/io/File", [path], Nil{})

@unsafe def file_get_absolute_file(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +path : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- allocated_out(new_file(vm, file_absolute_text(vm, path)))
    return result

@unsafe def file_get_parent_file(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +path : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- file_parent_file_out(vm, file_parent_text(path))
    return result

@unsafe def file_parent_file_out(+vm: M.VM, found: Maybe<&2, String>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: L.ref_out(vm, 0)
    case Some{+text}: Bool.pick(Result<&2, &2, String, O.Outcome>, String.is_empty(text), L.ref_out(vm, 0), allocated_out(new_file(vm, text)))

@unsafe def file_is_absolute(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +path : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- L.bool_out(vm, String.starts_with(path, "/"))
    return result

@unsafe def file_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +other : U32 <- arg_ref(args, 1)
    +path : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- file_equals_other(vm, path, other)
    return result

@unsafe def file_equals_other(+vm: M.VM, +path: String, +other: U32) -> Result<&2, &2, String, O.Outcome>:
  match other:
    case 0: L.bool_out(vm, False{})
    case +ref:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
        +same_class : Bool = U32.is_eq(H.entry_class(entry), L.class_id(vm, "java/io/File"))
        +result : O.Outcome <- file_equals_class(same_class, vm, path, ref)
        return result

@unsafe def file_equals_class(same: Bool, +vm: M.VM, +path: String, +other: U32) -> Result<&2, &2, String, O.Outcome>:
  match same:
    case False{}: L.bool_out(vm, False{})
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +other_path : String <- binding_text(vm, other, 0)
        +result : O.Outcome <- L.bool_out(vm, String.eq(path, other_path))
        return result

# UnixFileSystem.hashCode: path.hashCode() ^ 1234321.
@unsafe def file_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +path : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- L.int_out(vm, U32.xor(L.units_hash(L.units_from_string(path)), 1234321))
    return result

# listFiles()/list(): the host lists the directory; a missing or non-directory
# path yields null.
@unsafe def file_list(+vm: M.VM, +args: +List<M.Slot>, +files: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(U32.is_ne(U32.and(S.host_caps_of(S.host(vm)), 1), 0), "java/io/IOException")
    +receiver : U32 <- arg_ref(args, 0)
    +path : String <- binding_text(vm, receiver, 0)
    return O.Suspend{S.with_status(S.with_effect(vm, M.ListDirectory{file_absolute_text(vm, path), path, files}), 5), M.ListDirectory{file_absolute_text(vm, path), path, files}}

# Host listings arrive as UTF-16 units with 0 between names.
@unsafe def split_names(+units: +List<U32>, +current: +List<U32>, +acc: +List<+List<U32>>) -> +List<+List<U32>>:
  match units:
    case Nil{}: M.reverse(+List<U32>, Bool.pick(+List<+List<U32>>, L.chars_nonempty(current), Con{M.reverse(U32, current), acc}, acc))
    case Con{0, rest}: split_names(rest, Nil{}, Con{M.reverse(U32, current), acc})
    case Con{unit, rest}: split_names(rest, Con{unit, current}, acc)

@unsafe def directory_slots(+vm: M.VM, +parent: String, +names: +List<+List<U32>>, +files: Bool, +acc: +List<M.Slot>) -> Result<&2, &2, String, Allocated>:
  match names:
    case Nil{}: directory_array(vm, files, M.reverse(M.Slot, acc))
    case Con{+name, rest}:
      do Result<&2, &2, String, Allocated>:
        +element : Allocated <- directory_element(vm, parent, name, files)
        +result : Allocated <- directory_next(element, parent, rest, files, acc)
        return result

@unsafe def directory_next(+element: Allocated, +parent: String, +rest: +List<+List<U32>>, +files: Bool, +acc: +List<M.Slot>) -> Result<&2, &2, String, Allocated>:
  match element:
    case Allocated{+vm, +reference}: directory_slots(vm, parent, rest, files, Con{M.Slot{3, reference}, acc})

@unsafe def directory_element(+vm: M.VM, +parent: String, +name: +List<U32>, +files: Bool) -> Result<&2, &2, String, Allocated>:
  match files:
    case True{}: new_file(vm, file_resolve(parent, L.name_text(name)))
    case False{}: allocated(H.allocate(vm, H.string_entry(L.class_id(vm, "java/lang/String"), name)))

@unsafe def directory_array(+vm: M.VM, +files: Bool, +slots: +List<M.Slot>) -> Result<&2, &2, String, Allocated>:
  +array_name : String = Bool.pick(String, files, "[Ljava/io/File;", "[Ljava/lang/String;")
  +component : String = Bool.pick(String, files, "java/io/File", "java/lang/String")
  do Result<&2, &2, String, Allocated>:
    +ready : M.VM <- L.ensure_array_class(vm, array_name)
    +result : Allocated <- allocated(H.allocate(ready, H.reference_array_entry(L.class_id(ready, array_name), L.class_id(ready, component), slots)))
    return result

# Resume of ListDirectory: `count` is none() when the path is not a directory.
@unsafe def resume_directory(+vm: M.VM, +parent: String, +files: Bool, +count: U32, +units: +List<U32>) -> Result<&2, &2, String, Allocated>:
  resume_directory_listed(U32.is_eq(count, none()), vm, parent, files, units)

@unsafe def resume_directory_listed(missing: Bool, +vm: M.VM, +parent: String, +files: Bool, +units: +List<U32>) -> Result<&2, &2, String, Allocated>:
  match missing:
    case True{}: Done{Allocated{vm, 0}}
    case False{}: directory_slots(vm, parent, split_names(units, Nil{}, Nil{}), files, Nil{})

# --- java.net.URI (RFC 2396 as java.net.URI parses it) ---

type UriParts is Data:
  UriParts{scheme: String, hasScheme: Bool, ssp: String, opaque: Bool, authority: String, path: String, query: String, hasQuery: Bool, fragment: String, hasFragment: Bool}

@unsafe def uri_scheme(+parts: UriParts) -> String:
  match parts:
    case UriParts{scheme, hasScheme, ssp, opaque, authority, path, query, hasQuery, fragment, hasFragment}: scheme

@unsafe def uri_has_scheme(+parts: UriParts) -> Bool:
  match parts:
    case UriParts{scheme, hasScheme, ssp, opaque, authority, path, query, hasQuery, fragment, hasFragment}: hasScheme

@unsafe def uri_ssp(+parts: UriParts) -> String:
  match parts:
    case UriParts{scheme, hasScheme, ssp, opaque, authority, path, query, hasQuery, fragment, hasFragment}: ssp

@unsafe def uri_opaque(+parts: UriParts) -> Bool:
  match parts:
    case UriParts{scheme, hasScheme, ssp, opaque, authority, path, query, hasQuery, fragment, hasFragment}: opaque

@unsafe def uri_authority(+parts: UriParts) -> String:
  match parts:
    case UriParts{scheme, hasScheme, ssp, opaque, authority, path, query, hasQuery, fragment, hasFragment}: authority

@unsafe def uri_path(+parts: UriParts) -> String:
  match parts:
    case UriParts{scheme, hasScheme, ssp, opaque, authority, path, query, hasQuery, fragment, hasFragment}: path

@unsafe def uri_fragment(+parts: UriParts) -> Maybe<&2, String>:
  match parts:
    case UriParts{scheme, hasScheme, ssp, opaque, authority, path, query, hasQuery, fragment, hasFragment}: Bool.pick(Maybe<&2, String>, hasFragment, Some{fragment}, None{})

@unsafe def uri_query(+parts: UriParts) -> Maybe<&2, String>:
  match parts:
    case UriParts{scheme, hasScheme, ssp, opaque, authority, path, query, hasQuery, fragment, hasFragment}: Bool.pick(Maybe<&2, String>, hasQuery, Some{query}, None{})

@unsafe def scheme_char(+c: U32, +first: Bool) -> Bool:
  +letter : Bool = (U32.is_ge(c, 65) && U32.is_le(c, 90)) || (U32.is_ge(c, 97) && U32.is_le(c, 122))
  letter || (Bool.not(first) && ((U32.is_ge(c, 48) && U32.is_le(c, 57)) || U32.is_eq(c, 43) || U32.is_eq(c, 45) || U32.is_eq(c, 46)))

# The scheme's length, or none() when the text has no scheme.
@unsafe def scheme_length(+chars: +List<Char>, +index: U32) -> U32:
  match chars:
    case Nil{}: none()
    case Con{Chr{58}, rest}: Bool.pick(U32, U32.is_eq(index, 0), none(), index)
    case Con{Chr{+c}, rest}: scheme_continue(scheme_char(c, U32.is_eq(index, 0)), rest, index)

@unsafe def scheme_continue(ok: Bool, +rest: +List<Char>, +index: U32) -> U32:
  match ok:
    case True{}: scheme_length(rest, U32.add(index, 1))
    case False{}: none()

@unsafe def split_at(+text: String, +marker: U32) -> SplitText:
  +index : U32 = first_index(String.to_list(text), marker, 0)
  Bool.pick(SplitText, U32.is_eq(index, none()), SplitText{text, "", False{}}, SplitText{take_text(text, index), drop_text(text, U32.add(index, 1)), True{}})

type SplitText is Data:
  SplitText{before: String, after: String, found: Bool}

@unsafe def uri_parse(+text: String) -> UriParts:
  uri_parse_split(split_at(text, 35))

@unsafe def uri_parse_split(+split: SplitText) -> UriParts:
  match split:
    case SplitText{+body, +fragment, +hasFragment}: uri_parse_body(body, fragment, hasFragment)

@unsafe def uri_parse_body(+body: String, +fragment: String, +hasFragment: Bool) -> UriParts:
  +length : U32 = scheme_length(String.to_list(body), 0)
  +hasScheme : Bool = U32.is_ne(length, none())
  +scheme : String = Bool.pick(String, hasScheme, take_text(body, length), "")
  +ssp : String = Bool.pick(String, hasScheme, drop_text(body, U32.add(length, 1)), body)
  +opaque : Bool = hasScheme && Bool.not(String.starts_with(ssp, "/"))
  uri_hierarchy(scheme, hasScheme, ssp, opaque, fragment, hasFragment)

@unsafe def uri_hierarchy(+scheme: String, +hasScheme: Bool, +ssp: String, +opaque: Bool, +fragment: String, +hasFragment: Bool) -> UriParts:
  uri_hierarchy_split(scheme, hasScheme, ssp, opaque, fragment, hasFragment, split_at(ssp, 63))

@unsafe def uri_hierarchy_split(+scheme: String, +hasScheme: Bool, +ssp: String, +opaque: Bool, +fragment: String, +hasFragment: Bool, +split: SplitText) -> UriParts:
  match split:
    case SplitText{+before, +query, +hasQuery}:
      +authority : String = Bool.pick(String, String.starts_with(before, "//"), uri_authority_text(drop_text(before, 2)), "")
      +path : String = Bool.pick(String, String.starts_with(before, "//"), drop_text(before, U32.add(2, text_length(authority))), before)
      UriParts{scheme, hasScheme, ssp, opaque, authority, Bool.pick(String, opaque, "", path), query, hasQuery && Bool.not(opaque), fragment, hasFragment}

@unsafe def uri_authority_text(+rest: String) -> String:
  +index : U32 = first_index(String.to_list(rest), 47, 0)
  Bool.pick(String, U32.is_eq(index, none()), rest, take_text(rest, index))

# Characters java.net.URI accepts outside escapes: unreserved, reserved and
# non-ASCII "other" characters; '#' only separates the fragment.
@unsafe def uri_char_ok(+c: U32) -> Bool:
  U32.is_gt(c, 127) ||
    (U32.is_ge(c, 97) && U32.is_le(c, 122)) || (U32.is_ge(c, 65) && U32.is_le(c, 90)) || (U32.is_ge(c, 48) && U32.is_le(c, 57)) ||
    U32.is_eq(c, 45) || U32.is_eq(c, 95) || U32.is_eq(c, 46) || U32.is_eq(c, 33) || U32.is_eq(c, 126) || U32.is_eq(c, 42) || U32.is_eq(c, 39) ||
    U32.is_eq(c, 40) || U32.is_eq(c, 41) || U32.is_eq(c, 59) || U32.is_eq(c, 47) || U32.is_eq(c, 63) || U32.is_eq(c, 58) || U32.is_eq(c, 64) ||
    U32.is_eq(c, 38) || U32.is_eq(c, 61) || U32.is_eq(c, 43) || U32.is_eq(c, 36) || U32.is_eq(c, 44) || U32.is_eq(c, 37) || U32.is_eq(c, 35)

@unsafe def hex_value(+c: U32) -> U32:
  Bool.pick(U32, U32.is_ge(c, 48) && U32.is_le(c, 57), U32.sub(c, 48),
    Bool.pick(U32, U32.is_ge(c, 97) && U32.is_le(c, 102), U32.sub(c, 87),
      Bool.pick(U32, U32.is_ge(c, 65) && U32.is_le(c, 70), U32.sub(c, 55), none())))

# The first illegal character's index and the component it is in, or none().
@unsafe def uri_invalid(+chars: +List<Char>, +index: U32, +fragment: Bool) -> UriProblem:
  match chars:
    case Nil{}: UriProblem{none(), ""}
    case Con{Chr{37}, Con{Chr{+a}, Con{Chr{+b}, rest}}}:
      uri_escape_step(U32.is_ne(hex_value(a), none()) && U32.is_ne(hex_value(b), none()), rest, index, fragment)
    case Con{Chr{37}, rest}: UriProblem{index, "Malformed escape pair"}
    case Con{Chr{35}, rest}: uri_hash_step(fragment, rest, index)
    case Con{Chr{+c}, rest}: uri_char_step(uri_char_ok(c), rest, index, fragment)

type UriProblem is Data:
  UriProblem{index: U32, reason: String}

@unsafe def uri_escape_step(ok: Bool, +rest: +List<Char>, +index: U32, +fragment: Bool) -> UriProblem:
  match ok:
    case True{}: uri_invalid(rest, U32.add(index, 3), fragment)
    case False{}: UriProblem{index, "Malformed escape pair"}

@unsafe def uri_hash_step(fragment: Bool, +rest: +List<Char>, +index: U32) -> UriProblem:
  match fragment:
    case True{}: UriProblem{index, "Illegal character in fragment"}
    case False{}: uri_invalid(rest, U32.add(index, 1), True{})

@unsafe def uri_char_step(ok: Bool, +rest: +List<Char>, +index: U32, +fragment: Bool) -> UriProblem:
  match ok:
    case True{}: uri_invalid(rest, U32.add(index, 1), fragment)
    case False{}: UriProblem{index, Bool.pick(String, fragment, "Illegal character in fragment", "Illegal character in path")}

# Decode %XX escapes as UTF-8 (java.net.URI.decode).
@unsafe def percent_bytes(+chars: +List<Char>) -> +List<U32>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{37}, Con{Chr{+a}, Con{Chr{+b}, rest}}}: Con{U32.add(U32.shln(hex_value(a), 4n), hex_value(b)), percent_bytes(rest)}
    case Con{Chr{+c}, rest}: M.append(U32, utf8_of(c), percent_bytes(rest))

@unsafe def utf8_of(+c: U32) -> +List<U32>:
  Bool.pick(+List<U32>, U32.is_lt(c, 128), [c],
    Bool.pick(+List<U32>, U32.is_lt(c, 2048), [U32.or(192, U32.shrn(c, 6n)), U32.or(128, U32.and(c, 63))],
      Bool.pick(+List<U32>, U32.is_lt(c, 65536), [U32.or(224, U32.shrn(c, 12n)), U32.or(128, U32.and(U32.shrn(c, 6n), 63)), U32.or(128, U32.and(c, 63))],
        [U32.or(240, U32.shrn(c, 18n)), U32.or(128, U32.and(U32.shrn(c, 12n), 63)), U32.or(128, U32.and(U32.shrn(c, 6n), 63)), U32.or(128, U32.and(c, 63))])))

# The sequence length a UTF-8 lead byte announces (1 for ASCII or invalid).
@unsafe def utf8_width(+b0: U32) -> U32:
  Bool.pick(U32, U32.is_ge(b0, 240) && U32.is_lt(b0, 248), 4,
    Bool.pick(U32, U32.is_ge(b0, 224), 3, Bool.pick(U32, U32.is_ge(b0, 192), 2, 1)))

@unsafe def continuation(+b: U32) -> U32:
  U32.and(b, 63)

# Decoding dispatches with match: Bool.pick would evaluate every recursive
# alternative eagerly in the generated code.
@unsafe def utf8_decode(+bytes: +List<U32>) -> +List<Char>:
  match bytes:
    case Nil{}: Nil{}
    case Con{+b0, rest}: utf8_sequence(utf8_width(b0), b0, rest)

@unsafe def utf8_sequence(width: U32, +b0: U32, +rest: +List<U32>) -> +List<Char>:
  match width:
    case 4:
      match rest:
        case Con{+b1, Con{+b2, Con{+b3, more}}}: Con{Chr{U32.or(U32.shln(U32.and(b0, 7), 18n), U32.or(U32.shln(continuation(b1), 12n), U32.or(U32.shln(continuation(b2), 6n), continuation(b3))))}, utf8_decode(more)}
        case _: Con{Chr{65533}, utf8_decode(rest)}
    case 3:
      match rest:
        case Con{+b1, Con{+b2, more}}: Con{Chr{U32.or(U32.shln(U32.and(b0, 15), 12n), U32.or(U32.shln(continuation(b1), 6n), continuation(b2)))}, utf8_decode(more)}
        case _: Con{Chr{65533}, utf8_decode(rest)}
    case 2:
      match rest:
        case Con{+b1, more}: Con{Chr{U32.or(U32.shln(U32.and(b0, 31), 6n), continuation(b1))}, utf8_decode(more)}
        case _: Con{Chr{65533}, utf8_decode(rest)}
    case _: Con{Chr{Bool.pick(U32, U32.is_lt(b0, 128), b0, 65533)}, utf8_decode(rest)}

@unsafe def percent_decode(+text: String) -> String:
  String.from_list(utf8_decode(percent_bytes(String.to_list(text))))

@unsafe def lower_chars(+chars: +List<Char>) -> +List<Char>:
  match chars:
    case Nil{}: Nil{}
    case Con{Chr{+c}, rest}: Con{Chr{Bool.pick(U32, U32.is_ge(c, 65) && U32.is_le(c, 90), U32.add(c, 32), c)}, lower_chars(rest)}

@unsafe def uri_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +text_ref : U32 <- arg_ref(args, 1)
    checked : Unit <- S.check(U32.is_ne(text_ref, 0), L.npe())
    +text : String <- L.string_text(vm, text_ref)
    +problem : UriProblem = uri_invalid(String.to_list(text), 0, False{})
    valid : Unit <- uri_check(problem, text)
    +entry : M.HeapEntry <- H.get(S.heap(vm), receiver)
    +result : O.Outcome <- L.void_out(H.put(vm, receiver, H.object_entry(H.entry_class(entry), [M.Binding{0, M.Slot{3, text_ref}}])))
    return result

@unsafe def uri_check(+problem: UriProblem, +text: String) -> Result<&2, &2, String, Unit>:
  match problem:
    case UriProblem{+index, +reason}:
      Bool.pick(Result<&2, &2, String, Unit>, U32.is_eq(index, none()), Done{Unit{}},
        Fail{"java/net/URISyntaxException: " ++ reason ++ " at index " ++ V.int_show(index) ++ ": " ++ text})

@unsafe def uri_text(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +receiver : U32 <- arg_ref(args, 0)
    +text : String <- binding_text(vm, receiver, 0)
    return text

@unsafe def optional_out(+vm: M.VM, found: Maybe<&2, String>) -> Result<&2, &2, String, O.Outcome>:
  match found:
    case None{}: L.ref_out(vm, 0)
    case Some{+text}: text_out(vm, text)

# op: 0 scheme, 1 decoded ssp, 2 raw ssp, 3 decoded path, 4 raw path,
# 5 decoded fragment, 6 raw query, 7 string.
@unsafe def uri_component(+parts: UriParts, +op: U32, +text: String) -> Maybe<&2, String>:
  match op:
    case 0: Bool.pick(Maybe<&2, String>, uri_has_scheme(parts), Some{uri_scheme(parts)}, None{})
    case 1: Some{percent_decode(uri_ssp(parts))}
    case 2: Some{uri_ssp(parts)}
    case 3: Bool.pick(Maybe<&2, String>, uri_opaque(parts), None{}, Some{percent_decode(uri_path(parts))})
    case 4: Bool.pick(Maybe<&2, String>, uri_opaque(parts), None{}, Some{uri_path(parts)})
    case 5: uri_decoded(uri_fragment(parts))
    case 6: uri_query(parts)
    case _: Some{text}

@unsafe def uri_decoded(found: Maybe<&2, String>) -> Maybe<&2, String>:
  match found:
    case None{}: None{}
    case Some{+text}: Some{percent_decode(text)}

@unsafe def uri_get(+vm: M.VM, +args: +List<M.Slot>, +op: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +text : String <- uri_text(vm, args)
    +result : O.Outcome <- optional_out(vm, uri_component(uri_parse(text), op, text))
    return result

@unsafe def uri_flag(+vm: M.VM, +args: +List<M.Slot>, +opaque: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +text : String <- uri_text(vm, args)
    +parts : UriParts = uri_parse(text)
    +result : O.Outcome <- L.bool_out(vm, Bool.pick(Bool, opaque, uri_opaque(parts), uri_has_scheme(parts)))
    return result

@unsafe def uri_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +text : String <- uri_text(vm, args)
    +other : U32 <- arg_ref(args, 1)
    +result : O.Outcome <- same_class_text(vm, other, "java/net/URI", text)
    return result

@unsafe def same_class_text(+vm: M.VM, +other: U32, +class: String, +text: String) -> Result<&2, &2, String, O.Outcome>:
  match other:
    case 0: L.bool_out(vm, False{})
    case +ref:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), ref)
        +result : O.Outcome <- same_class_compare(U32.is_eq(H.entry_class(entry), L.class_id(vm, class)), vm, ref, class, text)
        return result

@unsafe def same_class_compare(same: Bool, +vm: M.VM, +other: U32, +class: String, +text: String) -> Result<&2, &2, String, O.Outcome>:
  match same:
    case False{}: L.bool_out(vm, False{})
    case True{}:
      do Result<&2, &2, String, O.Outcome>:
        +other_text : String <- Bool.pick(Result<&2, &2, String, String>, String.eq(class, "java/net/URL"), url_spec_of(vm, other), binding_text(vm, other, 0))
        +result : O.Outcome <- L.bool_out(vm, String.eq(text, other_text))
        return result

@unsafe def uri_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +text : String <- uri_text(vm, args)
    +result : O.Outcome <- L.int_out(vm, L.units_hash(L.units_from_string(text)))
    return result

@unsafe def uri_to_url(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +text : String <- uri_text(vm, args)
    +parts : UriParts = uri_parse(text)
    absolute : Unit <- S.check(uri_has_scheme(parts), "java/lang/IllegalArgumentException: URI is not absolute")
    +result : O.Outcome <- allocated_out(new_url(vm, text))
    return result

# --- java.net.URL: the external form is the source of truth ---
# Bindings: 0 classpath resource name (or null), 1 origin (decoded file path or
# "archive!/entry"), 2 spec. Classpath resource URLs carry 0 and 1 and derive
# their spec; constructed URLs carry the spec and derive the origin.

@unsafe def url_spec_of(+vm: M.VM, +url: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +spec_ref : U32 <- binding_ref(vm, url, 2)
    +origin : String <- binding_text_optional(vm, url, 1)
    +spec : String <- url_spec_select(vm, spec_ref, origin)
    return spec

@unsafe def binding_text_optional(+vm: M.VM, +reference: U32, +index: U32) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +value : U32 <- binding_ref(vm, reference, index)
    +text : String <- optional_text(vm, value)
    return text

@unsafe def url_spec_select(+vm: M.VM, +spec_ref: U32, +origin: String) -> Result<&2, &2, String, String>:
  match spec_ref:
    case 0: Done{L.url_external_info(L.url_origin_info(origin))}
    case +ref: L.string_text(vm, ref)

@unsafe def url_protocol_text(+spec: String) -> String:
  String.from_list(lower_chars(String.to_list(take_text(spec, first_index(String.to_list(spec), 58, 0)))))

# The part after "protocol:", without query or reference.
@unsafe def url_after_protocol(+spec: String) -> String:
  drop_text(spec, U32.add(first_index(String.to_list(spec), 58, 0), 1))

@unsafe def split_before(+split: SplitText) -> String:
  match split:
    case SplitText{+before, +after, +found}: before

@unsafe def split_after(+split: SplitText) -> Maybe<&2, String>:
  match split:
    case SplitText{+before, +after, +found}: Bool.pick(Maybe<&2, String>, found, Some{after}, None{})

@unsafe def strip_ref(+text: String) -> String:
  split_before(split_at(text, 35))

@unsafe def url_ref_text(+spec: String) -> Maybe<&2, String>:
  split_after(split_at(spec, 35))

@unsafe def strip_query(+text: String) -> String:
  split_before(split_at(text, 63))

@unsafe def url_query_text(+spec: String) -> Maybe<&2, String>:
  split_after(split_at(strip_ref(spec), 63))

# getFile: the path and query; "//host" authorities are not part of it.
@unsafe def url_file_text(+spec: String) -> String:
  +rest : String = strip_ref(url_after_protocol(spec))
  Bool.pick(String, String.eq(url_protocol_text(spec), "jar"), rest,
    Bool.pick(String, String.starts_with(rest, "//"), url_after_authority(drop_text(rest, 2)), rest))

@unsafe def url_after_authority(+rest: String) -> String:
  +index : U32 = first_index(String.to_list(rest), 47, 0)
  Bool.pick(String, U32.is_eq(index, none()), "", drop_text(rest, index))

@unsafe def url_host_text(+spec: String) -> String:
  +rest : String = strip_ref(url_after_protocol(spec))
  Bool.pick(String, String.starts_with(rest, "//") && Bool.not(String.eq(url_protocol_text(spec), "jar")), uri_authority_text(drop_text(rest, 2)), "")

# The decoded origin a file or jar spec names ("path" or "archive!/entry").
@unsafe def url_origin_from_spec(+spec: String) -> String:
  +file : String = strip_query(url_file_text(spec))
  Bool.pick(String, String.eq(url_protocol_text(spec), "jar"), jar_origin(strip_query(url_file_text(spec))), percent_decode(file))

@unsafe def jar_origin(+file: String) -> String:
  +inner : String = Bool.pick(String, String.starts_with(file, "file:"), url_file_text(take_text(file, bang_slash(String.to_list(file), 0))), take_text(file, bang_slash(String.to_list(file), 0)))
  percent_decode(inner) ++ "!/" ++ percent_decode(drop_text(file, U32.add(bang_slash(String.to_list(file), 0), 2)))

@unsafe def known_protocol(+protocol: String) -> Bool:
  String.eq(protocol, "file") || String.eq(protocol, "jar") || String.eq(protocol, "http") || String.eq(protocol, "https") || String.eq(protocol, "ftp")

# The classpath resource whose origin a URL names, if any.
@unsafe def resource_name_for(+resources: +List<M.Resource>, +origin: String) -> Maybe<&2, String>:
  match resources:
    case Nil{}: None{}
    case Con{M.Resource{+name, +resource_origin}, rest}: resource_name_step(String.eq(resource_origin, origin), name, rest, origin)

@unsafe def resource_name_step(hit: Bool, +name: String, +rest: +List<M.Resource>, +origin: String) -> Maybe<&2, String>:
  match hit:
    case True{}: Some{name}
    case False{}: resource_name_for(rest, origin)

@unsafe def new_url(+vm: M.VM, +spec: String) -> Result<&2, &2, String, Allocated>:
  do Result<&2, &2, String, Allocated>:
    +protocol : String = url_protocol_text(spec)
    has_protocol : Unit <- S.check(U32.is_ne(first_index(String.to_list(spec), 58, 0), none()), "java/net/MalformedURLException: no protocol: " ++ spec)
    known : Unit <- S.check(known_protocol(protocol), "java/net/MalformedURLException: unknown protocol: " ++ protocol)
    jar_ok : Unit <- S.check(Bool.not(String.eq(protocol, "jar")) || U32.is_ne(bang_slash(String.to_list(spec), 0), none()), "java/net/MalformedURLException: no !/ in spec")
    +origin : String = Bool.pick(String, String.eq(protocol, "file") || String.eq(protocol, "jar"), url_origin_from_spec(spec), "")
    +result : Allocated <- alloc_url(vm, resource_name_for(S.resources(vm), origin), origin, spec)
    return result

@unsafe def alloc_url(+vm: M.VM, found: Maybe<&2, String>, +origin: String, +spec: String) -> Result<&2, &2, String, Allocated>:
  match found:
    case Some{+name}: alloc_text_object(vm, "java/net/URL", [name, origin, spec], Nil{})
    case None{}:
      do Result<&2, &2, String, Allocated>:
        +object : Allocated <- alloc_text_object(vm, "java/net/URL", [origin, spec], Nil{})
        +result : Allocated <- url_shift(object)
        return result

# Without a resource name the strings sit at 0 and 1; move them to 1 and 2.
@unsafe def url_shift(+object: Allocated) -> Result<&2, &2, String, Allocated>:
  match object:
    case Allocated{+vm, +reference}:
      do Result<&2, &2, String, Allocated>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
        +fields : +List<M.Binding> = L.entry_fields(entry)
        +origin : U32 = L.field_bits(fields, 0)
        +spec : U32 = L.field_bits(fields, 1)
        return Allocated{H.put(vm, reference, H.object_entry(H.entry_class(entry), [M.Binding{0, M.Slot{3, 0}}, M.Binding{1, M.Slot{3, origin}}, M.Binding{2, M.Slot{3, spec}}])), reference}

@unsafe def url_init_object(+vm: M.VM, +receiver: U32, +created: Allocated) -> Result<&2, &2, String, O.Outcome>:
  match created:
    case Allocated{+next, +reference}:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(next), reference)
        +result : O.Outcome <- L.void_out(H.put(next, receiver, entry))
        return result

@unsafe def url_init(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +spec_ref : U32 <- arg_ref(args, 1)
    present : Unit <- S.check(U32.is_ne(spec_ref, 0), "java/net/MalformedURLException")
    +spec : String <- L.string_text(vm, spec_ref)
    +created : Allocated <- new_url(vm, spec)
    +result : O.Outcome <- url_init_object(vm, receiver, created)
    return result

# Remove "." and ".." segments (URLStreamHandler.parseURL).
@unsafe def canonical_segments(+segments: +List<String>, +acc: +List<String>) -> +List<String>:
  match segments:
    case Nil{}: M.reverse(String, acc)
    case Con{+segment, rest}: canonical_step(segment, rest, acc)

@unsafe def canonical_step(+segment: String, +rest: +List<String>, +acc: +List<String>) -> +List<String>:
  match segment:
    case ".": canonical_segments(rest, Bool.pick(+List<String>, strings_nonempty(rest), acc, Con{"", acc}))
    case "..": canonical_segments(rest, Bool.pick(+List<String>, strings_nonempty(rest), drop_one(acc), Con{"", drop_one(acc)}))
    case _: canonical_segments(rest, Con{segment, acc})

@unsafe def strings_nonempty(+values: +List<String>) -> Bool:
  match values:
    case Nil{}: False{}
    case _: True{}

@unsafe def drop_one(+values: +List<String>) -> +List<String>:
  match values:
    case Con{head, Con{next, rest}}: Con{next, rest}
    case other: other

@unsafe def split_segments(+chars: +List<Char>, +current: +List<Char>, +acc: +List<String>) -> +List<String>:
  match chars:
    case Nil{}: M.reverse(String, Con{String.from_list(M.reverse(Char, current)), acc})
    case Con{Chr{47}, rest}: split_segments(rest, Nil{}, Con{String.from_list(M.reverse(Char, current)), acc})
    case Con{c, rest}: split_segments(rest, Con{c, current}, acc)

@unsafe def join_segments(+segments: +List<String>, +first: Bool) -> String:
  match segments:
    case Nil{}: ""
    case Con{+segment, rest}: Bool.pick(String, first, "", "/") ++ segment ++ join_segments(rest, False{})

@unsafe def canonical_path(+path: String) -> String:
  join_segments(canonical_segments(split_segments(String.to_list(path), Nil{}, Nil{}), Nil{}), True{})

# A path relative to `base`: absolute specs replace it; otherwise the base's
# last segment is replaced and dot segments are removed.
@unsafe def resolve_relative(+base: String, +spec: String) -> String:
  Bool.pick(String, String.starts_with(spec, "/"), canonical_path(spec),
    canonical_path(take_text(base, U32.add(last_index(String.to_list(base), 47, 0, none()), 1)) ++ spec))

@unsafe def url_context_spec(+context: String, +spec: String) -> String:
  +protocol : String = url_protocol_text(context)
  Bool.pick(String, String.eq(protocol, "jar"), jar_context_spec(context, spec),
    protocol ++ ":" ++ url_authority_prefix(context) ++ resolve_relative(strip_query(url_file_text(context)), spec))

@unsafe def url_authority_prefix(+context: String) -> String:
  +rest : String = url_after_protocol(context)
  Bool.pick(String, String.starts_with(rest, "//"), "//" ++ url_host_text(context), "")

# The jar handler resolves inside the entry path after "!/".
@unsafe def jar_context_spec(+context: String, +spec: String) -> String:
  +bang : U32 = bang_slash(String.to_list(context), 0)
  +prefix : String = take_text(context, U32.add(bang, 1))
  +entry : String = drop_text(strip_ref(context), U32.add(bang, 1))
  prefix ++ resolve_relative(entry, spec)

@unsafe def has_scheme_text(+spec: String) -> Bool:
  U32.is_ne(scheme_length(String.to_list(spec), 0), none())

@unsafe def url_init_context(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +context : U32 <- arg_ref(args, 1)
    +spec : String <- text_arg(vm, args, 2)
    +context_spec : String <- url_context_text(vm, context)
    +absolute : Bool = has_scheme_text(spec) || U32.is_eq(context, 0)
    +created : Allocated <- new_url(vm, Bool.pick(String, absolute, spec, url_context_spec(context_spec, spec)))
    +result : O.Outcome <- url_init_object(vm, receiver, created)
    return result

@unsafe def url_context_text(+vm: M.VM, +context: U32) -> Result<&2, &2, String, String>:
  match context:
    case 0: Done{""}
    case +ref: url_spec_of(vm, ref)

@unsafe def url_spec_arg(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +receiver : U32 <- arg_ref(args, 0)
    +spec : String <- url_spec_of(vm, receiver)
    return spec

# op: 0 toString, 1 protocol, 2 path, 3 file, 4 host, 5 ref, 6 query.
@unsafe def url_component(+spec: String, +op: U32) -> Maybe<&2, String>:
  match op:
    case 0: Some{spec}
    case 1: Some{url_protocol_text(spec)}
    case 2: Some{strip_query(url_file_text(spec))}
    case 3: Some{url_file_text(spec)}
    case 4: Some{url_host_text(spec)}
    case 5: url_ref_text(spec)
    case _: url_query_text(spec)

@unsafe def url_get(+vm: M.VM, +args: +List<M.Slot>, +op: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +spec : String <- url_spec_arg(vm, args)
    +result : O.Outcome <- optional_out(vm, url_component(spec, op))
    return result

@unsafe def url_port(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.int_out(vm, none())

@unsafe def url_equals(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +spec : String <- url_spec_arg(vm, args)
    +other : U32 <- arg_ref(args, 1)
    +result : O.Outcome <- same_class_text(vm, other, "java/net/URL", spec)
    return result

@unsafe def url_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +spec : String <- url_spec_arg(vm, args)
    +result : O.Outcome <- L.int_out(vm, L.units_hash(L.units_from_string(spec)))
    return result

@unsafe def url_to_uri(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +spec : String <- url_spec_arg(vm, args)
    valid : Unit <- uri_check(uri_invalid(String.to_list(spec), 0, False{}), spec)
    +result : O.Outcome <- allocated_out(alloc_text_object(vm, "java/net/URI", [spec], Nil{}))
    return result

# Reading a URL: a classpath resource reads through the class path; any other
# file or jar entry is read by the host (file access capability required).
@unsafe def url_read(+vm: M.VM, +url: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +name_ref : U32 <- binding_ref(vm, url, 0)
    +origin : String <- binding_text_optional(vm, url, 1)
    +spec : String <- url_spec_of(vm, url)
    +result : O.Outcome <- url_read_named(vm, name_ref, origin, spec)
    return result

@unsafe def url_read_named(+vm: M.VM, +name_ref: U32, +origin: String, +spec: String) -> Result<&2, &2, String, O.Outcome>:
  match name_ref:
    case 0: path_read(vm, origin, url_protocol_text(spec))
    case +ref:
      do Result<&2, &2, String, O.Outcome>:
        +name : String <- L.string_text(vm, ref)
        +result : O.Outcome <- L.resource_stream_found(vm, L.resource_find_exact(S.resources(vm), name, origin))
        return result

@unsafe def path_read(+vm: M.VM, +origin: String, +protocol: String) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    supported : Unit <- S.check(String.eq(protocol, "file") || String.eq(protocol, "jar"), "java/io/IOException: unsupported protocol " ++ protocol)
    allowed : Unit <- S.check(U32.is_ne(U32.and(S.host_caps_of(S.host(vm)), 1), 0), "java/io/IOException")
    +bang : U32 = bang_slash(String.to_list(origin), 0)
    +archive : Bool = U32.is_ne(bang, none())
    +path : String = Bool.pick(String, archive, take_text(origin, bang), origin)
    +entry : String = Bool.pick(String, archive, drop_text(origin, U32.add(bang, 2)), "")
    return O.Suspend{S.with_status(S.with_effect(vm, M.ReadPathBytes{path, entry}), 5), M.ReadPathBytes{path, entry}}

@unsafe def url_open_stream(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +result : O.Outcome <- url_read(vm, receiver)
    return result

# --- URLConnection, JarURLConnection ---
# Bindings: 0 URL, 1 useCaches, 2 cached JarFile (jar connections).

@unsafe def url_open_connection(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +spec : String <- url_spec_of(vm, receiver)
    +protocol : String = url_protocol_text(spec)
    supported : Unit <- S.check(String.eq(protocol, "file") || String.eq(protocol, "jar"), "java/io/IOException: unsupported protocol " ++ protocol)
    +class : String = Bool.pick(String, String.eq(protocol, "jar"), "sun/net/www/protocol/jar/JarURLConnection", "sun/net/www/protocol/file/FileURLConnection")
    +result : O.Outcome <- allocated_out(allocated(H.allocate(vm, H.object_entry(L.class_id(vm, class), [M.Binding{0, M.Slot{3, receiver}}, M.Binding{1, M.Slot{1, 1}}, M.Binding{2, M.Slot{3, 0}}]))))
    return result

@unsafe def connection_url(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +receiver : U32 <- arg_ref(args, 0)
    +url : U32 <- binding_ref(vm, receiver, 0)
    return url

@unsafe def connection_input(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +url : U32 <- connection_url(vm, args)
    +result : O.Outcome <- url_read(vm, url)
    return result

@unsafe def connection_get_url(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +url : U32 <- connection_url(vm, args)
    +result : O.Outcome <- L.ref_out(vm, url)
    return result

@unsafe def set_binding(+vm: M.VM, +reference: U32, +index: U32, +value: M.Slot) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    +entry : M.HeapEntry <- H.get(S.heap(vm), reference)
    return H.put(vm, reference, H.object_entry(H.entry_class(entry), H.binding_set(L.entry_fields(entry), index, value)))

@unsafe def connection_set_caches(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +flag : U32 <- arg_ref(args, 1)
    +updated : M.VM <- set_binding(vm, receiver, 1, M.Slot{1, flag})
    +result : O.Outcome <- L.void_out(updated)
    return result

@unsafe def connection_get_caches(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +flag : U32 <- binding_ref(vm, receiver, 1)
    +result : O.Outcome <- L.bool_out(vm, U32.is_ne(flag, 0))
    return result

@unsafe def connection_connect(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  L.void_out(vm)

@unsafe def jar_spec_parts(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, String>:
  do Result<&2, &2, String, String>:
    +url : U32 <- connection_url(vm, args)
    +spec : String <- url_spec_of(vm, url)
    return spec

# getJarFileURL: the URL before "!/" (without "jar:").
@unsafe def jar_file_url(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +spec : String <- jar_spec_parts(vm, args)
    +inner : String = take_text(url_after_protocol(spec), bang_slash(String.to_list(url_after_protocol(spec)), 0))
    +result : O.Outcome <- allocated_out(new_url(vm, inner))
    return result

@unsafe def jar_entry_text(+spec: String) -> String:
  +file : String = strip_query(url_file_text(spec))
  percent_decode(drop_text(file, U32.add(bang_slash(String.to_list(file), 0), 2)))

@unsafe def jar_entry_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +spec : String <- jar_spec_parts(vm, args)
    +entry : String = jar_entry_text(spec)
    +result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, String.is_empty(entry), L.ref_out(vm, 0), text_out(vm, entry))
    return result

@unsafe def jar_archive_path(+spec: String) -> String:
  +origin : String = url_origin_from_spec(spec)
  take_text(origin, bang_slash(String.to_list(origin), 0))

# getJarFile/getJarEntry list the archive once per connection (ListArchive op 1
# pushes the JarFile, op 2 the connection's entry).
@unsafe def jar_connection_file(+vm: M.VM, +args: +List<M.Slot>, +op: U32) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +cached : U32 <- binding_ref(vm, receiver, 2)
    +spec : String <- jar_spec_parts(vm, args)
    +result : O.Outcome <- jar_connection_cached(vm, receiver, cached, spec, op)
    return result

@unsafe def jar_connection_cached(+vm: M.VM, +connection: U32, +cached: U32, +spec: String, +op: U32) -> Result<&2, &2, String, O.Outcome>:
  match cached:
    case 0:
      do Result<&2, &2, String, O.Outcome>:
        allowed : Unit <- S.check(U32.is_ne(U32.and(S.host_caps_of(S.host(vm)), 1), 0), "java/io/IOException")
        +path : String = jar_archive_path(spec)
        +jar : Allocated <- alloc_text_object(vm, "java/util/jar/JarFile", [path], [M.Binding{1, M.Slot{3, 0}}, M.Binding{2, M.Slot{1, 0}}])
        +result : O.Outcome <- jar_list_suspend(jar, path, op, connection, jar_entry_text(spec))
        return result
    case +jar: jar_connection_answer(vm, connection, jar, jar_entry_text(spec), op)

@unsafe def jar_list_suspend(+jar: Allocated, +path: String, +op: U32, +connection: U32, +entry: String) -> Result<&2, &2, String, O.Outcome>:
  match jar:
    case Allocated{+vm, +reference}:
      Done{O.Suspend{S.with_status(S.with_effect(vm, M.ListArchive{path, reference, op, connection, entry}), 5), M.ListArchive{path, reference, op, connection, entry}}}

@unsafe def jar_connection_answer(+vm: M.VM, +connection: U32, +jar: U32, +entry: String, +op: U32) -> Result<&2, &2, String, O.Outcome>:
  match op:
    case 1: L.ref_out(vm, jar)
    case _: jar_entry_lookup_out(vm, jar, entry)

@unsafe def jar_entry_lookup_out(+vm: M.VM, +jar: U32, +entry: String) -> Result<&2, &2, String, O.Outcome>:
  jar_entry_lookup_select(String.is_empty(entry), vm, jar, entry)

@unsafe def jar_entry_lookup_select(empty: Bool, +vm: M.VM, +jar: U32, +entry: String) -> Result<&2, &2, String, O.Outcome>:
  match empty:
    case True{}: L.ref_out(vm, 0)
    case False{}:
      do Result<&2, &2, String, O.Outcome>:
        +found : U32 <- zip_find(vm, jar, entry)
        present : Unit <- S.check(U32.is_ne(found, 0), "java/io/FileNotFoundException: JAR entry " ++ entry ++ " not found")
        +result : O.Outcome <- L.ref_out(vm, found)
        return result

@unsafe def jar_get_file(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  jar_connection_file(vm, args, 1)

@unsafe def jar_get_entry(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  jar_connection_file(vm, args, 2)

# --- ZipFile / JarFile / ZipEntry ---
# ZipFile bindings: 0 name, 1 ArrayList of entries, 2 closed. ZipEntry: 0 name.

@unsafe def zip_init(+vm: M.VM, +args: +List<M.Slot>, +from_file: Bool) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    allowed : Unit <- S.check(U32.is_ne(U32.and(S.host_caps_of(S.host(vm)), 1), 0), "java/io/IOException")
    +receiver : U32 <- arg_ref(args, 0)
    +source : U32 <- arg_ref(args, 1)
    checked : Unit <- S.check(U32.is_ne(source, 0), L.npe())
    +path : String <- Bool.pick(Result<&2, &2, String, String>, from_file, binding_text(vm, source, 0), L.string_text(vm, source))
    +name : Allocated <- alloc_string(vm, path)
    +result : O.Outcome <- zip_init_named(name, receiver, file_absolute_text(vm, path))
    return result

@unsafe def zip_init_named(+name: Allocated, +receiver: U32, +absolute: String) -> Result<&2, &2, String, O.Outcome>:
  match name:
    case Allocated{+vm, +reference}:
      do Result<&2, &2, String, O.Outcome>:
        +entry : M.HeapEntry <- H.get(S.heap(vm), receiver)
        +ready : M.VM = H.put(vm, receiver, H.object_entry(H.entry_class(entry), [M.Binding{0, M.Slot{3, reference}}, M.Binding{1, M.Slot{3, 0}}, M.Binding{2, M.Slot{1, 0}}]))
        return O.Suspend{S.with_status(S.with_effect(ready, M.ListArchive{absolute, receiver, 0, 0, ""}), 5), M.ListArchive{absolute, receiver, 0, 0, ""}}

@unsafe def entry_objects(+vm: M.VM, +names: +List<+List<U32>>, +acc: +List<M.Slot>) -> Result<&2, &2, String, EntryObjects>:
  match names:
    case Nil{}: Done{EntryObjects{vm, M.reverse(M.Slot, acc)}}
    case Con{+name, rest}:
      do Result<&2, &2, String, EntryObjects>:
        +text : Allocated <- allocated(H.allocate(vm, H.string_entry(L.class_id(vm, "java/lang/String"), name)))
        +object : Allocated <- entry_object(text)
        +result : EntryObjects <- entry_objects_next(object, rest, acc)
        return result

type EntryObjects is Data:
  EntryObjects{vm: M.VM, slots: +List<M.Slot>}

@unsafe def entry_object(+text: Allocated) -> Result<&2, &2, String, Allocated>:
  match text:
    case Allocated{+vm, +reference}: allocated(H.allocate(vm, H.object_entry(L.class_id(vm, "java/util/jar/JarEntry"), [M.Binding{0, M.Slot{3, reference}}])))

@unsafe def entry_objects_next(+object: Allocated, +rest: +List<+List<U32>>, +acc: +List<M.Slot>) -> Result<&2, &2, String, EntryObjects>:
  match object:
    case Allocated{+vm, +reference}: entry_objects(vm, rest, Con{M.Slot{3, reference}, acc})

# Resume of ListArchive: store the entries, then finish per op (0 constructor,
# 1 push the JarFile, 2 push the connection's entry).
@unsafe def resume_archive(+vm: M.VM, +jar: U32, +op: U32, +connection: U32, +entry: String, +units: +List<U32>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +objects : EntryObjects <- entry_objects(vm, split_names(units, Nil{}, Nil{}), Nil{})
    +result : O.Outcome <- resume_archive_store(objects, jar, op, connection, entry)
    return result

@unsafe def resume_archive_store(+objects: EntryObjects, +jar: U32, +op: U32, +connection: U32, +entry: String) -> Result<&2, &2, String, O.Outcome>:
  match objects:
    case EntryObjects{+vm, +slots}:
      do Result<&2, &2, String, O.Outcome>:
        +list : Allocated <- allocated(H.allocate(vm, H.list_entry(L.class_id(vm, "java/util/ArrayList"), slots, M.length(M.Slot, slots), 0)))
        +result : O.Outcome <- resume_archive_list(list, jar, op, connection, entry)
        return result

@unsafe def resume_archive_list(+list: Allocated, +jar: U32, +op: U32, +connection: U32, +entry: String) -> Result<&2, &2, String, O.Outcome>:
  match list:
    case Allocated{+vm, +reference}:
      do Result<&2, &2, String, O.Outcome>:
        +stored : M.VM <- set_binding(vm, jar, 1, M.Slot{3, reference})
        +cached : M.VM <- Bool.pick(Result<&2, &2, String, M.VM>, U32.is_eq(connection, 0), Done{stored}, set_binding(stored, connection, 2, M.Slot{3, jar}))
        +result : O.Outcome <- Bool.pick(Result<&2, &2, String, O.Outcome>, U32.is_eq(op, 0), L.void_out(cached), jar_connection_answer(cached, connection, jar, entry, op))
        return result

@unsafe def zip_list(+vm: M.VM, +jar: U32) -> Result<&2, &2, String, +List<M.Slot>>:
  do Result<&2, &2, String, +List<M.Slot>>:
    +closed : U32 <- binding_ref(vm, jar, 2)
    open : Unit <- S.check(U32.is_eq(closed, 0), "java/lang/IllegalStateException: zip file closed")
    +list : U32 <- binding_ref(vm, jar, 1)
    +entry : M.HeapEntry <- H.get(S.heap(vm), list)
    return M.take(M.Slot, L.entry_values(entry), U32.to_nat(L.entry_element(entry)))

@unsafe def entry_named(+vm: M.VM, +entries: +List<M.Slot>, +name: String) -> U32:
  match entries:
    case Nil{}: 0
    case Con{+slot, rest}: entry_named_step(String.eq(entry_text(vm, bits(slot)), name), slot, vm, rest, name)

@unsafe def entry_named_step(hit: Bool, +slot: M.Slot, +vm: M.VM, +rest: +List<M.Slot>, +name: String) -> U32:
  match hit:
    case True{}: bits(slot)
    case False{}: entry_named(vm, rest, name)

@unsafe def entry_text(+vm: M.VM, +reference: U32) -> String:
  text_or_empty(binding_text(vm, reference, 0))

@unsafe def text_or_empty(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{error}: ""

# ZipFile.getEntry: an exact match, else the directory entry name + "/".
@unsafe def zip_find(+vm: M.VM, +jar: U32, +name: String) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +entries : +List<M.Slot> <- zip_list(vm, jar)
    +exact : U32 = entry_named(vm, entries, name)
    return Bool.pick(U32, U32.is_ne(exact, 0) || String.ends_with(name, "/"), exact, entry_named(vm, entries, name ++ "/"))

@unsafe def zip_get_entry(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name : String <- text_arg(vm, args, 1)
    +found : U32 <- zip_find(vm, receiver, name)
    +result : O.Outcome <- L.ref_out(vm, found)
    return result

@unsafe def zip_entries(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +entries : +List<M.Slot> <- zip_list(vm, receiver)
    +list : U32 <- binding_ref(vm, receiver, 1)
    +result : O.Outcome <- allocated_out(allocated(H.allocate(vm, H.object_entry(L.class_id(vm, "java/util/ResourceEnumeration"), [M.Binding{0, M.Slot{3, list}}, M.Binding{1, M.Slot{1, 0}}]))))
    return result

@unsafe def zip_size(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +entries : +List<M.Slot> <- zip_list(vm, receiver)
    +result : O.Outcome <- L.int_out(vm, M.length(M.Slot, entries))
    return result

@unsafe def zip_input(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +entry : U32 <- arg_ref(args, 1)
    checked : Unit <- S.check(U32.is_ne(entry, 0), L.npe())
    +entries : +List<M.Slot> <- zip_list(vm, receiver)
    +path : String <- binding_text(vm, receiver, 0)
    +name : String <- binding_text(vm, entry, 0)
    allowed : Unit <- S.check(U32.is_ne(U32.and(S.host_caps_of(S.host(vm)), 1), 0), "java/io/IOException")
    +absolute : String = file_absolute_text(vm, path)
    return O.Suspend{S.with_status(S.with_effect(vm, M.ReadPathBytes{absolute, name}), 5), M.ReadPathBytes{absolute, name}}

@unsafe def zip_close(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +updated : M.VM <- set_binding(vm, receiver, 2, M.Slot{1, 1})
    +result : O.Outcome <- L.void_out(updated)
    return result

@unsafe def zip_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name : U32 <- binding_ref(vm, receiver, 0)
    +result : O.Outcome <- L.ref_out(vm, name)
    return result

@unsafe def entry_get_name(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  zip_name(vm, args)

@unsafe def entry_is_directory(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- L.bool_out(vm, String.ends_with(name, "/"))
    return result

@unsafe def entry_hash(+vm: M.VM, +args: +List<M.Slot>) -> Result<&2, &2, String, O.Outcome>:
  do Result<&2, &2, String, O.Outcome>:
    +receiver : U32 <- arg_ref(args, 0)
    +name : String <- binding_text(vm, receiver, 0)
    +result : O.Outcome <- L.int_out(vm, L.units_hash(L.units_from_string(name)))
    return result
