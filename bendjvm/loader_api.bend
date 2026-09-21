import Base
import ./model.bend as M
import ./loader/class_loader.bend as L

def loaded_result(value: Result<&2, &2, String, M.VM>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print(error)
    case Done{loaded}: IO.print("ready")

def main() -> IO(Unit):
  loaded_result(L.load_many(Nil{}, 1))
