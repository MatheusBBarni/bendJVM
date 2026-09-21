public class FloatArray {
    public static void main(String[] args) {
        float[] values = new float[3];
        System.out.println(values[1]);
        values[0] = 1.25f; values[1] = -2.5f; values[2] = values[0] * values[1];
        System.out.println(values.length);
        for (int i = 0; i < values.length; i++) System.out.println(values[i]);
    }
}
