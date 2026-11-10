public class GcIdentity {
    static int churned;

    static void churn() {
        for (int i = 0; i < 400; i++) {
            churned += new Object() == null ? 0 : 1;
        }
    }

    public static void main(String[] args) {
        String first = "same";
        churn();
        String second = "same";
        System.out.println(first == second);

        Integer boxed = Integer.valueOf(40);
        churn();
        System.out.println(boxed == Integer.valueOf(40));
        System.out.println(Integer.valueOf(1000) == Integer.valueOf(1000));

        Class<?> viaLiteral = String.class;
        churn();
        Object text = "dropped";
        Class<?> viaObject = text.getClass();
        churn();
        System.out.println(viaLiteral == viaObject);
        System.out.println(viaObject == String.class);
        System.out.println(churned);
    }
}
