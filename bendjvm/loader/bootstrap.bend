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
   exception("java/lang/ReflectiveOperationException", "java/lang/Exception"),
   exception("java/lang/IllegalAccessException", "java/lang/ReflectiveOperationException"),
   exception("java/lang/InstantiationException", "java/lang/ReflectiveOperationException"),
   exception("java/lang/NoSuchFieldException", "java/lang/ReflectiveOperationException"),
   exception("java/lang/ClassNotFoundException", "java/lang/ReflectiveOperationException"),
   exception("java/lang/NoSuchMethodException", "java/lang/ReflectiveOperationException"),
   exception4("java/lang/RuntimeException", "java/lang/Exception"),
   cls("java/lang/reflect/UndeclaredThrowableException", "java/lang/RuntimeException", [native("<init>", "(Ljava/lang/Throwable;)V"), native("<init>", "(Ljava/lang/String;Ljava/lang/Throwable;)V"), native("getUndeclaredThrowable", "()Ljava/lang/Throwable;")]),
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
  [native("<init>", "()V"), native("getClass", "()Ljava/lang/Class;"), native("equals", "(Ljava/lang/Object;)Z"), native("hashCode", "()I"), native("toString", "()Ljava/lang/String;")]

def class_methods() -> +List<M.Method>:
  M.append(M.Method,
    [native("getName", "()Ljava/lang/String;"), native("getSuperclass", "()Ljava/lang/Class;"), native("getModifiers", "()I"), native("isPrimitive", "()Z"), native("isArray", "()Z"), native("isInterface", "()Z"), native("isAnnotation", "()Z"), native("isEnum", "()Z"), native("getInterfaces", "()[Ljava/lang/Class;"), native("getComponentType", "()Ljava/lang/Class;"), native("isAssignableFrom", "(Ljava/lang/Class;)Z"), native("isInstance", "(Ljava/lang/Object;)Z"), native("cast", "(Ljava/lang/Object;)Ljava/lang/Object;"), native_static("forName", "(Ljava/lang/String;)Ljava/lang/Class;"), native_static("forName", "(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;"), native("getDeclaredFields", "()[Ljava/lang/reflect/Field;"), native("getDeclaredMethods", "()[Ljava/lang/reflect/Method;"), native("getDeclaredConstructors", "()[Ljava/lang/reflect/Constructor;"), native("getDeclaredField", "(Ljava/lang/String;)Ljava/lang/reflect/Field;"), native("getDeclaredMethod", "(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;"), native("getDeclaredConstructor", "([Ljava/lang/Class;)Ljava/lang/reflect/Constructor;"), native("getFields", "()[Ljava/lang/reflect/Field;"), native("getMethods", "()[Ljava/lang/reflect/Method;"), native("getConstructors", "()[Ljava/lang/reflect/Constructor;"), native("getField", "(Ljava/lang/String;)Ljava/lang/reflect/Field;"), native("getMethod", "(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;"), native("getConstructor", "([Ljava/lang/Class;)Ljava/lang/reflect/Constructor;"), native("getResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;"), native("getResource", "(Ljava/lang/String;)Ljava/net/URL;"), native("getClassLoader", "()Ljava/lang/ClassLoader;"), native("isAnnotationPresent", "(Ljava/lang/Class;)Z"), native("getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getAnnotations", "()[Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;")],
    [native("getAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;")])

def string_methods() -> +List<M.Method>:
  [native("length", "()I"), native("isEmpty", "()Z"), native("charAt", "(I)C"), native("equals", "(Ljava/lang/Object;)Z"), native("hashCode", "()I"), native("substring", "(I)Ljava/lang/String;"), native("substring", "(II)Ljava/lang/String;"), native("concat", "(Ljava/lang/String;)Ljava/lang/String;"), native("toString", "()Ljava/lang/String;"), native_static("valueOf", "(I)Ljava/lang/String;"), native_static("valueOf", "(Z)Ljava/lang/String;"), native_static("valueOf", "(Ljava/lang/Object;)Ljava/lang/String;")]

def builder_methods() -> +List<M.Method>:
  [native("<init>", "()V"), native("<init>", "(Ljava/lang/String;)V"), native("append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;"), native("append", "(Ljava/lang/Object;)Ljava/lang/StringBuilder;"), native("append", "(I)Ljava/lang/StringBuilder;"), native("append", "(C)Ljava/lang/StringBuilder;"), native("append", "(Z)Ljava/lang/StringBuilder;"), native("length", "()I"), native("toString", "()Ljava/lang/String;")]

def integer_methods() -> +List<M.Method>:
  [native_static("valueOf", "(I)Ljava/lang/Integer;"), native("intValue", "()I"), native_static("parseInt", "(Ljava/lang/String;)I"), native("equals", "(Ljava/lang/Object;)Z"), native("hashCode", "()I"), native("toString", "()Ljava/lang/String;")]
