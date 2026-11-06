// An exception ending main goes to the default UncaughtExceptionHandler; the
// run still exits with status 1 (plan 05).
public class MainHandled {
    public static void main(String[] args) {
        Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
            public void uncaughtException(Thread t, Throwable e) {
                System.out.println("handled " + e.getMessage() + " in " + t.getName());
            }
        });
        System.out.println("main starts");
        throw new IllegalStateException("main failed");
    }
}
