import Base
import ../model.bend as M
import ../classfile/descriptor.bend as D
import ../classfile/constant_pool.bend as CP
import ../classfile/reader.bend as R
import ./instruction.bend as I
import ./stack_map.bend as SM
import ../classfile/bootstrap_methods.bend as BM

type VType is Data:
  VTop{}
  VInt{}
  VFloat{}
  VLong{}
  VDouble{}
  VNull{}
  VRef{name: String}
  VUninitializedThis{name: String}
  VUninitialized{offset: U32, name: String}
  VUnusable{}

type State is Data:
  State{locals: +List<VType>, stack: +List<VType>, uninitializedThis: Bool}

type Hierarchy is Data:
  # files must include the current class and every known ancestor/interface needed
  # to answer reference assignability queries.
  Hierarchy{files: +List<M.ClassFile>}

type AttrWalk is Data:
  AttrWalk{reader: R.Reader, stackMap: Maybe<&2, SM.Frames>}

type MethodView is Data:
  MethodView{maxStack: U32, maxLocals: U32, codeLength: U32, stackMap: Maybe<&2, SM.Frames>}
def attr_walk_reader(value: AttrWalk) -> R.Reader:
  match value:
    case AttrWalk{reader, stackMap}: reader

def attr_walk_stackmap(value: AttrWalk) -> Maybe<&2, SM.Frames>:
  match value:
    case AttrWalk{reader, stackMap}: stackMap


def fail(className: String, methodName: String, descriptor: String, offset: U32, category: String, detail: String) -> String:
  "VerifyError[" ++ category ++ "] " ++ className ++ "." ++ methodName ++ descriptor ++ " @" ++ U32.show(offset) ++ ": " ++ detail

def require(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  R.require(ok, message)

def class_name(value: M.ClassFile) -> String:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}: name

def class_flags(value: M.ClassFile) -> U32:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}: flags

def class_parent(value: M.ClassFile) -> String:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}: parent

def class_interfaces(value: M.ClassFile) -> +List<String>:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}: interfaces

def class_pool(value: M.ClassFile) -> +List<M.Constant>:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}: pool

def class_methods(value: M.ClassFile) -> +List<M.Method>:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}: methods

def class_fields(value: M.ClassFile) -> +List<M.Field>:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}: fields
def class_declares_field(fields: +List<M.Field>, +name: String, +descriptor: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{M.Field{flags, fieldName, fieldDescriptor, constant, attributes}, rest}:
      (String.eq(fieldName, name) && String.eq(fieldDescriptor, descriptor)) || class_declares_field(rest, name, descriptor)

def class_major(value: M.ClassFile) -> U32:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}: major

def method_name(value: M.Method) -> String:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: name

def method_descriptor(value: M.Method) -> String:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: descriptor

def method_flags(value: M.Method) -> U32:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: flags

def method_attributes(value: M.Method) -> +List<M.Attribute>:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: attributes

def method_code(value: M.Method) -> +List<U32>:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: code

def method_instructions(value: M.Method) -> +List<M.Instruction>:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: instructions

def method_handlers(value: M.Method) -> +List<M.Handler>:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: handlers

def method_switches(value: M.Method) -> +List<M.SwitchTable>:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: switches

def method_max_stack(value: M.Method) -> U32:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: maxStack

def method_max_locals(value: M.Method) -> U32:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes, switches}: maxLocals

def state_uninitialized_this(value: State) -> Bool:
  match value:
    case State{locals, stack, uninitializedThis}: uninitializedThis

def state_with_uninitialized_this(value: State, +uninitializedThis: Bool) -> State:
  match value:
    case State{locals, stack, current}: State{locals, stack, uninitializedThis}

def state_locals(value: State) -> +List<VType>:
  match value:
    case State{locals, stack, uninitializedThis}: locals

def view_max_stack(value: MethodView) -> U32:
  match value:
    case MethodView{maxStack, maxLocals, codeLength, stackMap}: maxStack

def view_max_locals(value: MethodView) -> U32:
  match value:
    case MethodView{maxStack, maxLocals, codeLength, stackMap}: maxLocals

def hierarchy_files(value: Hierarchy) -> +List<M.ClassFile>:
  match value:
    case Hierarchy{files}: files

def view_stackmap(value: MethodView) -> Maybe<&2, SM.Frames>:
  match value:
    case MethodView{maxStack, maxLocals, codeLength, stackMap}: stackMap

def code_attr(attrs: +List<M.Attribute>) -> Maybe<&2, +List<U32>>:
  match attrs:
    case Nil{}: None{}
    case Con{M.Attribute{name, bytes}, rest}:
      Bool.pick(Maybe<&2, +List<U32>>, String.eq(name, "Code"), Some{bytes}, code_attr(rest))
    case Con{M.ValidatedAnnotations{metadata}, rest}: code_attr(rest)

def code_attribute_count(attrs: +List<M.Attribute>) -> U32:
  match attrs:
    case Nil{}: 0
    case Con{M.Attribute{name, bytes}, rest}:
      (Bool.pick(U32, String.eq(name, "Code"), 1, 0) + code_attribute_count(rest) : U32)
    case Con{M.ValidatedAnnotations{metadata}, rest}: code_attribute_count(rest)

def skip_handlers(count: Nat, reader: R.Reader) -> Result<&2, &2, String, R.Reader>:
  match count:
    case 0n: Done{reader}
    case 1n+rest:
      do Result<&2, &2, String, R.Reader>:
        end : R.Reader <- R.skip(reader, 8)
        result : R.Reader <- skip_handlers(rest, end)
        return result

def parse_stackmap(found: Maybe<&2, SM.Frames>, bytes: +List<U32>, pool: +List<M.Constant>, codeLength: U32) -> Result<&2, &2, String, Maybe<&2, SM.Frames>>:
  match found:
    case Some{_}: Fail{"VerifyError[StackMap]: duplicate StackMapTable"}
    case None{}:
      do Result<&2, &2, String, Maybe<&2, SM.Frames>>:
        frames : SM.Frames <- SM.parse(bytes, pool, codeLength)
        return Some{frames}

def update_stackmap(name: String, +found: Maybe<&2, SM.Frames>, bytes: +List<U32>, pool: +List<M.Constant>, codeLength: U32) -> Result<&2, &2, String, Maybe<&2, SM.Frames>>:
  Bool.pick(Result<&2, &2, String, Maybe<&2, SM.Frames>>, String.eq(name, "StackMapTable"), parse_stackmap(found, bytes, pool, codeLength), Done{found})

def nested_attrs(count: Nat, reader: R.Reader, +pool: +List<M.Constant>, +codeLength: U32, +found: Maybe<&2, SM.Frames>) -> Result<&2, &2, String, AttrWalk>:
  match count:
    case 0n: Done{AttrWalk{reader, found}}
    case 1n+rest:
      do Result<&2, &2, String, AttrWalk>:
        +nameWord : R.RWord <- R.read_u2(reader)
        afterName : R.Reader = R.word_reader(nameWord)
        nameIndex : U32 = R.word_value(nameWord)
        name : String <- CP.utf(pool, nameIndex)
        +lengthWord : R.RWord <- R.read_u4(afterName)
        afterLength : R.Reader = R.word_reader(lengthWord)
        length : U32 = R.word_value(lengthWord)
        +payload : R.RBytes <- R.slice(afterLength, length)
        afterPayload : R.Reader = R.bytes_reader(payload)
        bytes : +List<U32> = R.bytes_value(payload)
        nextFound : Maybe<&2, SM.Frames> <- update_stackmap(name, found, bytes, pool, codeLength)
        result : AttrWalk <- nested_attrs(rest, afterPayload, pool, codeLength, nextFound)
        return result


def method_view_found(+method: M.Method, pool: +List<M.Constant>, found: Maybe<&2, +List<U32>>) -> Result<&2, &2, String, MethodView>:
  match found:
    case None{}:
      Done{MethodView{method_max_stack(method), method_max_locals(method), M.length(U32, method_code(method)), None{}}}
    case Some{bytes}:
      do Result<&2, &2, String, MethodView>:
        reader : R.Reader = R.new(bytes)
        +stackWord : R.RWord <- R.read_u2(reader)
        afterStack : R.Reader = R.word_reader(stackWord)
        +maxStack : U32 = R.word_value(stackWord)
        +localsWord : R.RWord <- R.read_u2(afterStack)
        afterLocals : R.Reader = R.word_reader(localsWord)
        +maxLocals : U32 = R.word_value(localsWord)
        +codeWord : R.RWord <- R.read_u4(afterLocals)
        afterCodeLength : R.Reader = R.word_reader(codeWord)
        +codeLength : U32 = R.word_value(codeWord)
        code : R.RBytes <- R.slice(afterCodeLength, codeLength)
        afterCode : R.Reader = R.bytes_reader(code)
        +exceptions : R.RWord <- R.read_u2(afterCode)
        afterExceptionCount : R.Reader = R.word_reader(exceptions)
        exceptionCount : U32 = R.word_value(exceptions)
        afterHandlers : R.Reader <- skip_handlers(U32.to_nat(exceptionCount), afterExceptionCount)
        +attrsWord : R.RWord <- R.read_u2(afterHandlers)
        +afterAttrCount : R.Reader = R.word_reader(attrsWord)
        +attrCount : U32 = R.word_value(attrsWord)
        require(U32.is_le(attrCount, R.remaining(afterAttrCount)), "truncated nested Code attributes")
        +nested : AttrWalk <- nested_attrs(U32.to_nat(attrCount), afterAttrCount, pool, codeLength, None{})
        end : R.Reader = attr_walk_reader(nested)
        stackMap : Maybe<&2, SM.Frames> = attr_walk_stackmap(nested)
        R.finish(end)
        require(U32.is_lt(0, codeLength) && U32.is_le(codeLength, 65535), "VerifyError[Code]: Code length is outside 1..65535")
        require(U32.is_eq(codeLength, M.length(U32, method_code(method))), "VerifyError[Code]: Code attribute length disagrees with decoded code")
        require(U32.is_eq(maxStack, method_max_stack(method)) && U32.is_eq(maxLocals, method_max_locals(method)), "VerifyError[Code]: Code limits disagree with method model")
        return MethodView{maxStack, maxLocals, codeLength, stackMap}
def method_view(+method: M.Method, pool: +List<M.Constant>, major: U32) -> Result<&2, &2, String, MethodView>:
  method_view_found(method, pool, code_attr(method_attributes(method)))

def width(tag: U32) -> U32:
  match tag:
    case 4: 2
    case 5: 2
    case _: 1

def vtag(value: VType) -> U32:
  match value:
    case VInt{}: 1
    case VFloat{}: 2
    case VLong{}: 4
    case VDouble{}: 5
    case VRef{name}: 3
    case VNull{}: 3
    case VUninitializedThis{name}: 3
    case VUninitialized{offset, name}: 3
    case _: 0

def is_null(value: VType) -> Bool:
  match value:
    case VNull{}: True{}
    case _: False{}

def is_uninit(value: VType) -> Bool:
  match value:
    case VUninitializedThis{name}: True{}
    case VUninitialized{offset, name}: True{}
    case _: False{}

def is_uninitialized_this(value: VType) -> Bool:
  match value:
    case VUninitializedThis{name}: True{}
    case _: False{}
def compatible(expected: U32, +actual: VType) -> Bool:
  match expected:
    case 3:
      Bool.or(U32.is_eq(vtag(actual), 3), Bool.or(is_uninit(actual), is_null(actual)))
    case _: U32.is_eq(expected, vtag(actual))


def is_reference(+value: VType) -> Bool:
  Bool.or(U32.is_eq(vtag(value), 3), is_uninit(value))

def list_nth(values: +List<VType>, index: U32) -> Maybe<&2, VType>:
  M.nth(VType, values, index)

def replace_nth(values: +List<VType>, index: U32, value: VType) -> +List<VType>:
  match values:
    case Nil{}: Nil{}
    case Con{old, rest}:
      match index:
        case 0: Con{value, rest}
        case _ : Con{old, replace_nth(rest, (index - 1 : U32), value)}

def add_width_rest(values: +List<VType>) -> U32:
  match values:
    case Nil{}: 0
    case Con{value, rest}: (width(vtag(value)) + add_width_rest(rest) : U32)

def find_file(files: +List<M.ClassFile>, +name: String) -> Maybe<&2, M.ClassFile>:
  match files:
    case Nil{}: None{}
    case Con{+file, rest}:
      Bool.pick(Maybe<&2, M.ClassFile>, String.eq(class_name(file), name), Some{file}, find_file(rest, name))

def ancestor_interfaces(interfaces: +List<String>, +pending: +List<String>) -> +List<String>:
  match interfaces:
    case Nil{}: pending
    case Con{interface, rest}: Con{interface, ancestor_interfaces(rest, pending)}

def ancestor_expand(found: Maybe<&2, M.ClassFile>, +pending: +List<String>) -> +List<String>:
  match found:
    case None{}: pending
    case Some{+file}: Con{class_parent(file), ancestor_interfaces(class_interfaces(file), pending)}

def is_ancestor_work(fuel: Nat, pending: +List<String>, +ancestor: String, +files: +List<M.ClassFile>) -> Bool:
  match fuel pending:
    case 0n _: False{}
    case 1n+rest Nil{}: False{}
    case 1n+rest Con{+child, tail}:
      Bool.pick(Bool, String.eq(child, ancestor), True{},
        is_ancestor_work(rest, ancestor_expand(find_file(files, child), tail), ancestor, files))

def is_ancestor(+child: String, +ancestor: String, +files: +List<M.ClassFile>, fuel: U32) -> Bool:
  is_ancestor_work(U32.to_nat(fuel), Con{child, Nil{}}, ancestor, files)

def array_descriptor(value: M.JvmType) -> String:
  match value:
    case M.Primitive{66}: "[B"
    case M.Primitive{67}: "[C"
    case M.Primitive{68}: "[D"
    case M.Primitive{70}: "[F"
    case M.Primitive{73}: "[I"
    case M.Primitive{74}: "[J"
    case M.Primitive{83}: "[S"
    case M.Primitive{90}: "[Z"
    case M.ObjectType{name}: "[L" ++ name ++ ";"
    case M.ArrayType{element}: "[" ++ array_descriptor(element)
    case _: "[Ljava/lang/Object;"
def local_error(file: M.ClassFile, +method: M.Method, offset: U32, detail: String) -> String:
  fail(class_name(file), method_name(method), method_descriptor(method), offset, "Type", detail)

def switch_successor_result(default: U32, found: Maybe<&2, M.SwitchTable>) -> +List<U32>:
  match found:
    case None{}: [default]
    case Some{M.SwitchTable{kind, low, high, keys, targets}}: M.append(U32, [default], targets)
def switch_successors(default: U32, index: U32, tables: +List<M.SwitchTable>) -> +List<U32>:
  switch_successor_result(default, M.nth(M.SwitchTable, tables, index))
type StackRead is Data:
  StackRead{value: VType, rest: +List<VType>}

def stack_read_rest(value: StackRead) -> +List<VType>:
  match value:
    case StackRead{value, rest}: rest

def stack_read_value(value: StackRead) -> VType:
  match value:
    case StackRead{value, rest}: value
