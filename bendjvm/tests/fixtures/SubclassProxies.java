import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.List;

// Runtime-generated subclasses, as CGLIB and ByteBuddy build them: class bytes
// written at run time, defined through a class loader, overriding methods of a
// user class and calling super.
public class SubclassProxies {
    public interface Marker {
        String tag();
    }

    public static class Service {
        protected int calls;

        public String greet(String name) {
            calls++;
            return "hello " + name;
        }

        public int count() {
            return calls;
        }
    }

    static class DefiningLoader extends ClassLoader {
        DefiningLoader(ClassLoader parent) {
            super(parent);
        }

        Class<?> define(String name, byte[] bytes) {
            return defineClass(name, bytes, 0, bytes.length);
        }
    }

    // A minimal class file writer over a byte buffer, as ASM's ByteVector:
    // constant pool, one class, straight-line methods.
    static void u1(ByteArrayOutputStream out, int value) {
        out.write(value & 0xff);
    }

    static void u2(ByteArrayOutputStream out, int value) {
        out.write((value >> 8) & 0xff);
        out.write(value & 0xff);
    }

    static void u4(ByteArrayOutputStream out, int value) {
        u2(out, value >>> 16);
        u2(out, value);
    }

    static final class Writer {
        final List<byte[]> pool = new ArrayList<byte[]>();
        final ByteArrayOutputStream methods = new ByteArrayOutputStream();
        int methodCount;

        int add(byte[] entry) {
            for (int i = 0; i < pool.size(); i++) {
                if (same(pool.get(i), entry)) {
                    return i + 1;
                }
            }
            pool.add(entry);
            return pool.size();
        }

        static boolean same(byte[] left, byte[] right) {
            if (left.length != right.length) {
                return false;
            }
            for (int i = 0; i < left.length; i++) {
                if (left[i] != right[i]) {
                    return false;
                }
            }
            return true;
        }

        // ASCII text: its modified UTF-8 form is the characters themselves.
        int utf(String text) throws IOException {
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            u1(buffer, 1);
            u2(buffer, text.length());
            for (int i = 0; i < text.length(); i++) {
                u1(buffer, text.charAt(i));
            }
            return add(buffer.toByteArray());
        }

        int ref(int tag, int first, int second) {
            return add(new byte[] {(byte) tag, (byte) (first >> 8), (byte) first, (byte) (second >> 8), (byte) second});
        }

        int single(int tag, int index) {
            return add(new byte[] {(byte) tag, (byte) (index >> 8), (byte) index});
        }

        int type(String name) throws IOException {
            return single(7, utf(name));
        }

        int string(String text) throws IOException {
            return single(8, utf(text));
        }

        int member(int tag, String owner, String name, String descriptor) throws IOException {
            return ref(tag, type(owner), ref(12, utf(name), utf(descriptor)));
        }

        void method(int flags, String name, String descriptor, int stack, int locals, byte[] code) throws IOException {
            ByteArrayOutputStream out = methods;
            u2(out, flags);
            u2(out, utf(name));
            u2(out, utf(descriptor));
            u2(out, 1);
            u2(out, utf("Code"));
            u4(out, 12 + code.length);
            u2(out, stack);
            u2(out, locals);
            u4(out, code.length);
            out.write(code, 0, code.length);
            u2(out, 0);
            u2(out, 0);
            methodCount++;
        }

        byte[] finish(String name, String parent, String[] interfaces) throws IOException {
            int self = type(name);
            int superclass = type(parent);
            int[] implemented = new int[interfaces.length];
            for (int i = 0; i < interfaces.length; i++) {
                implemented[i] = type(interfaces[i]);
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            u4(out, 0xCAFEBABE);
            u2(out, 0);
            u2(out, 52);
            u2(out, pool.size() + 1);
            for (byte[] entry : pool) {
                out.write(entry, 0, entry.length);
            }
            u2(out, 0x0021);
            u2(out, self);
            u2(out, superclass);
            u2(out, interfaces.length);
            for (int index : implemented) {
                u2(out, index);
            }
            u2(out, 0);
            u2(out, methodCount);
            byte[] body = methods.toByteArray();
            out.write(body, 0, body.length);
            u2(out, 0);
            return out.toByteArray();
        }
    }

