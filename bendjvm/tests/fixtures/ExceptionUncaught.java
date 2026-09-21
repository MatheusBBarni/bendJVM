public class ExceptionUncaught {
    static int divide(int n) { return 7 / n; }
    public static void main(String[] args) {
        System.out.println(123); System.out.println(divide(0)); System.out.println(999);
    }
}
