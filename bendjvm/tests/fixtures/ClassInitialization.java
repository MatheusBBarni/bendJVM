public class ClassInitialization {
    static int count;
    static int initialize() { count++; System.out.println(10); return 17; }
    static int value = initialize();
    public static void main(String[] args) {
        System.out.println(value); System.out.println(count);
        System.out.println(InitChild.value); System.out.println(InitChild.value);
        System.out.println(InitParent.value);
    }
}
class InitParent {
    static int initialize() { System.out.println(20); return 23; }
    static int value = initialize();
}
class InitChild extends InitParent {
    static int initialize() { System.out.println(30); return InitParent.value + 6; }
    static int value = initialize();
}
