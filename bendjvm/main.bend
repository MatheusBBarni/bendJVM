import Base
import ./model.bend as M
import ./runtime/state.bend as S
import ./runtime/execute.bend as X
import ./loader/class_loader.bend as L

def jvm_class_path() -> IO(String):
  import "./args.c"
  import "./args.js"

def jvm_class_files() -> IO(String):
  import "./args.c"
  import "./args.js"
def jvm_fuel() -> IO(U32):
  import "./args.c"
  import "./args.js"

def jvm_max_heap() -> IO(U32):
  import "./args.c"
  import "./args.js"
def jvm_mode() -> IO(U32):
  import "./args.c"
  import "./args.js"


def read_file_pair(pair: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(+List<U32>):
  match pair:
    case (file, result):
      do IO<+List<U32>>:
        File.close(file)
        bytes : +List<U32> <- IO.pass(+List<U32>, result)
        return bytes

def read_file(path: String) -> IO(+List<U32>):
  do IO<+List<U32>>:
    file : File <- IO.try(File, File.open(path, "rb"))
    pair : File & Result<&1, &1, U32 & String, +List<U32>> <- File.read_bytes(file, 65536)
    bytes : +List<U32> <- read_file_pair(pair)
    return bytes

def read_files(paths: +List<String>) -> IO(+List<+List<U32>>):
  match paths:
    case Nil{}:
      IO.pure(+List<+List<U32>>, Nil{})
    case Con{path, rest}:
      do IO<+List<+List<U32>>>:
        bytes : +List<U32> <- read_file(path)
        tail : +List<+List<U32>> <- read_files(rest)
        return Con{bytes, tail}

def symbol_found(found: Maybe<&2, String>) -> String:
  match found:
    case None{}: ""
    case Some{text}: text

def symbol_at(+symbols: +List<String>, id: U32) -> String:
  symbol_found(M.nth(String, symbols, id))

def entry_match(+method: M.LoadedMethod, +symbols: +List<String>) -> Bool:
  Bool.and(String.eq(symbol_at(symbols, M.loaded_method_name(method)), "main"), String.eq(symbol_at(symbols, M.loaded_method_descriptor(method)), "([Ljava/lang/String;)V"))

def entry_method(methods: +List<M.LoadedMethod>, +symbols: +List<String>) -> Maybe<&2, M.LoadedMethod>:
  match methods:
    case Nil{}: None{}
    case Con{+method, rest}:
      Bool.pick(Maybe<&2, M.LoadedMethod>, entry_match(method, symbols), Some{method}, entry_method(rest, symbols))

def method_locals(value: M.LoadedMethod) -> +List<M.Slot>:
  match value:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      M.replace(M.Slot, M.zeros(U32.to_nat(maxLocals)), 0n, M.Slot{1, 0})

def start_initializer_found(vm: M.VM, mainFrame: M.Frame, owner: U32, found: Maybe<&2, M.LoadedMethod>) -> M.VM:
  match found:
    case None{}: S.with_frames(vm, [mainFrame])
    case Some{+method}:
      +id = M.loaded_method_id(method)
      S.with_frames(vm, [M.Frame{id, 0, 0, method_locals(method), Nil{}, owner}, mainFrame])

def start_initializer_method(+vm: M.VM, mainFrame: M.Frame, owner: U32, initializer: U32) -> M.VM:
  start_initializer_found(vm, mainFrame, owner, M.nth(M.LoadedMethod, S.methods(vm), initializer))

def start_class_found(+vm: M.VM, mainFrame: M.Frame, found: Maybe<&2, M.LoadedClass>) -> M.VM:
  match found:
    case None{}: S.with_frames(vm, [mainFrame])
    case Some{class}:
      M.LoadedClass{id, name, parent, interfaces, fields, methods, initializer, state} = class
      match initializer:
        case 4294967295: S.with_frames(vm, [mainFrame])
        case value: start_initializer_method(vm, mainFrame, id, value)

def start_class(+vm: M.VM, mainFrame: M.Frame, owner: U32) -> M.VM:
  start_class_found(vm, mainFrame, M.nth(M.LoadedClass, S.classes(vm), owner))


def start_found(+vm: M.VM, found: Maybe<&2, M.LoadedMethod>) -> M.VM:
  match found:
    case None{}: S.fail(vm, "NoSuchMethodError: main")
    case Some{+method}:
      +id = M.loaded_method_id(method)
      +owner = M.loaded_method_owner(method)
      start_class(vm, M.Frame{id, 0, 0, method_locals(method), Nil{}, 4294967295}, owner)

def print_lines(lines: +List<String>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{line, rest}:
      do IO<Unit>:
        IO.print(line)
        print_lines(rest)

def finish_status(+vm: M.VM, status: U32) -> IO(Unit):
  match status:
    case 4: IO.die(Unit, 1, S.error(vm))
    case 3: IO.die(Unit, 1, "OutOfFuel")
    case _: IO.pure(Unit, Unit{})

def finish(+vm: M.VM) -> IO(Unit):
  do IO<Unit>:
    print_lines(M.reverse(String, S.output(vm)))
    finish_status(vm, S.status(vm))
def mnemonic(op: U32) -> String:
  match op:
    case 0: "nop"
    case 1: "aconst_null"
    case 2: "iconst_m1"
    case 3: "iconst_0"
    case 4: "iconst_1"
    case 5: "iconst_2"
    case 6: "iconst_3"
    case 7: "iconst_4"
    case 8: "iconst_5"
    case 11: "fconst_0"
    case 12: "fconst_1"
    case 13: "fconst_2"
    case 16: "bipush"
    case 17: "sipush"
    case 18: "ldc"
    case 19: "ldc_w"
    case 21: "iload"
    case 23: "fload"
    case 26: "iload_0"
    case 27: "iload_1"
    case 28: "iload_2"
    case 29: "iload_3"
    case 32: "fload_0"
    case 33: "fload_1"
    case 34: "fload_2"
    case 35: "fload_3"
    case 46: "iaload"
    case 48: "faload"
    case 50: "aaload"
    case 54: "istore"
    case 56: "fstore"
    case 59: "istore_0"
    case 60: "istore_1"
    case 61: "istore_2"
    case 62: "istore_3"
    case 67: "fstore_0"
    case 68: "fstore_1"
    case 69: "fstore_2"
    case 70: "fstore_3"
    case 79: "iastore"
    case 81: "fastore"
    case 83: "aastore"
    case 87: "pop"
    case 89: "dup"
    case 96: "iadd"
    case 98: "fadd"
    case 100: "isub"
    case 102: "fsub"
    case 104: "imul"
    case 106: "fmul"
    case 108: "idiv"
    case 110: "fdiv"
    case 112: "irem"
    case 114: "frem"
    case 116: "ineg"
    case 118: "fneg"
    case 120: "ishl"
    case 122: "ishr"
    case 124: "iushr"
    case 126: "iand"
    case 128: "ior"
    case 130: "ixor"
    case 132: "iinc"
    case 134: "i2f"
    case 139: "f2i"
    case 149: "fcmpl"
    case 150: "fcmpg"
    case 153: "ifeq"
    case 154: "ifne"
    case 155: "iflt"
    case 156: "ifge"
    case 157: "ifgt"
    case 158: "ifle"
    case 159: "if_icmpeq"
    case 160: "if_icmpne"
    case 161: "if_icmplt"
    case 162: "if_icmpge"
    case 163: "if_icmpgt"
    case 164: "if_icmple"
    case 167: "goto"
    case 172: "ireturn"
    case 174: "dreturn"
    case 175: "freturn"
    case 176: "areturn"
    case 177: "return"
    case 178: "getstatic"
    case 179: "putstatic"
    case 180: "getfield"
    case 181: "putfield"
    case 182: "invokevirtual"
    case 183: "invokespecial"
    case 184: "invokestatic"
    case 187: "new"
    case 188: "newarray"
    case 189: "anewarray"
    case 190: "arraylength"
    case 191: "athrow"
    case 192: "checkcast"
    case 193: "instanceof"
    case 196: "wide"
    case _: "opcode_" ++ U32.show(op)

def dump_instruction(instruction: M.Instruction) -> IO(Unit):
  match instruction:
    case M.Instruction{op, a, b, c, offset}: IO.print(U32.show(offset) ++ " " ++ mnemonic(op) ++ " " ++ U32.show(a) ++ " " ++ U32.show(b) ++ " " ++ U32.show(c) ++ "\n")

def dump_instructions(instructions: +List<M.Instruction>) -> IO(Unit):
  match instructions:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{instruction, rest}:
      do IO<Unit>:
        dump_instruction(instruction)
        dump_instructions(rest)

def dump_method(method: M.LoadedMethod, +symbols: +List<String>) -> IO(Unit):
  match method:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      do IO<Unit>:
        IO.print("method " ++ symbol_at(symbols, name) ++ symbol_at(symbols, descriptor) ++ "\n")
        dump_instructions(instructions)

def dump_methods(methods: +List<M.LoadedMethod>, +symbols: +List<String>) -> IO(Unit):
  match methods:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{+method, rest}:
      do IO<Unit>:
        dump_method(method, symbols)
        dump_methods(rest, symbols)

def dump_classes(classes: +List<M.LoadedClass>, +symbols: +List<String>) -> IO(Unit):
  match classes:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{value, rest}:
      do IO<Unit>:
        IO.print("class " ++ symbol_at(symbols, M.loaded_class_name(value)) ++ " version 52 constant pool fields methods attributes\n")
        dump_classes(rest, symbols)

def trace_instruction(+class_name: String, +method_name: String, instruction: M.Instruction) -> IO(Unit):
  match instruction:
    case M.Instruction{op, a, b, c, offset}:
      IO.print_err("[" ++ class_name ++ "." ++ method_name ++ " pc=" ++ U32.show(offset) ++ "] " ++ mnemonic(op) ++ "\nstack: []\n")

def trace_instructions(+class_name: String, +method_name: String, instructions: +List<M.Instruction>) -> IO(Unit):
  match instructions:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{instruction, rest}:
      do IO<Unit>:
        trace_instruction(class_name, method_name, instruction)
        trace_instructions(class_name, method_name, rest)

def trace_class_name(found: Maybe<&2, M.LoadedClass>, +symbols: +List<String>) -> String:
  match found:
    case None{}: ""
    case Some{class}: symbol_at(symbols, M.loaded_class_name(class))

def trace_method(method: M.LoadedMethod, +classes: +List<M.LoadedClass>, +symbols: +List<String>) -> IO(Unit):
  match method:
    case M.LoadedMethod{id, owner, name, descriptor, flags, parameters, resultTag, maxStack, maxLocals, instructions, handlers, intrinsic}:
      trace_instructions(trace_class_name(M.nth(M.LoadedClass, classes, owner), symbols), symbol_at(symbols, name), instructions)
def trace_methods(methods: +List<M.LoadedMethod>, +classes: +List<M.LoadedClass>, +symbols: +List<String>) -> IO(Unit):
  match methods:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{+method, rest}:
      do IO<Unit>:
        trace_method(method, classes, symbols)
        trace_methods(rest, classes, symbols)

def trace_loaded(+loaded: M.VM) -> IO(Unit):
  trace_methods(S.methods(loaded), S.classes(loaded), S.symbols(loaded))

def dump_loaded(+loaded: M.VM, mode: U32) -> IO(Unit):
  match mode:
    case 0: IO.pure(Unit, Unit{})
    case 1: dump_classes(S.classes(loaded), S.symbols(loaded))
    case 2:
      do IO<Unit>:
        dump_classes(S.classes(loaded), S.symbols(loaded))
        dump_methods(S.methods(loaded), S.symbols(loaded))
    case _:
      trace_loaded(loaded)


def execute_loaded(+loaded: M.VM, fuel: U32) -> M.VM:
  X.run(loaded, U32.to_nat(fuel))

def run_mode(+loaded: M.VM, fuel: U32, mode: U32) -> IO(Unit):
  match mode:
    case 1: IO.pure(Unit, Unit{})
    case _: finish(execute_loaded(loaded, fuel))
def run_done(+loaded: M.VM, +fuel: U32, +mode: U32) -> IO(Unit):
  do IO<Unit>:
    dump_loaded(loaded, mode)
    run_mode(loaded, fuel, mode)

def run_loaded(value: Result<&2, &2, String, M.VM>, fuel: U32, mode: U32) -> IO(Unit):
  match value:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{+loaded}: run_done(loaded, fuel, mode)
def main() -> IO(Unit):
  do IO<Unit>:
    class_files : String <- jvm_class_files()
    maxHeap : U32 <- jvm_max_heap()
    fuel : U32 <- jvm_fuel()
    paths : +List<String> = String.lines(class_files)
    bytes : +List<+List<U32>> <- read_files(paths)
    mode : U32 <- jvm_mode()
    run_loaded(L.load_many(bytes, maxHeap), fuel, mode)
