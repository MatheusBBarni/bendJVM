package fixture.sub;

import fixture.target.CrossPackageTarget;
import java.lang.reflect.Field;

public class CrossPackageSubclass extends CrossPackageTarget {
    public static int readProtected(Object target) throws Exception {
        Field field = CrossPackageTarget.class.getDeclaredField("protectedValue");
        return field.getInt(target);
    }
}