    static byte[] u2(int value) {
        return new byte[] {(byte) (value >> 8), (byte) value};
    }

    static byte[] code(Object... parts) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (Object part : parts) {
            if (part instanceof byte[]) {
                byte[] bytes = (byte[]) part;
                out.write(bytes, 0, bytes.length);
            } else {
                out.write(((Integer) part).intValue());
            }
        }
        return out.toByteArray();
    }

    static byte[] subclass(String name, boolean broken) throws IOException {
        String parent = "SubclassProxies$Service";
        Writer writer = new Writer();
        int superInit = writer.member(10, parent, "<init>", "()V");
        writer.method(1, "<init>", "()V", 1, 1, code(0x2a, 0xb7, u2(superInit), 0xb1));
        int builder = writer.type("java/lang/StringBuilder");
        int builderInit = writer.member(10, "java/lang/StringBuilder", "<init>", "()V");
        int append = writer.member(10, "java/lang/StringBuilder", "append", "(Ljava/lang/String;)Ljava/lang/StringBuilder;");
        int toText = writer.member(10, "java/lang/StringBuilder", "toString", "()Ljava/lang/String;");
        int superGreet = writer.member(10, parent, "greet", "(Ljava/lang/String;)Ljava/lang/String;");
        int open = writer.string("[");
        int close = writer.string("]");
        writer.method(1, "greet", "(Ljava/lang/String;)Ljava/lang/String;", 3, 2, code(
            0xbb, u2(builder), 0x59, 0xb7, u2(builderInit),
            0x13, u2(open), 0xb6, u2(append),
            0x2a, 0x2b, 0xb7, u2(superGreet), 0xb6, u2(append),
            0x13, u2(close), 0xb6, u2(append),
            0xb6, u2(toText), 0xb0));
        int superCount = writer.member(10, parent, "count", "()I");
        writer.method(1, "count", "()I", 2, 1, broken
            ? code(0x60, 0xac)
            : code(0x2a, 0xb7, u2(superCount), 0x10, 100, 0x60, 0xac));
        int calls = writer.member(9, parent, "calls", "I");
        int tagText = writer.string("generated");
        writer.method(1, "tag", "()Ljava/lang/String;", 1, 1, code(0x13, u2(tagText), 0xb0));
        writer.method(1, "calls", "()I", 1, 1, code(0x2a, 0xb4, u2(calls), 0xac));
        return writer.finish(name, parent, new String[] {"SubclassProxies$Marker"});
    }

    public static void main(String[] args) throws Exception {
        DefiningLoader loader = new DefiningLoader(SubclassProxies.class.getClassLoader());
        Class<?> generated = loader.define("Service$$Generated", subclass("Service$$Generated", false));
        System.out.println(generated.getName() + " extends " + generated.getSuperclass().getName());
        System.out.println(generated.getClassLoader() == loader);
        System.out.println(Service.class.isAssignableFrom(generated) + " " + Marker.class.isAssignableFrom(generated));
        Service service = (Service) generated.newInstance();
        System.out.println(service.greet("world"));
        System.out.println(service.greet("again"));
        System.out.println(service.count());
        System.out.println(((Marker) service).tag());
        System.out.println(generated.getMethod("calls").invoke(service));
        List<String> names = new ArrayList<String>();
        for (Method method : generated.getDeclaredMethods()) {
            String text = method.getName() + ":" + method.getReturnType().getSimpleName();
            int index = 0;
            while (index < names.size() && names.get(index).compareTo(text) < 0) {
                index++;
            }
            names.add(index, text);
        }
        System.out.println(names);
        Method greet = Service.class.getMethod("greet", String.class);
        System.out.println(greet.invoke(service, "reflected"));

        Class<?> broken = new DefiningLoader(SubclassProxies.class.getClassLoader()).define("Service$$Broken", subclass("Service$$Broken", true));
        System.out.println("defined " + broken.getName());
        try {
            broken.newInstance();
            System.out.println("verified");
        } catch (VerifyError expected) {
            System.out.println("verify error at first use");
        }
    }
}
