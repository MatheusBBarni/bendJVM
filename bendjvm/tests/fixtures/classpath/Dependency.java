package fixture.packaged.dependency;

public class Dependency {
    public static String value() {
        return TransitiveHelper.value();
    }
}
