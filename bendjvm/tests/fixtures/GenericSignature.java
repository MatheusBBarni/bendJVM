import java.io.IOException;
import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.lang.reflect.AnnotatedParameterizedType;
import java.lang.reflect.AnnotatedType;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.ParameterizedType;
import java.util.ArrayList;
import java.util.List;
public class GenericSignature {
    @Retention(RetentionPolicy.RUNTIME)
    @Target(ElementType.TYPE_USE)
    @interface Mark {
        String value();
    }

    public static List<String> boxed(List<Integer> values) throws IOException {
        return null;
    }

    public static List<@Mark("arg") String> nested() {
        return null;
    }

    public static @Mark("ret") String plain() {
        return null;
    }

    public static <T> T id(T value) {
        return value;
    }

    public List<String> items;
    public List<@Mark("field") String> marked;

    static class Box<T> extends ArrayList<T> {
    }

    public static void main(String[] args) throws Exception {
        Method boxed = GenericSignature.class.getDeclaredMethod("boxed", List.class);
        System.out.println(boxed.getGenericReturnType().getTypeName());
        System.out.println(boxed.getGenericParameterTypes()[0].getTypeName());
        System.out.println(boxed.getGenericExceptionTypes()[0].getTypeName());
        System.out.println(boxed.getGenericReturnType() instanceof ParameterizedType);
        Method plain = GenericSignature.class.getDeclaredMethod("plain");
        System.out.println(plain.getGenericReturnType().getTypeName());
        System.out.println(plain.getAnnotatedReturnType().getAnnotation(Mark.class).value());
        Method nested = GenericSignature.class.getDeclaredMethod("nested");
        AnnotatedType returned = nested.getAnnotatedReturnType();
        System.out.println(returned.getAnnotation(Mark.class) == null);
        AnnotatedParameterizedType parameterized = (AnnotatedParameterizedType) returned;
        System.out.println(parameterized.getAnnotatedActualTypeArguments()[0].getAnnotation(Mark.class).value());
        System.out.println(returned.getType().getTypeName());
        Method identity = GenericSignature.class.getDeclaredMethod("id", Object.class);
        System.out.println(identity.getGenericReturnType().getTypeName());
        System.out.println(identity.getGenericParameterTypes()[0].getTypeName());
        System.out.println(GenericSignature.class.getDeclaredField("items").getGenericType().getTypeName());
        AnnotatedParameterizedType fieldType = (AnnotatedParameterizedType) GenericSignature.class.getDeclaredField("marked").getAnnotatedType();
        System.out.println(fieldType.getAnnotatedActualTypeArguments()[0].getAnnotation(Mark.class).value());
        System.out.println(Box.class.getGenericSuperclass().getTypeName());
    }
}
