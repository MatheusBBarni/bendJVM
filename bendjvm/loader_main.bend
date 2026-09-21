import Base
import ./model.bend as M
import ./loader/class_loader.bend as L
import ./loader/codec.bend as C

def jvm_class_files() -> IO(String):
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

def print_parsed(value: Result<&2, &2, String, +List<M.ClassFile>>) -> IO(Unit):
  match value:
    case Fail{error}: IO.die(Unit, 1, error)
    case Done{+classes}: IO.print(C.encode_classes(classes))

def main() -> IO(Unit):
  do IO<Unit>:
    class_files : String <- jvm_class_files()
    paths : +List<String> = String.lines(class_files)
    bytes : +List<+List<U32>> <- read_files(paths)
    print_parsed(L.parse_classes(bytes, Nil{}))
