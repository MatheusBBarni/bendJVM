public class MultipleArguments {
    static int combine(int a, int b, int c, int d, int e, int f) {
        return a - b * c + d / e - f;
    }
    int receiver(int a, int b, int c) { return a * 100 + b * 10 + c; }
    public static void main(String[] args) {
        System.out.println(combine(50, 3, 7, 24, 6, 2));
        System.out.println(new MultipleArguments().receiver(1, 2, 3));
    }
}
