package sun.misc;

import java.io.PrintStream;

/**
 * Throwable.printStackTrace for BendJVM. Each throwable records its creation
 * stack in the VM; {@link #frames} renders it ("Owner.method(File.java:line)",
 * innermost first) and this class prints it in the JDK's layout: frames shared
 * with the enclosing trace become "... n more", followed by suppressed
 * exceptions and the cause chain.
 */
public final class BendStackTrace {
    private BendStackTrace() {
    }

    static native String[] frames(Throwable t);

    public static void print(Throwable t, PrintStream s) {
        Throwable[] seen = new Throwable[] {t};
        s.println(t);
        String[] trace = frames(t);
        for (String frame : trace) {
            s.println("\tat " + frame);
        }
        seen = printRelated(t, s, trace, "", seen);
    }

    private static Throwable[] printRelated(Throwable t, PrintStream s, String[] trace, String prefix, Throwable[] seen) {
        for (Throwable suppressed : t.getSuppressed()) {
            seen = printEnclosed(suppressed, s, trace, "Suppressed: ", prefix + "\t", seen);
        }
        Throwable cause = t.getCause();
        if (cause != null) {
            seen = printEnclosed(cause, s, trace, "Caused by: ", prefix, seen);
        }
        return seen;
    }

    private static Throwable[] printEnclosed(Throwable t, PrintStream s, String[] enclosing, String caption, String prefix, Throwable[] seen) {
        for (Throwable earlier : seen) {
            if (earlier == t) {
                s.println(prefix + caption + "[CIRCULAR REFERENCE:" + t + "]");
                return seen;
            }
        }
        Throwable[] grown = new Throwable[seen.length + 1];
        System.arraycopy(seen, 0, grown, 0, seen.length);
        grown[seen.length] = t;
        String[] trace = frames(t);
        int m = trace.length - 1;
        int n = enclosing.length - 1;
        while (m >= 0 && n >= 0 && trace[m].equals(enclosing[n])) {
            m--;
            n--;
        }
        int inCommon = trace.length - 1 - m;
        s.println(prefix + caption + t);
        for (int i = 0; i <= m; i++) {
            s.println(prefix + "\tat " + trace[i]);
        }
        if (inCommon != 0) {
            s.println(prefix + "\t... " + inCommon + " more");
        }
        return printRelated(t, s, trace, prefix, grown);
    }

    // main() ended with an exception and java.lang.Thread is not loaded: the
    // JDK's default report. True once printed.
    static boolean mainUncaught(Throwable e) {
        try {
            System.err.print("Exception in thread \"main\" ");
            print(e, System.err);
            return true;
        } catch (Throwable failed) {
            return false;
        }
    }
}
