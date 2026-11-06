import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.lang.reflect.Constructor;
import java.lang.reflect.Executable;
import java.lang.reflect.Method;
import java.lang.reflect.Parameter;
import java.util.List;

// java.lang.reflect.Parameter and Executable.getParameters (JDK 8). The harness
// runs this both with and without javac -parameters.
public class ParameterReflection {
    @Retention(RetentionPolicy.RUNTIME) @Target(ElementType.PARAMETER) @interface Tag { String value(); }

    public static int sum(final int first, @Tag("second") long second, String... rest) { return 0; }
    public <T extends Number> void generic(List<T> values, T[] array) {}
    public ParameterReflection(String label) {}
    class Inner { Inner(@Tag("inner") int value) {} }

    static void describe(Executable executable) {
        System.out.println(executable.getName() + " count=" + executable.getParameterCount());
        Parameter[] parameters = executable.getParameters();
        for (int i = 0; i < parameters.length; i++) {
            Parameter p = parameters[i];
            Tag tag = p.getAnnotation(Tag.class);
            System.out.println("  " + p.getName() + " present=" + p.isNamePresent() + " modifiers=" + p.getModifiers()
                + " implicit=" + p.isImplicit() + " synthetic=" + p.isSynthetic() + " varargs=" + p.isVarArgs());
            System.out.println("    type=" + p.getType().getName() + " generic=" + p.getParameterizedType().getTypeName()
                + " tag=" + (tag == null ? "none" : tag.value()) + " annotations=" + p.getAnnotations().length
                + " present=" + p.isAnnotationPresent(Tag.class));
            System.out.println("    toString=" + p);
            System.out.println("    declaring=" + (p.getDeclaringExecutable() == executable) + " equal=" + p.equals(executable.getParameters()[i])
                + " hash=" + (p.hashCode() == executable.getParameters()[i].hashCode()) + " self=" + p.equals(parameters[(i + 1) % parameters.length]));
        }
    }

    public static void main(String[] args) throws Exception {
        Method sum = ParameterReflection.class.getMethod("sum", int.class, long.class, String[].class);
        describe(sum);
        for (Method m : ParameterReflection.class.getDeclaredMethods()) {
            if (m.getName().equals("generic")) describe(m);
        }
        Constructor<ParameterReflection> constructor = ParameterReflection.class.getConstructor(String.class);
        describe(constructor);
        describe(Inner.class.getDeclaredConstructors()[0]);
        System.out.println(sum.getParameters()[0].equals(null) + " " + sum.getParameters()[0].equals("x"));
    }
}
