import Base
import ./model.bend as M
import ./loader/class_loader.bend as L

def inspect_class_info(+bytes: +List<U32>) -> Result<&2, &2, String, L.Inspected>:
  L.inspect_class_info(bytes)

def loaded_result(value: Result<&2, &2, String, M.VM>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print(error)
    case Done{loaded}: IO.print("ready")

def inspect_result(value: Result<&2, &2, String, L.Inspected>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print(error)
    case Done{info}: IO.print("inspected")

def inspect_or_load(value: Result<&2, &2, String, L.Inspected>) -> IO(Unit):
  match value:
    case Fail{error}:
      loaded_result(L.load_many_with_resources(Nil{}, Nil{}, 1))
    case Done{info}:
      inspect_result(Done{info})

def main() -> IO(Unit):
  inspect_or_load(inspect_class_info(Nil{}))
