public class ArrayCopy {
    public static void main(String[] args) {
        int[] src = new int[] { 1, 2, 3, 4 };
        int[] dest = new int[4];
        System.arraycopy(src, 0, dest, 0, 4);
        System.out.println(dest[0]);
        System.out.println(dest[3]);
        System.arraycopy(src, 0, src, 1, 3);
        System.out.println(src[1]);
        System.arraycopy(src, 1, src, 0, 3);
        System.out.println(src[0]);
    }
}
