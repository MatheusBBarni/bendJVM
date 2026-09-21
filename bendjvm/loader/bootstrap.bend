import Base
import ../model.bend as M

# Only these native signatures cross into the explicitly registered intrinsics.
def native(name: String, descriptor: String) -> M.Method:
  M.Method{257, name, descriptor, 8, 8, Nil{}, Nil{}, Nil{}, Nil{}}
def native_static(name: String, descriptor: String) -> M.Method:
  M.Method{265, name, descriptor, 8, 8, Nil{}, Nil{}, Nil{}, Nil{}}
def abs_m(name: String, descriptor: String) -> M.Method:
  M.Method{1025, name, descriptor, 8, 8, Nil{}, Nil{}, Nil{}, Nil{}}

def cls(name: String, parent: String, methods: +List<M.Method>) -> M.ClassFile:
  M.ClassFile{0, 52, 1, name, parent, Nil{}, [M.Unused{}], Nil{}, methods, Nil{}}

def cls_if(name: String, parent: String, interfaces: +List<String>, methods: +List<M.Method>) -> M.ClassFile:
  M.ClassFile{0, 52, 1, name, parent, interfaces, [M.Unused{}], Nil{}, methods, Nil{}}

def iface(name: String, interfaces: +List<String>, methods: +List<M.Method>) -> M.ClassFile:
  M.ClassFile{0, 52, 1537, name, "java/lang/Object", interfaces, [M.Unused{}], Nil{}, methods, Nil{}}

def exception(name: String, parent: String) -> M.ClassFile:
  cls(name, parent, [native("<init>", "()V"), native("<init>", "(Ljava/lang/String;)V")])

def exception4(name: String, parent: String) -> M.ClassFile:
  cls(name, parent, [native("<init>", "()V"), native("<init>", "(Ljava/lang/String;)V"), native("<init>", "(Ljava/lang/Throwable;)V"), native("<init>", "(Ljava/lang/String;Ljava/lang/Throwable;)V")])

def throwable_methods() -> +List<M.Method>:
  [native("<init>", "()V"), native("<init>", "(Ljava/lang/String;)V"), native("<init>", "(Ljava/lang/Throwable;)V"), native("<init>", "(Ljava/lang/String;Ljava/lang/Throwable;)V"), native("getMessage", "()Ljava/lang/String;"), native("getCause", "()Ljava/lang/Throwable;"), native("initCause", "(Ljava/lang/Throwable;)Ljava/lang/Throwable;"), native("addSuppressed", "(Ljava/lang/Throwable;)V"), native("getSuppressed", "()[Ljava/lang/Throwable;"), native("toString", "()Ljava/lang/String;")]

def throwables() -> +List<M.ClassFile>:
  [cls("java/lang/Throwable", "java/lang/Object", throwable_methods()),
   exception4("java/lang/Exception", "java/lang/Throwable"),
   exception4("java/lang/RuntimeException", "java/lang/Exception"),
   exception4("java/lang/Error", "java/lang/Throwable"),
   exception("java/lang/ArithmeticException", "java/lang/RuntimeException"),
   exception("java/lang/NullPointerException", "java/lang/RuntimeException"),
   exception("java/lang/ArrayIndexOutOfBoundsException", "java/lang/IndexOutOfBoundsException"),
   exception("java/lang/IndexOutOfBoundsException", "java/lang/RuntimeException"),
   exception("java/lang/StringIndexOutOfBoundsException", "java/lang/IndexOutOfBoundsException"),
   exception("java/lang/ClassCastException", "java/lang/RuntimeException"),
   exception("java/lang/NegativeArraySizeException", "java/lang/RuntimeException"),
   exception("java/lang/ArrayStoreException", "java/lang/RuntimeException"),
   exception("java/lang/IllegalArgumentException", "java/lang/RuntimeException"),
   exception("java/lang/IllegalStateException", "java/lang/RuntimeException"),
   exception("java/lang/NumberFormatException", "java/lang/IllegalArgumentException"),
   exception("java/lang/NoSuchElementException", "java/lang/RuntimeException"),
   exception("java/lang/ConcurrentModificationException", "java/lang/RuntimeException"),
   exception("java/lang/UnsupportedOperationException", "java/lang/RuntimeException"),
   exception("java/lang/OutOfMemoryError", "java/lang/Error"),
   exception("java/lang/NoClassDefFoundError", "java/lang/LinkageError"),
   exception("java/lang/LinkageError", "java/lang/Error"),
   exception("java/lang/IncompatibleClassChangeError", "java/lang/LinkageError"),
   exception("java/lang/AbstractMethodError", "java/lang/IncompatibleClassChangeError"),
   exception("java/lang/NoSuchMethodError", "java/lang/IncompatibleClassChangeError"),
   exception("java/lang/NoSuchFieldError", "java/lang/IncompatibleClassChangeError"),
   cls("java/lang/ExceptionInInitializerError", "java/lang/Error", [native("<init>", "()V"), native("<init>", "(Ljava/lang/String;)V"), native("<init>", "(Ljava/lang/Throwable;)V")]),
   exception4("java/io/IOException", "java/lang/Exception"),
   exception("java/io/FileNotFoundException", "java/io/IOException"),
   exception("java/io/EOFException", "java/io/IOException"),
   exception("java/io/UnsupportedEncodingException", "java/io/IOException"),
   exception("java/io/InterruptedIOException", "java/io/IOException"),
   exception("java/net/SocketException", "java/io/IOException"),
   exception("java/net/ConnectException", "java/net/SocketException"),
   exception("java/net/UnknownHostException", "java/io/IOException"),
   exception("java/net/SocketTimeoutException", "java/io/InterruptedIOException")]

