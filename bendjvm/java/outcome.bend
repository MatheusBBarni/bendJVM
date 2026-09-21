import Base
import ../model.bend as M

type Outcome is Data:
  Returned{vm: M.VM, value: Maybe<&2, M.Slot>}
  ThrownRef{vm: M.VM, reference: U32}
  ThrownName{vm: M.VM, name: String}
  Suspend{vm: M.VM, effect: M.Effect}
  Call{vm: M.VM, method: M.LoadedMethod, args: +List<M.Slot>}