def stack_pop(stack: +List<VType>, expected: U32, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, StackRead>:
  match stack:
    case Nil{}: Fail{local_error(file, method, offset, "operand stack underflow")}
    case Con{+value, rest}:
      Bool.pick(Result<&2, &2, String, StackRead>, compatible(expected, value), Done{StackRead{value, rest}}, Fail{local_error(file, method, offset, "operand type mismatch")})


def stack_push(value: VType, stack: +List<VType>) -> +List<VType>:
  Con{value, stack}



def valid_local_pair_second(found: Maybe<&2, VType>) -> Bool:
  match found:
    case Some{VUnusable{}}: True{}
    case _: False{}

def valid_local_pair_width(+slotWidth: U32, locals: +List<VType>, index: U32) -> Bool:
  Bool.pick(Bool, U32.is_eq(slotWidth, 1), True{},
    Bool.pick(Bool, U32.is_eq(slotWidth, 2), valid_local_pair_second(list_nth(locals, (index + 1 : U32))), False{}))

def valid_local_pair(locals: +List<VType>, index: U32, value: VType) -> Bool:
  valid_local_pair_width(width(vtag(value)), locals, index)
def apply_load_local(found: Maybe<&2, VType>, tag: U32, +locals: +List<VType>, stack: +List<VType>, index: U32, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  match found:
    case None{}: Fail{local_error(file, method, offset, "local index outside max_locals")}
    case Some{+value}:
      Bool.pick(Result<&2, &2, String, State>, compatible(tag, value) && valid_local_pair(locals, index, value), Done{State{locals, stack_push(value, stack), False{}}}, Fail{local_error(file, method, offset, "load from incompatible, split, or unusable local")})

def put_initial(+locals: +List<VType>, +index: U32, value: VType, valueWidth: U32) -> +List<VType>:
  match valueWidth:
    case 2:
      replace_nth(replace_nth(locals, index, value), (index + 1 : U32), VUnusable{})
    case _:
      replace_nth(locals, index, value)
def is_wide_value(value: VType) -> Bool:
  U32.is_eq(width(vtag(value)), 2)

def clear_local_current(current: Maybe<&2, VType>, +locals: +List<VType>, +index: U32) -> +List<VType>:
  match current:
    case Some{VUnusable{}}:
      Bool.pick(+List<VType>, U32.is_eq(index, 0), locals, replace_nth(locals, (index - 1 : U32), VTop{}))
    case Some{value}:
      Bool.pick(+List<VType>, is_wide_value(value), replace_nth(locals, (index + 1 : U32), VTop{}), locals)
    case None{}: locals

def clear_local_next(next: Maybe<&2, VType>, +afterCurrent: +List<VType>, index: U32) -> +List<VType>:
  match next:
    case Some{value}:
      Bool.pick(+List<VType>, is_wide_value(value), replace_nth(afterCurrent, (index + 2 : U32), VTop{}), afterCurrent)
    case None{}: afterCurrent

# A store of `slotWidth` slots at `index` breaks any wide pair it overlaps:
# the pair ending at `index` and, for two-slot stores, the pair starting at `index + 1`.
def clear_local_after_current(current: Maybe<&2, VType>, locals: +List<VType>, +index: U32, +slotWidth: U32) -> +List<VType>:
  +afterCurrent : +List<VType> = clear_local_current(current, locals, index)
  Bool.pick(+List<VType>, U32.is_eq(slotWidth, 2), clear_local_next(list_nth(afterCurrent, (index + 1 : U32)), afterCurrent, index), afterCurrent)

def clear_local_overlap(+locals: +List<VType>, +index: U32, +slotWidth: U32) -> +List<VType>:
  clear_local_after_current(list_nth(locals, index), locals, index, slotWidth)

def store_local(+locals: +List<VType>, +index: U32, value: VType, +tag: U32) -> +List<VType>:
  cleared : +List<VType> = clear_local_overlap(locals, index, width(tag))
  put_initial(cleared, index, value, width(tag))

def apply_store_local(popped: Result<&2, &2, String, StackRead>, tag: U32, locals: +List<VType>, index: U32) -> Result<&2, &2, String, State>:
  match popped:
    case Fail{error}: Fail{error}
    case Done{StackRead{value, rest}}: Done{State{store_local(locals, index, value, tag), rest, False{}}}

def check_iinc_value(state: State, found: Maybe<&2, VType>, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  match found:
    case Some{VInt{}}: Done{state}
    case _: Fail{local_error(file, method, offset, "iinc requires an initialized int local")}

def check_iinc_local(state: State, locals: +List<VType>, index: U32, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  check_iinc_value(state, list_nth(locals, index), file, method, offset)
def type_of_tag(tag: U32) -> VType:
  match tag:
    case 1: VInt{}
    case 2: VFloat{}
    case 3: VRef{"java/lang/Object"}
    case 4: VLong{}
    case 5: VDouble{}
    case _: VTop{}

def make_outputs(outputs: +List<U32>, rest: +List<VType>) -> +List<VType>:
  match outputs:
    case Nil{}: rest
    case Con{tag, tail}: stack_push(type_of_tag(tag), make_outputs(tail, rest))

def consume(inputs: +List<U32>, stack: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, +List<VType>>:
  match inputs:
    case Nil{}: Done{stack}
    case Con{expected, rest}:
      do Result<&2, &2, String, +List<VType>>:
        popped : StackRead <- stack_pop(stack, expected, file, method, offset)
        result : +List<VType> <- consume(rest, stack_read_rest(popped), file, method, offset)
        return result

def apply_effects(inputs: +List<U32>, outputs: +List<U32>, locals: +List<VType>, stack: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32, maxStack: U32) -> Result<&2, &2, String, State>:
  do Result<&2, &2, String, State>:
    remainder : +List<VType> <- consume(inputs, stack, file, method, offset)
    +produced : +List<VType> = make_outputs(outputs, remainder)
    require(U32.is_le(add_width_rest(produced), maxStack), local_error(file, method, offset, "max_stack exceeded"))
    return State{locals, produced, False{}}
def type_of_jvm(value: M.JvmType) -> VType:
  match value:
    case M.Primitive{74}: VLong{}
    case M.Primitive{68}: VDouble{}
    case M.Primitive{70}: VFloat{}
    case M.Primitive{86}: VTop{}
    case M.ObjectType{name}: VRef{name}
    case M.ArrayType{element}: VRef{array_descriptor(element)}
    case M.Primitive{tag}: VInt{}



def bad_shape(file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  Fail{local_error(file, method, offset, "illegal category shape for stack operation")}


def permute_form(ok: Bool, state: State, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  Bool.pick(Result<&2, &2, String, State>, ok, Done{state}, bad_shape(file, method, offset))

def pop2_width(slotWidth: U32, +a: VType, rest: +List<VType>, +locals: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, State>:
  match slotWidth rest:
    case 2 tail: Done{State{locals, tail, False{}}}
    case 1 Con{b, tail}:
      permute_form(U32.is_eq(width(vtag(b)), 1), State{locals, tail, False{}}, file, method, offset)
    case _ _: bad_shape(file, method, offset)

def dup_x2_widths(widthA: U32, widthB: U32, +a: VType, +b: VType, rest: +List<VType>, +locals: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, State>:
  match widthA widthB rest:
    case 1 2 tail: Done{State{locals, Con{a, Con{b, Con{a, tail}}}, False{}}}
    case 1 1 Con{+c, tail}:
      permute_form(U32.is_eq(width(vtag(c)), 1), State{locals, Con{a, Con{b, Con{c, Con{a, tail}}}}, False{}}, file, method, offset)
    case _ _ _: bad_shape(file, method, offset)

def dup2_top_width(slotWidth: U32, +a: VType, rest: +List<VType>, +locals: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, State>:
  match slotWidth rest:
    case 2 tail: Done{State{locals, Con{a, Con{a, tail}}, False{}}}
    case 1 Con{+b, tail}:
      permute_form(U32.is_eq(width(vtag(b)), 1), State{locals, Con{a, Con{b, Con{a, Con{b, tail}}}}, False{}}, file, method, offset)
    case _ _: bad_shape(file, method, offset)

def dup2_x1_widths(widthA: U32, widthB: U32, +a: VType, +b: VType, rest: +List<VType>, +locals: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, State>:
  match widthA widthB rest:
    case 2 1 tail: Done{State{locals, Con{a, Con{b, Con{a, tail}}}, False{}}}
    case 1 1 Con{+c, tail}:
      permute_form(U32.is_eq(width(vtag(c)), 1), State{locals, Con{a, Con{b, Con{c, Con{a, Con{b, tail}}}}}, False{}}, file, method, offset)
    case _ _ _: bad_shape(file, method, offset)

def dup2_x2_tail_width(widthC: U32, +a: VType, +b: VType, +c: VType, rest: +List<VType>, +locals: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, State>:
  match widthC rest:
    case 2 tail: Done{State{locals, Con{a, Con{b, Con{c, Con{a, Con{b, tail}}}}}, False{}}}
    case 1 Con{+d, tail}:
      permute_form(U32.is_eq(width(vtag(d)), 1), State{locals, Con{a, Con{b, Con{c, Con{d, Con{a, Con{b, tail}}}}}}, False{}}, file, method, offset)
    case _ _: bad_shape(file, method, offset)

def dup2_x2_widths(widthA: U32, widthB: U32, +a: VType, +b: VType, rest: +List<VType>, +locals: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, State>:
  match widthA widthB rest:
    case 2 2 tail: Done{State{locals, Con{a, Con{b, Con{a, tail}}}, False{}}}
    case 2 1 Con{+c, tail}:
      permute_form(U32.is_eq(width(vtag(c)), 1), State{locals, Con{a, Con{b, Con{c, Con{a, tail}}}}, False{}}, file, method, offset)
    case 1 1 Con{+c, tail}:
      dup2_x2_tail_width(width(vtag(c)), a, b, c, tail, locals, file, method, offset)
    case _ _ _: bad_shape(file, method, offset)

def pop2(+a: VType, rest: +List<VType>, locals: +List<VType>, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  pop2_width(width(vtag(a)), a, rest, locals, file, method, offset)

def dup_x2(+a: VType, +b: VType, rest: +List<VType>, locals: +List<VType>, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  dup_x2_widths(width(vtag(a)), width(vtag(b)), a, b, rest, locals, file, method, offset)

def dup2_top(+a: VType, rest: +List<VType>, locals: +List<VType>, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  dup2_top_width(width(vtag(a)), a, rest, locals, file, method, offset)

def dup2_x1(+a: VType, +b: VType, rest: +List<VType>, locals: +List<VType>, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  dup2_x1_widths(width(vtag(a)), width(vtag(b)), a, b, rest, locals, file, method, offset)

def dup2_x2(+a: VType, +b: VType, rest: +List<VType>, locals: +List<VType>, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  dup2_x2_widths(width(vtag(a)), width(vtag(b)), a, b, rest, locals, file, method, offset)

def permute(op: U32, +locals: +List<VType>, stack: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, State>:
  match op stack:
    case 87 Con{a, rest}:
      Bool.pick(Result<&2, &2, String, State>, U32.is_eq(width(vtag(a)), 1), Done{State{locals, rest, False{}}}, bad_shape(file, method, offset))
    case 88 Con{a, rest}:
      pop2(a, rest, locals, file, method, offset)
    case 89 Con{+a, rest}:
      Bool.pick(Result<&2, &2, String, State>, U32.is_eq(width(vtag(a)), 1), Done{State{locals, Con{a, Con{a, rest}}, False{}}}, bad_shape(file, method, offset))
    case 90 Con{+a, Con{+b, rest}}:
      permute_form(U32.is_eq(width(vtag(a)), 1) && U32.is_eq(width(vtag(b)), 1), State{locals, Con{a, Con{b, Con{a, rest}}}, False{}}, file, method, offset)
    case 91 Con{a, Con{b, rest}}:
      dup_x2(a, b, rest, locals, file, method, offset)
    case 92 Con{a, rest}:
      dup2_top(a, rest, locals, file, method, offset)
    case 93 Con{a, Con{b, rest}}:
      dup2_x1(a, b, rest, locals, file, method, offset)
    case 94 Con{a, Con{b, rest}}:
      dup2_x2(a, b, rest, locals, file, method, offset)
    case 95 Con{+a, Con{+b, rest}}:
      permute_form(U32.is_eq(width(vtag(a)), 1) && U32.is_eq(width(vtag(b)), 1), State{locals, Con{b, Con{a, rest}}, False{}}, file, method, offset)
    case _ _: bad_shape(file, method, offset)
def apply_permute(op: U32, state: State, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  match state:
    case State{locals, stack, uninitializedThis}:
      permute(op, locals, stack, file, method, offset)
def apply_rule_kind(kind: U32, +tag: U32, inputs: +List<U32>, outputs: +List<U32>, +locals: +List<VType>, +stack: +List<VType>, op: U32, +index: U32, state: State, +file: M.ClassFile, +method: M.Method, +offset: U32, maxStack: U32) -> Result<&2, &2, String, State>:
  match kind:
    case 1: apply_load_local(list_nth(locals, index), tag, locals, stack, index, file, method, offset)
    case 2: apply_store_local(stack_pop(stack, tag, file, method, offset), tag, locals, index)
    case 3: check_iinc_local(state, locals, index, file, method, offset)
    case 4: apply_permute(op, state, file, method, offset)
    case _: apply_effects(inputs, outputs, locals, stack, file, method, offset, maxStack)
def apply_simple(rule: I.Rule, +state: State, instruction: M.Instruction, file: M.ClassFile, method: M.Method, maxStack: U32) -> Result<&2, &2, String, State>:
  match rule state instruction:
    case I.Rule{kind, tag, inputs, outputs} State{+locals, +stack, uninitializedThis} M.Instruction{op, a, b, c, offset}:
      apply_rule_kind(kind, tag, inputs, outputs, locals, stack, op, a, state, file, method, offset, maxStack)

def instruction_offset(value: M.Instruction) -> U32:
  match value:
    case M.Instruction{op, a, b, c, offset}: offset

def instruction_opcode(value: M.Instruction) -> U32:
  match value:
    case M.Instruction{op, a, b, c, offset}: op

def expected_return(method: M.Method) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    descriptor : M.Descriptor <- D.parse_method(method_descriptor(method))
    return D.slot_tag(D.result_type(descriptor))


def stack_type_found(found: Maybe<&2, VType>, file: M.ClassFile, method: M.Method, offset: U32, detail: String) -> Result<&2, &2, String, VType>:
  match found:
    case None{}: Fail{local_error(file, method, offset, detail)}
    case Some{value}: Done{value}

def stack_type_at(state: State, index: U32, file: M.ClassFile, method: M.Method, offset: U32, detail: String) -> Result<&2, &2, String, VType>:
  match state:
    case State{locals, stack, uninitializedThis}:
      stack_type_found(M.nth(VType, stack, index), file, method, offset, detail)

def validate_reference_inputs_go(count: Nat, +index: U32, +state: State, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  match count:
    case 0n: Done{Unit{}}
    case 1n+rest:
      do Result<&2, &2, String, Unit>:
        +value : VType <- stack_type_at(state, index, file, method, offset, "reference operand missing from stack")
        require(is_reference(value) && Bool.not(is_uninit(value)), local_error(file, method, offset, "operation uses an uninitialized or non-reference value"))
        result : Unit <- validate_reference_inputs_go(rest, (index - 1 : U32), state, file, method, offset)
        return result

def validate_reference_inputs(+count: U32, state: State, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  validate_reference_inputs_go(U32.to_nat(count), (count - 1 : U32), state, file, method, offset)

def validate_reference_consumers(instruction: M.Instruction, state: State, file: M.ClassFile, method: M.Method) -> Result<&2, &2, String, Unit>:
  match instruction:
    case M.Instruction{op, a, b, c, offset}:
      match op:
        case 165: validate_reference_inputs(2, state, file, method, offset)
        case 166: validate_reference_inputs(2, state, file, method, offset)
        case 191: validate_reference_inputs(1, state, file, method, offset)
        case 194: validate_reference_inputs(1, state, file, method, offset)
        case 195: validate_reference_inputs(1, state, file, method, offset)
        case 193: validate_reference_inputs(1, state, file, method, offset)
        case 198: validate_reference_inputs(1, state, file, method, offset)
        case 199: validate_reference_inputs(1, state, file, method, offset)
        case _: Done{Unit{}}

def is_array_opcode(+op: U32) -> Bool:
  (U32.is_ge(op, 46) && U32.is_le(op, 53)) || (U32.is_ge(op, 79) && U32.is_le(op, 86)) || U32.is_eq(op, 190)

def is_array_name(name: String) -> Bool:
  match name:
    case SCon{Chr{91}, rest}: True{}
    case _: False{}

def array_component_descriptor(name: String) -> String:
  match name:
    case SCon{Chr{91}, rest}: rest
    case _: ""

def is_reference_descriptor(value: String) -> Bool:
  match value:
    case SCon{Chr{91}, rest}: True{}
    case SCon{Chr{76}, rest}: True{}
    case _: False{}

def array_component_matches(op: U32, +component: String) -> Bool:
  match op:
    case 46: String.eq(component, "I")
    case 47: String.eq(component, "J")
    case 48: String.eq(component, "F")
    case 49: String.eq(component, "D")
    case 50: is_reference_descriptor(component)
    case 51: String.eq(component, "B") || String.eq(component, "Z")
    case 52: String.eq(component, "C")
    case 53: String.eq(component, "S")
    case _: False{}

def array_opcode_matches_name(isArray: Bool, +op: U32, name: String) -> Bool:
  match isArray:
    case False{}: False{}
    case True{}:
      array_component_matches(Bool.pick(U32, U32.is_ge(op, 79) && U32.is_le(op, 86), (op - 33 : U32), op), array_component_descriptor(name))

def array_opcode_matches_is_length(isLength: Bool, op: U32, +name: String) -> Bool:
  match isLength:
    case True{}: is_array_name(name)
    case False{}: array_opcode_matches_name(is_array_name(name), op, name)

def array_opcode_matches(+op: U32, name: String) -> Bool:
  array_opcode_matches_is_length(U32.is_eq(op, 190), op, name)

def array_store_reference_found(found: Maybe<&2, VType>) -> Bool:
  match found:
    case Some{+value}: is_reference(value) && Bool.not(is_uninit(value))
    case None{}: False{}

def array_store_reference_value(state: State) -> Bool:
  match state:
    case State{locals, stack, uninitializedThis}: array_store_reference_found(M.nth(VType, stack, 0))

def reference_value_descriptor(+name: String) -> String:
  Bool.pick(String, is_array_name(name), name, "L" ++ name ++ ";")

# JVMS 4.10.1.2 isJavaAssignable: every reference is assignable to an interface
# type; interface conformance is enforced at invokeinterface time instead.
def interface_flagged(found: Maybe<&2, M.ClassFile>) -> Bool:
  match found:
    case None{}: False{}
    case Some{file}: U32.is_ne(U32.and(class_flags(file), 512), 0)

# Generated Bool.pick/||/&& evaluate eagerly, so hierarchy scans are guarded by match.
def reference_assignable_interface(isInterface: Bool, +actualName: String, +expectedName: String, +files: +List<M.ClassFile>) -> Bool:
  match isInterface:
    case True{}: True{}
    case False{}: is_ancestor(actualName, expectedName, files, 256)

def reference_assignable_quick(quick: Bool, +actualName: String, +expectedName: String, +files: +List<M.ClassFile>) -> Bool:
  match quick:
    case True{}: True{}
    case False{}: reference_assignable_interface(interface_flagged(find_file(files, expectedName)), actualName, expectedName, files)

def reference_assignable(+actualName: String, +expectedName: String, +files: +List<M.ClassFile>) -> Bool:
  reference_assignable_quick(String.eq(actualName, expectedName) || String.eq(expectedName, "java/lang/Object"), actualName, expectedName, files)

# JVMS 4.10.1.2 isJavaAssignable over parsed field types; the single reference
# assignability rule shared by frames, receivers, arguments, fields, and returns.
def jvm_assignable(actual: M.JvmType, expected: M.JvmType, +files: +List<M.ClassFile>) -> Bool:
  match actual expected:
    case M.Primitive{actualTag} M.Primitive{expectedTag}: U32.is_eq(actualTag, expectedTag)
    case M.ObjectType{+actualName} M.ObjectType{+expectedName}: reference_assignable(actualName, expectedName, files)
    case M.ArrayType{actualElement} M.ArrayType{expectedElement}: jvm_assignable(actualElement, expectedElement, files)
    case M.ArrayType{element} M.ObjectType{+expectedName}:
      String.eq(expectedName, "java/lang/Object") || String.eq(expectedName, "java/lang/Cloneable") || String.eq(expectedName, "java/io/Serializable")
    case _ _: False{}

def parsed_assignable(actual: Result<&2, &2, String, M.JvmType>, expected: Result<&2, &2, String, M.JvmType>, +files: +List<M.ClassFile>) -> Bool:
  match actual expected:
    case Done{actualType} Done{expectedType}: jvm_assignable(actualType, expectedType, files)
    case _ _: False{}

def reference_names_assignable(+actualName: String, +expectedName: String, +hierarchy: Hierarchy) -> Bool:
  parsed_assignable(D.parse_field(reference_value_descriptor(actualName)), D.parse_field(reference_value_descriptor(expectedName)), hierarchy_files(hierarchy))

def reference_type_assignable(+actualName: String, expected: M.JvmType, +hierarchy: Hierarchy) -> Bool:
  parsed_assignable(D.parse_field(reference_value_descriptor(actualName)), Done{expected}, hierarchy_files(hierarchy))

def validate_reference_array(+name: String, +op: U32, state: State, hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    require(array_opcode_matches(op, name), local_error(file, method, offset, "array opcode does not match array component type"))
    # aastore component compatibility is a runtime ArrayStoreException check (JVMS 6.5).
    require(Bool.not(U32.is_eq(op, 83)) || array_store_reference_value(state), local_error(file, method, offset, "aastore value must be an initialized reference"))
    return Unit{}

def validate_array_value(array: VType, op: U32, state: State, hierarchy: Hierarchy, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  match array:
    case VNull{}:
      require(Bool.not(U32.is_eq(op, 83)) || array_store_reference_value(state), local_error(file, method, offset, "aastore value must be an initialized reference"))
    case VRef{name}: validate_reference_array(name, op, state, hierarchy, file, method, offset)
    case _: Fail{local_error(file, method, offset, "array opcode requires an array reference")}

def validate_array_opcode(isArray: Bool, +op: U32, +state: State, hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  match isArray:
    case False{}: Done{Unit{}}
    case True{}:
      do Result<&2, &2, String, Unit>:
        arrayIndex : U32 = Bool.pick(U32, U32.is_ge(op, 79) && U32.is_le(op, 86), 2, Bool.pick(U32, U32.is_eq(op, 190), 0, 1))
        array : VType <- stack_type_at(state, arrayIndex, file, method, offset, "array operand is missing")
        result : Unit <- validate_array_value(array, op, state, hierarchy, file, method, offset)
        return result

def validate_array_instruction(instruction: M.Instruction, state: State, hierarchy: Hierarchy, file: M.ClassFile, method: M.Method) -> Result<&2, &2, String, Unit>:
  match instruction:
    case M.Instruction{+op, a, b, c, offset}:
      validate_array_opcode(is_array_opcode(op), op, state, hierarchy, file, method, offset)

def is_int_primitive_tag(+tag: U32) -> Bool:
  U32.is_eq(tag, 66) || U32.is_eq(tag, 67) || U32.is_eq(tag, 73) || U32.is_eq(tag, 83) || U32.is_eq(tag, 90)

def is_reference_jvm_type(value: M.JvmType) -> Bool:
  match value:
    case M.ObjectType{name}: True{}
    case M.ArrayType{element}: True{}
    case _: False{}

def verifier_value_assignable(actual: VType, expected: M.JvmType, hierarchy: Hierarchy) -> Bool:
  match actual:
    case VInt{}:
      match expected:
        case M.Primitive{tag}: is_int_primitive_tag(tag)
        case _: False{}
    case VLong{}:
      match expected:
        case M.Primitive{74}: True{}
        case _: False{}
    case VFloat{}:
      match expected:
        case M.Primitive{70}: True{}
        case _: False{}
    case VDouble{}:
      match expected:
        case M.Primitive{68}: True{}
        case _: False{}
    case VNull{}: is_reference_jvm_type(expected)
    case VRef{+name}: reference_type_assignable(name, expected, hierarchy)
    case _: False{}

def verifier_reference_parsed(actual: VType, expected: Result<&2, &2, String, M.JvmType>, hierarchy: Hierarchy) -> Bool:
  match expected:
    case Fail{error}: False{}
    case Done{expectedType}: verifier_value_assignable(actual, expectedType, hierarchy)

# Owners and field classes are binary names; array owners such as `[LX;` parse as arrays.
def verifier_reference_assignable(actual: VType, +expectedName: String, hierarchy: Hierarchy) -> Bool:
  verifier_reference_parsed(actual, D.parse_field(reference_value_descriptor(expectedName)), hierarchy)
def validate_call_receiver(index: U32, +state: State, +pool: +List<M.Constant>, +file: M.ClassFile, +method: M.Method, hierarchy: Hierarchy, +offset: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    +member : CP.Member <- CP.member(pool, index)
    descriptor : M.Descriptor <- D.parse_method(CP.member_descriptor(member))
    receiverIndex : U32 = D.parameter_count(descriptor)
    +receiver : VType <- stack_type_at(state, receiverIndex, file, method, offset, "invocation receiver missing below arguments")
    require(Bool.not(is_uninit(receiver)), local_error(file, method, offset, "virtual/interface invocation uses an uninitialized receiver"))
    require(verifier_reference_assignable(receiver, CP.member_owner(member), hierarchy), local_error(file, method, offset, "invocation receiver is not assignable to the method owner"))
    return Unit{}

def validate_special_receiver_kind(isConstructor: Bool, index: U32, state: State, pool: +List<M.Constant>, file: M.ClassFile, method: M.Method, hierarchy: Hierarchy, offset: U32) -> Result<&2, &2, String, Unit>:
  match isConstructor:
    case True{}: Done{Unit{}}
    case False{}: validate_call_receiver(index, state, pool, file, method, hierarchy, offset)

def validate_special_receiver(+index: U32, state: State, +pool: +List<M.Constant>, file: M.ClassFile, method: M.Method, hierarchy: Hierarchy, offset: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    member : CP.Member <- CP.member(pool, index)
    result : Unit <- validate_special_receiver_kind(String.eq(CP.member_name(member), "<init>"), index, state, pool, file, method, hierarchy, offset)
    return result

def validate_field_receiver_type(receiver: VType, stackIndex: U32, +member: CP.Member, +file: M.ClassFile, method: M.Method, hierarchy: Hierarchy, offset: U32) -> Result<&2, &2, String, Unit>:
  match receiver:
    case VUninitializedThis{name}:
      require(U32.is_eq(stackIndex, 1) && String.eq(CP.member_owner(member), class_name(file)) && class_declares_field(class_fields(file), CP.member_name(member), CP.member_descriptor(member)), local_error(file, method, offset, "putfield on uninitializedThis is only valid for a field declared by this class"))
    case VUninitialized{allocation, name}:
      Fail{local_error(file, method, offset, "field access uses an uninitialized allocation")}
    case _: require(verifier_reference_assignable(receiver, CP.member_owner(member), hierarchy), local_error(file, method, offset, "field receiver is not assignable to the field owner"))

def validate_field_receiver(index: U32, +stackIndex: U32, +state: State, +pool: +List<M.Constant>, +file: M.ClassFile, +method: M.Method, hierarchy: Hierarchy, +offset: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    member : CP.Member <- CP.member(pool, index)
    receiver : VType <- stack_type_at(state, stackIndex, file, method, offset, "field receiver is missing from operand stack")
    result : Unit <- validate_field_receiver_type(receiver, stackIndex, member, file, method, hierarchy, offset)
    return result

def validate_invocation_receiver(instruction: M.Instruction, state: State, pool: +List<M.Constant>, file: M.ClassFile, method: M.Method, hierarchy: Hierarchy) -> Result<&2, &2, String, Unit>:
  match instruction:
    case M.Instruction{op, a, b, c, offset}:
      match op:
        case 180: validate_field_receiver(a, 0, state, pool, file, method, hierarchy, offset)
        case 181: validate_field_receiver(a, 1, state, pool, file, method, hierarchy, offset)
        case 182: validate_call_receiver(a, state, pool, file, method, hierarchy, offset)
        case 183: validate_special_receiver(a, state, pool, file, method, hierarchy, offset)
        case 185: validate_call_receiver(a, state, pool, file, method, hierarchy, offset)
        case _: Done{Unit{}}

def constant_pool_result(found: Maybe<&2, M.Constant>, error: String) -> Result<&2, &2, String, M.Constant>:
  match found:
    case None{}: Fail{error}
    case Some{value}: Done{value}

def dynamic_constant(pool: +List<M.Constant>, index: U32) -> Result<&2, &2, String, M.Constant>:
  constant_pool_result(M.nth(M.Constant, pool, index), "VerifyError: invokedynamic constant index out of bounds")

def invocation_name_type(value: M.Constant) -> Result<&2, &2, String, U32>:
  match value:
    case M.PairIndex{18, bootstrap, nameType}: Done{nameType}
    case _: Fail{"VerifyError: invokedynamic operand is not InvokeDynamic"}

def name_type_descriptor(value: CP.NameType) -> String:
  match value:
    case CP.NameType{name, descriptor}: descriptor

def invocation_descriptor_kind(isDynamic: Bool, index: U32, +pool: +List<M.Constant>) -> Result<&2, &2, String, String>:
  match isDynamic:
    case False{}:
      do Result<&2, &2, String, String>:
        member : CP.Member <- CP.member(pool, index)
        return CP.member_descriptor(member)
    case True{}:
      do Result<&2, &2, String, String>:
        entry : M.Constant <- dynamic_constant(pool, index)
        nameType : U32 <- invocation_name_type(entry)
        pair : CP.NameType <- CP.name_type(pool, nameType)
        return name_type_descriptor(pair)

def invocation_descriptor(+op: U32, index: U32, pool: +List<M.Constant>) -> Result<&2, &2, String, String>:
  invocation_descriptor_kind(U32.is_eq(op, 186), index, pool)

def direct_method_flags(+methods: +List<M.Method>, +name: String, +descriptor: String) -> Maybe<&2, U32>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, U32>,
        String.eq(method_name(method), name) && String.eq(method_descriptor(method), descriptor),
        Some{method_flags(method)},
        direct_method_flags(rest, name, descriptor))

def prepend_interfaces(interfaces: +List<String>, +pending: +List<String>) -> +List<String>:
  match interfaces:
    case Nil{}: pending
    case Con{interface, rest}: Con{interface, prepend_interfaces(rest, pending)}

def resolution_successors(+file: M.ClassFile, +pending: +List<String>) -> +List<String>:
  prepend_interfaces(class_interfaces(file), Con{class_parent(file), pending})

def resolve_method_flags_work(fuel: Nat, +pending: +List<String>, current: Maybe<&2, M.ClassFile>, checked: Bool, flags: Maybe<&2, U32>, +name: String, +descriptor: String, +files: +List<M.ClassFile>) -> Maybe<&2, U32>:
  match fuel pending current checked flags:
    case 0n _ _ _ _: None{}
    case 1n+rest Nil{} _ _ _: None{}
    case 1n+rest Con{owner, tail} None{} False{} _:
      resolve_method_flags_work(rest, tail, find_file(files, owner), False{}, None{}, name, descriptor, files)
    case 1n+rest Con{owner, tail} Some{+file} False{} _:
      resolve_method_flags_work(rest, Con{owner, tail}, Some{file}, True{}, direct_method_flags(class_methods(file), name, descriptor), name, descriptor, files)
    case 1n+rest Con{owner, tail} Some{+file} True{} Some{foundFlags}:
      Some{foundFlags}
    case 1n+rest Con{owner, tail} Some{+file} True{} None{}:
      resolve_method_flags_work(rest, resolution_successors(file, tail), None{}, False{}, None{}, name, descriptor, files)
    case _ _ _ _ _: None{}

def resolve_method_flags(owner: String, name: String, descriptor: String, files: +List<M.ClassFile>, fuel: U32) -> Maybe<&2, U32>:
  resolve_method_flags_work(U32.to_nat(fuel), Con{owner, Nil{}}, None{}, False{}, None{}, name, descriptor, files)

def validate_call_staticness_flags(found: Maybe<&2, U32>, op: U32, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  match found:
    case None{}: Done{Unit{}}
    case Some{flags}:
      require(Bool.not(Bool.xor(U32.is_ne(U32.and(flags, 8), 0), U32.is_eq(op, 184))), local_error(file, method, offset, "invocation opcode does not match resolved method staticness"))

def validate_call_staticness_applicable(applicable: Bool, op: U32, index: U32, pool: +List<M.Constant>, hierarchy: Hierarchy, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  match applicable:
    case False{}: Done{Unit{}}
    case True{}:
      do Result<&2, &2, String, Unit>:
        +member : CP.Member <- CP.member(pool, index)
        name : String = CP.member_name(member)
        descriptor : String = CP.member_descriptor(member)
        flags : Maybe<&2, U32> = resolve_method_flags(CP.member_owner(member), name, descriptor, hierarchy_files(hierarchy), 256)
        result : Unit <- validate_call_staticness_flags(flags, op, file, method, offset)
        return result

def validate_call_staticness(+op: U32, index: U32, pool: +List<M.Constant>, hierarchy: Hierarchy, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  validate_call_staticness_applicable(U32.is_ge(op, 182) && U32.is_le(op, 185), op, index, pool, hierarchy, file, method, offset)

def validate_stack_value(expected: M.JvmType, stack: +List<VType>, index: U32, hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32, message: String) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    actual : VType <- stack_type_found(M.nth(VType, stack, index), file, method, offset, "required typed operand is missing")
    require(verifier_value_assignable(actual, expected, hierarchy), local_error(file, method, offset, message))
    return Unit{}

def validate_field_store_state(expected: M.JvmType, state: State, hierarchy: Hierarchy, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  match state:
    case State{locals, stack, uninitializedThis}:
      validate_stack_value(expected, stack, 0, hierarchy, file, method, offset, "field value type does not match its descriptor")

def validate_field_store(index: U32, state: State, pool: +List<M.Constant>, hierarchy: Hierarchy, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    member : CP.Member <- CP.member(pool, index)
    expected : M.JvmType <- D.parse_field(CP.member_descriptor(member))
    result : Unit <- validate_field_store_state(expected, state, hierarchy, file, method, offset)
    return result

def validate_return_value_state(expected: M.JvmType, state: State, hierarchy: Hierarchy, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  match state:
    case State{locals, stack, uninitializedThis}:
      validate_stack_value(expected, stack, 0, hierarchy, file, method, offset, "areturn value is not assignable to the method result")

def validate_return_value(state: State, +method: M.Method, hierarchy: Hierarchy, file: M.ClassFile, offset: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    descriptor : M.Descriptor <- D.parse_method(method_descriptor(method))
    expected : M.JvmType = D.result_type(descriptor)
    result : Unit <- validate_return_value_state(expected, state, hierarchy, file, method, offset)
    return result

def validate_argument_types(parameters: +List<M.JvmType>, +stack: +List<VType>, +index: U32, +hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  match parameters:
    case Nil{}: Done{Unit{}}
    case Con{parameter, rest}:
      do Result<&2, &2, String, Unit>:
        actual : VType <- stack_type_found(M.nth(VType, stack, index), file, method, offset, "invocation argument missing from operand stack")
        require(verifier_value_assignable(actual, parameter, hierarchy), local_error(file, method, offset, "invocation argument type is not assignable to its descriptor"))
        result : Unit <- validate_argument_types(rest, stack, (index + 1 : U32), hierarchy, file, method, offset)
        return result

def validate_call_arguments_parsed(parsed: M.Descriptor, state: State, hierarchy: Hierarchy, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  match state:
    case State{locals, stack, uninitializedThis}:
      validate_argument_types(M.reverse(M.JvmType, D.parameter_types(parsed)), stack, 0, hierarchy, file, method, offset)

def validate_call_arguments(+op: U32, +index: U32, state: State, +pool: +List<M.Constant>, +hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    validate_call_staticness(op, index, pool, hierarchy, file, method, offset)
    descriptor : String <- invocation_descriptor(op, index, pool)
    parsed : M.Descriptor <- D.parse_method(descriptor)
    result : Unit <- validate_call_arguments_parsed(parsed, state, hierarchy, file, method, offset)
    return result

def validate_invocation_arguments(instruction: M.Instruction, state: State, pool: +List<M.Constant>, file: M.ClassFile, method: M.Method, hierarchy: Hierarchy) -> Result<&2, &2, String, Unit>:
  match instruction:
    case M.Instruction{+op, a, b, c, offset}:
      match op:
        case 179: validate_field_store(a, state, pool, hierarchy, file, method, offset)
        case 181: validate_field_store(a, state, pool, hierarchy, file, method, offset)
        case 176: validate_return_value(state, method, hierarchy, file, offset)
        case 182: validate_call_arguments(op, a, state, pool, hierarchy, file, method, offset)
        case 183: validate_call_arguments(op, a, state, pool, hierarchy, file, method, offset)
        case 184: validate_call_arguments(op, a, state, pool, hierarchy, file, method, offset)
        case 185: validate_call_arguments(op, a, state, pool, hierarchy, file, method, offset)
        case 186: validate_call_arguments(op, a, state, pool, hierarchy, file, method, offset)
        case _: Done{Unit{}}
def stack_slots(values: +List<VType>) -> U32:
  match values:
    case Nil{}: 0
    case Con{value, rest}: (width(vtag(value)) + stack_slots(rest) : U32)


def transfer_new_state(name: String, state: State, +offset: U32, file: M.ClassFile, method: M.Method, maxStack: U32) -> Result<&2, &2, String, State>:
  match state:
    case State{locals, stack, uninitializedThis}:
      do Result<&2, &2, String, State>:
        +grown : +List<VType> = Con{VUninitialized{offset, name}, stack}
        require(U32.is_le(add_width_rest(grown), maxStack), local_error(file, method, offset, "max_stack exceeded by new"))
        return State{locals, grown, False{}}

def transfer_checkcast_stack(name: String, locals: +List<VType>, stack: +List<VType>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, State>:
  do Result<&2, &2, String, State>:
    +popped : StackRead <- stack_pop(stack, 3, file, method, offset)
    require(Bool.not(is_uninit(stack_read_value(popped))), local_error(file, method, offset, "checkcast applied to uninitialized reference"))
    return State{locals, Con{VRef{name}, stack_read_rest(popped)}, False{}}

def transfer_checkcast_state(name: String, state: State, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  match state:
    case State{locals, stack, uninitializedThis}: transfer_checkcast_stack(name, locals, stack, file, method, offset)

def type_of_load_constant(entry: M.Constant) -> VType:
  match entry:
    case M.Index{7, index}: VRef{"java/lang/Class"}
    case M.Index{8, index}: VRef{"java/lang/String"}
    case M.PairIndex{15, kind, index}: VRef{"java/lang/invoke/MethodHandle"}
    case M.Index{16, index}: VRef{"java/lang/invoke/MethodType"}
    case _: VTop{}

def transfer_typed_ldc_stack(locals: +List<VType>, stack: +List<VType>, resultType: VType) -> Result<&2, &2, String, State>:
  match stack:
    case Con{+value, rest}:
      Done{State{locals, Con{Bool.pick(VType, U32.is_eq(vtag(value), 3), resultType, value), rest}, False{}}}
    case Nil{}: Done{State{locals, Nil{}, False{}}}

def transfer_typed_ldc_result(next: State, resultType: VType) -> Result<&2, &2, String, State>:
  match next:
    case State{locals, stack, uninitializedThis}: transfer_typed_ldc_stack(locals, stack, resultType)

def transfer_typed_ldc(rule: I.Rule, state: State, +instruction: M.Instruction, file: M.ClassFile, method: M.Method, pool: +List<M.Constant>, maxStack: U32) -> Result<&2, &2, String, State>:
  match instruction:
    case M.Instruction{op, +a, b, c, offset}:
      do Result<&2, &2, String, State>:
        entry : M.Constant <- CP.get(pool, a)
        resultType : VType = type_of_load_constant(entry)
        next : State <- apply_simple(rule, state, instruction, file, method, maxStack)
        result : State <- transfer_typed_ldc_result(next, resultType)
        return result

def aaload_element_type(arrayType: VType, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, M.JvmType>:
  match arrayType:
    case VRef{name}: D.parse_field(array_component_descriptor(name))
    case VNull{}: Done{M.ObjectType{"java/lang/Object"}}
    case _: Fail{local_error(file, method, offset, "aaload requires a reference array")}

def replace_call_result_stack(locals: +List<VType>, stack: +List<VType>, result: M.JvmType) -> State:
  match stack:
    case Nil{}: State{locals, Nil{}, False{}}
    case Con{value, rest}: State{locals, Con{type_of_jvm(result), rest}, False{}}

def replace_call_result_state(state: State, result: M.JvmType) -> State:
  match state:
    case State{locals, stack, uninitializedThis}: replace_call_result_stack(locals, stack, result)

def replace_call_result(state: State, result: M.JvmType) -> State:
  match result:
    case M.Primitive{86}: state
    case _: replace_call_result_state(state, result)

def transfer_aaload(rule: I.Rule, +state: State, +instruction: M.Instruction, +file: M.ClassFile, +method: M.Method, maxStack: U32) -> Result<&2, &2, String, State>:
  match instruction:
    case M.Instruction{op, a, b, c, +offset}:
      do Result<&2, &2, String, State>:
        arrayType : VType <- stack_type_at(state, 1, file, method, offset, "aaload array operand is missing")
        elementType : M.JvmType <- aaload_element_type(arrayType, file, method, offset)
        next : State <- apply_simple(rule, state, instruction, file, method, maxStack)
        return replace_call_result(next, elementType)

def array_class_descriptor(name: String) -> String:
  match name:
    case SCon{Chr{91}, rest}: "[" ++ name
    case _: "[L" ++ name ++ ";"

def array_creation_type(op: U32, operand: U32, pool: +List<M.Constant>) -> Result<&2, &2, String, M.JvmType>:
  match op:
    case 188:
      match operand:
        case 4: Done{M.ArrayType{M.Primitive{90}}}
        case 5: Done{M.ArrayType{M.Primitive{67}}}
        case 6: Done{M.ArrayType{M.Primitive{70}}}
        case 7: Done{M.ArrayType{M.Primitive{68}}}
        case 8: Done{M.ArrayType{M.Primitive{66}}}
        case 9: Done{M.ArrayType{M.Primitive{83}}}
        case 10: Done{M.ArrayType{M.Primitive{73}}}
        case 11: Done{M.ArrayType{M.Primitive{74}}}
        case _: Fail{"VerifyError: invalid newarray primitive type"}
    case _:
      do Result<&2, &2, String, M.JvmType>:
        name : String <- CP.class_name(pool, operand)
        descriptor : String = array_class_descriptor(name)
        value : M.JvmType <- D.parse_field(descriptor)
        return value

def transfer_array_creation(rule: I.Rule, state: State, +instruction: M.Instruction, file: M.ClassFile, method: M.Method, pool: +List<M.Constant>, maxStack: U32) -> Result<&2, &2, String, State>:
  match instruction:
    case M.Instruction{+op, +a, b, c, offset}:
      do Result<&2, &2, String, State>:
        valueType : M.JvmType <- array_creation_type(op, a, pool)
        next : State <- apply_simple(rule, state, instruction, file, method, maxStack)
        return replace_call_result(next, valueType)

def transfer_multi_array(rule: I.Rule, state: State, +instruction: M.Instruction, file: M.ClassFile, method: M.Method, pool: +List<M.Constant>, maxStack: U32) -> Result<&2, &2, String, State>:
  match instruction:
    case M.Instruction{op, +a, b, c, offset}:
      do Result<&2, &2, String, State>:
        name : String <- CP.class_name(pool, a)
        valueType : M.JvmType <- D.parse_field(name)
        next : State <- apply_simple(rule, state, instruction, file, method, maxStack)
        return replace_call_result(next, valueType)

def transfer_field_result(rule: I.Rule, state: State, +instruction: M.Instruction, file: M.ClassFile, method: M.Method, pool: +List<M.Constant>, maxStack: U32) -> Result<&2, &2, String, State>:
  match instruction:
    case M.Instruction{op, +a, b, c, offset}:
      do Result<&2, &2, String, State>:
        member : CP.Member <- CP.member(pool, a)
        valueType : M.JvmType <- D.parse_field(CP.member_descriptor(member))
        next : State <- apply_simple(rule, state, instruction, file, method, maxStack)
        return replace_call_result(next, valueType)

def transfer_call_result(rule: I.Rule, state: State, +instruction: M.Instruction, file: M.ClassFile, method: M.Method, pool: +List<M.Constant>, maxStack: U32) -> Result<&2, &2, String, State>:
  match instruction:
    case M.Instruction{+op, +a, b, c, offset}:
      do Result<&2, &2, String, State>:
        descriptor : String <- invocation_descriptor(op, a, pool)
        parsed : M.Descriptor <- D.parse_method(descriptor)
        result : M.JvmType = D.result_type(parsed)
        next : State <- apply_simple(rule, state, instruction, file, method, maxStack)
        return replace_call_result(next, result)

def constructor_owner_ok(receiver: VType, +target: String, file: M.ClassFile) -> Bool:
  match receiver:
    case VUninitialized{offset, name}: String.eq(name, target)
    case VUninitializedThis{name}: String.eq(name, target) || String.eq(class_parent(file), target)
    case _: False{}

def initialize_type(value: VType) -> VType:
  match value:
    case VUninitialized{offset, name}: VRef{name}
    case VUninitializedThis{name}: VRef{name}
    case _: value

def same_type(left: VType, right: VType) -> Bool:
  match left right:
    case VTop{} VTop{}: True{}
    case VUnusable{} VUnusable{}: True{}
    case VInt{} VInt{}: True{}
    case VFloat{} VFloat{}: True{}
    case VLong{} VLong{}: True{}
    case VDouble{} VDouble{}: True{}
    case VNull{} VNull{}: True{}
    case VRef{name} VRef{other}: String.eq(name, other)
    case VUninitializedThis{name} VUninitializedThis{other}: String.eq(name, other)
    case VUninitialized{offset, name} VUninitialized{otherOffset, otherName}: U32.is_eq(offset, otherOffset) && String.eq(name, otherName)
    case _ _: False{}

def replace_alias(values: +List<VType>, +old: VType, +fresh: VType) -> +List<VType>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      Con{Bool.pick(VType, same_type(value, old), fresh, value), replace_alias(rest, old, fresh)}

def replace_alias_state(state: State, +old: VType, +fresh: VType) -> State:
  match state:
    case State{locals, stack, uninitializedThis}: State{replace_alias(locals, old, fresh), replace_alias(stack, old, fresh), uninitializedThis}

def transfer_invokespecial_kind(isConstructor: Bool, rule: I.Rule, +state: State, +instruction: M.Instruction, +file: M.ClassFile, +method: M.Method, +pool: +List<M.Constant>, maxStack: U32, +member: CP.Member, +offset: U32) -> Result<&2, &2, String, State>:
  match isConstructor:
    case False{}:
      do Result<&2, &2, String, State>:
        descriptor : M.Descriptor <- D.parse_method(CP.member_descriptor(member))
        receiverIndex : U32 = D.parameter_count(descriptor)
        receiver : VType <- stack_type_at(state, receiverIndex, file, method, offset, "invokespecial receiver missing below arguments")
        require(Bool.not(is_uninit(receiver)), local_error(file, method, offset, "non-constructor invokespecial uses an uninitialized receiver"))
        result : State <- transfer_call_result(rule, state, instruction, file, method, pool, maxStack)
        return result
    case True{}:
      do Result<&2, &2, String, State>:
        descriptor : M.Descriptor <- D.parse_method(CP.member_descriptor(member))
        receiverIndex : U32 = D.parameter_count(descriptor)
        +receiver : VType <- stack_type_at(state, receiverIndex, file, method, offset, "constructor receiver missing below arguments")
        constructorOwner : String = CP.member_owner(member)
        require(constructor_owner_ok(receiver, constructorOwner, file), local_error(file, method, offset, "invokespecial constructor owner does not match uninitialized receiver"))
        initialized : VType = initialize_type(receiver)
        next : State <- apply_simple(rule, state, instruction, file, method, maxStack)
        result : State = replace_alias_state(next, receiver, initialized)
        return result

def transfer_invokespecial_member(rule: I.Rule, state: State, instruction: M.Instruction, file: M.ClassFile, method: M.Method, pool: +List<M.Constant>, maxStack: U32, +member: CP.Member, offset: U32) -> Result<&2, &2, String, State>:
  transfer_invokespecial_kind(String.eq(CP.member_name(member), "<init>"), rule, state, instruction, file, method, pool, maxStack, member, offset)

def transfer_invokespecial(rule: I.Rule, state: State, +instruction: M.Instruction, file: M.ClassFile, method: M.Method, +pool: +List<M.Constant>, maxStack: U32) -> Result<&2, &2, String, State>:
  match instruction:
    case M.Instruction{op, a, b, c, +offset}:
      do Result<&2, &2, String, State>:
        member : CP.Member <- CP.member(pool, a)
        result : State <- transfer_invokespecial_member(rule, state, instruction, file, method, pool, maxStack, member, offset)
        return result

def replace_top_state(state: State, value: VType) -> State:
  match state:
    case State{locals, Con{top, rest}, uninitializedThis}: State{locals, Con{value, rest}, uninitializedThis}
    case other: other

# aconst_null pushes the verifier null type, assignable to every reference type.
def transfer_null(rule: I.Rule, state: State, instruction: M.Instruction, file: M.ClassFile, method: M.Method, maxStack: U32) -> Result<&2, &2, String, State>:
  do Result<&2, &2, String, State>:
    next : State <- apply_simple(rule, state, instruction, file, method, maxStack)
    return replace_top_state(next, VNull{})

def transfer_rule(rule: I.Rule, state: State, instruction: M.Instruction, file: M.ClassFile, method: M.Method, pool: +List<M.Constant>, maxStack: U32) -> Result<&2, &2, String, State>:
  match instruction:
    case M.Instruction{op, a, b, c, offset}:
      match op:
        case 187:
          do Result<&2, &2, String, State>:
            name : String <- CP.class_name(pool, a)
            next : State <- transfer_new_state(name, state, offset, file, method, maxStack)
            return next
        case 192:
          do Result<&2, &2, String, State>:
            name : String <- CP.class_name(pool, a)
            next : State <- transfer_checkcast_state(name, state, file, method, offset)
            return next
        case 18: transfer_typed_ldc(rule, state, instruction, file, method, pool, maxStack)
        case 19: transfer_typed_ldc(rule, state, instruction, file, method, pool, maxStack)
        case 188: transfer_array_creation(rule, state, instruction, file, method, pool, maxStack)
        case 189: transfer_array_creation(rule, state, instruction, file, method, pool, maxStack)
        case 197: transfer_multi_array(rule, state, instruction, file, method, pool, maxStack)
        case 182: transfer_call_result(rule, state, instruction, file, method, pool, maxStack)
        case 184: transfer_call_result(rule, state, instruction, file, method, pool, maxStack)
        case 178: transfer_field_result(rule, state, instruction, file, method, pool, maxStack)
        case 180: transfer_field_result(rule, state, instruction, file, method, pool, maxStack)
        case 185: transfer_call_result(rule, state, instruction, file, method, pool, maxStack)
        case 186: transfer_call_result(rule, state, instruction, file, method, pool, maxStack)
        case 183: transfer_invokespecial(rule, state, instruction, file, method, pool, maxStack)
        case 50: transfer_aaload(rule, state, instruction, file, method, maxStack)
        case 1: transfer_null(rule, state, instruction, file, method, maxStack)
        case _: apply_simple(rule, state, instruction, file, method, maxStack)



def checked_transfer_state(next: State, instruction: M.Instruction, +method: M.Method, +file: M.ClassFile) -> Result<&2, &2, String, State>:
  match next instruction:
    case State{+locals, +stack, +uninitializedThis} M.Instruction{+op, a, b, c, +offset}:
      do Result<&2, &2, String, State>:
        require(U32.is_le(stack_slots(stack), method_max_stack(method)), local_error(file, method, offset, "max_stack exceeded"))
        require(Bool.not(U32.is_eq(op, 177) && String.eq(method_name(method), "<init>")) || Bool.not(uninitializedThis), local_error(file, method, offset, "constructor returns before this is initialized"))
        return State{locals, stack, uninitializedThis}

def constructor_initializes_this_member(isConstructor: Bool, +member: CP.Member, state: State, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Bool>:
  match isConstructor:
    case False{}: Done{False{}}
    case True{}:
      do Result<&2, &2, String, Bool>:
        descriptor : M.Descriptor <- D.parse_method(CP.member_descriptor(member))
        receiver : VType <- stack_type_at(state, D.parameter_count(descriptor), file, method, offset, "constructor receiver missing before initialization")
        return is_uninitialized_this(receiver)

def constructor_initializes_this_instruction(isSpecial: Bool, index: U32, state: State, pool: +List<M.Constant>, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, Bool>:
  match isSpecial:
    case False{}: Done{False{}}
    case True{}:
      do Result<&2, &2, String, Bool>:
        +member : CP.Member <- CP.member(pool, index)
        is_this : Bool <- constructor_initializes_this_member(String.eq(CP.member_name(member), "<init>"), member, state, file, method, offset)
        return is_this

def constructor_initializes_instruction(instruction: M.Instruction, state: State, pool: +List<M.Constant>, file: M.ClassFile, method: M.Method) -> Result<&2, &2, String, Bool>:
  match instruction:
    case M.Instruction{op, a, b, c, offset}:
      constructor_initializes_this_instruction(U32.is_eq(op, 183), a, state, pool, file, method, offset)

def checked_transfer(rule: I.Rule, +state: State, +instruction: M.Instruction, +file: M.ClassFile, +method: M.Method, +pool: +List<M.Constant>, maxStack: U32) -> Result<&2, &2, String, State>:
  do Result<&2, &2, String, State>:
    next : State <- transfer_rule(rule, state, instruction, file, method, pool, maxStack)
    isThisInitialization : Bool <- constructor_initializes_instruction(instruction, state, pool, file, method)
    nextUninitialized : Bool = state_uninitialized_this(state) && Bool.not(isThisInitialization)
    checked : State <- checked_transfer_state(state_with_uninitialized_this(next, nextUninitialized), instruction, method, file)
    return checked

def transfer(+instruction: M.Instruction, +state: State, +file: M.ClassFile, +method: M.Method, +pool: +List<M.Constant>, expected: U32, maxLocals: U32, maxStack: U32, +hierarchy: Hierarchy) -> Result<&2, &2, String, State>:
  do Result<&2, &2, String, State>:
    validate_invocation_receiver(instruction, state, pool, file, method, hierarchy)
    validate_reference_consumers(instruction, state, file, method)
    validate_array_instruction(instruction, state, hierarchy, file, method)
    validate_invocation_arguments(instruction, state, pool, file, method, hierarchy)
    rule : I.Rule <- I.verify(instruction, pool, expected, maxLocals)
    next : State <- checked_transfer(rule, state, instruction, file, method, pool, maxStack)
    return next

def find_instruction(instructions: +List<M.Instruction>, +pc: U32, +current: U32) -> Maybe<&2, M.Instruction>:
  match instructions:
    case Nil{}: None{}
    case Con{instruction, rest}:
      Bool.pick(Maybe<&2, M.Instruction>, U32.is_eq(pc, current), Some{instruction}, find_instruction(rest, pc, (current + 1 : U32)))


def fill_locals(count: Nat, acc: +List<VType>) -> +List<VType>:
  match count:
    case 0n: M.reverse(VType, acc)
    case 1n+rest: fill_locals(rest, Con{VTop{}, acc})


def init_parameters(params: +List<M.JvmType>, +index: U32, +locals: +List<VType>, +maxLocals: U32, +owner: String, +method: M.Method) -> Result<&2, &2, String, +List<VType>>:
  match params:
    case Nil{}: Done{locals}
    case Con{+typ, rest}:
      do Result<&2, &2, String, +List<VType>>:
        +valueWidth : U32 = D.slots(typ)
        require(U32.is_le((index + valueWidth : U32), maxLocals), fail(owner, method_name(method), method_descriptor(method), 0, "Descriptor", "parameters exceed max_locals"))
        next : +List<VType> = put_initial(locals, index, type_of_jvm(typ), valueWidth)
        init_parameters(rest, (index + valueWidth : U32), next, maxLocals, owner, method)

def initial_locals(+owner: String, +method: M.Method, +params: +List<M.JvmType>, +maxLocals: U32) -> Result<&2, &2, String, +List<VType>>:
  do Result<&2, &2, String, +List<VType>>:
    +blank : +List<VType> = fill_locals(U32.to_nat(maxLocals), Nil{})
    +isStatic : Bool = U32.is_ne(U32.and(method_flags(method), 8), 0)
    +start : U32 = Bool.pick(U32, isStatic, 0, 1)
    receiver : VType = Bool.pick(VType, String.eq(method_name(method), "<init>"), VUninitializedThis{owner}, VRef{owner})
    seeded : +List<VType> = Bool.pick(+List<VType>, isStatic, blank, replace_nth(blank, 0, receiver))
    require(U32.is_le((start + D.parameter_slots(params) : U32), maxLocals), fail(owner, method_name(method), method_descriptor(method), 0, "Descriptor", "receiver and parameters exceed max_locals"))
    init_parameters(params, start, seeded, maxLocals, owner, method)
def initial_state(file: M.ClassFile, +method: M.Method, maxLocals: U32) -> Result<&2, &2, String, State>:
  do Result<&2, &2, String, State>:
    descriptor : M.Descriptor <- D.parse_method(method_descriptor(method))
    locals : +List<VType> <- initial_locals(class_name(file), method, D.parameter_types(descriptor), maxLocals)
    return State{locals, Nil{}, String.eq(method_name(method), "<init>")}


def validate_instruction_rule_result(found: Result<&2, &2, String, I.Rule>, +owner: M.ClassFile, +method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  match found:
    case Fail{error}: Fail{fail(class_name(owner), method_name(method), method_descriptor(method), offset, "Instruction", error)}
    case Done{_}: Done{Unit{}}

def validate_instruction_rules(instructions: +List<M.Instruction>, +pool: +List<M.Constant>, +expected: U32, +maxLocals: U32, +owner: M.ClassFile, +method: M.Method) -> Result<&2, &2, String, Unit>:
  match instructions:
    case Nil{}: Done{Unit{}}
    case Con{+instruction, rest}:
      do Result<&2, &2, String, Unit>:
        validate_instruction_rule_result(I.verify(instruction, pool, expected, maxLocals), owner, method, instruction_offset(instruction))
        result : Unit <- validate_instruction_rules(rest, pool, expected, maxLocals, owner, method)
        return result




def constructor_exception_clear_receiver(state: State, +receiver: VType) -> Result<&2, &2, String, State>:
  match state:
    case State{locals, stack, uninitializedThis}: Done{State{replace_alias(locals, receiver, VTop{}), stack, uninitializedThis || is_uninitialized_this(receiver)}}

def constructor_exception_uninitialized(uninitialized: Bool, state: State, receiver: VType) -> Result<&2, &2, String, State>:
  match uninitialized:
    case False{}: Done{state}
    case True{}: constructor_exception_clear_receiver(state, receiver)

def constructor_exception_member(isConstructor: Bool, +member: CP.Member, +state: State, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, State>:
  match isConstructor:
    case False{}: Done{state}
    case True{}:
      do Result<&2, &2, String, State>:
        descriptor : M.Descriptor <- D.parse_method(CP.member_descriptor(member))
        receiverIndex : U32 = D.parameter_count(descriptor)
        +receiver : VType <- stack_type_at(state, receiverIndex, file, method, offset, "constructor receiver missing on exceptional edge")
        result : State <- constructor_exception_uninitialized(is_uninit(receiver), state, receiver)
        return result

def constructor_exception_opcode(isSpecial: Bool, state: State, pool: +List<M.Constant>, file: M.ClassFile, method: M.Method, index: U32, offset: U32) -> Result<&2, &2, String, State>:
  match isSpecial:
    case False{}: Done{state}
    case True{}:
      do Result<&2, &2, String, State>:
        +member : CP.Member <- CP.member(pool, index)
        result : State <- constructor_exception_member(String.eq(CP.member_name(member), "<init>"), member, state, file, method, offset)
        return result

def constructor_exception_state(instruction: M.Instruction, state: State, pool: +List<M.Constant>, file: M.ClassFile, method: M.Method) -> Result<&2, &2, String, State>:
  match instruction:
    case M.Instruction{op, a, b, c, offset}:
      constructor_exception_opcode(U32.is_eq(op, 183), state, pool, file, method, a, offset)

def trim_top_slots(reversedValues: +List<VType>) -> +List<VType>:
  match reversedValues:
    case Con{VTop{}, rest}: trim_top_slots(rest)
    case _: reversedValues

def compact_slots(values: +List<VType>) -> +List<VType>:
  match values:
    case Nil{}: Nil{}
    case Con{VLong{}, Con{VUnusable{}, rest}}: Con{VLong{}, compact_slots(rest)}
    case Con{VDouble{}, Con{VUnusable{}, rest}}: Con{VDouble{}, compact_slots(rest)}
    case Con{VUnusable{}, rest}: Con{VTop{}, compact_slots(rest)}
    case Con{value, rest}: Con{value, compact_slots(rest)}
def compact_locals(values: +List<VType>) -> +List<VType>:
  compact_slots(M.reverse(VType, trim_top_slots(M.reverse(VType, values))))

def drop_prefix(+values: +List<VType>, +count: U32, file: M.ClassFile, +method: M.Method, offset: U32) -> Result<&2, &2, String, +List<VType>>:
  match values count:
    case _ 0: Done{values}
    case Nil{} _: Fail{fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "chop frame removes more locals than exist")}
    case Con{value, rest} _: drop_prefix(rest, (count - 1 : U32), file, method, offset)

def drop_last_logical(values: +List<VType>, count: U32, file: M.ClassFile, method: M.Method, offset: U32) -> Result<&2, &2, String, +List<VType>>:
  do Result<&2, &2, String, +List<VType>>:
    reversed : +List<VType> = M.reverse(VType, values)
    remaining : +List<VType> <- drop_prefix(reversed, count, file, method, offset)
    return M.reverse(VType, remaining)

def append_top_locals(count: Nat, values: +List<VType>) -> +List<VType>:
  match count:
    case 0n: values
    case 1n+p: append_top_locals(p, M.append(VType, values, [VTop{}]))

def expand_type_slots(values: +List<VType>, reversedAcc: +List<VType>) -> +List<VType>:
  match values:
    case Nil{}: M.reverse(VType, reversedAcc)
    case Con{value, rest}:
      match value:
        case VLong{}: expand_type_slots(rest, Con{VUnusable{}, Con{value, reversedAcc}})
        case VDouble{}: expand_type_slots(rest, Con{VUnusable{}, Con{value, reversedAcc}})
        case _: expand_type_slots(rest, Con{value, reversedAcc})
def expand_local_types(values: +List<VType>, +maxLocals: U32, file: M.ClassFile, +method: M.Method, offset: U32) -> Result<&2, &2, String, +List<VType>>:
  do Result<&2, &2, String, +List<VType>>:
    +expanded : +List<VType> = expand_type_slots(values, Nil{})
    require(U32.is_le(M.length(VType, expanded), maxLocals), fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "frame locals exceed max_locals"))
    return append_top_locals(U32.to_nat((maxLocals - M.length(VType, expanded) : U32)), expanded)

def frame_offset(frame: SM.Frame) -> U32:
  match frame:
    case SM.Same{offset}: offset
    case SM.SameLocalsOne{offset, stack}: offset
    case SM.Chop{offset, count}: offset
    case SM.Append{offset, locals}: offset
    case SM.Full{offset, locals, stack}: offset
def expand_verification_slot_value(converted: VType, slotWidth: U32, acc: +List<VType>) -> +List<VType>:
  match slotWidth:
    case 2: Con{VUnusable{}, Con{converted, acc}}
    case _: Con{converted, acc}
def verification_width(value: SM.Verification) -> U32:
  match value:
    case SM.Long{}: 2
    case SM.Double{}: 2
    case _: 1




def find_offset_required(found: Maybe<&2, M.Instruction>, file: M.ClassFile, +method: M.Method, frameOffset: U32) -> Result<&2, &2, String, M.Instruction>:
  match found:
    case None{}: Fail{fail(class_name(file), method_name(method), method_descriptor(method), frameOffset, "StackMap", "uninitialized value does not identify an instruction")}
    case Some{value}: Done{value}

def instruction_operand(value: M.Instruction) -> U32:
  match value:
    case M.Instruction{op, a, b, c, offset}: a

def find_offset(instructions: +List<M.Instruction>, +offset: U32) -> Maybe<&2, M.Instruction>:
  match instructions:
    case Nil{}: None{}
    case Con{+instruction, rest}:
      Bool.pick(Maybe<&2, M.Instruction>, U32.is_eq(instruction_offset(instruction), offset), Some{instruction}, find_offset(rest, offset))
def convert_verification(value: SM.Verification, instructions: +List<M.Instruction>, pool: +List<M.Constant>, +file: M.ClassFile, +method: M.Method, +frameOffset: U32) -> Result<&2, &2, String, VType>:
  match value:
    case SM.Top{}: Done{VTop{}}
    case SM.Integer{}: Done{VInt{}}
    case SM.Float{}: Done{VFloat{}}
    case SM.Long{}: Done{VLong{}}
    case SM.Double{}: Done{VDouble{}}
    case SM.Null{}: Done{VNull{}}
    case SM.UninitializedThis{}: Done{VUninitializedThis{class_name(file)}}
    case SM.Object{index, name}: Done{VRef{name}}
    case SM.Uninitialized{+offset}:
      do Result<&2, &2, String, VType>:
        +instruction : M.Instruction <- find_offset_required(find_offset(instructions, offset), file, method, frameOffset)
        require(U32.is_eq(instruction_opcode(instruction), 187), fail(class_name(file), method_name(method), method_descriptor(method), frameOffset, "StackMap", "uninitialized value does not identify new"))
        name : String <- CP.class_name(pool, instruction_operand(instruction))
        return VUninitialized{offset, name}
def convert_verifications(values: +List<SM.Verification>, +instructions: +List<M.Instruction>, +pool: +List<M.Constant>, +file: M.ClassFile, +method: M.Method, +frameOffset: U32) -> Result<&2, &2, String, +List<VType>>:
  match values:
    case Nil{}: Done{Nil{}}
    case Con{value, rest}:
      do Result<&2, &2, String, +List<VType>>:
        converted : VType <- convert_verification(value, instructions, pool, file, method, frameOffset)
        tail : +List<VType> <- convert_verifications(rest, instructions, pool, file, method, frameOffset)
        return Con{converted, tail}
def expand_verification_slots(values: +List<SM.Verification>, +instructions: +List<M.Instruction>, +pool: +List<M.Constant>, +file: M.ClassFile, +method: M.Method, +frameOffset: U32, acc: +List<VType>) -> Result<&2, &2, String, +List<VType>>:
  match values:
    case Nil{}: Done{M.reverse(VType, acc)}
    case Con{+value, rest}:
      do Result<&2, &2, String, +List<VType>>:
        converted : VType <- convert_verification(value, instructions, pool, file, method, frameOffset)
        next : +List<VType> = expand_verification_slot_value(converted, verification_width(value), acc)
        tail : +List<VType> <- expand_verification_slots(rest, instructions, pool, file, method, frameOffset, next)
        return tail
def expand_frame_locals(values: +List<SM.Verification>, +maxLocals: U32, +instructions: +List<M.Instruction>, +pool: +List<M.Constant>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, +List<VType>>:
  do Result<&2, &2, String, +List<VType>>:
    +expanded : +List<VType> <- expand_verification_slots(values, instructions, pool, file, method, offset, Nil{})
    require(U32.is_le(M.length(VType, expanded), maxLocals), fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "full-frame locals exceed max_locals"))
    return append_top_locals(U32.to_nat((maxLocals - M.length(VType, expanded) : U32)), expanded)
def apply_frame(frame: SM.Frame, +previous: State, +instructions: +List<M.Instruction>, +pool: +List<M.Constant>, +maxLocals: U32, +file: M.ClassFile, +method: M.Method) -> Result<&2, &2, String, State>:
  match frame:
    case SM.Same{offset}: Done{State{state_locals(previous), Nil{}, state_uninitialized_this(previous)}}
    case SM.SameLocalsOne{+offset, stack}:
      do Result<&2, &2, String, State>:
        value : VType <- convert_verification(stack, instructions, pool, file, method, offset)
        return State{state_locals(previous), [value], state_uninitialized_this(previous)}
    case SM.Chop{+offset, count}:
      do Result<&2, &2, String, State>:
        logical : +List<VType> = compact_locals(state_locals(previous))
        chopped : +List<VType> <- drop_last_logical(logical, count, file, method, offset)
        locals : +List<VType> <- expand_local_types(chopped, maxLocals, file, method, offset)
        return State{locals, Nil{}, state_uninitialized_this(previous)}
    case SM.Append{+offset, locals}:
      do Result<&2, &2, String, State>:
        logical : +List<VType> = compact_locals(state_locals(previous))
        added : +List<VType> <- convert_verifications(locals, instructions, pool, file, method, offset)
        expanded : +List<VType> <- expand_local_types(M.append(VType, logical, added), maxLocals, file, method, offset)
        return State{expanded, Nil{}, state_uninitialized_this(previous)}
    case SM.Full{+offset, locals, stack}:
      do Result<&2, &2, String, State>:
        expanded : +List<VType> <- expand_frame_locals(locals, maxLocals, instructions, pool, file, method, offset)
        stackValues : +List<VType> <- convert_verifications(stack, instructions, pool, file, method, offset)
        # StackMapTable lists the operand stack bottom-to-top; State stacks are top-first.
        return State{expanded, M.reverse(VType, stackValues), state_uninitialized_this(previous)}


def assignable_type(actual: VType, expected: VType, +hierarchy: Hierarchy) -> Bool:
  match actual expected:
    case VNull{} VRef{name}: True{}
    case VRef{+actualName} VRef{+expectedName}: reference_names_assignable(actualName, expectedName, hierarchy)
    case _ VTop{}: True{}
    case actualType expectedType: same_type(actualType, expectedType)

def assignable_types(actual: +List<VType>, expected: +List<VType>, +hierarchy: Hierarchy) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case Con{a, as_} Con{e, es}: assignable_type(a, e, hierarchy) && assignable_types(as_, es, hierarchy)
    case _ _: False{}

def has_top(values: +List<VType>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{VTop{}, rest}: True{}
    case Con{value, rest}: has_top(rest)

def state_assignable(actual: State, expected: State, +hierarchy: Hierarchy) -> Bool:
  match actual expected:
    case State{locals, stack, uninitializedThis} State{expectedLocals, +expectedStack, expectedUninitialized}:
      assignable_types(locals, expectedLocals, hierarchy) && assignable_types(stack, expectedStack, hierarchy) && Bool.not(has_top(expectedStack))


def requires_fallthrough(instruction: M.Instruction) -> Bool:
  match instruction:
    case M.Instruction{+op, a, b, c, offset}:
      Bool.not(U32.is_eq(op, 167) || U32.is_eq(op, 170) || U32.is_eq(op, 171) || U32.is_eq(op, 191) || U32.is_eq(op, 200) || (U32.is_ge(op, 172) && U32.is_le(op, 177)))


def has_byte_offset(instructions: +List<M.Instruction>, +offset: U32) -> Bool:
  match instructions:
    case Nil{}: False{}
    case Con{M.Instruction{op, a, b, c, at}, rest}:
      Bool.pick(Bool, U32.is_eq(at, offset), True{}, has_byte_offset(rest, offset))



def verification_slots(values: +List<SM.Verification>) -> U32:
  match values:
    case Nil{}: 0
    case Con{value, rest}: (verification_width(value) + verification_slots(rest) : U32)





def validate_handler_catch(isCatchAll: Bool, catch: U32, pool: +List<M.Constant>, file: M.ClassFile, +method: M.Method, hierarchy: Hierarchy, start: U32) -> Result<&2, &2, String, Unit>:
  match isCatchAll:
    case True{}: Done{Unit{}}
    case False{}:
      do Result<&2, &2, String, Unit>:
        name : String <- CP.class_name(pool, catch)
        require(is_ancestor(name, "java/lang/Throwable", hierarchy_files(hierarchy), 256), fail(class_name(file), method_name(method), method_descriptor(method), start, "ExceptionHandler", "catch type is not Throwable"))
        return Unit{}

def validate_handlers(handlers: +List<M.Handler>, +count: U32, +pool: +List<M.Constant>, +file: M.ClassFile, +method: M.Method, +hierarchy: Hierarchy) -> Result<&2, &2, String, Unit>:
  match handlers:
    case Nil{}: Done{Unit{}}
    case Con{M.Handler{+start, +end, target, +catch}, rest}:
      do Result<&2, &2, String, Unit>:
        require(U32.is_lt(start, end) && U32.is_le(end, count) && U32.is_lt(target, count), fail(class_name(file), method_name(method), method_descriptor(method), start, "ExceptionHandler", "invalid handler range or target"))
        validate_handler_catch(U32.is_eq(catch, 0), catch, pool, file, method, hierarchy, start)
        tail : Unit <- validate_handlers(rest, count, pool, file, method, hierarchy)
        return tail
def handler_state_catch(isCatchAll: Bool, locals: +List<VType>, catch: U32, pool: +List<M.Constant>, uninitializedThis: Bool) -> Result<&2, &2, String, State>:
  match isCatchAll:
    case True{}: Done{State{locals, [VRef{"java/lang/Throwable"}], uninitializedThis}}
    case False{}:
      do Result<&2, &2, String, State>:
        name : String <- CP.class_name(pool, catch)
        return State{locals, [VRef{name}], uninitializedThis}
def handler_state(locals: +List<VType>, handler: M.Handler, pool: +List<M.Constant>, uninitializedThis: Bool) -> Result<&2, &2, String, State>:
  match handler:
    case M.Handler{start, end, target, +catch}:
      handler_state_catch(U32.is_eq(catch, 0), locals, catch, pool, uninitializedThis)


def handler_in_range(handler: M.Handler, +pc: U32) -> Bool:
  match handler:
    case M.Handler{start, end, target, catch}: U32.is_ge(pc, start) && U32.is_lt(pc, end)

def handler_target(handler: M.Handler) -> U32:
  match handler:
    case M.Handler{start, end, target, catch}: target

def class_attributes(value: M.ClassFile) -> +List<M.Attribute>:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}: attributes

def bootstrap_attribute_count(attrs: +List<M.Attribute>) -> U32:
  match attrs:
    case Nil{}: 0
    case Con{M.Attribute{name, bytes}, rest}:
      (Bool.pick(U32, String.eq(name, "BootstrapMethods"), 1, 0) + bootstrap_attribute_count(rest) : U32)
    case Con{M.ValidatedAnnotations{metadata}, rest}: bootstrap_attribute_count(rest)

def validate_bootstrap_kind(isConstructor: Bool, +name: String, descriptor: M.Descriptor) -> Result<&2, &2, String, Unit>:
  match isConstructor:
    case True{}:
      require(String.eq(name, "<init>") && U32.is_eq(D.slot_tag(D.result_type(descriptor)), 0), "VerifyError[BootstrapMethods]: newInvokeSpecial must target a void constructor")
    case False{}:
      require(Bool.not(String.eq(name, "<init>")) && Bool.not(String.eq(name, "<clinit>")), "VerifyError[BootstrapMethods]: invokeStatic cannot target a special method")

def validate_bootstrap_target(+pool: +List<M.Constant>, +kind: U32, reference: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    +member : CP.Member <- CP.member(pool, reference)
    require(U32.is_eq(CP.member_tag(member), 10) || U32.is_eq(CP.member_tag(member), 11), "VerifyError[BootstrapMethods]: bootstrap handle target is not a method reference")
    name : String = CP.member_name(member)
    descriptor : M.Descriptor <- D.parse_method(CP.member_descriptor(member))
    result : Unit <- validate_bootstrap_kind(U32.is_eq(kind, 8), name, descriptor)
    return result

# BootstrapMethods is parsed once by classfile/bootstrap_methods.bend (shared with
# the catalog); the verifier adds the handle-target rules on the parsed table.
def parsed_bootstrap_methods(parsed: Maybe<&2, BM.BootstrapMethods>) -> +List<BM.BootstrapMethod>:
  match parsed:
    case None{}: Nil{}
    case Some{BM.BootstrapMethods{methods}}: methods

def validate_bootstrap_targets(methods: +List<BM.BootstrapMethod>, +pool: +List<M.Constant>) -> Result<&2, &2, String, Unit>:
  match methods:
    case Nil{}: Done{Unit{}}
    case Con{BM.BootstrapMethod{index, methodRef, +handleKind, handleReference, arguments}, rest}:
      do Result<&2, &2, String, Unit>:
        validate_bootstrap_target(pool, handleKind, handleReference)
        tail : Unit <- validate_bootstrap_targets(rest, pool)
        return tail

def validate_bootstrap_metadata(+file: M.ClassFile) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    +attrs : +List<M.Attribute> = class_attributes(file)
    +count : U32 = bootstrap_attribute_count(attrs)
    require(U32.is_le(count, 1), "VerifyError[BootstrapMethods]: duplicate attribute")
    require(U32.is_eq(count, 0) || U32.is_ge(class_major(file), 51), "VerifyError[Version]: BootstrapMethods requires classfile version 51 or later")
    parsed : Maybe<&2, BM.BootstrapMethods> <- BM.parse_class_attributes(attrs, class_pool(file))
    +methods : +List<BM.BootstrapMethod> = parsed_bootstrap_methods(parsed)
    validate_bootstrap_targets(methods, class_pool(file))
    return M.length(BM.BootstrapMethod, methods)
def name_type_name(value: CP.NameType) -> String:
  match value:
    case CP.NameType{name, descriptor}: name

def validate_dynamic_bootstrap_entry(entry: M.Constant, +count: U32, +major: U32, pool: +List<M.Constant>) -> Result<&2, &2, String, Unit>:
  match entry:
    case M.PairIndex{18, bootstrap, nameType}:
      do Result<&2, &2, String, Unit>:
        require(U32.is_ge(major, 51), "VerifyError[Version]: InvokeDynamic requires classfile version 51 or later")
        require(U32.is_lt(bootstrap, count), "VerifyError[BootstrapMethods]: invokedynamic bootstrap index out of bounds")
        +pair : CP.NameType <- CP.name_type(pool, nameType)
        +name : String = name_type_name(pair)
        descriptor : String = name_type_descriptor(pair)
        require(Bool.not(String.eq(name, "<init>")) && Bool.not(String.eq(name, "<clinit>")), "VerifyError[BootstrapMethods]: invokedynamic has a forbidden special name")
        parsed : M.Descriptor <- D.parse_method(descriptor)
        return Unit{}
    case _: Done{Unit{}}

# `remaining` walks the entries; NameAndType references resolve against the whole pool.
def validate_dynamic_bootstrap_entries(remaining: +List<M.Constant>, +pool: +List<M.Constant>, +count: U32, +major: U32) -> Result<&2, &2, String, Unit>:
  match remaining:
    case Nil{}: Done{Unit{}}
    case Con{entry, rest}:
      do Result<&2, &2, String, Unit>:
        validate_dynamic_bootstrap_entry(entry, count, major, pool)
        result : Unit <- validate_dynamic_bootstrap_entries(rest, pool, count, major)
        return result

def validate_dynamic_bootstrap_indices(+pool: +List<M.Constant>, +count: U32, +major: U32) -> Result<&2, &2, String, Unit>:
  validate_dynamic_bootstrap_entries(pool, pool, count, major)
def field_name(value: M.Field) -> String:
  match value:
    case M.Field{flags, name, descriptor, constant, attributes}: name

def field_descriptor(value: M.Field) -> String:
  match value:
    case M.Field{flags, name, descriptor, constant, attributes}: descriptor

def field_flags(value: M.Field) -> U32:
  match value:
    case M.Field{flags, name, descriptor, constant, attributes}: flags

def field_constant(value: M.Field) -> U32:
  match value:
    case M.Field{flags, name, descriptor, constant, attributes}: constant

def verifier_constant_tag(value: M.Constant) -> U32:
  match value:
    case M.Number{tag, bits}: tag
    case M.Index{tag, index}: tag
    case M.PairIndex{tag, first, second}: tag
    case _: 0

def field_constant_tag(descriptor: M.JvmType) -> U32:
  match descriptor:
    case M.Primitive{70}: 4
    case M.Primitive{74}: 5
    case M.Primitive{68}: 6
    case M.ObjectType{name}: Bool.pick(U32, String.eq(name, "java/lang/String"), 8, 0)
    case M.ArrayType{element}: 0
    case _: 3

def validate_field_constant_present(isAbsent: Bool, +field: M.Field, descriptor: M.JvmType, pool: +List<M.Constant>, +file: M.ClassFile) -> Result<&2, &2, String, Unit>:
  match isAbsent:
    case True{}: Done{Unit{}}
    case False{}:
      do Result<&2, &2, String, Unit>:
        require(U32.is_ne(U32.and(field_flags(field), 24), 0) && U32.is_eq(U32.and(field_flags(field), 24), 24), fail(class_name(file), field_name(field), field_descriptor(field), 0, "ConstantValue", "ConstantValue requires static final field"))
        value : M.Constant <- CP.get(pool, field_constant(field))
        +expectedTag : U32 = field_constant_tag(descriptor)
        require(U32.is_ne(expectedTag, 0) && U32.is_eq(verifier_constant_tag(value), expectedTag), fail(class_name(file), field_name(field), field_descriptor(field), 0, "ConstantValue", "constant kind does not match field descriptor"))
        return Unit{}

def validate_field_constant(+field: M.Field, descriptor: M.JvmType, pool: +List<M.Constant>, file: M.ClassFile) -> Result<&2, &2, String, Unit>:
  validate_field_constant_present(U32.is_eq(field_constant(field), 0), field, descriptor, pool, file)

def has_duplicate_field(+field: M.Field, rest: +List<M.Field>) -> Bool:
  match rest:
    case Nil{}: False{}
    case Con{+other, tail}:
      (String.eq(field_name(field), field_name(other)) && String.eq(field_descriptor(field), field_descriptor(other))) || has_duplicate_field(field, tail)

def validate_fields(fields: +List<M.Field>, +file: M.ClassFile) -> Result<&2, &2, String, Unit>:
  match fields:
    case Nil{}: Done{Unit{}}
    case Con{+field, +rest}:
      do Result<&2, &2, String, Unit>:
        require(Bool.not(has_duplicate_field(field, rest)), fail(class_name(file), field_name(field), field_descriptor(field), 0, "FieldTable", "duplicate field name and descriptor"))
        descriptor : M.JvmType <- D.parse_field(field_descriptor(field))
        validate_field_constant(field, descriptor, class_pool(file), file)
        tail : Unit <- validate_fields(rest, file)
        return tail


def has_duplicate_method(+method: M.Method, rest: +List<M.Method>) -> Bool:
  match rest:
    case Nil{}: False{}
    case Con{+other, tail}:
      (String.eq(method_name(method), method_name(other)) && String.eq(method_descriptor(method), method_descriptor(other))) || has_duplicate_method(method, tail)

def validate_unique_methods(methods: +List<M.Method>, +owner: String) -> Result<&2, &2, String, Unit>:
  match methods:
    case Nil{}: Done{Unit{}}
    case Con{+method, +rest}:
      do Result<&2, &2, String, Unit>:
        require(Bool.not(has_duplicate_method(method, rest)), fail(owner, method_name(method), method_descriptor(method), 0, "MethodTable", "duplicate method name and descriptor"))
        tail : Unit <- validate_unique_methods(rest, owner)
        return tail

def is_void_type(value: M.JvmType) -> Bool:
  match value:
    case M.Primitive{86}: True{}
    case _: False{}

def validate_method_shape(+method: M.Method, +owner: M.ClassFile) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    +descriptor : M.Descriptor <- D.parse_method(method_descriptor(method))
    +name : String = method_name(method)
    +flags : U32 = method_flags(method)
    +isStatic : Bool = U32.is_ne(U32.and(flags, 8), 0)
    +result : M.JvmType = D.result_type(descriptor)
    +isVoid : Bool = is_void_type(result)
    require(Bool.not(String.eq(name, "<init>")) || (Bool.not(isStatic) && isVoid), fail(class_name(owner), name, method_descriptor(method), 0, "Method", "constructor must be non-static and return void"))
    require(Bool.not(String.eq(name, "<clinit>")) || (isStatic && isVoid && U32.is_eq(D.parameter_count(descriptor), 0)), fail(class_name(owner), name, method_descriptor(method), 0, "Method", "class initializer must be static ()V"))
    require(U32.is_eq(U32.and(flags, 1024), 0) || U32.is_eq(U32.and(flags, 2362), 0), fail(class_name(owner), name, method_descriptor(method), 0, "MethodFlags", "abstract method has incompatible access flags"))
    +parameterSlots : U32 = ((Bool.pick(U32, isStatic, 0, 1) + D.parameter_slots(D.parameter_types(descriptor))) : U32)
    require(U32.is_le(parameterSlots, 255), fail(class_name(owner), name, method_descriptor(method), 0, "Descriptor", "method parameters exceed the JVM 255-slot limit"))
    return Unit{}
def required_branch_instruction(found: Maybe<&2, M.Instruction>, target: U32, file: M.ClassFile, +method: M.Method) -> Result<&2, &2, String, M.Instruction>:
  match found:
    case None{}: Fail{fail(class_name(file), method_name(method), method_descriptor(method), target, "StackMap", "branch target is not an instruction")}
    case Some{value}: Done{value}

def is_new_offset(instructions: +List<M.Instruction>, +offset: U32) -> Bool:
  match instructions:
    case Nil{}: False{}
    case Con{M.Instruction{op, a, b, c, at}, rest}:
      Bool.pick(Bool, U32.is_eq(at, offset), U32.is_eq(op, 187), is_new_offset(rest, offset))

def validate_verification(value: SM.Verification, instructions: +List<M.Instruction>, file: M.ClassFile, +method: M.Method, +frameOffset: U32) -> Result<&2, &2, String, Unit>:
  match value:
    case SM.UninitializedThis{}:
      require(String.eq(method_name(method), "<init>"), fail(class_name(file), method_name(method), method_descriptor(method), frameOffset, "StackMap", "uninitializedThis appears outside a constructor"))
    case SM.Uninitialized{+offset}:
      do Result<&2, &2, String, Unit>:
        require(is_new_offset(instructions, offset), fail(class_name(file), method_name(method), method_descriptor(method), frameOffset, "StackMap", "uninitialized value does not identify a new instruction"))
        return Unit{}
    case _: Done{Unit{}}

def validate_verifications(values: +List<SM.Verification>, +instructions: +List<M.Instruction>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  match values:
    case Nil{}: Done{Unit{}}
    case Con{value, rest}:
      do Result<&2, &2, String, Unit>:
        validate_verification(value, instructions, file, method, offset)
        tail : Unit <- validate_verifications(rest, instructions, file, method, offset)
        return tail

def validate_frame_values(frame: SM.Frame, +instructions: +List<M.Instruction>, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  match frame:
    case SM.Same{offset}: Done{Unit{}}
    case SM.Chop{offset, count}: Done{Unit{}}
    case SM.SameLocalsOne{offset, stack}: validate_verification(stack, instructions, file, method, offset)
    case SM.Append{offset, locals}: validate_verifications(locals, instructions, file, method, offset)
    case SM.Full{+offset, locals, stack}:
      do Result<&2, &2, String, Unit>:
        validate_verifications(locals, instructions, file, method, offset)
        validate_verifications(stack, instructions, file, method, offset)
        return Unit{}

def validate_frame_limits(frame: SM.Frame, +maxStack: U32, +maxLocals: U32, file: M.ClassFile, +method: M.Method, offset: U32) -> Result<&2, &2, String, Unit>:
  match frame:
    case SM.Same{offset}: Done{Unit{}}
    case SM.Chop{offset, count}: Done{Unit{}}
    case SM.SameLocalsOne{offset, stack}:
      require(U32.is_le(verification_width(stack), maxStack), fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "frame stack exceeds max_stack"))
    case SM.Append{offset, locals}:
      require(U32.is_le(verification_slots(locals), maxLocals), fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "appended locals exceed max_locals"))
    case SM.Full{offset, locals, stack}:
      require(U32.is_le(verification_slots(locals), maxLocals) && U32.is_le(verification_slots(stack), maxStack), fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "full frame exceeds max_locals or max_stack"))

def validate_frame_list(frames: +List<SM.Frame>, +instructions: +List<M.Instruction>, +file: M.ClassFile, +method: M.Method, +maxStack: U32, +maxLocals: U32) -> Result<&2, &2, String, Unit>:
  match frames:
    case Nil{}: Done{Unit{}}
    case Con{+frame, rest}:
      do Result<&2, &2, String, Unit>:
        +offset : U32 = frame_offset(frame)
        require(has_byte_offset(instructions, offset), fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "frame offset is not an instruction boundary"))
        validate_frame_values(frame, instructions, file, method, offset)
        validate_frame_limits(frame, maxStack, maxLocals, file, method, offset)
        tail : Unit <- validate_frame_list(rest, instructions, file, method, maxStack, maxLocals)
        return tail

def validate_stackmaps(found: Maybe<&2, SM.Frames>, +instructions: +List<M.Instruction>, +file: M.ClassFile, +method: M.Method, maxStack: U32, maxLocals: U32) -> Result<&2, &2, String, Unit>:
  match found:
    case None{}: Done{Unit{}}
    case Some{SM.Frames{codeLength, frames}}:
      validate_frame_list(frames, instructions, file, method, maxStack, maxLocals)
# Java 8 type checking (JVMS 4.10.1): StackMapTable frames are authoritative.
# One linear pass replaces the inferred state with the frame recorded at each
# offset, checks fallthrough, branch, and handler edges with isAssignable, and
# never computes least upper bounds.
type FrameAt is Data:
  FrameAt{offset: U32, state: State}

def locals_have_uninitialized_this(values: +List<VType>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{value, rest}: is_uninitialized_this(value) || locals_have_uninitialized_this(rest)

# A frame's flagThisUninit is derived from its locals, not from the previous frame.
def frame_flagged(state: State) -> State:
  match state:
    case State{+locals, stack, uninitializedThis}: State{locals, stack, locals_have_uninitialized_this(locals)}

def frame_states_go(frames: +List<SM.Frame>, previous: State, +instructions: +List<M.Instruction>, +pool: +List<M.Constant>, +maxLocals: U32, +file: M.ClassFile, +method: M.Method, +acc: +List<FrameAt>) -> Result<&2, &2, String, +List<FrameAt>>:
  match frames:
    case Nil{}: Done{M.reverse(FrameAt, acc)}
    case Con{+frame, rest}:
      do Result<&2, &2, String, +List<FrameAt>>:
        +next : State <- apply_frame(frame, previous, instructions, pool, maxLocals, file, method)
        +flagged : State = frame_flagged(next)
        tail : +List<FrameAt> <- frame_states_go(rest, flagged, instructions, pool, maxLocals, file, method, Con{FrameAt{frame_offset(frame), flagged}, acc})
        return tail

def frame_states(found: Maybe<&2, SM.Frames>, +initial: State, +instructions: +List<M.Instruction>, +pool: +List<M.Constant>, +maxLocals: U32, +file: M.ClassFile, +method: M.Method) -> Result<&2, &2, String, +List<FrameAt>>:
  match found:
    case None{}: Done{Nil{}}
    case Some{SM.Frames{codeLength, frames}}: frame_states_go(frames, initial, instructions, pool, maxLocals, file, method, Nil{})

def frame_at(frames: +List<FrameAt>, +offset: U32) -> Maybe<&2, State>:
  match frames:
    case Nil{}: None{}
    case Con{FrameAt{frameOffset, +state}, rest}:
      Bool.pick(Maybe<&2, State>, U32.is_eq(frameOffset, offset), Some{state}, frame_at(rest, offset))

def branch_opcode(+op: U32) -> Bool:
  (U32.is_ge(op, 153) && U32.is_le(op, 167)) || U32.is_eq(op, 198) || U32.is_eq(op, 199) || U32.is_eq(op, 200)

# Jump targets as instruction indices; fallthrough is handled by the pass itself.
def jump_targets(instruction: M.Instruction, +switches: +List<M.SwitchTable>) -> +List<U32>:
  match instruction:
    case M.Instruction{+op, a, b, c, offset}:
      match op:
        case 170: switch_successors(a, b, switches)
        case 171: switch_successors(a, b, switches)
        case _:
          Bool.pick(+List<U32>, branch_opcode(op), [a], Nil{})

def target_frame_found(found: Maybe<&2, State>, +offset: U32, +file: M.ClassFile, +method: M.Method) -> Result<&2, &2, String, State>:
  match found:
    case None{}: Fail{fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "branch target is missing a StackMap frame")}
    case Some{state}: Done{state}

def target_frame(+target: U32, +instructions: +List<M.Instruction>, +frames: +List<FrameAt>, +file: M.ClassFile, +method: M.Method) -> Result<&2, &2, String, State>:
  do Result<&2, &2, String, State>:
    instruction : M.Instruction <- required_branch_instruction(find_instruction(instructions, target, 0), target, file, method)
    +offset : U32 = instruction_offset(instruction)
    state : State <- target_frame_found(frame_at(frames, offset), offset, file, method)
    return state

def show_vtype(value: VType) -> String:
  match value:
    case VTop{}: "top"
    case VInt{}: "int"
    case VFloat{}: "float"
    case VLong{}: "long"
    case VDouble{}: "double"
    case VNull{}: "null"
    case VRef{name}: name
    case VUninitializedThis{name}: "uninitializedThis"
    case VUninitialized{offset, name}: "uninitialized(" ++ U32.show(offset) ++ ")"
    case VUnusable{}: "-"

def show_vtypes(values: +List<VType>) -> String:
  match values:
    case Nil{}: ""
    case Con{value, Nil{}}: show_vtype(value)
    case Con{value, rest}: show_vtype(value) ++ ", " ++ show_vtypes(rest)

# Mirrors HotSpot's "Current Frame / Stackmap Frame" detail; stacks print bottom-to-top.
def show_state(state: State) -> String:
  match state:
    case State{locals, stack, uninitializedThis}:
      "locals=[" ++ show_vtypes(locals) ++ "] stack=[" ++ show_vtypes(M.reverse(VType, stack)) ++ "]" ++ Bool.pick(String, uninitializedThis, " flags=[uninitializedThis]", "")

def frame_mismatch(+actual: State, +expected: State) -> String:
  ": current " ++ show_state(actual) ++ "; frame " ++ show_state(expected)

def frame_assignable(actual: State, expected: State, +hierarchy: Hierarchy) -> Bool:
  match actual expected:
    case State{locals, stack, +uninitializedThis} State{expectedLocals, expectedStack, +expectedUninitialized}:
      state_assignable(State{locals, stack, uninitializedThis}, State{expectedLocals, expectedStack, expectedUninitialized}, hierarchy) &&
        (Bool.not(uninitializedThis) || expectedUninitialized)

def check_jump_targets(targets: +List<U32>, +state: State, +instructions: +List<M.Instruction>, +frames: +List<FrameAt>, +hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  match targets:
    case Nil{}: Done{Unit{}}
    case Con{target, rest}:
      do Result<&2, &2, String, Unit>:
        +expected : State <- target_frame(target, instructions, frames, file, method)
        require(frame_assignable(state, expected, hierarchy), fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "branch state is not assignable to the target StackMap frame" ++ frame_mismatch(state, expected)))
        tail : Unit <- check_jump_targets(rest, state, instructions, frames, hierarchy, file, method, offset)
        return tail

def check_handler(+handler: M.Handler, +state: State, +pool: +List<M.Constant>, +instructions: +List<M.Instruction>, +frames: +List<FrameAt>, +hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    +entry : State <- handler_state(state_locals(state), handler, pool, state_uninitialized_this(state))
    +expected : State <- target_frame(handler_target(handler), instructions, frames, file, method)
    require(frame_assignable(entry, expected, hierarchy), fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "exception state is not assignable to the handler StackMap frame" ++ frame_mismatch(entry, expected)))
    return Unit{}

def check_handler_in_range(inRange: Bool, +handler: M.Handler, +state: State, +pool: +List<M.Constant>, +instructions: +List<M.Instruction>, +frames: +List<FrameAt>, +hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  match inRange:
    case True{}: check_handler(handler, state, pool, instructions, frames, hierarchy, file, method, offset)
    case False{}: Done{Unit{}}

def check_handlers(handlers: +List<M.Handler>, +pc: U32, +state: State, +pool: +List<M.Constant>, +instructions: +List<M.Instruction>, +frames: +List<FrameAt>, +hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, Unit>:
  match handlers:
    case Nil{}: Done{Unit{}}
    case Con{+handler, rest}:
      do Result<&2, &2, String, Unit>:
        check_handler_in_range(handler_in_range(handler, pc), handler, state, pool, instructions, frames, hierarchy, file, method, offset)
        tail : Unit <- check_handlers(rest, pc, state, pool, instructions, frames, hierarchy, file, method, offset)
        return tail

def incoming_state(frame: Maybe<&2, State>, current: Maybe<&2, State>, +hierarchy: Hierarchy, +file: M.ClassFile, +method: M.Method, +offset: U32) -> Result<&2, &2, String, State>:
  match frame current:
    case Some{+expected} Some{+actual}:
      do Result<&2, &2, String, State>:
        require(frame_assignable(actual, expected, hierarchy), fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "inferred state is not assignable to StackMap frame" ++ frame_mismatch(actual, expected)))
        return expected
    case Some{expected} None{}: Done{expected}
    case None{} Some{actual}: Done{actual}
    case None{} None{}: Fail{fail(class_name(file), method_name(method), method_descriptor(method), offset, "StackMap", "instruction after an unconditional control transfer has no StackMap frame")}

def method_code_length(method: M.Method) -> U32:
  M.length(U32, method_code(method))

def check_end(current: Maybe<&2, State>, +file: M.ClassFile, +method: M.Method) -> Result<&2, &2, String, Unit>:
  match current:
    case None{}: Done{Unit{}}
    case Some{state}: Fail{fail(class_name(file), method_name(method), method_descriptor(method), method_code_length(method), "CFG", "execution falls off the end of the code")}

def check_code(remaining: +List<M.Instruction>, +pc: U32, current: Maybe<&2, State>, +instructions: +List<M.Instruction>, +frames: +List<FrameAt>, +method: M.Method, +owner: M.ClassFile, +hierarchy: Hierarchy, +view: MethodView, +expected: U32) -> Result<&2, &2, String, Unit>:
  match remaining:
    case Nil{}: check_end(current, owner, method)
    case Con{+instruction, rest}:
      do Result<&2, &2, String, Unit>:
        +offset : U32 = instruction_offset(instruction)
        +state : State <- incoming_state(frame_at(frames, offset), current, hierarchy, owner, method, offset)
        +next : State <- transfer(instruction, state, owner, method, class_pool(owner), expected, view_max_locals(view), view_max_stack(view), hierarchy)
        check_jump_targets(jump_targets(instruction, method_switches(method)), next, instructions, frames, hierarchy, owner, method, offset)
        exceptionState : State <- constructor_exception_state(instruction, state, class_pool(owner), owner, method)
        check_handlers(method_handlers(method), pc, exceptionState, class_pool(owner), instructions, frames, hierarchy, owner, method, offset)
        following : Maybe<&2, State> = Bool.pick(Maybe<&2, State>, requires_fallthrough(instruction), Some{next}, None{})
        result : Unit <- check_code(rest, (pc + 1 : U32), following, instructions, frames, method, owner, hierarchy, view, expected)
        return result

def verify_method_code_list(instructions: +List<U32>, +method: M.Method, +owner: M.ClassFile, +hierarchy: Hierarchy) -> Result<&2, &2, String, Unit>:
  match instructions:
    case Nil{}:
      do Result<&2, &2, String, Unit>:
        +codeCount : U32 = code_attribute_count(method_attributes(method))
        require(U32.is_le(codeCount, 1), fail(class_name(owner), method_name(method), method_descriptor(method), 0, "Code", "duplicate Code attributes"))
        require(U32.is_eq(codeCount, 0), fail(class_name(owner), method_name(method), method_descriptor(method), 0, "Code", "abstract or native method has a Code attribute"))
        +isAbstract : Bool = U32.is_ne(U32.and(method_flags(method), 1024), 0)
        +isNative : Bool = U32.is_ne(U32.and(method_flags(method), 256), 0)
        require(isAbstract || isNative, fail(class_name(owner), method_name(method), method_descriptor(method), 0, "Code", "concrete method has no Code"))
        require(Bool.not(isAbstract && isNative), fail(class_name(owner), method_name(method), method_descriptor(method), 0, "MethodFlags", "method cannot be both abstract and native"))
        return Unit{}
    case Con{first, rest}:
      do Result<&2, &2, String, Unit>:
        isNoCode : Bool = U32.is_ne(U32.and(method_flags(method), 1024), 0) || U32.is_ne(U32.and(method_flags(method), 256), 0)
        require(Bool.not(isNoCode), fail(class_name(owner), method_name(method), method_descriptor(method), 0, "Code", "abstract or native method has a Code attribute"))
        require(U32.is_le(code_attribute_count(method_attributes(method)), 1), fail(class_name(owner), method_name(method), method_descriptor(method), 0, "Code", "duplicate Code attributes"))
        require(U32.is_eq(code_attribute_count(method_attributes(method)), 1), fail(class_name(owner), method_name(method), method_descriptor(method), 0, "Code", "concrete method must have exactly one Code attribute"))
        +view : MethodView <- method_view(method, class_pool(owner), class_major(owner))
        +expected : U32 <- expected_return(method)
        validate_instruction_rules(method_instructions(method), class_pool(owner), expected, view_max_locals(view), owner, method)
        validate_handlers(method_handlers(method), M.length(M.Instruction, method_instructions(method)), class_pool(owner), owner, method, hierarchy)
        validate_stackmaps(view_stackmap(view), method_instructions(method), owner, method, view_max_stack(view), view_max_locals(view))
        +start : State <- initial_state(owner, method, view_max_locals(view))
        frames : +List<FrameAt> <- frame_states(view_stackmap(view), start, method_instructions(method), class_pool(owner), view_max_locals(view), owner, method)
        result : Unit <- check_code(method_instructions(method), 0, Some{start}, method_instructions(method), frames, method, owner, hierarchy, view, expected)
        return result
def verify_method_code(+method: M.Method, owner: M.ClassFile, hierarchy: Hierarchy) -> Result<&2, &2, String, Unit>:
  verify_method_code_list(method_code(method), method, owner, hierarchy)

def verify_method_inner(+method: M.Method, +owner: M.ClassFile, hierarchy: Hierarchy) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    validate_method_shape(method, owner)
    result : Unit <- verify_method_code(method, owner, hierarchy)
    return result

def verify_method_result(found: Result<&2, &2, String, Unit>, +method: M.Method, +owner: M.ClassFile) -> Result<&2, &2, String, Unit>:
  match found:
    case Done{value}: Done{value}
    case Fail{error}: Fail{fail(class_name(owner), method_name(method), method_descriptor(method), 0, "Method", error)}

def verify_method(+method: M.Method, +owner: M.ClassFile, hierarchy: Hierarchy) -> Result<&2, &2, String, Unit>:
  verify_method_result(verify_method_inner(method, owner, hierarchy), method, owner)
def verify_methods(methods: +List<M.Method>, +file: M.ClassFile, +hierarchy: Hierarchy) -> Result<&2, &2, String, Unit>:
  match methods:
    case Nil{}: Done{Unit{}}
    case Con{method, rest}:
      do Result<&2, &2, String, Unit>:
        verify_method(method, file, hierarchy)
        tail : Unit <- verify_methods(rest, file, hierarchy)
        return tail
def verify_class(+file: M.ClassFile, hierarchy: Hierarchy) -> Result<&2, &2, String, Unit>:
  do Result<&2, &2, String, Unit>:
    bootstrapCount : U32 <- validate_bootstrap_metadata(file)
    validate_dynamic_bootstrap_indices(class_pool(file), bootstrapCount, class_major(file))
    validate_fields(class_fields(file), file)
    validate_unique_methods(class_methods(file), class_name(file))
    result : Unit <- verify_methods(class_methods(file), file, hierarchy)
    return result