def byte_methods() -> +List<M.Method>:
  [native_static("valueOf", "(B)Ljava/lang/Byte;"), native("byteValue", "()B"), native("toString", "()Ljava/lang/String;")]
def short_methods() -> +List<M.Method>:
  [native_static("valueOf", "(S)Ljava/lang/Short;"), native("shortValue", "()S"), native("toString", "()Ljava/lang/String;")]
def character_methods() -> +List<M.Method>:
  [native_static("valueOf", "(C)Ljava/lang/Character;"), native("charValue", "()C"), native("toString", "()Ljava/lang/String;")]
def float_methods() -> +List<M.Method>:
  [native_static("valueOf", "(F)Ljava/lang/Float;"), native("floatValue", "()F"), native("toString", "()Ljava/lang/String;")]
def boolean_class() -> M.ClassFile:
  M.ClassFile{0, 52, 1, "java/lang/Boolean", "java/lang/Object", Nil{}, [M.Unused{}], [M.Field{9, "TYPE", "Ljava/lang/Class;", 0, Nil{}}, M.Field{25, "TRUE", "Ljava/lang/Boolean;", 0, Nil{}}, M.Field{25, "FALSE", "Ljava/lang/Boolean;", 0, Nil{}}], [native_static("valueOf", "(Z)Ljava/lang/Boolean;"), native("booleanValue", "()Z"), native("toString", "()Ljava/lang/String;")], Nil{}}
def primitive_wrapper(name: String, methods: +List<M.Method>) -> M.ClassFile:
  M.ClassFile{0, 52, 1, name, "java/lang/Object", Nil{}, [M.Unused{}], [M.Field{9, "TYPE", "Ljava/lang/Class;", 0, Nil{}}], methods, Nil{}}

def boolean_methods() -> +List<M.Method>:
  [native_static("valueOf", "(Z)Ljava/lang/Boolean;"), native("booleanValue", "()Z"), native("toString", "()Ljava/lang/String;")]
def primitive_class(name: String) -> M.ClassFile:
  M.ClassFile{0, 52, 1, name, "", Nil{}, [M.Unused{}], Nil{}, Nil{}, Nil{}}


def list_methods() -> +List<M.Method>:
  [native("<init>", "()V"), native("<init>", "(I)V"), native("size", "()I"), native("isEmpty", "()Z"), native("add", "(Ljava/lang/Object;)Z"), native("add", "(ILjava/lang/Object;)V"), native("get", "(I)Ljava/lang/Object;"), native("set", "(ILjava/lang/Object;)Ljava/lang/Object;"), native("remove", "(I)Ljava/lang/Object;"), native("contains", "(Ljava/lang/Object;)Z"), native("clear", "()V"), native("iterator", "()Ljava/util/Iterator;")]

def map_methods() -> +List<M.Method>:
  [native("<init>", "()V"), native("size", "()I"), native("isEmpty", "()Z"), native("put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"), native("get", "(Ljava/lang/Object;)Ljava/lang/Object;"), native("containsKey", "(Ljava/lang/Object;)Z"), native("remove", "(Ljava/lang/Object;)Ljava/lang/Object;"), native("clear", "()V")]

def stream_in() -> +List<M.Method>:
  [native("read", "()I"), native("read", "([B)I"), native("read", "([BII)I"), native("close", "()V")]

def stream_out() -> +List<M.Method>:
  [native("write", "(I)V"), native("write", "([B)V"), native("write", "([BII)V"), native("flush", "()V"), native("close", "()V")]

