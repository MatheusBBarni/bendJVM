// Comparable.compareTo for String and the primitive wrappers, plus the static
// compare methods, including NaN, signed zero, overflow-prone differences, and
// the bridge's NullPointerException/ClassCastException.
public class ComparableValues {
    @SuppressWarnings({"rawtypes", "unchecked"})
    static int viaInterface(Comparable left, Object right) { return left.compareTo(right); }

    public static void main(String[] args) {
        System.out.println("apple".compareTo("apricot") + " " + "abc".compareTo("ab") + " " + "".compareTo("x") + " " + "same".compareTo("same"));
        System.out.println(Integer.valueOf(Integer.MIN_VALUE).compareTo(Integer.MAX_VALUE) + " " + Integer.valueOf(5).compareTo(5) + " " + Integer.compare(7, -7));
        System.out.println(Long.valueOf(Long.MIN_VALUE).compareTo(Long.MAX_VALUE) + " " + Long.compare(1L << 40, 1L << 41) + " " + Long.valueOf(3).compareTo(3L));
        System.out.println(Short.valueOf((short) -300).compareTo((short) 200) + " " + Byte.valueOf((byte) 100).compareTo((byte) -100) + " " + Character.valueOf('z').compareTo('a'));
        System.out.println(Boolean.TRUE.compareTo(false) + " " + Boolean.FALSE.compareTo(true) + " " + Boolean.TRUE.compareTo(true));
        System.out.println(Double.compare(0.0, -0.0) + " " + Double.compare(Double.NaN, Double.POSITIVE_INFINITY) + " " + Double.compare(Double.NaN, Double.NaN) + " " + Double.valueOf(-1.5).compareTo(2.5));
        System.out.println(Float.compare(-0.0f, 0.0f) + " " + Float.compare(Float.NaN, 1f) + " " + Float.valueOf(Float.NEGATIVE_INFINITY).compareTo(-1e30f) + " " + Float.compare(2f, 2f));
        System.out.println(viaInterface("b", "a") + " " + viaInterface(Integer.valueOf(1), Integer.valueOf(2)) + " " + viaInterface(Double.valueOf(1), Double.valueOf(1)));
        Object text = "x";
        System.out.println((text instanceof Comparable) + " " + (Integer.valueOf(1) instanceof Comparable));
        try { viaInterface(Integer.valueOf(1), "one"); } catch (ClassCastException e) { System.out.println("CCE"); }
        try { viaInterface("a", null); } catch (NullPointerException e) { System.out.println("NPE"); }
    }
}
