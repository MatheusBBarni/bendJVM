public class FloatOperations {
    static void calculate(float a, float b) {
        System.out.println(a + b); System.out.println(a - b);
        System.out.println(a * b); System.out.println(a / b);
        System.out.println(a % b); System.out.println(-a);
        System.out.println(a < b); System.out.println(a >= b);
        System.out.println((int) a);
    }
    public static void main(String[] args) {
        calculate(7.5f, 2.0f); calculate(-7.5f, 2.0f);
        int n = -13; System.out.println((float) n);
    }
}
