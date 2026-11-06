import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.lang.annotation.Annotation;
import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;

// User class loaders: parent delegation, findClass/defineClass, loader identity,
// and one binary name defined independently by two loaders. The isolated classes
// are on the class path only as "*.bytes" resources, so only these loaders see them.
public class ClassLoaders {
    static class ByteLoader extends ClassLoader {
        int found;

        ByteLoader(ClassLoader parent) {
            super(parent);
        }

        protected Class<?> findClass(String name) throws ClassNotFoundException {
            byte[] bytes = read(name.replace('.', '/') + ".bytes");
            if (bytes == null) {
                throw new ClassNotFoundException(name);
            }
            found++;
            return defineClass(name, bytes, 0, bytes.length);
        }

        Class<?> define(String name, byte[] bytes) {
            return defineClass(name, bytes, 0, bytes.length);
        }

        Class<?> loaded(String name) {
            return findLoadedClass(name);
        }
    }

    // Child-first: defines isolated classes itself and delegates the rest.
    static class ChildFirstLoader extends ByteLoader {
        ChildFirstLoader(ClassLoader parent) {
            super(parent);
        }

        protected Class<?> loadClass(String name, boolean resolve) throws ClassNotFoundException {
            Class<?> loaded = findLoadedClass(name);
            if (loaded == null && name.startsWith("isolated.")) {
                loaded = findClass(name);
            }
            return loaded != null ? loaded : super.loadClass(name, resolve);
        }
    }

    static byte[] read(String resource) {
        try {
            InputStream stream = ClassLoaders.class.getClassLoader().getResourceAsStream(resource);
            if (stream == null) {
                return null;
            }
            ByteArrayOutputStream buffer = new ByteArrayOutputStream();
            int next;
            while ((next = stream.read()) >= 0) {
                buffer.write(next);
            }
            stream.close();
            return buffer.toByteArray();
        } catch (Exception error) {
            return null;
        }
    }

    @SuppressWarnings("unchecked")
    static Class<? extends Annotation> annotation(Class<?> type) {
        return (Class<? extends Annotation>) type;
    }

    public static void main(String[] args) throws Exception {
        ClassLoader system = ClassLoader.getSystemClassLoader();
        System.out.println(ClassLoaders.class.getClassLoader() == system);
        System.out.println(String.class.getClassLoader() == null);

        ByteLoader first = new ByteLoader(system);
        System.out.println(first.getParent() == system);
        System.out.println(first.loaded("isolated.Payload") == null);
        Class<?> payload = first.loadClass("isolated.Payload");
        System.out.println(payload.getName() + " " + (payload.getClassLoader() == first));
        System.out.println(first.loaded("isolated.Payload") == payload);
        System.out.println(first.loadClass("isolated.Payload") == payload);
        Object instance = payload.newInstance();
        System.out.println(payload.getMethod("run").invoke(instance));
        // JVMS 5.4 lets a VM load referenced classes eagerly, so findClass counts
        // are compared only once run() has used Helper (HotSpot loads it lazily).
        System.out.println("found " + first.found);
        System.out.println(payload.getMethod("loader").invoke(instance) == first);
        Class<?> helper = first.loadClass("isolated.Helper");
        System.out.println(helper.getClassLoader() == first);
        System.out.println(first.loadClass("java.lang.String") == String.class);
        System.out.println(first.loadClass("ClassLoaders") == ClassLoaders.class);
        System.out.println(Class.forName("isolated.Payload", false, first) == payload);
        try {
            Class.forName("isolated.Payload");
            System.out.println("visible to the application loader");
        } catch (ClassNotFoundException expected) {
            System.out.println("hidden from the application loader: " + expected.getMessage());
        }
        try {
            first.loadClass("isolated.Missing");
        } catch (ClassNotFoundException expected) {
            System.out.println("missing: " + expected.getMessage());
        }

        ByteLoader second = new ByteLoader(system);
        Class<?> again = second.loadClass("isolated.Payload");
        System.out.println(again != payload);
        System.out.println(again.getName().equals(payload.getName()));
        System.out.println(again.isInstance(instance) + " " + payload.isInstance(instance));
        Object other = again.newInstance();
        System.out.println(again.getMethod("run").invoke(other));
        System.out.println(payload.getField("initialized").getInt(null) + " " + again.getField("initialized").getInt(null));

        ChildFirstLoader child = new ChildFirstLoader(first);
        Class<?> own = child.loadClass("isolated.Payload");
        System.out.println(own != payload && own.getClassLoader() == child);
        System.out.println(child.loadClass("ClassLoaders") == ClassLoaders.class);

        byte[] bytes = read("isolated/Payload.bytes");
        try {
            new ByteLoader(system).define("isolated.Other", bytes);
        } catch (NoClassDefFoundError expected) {
            System.out.println("wrong name: " + expected.getMessage());
        }
        try {
            first.define("isolated.Payload", bytes);
        } catch (LinkageError expected) {
            System.out.println("duplicate: " + expected.getClass().getName());
        }
        try {
            new ByteLoader(system).define("java.lang.Payload", bytes);
        } catch (SecurityException expected) {
            System.out.println("prohibited: " + expected.getMessage());
        }
        byte[] broken = bytes.clone();
        broken[0] = 0;
        try {
            new ByteLoader(system).define("isolated.Payload", broken);
        } catch (ClassFormatError expected) {
            System.out.println("format: " + expected.getClass().getName());
        }

        // Deserialization in isolated code resolves stream classes through its
        // defining loader (latestUserDefinedLoader), loading them if needed.
        Class<?> serial = first.loadClass("isolated.Serial");
        System.out.println(serial.getMethod("roundTrip").invoke(null));
        System.out.println(second.loadClass("isolated.Serial").getMethod("roundTrip").invoke(null));
        byte[] boxed = (byte[]) serial.getMethod("boxBytes").invoke(null);
        ByteLoader third = new ByteLoader(system);
        Object fresh = third.loadClass("isolated.Reader").getMethod("read", byte[].class).invoke(null, (Object) boxed);
        System.out.println(fresh.getClass().getName() + " " + (fresh.getClass().getClassLoader() == third));

        // A second definition keeps its annotations and generic signatures in
        // its own namespace.
        Class<?> box = first.loadClass("isolated.Box");
        Class<?> boxAgain = second.loadClass("isolated.Box");
        Class<? extends Annotation> tag = annotation(first.loadClass("isolated.Tag"));
        Class<? extends Annotation> tagAgain = annotation(second.loadClass("isolated.Tag"));
        System.out.println(box.isAnnotationPresent(tag) + " " + boxAgain.isAnnotationPresent(tagAgain) + " " + boxAgain.isAnnotationPresent(tag));
        Type argument = ((ParameterizedType) boxAgain.getField("helpers").getGenericType()).getActualTypeArguments()[0];
        System.out.println((argument == second.loadClass("isolated.Helper")) + " " + (argument == helper));
    }
}
