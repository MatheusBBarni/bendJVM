public class HeapLimit {
    public static void main(String[] args) {
        Object[] values = new Object[100];
        for (int i = 0; i < values.length; i++) values[i] = new Object();
        System.out.println(100);
    }
}
