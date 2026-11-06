# MiniJRE Java-source layer

Classes here are part of the BendJVM MiniJRE, written in Java and compiled with `javac --release 8` when the runner prepares its artifacts.
They execute as ordinary bytecode on the Bend interpreter.
Their `native` methods bind to Bend intrinsics registered in `bendjvm/loader/bootstrap.bend` (`signatures()`), so scheduler, monitor, and host state stay owned by Bend.

Rules for these sources:

- Use only classes the MiniJRE defines (the Bend bootstrap catalog or this directory); `javac` checks against the JDK 8 API, so a missing MiniJRE class only shows up at launch as `MissingClass`.
- Guard shared static state with `synchronized`; Java threads are preempted at any bytecode.
- Never depend on JDK internals; keep each class to the API subset documented in `bendjvm-spec.md`.
