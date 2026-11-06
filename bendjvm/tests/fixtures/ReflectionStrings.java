import java.io.IOException;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.List;
import java.util.Map;

// Modifier tests and toString (volatile/synchronized members load in plan 05), Method/Constructor/Field toString and
// toGenericString, and PrintStream.print without a trailing newline.
public class ReflectionStrings {
    public static final int CONSTANT = 1;
    protected transient List<String> names;
    private Map<String, int[]>[] table;
    interface Shape { default double area() { return 0; } double perimeter(); }

    public ReflectionStrings() {}
    protected ReflectionStrings(String label, int... values) throws IOException {}
    public static <T extends Comparable<T>> T max(List<? extends T> values, T fallback) throws IllegalStateException, IOException { return fallback; }
    private native void raw();
    public final strictfp double[][] grid(long[] seeds, Object... extra) { return null; }

    public static void main(String[] args) throws Exception {
        int[] flags = {Modifier.PUBLIC | Modifier.STATIC | Modifier.FINAL, Modifier.PRIVATE | Modifier.TRANSIENT | Modifier.VOLATILE, Modifier.PROTECTED | Modifier.ABSTRACT | Modifier.INTERFACE, Modifier.SYNCHRONIZED | Modifier.NATIVE | Modifier.STRICT, 0};
        for (int f : flags) {
            System.out.print("[" + Modifier.toString(f) + "] ");
            System.out.print(Modifier.isPublic(f));
            System.out.print(' ');
            System.out.print(Modifier.isStatic(f) ? 1 : 0);
            System.out.print(" ");
            System.out.println(Modifier.isAbstract(f) + " " + Modifier.isInterface(f) + " " + Modifier.isFinal(f) + " " + Modifier.isPrivate(f) + " " + Modifier.isProtected(f) + " " + Modifier.isTransient(f) + " " + Modifier.isVolatile(f) + " " + Modifier.isSynchronized(f) + " " + Modifier.isNative(f) + " " + Modifier.isStrict(f));
        }
        Class<?> c = ReflectionStrings.class;
        for (String name : new String[]{"max", "raw", "grid", "main"}) {
            for (Method m : c.getDeclaredMethods()) {
                if (m.getName().equals(name)) {
                    System.out.println(m);
                    System.out.println(m.toGenericString());
                }
            }
        }
        System.out.println(Shape.class.getMethod("area"));
        System.out.println(Shape.class.getMethod("area").toGenericString());
        System.out.println(Shape.class.getMethod("perimeter"));
        System.out.println(c.getConstructor());
        Constructor<?> labelled = c.getDeclaredConstructor(String.class, int[].class);
        System.out.println(labelled);
        System.out.println(labelled.toGenericString());
        for (String name : new String[]{"CONSTANT", "names", "table"}) {
            Field f = c.getDeclaredField(name);
            System.out.println(f);
            System.out.println(f.toGenericString());
        }
        System.out.print("done");
        System.out.print(1L);
        System.out.print(2.5);
        System.out.print(3.5f);
        System.out.print(true);
        System.out.print((Object) null);
        System.out.print(c.getSimpleName());
        System.out.println();
    }
}