def array_class(name: String) -> M.ClassFile:
  M.ClassFile{0, 52, 17, name, "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}}

def primitive_arrays() -> +List<M.ClassFile>:
  [array_class("[Z"), array_class("[C"), array_class("[F"), array_class("[B"), array_class("[S"), array_class("[I")]
def classes() -> +List<M.ClassFile>:
  M.append(M.ClassFile,
    [cls("java/lang/Object", "", object_methods()),
     cls("java/lang/String", "java/lang/Object", string_methods()),
     cls("java/lang/Class", "java/lang/Object", class_methods()),
     cls("java/lang/StringBuilder", "java/lang/Object", builder_methods()),
     primitive_wrapper("java/lang/Integer", integer_methods()),
     cls("java/lang/Math", "java/lang/Object", [native_static("abs", "(I)I"), native_static("min", "(II)I"), native_static("max", "(II)I")]),
     primitive_wrapper("java/lang/Byte", byte_methods()),
     primitive_wrapper("java/lang/Short", short_methods()),
     primitive_wrapper("java/lang/Character", character_methods()),
     primitive_wrapper("java/lang/Float", float_methods()),
     primitive_wrapper("java/lang/Void", Nil{}),
     boolean_class(),
     primitive_class("boolean"),
     primitive_class("byte"),
     primitive_class("char"),
     primitive_class("short"),
     primitive_class("int"),
     primitive_class("long"),
     primitive_class("float"),
     primitive_class("double"),
     primitive_class("void"),
     cls("java/lang/Enum", "java/lang/Object", [native("<init>", "(Ljava/lang/String;I)V"), native("name", "()Ljava/lang/String;"), native("ordinal", "()I"), native_static("valueOf", "(Ljava/lang/Class;Ljava/lang/String;)Ljava/lang/Enum;")]),
     iface("java/lang/reflect/AnnotatedType", Nil{}, [native("isAnnotationPresent", "(Ljava/lang/Class;)Z"), native("getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getAnnotations", "()[Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;")]),
     iface("java/lang/reflect/InvocationHandler", Nil{}, [abs_m("invoke", "(Ljava/lang/Object;Ljava/lang/reflect/Method;[Ljava/lang/Object;)Ljava/lang/Object;")]),
     cls("java/lang/reflect/Proxy", "java/lang/Object", [native("<init>", "(Ljava/lang/reflect/InvocationHandler;)V"), native_static("newProxyInstance", "(Ljava/lang/ClassLoader;[Ljava/lang/Class;Ljava/lang/reflect/InvocationHandler;)Ljava/lang/Object;"), native_static("getProxyClass", "(Ljava/lang/ClassLoader;[Ljava/lang/Class;)Ljava/lang/Class;"), native_static("isProxyClass", "(Ljava/lang/Class;)Z"), native_static("getInvocationHandler", "(Ljava/lang/Object;)Ljava/lang/reflect/InvocationHandler;")]),
     iface("java/lang/annotation/Annotation", Nil{}, Nil{}),
     iface("java/lang/annotation/Retention", Nil{}, Nil{}),
     iface("java/lang/annotation/Target", Nil{}, Nil{}),
     iface("java/lang/annotation/Inherited", Nil{}, Nil{}),
     iface("java/lang/annotation/Documented", Nil{}, Nil{}),
     iface("java/lang/annotation/Repeatable", Nil{}, [abs_m("value", "()Ljava/lang/Class;")]),
     cls("java/lang/AssertionError", "java/lang/Error", Nil{}),
     cls("java/lang/annotation/RetentionPolicy", "java/lang/Enum", Nil{}),
     cls("java/lang/AnnotationEnumCache", "java/lang/Object", Nil{}),
     cls("java/util/Objects", "java/lang/Object", [native_static("requireNonNull", "(Ljava/lang/Object;)Ljava/lang/Object;"), native_static("equals", "(Ljava/lang/Object;Ljava/lang/Object;)Z")]),
     cls("java/lang/ClassLoader", "java/lang/Object", [native_static("getSystemResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;"), native_static("getSystemResource", "(Ljava/lang/String;)Ljava/net/URL;"), native_static("getSystemResources", "(Ljava/lang/String;)Ljava/util/Enumeration;"), native_static("getSystemClassLoader", "()Ljava/lang/ClassLoader;"), native("loadClass", "(Ljava/lang/String;)Ljava/lang/Class;"), native("getResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;"), native("getResource", "(Ljava/lang/String;)Ljava/net/URL;"), native("getResources", "(Ljava/lang/String;)Ljava/util/Enumeration;")]),
     cls("java/net/URL", "java/lang/Object", [native("openStream", "()Ljava/io/InputStream;"), native("getPath", "()Ljava/lang/String;"), native("getProtocol", "()Ljava/lang/String;"), native("toExternalForm", "()Ljava/lang/String;"), native("toString", "()Ljava/lang/String;")]),
     cls("java/lang/reflect/AccessibleObject", "java/lang/Object", [native("setAccessible", "(Z)V"), native("isAccessible", "()Z")]),
     cls("java/lang/reflect/Field", "java/lang/reflect/AccessibleObject", [native("getName", "()Ljava/lang/String;"), native("getModifiers", "()I"), native("getDeclaringClass", "()Ljava/lang/Class;"), native("getType", "()Ljava/lang/Class;"), native("get", "(Ljava/lang/Object;)Ljava/lang/Object;"), native("set", "(Ljava/lang/Object;Ljava/lang/Object;)V"), native("getInt", "(Ljava/lang/Object;)I"), native("setInt", "(Ljava/lang/Object;I)V"), native("isSynthetic", "()Z"), native("isEnumConstant", "()Z"), native("equals", "(Ljava/lang/Object;)Z"), native("hashCode", "()I"), native("isAnnotationPresent", "(Ljava/lang/Class;)Z"), native("getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getAnnotations", "()[Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;"), native("getAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;")]),
     cls("java/lang/reflect/Method", "java/lang/reflect/AccessibleObject", [native("getName", "()Ljava/lang/String;"), native("getModifiers", "()I"), native("getDeclaringClass", "()Ljava/lang/Class;"), native("getReturnType", "()Ljava/lang/Class;"), native("getParameterTypes", "()[Ljava/lang/Class;"), native("getExceptionTypes", "()[Ljava/lang/Class;"), native("isBridge", "()Z"), native("isSynthetic", "()Z"), native("isVarArgs", "()Z"), native("equals", "(Ljava/lang/Object;)Z"), native("hashCode", "()I"), native("invoke", "(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;"), native("isAnnotationPresent", "(Ljava/lang/Class;)Z"), native("getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getAnnotations", "()[Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;"), native("getParameterAnnotations", "()[[Ljava/lang/annotation/Annotation;"), native("getDefaultValue", "()Ljava/lang/Object;"), native("getAnnotatedParameterTypes", "()[Ljava/lang/reflect/AnnotatedType;"), native("getAnnotatedReturnType", "()Ljava/lang/reflect/AnnotatedType;"), native("getAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;")]),
     cls("java/lang/reflect/Constructor", "java/lang/reflect/AccessibleObject", [native("getName", "()Ljava/lang/String;"), native("getModifiers", "()I"), native("getDeclaringClass", "()Ljava/lang/Class;"), native("getParameterTypes", "()[Ljava/lang/Class;"), native("getExceptionTypes", "()[Ljava/lang/Class;"), native("isSynthetic", "()Z"), native("isVarArgs", "()Z"), native("equals", "(Ljava/lang/Object;)Z"), native("hashCode", "()I"), native("newInstance", "([Ljava/lang/Object;)Ljava/lang/Object;"), native("isAnnotationPresent", "(Ljava/lang/Class;)Z"), native("getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;"), native("getAnnotations", "()[Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;"), native("getParameterAnnotations", "()[[Ljava/lang/annotation/Annotation;"), native("getAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;"), native("getDeclaredAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;")]),
     M.ClassFile{0, 52, 1, "java/lang/System", "java/lang/Object", Nil{}, [M.Unused{}], [M.Field{9, "out", "Ljava/io/PrintStream;", 0, Nil{}}], [native_static("arraycopy", "(Ljava/lang/Object;ILjava/lang/Object;II)V")], Nil{}},
     cls("java/io/PrintStream", "java/lang/Object", [native("println", "(I)V"), native("println", "(Ljava/lang/String;)V"), native("println", "()V"), native("println", "(F)V"), native("println", "(Z)V"), native("println", "(C)V")]),
     iface("java/lang/AutoCloseable", Nil{}, [abs_m("close", "()V")]),
     iface("java/io/Closeable", ["java/lang/AutoCloseable"], [abs_m("close", "()V")]),
     iface("java/io/Flushable", Nil{}, [abs_m("flush", "()V")]),
     iface("java/lang/Iterable", Nil{}, [abs_m("iterator", "()Ljava/util/Iterator;")]),
     iface("java/util/Enumeration", Nil{}, [abs_m("hasMoreElements", "()Z"), abs_m("nextElement", "()Ljava/lang/Object;")]),
     iface("java/util/Iterator", Nil{}, [abs_m("hasNext", "()Z"), abs_m("next", "()Ljava/lang/Object;"), abs_m("remove", "()V")]),
     iface("java/util/Collection", ["java/lang/Iterable"], [abs_m("size", "()I"), abs_m("isEmpty", "()Z"), abs_m("add", "(Ljava/lang/Object;)Z"), abs_m("contains", "(Ljava/lang/Object;)Z"), abs_m("clear", "()V"), abs_m("iterator", "()Ljava/util/Iterator;")]),
     iface("java/util/List", ["java/util/Collection"], [abs_m("size", "()I"), abs_m("isEmpty", "()Z"), abs_m("add", "(Ljava/lang/Object;)Z"), abs_m("contains", "(Ljava/lang/Object;)Z"), abs_m("clear", "()V"), abs_m("iterator", "()Ljava/util/Iterator;"), abs_m("get", "(I)Ljava/lang/Object;"), abs_m("set", "(ILjava/lang/Object;)Ljava/lang/Object;"), abs_m("add", "(ILjava/lang/Object;)V"), abs_m("remove", "(I)Ljava/lang/Object;")]),
     iface("java/util/Map", Nil{}, [abs_m("size", "()I"), abs_m("isEmpty", "()Z"), abs_m("put", "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;"), abs_m("get", "(Ljava/lang/Object;)Ljava/lang/Object;"), abs_m("containsKey", "(Ljava/lang/Object;)Z"), abs_m("remove", "(Ljava/lang/Object;)Ljava/lang/Object;"), abs_m("clear", "()V")]),
     cls_if("java/util/ArrayList", "java/lang/Object", ["java/util/List", "java/util/Collection", "java/lang/Iterable"], list_methods()),
     cls_if("java/util/ArrayList$Itr", "java/lang/Object", ["java/util/Iterator"], [native("hasNext", "()Z"), native("next", "()Ljava/lang/Object;"), native("remove", "()V")]),
     cls_if("java/util/ResourceEnumeration", "java/lang/Object", ["java/util/Enumeration"], [native("hasMoreElements", "()Z"), native("nextElement", "()Ljava/lang/Object;")]),
     cls_if("java/util/HashMap", "java/lang/Object", ["java/util/Map"], map_methods()),
     cls("java/util/Properties", "java/util/HashMap", [native("<init>", "()V"), native("load", "(Ljava/io/InputStream;)V"), native("load", "(Ljava/io/Reader;)V"), native("getProperty", "(Ljava/lang/String;)Ljava/lang/String;"), native("getProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"), native("setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;")]),
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
     M.ClassFile{0, 52, 17, "[Ljava/lang/reflect/Field;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[Ljava/lang/reflect/Method;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[Ljava/lang/reflect/Constructor;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[Ljava/lang/Class;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[Ljava/lang/reflect/AnnotatedType;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[Ljava/lang/annotation/Annotation;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[[Ljava/lang/annotation/Annotation;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}},
     M.ClassFile{0, 52, 17, "[Ljava/lang/Throwable;", "java/lang/Object", ["java/lang/Cloneable", "java/io/Serializable"], [M.Unused{}], Nil{}, Nil{}, Nil{}}],
    M.append(M.ClassFile, primitive_arrays(), throwables()))

def array_name(+name: String) -> String:
  Bool.pick(String, String.starts_with(name, "["), "[" ++ name, "[L" ++ name ++ ";")


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
  Bool.pick(U32, String.eq(owner, "java/lang/reflect/Proxy") && String.eq(desc, "(Ljava/lang/reflect/InvocationHandler;)V"), 249,
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
  0)))))))))))))))))))))))))