def object_methods() -> +List<M.Method>:
  [native("<init>", "()V"), native("equals", "(Ljava/lang/Object;)Z"), native("hashCode", "()I"), native("toString", "()Ljava/lang/String;")]

def string_methods() -> +List<M.Method>:
  [native("length", "()I"), native("isEmpty", "()Z"), native("charAt", "(I)C"), native("equals", "(Ljava/lang/Object;)Z"), native("hashCode", "()I"), native("substring", "(I)Ljava/lang/String;"), native("substring", "(II)Ljava/lang/String;"), native("concat", "(Ljava/lang/String;)Ljava/lang/String;"), native("toString", "()Ljava/lang/String;"), native_static("valueOf", "(I)Ljava/lang/String;"), native_static("valueOf", "(Z)Ljava/lang/String;"), native_static("valueOf", "(Ljava/lang/Object;)Ljava/lang/String;")]

def builder_methods() -> +List<M.Method>:
  [native("<init>", "()V"), native("<init>", "(Ljava/lang/String;)V"), native("append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"), native("append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;"), native("append", "(I)Ljava/lang/StringBuilder;"), native("append", "(C)Ljava/lang/StringBuilder;"), native("append", "(Z)Ljava/lang/StringBuilder;"), native("length", "()I"), native("toString", "()Ljava/lang/String;")]

def integer_methods() -> +List<M.Method>:
  [native_static("valueOf", "(I)Ljava/lang/Integer;"), native("intValue", "()I"), native_static("parseInt", "(Ljava/lang/String;)I"), native("equals", "(Ljava/lang/Object;)Z"), native("hashCode", "()I"), native("toString", "()Ljava/lang/String;")]

def list_methods() -> +List<M.Method>:
  [native("<init>", "()V"), native("<init>", "(I)V"), native("size", "()I"), native("isEmpty", "()Z"), native("add", "(Ljava/lang/Object;)Z"), native("add", "(ILjava/lang/Object;)V"), native("get", "(I)Ljava/lang/Object;"), native("set", "(ILjava/lang/Object;)Ljava/lang/Object;"), native("remove", "(I)Ljava/lang/Object;"), native("contains", "(Ljava/lang/Object;)Z"), native("clear", "()V"), native("iterator", "()Ljava/util/Iterator;")]

def map_methods() -> +List<M.Method>:
  [native("<init>", "()V"), native("size", "()I"), native("isEmpty", "()Z"), native("put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"), native("get", "(Ljava/lang/Object;)Ljava/lang/Object;"), native("containsKey", "(Ljava/lang/Object;)Z"), native("remove", "(Ljava/lang/Object;)Ljava/lang/Object;"), native("clear", "()V")]

def stream_in() -> +List<M.Method>:
  [native("read", "()I"), native("read", "([B)I"), native("read", "([BII)I"), native("close", "()V")]

