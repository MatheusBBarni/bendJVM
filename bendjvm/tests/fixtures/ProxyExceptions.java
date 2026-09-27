import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.lang.reflect.UndeclaredThrowableException;

interface CheckedCall {
    int call();
}

public class ProxyExceptions {
    public static void main(String[] args) throws Exception {
        InvocationHandler handler = new InvocationHandler() {
            public Object invoke(Object proxy, Method method, Object[] values) throws Throwable {
                throw new Exception("checked");
            }
        };
        CheckedCall call = (CheckedCall) Proxy.newProxyInstance(
            ProxyExceptions.class.getClassLoader(),
            new Class[] { CheckedCall.class },
            handler);
        try {
            call.call();
            System.out.println(false);
        } catch (UndeclaredThrowableException error) {
            System.out.println(error.getCause() instanceof Exception);
            System.out.println(error.getUndeclaredThrowable() instanceof Exception);
        }
    }
}
