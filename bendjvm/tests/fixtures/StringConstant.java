public class StringConstant {
    static String message() { return "Bend JVM"; }
    public static void main(String[] args) {
        System.out.println(message()); System.out.println("");
        System.out.println("same" == "same");
    }
}
