import java.lang.invoke.CallSite;
import java.lang.invoke.ConstantCallSite;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.invoke.MutableCallSite;
import java.lang.invoke.VolatileCallSite;

public final class MethodHandleFixture {
    public interface Adder {
        long add(long amount);
    }
    public static final class Box implements Adder {
        public long value;
        public Box(long value) { this.value = value; }
        public long add(long amount) { return value + amount; }
    }
    public static int staticValue;

    public static int add(int left, int right) { return left + right; }
    public static int subtract(int left, int right) { return left - right; }
    public static long wide(long left, double right) { return left + (long) right; }
    private static int hiddenValue() { return 17; }
    public static void noResult() { }
    public static int fail() { throw new IllegalStateException("handle-target"); }
    public static int sum(int... values) {
        int result = 0;
        for (int value : values) result += value;
        return result;
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Throwable {
        MethodHandles.Lookup lookup = MethodHandles.lookup();
        MethodType binaryType = MethodType.methodType(
            int.class, new Class[] { int.class, int.class });
        MethodType parsedType = MethodType.fromMethodDescriptorString(
            "(II)I", MethodHandleFixture.class.getClassLoader());
        check(binaryType.equals(parsedType) && binaryType.hashCode() == parsedType.hashCode() &&
              binaryType.toMethodDescriptorString().equals("(II)I") &&
              binaryType.parameterCount() == 2 && binaryType.parameterType(1) == int.class &&
              binaryType.parameterArray().length == 2 && binaryType.returnType() == int.class,
              "MethodType descriptor and queries");
        MethodType unary = MethodType.methodType(long.class, long.class);
        MethodType noArguments = MethodType.methodType(String.class);
        check(unary.parameterCount() == 1 && unary.returnType() == long.class &&
              noArguments.parameterCount() == 0 && noArguments.returnType() == String.class,
              "MethodType class overloads");
        try {
            MethodType.methodType(int.class, void.class);
            throw new AssertionError("MethodType accepted a void parameter");
        } catch (IllegalArgumentException expected) { }
        MethodHandles.Lookup publicLookup = MethodHandles.publicLookup();
        check(lookup.lookupClass() == MethodHandleFixture.class &&
              (lookup.lookupModes() & 15) == 15 &&
              lookup.in(MethodHandleFixture.class).lookupClass() == MethodHandleFixture.class,
              "Lookup identity and modes");
        MethodHandle publicAdd = publicLookup.findStatic(MethodHandleFixture.class, "add", binaryType);
        check((int) publicAdd.invokeExact(3, 4) == 7,
              "public lookup");
        try {
            publicLookup.findStatic(MethodHandleFixture.class, "hiddenValue",
                MethodType.methodType(int.class));
            throw new AssertionError("public lookup accessed private method");
        } catch (IllegalAccessException expected) { }


        MethodHandle add = lookup.findStatic(MethodHandleFixture.class, "add", binaryType);
        check((int) add.invokeExact(7, 8) == 15 &&
              add.type().toMethodDescriptorString().equals("(II)I"),
              "findStatic and invokeExact");
        check((int) add.invoke((short) 2, (short) 3) == 5,
              "invoke primitive widening");
        try {
            add.invokeExact((short) 2, (short) 3);
            throw new AssertionError("invokeExact adapted a mismatched type");
        } catch (java.lang.invoke.WrongMethodTypeException expected) { }


        MethodType widenedType = MethodType.methodType(
            double.class, new Class[] { int.class, float.class });
        MethodHandle widened = lookup.findStatic(MethodHandleFixture.class, "wide",
            MethodType.methodType(long.class, new Class[] { long.class, double.class }))
            .asType(widenedType);
        check((double) widened.invokeExact(7, 2.5f) == 9.0d,
              "asType primitive widening");
        MethodHandle identityInt = MethodHandles.identity(int.class);
        MethodHandle objectIdentity = identityInt.asType(
            MethodType.methodType(Object.class, Object.class));
        Object identityResult = objectIdentity.invokeExact((Object) Integer.valueOf(23));
        check(Integer.valueOf(23).equals(identityResult),
              "asType boxing and unboxing");
        try {
            Object wrongResult = objectIdentity.invokeExact((Object) "not an integer");
            throw new AssertionError("asType accepted the wrong wrapper");
        } catch (ClassCastException expected) { }
        Object nullValue = null;
        try {
            Object nullResult = objectIdentity.invokeExact(nullValue);
            throw new AssertionError("asType unboxed null");
        } catch (NullPointerException expected) { }
        try {
            objectIdentity.asType(MethodType.methodType(String.class));
            throw new AssertionError("asType accepted a parameter-count mismatch");
        } catch (java.lang.invoke.WrongMethodTypeException expected) { }
        MethodHandle droppedResult = identityInt.asType(
            MethodType.methodType(void.class, int.class));
        droppedResult.invokeExact(9);
        MethodHandle defaultResult = lookup.findStatic(
            MethodHandleFixture.class, "noResult", MethodType.methodType(void.class))
            .asType(MethodType.methodType(int.class));
        check((int) defaultResult.invokeExact() == 0,
              "asType return drop and default");
        MethodHandle stringIdentity = MethodHandles.identity(Object.class).asType(
            MethodType.methodType(String.class, String.class));
        check("cast".equals((String) stringIdentity.invokeExact("cast")),
              "asType reference casts");
        MethodHandle referenceIdentity = MethodHandles.identity(Object.class).asType(
            MethodType.methodType(String.class, Object.class));
        try {
            Object notString = Integer.valueOf(1);
            String invalidCast = (String) referenceIdentity.invokeExact(notString);
            throw new AssertionError("asType skipped its reference cast");
        } catch (ClassCastException expected) { }




        MethodHandle failing = lookup.findStatic(MethodHandleFixture.class, "fail",
            MethodType.methodType(int.class));
        try {
            int ignored = (int) failing.invokeExact();
            throw new AssertionError("target exception was swallowed");
        } catch (IllegalStateException expected) {
            check("handle-target".equals(expected.getMessage()),
                  "target exception propagated directly");
        }

        MethodHandle inserted = MethodHandles.insertArguments(
            add, 0, new Object[] { Integer.valueOf(40) });
        check((int) inserted.invokeExact(2) == 42,
              "insertArguments primitive binding");
        MethodHandle wideAdd = lookup.findStatic(MethodHandleFixture.class, "wide",
            MethodType.methodType(long.class, new Class[] { long.class, double.class }));
        MethodHandle boundWide = MethodHandles.insertArguments(
            wideAdd, 0, new Object[] { Long.valueOf(40L) });
        check((long) boundWide.invokeExact(2.5d) == 42L,
              "insertArguments wide binding");

        MethodHandle constant = MethodHandles.constant(int.class, Integer.valueOf(19));
        MethodHandle booleanConstant = MethodHandles.constant(boolean.class, Boolean.TRUE);
        MethodHandle byteConstant = MethodHandles.constant(byte.class, Byte.valueOf((byte) 7));
        MethodHandle charConstant = MethodHandles.constant(char.class, Character.valueOf('q'));
        MethodHandle shortConstant = MethodHandles.constant(short.class, Short.valueOf((short) 13));
        MethodHandle floatConstant = MethodHandles.constant(float.class, Float.valueOf(1.25f));
        MethodHandle wideConstant = MethodHandles.constant(
            long.class, Long.valueOf(0x1234567887654321L));
        MethodHandle doubleConstant = MethodHandles.constant(double.class, Double.valueOf(-0.0d));
        MethodHandle identity = MethodHandles.identity(long.class);
        check((int) constant.invokeExact() == 19 &&
              (boolean) booleanConstant.invokeExact() &&
              (byte) byteConstant.invokeExact() == 7 &&
              (char) charConstant.invokeExact() == 'q' &&
              (short) shortConstant.invokeExact() == 13 &&
              (float) floatConstant.invokeExact() == 1.25f &&
              (long) wideConstant.invokeExact() == 0x1234567887654321L &&
              Double.doubleToRawLongBits((double) doubleConstant.invokeExact()) == Long.MIN_VALUE &&
              (long) identity.invokeExact(0x1234567887654321L) == 0x1234567887654321L,
              "primitive constants and identity handles");

        MethodHandle referenceConstant = MethodHandles.constant(String.class, "constant");
        MethodHandle nullConstant = MethodHandles.constant(Object.class, null);
        check("constant".equals((String) referenceConstant.invokeExact()) &&
              nullConstant.invokeExact() == null,
              "reference and null constants");
        try {
            MethodHandles.constant(String.class, Integer.valueOf(1));
            throw new AssertionError("constant accepted an incompatible reference");
        } catch (ClassCastException expected) { }
        try {
            MethodHandles.constant(int.class, Long.valueOf(1L));
            throw new AssertionError("constant accepted the wrong primitive wrapper");
        } catch (ClassCastException expected) { }
        try {
            MethodHandles.constant(int.class, null);
            throw new AssertionError("constant accepted null for a primitive");
        } catch (NullPointerException expected) { }
        try {
            MethodHandles.constant(void.class, Integer.valueOf(1));
            throw new AssertionError("constant accepted void");
        } catch (IllegalArgumentException expected) { }

        Box box = new Box(30L);
        MethodHandle virtual = lookup.findVirtual(Box.class, "add",
            MethodType.methodType(long.class, long.class));
        MethodHandle bound = virtual.bindTo(box);
        check((long) virtual.invokeExact(box, 4L) == 34L &&
              (long) bound.invokeExact(5L) == 35L,
              "findVirtual and bindTo");
        MethodHandle interfaceVirtual = lookup.findVirtual(
            Adder.class, "add", MethodType.methodType(long.class, long.class));
        check((long) interfaceVirtual.invokeExact((Adder) box, 6L) == 36L,
              "findVirtual interface reference kind");


        MethodHandle constructor = lookup.findConstructor(Box.class,
            MethodType.methodType(void.class, long.class));
        Box created = (Box) constructor.invokeExact(12L);
        MethodHandle getter = lookup.findGetter(Box.class, "value", long.class);
        MethodHandle setter = lookup.findSetter(Box.class, "value", long.class);
        check((long) getter.invokeExact(created) == 12L,
              "findConstructor and findGetter");
        setter.invokeExact(created, 55L);
        check(created.value == 55L, "findSetter");

        MethodHandle staticGetter = lookup.findStaticGetter(
            MethodHandleFixture.class, "staticValue", int.class);
        MethodHandle staticSetter = lookup.findStaticSetter(
            MethodHandleFixture.class, "staticValue", int.class);
        staticSetter.invokeExact(73);
        check((int) staticGetter.invokeExact() == 73, "static field handles");

        MethodHandle varargs = lookup.findStatic(MethodHandleFixture.class, "sum",
            MethodType.methodType(int.class, int[].class));
        MethodHandle collector = varargs.asVarargsCollector(int[].class);
        check(collector.isVarargsCollector() && (int) collector.invoke(1, 2, 3) == 6 &&
              !collector.asFixedArity().isVarargsCollector(),
              "varargs collector and fixed arity");

        MethodHandle subtract = lookup.findStatic(MethodHandleFixture.class, "subtract", binaryType);
        MutableCallSite mutable = new MutableCallSite(add);
        MethodHandle dynamic = mutable.dynamicInvoker();
        check((int) dynamic.invokeExact(9, 2) == 11, "mutable initial target");
        mutable.setTarget(subtract);
        MutableCallSite.syncAll(new MutableCallSite[] { mutable });
        check((int) dynamic.invokeExact(9, 2) == 7 && mutable.type().equals(binaryType) &&
              mutable.getTarget().type().equals(binaryType),
              "mutable target update and dynamicInvoker");

        MutableCallSite typedMutable = new MutableCallSite(binaryType);
        typedMutable.setTarget(add);
        check((int) typedMutable.dynamicInvoker().invokeExact(4, 5) == 9,
              "typed mutable call site");
        try {
            typedMutable.setTarget(identity);
            throw new AssertionError("mutable call site accepted wrong target type");
        } catch (java.lang.invoke.WrongMethodTypeException expected) { }
        try {
            typedMutable.setTarget(null);
            throw new AssertionError("mutable call site accepted null target");
        } catch (NullPointerException expected) { }
        MutableCallSite.syncAll(new MutableCallSite[0]);


        VolatileCallSite volatileSite = new VolatileCallSite(binaryType);
        volatileSite.setTarget(add);
        check((int) volatileSite.dynamicInvoker().invokeExact(10, 5) == 15,
              "typed volatile call site");
        CallSite constantSite = new ConstantCallSite(add);
        check((int) constantSite.dynamicInvoker().invokeExact(6, 4) == 10,
              "constant call site target");
        try {
            constantSite.setTarget(subtract);
            throw new AssertionError("constant call site accepted mutation");
        } catch (UnsupportedOperationException expected) {
            System.out.println("constant-site-immutable");
        }
        System.out.println("method-handles-ok");
    }
}