def signatures() -> +List<Sig>:
  [Sig{"java/io/PrintStream", "println", "(I)V", 2},
   Sig{"java/io/PrintStream", "println", "(Ljava/lang/String;)V", 3},
   Sig{"java/io/PrintStream", "println", "()V", 4},
   Sig{"java/io/PrintStream", "println", "(F)V", 5},
   Sig{"java/io/PrintStream", "println", "(Z)V", 6},
   Sig{"java/io/PrintStream", "println", "(C)V", 170},
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
   Sig{"java/lang/Object", "getClass", "()Ljava/lang/Class;", 115},
   Sig{"java/lang/Class", "getName", "()Ljava/lang/String;", 116},
   Sig{"java/lang/Class", "getSuperclass", "()Ljava/lang/Class;", 117},
   Sig{"java/lang/Class", "getModifiers", "()I", 118},
   Sig{"java/lang/Class", "isPrimitive", "()Z", 119},
   Sig{"java/lang/Class", "isArray", "()Z", 120},
   Sig{"java/lang/Class", "isInterface", "()Z", 121},
   Sig{"java/lang/Class", "isAssignableFrom", "(Ljava/lang/Class;)Z", 122},
   Sig{"java/lang/Class", "isInstance", "(Ljava/lang/Object;)Z", 185},
   Sig{"java/lang/Class", "cast", "(Ljava/lang/Object;)Ljava/lang/Object;", 123},
   Sig{"java/lang/Class", "forName", "(Ljava/lang/String;)Ljava/lang/Class;", 124},
   Sig{"java/lang/Class", "isAnnotation", "()Z", 154},
   Sig{"java/lang/Class", "isEnum", "()Z", 155},
   Sig{"java/lang/Class", "getInterfaces", "()[Ljava/lang/Class;", 156},
   Sig{"java/lang/Class", "getComponentType", "()Ljava/lang/Class;", 169},
   Sig{"java/lang/Byte", "valueOf", "(B)Ljava/lang/Byte;", 157},
   Sig{"java/lang/Byte", "byteValue", "()B", 158},
   Sig{"java/lang/Byte", "toString", "()Ljava/lang/String;", 159},
   Sig{"java/lang/Short", "valueOf", "(S)Ljava/lang/Short;", 160},
   Sig{"java/lang/Short", "shortValue", "()S", 161},
   Sig{"java/lang/Short", "toString", "()Ljava/lang/String;", 162},
   Sig{"java/lang/Character", "valueOf", "(C)Ljava/lang/Character;", 163},
   Sig{"java/lang/Character", "charValue", "()C", 164},
   Sig{"java/lang/Character", "toString", "()Ljava/lang/String;", 165},
   Sig{"java/lang/Float", "valueOf", "(F)Ljava/lang/Float;", 166},
   Sig{"java/lang/Float", "floatValue", "()F", 167},
   Sig{"java/lang/Float", "toString", "()Ljava/lang/String;", 168},
   Sig{"java/lang/ClassLoader", "getSystemClassLoader", "()Ljava/lang/ClassLoader;", 125},
   Sig{"java/lang/ClassLoader", "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;", 126},
   Sig{"java/lang/Class", "getDeclaredFields", "()[Ljava/lang/reflect/Field;", 127},
   Sig{"java/lang/Class", "getDeclaredMethods", "()[Ljava/lang/reflect/Method;", 128},
   Sig{"java/lang/Class", "getDeclaredConstructors", "()[Ljava/lang/reflect/Constructor;", 129},
   Sig{"java/lang/reflect/Field", "getName", "()Ljava/lang/String;", 130},
   Sig{"java/lang/reflect/Field", "getModifiers", "()I", 131},
   Sig{"java/lang/reflect/Field", "getDeclaringClass", "()Ljava/lang/Class;", 189},
   Sig{"java/lang/reflect/Field", "getType", "()Ljava/lang/Class;", 132},
   Sig{"java/lang/reflect/Method", "getName", "()Ljava/lang/String;", 133},
   Sig{"java/lang/reflect/Method", "getModifiers", "()I", 134},
   Sig{"java/lang/reflect/Method", "getDeclaringClass", "()Ljava/lang/Class;", 190},
   Sig{"java/lang/reflect/Method", "getReturnType", "()Ljava/lang/Class;", 135},
   Sig{"java/lang/reflect/Method", "getParameterTypes", "()[Ljava/lang/Class;", 136},
   Sig{"java/lang/reflect/Constructor", "getName", "()Ljava/lang/String;", 137},
   Sig{"java/lang/reflect/Constructor", "getModifiers", "()I", 138},
   Sig{"java/lang/reflect/Constructor", "getDeclaringClass", "()Ljava/lang/Class;", 191},
   Sig{"java/lang/reflect/Constructor", "getParameterTypes", "()[Ljava/lang/Class;", 139},
   Sig{"java/lang/ClassLoader", "getSystemResource", "(Ljava/lang/String;)Ljava/net/URL;", 140},
   Sig{"java/net/URL", "openStream", "()Ljava/io/InputStream;", 141},
   Sig{"java/util/Properties", "<init>", "()V", 143},
   Sig{"java/util/Properties", "load", "(Ljava/io/InputStream;)V", 144},
   Sig{"java/util/Properties", "getProperty", "(Ljava/lang/String;)Ljava/lang/String;", 145},
   Sig{"java/util/Properties", "load", "(Ljava/io/Reader;)V", 209},
   Sig{"java/util/Properties", "getProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;", 208},
   Sig{"java/util/Properties", "setProperty", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;", 146},
   Sig{"java/lang/Boolean", "valueOf", "(Z)Ljava/lang/Boolean;", 147},
   Sig{"java/lang/Boolean", "booleanValue", "()Z", 148},
   Sig{"java/lang/Boolean", "toString", "()Ljava/lang/String;", 149},
   Sig{"java/lang/Enum", "<init>", "(Ljava/lang/String;I)V", 150},
   Sig{"java/lang/Enum", "name", "()Ljava/lang/String;", 151},
   Sig{"java/lang/Enum", "ordinal", "()I", 152},
   Sig{"java/lang/Enum", "valueOf", "(Ljava/lang/Class;Ljava/lang/String;)Ljava/lang/Enum;", 153},
   Sig{"java/net/URL", "getPath", "()Ljava/lang/String;", 142},
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
   Sig{"java/lang/Error", "toString", "()Ljava/lang/String;", 114},
   Sig{"java/lang/Class", "getResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;", 171},
   Sig{"java/lang/Class", "getResource", "(Ljava/lang/String;)Ljava/net/URL;", 172},
   Sig{"java/lang/Class", "getClassLoader", "()Ljava/lang/ClassLoader;", 173},
   Sig{"java/lang/ClassLoader", "getResourceAsStream", "(Ljava/lang/String;)Ljava/io/InputStream;", 174},
   Sig{"java/lang/ClassLoader", "getResource", "(Ljava/lang/String;)Ljava/net/URL;", 175},
   Sig{"java/net/URL", "getProtocol", "()Ljava/lang/String;", 176},
   Sig{"java/net/URL", "toExternalForm", "()Ljava/lang/String;", 177},
   Sig{"java/net/URL", "toString", "()Ljava/lang/String;", 178},
   Sig{"java/lang/reflect/Field", "get", "(Ljava/lang/Object;)Ljava/lang/Object;", 179},
   Sig{"java/lang/reflect/Field", "set", "(Ljava/lang/Object;Ljava/lang/Object;)V", 180},
   Sig{"java/lang/reflect/Field", "getInt", "(Ljava/lang/Object;)I", 181},
   Sig{"java/lang/reflect/Field", "setInt", "(Ljava/lang/Object;I)V", 182},
   Sig{"java/lang/reflect/Method", "invoke", "(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;", 183},
   Sig{"java/lang/reflect/Constructor", "newInstance", "([Ljava/lang/Object;)Ljava/lang/Object;", 184},
   Sig{"java/lang/Class", "getDeclaredField", "(Ljava/lang/String;)Ljava/lang/reflect/Field;", 186},
   Sig{"java/lang/Class", "getDeclaredMethod", "(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;", 187},
   Sig{"java/lang/Class", "getDeclaredConstructor", "([Ljava/lang/Class;)Ljava/lang/reflect/Constructor;", 188},
   Sig{"java/lang/reflect/AccessibleObject", "setAccessible", "(Z)V", 192},
   Sig{"java/lang/reflect/AccessibleObject", "isAccessible", "()Z", 193},
   Sig{"java/lang/Class", "getFields", "()[Ljava/lang/reflect/Field;", 194},
   Sig{"java/lang/Class", "getMethods", "()[Ljava/lang/reflect/Method;", 195},
   Sig{"java/lang/Class", "getConstructors", "()[Ljava/lang/reflect/Constructor;", 196},
   Sig{"java/lang/Class", "getField", "(Ljava/lang/String;)Ljava/lang/reflect/Field;", 197},
   Sig{"java/lang/Class", "getMethod", "(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;", 198},
   Sig{"java/lang/Class", "getConstructor", "([Ljava/lang/Class;)Ljava/lang/reflect/Constructor;", 199},
   Sig{"java/lang/ClassLoader", "getSystemResources", "(Ljava/lang/String;)Ljava/util/Enumeration;", 202},
   Sig{"java/lang/ClassLoader", "getResources", "(Ljava/lang/String;)Ljava/util/Enumeration;", 203},
   Sig{"java/util/ResourceEnumeration", "hasMoreElements", "()Z", 204},
   Sig{"java/util/ResourceEnumeration", "nextElement", "()Ljava/lang/Object;", 205},
   Sig{"java/util/Enumeration", "hasMoreElements", "()Z", 206},
   Sig{"java/util/Enumeration", "nextElement", "()Ljava/lang/Object;", 207},
   Sig{"java/lang/Class", "isAnnotationPresent", "(Ljava/lang/Class;)Z", 210},
   Sig{"java/lang/Class", "getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 215},
   Sig{"java/lang/Class", "getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 216},
   Sig{"java/lang/Class", "getAnnotations", "()[Ljava/lang/annotation/Annotation;", 217},
   Sig{"java/lang/Class", "getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;", 218},
   Sig{"java/lang/reflect/Field", "isAnnotationPresent", "(Ljava/lang/Class;)Z", 219},
   Sig{"java/lang/reflect/Field", "getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 220},
   Sig{"java/lang/reflect/Field", "getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 221},
   Sig{"java/lang/reflect/Field", "getAnnotations", "()[Ljava/lang/annotation/Annotation;", 222},
   Sig{"java/lang/reflect/Field", "getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;", 223},
   Sig{"java/lang/reflect/Method", "isAnnotationPresent", "(Ljava/lang/Class;)Z", 224},
   Sig{"java/lang/reflect/Method", "getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 225},
   Sig{"java/lang/reflect/Method", "getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 226},
   Sig{"java/lang/reflect/Method", "getAnnotations", "()[Ljava/lang/annotation/Annotation;", 227},
   Sig{"java/lang/reflect/Method", "getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;", 228},
   Sig{"java/lang/reflect/Method", "getParameterAnnotations", "()[[Ljava/lang/annotation/Annotation;", 229},
   Sig{"java/lang/reflect/Method", "getDefaultValue", "()Ljava/lang/Object;", 230},
   Sig{"java/lang/reflect/Constructor", "isAnnotationPresent", "(Ljava/lang/Class;)Z", 231},
   Sig{"java/lang/reflect/Constructor", "getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 232},
   Sig{"java/lang/reflect/Constructor", "getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 233},
   Sig{"java/lang/reflect/Constructor", "getAnnotations", "()[Ljava/lang/annotation/Annotation;", 234},
   Sig{"java/lang/reflect/Constructor", "getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;", 235},
   Sig{"java/lang/reflect/Constructor", "getParameterAnnotations", "()[[Ljava/lang/annotation/Annotation;", 236},
   Sig{"java/lang/reflect/Method", "getAnnotatedParameterTypes", "()[Ljava/lang/reflect/AnnotatedType;", 237},
   Sig{"java/lang/reflect/Method", "getAnnotatedReturnType", "()Ljava/lang/reflect/AnnotatedType;", 238},
   Sig{"java/lang/reflect/AnnotatedType", "isAnnotationPresent", "(Ljava/lang/Class;)Z", 239},
   Sig{"java/lang/reflect/AnnotatedType", "getAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 240},
   Sig{"java/lang/reflect/AnnotatedType", "getDeclaredAnnotation", "(Ljava/lang/Class;)Ljava/lang/annotation/Annotation;", 241},
   Sig{"java/lang/reflect/AnnotatedType", "getAnnotations", "()[Ljava/lang/annotation/Annotation;", 242},
   Sig{"java/lang/reflect/AnnotatedType", "getDeclaredAnnotations", "()[Ljava/lang/annotation/Annotation;", 243},
   Sig{"java/lang/reflect/Method", "getExceptionTypes", "()[Ljava/lang/Class;", 244},
   Sig{"java/lang/reflect/Proxy", "newProxyInstance", "(Ljava/lang/ClassLoader;[Ljava/lang/Class;Ljava/lang/reflect/InvocationHandler;)Ljava/lang/Object;", 245},
   Sig{"java/lang/reflect/Proxy", "getProxyClass", "(Ljava/lang/ClassLoader;[Ljava/lang/Class;)Ljava/lang/Class;", 246},
   Sig{"java/lang/reflect/Proxy", "isProxyClass", "(Ljava/lang/Class;)Z", 247},
   Sig{"java/lang/reflect/Proxy", "getInvocationHandler", "(Ljava/lang/Object;)Ljava/lang/reflect/InvocationHandler;", 248},
   Sig{"java/lang/Class", "forName", "(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;", 250},
   Sig{"java/lang/reflect/Field", "isSynthetic", "()Z", 251},
   Sig{"java/lang/reflect/Field", "isEnumConstant", "()Z", 252},
   Sig{"java/lang/reflect/Method", "isBridge", "()Z", 253},
   Sig{"java/lang/reflect/Method", "isSynthetic", "()Z", 254},
   Sig{"java/lang/reflect/Method", "isVarArgs", "()Z", 255},
   Sig{"java/lang/reflect/Constructor", "getExceptionTypes", "()[Ljava/lang/Class;", 256},
   Sig{"java/lang/reflect/Constructor", "isSynthetic", "()Z", 257},
   Sig{"java/lang/reflect/Constructor", "isVarArgs", "()Z", 258},
   Sig{"java/lang/reflect/Field", "equals", "(Ljava/lang/Object;)Z", 259},
   Sig{"java/lang/reflect/Field", "hashCode", "()I", 260},
   Sig{"java/lang/reflect/Method", "equals", "(Ljava/lang/Object;)Z", 261},
   Sig{"java/lang/reflect/Method", "hashCode", "()I", 262},
   Sig{"java/lang/reflect/Constructor", "equals", "(Ljava/lang/Object;)Z", 263},
   Sig{"java/lang/reflect/Constructor", "hashCode", "()I", 264},
   Sig{"java/lang/Class", "getAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;", 265},
   Sig{"java/lang/Class", "getDeclaredAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;", 266},
   Sig{"java/lang/reflect/Field", "getAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;", 267},
   Sig{"java/lang/reflect/Field", "getDeclaredAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;", 268},
   Sig{"java/lang/reflect/Method", "getAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;", 269},
   Sig{"java/lang/reflect/Method", "getDeclaredAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;", 270},
   Sig{"java/lang/reflect/Constructor", "getAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;", 271},
   Sig{"java/lang/reflect/Constructor", "getDeclaredAnnotationsByType", "(Ljava/lang/Class;)[Ljava/lang/annotation/Annotation;", 272}]

def throwable_inherited(+owner: String, +name: String, +desc: String) -> U32:
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "getMessage") && String.eq(desc, "()Ljava/lang/String;"), 109,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "getCause") && String.eq(desc, "()Ljava/lang/Throwable;"), 110,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "initCause") && String.eq(desc, "(Ljava/lang/Throwable;)Ljava/lang/Throwable;"), 111,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "addSuppressed") && String.eq(desc, "(Ljava/lang/Throwable;)V"), 112,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "getSuppressed") && String.eq(desc, "()[Ljava/lang/Throwable;"), 113,
  Bool.pick(U32, is_throwable(owner) && String.eq(name, "toString") && String.eq(desc, "()Ljava/lang/String;"), 114,
  Bool.pick(U32, String.eq(owner, "java/lang/reflect/UndeclaredThrowableException") && String.eq(name, "getUndeclaredThrowable") && String.eq(desc, "()Ljava/lang/Throwable;"), 273,
  0)))))))

def intrinsic_desc(+owner: String, +name: String, +desc: String) -> U32:
  +found = sig_id(signatures(), owner, name, desc)
  Bool.pick(U32, U32.is_ne(found, 0), found,
    Bool.pick(U32, String.eq(name, "<init>"), ctor_id(owner, desc), throwable_inherited(owner, name, desc)))
