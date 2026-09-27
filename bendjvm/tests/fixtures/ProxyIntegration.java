import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

interface Service {
    int value();
}

interface Label {
    String label();
}
interface Numeric {
    int add(int value);
}

public class ProxyIntegration {
    public static void main(String[] args) {
        final Object[] calls = new Object[] { Integer.valueOf(0) };
        InvocationHandler handler = new InvocationHandler() {
            public Object invoke(Object proxy, Method method, Object[] values) {
                calls[0] = Integer.valueOf(((Integer) calls[0]).intValue() + 1);
                String name = method.getName();
                if (name.equals("value")) {
                    return Integer.valueOf(5);
                }
                if (name.equals("add")) {
                    return Integer.valueOf(((Integer) values[0]).intValue() + 1);
                }
                if (name.equals("equals")) {
                    return Boolean.valueOf(values[0] == proxy);
                }
                if (name.equals("hashCode")) {
                    return Integer.valueOf(17);
                }
                return "proxy";
            }
        };
        ClassLoader loader = ProxyIntegration.class.getClassLoader();
        Class[] interfaces = new Class[] { Service.class, Label.class, Numeric.class };
        try {
            Proxy.getProxyClass(loader, new Class[] { Service.class, Service.class });
            System.out.println(false);
        } catch (IllegalArgumentException error) {
            System.out.println(true);
        }
        try {
            Proxy.getProxyClass(loader, new Class[] { Object.class });
            System.out.println(false);
        } catch (IllegalArgumentException error) {
            System.out.println(true);
        }
        Object value = Proxy.newProxyInstance(loader, interfaces, handler);
        System.out.println(value.getClass() == Proxy.getProxyClass(loader, new Class[] { Service.class, Label.class, Numeric.class }));
        System.out.println(value.getClass().getSuperclass() == Proxy.class);
        System.out.println(value.getClass().getInterfaces().length);
        Service service = (Service) value;
        Label label = (Label) value;
        Numeric numeric = (Numeric) value;
        System.out.println(Service.class.isAssignableFrom(value.getClass()));
        System.out.println(Proxy.class.isAssignableFrom(value.getClass()));
        System.out.println(Proxy.isProxyClass(value.getClass()));
        System.out.println(service.value());
        System.out.println(label.label());
        System.out.println(numeric.add(4));
        System.out.println(value.equals(value));
        System.out.println(value.toString());
        System.out.println(Proxy.getInvocationHandler(value) == handler);
        System.out.println(((Integer) calls[0]).intValue());
    }
}
