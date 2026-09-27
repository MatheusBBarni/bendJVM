import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

@Retention(RetentionPolicy.RUNTIME)
@interface LevelMark {
    Level value();
}

enum Level {
    LOW,
    HIGH
}

@LevelMark(Level.HIGH)
class EnumAnnotated {
}

public class EnumAnnotation {
    public static void main(String[] args) {
        Level first = EnumAnnotated.class.getAnnotation(LevelMark.class).value();
        Level second = EnumAnnotated.class.getAnnotation(LevelMark.class).value();
        System.out.println(first == second);
        System.out.println(first.name());
        System.out.println(first.ordinal());
    }
}