def stream_out() -> +List<M.Method>:
  [native("write", "(I)V"), native("write", "([B)V"), native("write", "([BII)V"), native("flush", "()V"), native("close", "()V")]

def classes() -> +List<M.ClassFile>:
  M.append(M.ClassFile,
    [cls("java/lang/Object", "", object_methods()),
     cls("java/lang/String", "java/lang/Object", string_methods()),
     cls("java/lang/StringBuilder", "java/lang/Object", builder_methods()),
     cls("java/lang/Integer", "java/lang/Object", integer_methods()),
     cls("java/lang/Math", "java/lang/Object", [native_static("abs", "(I)I"), native_static("min", "(II)I"), native_static("max", "(II)I")]),
     cls("java/util/Objects", "java/lang/Object", [native_static("requireNonNull", "(Ljava/lang/Object;)Ljava/lang/Object;"), native_static("equals", "(Ljava/lang/Object;Ljava/lang/Object;)Z")]),
     cls("java/lang/ClassLoader", "java/lang/Object", [native_static("getSystemResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;")]),
     M.ClassFile{0, 52, 1, "java/lang/System", "java/lang/Object", Nil{}, [M.Unused{}], [M.Field{9, "out", "Ljava/io/PrintStream;", 0, Nil{}}], [native_static("arraycopy", "(Ljava/lang/Object;ILjava/lang/Object;II)V")], Nil{}},
     cls("java/io/PrintStream", "java/lang/Object", [native("println", "(I)V"), native("println", "(Ljava/lang/String;)V"), native("println", "()V"), native("println", "(F)V"), native("println", "(Z)V")]),
     iface("java/lang/AutoCloseable", Nil{}, [abs_m("close", "()V")]),
     iface("java/io/Closeable", ["java/lang/AutoCloseable"], [abs_m("close", "()V")]),
     iface("java/io/Flushable", Nil{}, [abs_m("flush", "()V")]),
     iface("java/lang/Iterable", Nil{}, [abs_m("iterator", "()Ljava/util/Iterator;")]),
     iface("java/util/Iterator", Nil{}, [abs_m("hasNext", "()Z"), abs_m("next", "()Ljava/lang/Object;"), abs_m("remove", "()V")]),
     iface("java/util/Collection", ["java/lang/Iterable"], [abs_m("size", "()I"), abs_m("isEmpty", "()Z"), abs_m("add", "(Ljava/lang/Object;)Z"), abs_m("contains", "(Ljava/lang/Object;)Z"), abs_m("clear", "()V"), abs_m("iterator", "()Ljava/util/Iterator;")]),
     iface("java/util/List", ["java/util/Collection"], [abs_m("size", "()I"), abs_m("isEmpty", "()Z"), abs_m("add", "(Ljava/lang/Object;)Z"), abs_m("contains", "(Ljava/lang/Object;)Z"), abs_m("clear", "()V"), abs_m("iterator", "()Ljava/util/Iterator;"), abs_m("get", "(I)Ljava/lang/Object;"), abs_m("set", "(ILjava/lang/Object;)Ljava/lang/Object;"), abs_m("add", "(ILjava/lang/Object;)V"), abs_m("remove", "(I)Ljava/lang/Object;")]),
     iface("java/util/Map", Nil{}, [abs_m("size", "()I"), abs_m("isEmpty", "()Z"), abs_m("put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"), abs_m("get", "(Ljava/lang/Object;)Ljava/lang/Object;"), abs_m("containsKey", "(Ljava/lang/Object;)Z"), abs_m("remove", "(Ljava/lang/Object;)Ljava/lang/Object;"), abs_m("clear", "()V")]),
     cls_if("java/util/ArrayList", "java/lang/Object", ["java/util/List", "java/util/Collection", "java/lang/Iterable"], list_methods()),
     cls("java/util/ArrayList$Itr", "java/lang/Object", [native("hasNext", "()Z"), native("next", "()Ljava/lang/Object;"), native("remove", "()V")]),
     cls_if("java/util/HashMap", "java/lang/Object", ["java/util/Map"], map_methods()),
     cls_if("java/io/InputStream", "java/lang/Object", ["java/io/Closeable"], stream_in()),
     cls_if("java/io/OutputStream", "java/lang/Object", ["java/io/Closeable", "java/io/Flushable"], stream_out()),
     cls("java/io/ByteArrayInputStream", "java/io/InputStream", [native("<init>", "([B)V")]),
     cls("java/io/ByteArrayOutputStream", "java/io/OutputStream", [native("<init>", "()V"), native("toByteArray", "()[B"), native("size", "()I"), native("reset", "()V")]),
     cls("java/io/File", "java/lang/Object", [native("<init>", "(Ljava/lang/String;)V"), native("exists", "()Z"), native("isFile", "()Z"), native("isDirectory", "()Z"), native("getPath", "()Ljava/lang/String;")]),
     cls("java/io/FileInputStream", "java/io/InputStream", [native("<init>", "(Ljava/lang/String;)V")]),
     cls("java/io/FileOutputStream", "java/io/OutputStream", [native("<init>", "(Ljava/lang/String;)V"), native("<init>", "(Ljava/lang/String;Z)V")]),
     cls_if("java/io/Reader", "java/lang/Object", ["java/io/Closeable"], [native("read", "()I"), native("read", "([CII)I"), native("close", "()V")]),
     cls_if("java/io/Writer", "java/lang/Object", ["java/io/Closeable", "java/io/Flushable"], [native("write", "(I)V"), native("write", "(Ljava/lang/String;)V"), native("write", "([CII)V"), native("flush", "()V"), native("close", "()V")]),
     cls("java/io/InputStreamReader", "java/io/Reader", [native("<init>", "(Ljava/io/InputStream;Ljava/lang/String;)V")]),
     cls("java/io/OutputStreamWriter", "java/io/Writer", [native("<init>", "(Ljava/io/OutputStream;Ljava/lang/String;)V")]),
     cls("java/io/BufferedReader", "java/io/Reader", [native("<init>", "(Ljava/io/Reader;)V"), native("readLine", "()Ljava/lang/String;")]),
     cls("java/net/SocketAddress", "java/lang/Object", [native("<init>", "()V")]),
     cls("java/net/InetSocketAddress", "java/net/SocketAddress", [native("<init>", "(Ljava/lang/String;I)V")]),
     cls("java/net/Socket", "java/lang/Object", [native("<init>", "()V"), native("<init>", "(Ljava/lang/String;I)V"), native("connect", "(Ljava/net/SocketAddress;I)V"), native("getInputStream", "()Ljava/io/InputStream;"), native("getOutputStream", "()Ljava/io/OutputStream;"), native("setSoTimeout", "(I)V"), native("close", "()V")]),
     cls("java/net/ServerSocket", "java/lang/Object", [native("<init>", "(I)V"), native("getLocalPort", "()I"), native("accept", "()Ljava/net/Socket;"), native("setSoTimeout", "(I)V"), native("close", "()V")]),
     cls("java/io/SocketInputStream", "java/io/InputStream", Nil{}),
     cls("java/io/SocketOutputStream", "java/io/OutputStream", Nil{}),
     cls("java/lang/Cloneable", "java/lang/Object", Nil{}),
     cls("java/io/Serializable", "java/lang/Object", Nil{}),
     M.ClassFile{0, 52, 17, "[Ljava/lang/String;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[B", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[C", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[Ljava/lang/Object;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[Ljava/lang/Throwable;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}}],
    throwables())

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

type Sig is Data:
  Sig{owner: String, name: String, desc: String, id: U32}

def sig_id(sigs: +List<Sig>, +owner: String, +name: String, +desc: String) -> U32:
  match sigs:
    case Nil{}:
      0
    case Con{Sig{+o, +n, +d, +id}, rest}:
      Bool.pick(U32, String.eq(o, owner) && String.eq(n, name) && String.eq(d, desc), id, sig_id(rest, owner, name, desc))

def is_throwable(+name: String) -> Bool:
  Bool.or(String.eq(name, "java/lang/Throwable"), Bool.or(String.ends_with(name, "Exception"), String.ends_with(name, "Error")))

def ctor_id(+owner: String, +desc: String) -> U32:
  Bool.pick(U32, String.eq(owner, "java/lang/Object"), 1,
  Bool.pick(U32, String.eq(owner, "java/lang/StringBuilder") && String.eq(desc, "()V"), 29,
  Bool.pick(U32, String.eq(owner, "java/lang/StringBuilder") && String.eq(desc, "(Ljava/lang/String;)V"), 30,
  Bool.pick(U32, String.eq(owner, "java/util/ArrayList") && String.eq(desc, "()V"), 48,
  Bool.pick(U32, String.eq(owner, "java/util/ArrayList") && String.eq(desc, "(I)V"), 49,
  Bool.pick(U32, String.eq(owner, "java/util/HashMap") && String.eq(desc, "()V"), 63,
  Bool.pick(U32, String.eq(owner, "java/io/ByteArrayInputStream") && String.eq(desc, "([B)V"), 68,
  Bool.pick(U32, String.eq(owner, "java/io/ByteArrayOutputStream") && String.eq(desc, "()V"), 69,
  Bool.pick(U32, String.eq(owner, "java/io/File") && String.eq(desc, "(Ljava/lang/String;)V"), 79,
  Bool.pick(U32, String.eq(owner, "java/io/FileInputStream") && String.eq(desc, "(Ljava/lang/String;)V"), 84,
  Bool.pick(U32, String.eq(owner, "java/io/FileOutputStream") && String.eq(desc, "(Ljava/lang/String;)V"), 85,
  Bool.pick(U32, String.eq(owner, "java/io/FileOutputStream") && String.eq(desc, "(Ljava/lang/String;Z)V"), 86,
  Bool.pick(U32, String.eq(owner, "java/io/InputStreamReader") && String.eq(desc, "(Ljava/io/InputStream;Ljava/lang/String;)V"), 92,
  Bool.pick(U32, String.eq(owner, "java/io/OutputStreamWriter") && String.eq(desc, "(Ljava/io/OutputStream;Ljava/lang/String;)V"), 93,
  Bool.pick(U32, String.eq(owner, "java/io/BufferedReader") && String.eq(desc, "(Ljava/io/Reader;)V"), 94,
  Bool.pick(U32, String.eq(owner, "java/net/InetSocketAddress") && String.eq(desc, "(Ljava/lang/String;I)V"), 96,
  Bool.pick(U32, String.eq(owner, "java/net/Socket") && String.eq(desc, "()V"), 97,
  Bool.pick(U32, String.eq(owner, "java/net/Socket") && String.eq(desc, "(Ljava/lang/String;I)V"), 98,
  Bool.pick(U32, String.eq(owner, "java/net/ServerSocket") && String.eq(desc, "(I)V"), 104,
  Bool.pick(U32, String.eq(owner, "java/net/SocketAddress") && String.eq(desc, "()V"), 1,
  Bool.pick(U32, is_throwable(owner) && String.eq(desc, "()V"), 211,
  Bool.pick(U32, is_throwable(owner) && String.eq(desc, "(Ljava/lang/String;)V"), 212,
  Bool.pick(U32, is_throwable(owner) && String.eq(desc, "(Ljava/lang/Throwable;)V"), 213,
  Bool.pick(U32, is_throwable(owner) && String.eq(desc, "(Ljava/lang/String;Ljava/lang/Throwable;)V"), 214,
  0))))))))))))))))))))))))

def signatures() -> +List<Sig>:
  [Sig{"java/io/PrintStream", "println", "(I)V", 2},
   Sig{"java/io/PrintStream", "println", "(Ljava/lang/String;)V", 3},
   Sig{"java/io/PrintStream", "println", "()V", 4},
   Sig{"java/io/PrintStream", "println", "(F)V", 5},
   Sig{"java/io/PrintStream", "println", "(Z)V", 6},
   Sig{"java/lang/ClassLoader", "getSystemResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;", 9},
   Sig{"java/io/InputStream", "read", "()I", 10},
   Sig{"java/io/InputStream", "close", "()V", 11},
   Sig{"java/io/ByteArrayInputStream", "read", "()I", 10},
   Sig{"java/io/ByteArrayInputStream", "close", "()V", 11},
   Sig{"java/io/FileInputStream", "read", "()I", 10},
   Sig{"java/io/FileInputStream", "close", "()V", 11},
   Sig{"java/io/SocketInputStream", "read", "()I", 10},
   Sig{"java/io/SocketInputStream", "close", "()V", 11},
   Sig{"java/lang/Object", "equals", "(Ljava/lang/Object;)Z", 12},
   Sig{"java/lang/Object", "hashCode", "()I", 13},
   Sig{"java/lang/Object", "toString", "()Ljava/lang/String;", 14},
   Sig{"java/util/Objects", "requireNonNull", "(Ljava/lang/Object;)Ljava/lang/Object;", 15},
   Sig{"java/util/Objects", "equals", "(Ljava/lang/Object;Ljava/lang/Object;)Z", 16},
   Sig{"java/lang/String", "length", "()I", 17},
   Sig{"java/lang/String", "isEmpty", "()Z", 18},
   Sig{"java/lang/String", "charAt", "(I)C", 19},
   Sig{"java/lang/String", "equals", "(Ljava/lang/Object;)Z", 20},
   Sig{"java/lang/String", "hashCode", "()I", 21},
   Sig{"java/lang/String", "substring", "(I)Ljava/lang/String;", 22},
   Sig{"java/lang/String", "substring", "(II)Ljava/lang/String;", 23},
   Sig{"java/lang/String", "concat", "(Ljava/lang/String;)Ljava/lang/String;", 24},
   Sig{"java/lang/String", "toString", "()Ljava/lang/String;", 25},
   Sig{"java/lang/String", "valueOf", "(I)Ljava/lang/String;", 26},
   Sig{"java/lang/String", "valueOf", "(Z)Ljava/lang/String;", 27},
   Sig{"java/lang/String", "valueOf", "(Ljava/lang/Object;)Ljava/lang/String;", 28},
   Sig{"java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;", 31},
   Sig{"java/lang/StringBuilder", "append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;", 32},
   Sig{"java/lang/StringBuilder", "append", "(I)Ljava/lang/StringBuilder;", 33},
   Sig{"java/lang/StringBuilder", "append", "(C)Ljava/lang/StringBuilder;", 34},
   Sig{"java/lang/StringBuilder", "append", "(Z)Ljava/lang/StringBuilder;", 35},
   Sig{"java/lang/StringBuilder", "length", "()I", 36},
   Sig{"java/lang/StringBuilder", "toString", "()Ljava/lang/String;", 37},
   Sig{"java/lang/Integer", "valueOf", "(I)Ljava/lang/Integer;", 38},
   Sig{"java/lang/Integer", "intValue", "()I", 39},
   Sig{"java/lang/Integer", "parseInt", "(Ljava/lang/String;)I", 40},
   Sig{"java/lang/Integer", "equals", "(Ljava/lang/Object;)Z", 41},
   Sig{"java/lang/Integer", "hashCode", "()I", 42},
   Sig{"java/lang/Integer", "toString", "()Ljava/lang/String;", 43},
   Sig{"java/lang/Math", "abs", "(I)I", 44},
   Sig{"java/lang/Math", "min", "(II)I", 45},
   Sig{"java/lang/Math", "max", "(II)I", 46},
   Sig{"java/lang/System", "arraycopy", "(Ljava/lang/Object;ILjava/lang/Object;II)V", 47},
   Sig{"java/util/ArrayList", "size", "()I", 50},
   Sig{"java/util/ArrayList", "isEmpty", "()Z", 51},
   Sig{"java/util/ArrayList", "add", "(Ljava/lang/Object;)Z", 52},
   Sig{"java/util/ArrayList", "add", "(ILjava/lang/Object;)V", 53},
   Sig{"java/util/ArrayList", "get", "(I)Ljava/lang/Object;", 54},
   Sig{"java/util/ArrayList", "set", "(ILjava/lang/Object;)Ljava/lang/Object;", 55},
   Sig{"java/util/ArrayList", "remove", "(I)Ljava/lang/Object;", 56},
   Sig{"java/util/ArrayList", "contains", "(Ljava/lang/Object;)Z", 57},
   Sig{"java/util/ArrayList", "clear", "()V", 58},
   Sig{"java/util/ArrayList", "iterator", "()Ljava/util/Iterator;", 59},
   Sig{"java/util/ArrayList$Itr", "hasNext", "()Z", 60},
   Sig{"java/util/ArrayList$Itr", "next", "()Ljava/lang/Object;", 61},
   Sig{"java/util/ArrayList$Itr", "remove", "()V", 62},
   Sig{"java/util/HashMap", "size", "()I", 50},
   Sig{"java/util/HashMap", "isEmpty", "()Z", 51},
   Sig{"java/util/HashMap", "clear", "()V", 58},
   Sig{"java/util/HashMap", "put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;", 64},
   Sig{"java/util/HashMap", "get", "(Ljava/lang/Object;)Ljava/lang/Object;", 65},
   Sig{"java/util/HashMap", "containsKey", "(Ljava/lang/Object;)Z", 66},
   Sig{"java/util/HashMap", "remove", "(Ljava/lang/Object;)Ljava/lang/Object;", 67},
   Sig{"java/io/ByteArrayOutputStream", "toByteArray", "()[B", 70},
   Sig{"java/io/ByteArrayOutputStream", "size", "()I", 71},
   Sig{"java/io/ByteArrayOutputStream", "reset", "()V", 72},
   Sig{"java/io/InputStream", "read", "([B)I", 73},
   Sig{"java/io/InputStream", "read", "([BII)I", 74},
   Sig{"java/io/ByteArrayInputStream", "read", "([B)I", 73},
   Sig{"java/io/ByteArrayInputStream", "read", "([BII)I", 74},
   Sig{"java/io/FileInputStream", "read", "([B)I", 73},
   Sig{"java/io/FileInputStream", "read", "([BII)I", 74},
   Sig{"java/io/SocketInputStream", "read", "([B)I", 73},
   Sig{"java/io/SocketInputStream", "read", "([BII)I", 74},
   Sig{"java/io/OutputStream", "write", "(I)V", 75},
   Sig{"java/io/OutputStream", "write", "([B)V", 76},
   Sig{"java/io/OutputStream", "write", "([BII)V", 77},
   Sig{"java/io/OutputStream", "flush", "()V", 78},
   Sig{"java/io/OutputStream", "close", "()V", 11},
   Sig{"java/io/ByteArrayOutputStream", "write", "(I)V", 75},
   Sig{"java/io/ByteArrayOutputStream", "write", "([B)V", 76},
   Sig{"java/io/ByteArrayOutputStream", "write", "([BII)V", 77},
   Sig{"java/io/ByteArrayOutputStream", "flush", "()V", 78},
   Sig{"java/io/ByteArrayOutputStream", "close", "()V", 11},
   Sig{"java/io/FileOutputStream", "write", "(I)V", 75},
   Sig{"java/io/FileOutputStream", "write", "([B)V", 76},
   Sig{"java/io/FileOutputStream", "write", "([BII)V", 77},
   Sig{"java/io/FileOutputStream", "flush", "()V", 78},
   Sig{"java/io/FileOutputStream", "close", "()V", 11},
   Sig{"java/io/SocketOutputStream", "write", "(I)V", 75},
   Sig{"java/io/SocketOutputStream", "write", "([B)V", 76},
   Sig{"java/io/SocketOutputStream", "write", "([BII)V", 77},
   Sig{"java/io/SocketOutputStream", "flush", "()V", 78},
   Sig{"java/io/SocketOutputStream", "close", "()V", 11},
   Sig{"java/io/File", "exists", "()Z", 80},
   Sig{"java/io/File", "isFile", "()Z", 81},
   Sig{"java/io/File", "isDirectory", "()Z", 82},
   Sig{"java/io/File", "getPath", "()Ljava/lang/String;", 83},
   Sig{"java/io/Reader", "read", "()I", 87},
   Sig{"java/io/Reader", "read", "([CII)I", 88},
   Sig{"java/io/Reader", "close", "()V", 11},
   Sig{"java/io/InputStreamReader", "read", "()I", 87},
   Sig{"java/io/InputStreamReader", "read", "([CII)I", 88},
   Sig{"java/io/InputStreamReader", "close", "()V", 11},
   Sig{"java/io/BufferedReader", "read", "()I", 87},
   Sig{"java/io/BufferedReader", "read", "([CII)I", 88},
   Sig{"java/io/BufferedReader", "close", "()V", 11},
   Sig{"java/io/Writer", "write", "(I)V", 89},
   Sig{"java/io/Writer", "write", "(Ljava/lang/String;)V", 90},
   Sig{"java/io/Writer", "write", "([CII)V", 91},
   Sig{"java/io/Writer", "flush", "()V", 78},
   Sig{"java/io/Writer", "close", "()V", 11},
   Sig{"java/io/OutputStreamWriter", "write", "(I)V", 89},
   Sig{"java/io/OutputStreamWriter", "write", "(Ljava/lang/String;)V", 90},
   Sig{"java/io/OutputStreamWriter", "write", "([CII)V", 91},
   Sig{"java/io/OutputStreamWriter", "flush", "()V", 78},
   Sig{"java/io/OutputStreamWriter", "close", "()V", 11},
   Sig{"java/io/BufferedReader", "readLine", "()Ljava/lang/String;", 95},
   Sig{"java/net/Socket", "connect", "(Ljava/net/SocketAddress;I)V", 99},
   Sig{"java/net/Socket", "getInputStream", "()Ljava/io/InputStream;", 100},
   Sig{"java/net/Socket", "getOutputStream", "()Ljava/io/OutputStream;", 101},
   Sig{"java/net/Socket", "setSoTimeout", "(I)V", 102},
   Sig{"java/net/Socket", "close", "()V", 103},
   Sig{"java/net/ServerSocket", "getLocalPort", "()I", 105},
   Sig{"java/net/ServerSocket", "accept", "()Ljava/net/Socket;", 106},
   Sig{"java/net/ServerSocket", "setSoTimeout", "(I)V", 107},
   Sig{"java/net/ServerSocket", "close", "()V", 108},
   Sig{"java/lang/Throwable", "getMessage", "()Ljava/lang/String;", 109},
   Sig{"java/lang/Throwable", "getCause", "()Ljava/lang/Throwable;", 110},
   Sig{"java/lang/Throwable", "initCause", "(Ljava/lang/Throwable;)Ljava/lang/Throwable;", 111},
   Sig{"java/lang/Throwable", "addSuppressed", "(Ljava/lang/Throwable;)V", 112},
   Sig{"java/lang/Throwable", "getSuppressed", "()[Ljava/lang/Throwable;", 113},
   Sig{"java/lang/Throwable", "toString", "()Ljava/lang/String;", 114},
   Sig{"java/lang/Exception", "getMessage", "()Ljava/lang/String;", 109},
   Sig{"java/lang/Exception", "getCause", "()Ljava/lang/Throwable;", 110},
   Sig{"java/lang/Exception", "initCause", "(Ljava/lang/Throwable;)Ljava/lang/Throwable;", 111},
   Sig{"java/lang/Exception", "addSuppressed", "(Ljava/lang/Throwable;)V", 112},
   Sig{"java/lang/Exception", "getSuppressed", "()[Ljava/lang/Throwable;", 113},
   Sig{"java/lang/Exception", "toString", "()Ljava/lang/String;", 114},
   Sig{"java/lang/RuntimeException", "getMessage", "()Ljava/lang/String;", 109},
   Sig{"java/lang/RuntimeException", "getCause", "()Ljava/lang/Throwable;", 110},
   Sig{"java/lang/RuntimeException", "initCause", "(Ljava/lang/Throwable;)Ljava/lang/Throwable;", 111},
   Sig{"java/lang/RuntimeException", "addSuppressed", "(Ljava/lang/Throwable;)V", 112},
   Sig{"java/lang/RuntimeException", "getSuppressed", "()[Ljava/lang/Throwable;", 113},
   Sig{"java/lang/RuntimeException", "toString", "()Ljava/lang/String;", 114},
   Sig{"java/lang/Error", "getMessage", "()Ljava/lang/String;", 109},
   Sig{"java/lang/Error", "getCause", "()Ljava/lang/Throwable;", 110},
   Sig{"java/lang/Error", "toString", "()Ljava/lang/String;", 114}]

def throwable_inherited(+owner: String, +name: String, +desc: String) -> U32:
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "getMessage") && String.eq(desc, "()Ljava/lang/String;"), 109,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "getCause") && String.eq(desc, "()Ljava/lang/Throwable;"), 110,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "initCause") && String.eq(desc, "(Ljava/lang/Throwable;)Ljava/lang/Throwable;"), 111,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "addSuppressed") && String.eq(desc, "(Ljava/lang/Throwable;)V"), 112,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "getSuppressed") && String.eq(desc, "()[Ljava/lang/Throwable;"), 113,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "toString") && String.eq(desc, "()Ljava/lang/String;"), 114,
  0))))))

def intrinsic_desc(+owner: String, +name: String, +desc: String) -> U32:
  +found = sig_id(signatures(), owner, name, desc)
  Bool.pick(U32, U32.is_ne(found, 0), found,
    Bool.pick(U32, String.eq(name, "<init>"), ctor_id(owner, desc), throwable_inherited(owner, name, desc)))
