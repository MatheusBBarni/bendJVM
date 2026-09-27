import java.lang.annotation.Annotation;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Repeatable;

@Retention(RetentionPolicy.RUNTIME)
@Repeatable(Tags.class)
@interface Tag {
    String value();
}

@Retention(RetentionPolicy.RUNTIME)
@interface Tags {
    Tag[] value();
}

@Retention(RetentionPolicy.RUNTIME)
@interface NestedValue {
    String value();
}

@Retention(RetentionPolicy.RUNTIME)
@interface ComplexValue {
    int[] ints();
    NestedValue nested();
}

@ComplexValue(ints = {1, 2, 3}, nested = @NestedValue("nested"))

@Tag("a")
@Tag("b")
public class RepeatableAnnotation {
    @Tag("field")
    private int field;

    @Tag("method")
    public void method() {
    }

    public static void main(String[] args) {
        ComplexValue first = RepeatableAnnotation.class.getAnnotation(ComplexValue.class);
        ComplexValue second = RepeatableAnnotation.class.getAnnotation(ComplexValue.class);
        System.out.println(first.equals(second));
        System.out.println(first.hashCode() == second.hashCode());
        Tag[] classTags = RepeatableAnnotation.class.getAnnotationsByType(Tag.class);
        Tag[] declaredTags = RepeatableAnnotation.class.getDeclaredAnnotationsByType(Tag.class);
        Tag[] fieldTags = null;
        Tag[] methodTags = null;
        try {
            fieldTags = RepeatableAnnotation.class.getDeclaredField("field").getAnnotationsByType(Tag.class);
            methodTags = RepeatableAnnotation.class.getDeclaredMethod("method").getAnnotationsByType(Tag.class);
        } catch (Exception error) {
            System.out.println("lookup-error");
        }
        System.out.println(classTags.length);
        System.out.println(classTags[0].value());
        System.out.println(classTags[1].value());
        System.out.println(declaredTags.length);
        System.out.println(fieldTags.length);
        System.out.println(fieldTags[0].value());
        System.out.println(methodTags.length);
        System.out.println(methodTags[0].value());
        System.out.println(RepeatableAnnotation.class.getAnnotation(Tags.class) != null);
        System.out.println(RepeatableAnnotation.class.getAnnotation(Tag.class) == null);
        System.out.println(classTags != RepeatableAnnotation.class.getAnnotationsByType(Tag.class));
        Annotation[] all = RepeatableAnnotation.class.getDeclaredAnnotations();
        System.out.println(all.length);
    }
}
