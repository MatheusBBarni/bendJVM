public class ArithmeticAndBranches {
    static int sumTo(int limit) {
        int sum = 0;
        for (int value = 1; value <= limit; value++) {
            sum += value;
        }
        return sum;
    }

    public static void main(String[] args) {
        int left = 7;
        int right = 5;
        System.out.println(left * right + left - right);
        System.out.println(sumTo(10));
        System.out.println(left > right);
    }
}
