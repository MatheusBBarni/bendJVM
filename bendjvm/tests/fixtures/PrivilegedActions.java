import java.io.IOException;
import java.security.AccessControlContext;
import java.security.AccessController;
import java.security.PrivilegedAction;
import java.security.PrivilegedActionException;
import java.security.PrivilegedExceptionAction;

public class PrivilegedActions {
    static final class Named implements PrivilegedAction<String> {
        public String run() {
            return "named-action";
        }
    }

    static final class Failing implements PrivilegedExceptionAction<Integer> {
        private final boolean checked;

        Failing(boolean checked) {
            this.checked = checked;
        }

        public Integer run() throws Exception {
            if (checked) {
                throw new IOException("checked-boom");
            }
            throw new IllegalStateException("unchecked-boom");
        }
    }

    public static void main(String[] args) throws Exception {
        System.out.println(System.getSecurityManager() == null);
        System.out.println(AccessController.doPrivileged(new Named()));
        String lambda = AccessController.doPrivileged((PrivilegedAction<String>) () -> "lambda-action");
        System.out.println(lambda);
        Integer value = AccessController.doPrivileged((PrivilegedExceptionAction<Integer>) () -> Integer.valueOf(42));
        System.out.println(value.intValue());
        AccessControlContext context = AccessController.getContext();
        System.out.println(context != null);
        System.out.println(AccessController.doPrivileged(new Named(), context));
        Object nullResult = AccessController.doPrivileged((PrivilegedAction<Object>) () -> null);
        System.out.println(nullResult == null);
        try {
            AccessController.doPrivileged(new Failing(true));
            System.out.println("checked-missed");
        } catch (PrivilegedActionException error) {
            Exception cause = error.getException();
            System.out.println(cause.getClass().getName() + " " + cause.getMessage());
            System.out.println(error.getCause() == cause);
            System.out.println(error.getMessage() == null);
        }
        try {
            AccessController.doPrivileged(new Failing(false), context);
            System.out.println("unchecked-missed");
        } catch (IllegalStateException error) {
            System.out.println("unchecked " + error.getMessage());
        }
        int depth = AccessController.doPrivileged((PrivilegedAction<Integer>) () ->
            AccessController.doPrivileged((PrivilegedAction<Integer>) () -> Integer.valueOf(7)));
        System.out.println(depth);
    }
}
