public class Branching {
    static int compare(int a, int b) {
        if (a == b) return 0;
        if (a < b) return -1;
        return 1;
    }
    public static void main(String[] args) {
        System.out.println(compare(3, 3)); System.out.println(compare(-2, 4));
        System.out.println(compare(7, -1));
        int x = -1;
        System.out.println(x <= 0); System.out.println(x >= 0);
        System.out.println(x != 0); System.out.println(x > 0);
    }
}
