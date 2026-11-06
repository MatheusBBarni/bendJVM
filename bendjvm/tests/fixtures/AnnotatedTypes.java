import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;
import java.lang.reflect.AnnotatedArrayType;
import java.lang.reflect.AnnotatedParameterizedType;
import java.lang.reflect.AnnotatedType;
import java.lang.reflect.AnnotatedTypeVariable;
import java.lang.reflect.AnnotatedWildcardType;
import java.lang.reflect.Method;
import java.lang.reflect.TypeVariable;
import java.util.List;
import java.util.Map;

// Type-use and type-parameter annotations through the AnnotatedType interfaces.
public class AnnotatedTypes {
    @Retention(RetentionPolicy.RUNTIME)
    @Target({ElementType.TYPE_USE, ElementType.TYPE_PARAMETER})
    @interface Tag {
        String value();
    }

    static class Holder<@Tag("param") T extends @Tag("bound") Comparable<T>> {
        @Tag("field") String plain;
        List<@Tag("element") String> list;
        @Tag("array") String @Tag("dims") [] array;
        Map<@Tag("key") String, ? extends @Tag("upper") Number> wild;
        @Tag("variable") T variable;

        <@Tag("method-param") M> @Tag("returned") M pick(@Tag("arg") M value, List<? super @Tag("lower") Integer> sink) {
            return value;
        }
    }

    static String kind(AnnotatedType type) {
        String kind = type instanceof AnnotatedParameterizedType ? "parameterized"
            : type instanceof AnnotatedArrayType ? "array"
            : type instanceof AnnotatedTypeVariable ? "variable"
            : type instanceof AnnotatedWildcardType ? "wildcard" : "plain";
        return kind + " " + type.getType().getTypeName() + " " + tags(type);
    }

    static String tags(AnnotatedType type) {
        StringBuilder text = new StringBuilder("[");
        for (java.lang.annotation.Annotation annotation : type.getAnnotations()) {
            if (text.length() > 1) {
                text.append(", ");
            }
            text.append(((Tag) annotation).value());
        }
        return text.append("]").toString();
    }

    public static void main(String[] args) throws Exception {
        Class<?> holder = Holder.class;
        System.out.println(kind(holder.getDeclaredField("plain").getAnnotatedType()));
        AnnotatedType list = holder.getDeclaredField("list").getAnnotatedType();
        System.out.println(kind(list));
        System.out.println(kind(((AnnotatedParameterizedType) list).getAnnotatedActualTypeArguments()[0]));
        AnnotatedType array = holder.getDeclaredField("array").getAnnotatedType();
        System.out.println(kind(array));
        System.out.println(kind(((AnnotatedArrayType) array).getAnnotatedGenericComponentType()));
        AnnotatedType wild = holder.getDeclaredField("wild").getAnnotatedType();
        AnnotatedType[] wildArgs = ((AnnotatedParameterizedType) wild).getAnnotatedActualTypeArguments();
        System.out.println(kind(wildArgs[0]) + " / " + kind(wildArgs[1]));
        AnnotatedWildcardType upper = (AnnotatedWildcardType) wildArgs[1];
        System.out.println(kind(upper.getAnnotatedUpperBounds()[0]) + " " + upper.getAnnotatedLowerBounds().length);
        AnnotatedType variable = holder.getDeclaredField("variable").getAnnotatedType();
        System.out.println(kind(variable));
        System.out.println(kind(((AnnotatedTypeVariable) variable).getAnnotatedBounds()[0]));

        TypeVariable<?> parameter = holder.getTypeParameters()[0];
        System.out.println(parameter.getName() + " " + ((Tag) parameter.getAnnotation(Tag.class)).value() + " " + parameter.getAnnotations().length);
        System.out.println(kind(parameter.getAnnotatedBounds()[0]));

        Method pick = null;
        for (Method method : holder.getDeclaredMethods()) {
            if (method.getName().equals("pick")) {
                pick = method;
            }
        }
        TypeVariable<Method> methodParameter = pick.getTypeParameters()[0];
        System.out.println(methodParameter.getName() + " " + methodParameter.getAnnotation(Tag.class).value() + " " + kind(methodParameter.getAnnotatedBounds()[0]));
        System.out.println(kind(pick.getAnnotatedReturnType()));
        AnnotatedType[] parameters = pick.getAnnotatedParameterTypes();
        System.out.println(kind(parameters[0]) + " / " + kind(parameters[1]));
        AnnotatedWildcardType lower = (AnnotatedWildcardType) ((AnnotatedParameterizedType) parameters[1]).getAnnotatedActualTypeArguments()[0];
        System.out.println(kind(lower.getAnnotatedLowerBounds()[0]) + " " + kind(lower.getAnnotatedUpperBounds()[0]));
        System.out.println(holder.getDeclaredField("plain").getAnnotatedType().getClass().getName());
        System.out.println(list.getClass().getName());
    }
}
