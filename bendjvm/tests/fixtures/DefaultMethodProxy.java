import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.List;

public class DefaultMethodProxy {
    public interface Greeter {
        String name();

        default String greet(String greeting) {
            return greeting + ", " + name() + "!";
        }

        default int twice(int value) {
            return value * 2;
        }

        default void touch(StringBuilder log) {
            log.append("touched");
        }
    }

    public static class Point {
        private int x;
        public int y;

        public Point() {
            this(1, 2);
        }

        private Point(int x, int y) {
            this.x = x;
            this.y = y;
        }

        private int sum() {
            return x + y;
        }

        public static String describe(String prefix, int value) {
            return prefix + value;
        }

        public static int count(String... values) {
            return values.length;
        }
    }

    // Spring 5 on Java 8 reflectively uses the private Lookup(Class, int) or
    // Lookup(Class) constructor; Java 9+ removed both, so fall back to
    // privateLookupIn only when the constructor is missing or not openable.
    static MethodHandles.Lookup privateLookup(Class<?> type, boolean twoArgs) throws Exception {
        try {
            Constructor<MethodHandles.Lookup> constructor = twoArgs
                ? MethodHandles.Lookup.class.getDeclaredConstructor(Class.class, int.class)
                : MethodHandles.Lookup.class.getDeclaredConstructor(Class.class);
            constructor.setAccessible(true);
            return twoArgs ? constructor.newInstance(type, Integer.valueOf(MethodHandles.Lookup.PRIVATE)) : constructor.newInstance(type);
        } catch (NoSuchMethodException | RuntimeException missing) {
            Method method = MethodHandles.class.getMethod("privateLookupIn", Class.class, MethodHandles.Lookup.class);
            return (MethodHandles.Lookup) method.invoke(null, type, MethodHandles.lookup());
        }
    }

    public static void main(String[] args) throws Throwable {
        final boolean[] twoArgs = {true};
        InvocationHandler handler = new InvocationHandler() {
            public Object invoke(Object proxy, Method method, Object[] arguments) throws Throwable {
                if (method.getName().equals("name")) {
                    return "proxy";
                }
                if (method.isDefault()) {
                    Class<?> declaring = method.getDeclaringClass();
                    return privateLookup(declaring, twoArgs[0])
                        .unreflectSpecial(method, declaring)
                        .bindTo(proxy)
                        .invokeWithArguments(arguments);
                }
                throw new UnsupportedOperationException(method.getName());
            }
        };
        Greeter greeter = (Greeter) Proxy.newProxyInstance(
            Greeter.class.getClassLoader(), new Class<?>[] {Greeter.class}, handler);
        System.out.println(greeter.greet("Hello"));
        System.out.println(greeter.twice(21));
        StringBuilder log = new StringBuilder();
        greeter.touch(log);
        System.out.println(log);
        twoArgs[0] = false;
        System.out.println(greeter.greet("Hi"));

        MethodHandles.Lookup lookup = MethodHandles.lookup();
        Method sum = Point.class.getDeclaredMethod("sum");
        try {
            lookup.unreflect(sum);
            System.out.println("private unreflect allowed");
        } catch (IllegalAccessException denied) {
            System.out.println("private unreflect denied");
        }
        sum.setAccessible(true);
        MethodHandle sumHandle = lookup.unreflect(sum);
        System.out.println(sumHandle.type());
        System.out.println((int) sumHandle.invokeExact(new Point()));
        System.out.println(sumHandle.invokeWithArguments(new Point()));

        Method describe = Point.class.getMethod("describe", String.class, int.class);
        MethodHandle describeHandle = lookup.unreflect(describe);
        System.out.println(describeHandle.type());
        System.out.println(describeHandle.invokeWithArguments("value=", 7));
        List<Object> listed = new ArrayList<Object>();
        listed.add("listed=");
        listed.add(Integer.valueOf(8));
        System.out.println(describeHandle.invokeWithArguments(listed));

        MethodHandle countHandle = lookup.unreflect(Point.class.getMethod("count", String[].class));
        System.out.println(countHandle.isVarargsCollector());
        System.out.println(countHandle.invokeWithArguments("a", "b", "c"));

        Constructor<Point> privateConstructor = Point.class.getDeclaredConstructor(int.class, int.class);
        try {
            lookup.unreflectConstructor(privateConstructor);
            System.out.println("private constructor allowed");
        } catch (IllegalAccessException denied) {
            System.out.println("private constructor denied");
        }
        privateConstructor.setAccessible(true);
        MethodHandle constructorHandle = lookup.unreflectConstructor(privateConstructor);
        System.out.println(constructorHandle.type());
        Point made = (Point) constructorHandle.invokeWithArguments(3, 4);
        System.out.println(made.y);

        Field x = Point.class.getDeclaredField("x");
        x.setAccessible(true);
        MethodHandle getter = lookup.unreflectGetter(x);
        MethodHandle setter = lookup.unreflectSetter(x);
        System.out.println(getter.type() + " " + setter.type());
        setter.invokeWithArguments(made, 30);
        System.out.println(getter.invokeWithArguments(made));

        Field y = Point.class.getField("y");
        MethodHandle yGetter = MethodHandles.publicLookup().unreflectGetter(y);
        System.out.println(yGetter.invokeWithArguments(made));

        MethodHandle virtual = lookup.findVirtual(Greeter.class, "greet", MethodType.methodType(String.class, String.class));
        System.out.println(virtual.invokeWithArguments(greeter, "Hey"));
        System.out.println(lookup.findStatic(Point.class, "describe", MethodType.methodType(String.class, String.class, int.class))
            .bindTo("bound=").invokeWithArguments(new Object[] {Integer.valueOf(9)}));
        try {
            sumHandle.invokeWithArguments();
        } catch (Exception wrong) {
            System.out.println(wrong.getClass().getName());
        }
    }
}
