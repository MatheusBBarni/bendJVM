public class IntArray {
    public static void main(String[] args) {
        int[] values = new int[5];
        System.out.println(values[3]); System.out.println(values.length);
        for (int i = 0; i < values.length; i++) values[i] = i * i - 4;
        int sum = 0;
        for (int i = 0; i < values.length; i++) sum += values[i];
        System.out.println(sum); System.out.println(values[0]);
    }
}
