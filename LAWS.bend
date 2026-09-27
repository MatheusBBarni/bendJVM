# The milestone-3 metadata, mirror, and resource paths are VM/host state
# transitions. Keep this gate limited to pure invariants until those APIs expose
# stable pure functions suitable for a law.
import Base

law nat_add_zero:
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}
