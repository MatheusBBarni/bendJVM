// Array classes, instanceof/checkcast on array types, multianewarray, and array
// store/size exceptions (JVMS 6.5).
public class ArraySemantics {
    public static void main(String[] a) {
        Object s = new String[2];
        System.out.println(s.getClass().getName());
        Object n = new int[2][];
        System.out.println(n.getClass().getName());
        System.out.println((s instanceof Object[]) + " " + (s instanceof String[]) + " " + (n instanceof Object[]) + " " + (n instanceof int[][]) + " " + (s instanceof Integer[]));
        Object[] objs = new Integer[1];
        System.out.println(objs.getClass().getComponentType().getName());
        int[][] grid = new int[2][3];
        grid[1][2] = 7;
        System.out.println(grid.length + " " + grid[1].length + " " + grid[1][2] + " " + grid.getClass().getName() + " " + grid[0].getClass().getName());
        String[][][] cube = new String[2][0][4];
        System.out.println(cube.length + " " + cube[1].length + " " + cube.getClass().getName());
        long[][] longs = new long[1][2];
        System.out.println(longs[0][1] + " " + int[][].class.getName() + " " + String[][].class.getName() + " " + int[][].class.getComponentType().getName());
        try { objs[0] = "x"; } catch (ArrayStoreException e) { System.out.println("ASE"); }
        try { Object bad = new int[-1][2]; } catch (NegativeArraySizeException e) { System.out.println("NASE"); }
        Object o = grid;
        try { String[][] wrong = (String[][]) o; } catch (ClassCastException e) { System.out.println("CCE"); }
    }
}
