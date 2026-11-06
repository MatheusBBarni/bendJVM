import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

public class AnnotationFormatting {
    enum Mode { FAST, SLOW }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Inner {
        String value() default "inner";
        int depth() default 1;
    }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Single {
        String value();
    }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Lone {
        int number();
    }

    @Retention(RetentionPolicy.RUNTIME)
    @interface Empty {
    }

    @Retention(RetentionPolicy.RUNTIME)
    @Target({ElementType.TYPE, ElementType.METHOD, ElementType.FIELD})
    @interface Everything {
        String text() default "quote \" back \\ tab \t nl \n apostrophe ' unicode é 中";
        char letter() default '\'';
        char control() default '\u0001';
        byte small() default -2;
        short medium() default 300;
        int number() default 42;
        long big() default 1234567890123L;
        float ratio() default 1.5f;
        float notNumber() default Float.NaN;
        double exact() default 0.1;
        double infinite() default Double.NEGATIVE_INFINITY;
        boolean flag() default true;
        Class<?> type() default String.class;
        Class<?> primitive() default int.class;
        Class<?> array() default String[][].class;
        Class<?> nested() default Inner.class;
        Mode mode() default Mode.SLOW;
        Inner inner() default @Inner;
        String[] strings() default {"a", "b\"c"};
        int[] numbers() default {1, 2, 3};
        long[] bigs() default {4L};
        char[] letters() default {'x', '\n'};
        byte[] bytes() default {0, 127, -128};
        short[] shorts() default {-1};
        boolean[] booleans() default {true, false};
        float[] floats() default {2.0f};
        double[] doubles() default {3.25};
        Class<?>[] types() default {Integer.class, void.class};
        Mode[] modeArray() default {Mode.FAST, Mode.SLOW};
        Inner[] inners() default {@Inner(value = "x", depth = 2), @Inner};
        String[] nothing() default {};
    }

    @Everything
    static class Defaults {
    }

    @Everything(number = 7, text = "explicit", modeArray = Mode.FAST)
    @Single("only")
    @Lone(number = 5)
    @Empty
    static class Explicit {
    }

    @Single(value = "named")
    @Inner(depth = 9)
    static class Named {
    }

    // Member names avoid sharing a HashMap bucket: the JDK orders defaults by
    // AnnotationType's HashMap, whose ties follow HotSpot's internal method order.
    public static void main(String[] args) {
        System.out.println(Defaults.class.getAnnotation(Everything.class));
        System.out.println(Explicit.class.getAnnotation(Everything.class));
        System.out.println(Explicit.class.getAnnotation(Single.class));
        System.out.println(Explicit.class.getAnnotation(Lone.class));
        System.out.println(Explicit.class.getAnnotation(Empty.class));
        System.out.println(Named.class.getAnnotation(Single.class));
        System.out.println(Named.class.getAnnotation(Inner.class));
        System.out.println(Named.class.getAnnotation(Inner.class).toString().equals(String.valueOf(Named.class.getAnnotation(Inner.class))));
    }
}
