import Base
import ../model.bend as M

type Cursor is Data:
  Cursor{values: +List<U32>}

def token(value: U32) -> String:
  U32.show(value)

def encode_string_chars(chars: +List<Char>) -> +List<String>:
  match chars:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{token(Char.to_u32(head)), encode_string_chars(tail)}

def encode_string(+value: String) -> +List<String>:
  Con{Nat.show(String.length(value)), encode_string_chars(String.to_list(value))}

def encode_u32s(values: +List<U32>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{token(head), encode_u32s(tail)}

def encode_u32_list(+values: +List<U32>) -> +List<String>:
  Con{token(M.length(U32, values)), encode_u32s(values)}

def encode_attribute(value: M.Attribute) -> +List<String>:
  match value:
    case M.Attribute{name, bytes}:
      M.append(String, encode_string(name), encode_u32_list(bytes))

def encode_attributes(values: +List<M.Attribute>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{encode_attribute(head), encode_attributes(tail)}

def encode_attribute_list(+values: +List<M.Attribute>) -> +List<String>:
  M.append(String, [token(M.length(M.Attribute, values))], encode_attributes(values))

def encode_constant(value: M.Constant) -> +List<String>:
  match value:
    case M.Unused{}: [token(0)]
    case M.Utf{text}: M.append(String, [token(1)], encode_string(text))
    case M.Number{tag, bits}: M.append(String, [token(2), token(tag), token(bits)])
    case M.Index{tag, index}: M.append(String, [token(3), token(tag), token(index)])
    case M.PairIndex{tag, first, second}: [token(4), token(tag), token(first), token(second)]

def encode_constants(values: +List<M.Constant>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{encode_constant(head), encode_constants(tail)}

def encode_constant_list(+values: +List<M.Constant>) -> +List<String>:
  M.append(String, [token(M.length(M.Constant, values))], encode_constants(values))

def encode_field(value: M.Field) -> +List<String>:
  match value:
    case M.Field{flags, name, descriptor, constant, attributes}:
      [token(flags), encode_string(name), encode_string(descriptor), token(constant), encode_attribute_list(attributes)]

def encode_fields(values: +List<M.Field>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{encode_field(head), encode_fields(tail)}

def encode_field_list(+values: +List<M.Field>) -> +List<String>:
  M.append(String, [token(M.length(M.Field, values))], encode_fields(values))

def encode_instruction(value: M.Instruction) -> +List<String>:
  match value:
    case M.Instruction{op, a, b, c, offset}: [token(op), token(a), token(b), token(c), token(offset)]

def encode_instructions(values: +List<M.Instruction>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{encode_instruction(head), encode_instructions(tail)}

def encode_instruction_list(+values: +List<M.Instruction>) -> +List<String>:
  M.append(String, [token(M.length(M.Instruction, values))], encode_instructions(values))

def encode_handler(value: M.Handler) -> +List<String>:
  match value:
    case M.Handler{start, end, target, catch}: [token(start), token(end), token(target), token(catch)]

def encode_handlers(values: +List<M.Handler>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{encode_handler(head), encode_handlers(tail)}

def encode_handler_list(+values: +List<M.Handler>) -> +List<String>:
  M.append(String, [token(M.length(M.Handler, values))], encode_handlers(values))

def encode_method(value: M.Method) -> +List<String>:
  match value:
    case M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes}:
      [token(flags), encode_string(name), encode_string(descriptor), token(maxStack), token(maxLocals), encode_u32_list(code), encode_instruction_list(instructions), encode_handler_list(handlers), encode_attribute_list(attributes)]

def encode_methods(values: +List<M.Method>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{encode_method(head), encode_methods(tail)}

def encode_method_list(+values: +List<M.Method>) -> +List<String>:
  M.append(String, [token(M.length(M.Method, values))], encode_methods(values))

def encode_strings(values: +List<String>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{encode_string(head), encode_strings(tail)}

def encode_string_list(+values: +List<String>) -> +List<String>:
  M.append(String, [token(M.length(String, values))], encode_strings(values))

def encode_class(value: M.ClassFile) -> +List<String>:
  match value:
    case M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}:
      [token(minor), token(major), token(flags), encode_string(name), encode_string(parent), encode_string_list(interfaces), encode_constant_list(pool), encode_field_list(fields), encode_method_list(methods), encode_attribute_list(attributes)]

def encode_classes_go(values: +List<M.ClassFile>) -> +List<String>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}:
      Con{encode_class(head), encode_classes_go(tail)}

def encode_classes(+values: +List<M.ClassFile>) -> String:
  String.join(M.append(String, [U32.show(M.length(M.ClassFile, values))], encode_classes_go(values)), ',')

def next_value(+cursor: Cursor) -> U32 & Cursor:
  Cursor{values} = cursor
  match values:
    case Nil{}: (0, Cursor{Nil{}})
    case Con{head, tail}: (head, Cursor{tail})

def decode_string_chars_from(n: Nat, +acc: String, pair: U32 & Cursor) -> String & Cursor:
  (code, rest) = pair
  decode_string_chars(n, rest, SCon{Char.from_u32(code), acc})

def decode_string_chars(n: Nat, +cursor: Cursor, +acc: String) -> String & Cursor:
  match n:
    case 0n: (String.reverse(acc), cursor)
    case 1n+p:
      decode_string_chars_from(p, acc, next_value(cursor))

def decode_string_from(pair: U32 & Cursor) -> String & Cursor:
  (length, rest) = pair
  decode_string_chars(U32.to_nat(length), rest, SNil{})

def decode_string(+cursor: Cursor) -> String & Cursor:
  decode_string_from(next_value(cursor))

def decode_u32s_from(n: Nat, +acc: +List<U32>, pair: U32 & Cursor) -> +List<U32> & Cursor:
  (value, rest) = pair
  decode_u32s(n, rest, Con{value, acc})

def decode_u32s(n: Nat, +cursor: Cursor, +acc: +List<U32>) -> +List<U32> & Cursor:
  match n:
    case 0n: (M.reverse(U32, acc), cursor)
    case 1n+p:
      decode_u32s_from(p, acc, next_value(cursor))

def decode_u32_list_from(pair: U32 & Cursor) -> +List<U32> & Cursor:
  (length, rest) = pair
  decode_u32s(U32.to_nat(length), rest, Nil{})

def decode_u32_list(+cursor: Cursor) -> +List<U32> & Cursor:
  decode_u32_list_from(next_value(cursor))

def decode_attributes_from(n: Nat, +acc: +List<M.Attribute>, pair: M.Attribute & Cursor) -> +List<M.Attribute> & Cursor:
  (value, rest) = pair
  decode_attributes(n, rest, Con{value, acc})

def decode_attributes(n: Nat, +cursor: Cursor, +acc: +List<M.Attribute>) -> +List<M.Attribute> & Cursor:
  match n:
    case 0n: (M.reverse(M.Attribute, acc), cursor)
    case 1n+p:
      decode_attributes_from(p, acc, decode_attribute(cursor))

def decode_attribute_bytes(name: String, pair: +List<U32> & Cursor) -> M.Attribute & Cursor:
  (bytes, end) = pair
  (M.Attribute{name, bytes}, end)

def decode_attribute_name(pair: String & Cursor) -> M.Attribute & Cursor:
  (name, rest) = pair
  decode_attribute_bytes(name, decode_u32_list(rest))

def decode_attribute(+cursor: Cursor) -> M.Attribute & Cursor:
  decode_attribute_name(decode_string(cursor))

def decode_attribute_list_from(pair: U32 & Cursor) -> +List<M.Attribute> & Cursor:
  (length, rest) = pair
  decode_attributes(U32.to_nat(length), rest, Nil{})

def decode_attribute_list(+cursor: Cursor) -> +List<M.Attribute> & Cursor:
  decode_attribute_list_from(next_value(cursor))

def decode_constants_from(n: Nat, +acc: +List<M.Constant>, pair: M.Constant & Cursor) -> +List<M.Constant> & Cursor:
  (value, rest) = pair
  decode_constants(n, rest, Con{value, acc})

def decode_constants(n: Nat, +cursor: Cursor, +acc: +List<M.Constant>) -> +List<M.Constant> & Cursor:
  match n:
    case 0n: (M.reverse(M.Constant, acc), cursor)
    case 1n+p:
      decode_constants_from(p, acc, decode_constant(cursor))


def decode_constant_utf(+cursor: Cursor) -> M.Constant & Cursor:
  decode_constant_utf_value(decode_string(cursor))

def decode_constant_utf_value(pair: String & Cursor) -> M.Constant & Cursor:
  (text, end) = pair
  (M.Utf{text}, end)

def decode_constant_number(+cursor: Cursor) -> M.Constant & Cursor:
  decode_constant_number_kind(next_value(cursor))

def decode_constant_number_kind(pair: U32 & Cursor) -> M.Constant & Cursor:
  (kind, rest) = pair
  decode_constant_number_bits(kind, next_value(rest))

def decode_constant_number_bits(kind: U32, pair: U32 & Cursor) -> M.Constant & Cursor:
  (bits, end) = pair
  (M.Number{kind, bits}, end)

def decode_constant_index(+cursor: Cursor) -> M.Constant & Cursor:
  decode_constant_index_kind(next_value(cursor))

def decode_constant_index_kind(pair: U32 & Cursor) -> M.Constant & Cursor:
  (kind, rest) = pair
  decode_constant_index_value(kind, next_value(rest))

def decode_constant_index_value(kind: U32, pair: U32 & Cursor) -> M.Constant & Cursor:
  (index, end) = pair
  (M.Index{kind, index}, end)

def decode_constant_pair(+cursor: Cursor) -> M.Constant & Cursor:
  decode_constant_pair_kind(next_value(cursor))

def decode_constant_pair_kind(pair: U32 & Cursor) -> M.Constant & Cursor:
  (kind, rest) = pair
  decode_constant_pair_first(kind, next_value(rest))

def decode_constant_pair_first(kind: U32, pair: U32 & Cursor) -> M.Constant & Cursor:
  (first, rest) = pair
  decode_constant_pair_second(kind, first, next_value(rest))

def decode_constant_pair_second(kind: U32, first: U32, pair: U32 & Cursor) -> M.Constant & Cursor:
  (second, end) = pair
  (M.PairIndex{kind, first, second}, end)

def decode_constant(+cursor: Cursor) -> M.Constant & Cursor:
  decode_constant_tag(next_value(cursor))

def decode_constant_tag(pair: U32 & Cursor) -> M.Constant & Cursor:
  (tag, rest) = pair
  decode_constant_tag_value(tag, rest)

def decode_constant_tag_value(tag: U32, +rest: Cursor) -> M.Constant & Cursor:
  match tag:
    case 0: (M.Unused{}, rest)
    case 1: decode_constant_utf(rest)
    case 2: decode_constant_number(rest)
    case 3: decode_constant_index(rest)
    case _: decode_constant_pair(rest)

def decode_constant_list_from(pair: U32 & Cursor) -> +List<M.Constant> & Cursor:
  (length, rest) = pair
  decode_constants(U32.to_nat(length), rest, Nil{})

def decode_constant_list(+cursor: Cursor) -> +List<M.Constant> & Cursor:
  decode_constant_list_from(next_value(cursor))

def decode_fields_from(n: Nat, +acc: +List<M.Field>, pair: M.Field & Cursor) -> +List<M.Field> & Cursor:
  (value, rest) = pair
  decode_fields(n, rest, Con{value, acc})

def decode_fields(n: Nat, +cursor: Cursor, +acc: +List<M.Field>) -> +List<M.Field> & Cursor:
  match n:
    case 0n: (M.reverse(M.Field, acc), cursor)
    case 1n+p:
      decode_fields_from(p, acc, decode_field(cursor))

def decode_field_flags(pair: U32 & Cursor) -> M.Field & Cursor:
  (flags, rest) = pair
  decode_field_name(flags, decode_string(rest))

def decode_field_name(flags: U32, pair: String & Cursor) -> M.Field & Cursor:
  (name, rest) = pair
  decode_field_descriptor(flags, name, decode_string(rest))

def decode_field_descriptor(flags: U32, name: String, pair: String & Cursor) -> M.Field & Cursor:
  (descriptor, rest) = pair
  decode_field_constant(flags, name, descriptor, next_value(rest))

def decode_field_constant(flags: U32, name: String, descriptor: String, pair: U32 & Cursor) -> M.Field & Cursor:
  (constant, rest) = pair
  decode_field_attributes(flags, name, descriptor, constant, decode_attribute_list(rest))

def decode_field_attributes(flags: U32, name: String, descriptor: String, constant: U32, pair: +List<M.Attribute> & Cursor) -> M.Field & Cursor:
  (attributes, end) = pair
  (M.Field{flags, name, descriptor, constant, attributes}, end)

def decode_field(+cursor: Cursor) -> M.Field & Cursor:
  decode_field_flags(next_value(cursor))

def decode_field_list_from(pair: U32 & Cursor) -> +List<M.Field> & Cursor:
  (length, rest) = pair
  decode_fields(U32.to_nat(length), rest, Nil{})

def decode_field_list(+cursor: Cursor) -> +List<M.Field> & Cursor:
  decode_field_list_from(next_value(cursor))

def decode_instructions_from(n: Nat, +acc: +List<M.Instruction>, pair: M.Instruction & Cursor) -> +List<M.Instruction> & Cursor:
  (value, rest) = pair
  decode_instructions(n, rest, Con{value, acc})

def decode_instructions(n: Nat, +cursor: Cursor, +acc: +List<M.Instruction>) -> +List<M.Instruction> & Cursor:
  match n:
    case 0n: (M.reverse(M.Instruction, acc), cursor)
    case 1n+p:
      decode_instructions_from(p, acc, decode_instruction(cursor))

def decode_instruction_offset(op: U32, a: U32, b: U32, c: U32, pair: U32 & Cursor) -> M.Instruction & Cursor:
  (offset, end) = pair
  (M.Instruction{op, a, b, c, offset}, end)

def decode_instruction_c(op: U32, a: U32, b: U32, pair: U32 & Cursor) -> M.Instruction & Cursor:
  (c, rest) = pair
  decode_instruction_offset(op, a, b, c, next_value(rest))

def decode_instruction_b(op: U32, a: U32, pair: U32 & Cursor) -> M.Instruction & Cursor:
  (b, rest) = pair
  decode_instruction_c(op, a, b, next_value(rest))

def decode_instruction_a(op: U32, pair: U32 & Cursor) -> M.Instruction & Cursor:
  (a, rest) = pair
  decode_instruction_b(op, a, next_value(rest))

def decode_instruction_op(pair: U32 & Cursor) -> M.Instruction & Cursor:
  (op, rest) = pair
  decode_instruction_a(op, next_value(rest))

def decode_instruction(+cursor: Cursor) -> M.Instruction & Cursor:
  decode_instruction_op(next_value(cursor))

def decode_instruction_list_from(pair: U32 & Cursor) -> +List<M.Instruction> & Cursor:
  (length, rest) = pair
  decode_instructions(U32.to_nat(length), rest, Nil{})

def decode_instruction_list(+cursor: Cursor) -> +List<M.Instruction> & Cursor:
  decode_instruction_list_from(next_value(cursor))

def decode_handlers_from(n: Nat, +acc: +List<M.Handler>, pair: M.Handler & Cursor) -> +List<M.Handler> & Cursor:
  (value, rest) = pair
  decode_handlers(n, rest, Con{value, acc})

def decode_handlers(n: Nat, +cursor: Cursor, +acc: +List<M.Handler>) -> +List<M.Handler> & Cursor:
  match n:
    case 0n: (M.reverse(M.Handler, acc), cursor)
    case 1n+p:
      decode_handlers_from(p, acc, decode_handler(cursor))

def decode_handler_catch(start: U32, end: U32, target: U32, pair: U32 & Cursor) -> M.Handler & Cursor:
  (catch, end_cursor) = pair
  (M.Handler{start, end, target, catch}, end_cursor)

def decode_handler_target(start: U32, end: U32, pair: U32 & Cursor) -> M.Handler & Cursor:
  (target, rest) = pair
  decode_handler_catch(start, end, target, next_value(rest))

def decode_handler_end(start: U32, pair: U32 & Cursor) -> M.Handler & Cursor:
  (end, rest) = pair
  decode_handler_target(start, end, next_value(rest))

def decode_handler_start(pair: U32 & Cursor) -> M.Handler & Cursor:
  (start, rest) = pair
  decode_handler_end(start, next_value(rest))

def decode_handler(+cursor: Cursor) -> M.Handler & Cursor:
  decode_handler_start(next_value(cursor))

def decode_handler_list_from(pair: U32 & Cursor) -> +List<M.Handler> & Cursor:
  (length, rest) = pair
  decode_handlers(U32.to_nat(length), rest, Nil{})

def decode_handler_list(+cursor: Cursor) -> +List<M.Handler> & Cursor:
  decode_handler_list_from(next_value(cursor))

def decode_methods_from(n: Nat, +acc: +List<M.Method>, pair: M.Method & Cursor) -> +List<M.Method> & Cursor:
  (value, rest) = pair
  decode_methods(n, rest, Con{value, acc})

def decode_methods(n: Nat, +cursor: Cursor, +acc: +List<M.Method>) -> +List<M.Method> & Cursor:
  match n:
    case 0n: (M.reverse(M.Method, acc), cursor)
    case 1n+p:
      decode_methods_from(p, acc, decode_method(cursor))

def decode_method_attributes(flags: U32, name: String, descriptor: String, maxStack: U32, maxLocals: U32, code: +List<U32>, instructions: +List<M.Instruction>, handlers: +List<M.Handler>, pair: +List<M.Attribute> & Cursor) -> M.Method & Cursor:
  (attributes, end) = pair
  (M.Method{flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, attributes}, end)

def decode_method_handlers(flags: U32, name: String, descriptor: String, maxStack: U32, maxLocals: U32, code: +List<U32>, instructions: +List<M.Instruction>, pair: +List<M.Handler> & Cursor) -> M.Method & Cursor:
  (handlers, rest) = pair
  decode_method_attributes(flags, name, descriptor, maxStack, maxLocals, code, instructions, handlers, decode_attribute_list(rest))

def decode_method_instructions(flags: U32, name: String, descriptor: String, maxStack: U32, maxLocals: U32, code: +List<U32>, pair: +List<M.Instruction> & Cursor) -> M.Method & Cursor:
  (instructions, rest) = pair
  decode_method_handlers(flags, name, descriptor, maxStack, maxLocals, code, instructions, decode_handler_list(rest))

def decode_method_code(flags: U32, name: String, descriptor: String, maxStack: U32, maxLocals: U32, pair: +List<U32> & Cursor) -> M.Method & Cursor:
  (code, rest) = pair
  decode_method_instructions(flags, name, descriptor, maxStack, maxLocals, code, decode_instruction_list(rest))

def decode_method_locals(flags: U32, name: String, descriptor: String, maxStack: U32, pair: U32 & Cursor) -> M.Method & Cursor:
  (maxLocals, rest) = pair
  decode_method_code(flags, name, descriptor, maxStack, maxLocals, decode_u32_list(rest))

def decode_method_stack(flags: U32, name: String, descriptor: String, pair: U32 & Cursor) -> M.Method & Cursor:
  (maxStack, rest) = pair
  decode_method_locals(flags, name, descriptor, maxStack, next_value(rest))

def decode_method_descriptor(flags: U32, name: String, pair: String & Cursor) -> M.Method & Cursor:
  (descriptor, rest) = pair
  decode_method_stack(flags, name, descriptor, next_value(rest))

def decode_method_name(flags: U32, pair: String & Cursor) -> M.Method & Cursor:
  (name, rest) = pair
  decode_method_descriptor(flags, name, decode_string(rest))

def decode_method_flags(pair: U32 & Cursor) -> M.Method & Cursor:
  (flags, rest) = pair
  decode_method_name(flags, decode_string(rest))

def decode_method(+cursor: Cursor) -> M.Method & Cursor:
  decode_method_flags(next_value(cursor))

def decode_method_list_from(pair: U32 & Cursor) -> +List<M.Method> & Cursor:
  (length, rest) = pair
  decode_methods(U32.to_nat(length), rest, Nil{})

def decode_method_list(+cursor: Cursor) -> +List<M.Method> & Cursor:
  decode_method_list_from(next_value(cursor))

def decode_strings_from(n: Nat, +acc: +List<String>, pair: String & Cursor) -> +List<String> & Cursor:
  (value, rest) = pair
  decode_strings(n, rest, Con{value, acc})

def decode_strings(n: Nat, +cursor: Cursor, +acc: +List<String>) -> +List<String> & Cursor:
  match n:
    case 0n: (M.reverse(String, acc), cursor)
    case 1n+p:
      decode_strings_from(p, acc, decode_string(cursor))

def decode_string_list_from(pair: U32 & Cursor) -> +List<String> & Cursor:
  (length, rest) = pair
  decode_strings(U32.to_nat(length), rest, Nil{})

def decode_string_list(+cursor: Cursor) -> +List<String> & Cursor:
  decode_string_list_from(next_value(cursor))

def decode_class_attributes(minor: U32, major: U32, flags: U32, name: String, parent: String, interfaces: +List<String>, pool: +List<M.Constant>, fields: +List<M.Field>, methods: +List<M.Method>, pair: +List<M.Attribute> & Cursor) -> M.ClassFile & Cursor:
  (attributes, end) = pair
  (M.ClassFile{minor, major, flags, name, parent, interfaces, pool, fields, methods, attributes}, end)

def decode_class_methods(minor: U32, major: U32, flags: U32, name: String, parent: String, interfaces: +List<String>, pool: +List<M.Constant>, fields: +List<M.Field>, pair: +List<M.Method> & Cursor) -> M.ClassFile & Cursor:
  (methods, rest) = pair
  decode_class_attributes(minor, major, flags, name, parent, interfaces, pool, fields, methods, decode_attribute_list(rest))

def decode_class_fields(minor: U32, major: U32, flags: U32, name: String, parent: String, interfaces: +List<String>, pool: +List<M.Constant>, pair: +List<M.Field> & Cursor) -> M.ClassFile & Cursor:
  (fields, rest) = pair
  decode_class_methods(minor, major, flags, name, parent, interfaces, pool, fields, decode_method_list(rest))

def decode_class_pool(minor: U32, major: U32, flags: U32, name: String, parent: String, interfaces: +List<String>, pair: +List<M.Constant> & Cursor) -> M.ClassFile & Cursor:
  (pool, rest) = pair
  decode_class_fields(minor, major, flags, name, parent, interfaces, pool, decode_field_list(rest))

def decode_class_interfaces(minor: U32, major: U32, flags: U32, name: String, parent: String, pair: +List<String> & Cursor) -> M.ClassFile & Cursor:
  (interfaces, rest) = pair
  decode_class_pool(minor, major, flags, name, parent, interfaces, decode_constant_list(rest))

def decode_class_parent(minor: U32, major: U32, flags: U32, name: String, pair: String & Cursor) -> M.ClassFile & Cursor:
  (parent, rest) = pair
  decode_class_interfaces(minor, major, flags, name, parent, decode_string_list(rest))

def decode_class_name(minor: U32, major: U32, flags: U32, pair: String & Cursor) -> M.ClassFile & Cursor:
  (name, rest) = pair
  decode_class_parent(minor, major, flags, name, decode_string(rest))

def decode_class_flags(minor: U32, major: U32, pair: U32 & Cursor) -> M.ClassFile & Cursor:
  (flags, rest) = pair
  decode_class_name(minor, major, flags, decode_string(rest))

def decode_class_major(minor: U32, pair: U32 & Cursor) -> M.ClassFile & Cursor:
  (major, rest) = pair
  decode_class_flags(minor, major, next_value(rest))

def decode_class_minor(pair: U32 & Cursor) -> M.ClassFile & Cursor:
  (minor, rest) = pair
  decode_class_major(minor, next_value(rest))

def decode_class(+cursor: Cursor) -> M.ClassFile & Cursor:
  decode_class_minor(next_value(cursor))

def decode_classes_from(n: Nat, +acc: +List<M.ClassFile>, pair: M.ClassFile & Cursor) -> +List<M.ClassFile>:
  (value, rest) = pair
  decode_classes(n, rest, Con{value, acc})

def decode_classes(n: Nat, +cursor: Cursor, +acc: +List<M.ClassFile>) -> +List<M.ClassFile>:
  match n:
    case 0n: M.reverse(M.ClassFile, acc)
    case 1n+p:
      decode_classes_from(p, acc, decode_class(cursor))

def token_value(value: Maybe<&2, U32>, +tail: +List<String>) -> +List<U32>:
  match value:
    case None{}: Con{0, tokens(tail)}
    case Some{value}: Con{value, tokens(tail)}

def tokens(values: +List<String>) -> +List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}: token_value(U32.read(head), tail)

def decode_classes_text_from(pair: U32 & Cursor) -> +List<M.ClassFile>:
  (length, rest) = pair
  decode_classes(U32.to_nat(length), rest, Nil{})

def decode_classes_text_tokens(values: +List<U32>) -> +List<M.ClassFile>:
  decode_classes_text_from(next_value(Cursor{values}))

def decode_classes_text(text: String) -> +List<M.ClassFile>:
  decode_classes_text_tokens(tokens(String.split(text, ',')))
