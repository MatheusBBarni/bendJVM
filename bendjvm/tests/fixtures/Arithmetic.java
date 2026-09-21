public class Arithmetic {
    static void calculate(int a, int b) {
        System.out.println(a + b); System.out.println(a - b);
        System.out.println(a * b); System.out.println(a / b);
        System.out.println(a % b); System.out.println(-a);
        System.out.println(a & b); System.out.println(a | b);
        System.out.println(a ^ b); System.out.println(~a);
    }
    public static void main(String[] args) { calculate(23, 5); calculate(-23, 5); }
}
