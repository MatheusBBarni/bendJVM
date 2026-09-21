public class Exceptions {
    static int safeDivide(int numerator, int denominator) {
        try {
            return numerator / denominator;
        } catch (ArithmeticException error) {
            return 0;
        }
    }

    public static void main(String[] args) {
        System.out.println(safeDivide(20, 4));
        System.out.println(safeDivide(20, 0));
    }
}
