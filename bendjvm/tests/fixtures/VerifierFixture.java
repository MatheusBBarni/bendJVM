public final class VerifierFixture {
    interface PublicContract {
        long apply(long value);
    }

    static final class Implementation implements PublicContract {
        public long apply(long value) { return value + 3L; }
    }

    static final class AlternateImplementation implements PublicContract {
        public long apply(long value) { return value + 5L; }
    }

    static long interfaceMerge(boolean chooseFirst) {
        PublicContract contract;
        if (chooseFirst) contract = new Implementation();
        else contract = new AlternateImplementation();
        return contract.apply(9L);
    }

    static int arrayMerge(boolean chooseString) {
        Object[] values;
        if (chooseString) values = new String[] { "array" };
        else values = new Integer[] { 42 };
        return values[0].toString().length() + values.length;
    }

    static int unusableLocalMerge(boolean initialize) {
        int value;
        if (initialize) value = 7;
        return 11;
    }

    public static void main(String[] args) {
        PublicContract contract = new Implementation();
        System.out.println(contract.apply(9L));
        System.out.println(interfaceMerge(true));
        System.out.println(interfaceMerge(false));
        System.out.println(arrayMerge(true));
        System.out.println(arrayMerge(false));
        System.out.println(unusableLocalMerge(true));
        System.out.println(unusableLocalMerge(false));
    }
}
