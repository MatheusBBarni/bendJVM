import java.io.Serializable;
import java.lang.invoke.SerializedLambda;
import java.lang.reflect.Method;

public final class LambdaFixture {
    interface LongUnary {
        long apply(long value);
    }
    interface WideMix {
        double apply(long value, double adjustment);
    }
    interface BoundLong {
        long apply(long value);
    }
    interface UnboundLong {
        long apply(Holder holder, long value);
    }
    interface HolderFactory {
        Holder create(long initial);
    }
    interface GenericMapper<T> {
        T map(T value);
    }
    interface Marker { }

    public static final class Holder {
        private long base;
        public Holder(long base) { this.base = base; }
        public long add(long value) { return base + value; }
    }

    static class SpecialBase {
        String value() { return "base"; }
    }
    static class SpecialMiddle extends SpecialBase {
        String value() { return "middle"; }
    }
    static class SpecialChild extends SpecialMiddle {
        String invokeSpecial() throws Throwable {
            java.lang.invoke.MethodHandle handle = java.lang.invoke.MethodHandles.lookup()
                .findSpecial(SpecialBase.class, "value",
                    java.lang.invoke.MethodType.methodType(String.class), SpecialChild.class);
            return (String) handle.bindTo(this).invokeExact();
        }
    }


    static long staticAdd(long value) { return value + 5L; }
    static long fail(long value) { throw new IllegalStateException("lambda-target"); }

    static LongUnary capturing(long value) {
        return input -> input + value;
    }

    static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Throwable {
        LongUnary captured = capturing(7L);
        check(captured.apply(9L) == 16L, "capturing wide lambda");

        long[] mutable = { 4L };
        LongUnary mutableCapture = input -> input + mutable[0];
        mutable[0] = 10L;
        check(mutableCapture.apply(3L) == 13L, "captured mutable reference");

        LongUnary noncapturing = LambdaFixture::staticAdd;
        check(noncapturing.apply(8L) == 13L, "static method reference");
        Holder holder = new Holder(12L);
        BoundLong bound = holder::add;
        UnboundLong unbound = Holder::add;
        check(bound.apply(3L) == 15L && unbound.apply(holder, 4L) == 16L,
              "bound and unbound method references");

        HolderFactory factory = Holder::new;
        check(factory.create(20L).add(2L) == 22L, "constructor reference");
        WideMix mixed = (value, adjustment) -> value + adjustment;
        check(mixed.apply(2L, 3.5d) == 5.5d, "wide lambda arguments and result");

        String special = new SpecialChild().invokeSpecial();
        check(special.equals("middle"), "findSpecial ACC_SUPER selection");

        GenericMapper<String> mapper = value -> value + "!";
        check(mapper.map("bridge").equals("bridge!"), "generic SAM bridge");

        long extra = 2L;
        LongUnary serializable = (LongUnary & Marker & Serializable) (value -> value + extra);
        check(serializable instanceof Marker && serializable instanceof Serializable &&
              serializable.apply(5L) == 7L, "altMetafactory marker and serializable flags");
        Method writeReplace = serializable.getClass().getDeclaredMethod("writeReplace");
        writeReplace.setAccessible(true);
        SerializedLambda metadata = (SerializedLambda) writeReplace.invoke(serializable);
        check(metadata.getCapturingClass().contains("LambdaFixture") &&
              metadata.getFunctionalInterfaceClass().contains("LongUnary") &&
              metadata.getFunctionalInterfaceMethodName().equals("apply") &&
              metadata.getCapturedArgCount() == 1 &&
              ((Long) metadata.getCapturedArg(0)).longValue() == extra,
              "SerializedLambda metadata");

        LongUnary throwing = LambdaFixture::fail;
        try {
            throwing.apply(1L);
            throw new AssertionError("lambda exception was swallowed");
        } catch (IllegalStateException expected) {
            check(expected.getMessage().equals("lambda-target"), "lambda target exception");
            System.out.println(expected.getMessage());
        }
        System.out.println("lambda-ok");
    }
}
