public class ObjectArray {
    int n;
    ObjectArray(int value) { n = value; }
    public static void main(String[] args) {
        ObjectArray[] values = new ObjectArray[3];
        System.out.println(values[1] == null);
        values[0] = new ObjectArray(9); values[2] = values[0];
        System.out.println(values.length); System.out.println(values[2].n);
        System.out.println(values[0] == values[2]);
    }
}
