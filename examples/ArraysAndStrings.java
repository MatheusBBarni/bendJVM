public class ArraysAndStrings {
    public static void main(String[] args) {
        int[] values = new int[] {3, 1, 4, 1, 5};
        int[] copy = new int[values.length];
        System.arraycopy(values, 0, copy, 0, values.length);
        int total = 0;
        for (int index = 0; index < copy.length; index++) {
            total += copy[index];
        }
        String text = "BendJVM";
        System.out.println("pi digits");
        System.out.println(total);
        System.out.println(copy[2] == 4);
        System.out.println(text.substring(0, 4));
    }
}
