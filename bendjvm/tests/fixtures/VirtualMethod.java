public class VirtualMethod {
    int value() { return 11; }
    public static void main(String[] args) {
        VirtualMethod a = new VirtualMethod(), b = new VirtualChild();
        System.out.println(a.value()); System.out.println(b.value());
    }
}
class VirtualChild extends VirtualMethod { int value() { return 37; } }
