import java.io.InputStream;
import java.lang.reflect.Field;

public final class BroaderJvmApp {
    interface WideFunction {
        long apply(long value, double adjustment);
    }

    static final class Holder {
        private long amount;

        Holder(long amount) {
            this.amount = amount;
        }
    }

    static int denseSwitch(int key) {
        switch (key) {
            case -2: return 20;
            case -1: return 10;
            case 0: return 0;
            case 1: return 11;
            case 2: return 22;
            default: return -99;
        }
    }

    static int sparseSwitch(int key) {
        switch (key) {
            case -1000: return 1;
            case -7: return 2;
            case 42: return 3;
            case 10000: return 4;
            default: return -1;
        }
    }

    public static void main(String[] args) throws Exception {
        Holder holder = new Holder(0x1234567887654321L);
        Field amount = Holder.class.getDeclaredField("amount");
        amount.setAccessible(true);
        amount.setLong(holder, amount.getLong(holder) + 1L);
        System.out.println(amount.getLong(holder));

        WideFunction function = (value, adjustment) -> value + (long) adjustment;
        System.out.println(function.apply(amount.getLong(holder), 2.75d));
        System.out.println(denseSwitch(-2));
        System.out.println(denseSwitch(9));
        System.out.println(sparseSwitch(-7));
        System.out.println(sparseSwitch(9));

        IndyConstant.main(new String[0]);

        InputStream resource = ClassLoader.getSystemResourceAsStream("broader-resource.bin");
        System.out.println(resource.read());
        resource.close();
    }
}
