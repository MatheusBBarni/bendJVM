public class RuntimeExceptions {
    int value;
    int read() { return value; }
    public static void main(String[] args) {
        RuntimeExceptions missing = null;
        try { System.out.println(missing.value); } catch (NullPointerException e) { System.out.println(1); }
        try { missing.read(); } catch (NullPointerException e) { System.out.println(2); }
        int[] absent = null;
        try { System.out.println(absent.length); } catch (NullPointerException e) { System.out.println(3); }
        int[] values = new int[2];
        try { System.out.println(values[-1]); } catch (ArrayIndexOutOfBoundsException e) { System.out.println(4); }
        try { values[2] = 7; } catch (ArrayIndexOutOfBoundsException e) { System.out.println(5); }
        int size = -1;
        try { values = new int[size]; } catch (NegativeArraySizeException e) { System.out.println(6); }
        Object object = new Object();
        try { RuntimeExceptions wrong = (RuntimeExceptions) object; System.out.println(wrong.value); }
        catch (ClassCastException e) { System.out.println(7); }
        try { throw (RuntimeException) null; } catch (NullPointerException e) { System.out.println(8); }
        System.out.println(9);
    }
}
