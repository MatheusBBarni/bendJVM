import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

public class MetadataFixture {
    enum Kind { ALPHA, BETA }

    @Retention(RetentionPolicy.RUNTIME)
    @Target({ElementType.TYPE, ElementType.FIELD, ElementType.METHOD,
            ElementType.CONSTRUCTOR, ElementType.PARAMETER, ElementType.TYPE_USE})
    @interface Visible {
        int count() default 7;
        boolean enabled() default true;
        char marker() default 'M';
        float ratio() default 1.25f;
        long wide() default 123456789L;
        double precise() default 2.5d;
        String text() default "default";
        Class<?> type() default Object.class;
        Kind kind() default Kind.ALPHA;
        Nested nested() default @Nested(name = "nested-default");
        String[] labels() default {"one", "two"};
    }

    @Retention(RetentionPolicy.RUNTIME)
    @Target({ElementType.ANNOTATION_TYPE, ElementType.TYPE, ElementType.FIELD,
            ElementType.METHOD, ElementType.CONSTRUCTOR, ElementType.PARAMETER,
            ElementType.TYPE_USE})
    @interface Nested {
        String name();
    }

    @Retention(RetentionPolicy.CLASS)
    @Target({ElementType.TYPE, ElementType.FIELD, ElementType.METHOD,
            ElementType.CONSTRUCTOR, ElementType.PARAMETER, ElementType.TYPE_USE})
    @interface Invisible {
        String value() default "hidden";
    }

    @Retention(RetentionPolicy.RUNTIME)
    @Target(ElementType.TYPE_USE)
    @interface VisibleType {
        String value();
    }

    @Retention(RetentionPolicy.CLASS)
    @Target(ElementType.TYPE_USE)
    @interface InvisibleType {
        String value();
    }

    @Visible(text = "class", labels = {"class", "metadata"},
            nested = @Nested(name = "class-nested"), kind = Kind.BETA)
    @Invisible("class-hidden")
    public static class Annotated {
        @Visible(text = "field")
        @Invisible("field-hidden")
        private @VisibleType("field-type") @InvisibleType("field-type-hidden") String value;

        @Visible(text = "constructor")
        @Invisible("constructor-hidden")
        public Annotated(
                @Visible(text = "constructor-param")
                @Invisible("constructor-param-hidden") String value) {
            this.value = value;
        }

        @Visible(text = "method")
        @Invisible("method-hidden")
        public @VisibleType("return-type") String annotated(
                @Visible(text = "parameter")
                @Invisible("parameter-hidden")
                @VisibleType("parameter-type")
                @InvisibleType("parameter-type-hidden") String input)
                throws java.io.IOException, IllegalArgumentException {
            return value + input;
        }
    }

    public static class Probe {
        public static void main(String[] args) throws Exception {
            Class<Annotated> type = Annotated.class;
            if (type.getDeclaredAnnotation(Visible.class) == null
                    || type.getDeclaredAnnotation(Invisible.class) != null) {
                throw new AssertionError("class retention");
            }
            java.lang.reflect.Field field = type.getDeclaredField("value");
            if (field.getDeclaredAnnotation(Visible.class) == null
                    || field.getDeclaredAnnotation(Invisible.class) != null) {
                throw new AssertionError("field retention");
            }
            java.lang.reflect.Method method = type.getDeclaredMethod("annotated", String.class);
            if (method.getDeclaredAnnotation(Visible.class) == null
                    || method.getDeclaredAnnotation(Invisible.class) != null) {
                throw new AssertionError("method retention");
            }
            if (method.getParameterAnnotations()[0].length != 1
                    || method.getParameterAnnotations()[0][0].annotationType() != Visible.class) {
                throw new AssertionError("visible parameter annotation");
            }
            if (method.getAnnotatedParameterTypes()[0].getDeclaredAnnotation(VisibleType.class) == null
                    || method.getAnnotatedParameterTypes()[0].getDeclaredAnnotation(InvisibleType.class) != null) {
                throw new AssertionError("parameter type annotation");
            }
            if (method.getAnnotatedReturnType().getDeclaredAnnotation(VisibleType.class) == null) {
                throw new AssertionError("return type annotation");
            }
            if (method.getExceptionTypes().length != 2
                    || method.getExceptionTypes()[0] != java.io.IOException.class
                    || method.getExceptionTypes()[1] != IllegalArgumentException.class) {
                throw new AssertionError("exceptions attribute");
            }
            if (!Integer.valueOf(7).equals(Visible.class.getMethod("count").getDefaultValue())
                    || !Boolean.TRUE.equals(Visible.class.getMethod("enabled").getDefaultValue())) {
                throw new AssertionError("annotation defaults");
            }
            System.out.println("metadata-probe");
        }
    }

    public static void main(String[] args) {
        System.out.println("metadata-fixture");
    }
}
