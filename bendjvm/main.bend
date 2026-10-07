import Base

# Both entrypoints use the same ordered classpath and host-effect protocol.
def launch_arguments(args: List<String>) -> String:
  match args:
    case Nil{}: ""
    case Con{head, rest}: head ++ "\n" ++ launch_arguments(rest)

def jvm_launch_runner(arguments: String) -> IO(U32):
  import "./args.c"
  import "./args.js"

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +status : U32 <- jvm_launch_runner(launch_arguments(args))
    Bool.pick(IO(Unit), U32.is_eq(status, 0), IO.pure(Unit, Unit{}), IO.die(Unit, status, "BendJVM launch failed"))
