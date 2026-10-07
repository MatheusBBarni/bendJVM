package fixture.container;

import java.io.InputStream;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.lang.reflect.UndeclaredThrowableException;
import java.net.URL;
import java.util.Enumeration;
import java.util.Properties;

public class ReflectiveContainer {
    @Retention(RetentionPolicy.RUNTIME)
    public @interface Component { String value(); }
    @Retention(RetentionPolicy.RUNTIME)
    public @interface Inject {}
    @Retention(RetentionPolicy.RUNTIME)
    public @interface Start {}
    public interface Service {
        int run(int delta);
        void fail();
    }

    public static void main(String[] args) throws Exception {
        Enumeration<URL> resources = ClassLoader.getSystemResources("components.properties");
        int count = 0;
        while (resources.hasMoreElements()) {
            Properties config = new Properties();
            InputStream stream = resources.nextElement().openStream();
            try {
                config.load(stream);
            } finally {
                stream.close();
            }
            try {
                stream.read();
                throw new AssertionError("resource remains open");
            } catch (java.io.IOException closed) {
                System.out.println("closed");
            }
            Class<?> type = Class.forName(config.getProperty("component"), false,
                ReflectiveContainer.class.getClassLoader());
            System.out.println(type.getAnnotation(Component.class).value());
            final Object target = type.getConstructor().newInstance();
            for (Field field : type.getDeclaredFields()) {
                if (field.isAnnotationPresent(Inject.class)) {
                    field.setAccessible(true);
                    field.setInt(target, Integer.parseInt(config.getProperty("base")));
                }
            }
            for (Method method : type.getDeclaredMethods()) {
                if (method.isAnnotationPresent(Start.class)) method.invoke(target);
            }
            final Throwable[] failure = new Throwable[1];
            InvocationHandler handler = new InvocationHandler() {
                public Object invoke(Object proxy, Method method, Object[] values) throws Throwable {
                    try {
                        Object result = method.invoke(target, values);
                        if (method.getName().equals("run")) {
                            return Integer.valueOf(((Integer) result).intValue() + 1);
                        }
                        return result;
                    } catch (InvocationTargetException wrapped) {
                        failure[0] = wrapped.getTargetException();
                        throw wrapped.getCause();
                    }
                }
            };
            Service service = (Service) Proxy.newProxyInstance(type.getClassLoader(),
                new Class[] { Service.class }, handler);
            System.out.println(service.run(3));
            try {
                service.fail();
                throw new AssertionError("target failure lost");
            } catch (UndeclaredThrowableException wrapped) {
                System.out.println(wrapped.getCause() == failure[0]);
                System.out.println(wrapped.getUndeclaredThrowable().getMessage());
            }
            count++;
        }
        System.out.println(count);
    }
}
