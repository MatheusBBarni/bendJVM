public final class SwitchFixture {
    enum Choice { FIRST, SECOND, THIRD }

    static int defaultOnly(int key) {
        switch (key) {
            case 7: return 1;
            default: return 2;
        }
    }

    static int nested(int outer, int inner) {
        switch (outer) {
            case -2:
                switch (inner) {
                    case 3: return 23;
                    default: return 20;
                }
            case 4: return 40;
            default: return -1;
        }
    }

    static int backward(int count) {
        int total = 0;
        while (count > 0) {
            switch (count) {
                case 1: total += 10; break;
                case 2: total += 20; break;
                default: total += count;
            }
            count--;
        }
        return total;
    }

    static int text(String value) {
        switch (value) {
            case "alpha": return 1;
            case "beta": return 2;
            case "gamma": return 3;
            default: return -1;
        }
    }

    static int enumeration(Choice value) {
        switch (value) {
            case FIRST: return 11;
            case SECOND: return 22;
            case THIRD: return 33;
            default: return -1;
        }
    }

    static int guarded(int key) {
        try {
            switch (key) {
                case 0: throw new IllegalArgumentException();
                case 1: return 10;
                default: return 20;
            }
        } catch (IllegalArgumentException expected) {
            return -10;
        }
    }

    public static void main(String[] args) {
        System.out.println(defaultOnly(-1));
        System.out.println(defaultOnly(7));
        System.out.println(nested(-2, 3));
        System.out.println(nested(-2, 9));
        System.out.println(nested(4, 0));
        System.out.println(backward(4));
        System.out.println(text("beta"));
        System.out.println(text("other"));
        System.out.println(enumeration(Choice.SECOND));
        System.out.println(guarded(0));
        System.out.println(guarded(1));
    }
}
