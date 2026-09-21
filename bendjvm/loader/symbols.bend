import Base
import ../model.bend as M

type Interned is Data:
  Interned{symbols: +List<String>, id: U32}

def find_go(xs: +List<String>, +name: String, +index0: U32) -> U32:
  match xs:
    case Nil{}:
      4294967295
    case Con{h, t}:
      Bool.pick(U32, String.eq(h, name), index0, find_go(t, name, (index0 + 1 : U32)))

def find(xs: +List<String>, name: String) -> U32:
  find_go(xs, name, 0)

def insert(found: U32, +xs: +List<String>, name: String) -> Interned:
  match found:
    case 4294967295:
      Interned{M.append(String, xs, [name]), M.length(String, xs)}
    case id:
      Interned{xs, id}

def intern(+xs: +List<String>, +name: String) -> Interned:
  insert(find(xs, name), xs, name)
def interned_symbols(value: Interned) -> +List<String>:
  Interned{symbols, id} = value
  symbols

def text_at(value: Maybe<&2, String>) -> String:
  match value:
    case None{}:
      "<invalid-symbol>"
    case Some{text}:
      text

def text(xs: +List<String>, id: U32) -> String:
  text_at(M.nth(String, xs, id))
