public class ObjectCreation {
    int value;
    ObjectCreation(int n) { value = n; }
    int read() { return value; }
    public static void main(String[] args) {
        ObjectCreation a = new ObjectCreation(13), b = new ObjectCreation(29);
        System.out.println(a.read()); System.out.println(b.read());
        System.out.println(a == b); System.out.println(a == a);
    }
}
