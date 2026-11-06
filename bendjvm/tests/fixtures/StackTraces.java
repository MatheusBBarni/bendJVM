// Stack traces printed like the JDK's printStackTrace (plan 05). Compiled with
// debug information so frames show source files and line numbers.
public class StackTraces {
    static class Failure extends RuntimeException {
        Failure(String message, Throwable cause) {
            super(message, cause);
        }
    }

    static class Resource implements AutoCloseable {
        public void close() {
            throw new IllegalStateException("close failed");
        }
    }

    static int divide(int a, int b) {
        return a / b;
    }

    static void level2() {
        divide(1, 0);
    }

    static void level1() {
        try {
            level2();
        } catch (ArithmeticException e) {
            throw new Failure("wrapped", e);
        }
    }

    static Exception made() {
        return new UnsupportedOperationException("created here");
    }

    static void withResource() throws Exception {
        try (Resource r = new Resource()) {
            throw new Exception("body failed");
        }
    }

    public static void main(String[] args) throws Exception {
        try {
            level1();
        } catch (Failure e) {
            e.printStackTrace(System.out);
        }
        Exception early = made();
        try {
            throw early;
        } catch (Exception e) {
            e.printStackTrace(System.out);
        }
        try {
            withResource();
        } catch (Exception e) {
            e.printStackTrace(System.out);
        }
        new StackTraces().instance();
    }

    void instance() {
        throw new IllegalArgumentException("uncaught from " + getClass().getName());
    }
}
