import java.lang.reflect.Field;
import java.lang.reflect.Method;

class HiddenTarget {
    private int secret = 41;

    private int hidden(int delta) {
        return secret + delta;
    }
}

public class ReflectionAccess {
    public static void main(String[] args) throws Exception {
        HiddenTarget target = new HiddenTarget();
        Field field = HiddenTarget.class.getDeclaredField("secret");
        try {
            field.getInt(target);
            System.out.println("field-fail");
        } catch (IllegalAccessException error) {
            System.out.println("field-denied");
        }
        field.setAccessible(true);
        System.out.println(field.getInt(target));

        Method method = HiddenTarget.class.getDeclaredMethod("hidden", new Class<?>[] {int.class});
        try {
            method.invoke(target, new Object[] {Integer.valueOf(1)});
            System.out.println("method-fail");
        } catch (IllegalAccessException error) {
            System.out.println("method-denied");
        }
        method.setAccessible(true);
        System.out.println(((Integer) method.invoke(target, new Object[] {Integer.valueOf(1)})).intValue());
    }
}
