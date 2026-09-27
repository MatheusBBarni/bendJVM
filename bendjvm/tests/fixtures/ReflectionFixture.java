import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

@Retention(RetentionPolicy.RUNTIME)
@interface Marker {}


class ReflectionParent {
    public int inherited = 4;

    public ReflectionParent() {}

    public int parentAnswer() {
        return inherited;
    }
}

@Marker
public class ReflectionFixture extends ReflectionParent {
    public int value = 7;

    public ReflectionFixture() {}

    public int answer(int delta) {
        return value + delta;
    }
    public int answer(String delta) {
        return value + delta.length();
    }

    public static void main(String[] args) throws Exception {
        Class<?> type = ReflectionFixture.class;
        System.out.println(type.isAnnotationPresent(Marker.class));
        Constructor<?> constructor = type.getDeclaredConstructor(new Class<?>[0]);
        ReflectionFixture target = (ReflectionFixture) constructor.newInstance(new Object[0]);
        Field field = type.getDeclaredField("value");
        field.setInt(target, 9);
        Method method = type.getDeclaredMethod("answer", new Class<?>[] {int.class});
        Method textMethod = type.getDeclaredMethod("answer", new Class<?>[] {String.class});
        Field inherited = type.getField("inherited");
        Method parentMethod = type.getMethod("parentAnswer", new Class<?>[0]);
        System.out.println(method.getParameterTypes()[0] == int.class);
        System.out.println(constructor.getParameterTypes().length);
        System.out.println(field.getInt(target));
        System.out.println(((Integer) method.invoke(target, new Object[] {Integer.valueOf(3)})).intValue());
        System.out.println(((Integer) textMethod.invoke(target, new Object[] {"x"})).intValue());
        System.out.println(inherited.getInt(target));
        System.out.println(((Integer) parentMethod.invoke(target, new Object[0])).intValue());
        System.out.println(type.isInstance(target));
        System.out.println(method.getDeclaringClass() == type);
        System.out.println(inherited.getDeclaringClass().getName());
        System.out.println(parentMethod.getDeclaringClass().getName());
    }
}
