import Base
import ../model.bend as M
import ../classfile/parser.bend as P
import ./catalog.bend as C
import ./bootstrap.bend as B
import ./symbols.bend as S

def bootstrap_heap(+names: +List<String>) -> +List<M.HeapEntry>:
  [M.HeapEntry{S.find(names, "java/io/PrintStream"), 0, 0, Nil{}, Nil{}, Nil{}}]

def vm_from(catalog: C.Catalog, classes: +List<M.LoadedClass>, maxHeap: U32) -> M.VM:
  match catalog:
    case C.Catalog{sources, names, symbols, +fields, methods}:
      M.VM{classes, methods, fields, symbols, bootstrap_heap(names), C.static_fields(fields, Nil{}), Nil{}, 0, 0, M.Slot{0, 0}, Nil{}, "", maxHeap, 0n}

def parse_classes(values: +List<+List<U32>>, +acc: +List<M.ClassFile>) -> Result<&2, &2, String, +List<M.ClassFile>>:
  match values:
    case Nil{}:
      Done{M.reverse(M.ClassFile, acc)}
    case Con{+bytes, rest}:
      do Result<&2, &2, String, +List<M.ClassFile>>:
        class : M.ClassFile <- P.parse(bytes)
        tail : +List<M.ClassFile> <- parse_classes(rest, Con{class, acc})
        return tail

def load_many(values: +List<+List<U32>>, maxHeap: U32) -> Result<&2, &2, String, M.VM>:
  do Result<&2, &2, String, M.VM>:
    parsed : +List<M.ClassFile> <- parse_classes(values, Nil{})
    all : +List<M.ClassFile> = M.append(M.ClassFile, parsed, B.classes())
    +catalog : C.Catalog <- C.build(all)
    classes : +List<M.LoadedClass> <- C.loaded_classes(catalog)
    return vm_from(catalog, classes, maxHeap)

def failed_vm(error: String, maxHeap: U32) -> M.VM:
  M.VM{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, 4, 0, M.Slot{0, 0}, Nil{}, error, maxHeap, 0n}

def load_many_vm_result(value: Result<&2, &2, String, M.VM>, maxHeap: U32) -> M.VM:
  match value:
    case Fail{error}: failed_vm(error, maxHeap)
    case Done{+loaded}: loaded

def load_many_vm(values: +List<+List<U32>>, +maxHeap: U32) -> M.VM:
  load_many_vm_result(load_many(values, maxHeap), maxHeap)

def load_bytes(+bytes: +List<U32>, maxHeap: U32) -> Result<&2, &2, String, M.VM>:
  load_many(Con{bytes, Nil{}}, maxHeap)
