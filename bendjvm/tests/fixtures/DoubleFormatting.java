public final class DoubleFormatting {
    // Deterministic 64-bit LCG (Knuth MMIX constants) so both JVMs format the same bit patterns.
    private static long state = 0x2545F4914F6CDD1DL;

    private static long nextBits() {
        state = state * 6364136223846793005L + 1442695040888963407L;
        return state;
    }

    public static void main(String[] args) {
        double[] edges = {
            0.0, -0.0, 1.0, -1.0, 0.5, 0.1, 0.001, 0.0001, 9999999.0, 1.0E7,
            123456.789, 1.0 / 3.0, 2.0 / 3.0, 100.0, 4.35, 2.0E-3, 1.0E-5,
            Double.MIN_VALUE, Double.MIN_NORMAL, Double.MAX_VALUE,
            Double.longBitsToDouble(0x000FFFFFFFFFFFFFL),
            Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, Double.NaN,
        };
        for (double value : edges) System.out.println(value);
        int printed = 0;
        while (printed < 48) {
            long bits = nextBits();
            if (((bits >>> 52) & 0x7FF) == 0x7FF) continue;
            System.out.println(Double.longBitsToDouble(bits));
            printed++;
        }
    }
}
