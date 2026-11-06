public final class WideStackForms {
    static int dupValue(int value) { return value; }
    static int popValue(int value) { return value; }
    static int pop2Pair(int left, int right) { return left + right; }
    static long pop2Wide(long value) { return value; }
    static int dupX1(int left, int right) { return left + right; }
    static int dupX2Pair(int first, int second, int third) { return first + second + third; }
    static int dupX2Wide(long wide, int value) { return value; }
    static long dup2Wide(long value) { return value; }
    static int dup2Pair(int left, int right) { return left + right; }
    static int dup2X1Three(int first, int second, int third) { return first + second + third; }
    static long dup2X1Wide(int value, long wide) { return wide; }
    static int dup2X2Four(int first, int second, int third, int fourth) {
        return first + second + third + fourth;
    }
    static long dup2X2WideThenPair(long wide, int left, int right) { return wide; }
    static long dup2X2PairThenWide(int left, int right, long wide) { return wide; }
    static long dup2X2WidePair(long first, long second) { return first + second; }
    static int swap(int left, int right) { return left - right; }

    public static void main(String[] args) {
        System.out.println(dupValue(4));
        System.out.println(popValue(4));
        System.out.println(pop2Pair(1, 2));
        System.out.println(pop2Wide(0x1234567887654321L));
        System.out.println(dupX1(3, 4));
        System.out.println(dupX2Pair(1, 2, 9));
        System.out.println(dupX2Wide(0x1234567887654321L, 6));
        System.out.println(dup2Wide(0x2345678998765432L));
        System.out.println(dup2Pair(5, 6));
        System.out.println(dup2X1Three(2, 3, 4));
        System.out.println(dup2X1Wide(1, 22L));
        System.out.println(dup2X2Four(1, 2, 3, 4));
        System.out.println(dup2X2WideThenPair(0x3456789a98765432L, 8, 9));
        System.out.println(dup2X2PairThenWide(7, 8, 0x456789ab87654321L));
        System.out.println(dup2X2WidePair(0x1234567887654321L, 0x2345678998765432L));
        System.out.println(swap(10, 3));
    }
}
