package fixture.access.base;

public class AccessRulesBase {
    private int privateValue = 1;
    int packageValue = 2;
    protected int protectedValue = 3;
    public int publicValue = 4;
    protected static int protectedStatic = 5;
    public final int finalValue;
    public static final Integer FINAL_STATIC = Integer.valueOf(15);
    private static int privateStatic = 16;

    public AccessRulesBase() {
        this.finalValue = 14;
    }

    protected AccessRulesBase(int seed) {
        this.publicValue = seed;
        this.finalValue = 14;
    }

    private static int privateStaticMethod() {
        return 70;
    }

    private int privateMethod() {
        return 10;
    }

    int packageMethod() {
        return 20;
    }

    protected int protectedMethod() {
        return 30;
    }

    public int publicMethod() {
        return 40;
    }

    protected static int protectedStaticMethod() {
        return 50;
    }

    public static Object packageOnly() {
        return new PackageOnly();
    }
}

class PackageOnly {
    public int visible = 6;

    public PackageOnly() {
    }

    public int visibleMethod() {
        return 60;
    }
}
