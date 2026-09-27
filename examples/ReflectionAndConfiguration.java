import java.io.ByteArrayInputStream;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.Properties;

@Retention(RetentionPolicy.RUNTIME)
@interface ExampleMarker {}

@ExampleMarker
public class ReflectionAndConfiguration {
    private int value = 7;

    public int add(int delta) {
        return value + delta;
    }

    public int add(String text) {
        return value + text.length();
    }

    public static void main(String[] args) throws Exception {
        Class<?> type = ReflectionAndConfiguration.class;
        System.out.println(type.isAnnotationPresent(ExampleMarker.class));

        Constructor<?> constructor = type.getDeclaredConstructor();
        ReflectionAndConfiguration target =
            (ReflectionAndConfiguration) constructor.newInstance();
        Field field = type.getDeclaredField("value");
        field.setAccessible(true);
        field.setInt(target, 9);

        Method numeric = type.getDeclaredMethod("add", int.class);
        Method text = type.getDeclaredMethod("add", String.class);
        System.out.println(numeric.getParameterTypes()[0] == int.class);
        System.out.println(((Integer) numeric.invoke(target, Integer.valueOf(3))).intValue());
        System.out.println(((Integer) text.invoke(target, "!")).intValue());

        Properties properties = new Properties();
        properties.load(new ByteArrayInputStream(new byte[] {
            'n', 'a', 'm', 'e', '=', 'B', 'e', 'n', 'd', 'J', 'V', 'M', '\n'
        }));
        System.out.println(properties.getProperty("name"));
    }
}
