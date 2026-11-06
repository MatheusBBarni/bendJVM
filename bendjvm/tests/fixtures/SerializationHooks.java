import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.Externalizable;
import java.io.IOException;
import java.io.InputStream;
import java.io.InvalidObjectException;
import java.io.NotActiveException;
import java.io.ObjectInput;
import java.io.ObjectInputStream;
import java.io.ObjectInputValidation;
import java.io.ObjectOutput;
import java.io.ObjectOutputStream;
import java.io.ObjectStreamClass;
import java.io.ObjectStreamField;
import java.io.OutputStream;
import java.io.Serializable;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

// The ObjectOutputStream/ObjectInputStream subclass hooks, ObjectStreamClass
// and ObjectStreamField, serialPersistentFields with PutField/GetField,
// validation callbacks, TC_EXCEPTION, protocol 1, and field type checks.
public class SerializationHooks {
    static class Point implements Serializable {
        private static final long serialVersionUID = 1L;
        int x = 3;
        String label = "p";
        Object extra;
    }

    public interface Greeter {
        String greet();
    }

    static class Handler implements InvocationHandler, Serializable {
        private static final long serialVersionUID = 2L;

        public Object invoke(Object proxy, Method method, Object[] args) {
            return "hello";
        }
    }

    // Writes each class's name as its annotation and replaces strings.
    static class AnnotatingOutput extends ObjectOutputStream {
        AnnotatingOutput(OutputStream out) throws IOException {
            super(out);
            enableReplaceObject(true);
        }

        protected void writeStreamHeader() throws IOException {
            super.writeStreamHeader();
            writeByte(42);
        }

        protected void annotateClass(Class<?> type) throws IOException {
            writeUTF("class:" + type.getName());
        }

        protected void annotateProxyClass(Class<?> type) throws IOException {
            writeUTF("proxy");
        }

        protected Object replaceObject(Object value) {
            return "p".equals(value) ? "replaced" : value;
        }
    }

    // Reads the annotations back in resolveClass, like Spring's
    // ConfigurableObjectInputStream, and resolves strings.
    static class AnnotatedInput extends ObjectInputStream {
        AnnotatedInput(InputStream in) throws IOException {
            super(in);
            enableResolveObject(true);
        }

        protected void readStreamHeader() throws IOException {
            super.readStreamHeader();
            System.out.println("header extra " + readByte());
        }

        protected Class<?> resolveClass(ObjectStreamClass desc) throws IOException, ClassNotFoundException {
            System.out.println("resolveClass " + desc.getName() + " " + desc.getSerialVersionUID() + " " + readUTF());
            return super.resolveClass(desc);
        }

        protected Class<?> resolveProxyClass(String[] names) throws IOException, ClassNotFoundException {
            System.out.println("resolveProxyClass " + names.length + " " + names[0] + " " + readUTF());
            return super.resolveProxyClass(names);
        }

        protected Object resolveObject(Object value) {
            return "replaced".equals(value) ? "resolved" : value;
        }
    }

    // Compact descriptors: only the class name.
    static class CompactOutput extends ObjectOutputStream {
        CompactOutput(OutputStream out) throws IOException {
            super(out);
        }

        protected void writeClassDescriptor(ObjectStreamClass desc) throws IOException {
            writeUTF(desc.getName());
        }
    }

    static class CompactInput extends ObjectInputStream {
        CompactInput(InputStream in) throws IOException {
            super(in);
        }

        protected ObjectStreamClass readClassDescriptor() throws IOException, ClassNotFoundException {
            return ObjectStreamClass.lookup(Class.forName(readUTF()));
        }
    }

    // writeObjectOverride/readObjectOverride through the protected constructors.
    static class OverrideOutput extends ObjectOutputStream {
        final StringBuilder log = new StringBuilder();

        OverrideOutput() throws IOException {
            super();
        }

        protected void writeObjectOverride(Object value) {
            log.append("[").append(value).append("]");
        }
    }

    static class OverrideInput extends ObjectInputStream {
        OverrideInput() throws IOException {
            super();
        }

        protected Object readObjectOverride() {
            return "overridden";
        }
    }

