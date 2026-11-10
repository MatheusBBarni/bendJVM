import Base
import ../model.bend as M

# A binary trie from U32 keys to non-zero U32 values (0 reads as absent). Keys are
# consumed from the low bit, so the sequential numbers used as references stay
# balanced. Each leaf keeps its full key, so a lookup that leaves the path still
# compares exactly. Recursion is on fuel so the proofs in PROOF.bend can use it.

# Enough for 32 key bits plus the node a split adds.
def fuel() -> Nat:
  80n

def get_go(fuel: Nat, +t: M.Trie, +path: U32, +key: U32) -> U32:
  match fuel:
    case 0n: 0
    case 1n+ +p:
      match t:
        case M.TrieEmpty{}: 0
        case M.TrieLeaf{k, v}: Bool.pick(U32, U32.is_eq(k, key), v, 0)
        case M.TrieNode{+zero, +one}: get_go(p, Bool.pick(M.Trie, U32.is_eq(U32.and(path, 1), 0), zero, one), U32.shr(path), key)

def get(+t: M.Trie, +key: U32) -> U32:
  get_go(fuel(), t, key, key)

def set_go(fuel: Nat, +t: M.Trie, +depth: Nat, +path: U32, +key: U32, +value: U32) -> M.Trie:
  match fuel:
    case 0n: t
    case 1n+ +p:
      match t:
        case M.TrieEmpty{}: M.TrieLeaf{key, value}
        case M.TrieLeaf{+k, +v}:
          Bool.pick(M.Trie, U32.is_eq(k, key), M.TrieLeaf{key, value}, set_go(p, set_go(p, M.TrieNode{M.TrieEmpty{}, M.TrieEmpty{}}, depth, U32.shrn(k, depth), k, v), depth, path, key, value))
        case M.TrieNode{+zero, +one}:
          +low : Bool = U32.is_eq(U32.and(path, 1), 0)
          +updated : M.Trie = set_go(p, Bool.pick(M.Trie, low, zero, one), 1n+depth, U32.shr(path), key, value)
          M.TrieNode{Bool.pick(M.Trie, low, updated, zero), Bool.pick(M.Trie, low, one, updated)}

def set(+t: M.Trie, +key: U32, +value: U32) -> M.Trie:
  set_go(fuel(), t, 0n, key, key, value)

# Every value stored in the trie, pushed onto `acc`.
def values(t: M.Trie, +acc: +List<U32>) -> +List<U32>:
  match t:
    case M.TrieEmpty{}: acc
    case M.TrieLeaf{k, v}: Con{v, acc}
    case M.TrieNode{zero, one}: values(zero, values(one, acc))
