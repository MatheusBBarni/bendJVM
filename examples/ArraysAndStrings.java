public class ArraysAndStrings {
    public static void main(String[] args) {
        int[] values = new int[] {3, 1, 4, 1, 5};
        int total = 0;
        for (int index = 0; index < values.length; index++) {
            total += values[index];
        }
        System.out.println("array total");
        System.out.println(total);
        System.out.println(values[2] == 4);
    }
}
