import fixture.target.CrossPackageTarget;
import java.lang.reflect.Field;

public class CrossPackageReflection {
    private static void read(Class<?> type, Object target, String name) throws Exception {
        Field field = type.getDeclaredField(name);
        try {
            System.out.println(name + ":" + field.getInt(target));
        } catch (IllegalAccessException error) {
            System.out.println(name + ":denied");
        }
        field.setAccessible(true);
        try {
            System.out.println(name + ":" + field.getInt(target));
        } catch (IllegalAccessException error) {
            System.out.println(name + ":accessible-denied");
        }
    }

    public static void main(String[] args) throws Exception {
        Class<?> type = CrossPackageTarget.class;
        CrossPackageTarget target = new CrossPackageTarget();
        read(type, target, "secret");
        read(type, target, "packageValue");
        read(type, target, "protectedValue");
        read(type, target, "publicValue");
        Field finalField = type.getDeclaredField("STATIC_FINAL");
        finalField.setAccessible(true);
        try {
            finalField.setInt(null, 99);
            System.out.println("static-final:allowed");
        } catch (IllegalAccessException error) {
            System.out.println("static-final:denied");
        }
        System.out.println("same-class:" + CrossPackageTarget.selfRead());
    }
}
