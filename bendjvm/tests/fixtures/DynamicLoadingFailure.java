class LoadProbe {
    static {
        System.out.println("initialized");
    }
}

public class DynamicLoadingFailure {
    public static void main(String[] args) {
        try {
            Class.forName("missing.configuration.Type");
            System.out.println(false);
        } catch (ClassNotFoundException error) {
            System.out.println(true);
        }
        try {
            Class.forName("LoadProbe", false, DynamicLoadingFailure.class.getClassLoader());
            System.out.println("suppressed");
            Class.forName("LoadProbe", true, DynamicLoadingFailure.class.getClassLoader());
        } catch (ClassNotFoundException error) {
            System.out.println("missing");
        }
    }
}
