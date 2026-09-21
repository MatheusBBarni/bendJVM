public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("Hello from BendJVM");
        System.out.println(42);
        if (args.length > 0) {
            System.out.println("arg=" + args[0]);
        }
    }
}
