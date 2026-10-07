import java.lang.annotation.Annotation;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

public class AnnotationParserBoundaries {
    @Retention(RetentionPolicy.RUNTIME)
    public @interface Classes {
        Class<?> value() default void.class;
        Class<?> primitive() default int.class;
        Class<?> array() default int[].class;
    }
    @Retention(RetentionPolicy.CLASS)
    public @interface Hidden {}
    @Retention(RetentionPolicy.RUNTIME)
    public @interface Mark {}

    @Classes(void.class) @Hidden
    public static void explicit(int first, String second) {}
    public static void plain(int first, String second) {}
    public class Inner {
        public Inner(@Mark int value) {}
    }

    public static void main(String[] args) throws Exception {
        Annotation[][] plain = AnnotationParserBoundaries.class
                .getDeclaredMethod("plain", int.class, String.class).getParameterAnnotations();
        if (plain.length != 2 || plain[0].length != 0 || plain[1].length != 0)
            throw new AssertionError("unannotated parameter arity");
        java.lang.reflect.Method method = AnnotationParserBoundaries.class
                .getDeclaredMethod("explicit", int.class, String.class);
        Classes classes = method.getDeclaredAnnotation(Classes.class);
        if (classes.value() != void.class || classes.primitive() != int.class
                || classes.array() != int[].class || method.getDeclaredAnnotation(Hidden.class) != null)
            throw new AssertionError("Class values or invisible retention");
        if (Classes.class.getDeclaredMethod("value").getDefaultValue() != void.class)
            throw new AssertionError("void Class default");
        Annotation[][] inner = Inner.class.getDeclaredConstructor(
                AnnotationParserBoundaries.class, int.class).getParameterAnnotations();
        if (inner.length != 2 || inner[0].length != 0 || inner[1].length != 1
                || inner[1][0].annotationType() != Mark.class)
            throw new AssertionError("enclosing-instance annotation alignment");
        System.out.println("annotation-parser-boundaries");
    }
}
