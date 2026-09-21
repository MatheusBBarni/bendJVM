public class ArithmeticAndBranches {
    static int sumTo(int limit) {
        int sum = 0;
        for (int value = 1; value <= limit; value++) {
            sum += value;
        }
        return sum;
    }

    static int factorial(int value) {
        int product = 1;
        while (value > 0) {
            product *= value;
            value -= 1;
        }
        return product;
    }

    public static void main(String[] args) {
        int left = 7;
        int right = 5;
        System.out.println(left * right + left - right);
        System.out.println(sumTo(10));
        System.out.println(factorial(4));
        System.out.println(left > right);
    }
}
