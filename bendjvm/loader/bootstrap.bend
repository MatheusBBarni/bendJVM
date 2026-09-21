import Base
import ../model.bend as M

# Only these native signatures cross into the explicitly registered intrinsics.
def native(name: String, descriptor: String) -> M.Method:
  M.Method{257, name, descriptor, 0, 0, Nil{}, Nil{}, Nil{}, Nil{}}
def native_static(name: String, descriptor: String) -> M.Method:
  M.Method{265, name, descriptor, 0, 0, Nil{}, Nil{}, Nil{}, Nil{}}

def cls(name: String, parent: String, methods: +List<M.Method>) -> M.ClassFile:
  M.ClassFile{0, 52, 1, name, parent, Nil{}, [M.Unused{}], Nil{}, methods, Nil{}}

def exception(name: String, parent: String) -> M.ClassFile:
  cls(name, parent, [native("<init>", "()V"), native("<init>", "(Ljava/lang/String;)V")])

def classes() -> +List<M.ClassFile>:
  [cls("java/lang/Object", "", [native("<init>", "()V")]),
   cls("java/lang/String", "java/lang/Object", Nil{}),
   cls("java/lang/ClassLoader", "java/lang/Object", [native_static("getSystemResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;")]),
   cls("java/io/InputStream", "java/lang/Object", [native("read", "()I"), native("close", "()V")]),
   M.ClassFile{0, 52, 1, "java/lang/System", "java/lang/Object", Nil{}, [M.Unused{}], [M.Field{9, "out", "Ljava/io/PrintStream;", 0, Nil{}}], Nil{}, Nil{}},
   cls("java/io/PrintStream", "java/lang/Object", [native("println", "(I)V"), native("println", "(Ljava/lang/String;)V"), native("println", "()V"), native("println", "(F)V"), native("println", "(Z)V")]),
   exception("java/lang/Throwable", "java/lang/Object"),
   exception("java/lang/Exception", "java/lang/Throwable"),
   exception("java/lang/RuntimeException", "java/lang/Exception"),
   exception("java/lang/ArithmeticException", "java/lang/RuntimeException"),
   exception("java/lang/NullPointerException", "java/lang/RuntimeException"),
   exception("java/lang/ArrayIndexOutOfBoundsException", "java/lang/RuntimeException"),
   exception("java/lang/ClassCastException", "java/lang/RuntimeException"),
   exception("java/lang/NegativeArraySizeException", "java/lang/RuntimeException"),
   exception("java/lang/OutOfMemoryError", "java/lang/Error"),
   exception("java/lang/Error", "java/lang/Throwable"),
   exception("java/lang/ArrayStoreException", "java/lang/RuntimeException"),
   exception("java/lang/ExceptionInInitializerError", "java/lang/Error"),
   exception("java/lang/NoClassDefFoundError", "java/lang/Error"),
   cls("java/lang/Cloneable", "java/lang/Object", Nil{}),
   cls("java/io/Serializable", "java/lang/Object", Nil{}),
   M.ClassFile{0, 52, 17, "[Ljava/lang/String;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}}]

def array_name(+name: String) -> String:
  Bool.pick(String, String.starts_with(name, "["), "[" ++ name, "[L" ++ name ++ ";")

def array_class(name: String) -> M.ClassFile:
  M.ClassFile{0, 52, 17, name, "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}}

def primitive_arrays() -> +List<M.ClassFile>:
  [array_class("[Z"), array_class("[C"), array_class("[F"), array_class("[B"), array_class("[S"), array_class("[I")]

def atype_name(atype: U32) -> String:
  match atype:
    case 4: "[Z"
    case 5: "[C"
    case 6: "[F"
    case 8: "[B"
    case 9: "[S"
    case 10: "[I"
    case _: "<unsupported-array>"

def intrinsic_desc(+owner: String, +name: String, +desc: String) -> U32:
  p = Bool.pick(U32, String.eq(desc, "(I)V"), 2, Bool.pick(U32, String.eq(desc, "(Ljava/lang/String;)V"), 3, Bool.pick(U32, String.eq(desc, "()V"), 4, Bool.pick(U32, String.eq(desc, "(F)V"), 5, Bool.pick(U32, String.eq(desc, "(Z)V"), 6, 0)))))
  ctor = Bool.pick(U32, String.eq(owner, "java/lang/Object"), 1, Bool.pick(U32, String.eq(desc, "()V"), 7, 8))
  printed = Bool.pick(U32, String.eq(owner, "java/io/PrintStream") && String.eq(name, "println"), p, 0)
  closed = Bool.pick(U32, String.eq(owner, "java/io/InputStream") && String.eq(name, "close") && String.eq(desc, "()V"), 11, printed)
  read_or_closed = Bool.pick(U32, String.eq(owner, "java/io/InputStream") && String.eq(name, "read") && String.eq(desc, "()I"), 10, closed)
  resource_or_read = Bool.pick(U32, String.eq(owner, "java/lang/ClassLoader") && String.eq(name, "getSystemResourceAsStream") && String.eq(desc, "(Ljava/lang/String;)Ljava/io/InputStream;"), 9, read_or_closed)
  Bool.pick(U32, String.eq(name, "<init>"), ctor, resource_or_read)
