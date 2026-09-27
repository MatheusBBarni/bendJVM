import java.lang.annotation.Inherited;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

@Inherited
@Retention(RetentionPolicy.RUNTIME)
@interface InheritedMarker {
    String value();
}

@InheritedMarker("base")
class InheritedBase {
}

class InheritedMiddle extends InheritedBase {
}

class InheritedLeaf extends InheritedMiddle {
}

@InheritedMarker("interface")
interface AnnotatedInterface {
}

class ImplementsAnnotatedInterface implements AnnotatedInterface {
}

public class InheritedAnnotation {
    public static void main(String[] args) {
        InheritedMarker inherited = InheritedLeaf.class.getAnnotation(InheritedMarker.class);
        System.out.println(inherited != null);
        System.out.println(inherited.value());
        System.out.println(InheritedLeaf.class.isAnnotationPresent(InheritedMarker.class));
        System.out.println(InheritedMiddle.class.getAnnotation(InheritedMarker.class) != null);
        System.out.println(InheritedBase.class.getDeclaredAnnotation(InheritedMarker.class) != null);
        System.out.println(AnnotatedInterface.class.getAnnotation(InheritedMarker.class) != null);
        System.out.println(ImplementsAnnotatedInterface.class.getAnnotation(InheritedMarker.class) == null);
        System.out.println(ImplementsAnnotatedInterface.class.isAnnotationPresent(InheritedMarker.class));
    }
}
