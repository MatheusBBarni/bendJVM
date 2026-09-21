public class StaticInitialization {
    static int base = 6;
    static int doubled;

    static {
        doubled = base * 2;
    }

    public static void main(String[] args) {
        System.out.println(base);
        System.out.println(doubled);
    }
}
