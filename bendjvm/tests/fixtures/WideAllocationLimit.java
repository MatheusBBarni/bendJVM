public final class WideAllocationLimit {
    public static void main(String[] args) {
        System.out.println("before-wide-array");
        long[][] retained = new long[128][];
        long total = 0;
        for (int i = 0; i < retained.length; i++) {
            retained[i] = new long[] { 0x1234567887654321L + i };
            total += retained[i][0];
        }
        System.out.println(total);
    }
}
