package fixture.container;

@ReflectiveContainer.Component("configured")
public class ConfiguredComponent implements ReflectiveContainer.Service {
    @ReflectiveContainer.Inject
    private int base;
    private int started;

    public ConfiguredComponent() {}

    @ReflectiveContainer.Start
    public void start() { started = 2; }

    public int run(int delta) { return base + delta + started; }

    public void fail() {
        throwUnchecked(new Exception("target-failure"));
    }

    @SuppressWarnings("unchecked")
    private static <T extends Throwable> void throwUnchecked(Throwable error) throws T {
        throw (T) error;
    }
}
