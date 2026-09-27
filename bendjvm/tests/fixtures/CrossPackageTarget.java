package fixture.target;

import java.lang.reflect.Field;

public class CrossPackageTarget {
    private int secret = 41;
    int packageValue = 42;
    protected int protectedValue = 43;
    public int publicValue = 44;
    public static final int STATIC_FINAL = 45;

    public static int selfRead() throws Exception {
        Field field = CrossPackageTarget.class.getDeclaredField("secret");
        return field.getInt(new CrossPackageTarget());
    }
}
