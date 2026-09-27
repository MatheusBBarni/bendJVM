import java.io.ByteArrayInputStream;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.Properties;

@Retention(RetentionPolicy.RUNTIME)
@interface Component {
    String name() default "service";
}

@Component(name = "configured")
class ConfiguredService {
    public static int configured = 9;
    private int base;

    public ConfiguredService() {
    }

    public int run(int delta) {
        return base + delta;
    }

    private static Class<?> keepLoaded() {
        return ConfiguredService.class;
    }
}

interface ComponentApi {
    int value();
}

public class ReflectionIntegration {
    public static void main(String[] args) throws Exception {
        Properties config = new Properties();
        config.load(new ByteArrayInputStream(new byte[] {
            'c', 'o', 'm', 'p', 'o', 'n', 'e', 'n', 't', '=',
            'C', 'o', 'n', 'f', 'i', 'g', 'u', 'r', 'e', 'd', 'S', 'e', 'r', 'v', 'i', 'c', 'e', '\n'
        }));
        Class<?> component = Class.forName(config.getProperty("component"));
        Class<?> stringClass = Class.forName("java.lang.String", false, null);
        Class<?> loadedString = ClassLoader.getSystemClassLoader().loadClass("java.lang.String");
        Field configured = component.getDeclaredField("configured");
        System.out.println(configured.getInt(null));
        Component marker = component.getAnnotation(Component.class);
        Object instance = component.getDeclaredConstructor().newInstance();
        Field base = component.getDeclaredField("base");
        base.setAccessible(true);
        base.setInt(instance, 7);
        Method run = component.getDeclaredMethod("run", int.class);
        int answer = ((Integer) run.invoke(instance, Integer.valueOf(5))).intValue();
        InvocationHandler handler = new InvocationHandler() {
            public Object invoke(Object proxy, Method method, Object[] values) {
                return Integer.valueOf(11);
            }
        };
        ComponentApi api = (ComponentApi) Proxy.newProxyInstance(
            ReflectionIntegration.class.getClassLoader(),
            new Class[] { ComponentApi.class }, handler);
        System.out.println(marker.name());
        System.out.println(answer);
        System.out.println(api.value());
        System.out.println(ComponentApi.class.isInstance(api));
        System.out.println(Proxy.getInvocationHandler(api) == handler);
        System.out.println(stringClass == String.class);
        System.out.println(loadedString == String.class);
    }
}