    // serialPersistentFields name fields the class does not have; writeObject
    // and readObject use PutField and GetField.
    static class Persistent implements Serializable {
        private static final long serialVersionUID = 3L;
        private static final ObjectStreamField[] serialPersistentFields = {
            new ObjectStreamField("total", long.class),
            new ObjectStreamField("name", String.class),
            new ObjectStreamField("ratio", double.class),
        };
        transient long total = 10L;
        transient String title = "t";
        transient double ratio = 0.25;

        private void writeObject(ObjectOutputStream out) throws IOException {
            ObjectOutputStream.PutField fields = out.putFields();
            fields.put("total", total + 1);
            fields.put("name", title + "!");
            fields.put("ratio", ratio * 2);
            try {
                fields.put("missing", 1);
            } catch (IllegalArgumentException e) {
                System.out.println("put: " + e.getMessage());
            }
            out.writeFields();
        }

        private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
            ObjectInputStream.GetField fields = in.readFields();
            total = fields.get("total", 0L);
            title = (String) fields.get("name", null);
            ratio = fields.get("ratio", 0.0);
            System.out.println("defaulted " + fields.defaulted("total") + " " + fields.getObjectStreamClass().getName());
            try {
                fields.get("total", 0);
            } catch (IllegalArgumentException e) {
                System.out.println("get: " + e.getMessage());
            }
        }
    }

    static class Validated implements Serializable, ObjectInputValidation {
        private static final long serialVersionUID = 4L;
        String name;

        Validated(String name) {
            this.name = name;
        }

        private void readObject(ObjectInputStream in) throws IOException, ClassNotFoundException {
            in.defaultReadObject();
            in.registerValidation(this, name.length());
            in.registerValidation(new ObjectInputValidation() {
                public void validateObject() {
                    System.out.println("anonymous " + Validated.this.name);
                }
            }, name.length());
        }

        public void validateObject() throws InvalidObjectException {
            System.out.println("validate " + name);
            if (name.equals("bad")) {
                throw new InvalidObjectException("invalid " + name);
            }
        }
    }

    static class Pair implements Serializable {
        private static final long serialVersionUID = 5L;
        Validated first = new Validated("ab");
        Validated second = new Validated("abcd");
    }

    static class Unserializable {
    }

    static class Holder implements Serializable {
        private static final long serialVersionUID = 6L;
        Object value = new Unserializable();
    }

    static class Failing implements Serializable {
        private static final long serialVersionUID = 7L;

        private void writeObject(ObjectOutputStream out) throws IOException {
            out.writeInt(1);
            throw new IOException("callback failed");
        }
    }

    static class TypeA implements Serializable {
        private static final long serialVersionUID = 8L;
        Object value = "text";
    }

    static class TypeB implements Serializable {
        private static final long serialVersionUID = 8L;
        Integer value;
    }

    public static class Ext implements Externalizable {
        private static final long serialVersionUID = 9L;
        int count = 5;

        public Ext() {
        }

        public void writeExternal(ObjectOutput out) throws IOException {
            out.writeInt(count);
        }

        public void readExternal(ObjectInput in) throws IOException {
            count = in.readInt() + 1;
        }
    }

    static String hex(byte[] bytes) {
        StringBuilder text = new StringBuilder();
        for (byte value : bytes) {
            String digits = Integer.toHexString(value & 0xff);
            text.append(digits.length() == 1 ? "0" + digits : digits);
        }
        return text.toString();
    }

    static byte[] write(Object value) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        ObjectOutputStream out = new ObjectOutputStream(bytes);
        out.writeObject(value);
        out.close();
        return bytes.toByteArray();
    }

    static Object read(byte[] bytes) throws IOException, ClassNotFoundException {
        return new ObjectInputStream(new ByteArrayInputStream(bytes)).readObject();
    }

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
        // Annotations, header, replace and resolve hooks.
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        AnnotatingOutput annotating = new AnnotatingOutput(bytes);
        Point point = new Point();
        point.extra = Proxy.newProxyInstance(SerializationHooks.class.getClassLoader(), new Class<?>[] {Greeter.class}, new Handler());
        annotating.writeObject(point);
        annotating.close();
        System.out.println("annotated " + hex(bytes.toByteArray()));
        AnnotatedInput annotated = new AnnotatedInput(new ByteArrayInputStream(bytes.toByteArray()));
        Point read = (Point) annotated.readObject();
        System.out.println("point " + read.x + " " + read.label + " " + ((Greeter) read.extra).greet());

        // Compact class descriptors.
        bytes = new ByteArrayOutputStream();
        CompactOutput compact = new CompactOutput(bytes);
        compact.writeObject(new Point());
        compact.close();
        System.out.println("compact " + hex(bytes.toByteArray()));
        Point compactPoint = (Point) new CompactInput(new ByteArrayInputStream(bytes.toByteArray())).readObject();
        System.out.println("compact " + compactPoint.x + " " + compactPoint.label);

        // Override mode.
        OverrideOutput override = new OverrideOutput();
        override.writeObject("a");
        override.writeObject(7);
        System.out.println("override " + override.log + " " + new OverrideInput().readObject());

        // serialPersistentFields with PutField and GetField.
        byte[] persistent = write(new Persistent());
        System.out.println("persistent " + hex(persistent));
        Persistent restored = (Persistent) read(persistent);
        System.out.println("persistent " + restored.total + " " + restored.title + " " + restored.ratio);

        // ObjectStreamClass and ObjectStreamField.
        ObjectStreamClass desc = ObjectStreamClass.lookup(Persistent.class);
        System.out.println(desc + " " + desc.forClass().getName() + " " + (ObjectStreamClass.lookup(Persistent.class) == desc));
        for (ObjectStreamField field : desc.getFields()) {
            System.out.println("field " + field + " " + field.getTypeCode() + " " + field.getTypeString() + " " + field.isPrimitive() + " " + field.getType().getName());
        }
        System.out.println(desc.getField("name").getName() + " " + desc.getField("nothing") + " " + ObjectStreamClass.lookup(Unserializable.class) + " " + ObjectStreamClass.lookupAny(Unserializable.class).getSerialVersionUID());
        ObjectStreamField count = new ObjectStreamField("count", int.class);
        ObjectStreamField text = new ObjectStreamField("alpha", String.class);
        System.out.println(count.compareTo(text) + " " + text.compareTo(count) + " " + text.compareTo(new ObjectStreamField("beta", Object.class)));

        // Validation callbacks run after the top-level object, by priority.
        Pair pair = (Pair) read(write(new Pair()));
        System.out.println("pair " + pair.first.name + " " + pair.second.name);
        try {
            read(write(new Validated("bad")));
        } catch (InvalidObjectException e) {
            failure("validation", e);
        }
        ObjectInputStream idle = new ObjectInputStream(new ByteArrayInputStream(write("x")));
        try {
            idle.registerValidation(new Validated("idle"), 0);
        } catch (NotActiveException e) {
            failure("register", e);
        }

        // TC_EXCEPTION: a top-level write that fails records the exception.
        bytes = new ByteArrayOutputStream();
        ObjectOutputStream out = new ObjectOutputStream(bytes);
        out.writeObject("before");
        try {
            out.writeObject(new Holder());
        } catch (IOException e) {
            failure("write", e);
        }
        try {
            out.writeObject(new Failing());
        } catch (IOException e) {
            failure("callback", e);
        }
        out.close();
        ObjectInputStream in = new ObjectInputStream(new ByteArrayInputStream(bytes.toByteArray()));
        System.out.println("read " + in.readObject());
        for (int i = 0; i < 2; i++) {
            try {
                in.readObject();
            } catch (IOException e) {
                failure("aborted", e);
                System.out.println("cause " + e.getCause().getClass().getName() + ": " + e.getCause().getMessage());
            }
        }

        // A stream field whose local type changed.
        try {
            read(rename(write(new TypeA()), "$TypeA", "$TypeB"));
        } catch (ClassCastException e) {
            failure("type", e);
        }

        // Protocol version 1.
        bytes = new ByteArrayOutputStream();
        out = new ObjectOutputStream(bytes);
        out.useProtocolVersion(1);
        out.writeObject(new Ext());
        try {
            out.useProtocolVersion(2);
        } catch (IllegalStateException e) {
            failure("protocol", e);
        }
        out.close();
        System.out.println("protocol " + hex(bytes.toByteArray()) + " " + ((Ext) read(bytes.toByteArray())).count);
    }
}
