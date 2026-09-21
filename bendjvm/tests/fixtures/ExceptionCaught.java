public class ExceptionCaught {
    static int divide(int n) { return 20 / n; }
    static void raise() { throw new RuntimeException("raised"); }
    public static void main(String[] args) {
        try { System.out.println(divide(0)); }
        catch (ArithmeticException e) { System.out.println(101); }
        try { raise(); }
        catch (Exception e) { System.out.println(202); }
        System.out.println(303);
    }
}
