public class GcStrings {
    public static void main(String[] args) {
        String built = new StringBuilder("ab").append("c").toString();
        String literal = "abc";
        System.out.println(built == literal);
        System.out.println(built.equals(literal));
        System.out.println(built.intern() == literal);

        String joined = "ab".concat("c");
        System.out.println(joined.intern() == literal);

        String first = new StringBuilder("uniq").append(1).toString();
        String canonical = first.intern();
        System.out.println(canonical == first);
        System.out.println(new StringBuilder("uniq").append(1).toString().intern() == first);

        int length = 0;
        for (int i = 0; i < 1500; i++) {
            length += "x".concat(Integer.toString(i)).length();
            length += new StringBuilder().append(i).toString().length();
        }
        System.out.println(length);
    }
}
