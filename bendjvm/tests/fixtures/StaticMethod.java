public class StaticMethod {
    static int square(int n) { return n * n; }
    static void emit(int n) { System.out.println(square(n)); }
    public static void main(String[] args) { emit(10); emit(-4); }
}
