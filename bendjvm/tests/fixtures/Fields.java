public class Fields {
    static int shared;
    int value;
    Object reference;
    public static void main(String[] args) {
        Fields a = new Fields(), b = new Fields();
        System.out.println(a.value); System.out.println(a.reference == null);
        a.value = 9; b.value = 20; shared = a.value + b.value;
        System.out.println(a.value); System.out.println(b.value); System.out.println(shared);
        a.reference = b; System.out.println(a.reference == b);
    }
}
