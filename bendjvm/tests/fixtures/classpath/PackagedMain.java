package fixture.packaged;

import fixture.packaged.dependency.Dependency;

public class PackagedMain {
    public static void main(String[] args) {
        System.out.println(Dependency.value());
    }
}
