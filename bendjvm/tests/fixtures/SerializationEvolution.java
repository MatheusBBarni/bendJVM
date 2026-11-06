import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.Externalizable;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.ObjectInput;
import java.io.ObjectInputStream;
import java.io.ObjectOutput;
import java.io.ObjectOutputStream;
import java.io.Serializable;

// Serialization beyond the basics: Externalizable, unshared objects, reset,
// class evolution (fields matched by name, missing and extra classes), any
// InputStream as a source, stream classes loaded on demand, and the
// DataInput/DataOutput methods of the object streams.
public class SerializationEvolution {
    public static class Ext implements Externalizable {
        private static final long serialVersionUID = 5L;
        int count;
        String name;
        Object child;

        public Ext() {
            System.out.println("Ext()");
        }

        Ext(int count, String name, Object child) {
            this.count = count;
            this.name = name;
            this.child = child;
        }

        public void writeExternal(ObjectOutput out) throws IOException {
            out.writeInt(count);
            out.writeUTF(name);
            out.writeObject(child);
        }

        public void readExternal(ObjectInput in) throws IOException, ClassNotFoundException {
            count = in.readInt();
            name = in.readUTF();
            child = in.readObject();
        }
    }

    // Serializable, with the same serialVersionUID as Ext.
    static class Sxt implements Serializable {
        private static final long serialVersionUID = 5L;
    }

    // Externalizable without a public no-arg constructor.
    static class Hidden implements Externalizable {
        private static final long serialVersionUID = 1L;

        Hidden() {
        }

        public void writeExternal(ObjectOutput out) {
        }

        public void readExternal(ObjectInput in) {
        }
    }

    static class Item implements Serializable {
        private static final long serialVersionUID = 2L;
        int id;

        Item(int id) {
            this.id = id;
        }
    }

    static class Resetting implements Serializable {
        private static final long serialVersionUID = 4L;

        private void writeObject(ObjectOutputStream out) throws IOException {
            try {
                out.reset();
            } catch (IOException e) {
                System.out.println("reset: " + e.getMessage());
            }
            out.defaultWriteObject();
        }
    }

    static class BaseA implements Serializable {
        private static final long serialVersionUID = 8L;
        int base = 3;
    }

    static class EvoA extends BaseA {
        private static final long serialVersionUID = 7L;
        int count = 4;
        String gone = "g";
        long stamp = 99L;
    }

    static class BaseB implements Serializable {
        private static final long serialVersionUID = 9L;
        int other = 6;

        private void readObjectNoData() {
            other = -1;
            System.out.println("BaseB.readObjectNoData");
        }
    }

    // EvoA's stream read as EvoB: count and stamp match by name, gone is
    // dropped, added stays null, BaseA's data is skipped, and BaseB has none.
    static class EvoB extends BaseB {
        private static final long serialVersionUID = 7L;
        long stamp;
        String added = "default";
        int count;
    }

    static class EvoC implements Serializable {
        private static final long serialVersionUID = 7L;
        long count;
    }

    // Overrides only read(): the stream is read one byte at a time.
    static class OneByOne extends InputStream {
        private final byte[] data;
        private int at;

        OneByOne(byte[] data) {
            this.data = data;
        }

        public int read() {
            return at < data.length ? data[at++] & 0xff : -1;
        }
    }

    // read(byte[], int, int) returns at most three bytes per call.
    static class Chunks extends InputStream {
        private final byte[] data;
        private int at;

        Chunks(byte[] data) {
            this.data = data;
        }

        public int read() {
            return at < data.length ? data[at++] & 0xff : -1;
        }

        public int read(byte[] buffer, int offset, int length) {
            if (at >= data.length) {
                return -1;
            }
            int count = 0;
            while (count < length && count < 3 && at < data.length) {
                buffer[offset + count] = data[at];
                at++;
                count++;
            }
            return count;
        }
    }

    // An EvolutionLazy instance as the JDK writes it; no constant of this
    // class names EvolutionLazy, so reading it loads the class.
    static final String LAZY = "aced00057372000d45766f6c7574696f6e4c617a79000000000000000302000149000576616c756578700000000b";

    static String hex(byte[] bytes) {
        StringBuilder text = new StringBuilder();
        for (byte value : bytes) {
            String digits = Integer.toHexString(value & 0xff);
            text.append(digits.length() == 1 ? "0" + digits : digits);
        }
        return text.toString();
    }

    static byte[] unhex(String text) {
        byte[] bytes = new byte[text.length() / 2];
        for (int i = 0; i < bytes.length; i++) {
            bytes[i] = (byte) Integer.parseInt(text.substring(2 * i, 2 * i + 2), 16);
        }
        return bytes;
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
        return in.readObject();
    }

    // Replaces each occurrence of `from` by `to` (same length) in the stream.
    static byte[] rename(byte[] bytes, String from, String to) {
        byte[] result = bytes.clone();
        for (int i = 0; i + from.length() <= result.length; i++) {
            boolean match = true;
            for (int j = 0; j < from.length(); j++) {
                if (result[i + j] != (byte) from.charAt(j)) {
                    match = false;
                    break;
                }
            }
            if (match) {
                for (int j = 0; j < to.length(); j++) {
                    result[i + j] = (byte) to.charAt(j);
                }
            }
        }
        return result;
    }

    static void failure(String label, Throwable e) {
        System.out.println(label + ": " + e.getClass().getName() + ": " + e.getMessage());
    }

