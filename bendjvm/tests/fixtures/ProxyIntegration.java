import java.io.IOException;
import java.lang.reflect.UndeclaredThrowableException;
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

interface WideText { Object text(); }
interface NarrowText { String text(); }
interface IntegerConflict { Integer conflict(); }
interface StringConflict { String conflict(); }
interface VoidCall { void run(); }
interface DeclaredFailure { void fail() throws IOException; }
interface BroadFailure { void failDuplicate() throws Exception; }
interface NarrowFailure { void failDuplicate() throws IOException; }
public class ProxyIntegration {
    public static void main(String[] args) throws Exception {
        final Object[] calls = new Object[] { Integer.valueOf(0) };
        final boolean[] zeroArguments = new boolean[] { true };
        InvocationHandler handler = new InvocationHandler() {
            public Object invoke(Object proxy, Method method, Object[] values) {
                calls[0] = Integer.valueOf(((Integer) calls[0]).intValue() + 1);
                String name = method.getName();
                if ((name.equals("value") || name.equals("label")) && values != null) {
                    zeroArguments[0] = false;
                }
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
        System.out.println(zeroArguments[0]);
        System.out.println(Proxy.getProxyClass(loader,
            new Class[] { Numeric.class, Label.class, Service.class }) != value.getClass());
        try {
            Proxy.getProxyClass(loader, new Class[] { IntegerConflict.class, StringConflict.class });
            System.out.println(false);
        } catch (IllegalArgumentException error) {
            System.out.println(true);
        }
        Class<?> hidden = Class.forName("fixture.hidden.HiddenContract");
        Class<?> otherHidden = Class.forName("fixture.other.OtherHiddenContract");
        System.out.println(Proxy.getProxyClass(loader, new Class[] { hidden }) != null);
        try {
            Proxy.getProxyClass(loader, new Class[] { hidden, otherHidden });
            System.out.println(false);
        } catch (IllegalArgumentException error) {
            System.out.println(true);
        }
        try {
            Proxy.newProxyInstance(loader, new Class[] { Service.class }, null);
            System.out.println(false);
        } catch (NullPointerException error) {
            System.out.println(true);
        }
        Object covariant = Proxy.newProxyInstance(loader,
            new Class[] { WideText.class, NarrowText.class }, handler);
        System.out.println(((WideText) covariant).text());
        System.out.println(((NarrowText) covariant).text());
        VoidCall voidCall = (VoidCall) Proxy.newProxyInstance(loader,
            new Class[] { VoidCall.class }, handler);
        voidCall.run();
        System.out.println("void-ok");

        InvocationHandler nullHandler = new InvocationHandler() {
            public Object invoke(Object proxy, Method method, Object[] values) {
                return null;
            }
        };
        Service nullService = (Service) Proxy.newProxyInstance(loader,
            new Class[] { Service.class }, nullHandler);
        try {
            nullService.value();
            System.out.println(false);
        } catch (NullPointerException error) {
            System.out.println(true);
        }
        InvocationHandler wrongHandler = new InvocationHandler() {
            public Object invoke(Object proxy, Method method, Object[] values) {
                return "wrong";
            }
        };
        Service wrongService = (Service) Proxy.newProxyInstance(loader,
            new Class[] { Service.class }, wrongHandler);
        try {
            wrongService.value();
            System.out.println(false);
        } catch (ClassCastException error) {
            System.out.println(true);
        }
        DeclaredFailure declared = (DeclaredFailure) Proxy.newProxyInstance(loader,
            new Class[] { DeclaredFailure.class }, new InvocationHandler() {
                public Object invoke(Object proxy, Method method, Object[] values)
                        throws Throwable {
                    throw new IOException("declared");
                }
            });
        try {
            declared.fail();
            System.out.println(false);
        } catch (IOException error) {
            System.out.println(true);
        }
        final boolean[] firstDeclaration = new boolean[] { true };
        Object duplicateFailure = Proxy.newProxyInstance(loader,
            new Class[] { BroadFailure.class, NarrowFailure.class },
            new InvocationHandler() {
                public Object invoke(Object proxy, Method method, Object[] values)
                        throws Throwable {
                    if (method.getDeclaringClass() != BroadFailure.class)
                        firstDeclaration[0] = false;
                    throw new Exception("too broad");
                }
            });
        try {
            ((BroadFailure) duplicateFailure).failDuplicate();
            System.out.println(false);
        } catch (UndeclaredThrowableException error) {
            System.out.println(error.getUndeclaredThrowable() instanceof Exception);
        } catch (Exception error) {
            System.out.println(false);
        }
        try {
            ((NarrowFailure) duplicateFailure).failDuplicate();
            System.out.println(false);
        } catch (UndeclaredThrowableException error) {
            System.out.println(error.getUndeclaredThrowable() instanceof Exception);
        } catch (Exception error) {
            System.out.println(false);
        }
        System.out.println(firstDeclaration[0]);
    }
}
