import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.ObjectInputStream;
import java.io.ObjectOutputStream;
import java.io.Serializable;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.function.Supplier;

// Java serialization: the stream bytes must match the JDK's, and objects,
// classes, enums, arrays, back references, proxies and lambdas round-trip.
public class SerializationStreams {
    enum Color { RED, GREEN }

    static class Point implements Serializable {
        private static final long serialVersionUID = 7L;
        int x;
        transient int skipped = 5;
        String label;
        Point next;
        Color color = Color.GREEN;
    }

    // No serialVersionUID: the stream carries the computed default.
    static class Computed implements Serializable {
        long total = 9L;
        double ratio = 0.5;
        boolean flag = true;
        char letter = 'q';
        int[] numbers = {1, 2};
        String[] names = {"a", null};
    }

    static class Custom implements Serializable {
        private static final long serialVersionUID = 1L;
        transient String secret = "s";

        private void writeObject(ObjectOutputStream out) throws IOException {
            out.defaultWriteObject();
            out.writeUTF("extra " + secret);
            out.writeInt(3);
        }

        private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
            in.defaultReadObject();
            secret = in.readUTF() + " " + in.readInt();
        }
    }

    static final class Singleton implements Serializable {
        private static final long serialVersionUID = 2L;
        static final Singleton INSTANCE = new Singleton();

        private Object readResolve() {
            return INSTANCE;
        }
    }

    public interface Named {
        String name();
    }

    static class Handler implements InvocationHandler, Serializable {
        private static final long serialVersionUID = 3L;
        String value = "proxied";

        public Object invoke(Object proxy, Method method, Object[] args) {
            return value;
        }
    }

    static byte[] write(Object value) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        ObjectOutputStream out = new ObjectOutputStream(bytes);
        out.writeObject(value);
        out.close();
        return bytes.toByteArray();
    }

    static Object read(byte[] bytes) throws IOException, ClassNotFoundException {
        ObjectInputStream in = new ObjectInputStream(new ByteArrayInputStream(bytes));
        Object value = in.readObject();
        in.close();
        return value;
    }

    static String hex(byte[] bytes) {
        StringBuilder text = new StringBuilder();
        for (byte value : bytes) {
            String digits = Integer.toHexString(value & 0xff);
            text.append(digits.length() == 1 ? "0" + digits : digits);
        }
        return text.toString();
    }

    public static void main(String[] args) throws Exception {
        Point first = new Point();
        first.x = 3;
        first.label = "origin";
        Point second = new Point();
        second.x = 4;
        second.next = first;
        first.next = second;
        byte[] points = write(first);
        System.out.println(hex(points));
        Point copy = (Point) read(points);
        System.out.println(copy.x + " " + copy.label + " " + copy.skipped + " " + copy.next.x + " " + (copy.next.next == copy) + " " + copy.color);

        byte[] computed = write(new Computed());
        System.out.println(hex(computed));
        Computed computedCopy = (Computed) read(computed);
        System.out.println(computedCopy.total + " " + computedCopy.ratio + " " + computedCopy.flag + " " + computedCopy.letter + " " + computedCopy.numbers[1] + " " + computedCopy.names[0] + computedCopy.names[1]);

        byte[] custom = write(new Custom());
        System.out.println(hex(custom));
        System.out.println(((Custom) read(custom)).secret);

        System.out.println(read(write(Singleton.INSTANCE)) == Singleton.INSTANCE);
        System.out.println(hex(write(String.class)) + " " + (read(write(int[].class)) == int[].class));
        System.out.println(hex(write(Color.RED)) + " " + (read(write(Color.RED)) == Color.RED));
        System.out.println(hex(write(new Object[] {"x", 1, null})));

        Named proxy = (Named) Proxy.newProxyInstance(Named.class.getClassLoader(), new Class<?>[] {Named.class}, new Handler());
        byte[] proxied = write(proxy);
        System.out.println(hex(proxied));
        System.out.println(((Named) read(proxied)).name());

        Supplier<String> lambda = (Supplier<String> & Serializable) () -> "lambda " + first.label;
        Object lambdaCopy = read(write(lambda));
        System.out.println(((Supplier<?>) lambdaCopy).get());
    }
}
