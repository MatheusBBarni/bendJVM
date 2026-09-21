public class SignedArithmetic {
    static void edges(int min, int max, int minusOne) {
        System.out.println(max + 1); System.out.println(min - 1);
        System.out.println(-min); System.out.println(min / minusOne);
        System.out.println(min % minusOne); System.out.println(max * max);
        System.out.println(min < max); System.out.println(min > minusOne);
        System.out.println(-7 / 3); System.out.println(-7 % 3);
        System.out.println(7 / -3); System.out.println(7 % -3);
        int n = -7, d = 3;
        System.out.println(n / d); System.out.println(n % d);
        System.out.println(n >> 1); System.out.println(n >>> 1);
        System.out.println(n << 33); System.out.println(n >> -1);
        System.out.println(n >>> 32);
        System.out.println((byte) max); System.out.println((short) max); System.out.println((int) (char) min);
    }
    public static void main(String[] args) { edges(-2147483648, 2147483647, -1); }
}
