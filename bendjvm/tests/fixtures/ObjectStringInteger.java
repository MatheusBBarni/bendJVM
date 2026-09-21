public class ObjectStringInteger {
    public static void main(String[] args) {
        Object a = new Object();
        Object b = new Object();
        System.out.println(a.equals(a));
        System.out.println(a.equals(b));
        System.out.println(java.util.Objects.equals(null, null));
        System.out.println(java.util.Objects.requireNonNull(a) == a);
        String s = "Hello";
        System.out.println(s.length());
        System.out.println(s.isEmpty());
        System.out.println((int) s.charAt(1));
        System.out.println(s.substring(1, 4));
        System.out.println(s.concat("!"));
        System.out.println(String.valueOf(7));
        System.out.println(String.valueOf(true));
        System.out.println("ab".equals("ab"));
        Integer x = Integer.valueOf(40);
        Integer y = Integer.valueOf(40);
        System.out.println(x == y);
        System.out.println(x.intValue());
        System.out.println(Integer.parseInt("41"));
        System.out.println(x.equals(Integer.valueOf(40)));
        System.out.println(Math.abs(-3));
        System.out.println(Math.min(2, 9));
        System.out.println(Math.max(2, 9));
        StringBuilder sb = new StringBuilder("n");
        sb.append(1);
        System.out.println(sb.toString());
        System.out.println(sb.length());
    }
}