    public static void main(String[] args) throws Exception {
        // Externalizable: the public constructor runs, then readExternal.
        byte[] external = write(new Ext(7, "box", "inner"));
        System.out.println("external " + hex(external));
        Ext ext = (Ext) read(external);
        System.out.println("ext " + ext.count + " " + ext.name + " " + ext.child);
        try {
            read(write(new Hidden()));
        } catch (Exception e) {
            failure("hidden", e);
        }
        try {
            read(rename(external, "$Ext", "$Sxt"));
        } catch (Exception e) {
            failure("sxt", e);
        }

        // writeUnshared/readUnshared.
        Item item = new Item(1);
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        ObjectOutputStream out = new ObjectOutputStream(bytes);
        out.writeUnshared(item);
        out.writeObject(item);
        out.writeObject(item);
        out.close();
        System.out.println("unshared " + hex(bytes.toByteArray()));
        ObjectInputStream in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()));
        Object a = in.readUnshared();
        Object b = in.readObject();
        Object c = in.readObject();
        System.out.println("unshared " + (a != b) + " " + (b == c) + " " + ((Item) a).id);

        bytes = new ByteArrayOutputStream();
        out = new ObjectOutputStream(bytes);
        out.writeObject(item);
        out.writeObject(item);
        out.close();
        in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()));
        in.readUnshared();
        try {
            in.readObject();
        } catch (Exception e) {
            failure("back reference", e);
        }
        in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()));
        in.readObject();
        try {
            in.readUnshared();
        } catch (Exception e) {
            failure("unshared reference", e);
        }

        // reset: the second write describes the object again.
        bytes = new ByteArrayOutputStream();
        out = new ObjectOutputStream(bytes);
        out.writeObject(item);
        out.writeInt(5);
        out.reset();
        out.writeObject(item);
        out.writeObject(new Resetting());
        out.close();
        System.out.println("reset " + hex(bytes.toByteArray()));
        in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()));
        Object first = in.readObject();
        int five = in.readInt();
        Object second = in.readObject();
        System.out.println("reset " + (first != second) + " " + five + " " + ((Item) second).id + " " + in.readObject().getClass().getName());

        // Class evolution.
        byte[] evolved = write(new EvoA());
        EvoB evo = (EvoB) read(rename(evolved, "$EvoA", "$EvoB"));
        System.out.println("evolved " + evo.count + " " + evo.stamp + " " + evo.added + " " + evo.other);
        try {
            read(rename(evolved, "$EvoA", "$EvoC"));
        } catch (Exception e) {
            failure("evoc", e);
        }

        // Any InputStream: the object stream reads exactly what it needs.
        bytes = new ByteArrayOutputStream();
        out = new ObjectOutputStream(bytes);
        out.writeObject(new Ext(3, "chunked", null));
        out.writeInt(77);
        out.writeObject("tail");
        out.close();
        bytes.write(42);
        byte[] payload = bytes.toByteArray();
        InputStream[] sources = {new OneByOne(payload), new Chunks(payload), new ByteArrayInputStream(payload)};
        for (InputStream source : sources) {
            in = new ObjectInputStream(source);
            Ext read = (Ext) in.readObject();
            System.out.println("source " + read.name + " " + in.readInt() + " " + in.readObject() + " " + source.read());
        }

        // A file: its read() is a host call made while readObject runs.
        FileOutputStream file = new FileOutputStream("serialization-evolution.bin");
        file.write(payload);
        file.close();
        FileInputStream opened = new FileInputStream("serialization-evolution.bin");
        in = new ObjectInputStream(opened);
        Ext fromFile = (Ext) in.readObject();
        System.out.println("file " + fromFile.name + " " + in.readInt() + " " + in.readObject() + " " + opened.read());
        in.close();

        // A stream class nothing loaded yet.
        Object lazy = read(unhex(LAZY));
        System.out.println("lazy " + lazy.getClass().getName() + " " + lazy.getClass().getDeclaredField("value").getInt(lazy));

        // DataOutput/DataInput methods.
        bytes = new ByteArrayOutputStream();
        out = new ObjectOutputStream(bytes);
        out.write(new byte[] {1, 2, 3, 4, 5});
        out.writeBytes("AB");
        out.writeChars("C");
        out.close();
        System.out.println("data " + hex(bytes.toByteArray()));
        in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()));
        byte[] buffer = new byte[4];
        System.out.println("available " + in.available());
        System.out.println("read " + in.read(buffer, 1, 2) + " " + buffer[1] + " " + buffer[2]);
        System.out.println("skip " + in.skipBytes(1));
        in.readFully(buffer, 0, 2);
        System.out.println("fully " + buffer[0] + " " + buffer[1] + " " + in.readByte() + " " + in.readByte() + " " + in.readChar() + " " + in.read());

        // InputStream reads return unsigned bytes and fill arrays.
        ByteArrayInputStream plain = new ByteArrayInputStream(new byte[] {(byte) 0xAC, 1, 2, (byte) 200, 5});
        System.out.println("plain " + plain.read());
        byte[] three = new byte[3];
        System.out.println("plain " + plain.read(three) + " " + three[0] + " " + three[1] + " " + three[2] + " " + plain.read() + " " + plain.read());
    }
}

class EvolutionLazy implements Serializable {
    private static final long serialVersionUID = 3L;
    int value = 11;
}
