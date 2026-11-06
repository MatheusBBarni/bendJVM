"""Deterministic Java 8 invokedynamic classfile fixtures and bootstrap support."""

from __future__ import annotations

import struct
from collections.abc import Callable, Mapping

BOOTSTRAP_SOURCE = r'''import java.lang.invoke.CallSite;
import java.lang.invoke.ConstantCallSite;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.invoke.MutableCallSite;

public final class IndySupport {
    public static int bootstrapCount;
    private static MutableCallSite mutable;

    private IndySupport() { }

    public static int addOne(int value) { return value + 1; }
    public static int subtractOne(int value) { return value - 1; }
    public static int intValue() { return 2; }
    public static CallSite fuelBootstrap(MethodHandles.Lookup lookup, String name,
            MethodType type) throws ReflectiveOperationException {
        System.out.println("bootstrap-entered");
        for (int index = 0; index < 10000; index++) { }
        return new ConstantCallSite(lookup.findStatic(IndySupport.class, "intValue", type));
    }
    public static long longValue(int value) { return value + 40L; }
    public static String mixed(long value, String text) { return value + ":" + text; }

    public static CallSite constant(MethodHandles.Lookup lookup, String name, MethodType type)
            throws ReflectiveOperationException {
        bootstrapCount++;
        return new ConstantCallSite(lookup.findStatic(IndySupport.class, "addOne", type));
    }

    public static CallSite mutable(MethodHandles.Lookup lookup, String name, MethodType type)
            throws ReflectiveOperationException {
        bootstrapCount++;
        mutable = new MutableCallSite(lookup.findStatic(IndySupport.class, "addOne", type));
        return mutable;
    }

    public static void flip() throws ReflectiveOperationException {
        mutable.setTarget(MethodHandles.lookup().findStatic(IndySupport.class, "subtractOne", mutable.type()));
    }

    public static CallSite counted(MethodHandles.Lookup lookup, String name, MethodType type)
            throws ReflectiveOperationException {
        bootstrapCount++;
        return new ConstantCallSite(lookup.findStatic(IndySupport.class, "intValue", type));
    }

    public static CallSite adapting(MethodHandles.Lookup lookup, String name, MethodType type)
            throws ReflectiveOperationException {
        bootstrapCount++;
        return new ConstantCallSite(adaptableHandle().asType(type));
    }
    public static CallSite bootstrapMixed(MethodHandles.Lookup lookup, String name,
            MethodType type) throws ReflectiveOperationException {
        bootstrapCount++;
        return new ConstantCallSite(lookup.findStatic(IndySupport.class, "mixed", type));
    }
    public static MethodHandle adaptableHandle() throws ReflectiveOperationException {
        return MethodHandles.lookup().findStatic(IndySupport.class, "longValue",
                MethodType.methodType(long.class, int.class));
    }
    public static CallSite bootstrapWithHandle(MethodHandles.Lookup lookup, String name,
            MethodType type, MethodHandle target) {
        bootstrapCount++;
        return new ConstantCallSite(target.asType(type));
    }

    public static CallSite bootstrapWithType(MethodHandles.Lookup lookup, String name,
            MethodType type, MethodType staticType) throws ReflectiveOperationException {
        bootstrapCount++;
        if (!staticType.equals(type)) throw new BootstrapMethodError("unexpected MethodType");
        return new ConstantCallSite(lookup.findStatic(IndySupport.class, "addOne", type));
    }

    private static int privateTarget(int value) { return value + 2; }

    private static CallSite privateBootstrap(MethodHandles.Lookup lookup, String name,
            MethodType type) {
        bootstrapCount++;
        return new ConstantCallSite(MethodHandles.constant(int.class, 1));
    }


    public static CallSite exactMismatch(MethodHandles.Lookup lookup, String name, MethodType type)
            throws ReflectiveOperationException {
        bootstrapCount++;
        return new ConstantCallSite(lookup.findStatic(IndySupport.class, "addOne",
                MethodType.methodType(int.class, int.class)));
    }

    public static CallSite wrongTarget(MethodHandles.Lookup lookup, String name, MethodType type)
            throws ReflectiveOperationException {
        bootstrapCount++;
        return new ConstantCallSite(lookup.findStatic(IndySupport.class, "longValue",
                MethodType.methodType(long.class, int.class)));
    }

    public static CallSite nullSite(MethodHandles.Lookup lookup, String name, MethodType type) {
        bootstrapCount++;
        return null;
    }

    public static Object wrongSite(MethodHandles.Lookup lookup, String name, MethodType type) {
        bootstrapCount++;
        return new Object();
    }

    public static CallSite throwing(MethodHandles.Lookup lookup, String name, MethodType type) {
        bootstrapCount++;
        throw new IllegalStateException("bootstrap-boom");
    }

    public static CallSite reentrant(MethodHandles.Lookup lookup, String name, MethodType type)
            throws Throwable {
        // The JVM does not detect reentrant linkage: re-executing the same
        // unlinked instruction runs the bootstrap again (unbounded recursion ends in
        // StackOverflowError), and the first CallSite to complete is the one
        // published. Recurse exactly once so both activations print.
        if (++bootstrapCount == 1) {
            MethodHandle entry = lookup.findStatic(lookup.lookupClass(), "main",
                    MethodType.methodType(void.class, String[].class));
            entry.invokeExact(new String[0]);
        }
        return new ConstantCallSite(lookup.findStatic(IndySupport.class, "intValue", type));
    }
}
'''


def _u1(value: int) -> bytes:
    return struct.pack(">B", value)


def _u2(value: int) -> bytes:
    return struct.pack(">H", value)


def _u4(value: int) -> bytes:
    return struct.pack(">I", value)


class _Pool:
    def __init__(self) -> None:
        self.items: list[bytes] = []
        self.cache: dict[tuple[object, ...], int] = {}

    def add(self, key: tuple[object, ...], payload: bytes) -> int:
        old = self.cache.get(key)
        if old is not None:
            return old
        index = len(self.items) + 1
        self.items.append(payload)
        self.cache[key] = index
        return index

    def utf8(self, value: str) -> int:
        encoded = value.encode("utf-8")
        if len(encoded) > 65535:
            raise ValueError("constant pool UTF-8 value is too long")
        return self.add(("utf8", value), _u1(1) + _u2(len(encoded)) + encoded)

    def clazz(self, name: str) -> int:
        return self.add(("class", name), _u1(7) + _u2(self.utf8(name)))

    def name_type(self, name: str, descriptor: str) -> int:
        return self.add(("name-type", name, descriptor),
                        _u1(12) + _u2(self.utf8(name)) + _u2(self.utf8(descriptor)))

    def method_ref(self, owner: str, name: str, descriptor: str) -> int:
        return self.add(("method-ref", owner, name, descriptor),
                        _u1(10) + _u2(self.clazz(owner)) + _u2(self.name_type(name, descriptor)))

    def handle(self, kind: int, reference: int) -> int:
        return self.add(("handle", kind, reference), _u1(15) + _u1(kind) + _u2(reference))

    def method_type(self, descriptor: str) -> int:
        return self.add(("method-type", descriptor), _u1(16) + _u2(self.utf8(descriptor)))

    def invoke_dynamic(self, bootstrap: int, name: str, descriptor: str) -> int:
        return self.add(("invoke-dynamic", bootstrap, name, descriptor),
                        _u1(18) + _u2(bootstrap) + _u2(self.name_type(name, descriptor)))

    def string(self, value: str) -> int:
        return self.add(("string", value), _u1(8) + _u2(self.utf8(value)))

    def integer(self, value: int) -> int:
        return self.add(("integer", value), _u1(3) + struct.pack(">i", value))

    def finish(self) -> bytes:
        return _u2(len(self.items) + 1) + b"".join(self.items)


def _ldc(index: int) -> bytes:
    return bytes((0x12, index)) if index <= 255 else b"\x13" + _u2(index)


def _push_int(value: int, pool: _Pool) -> bytes:
    if -1 <= value <= 5:
        return bytes((0x03 + value,)) if value >= 0 else b"\x02"
    if -128 <= value <= 127:
        return b"\x10" + struct.pack(">b", value)
    if -32768 <= value <= 32767:
        return b"\x11" + struct.pack(">h", value)
    return _ldc(pool.integer(value))


def _bootstrap(pool: _Pool, method: str, descriptor: str,
               arguments: tuple[int, ...] = ()) -> bytes:
    ref = pool.method_ref("IndySupport", method, descriptor)
    handle = pool.handle(6, ref)  # REF_invokeStatic
    return (_u2(handle) + _u2(len(arguments)) +
            b"".join(_u2(argument) for argument in arguments))



_BOOTSTRAP_DESC = "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;"
_BOOTSTRAP_HANDLE_DESC = "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodHandle;)Ljava/lang/invoke/CallSite;"
_BOOTSTRAP_TYPE_DESC = "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;Ljava/lang/invoke/MethodType;)Ljava/lang/invoke/CallSite;"
_BOOTSTRAP_OBJECT_DESC = "(Ljava/lang/invoke/MethodHandles$Lookup;Ljava/lang/String;Ljava/lang/invoke/MethodType;)Ljava/lang/Object;"




def _program(name: str, bootstrap_method: str, descriptor: str, result_descriptor: str,
             body: Callable[[_Pool], bytes], max_stack: int, *,
             two_sites: bool = False, counter: bool = False, mutable_calls: bool = False,
             bootstrap_descriptor: str = _BOOTSTRAP_DESC,
             bootstrap_args: Callable[[_Pool], tuple[int, ...]] | None = None) -> bytes:
    pool = _Pool()
    system_out = pool.add(("field-ref", "java/lang/System", "out", "Ljava/io/PrintStream;"),
                          _u1(9) + _u2(pool.clazz("java/lang/System")) +
                          _u2(pool.name_type("out", "Ljava/io/PrintStream;")))
    helper_code = None
    if mutable_calls:
        helper_ref = pool.method_ref(name, "call", "(I)I")
        out = bytearray()
        out += b"\xb2" + _u2(system_out) + _push_int(5, pool) + b"\xb8" + _u2(helper_ref)
        out += b"\xb6" + _u2(pool.method_ref("java/io/PrintStream", "println", "(I)V"))
        out += _static_call(pool, "IndySupport", "flip", "()V")
        out += b"\xb2" + _u2(system_out) + _push_int(5, pool) + b"\xb8" + _u2(helper_ref)
        out += b"\xb6" + _u2(pool.method_ref("java/io/PrintStream", "println", "(I)V"))
        helper_code = b"\x1a" + body(pool) + b"\xac"
    else:
        out = bytearray()
        def invocation() -> bytes:
            return b"\xb2" + _u2(system_out) + body(pool) + b"\xb6" + _u2(
                pool.method_ref("java/io/PrintStream", "println", f"({result_descriptor})V"))
        out += invocation()
        if two_sites:
            out += invocation()
    if counter:
        out += b"\xb2" + _u2(system_out)
        out += b"\xb2" + _u2(pool.add(("field-ref", "IndySupport", "bootstrapCount", "I"),
                                       _u1(9) + _u2(pool.clazz("IndySupport")) +
                                       _u2(pool.name_type("bootstrapCount", "I"))))
        out += b"\xb6" + _u2(pool.method_ref("java/io/PrintStream", "println", "(I)V"))
    out += b"\xb1"
    arguments = bootstrap_args(pool) if bootstrap_args is not None else ()
    return _serialize(name, bytes(out), max_stack, descriptor, result_descriptor,
                      bootstrap_method, pool, bootstrap_descriptor=bootstrap_descriptor,
                      bootstrap_arguments=arguments, helper_code=helper_code)





def _invoke() -> bytes:
    return b"\xba\xff\xff\x00\x00"


def _static_call(pool: _Pool, owner: str, name: str, descriptor: str) -> bytes:
    reference = pool.method_ref(owner, name, descriptor)
    return b"\xb8" + _u2(reference)


def _mixed(pool: _Pool) -> bytes:
    return b"\x0a" + _ldc(pool.string("mixed")) + _invoke()


def _integer_argument(value: int) -> Callable[[_Pool], bytes]:
    return lambda pool: _push_int(value, pool) + _invoke()


def _method_handle_call(invocation: str) -> Callable[[_Pool], bytes]:
    def emit(pool: _Pool) -> bytes:
        factory = pool.method_ref(
            "IndySupport", "adaptableHandle", "()Ljava/lang/invoke/MethodHandle;")
        target = pool.method_ref("java/lang/invoke/MethodHandle", invocation, "(I)D")
        return b"\xb8" + _u2(factory) + b"\x05\xb6" + _u2(target)
    return emit


def _cached_failure_class() -> bytes:
    """Catch two uses of one failing indy instruction and expose its bootstrap count."""
    pool = _Pool()
    this_class = pool.clazz("IndyCachedFailure")
    super_class = pool.clazz("java/lang/Object")
    code_name = pool.utf8("Code")
    stack_map_name = pool.utf8("StackMapTable")
    main_name, main_desc = pool.utf8("main"), pool.utf8("([Ljava/lang/String;)V")
    call_name, call_desc = pool.utf8("call"), pool.utf8("()I")
    pool.method_type("()I")
    indy_index = pool.invoke_dynamic(0, "fail", "()I")
    call_ref = pool.method_ref("IndyCachedFailure", "call", "()I")
    system_out = pool.add(("field-ref", "java/lang/System", "out", "Ljava/io/PrintStream;"),
                          _u1(9) + _u2(pool.clazz("java/lang/System")) +
                          _u2(pool.name_type("out", "Ljava/io/PrintStream;")))
    count_ref = pool.add(("field-ref", "IndySupport", "bootstrapCount", "I"),
                         _u1(9) + _u2(pool.clazz("IndySupport")) +
                         _u2(pool.name_type("bootstrapCount", "I")))
    println = pool.method_ref("java/io/PrintStream", "println", "(I)V")
    string_array = pool.clazz("[Ljava/lang/String;")
    bootstrap_error = pool.clazz("java/lang/BootstrapMethodError")

    # Both invokestatic instructions reach the same indy instruction in call().
    main_code = (b"\xb8" + _u2(call_ref) + b"\x57" + b"\xa7\x00\x04" + b"\x57" +
                 b"\xb8" + _u2(call_ref) + b"\x57" + b"\xa7\x00\x04" + b"\x57" +
                 b"\xb2" + _u2(system_out) + b"\xb2" + _u2(count_ref) +
                 b"\xb6" + _u2(println) + b"\xb1")
    # Full frames: first handler, first goto target, second handler, second goto target.
    frames = bytearray(_u2(4))
    for delta, stack_class in ((7, bootstrap_error), (0, None),
                               (6, bootstrap_error), (0, None)):
        frames += b"\xff" + _u2(delta) + _u2(1) + b"\x07" + _u2(string_array)
        frames += (_u2(0) if stack_class is None else
                   _u2(1) + b"\x07" + _u2(stack_class))
    stack_map = bytes(frames)
    stack_attr = _u2(stack_map_name) + _u4(len(stack_map)) + stack_map
    handlers = (_u2(2) + _u2(0) + _u2(3) + _u2(7) + _u2(bootstrap_error) +
                _u2(8) + _u2(11) + _u2(15) + _u2(bootstrap_error))
    main_payload = (_u2(2) + _u2(1) + _u4(len(main_code)) + main_code + handlers +
                    _u2(1) + stack_attr)
    main_method = (_u2(0x0009) + _u2(main_name) + _u2(main_desc) + _u2(1) +
                   _u2(code_name) + _u4(len(main_payload)) + main_payload)
    helper_code = b"\xba" + _u2(indy_index) + b"\x00\x00\xac"
    helper_payload = (_u2(1) + _u2(0) + _u4(len(helper_code)) + helper_code +
                      _u2(0) + _u2(0))
    helper_method = (_u2(0x0009) + _u2(call_name) + _u2(call_desc) + _u2(1) +
                     _u2(code_name) + _u4(len(helper_payload)) + helper_payload)
    bootstrap = _bootstrap(pool, "throwing", _BOOTSTRAP_DESC)
    bootstrap_payload = _u2(1) + bootstrap
    bootstrap_name = pool.utf8("BootstrapMethods")
    return (b"\xca\xfe\xba\xbe" + _u2(0) + _u2(52) + pool.finish() +
            _u2(0x0021) + _u2(this_class) + _u2(super_class) + _u2(0) + _u2(0) +
            _u2(2) + main_method + helper_method + _u2(1) +
            _u2(bootstrap_name) + _u4(len(bootstrap_payload)) + bootstrap_payload)



def _serialize(name: str, code: bytes, max_stack: int, call_descriptor: str,
               result_descriptor: str, bootstrap_method: str, pool: _Pool, *,
               bootstrap_descriptor: str = _BOOTSTRAP_DESC,
               bootstrap_arguments: tuple[int, ...] = (),
               helper_code: bytes | None = None) -> bytes:
    this_class = pool.clazz(name)
    super_class = pool.clazz("java/lang/Object")
    code_name, bootstrap_name = pool.utf8("Code"), pool.utf8("BootstrapMethods")
    main_name, main_desc = pool.utf8("main"), pool.utf8("([Ljava/lang/String;)V")
    pool.method_type(call_descriptor)
    indy_index = pool.invoke_dynamic(0, "link", call_descriptor)
    code = code.replace(b"\xff\xff", _u2(indy_index))
    code_attr = _u2(max_stack) + _u2(1) + _u4(len(code)) + code + _u2(0) + _u2(0)
    methods = [_u2(0x0009) + _u2(main_name) + _u2(main_desc) + _u2(1) +
               _u2(code_name) + _u4(len(code_attr)) + code_attr]
    if helper_code is not None:
        helper_name = pool.utf8("call")
        helper_desc = pool.utf8("(I)I")
        helper_code = helper_code.replace(b"\xff\xff", _u2(indy_index))
        helper_attr = (_u2(2) + _u2(1) + _u4(len(helper_code)) + helper_code +
                       _u2(0) + _u2(0))
        methods.append(_u2(0x0009) + _u2(helper_name) + _u2(helper_desc) + _u2(1) +
                       _u2(code_name) + _u4(len(helper_attr)) + helper_attr)
    bootstrap = _bootstrap(pool, bootstrap_method, bootstrap_descriptor, bootstrap_arguments)
    payload = _u2(1) + bootstrap
    return (b"\xca\xfe\xba\xbe" + _u2(0) + _u2(52) + pool.finish() +
            _u2(0x0021) + _u2(this_class) + _u2(super_class) + _u2(0) + _u2(0) +
            _u2(len(methods)) + b"".join(methods) + _u2(1) +
            _u2(bootstrap_name) + _u4(len(payload)) + payload)


def generated_classes() -> Mapping[str, bytes]:
    """Return bounded, deterministic, straight-line version-52 fixture classfiles."""
    classes: dict[str, bytes] = {}
    # Positive control: a user bootstrap returns a ConstantCallSite with exact type.
    classes["IndyConstant"] = _program(
        "IndyConstant", "constant", "(I)I", "I", _integer_argument(5), 2)
    classes["IndyFuelBootstrap"] = _program(
        "IndyFuelBootstrap", "fuelBootstrap", "()I", "I",
        lambda _pool: _invoke(), 2)

    classes["IndyMutable"] = _program(
        "IndyMutable", "mutable", "(I)I", "I", lambda _pool: _invoke(), 2,
        counter=True, mutable_calls=True)
    # Two distinct instruction offsets share one CP entry and link independently.
    classes["IndySharedEntry"] = _program(
        "IndySharedEntry", "counted", "()I", "I", lambda _pool: _invoke(), 2,
        two_sites=True, counter=True)
    classes["IndyMixedWideReference"] = _program(
        "IndyMixedWideReference", "bootstrapMixed",
        "(JLjava/lang/String;)Ljava/lang/String;", "Ljava/lang/String;",
        _mixed, 4)

    classes["IndyMethodHandleArgument"] = _program(
        "IndyMethodHandleArgument", "bootstrapWithHandle", "(I)I", "I",
        _integer_argument(5), 2, bootstrap_descriptor=_BOOTSTRAP_HANDLE_DESC,
        bootstrap_args=lambda pool: (
            pool.handle(6, pool.method_ref("IndySupport", "addOne", "(I)I")),))
    classes["IndyMethodTypeArgument"] = _program(
        "IndyMethodTypeArgument", "bootstrapWithType", "(I)I", "I",
        _integer_argument(5), 2, bootstrap_descriptor=_BOOTSTRAP_TYPE_DESC,
        bootstrap_args=lambda pool: (pool.method_type("(I)I"),))
    classes["IndyInaccessibleHandleArgument"] = _program(
        "IndyInaccessibleHandleArgument", "bootstrapWithHandle", "(I)I", "I",
        _integer_argument(5), 2, bootstrap_descriptor=_BOOTSTRAP_HANDLE_DESC,
        bootstrap_args=lambda pool: (
            pool.handle(6, pool.method_ref("IndySupport", "privateTarget", "(I)I")),))
    classes["IndyMissingMethodTypeArgument"] = _program(
        "IndyMissingMethodTypeArgument", "bootstrapWithType", "()I", "I",
        lambda _pool: _invoke(), 2, bootstrap_descriptor=_BOOTSTRAP_TYPE_DESC,
        bootstrap_args=lambda pool: (pool.method_type("(Lmissing/Type;)V"),))
    classes["IndyInaccessibleBootstrap"] = _program(
        "IndyInaccessibleBootstrap", "privateBootstrap", "()I", "I",
        lambda _pool: _invoke(), 2)


    # MethodHandle.asType widens the target's long result to the call-site double result.
    classes["IndyAdapted"] = _program(
        "IndyAdapted", "adapting", "(I)D", "D", _integer_argument(2), 3)
    classes["MethodHandleInvokeAdapted"] = _program(
        "MethodHandleInvokeAdapted", "adapting", "(I)D", "D",
        _method_handle_call("invoke"), 3)
    classes["MethodHandleInvokeExactMismatch"] = _program(
        "MethodHandleInvokeExactMismatch", "adapting", "(I)D", "D",
        _method_handle_call("invokeExact"), 3)
    # The bootstrap intentionally returns an int target for a long call-site result.
    classes["IndyExactMismatch"] = _program(
        "IndyExactMismatch", "exactMismatch", "(I)J", "J", _integer_argument(2), 3)
    classes["IndyWrongTarget"] = _program(
        "IndyWrongTarget", "wrongTarget", "(I)I", "I", _integer_argument(2), 2)
    classes["IndyNullCallSite"] = _program(
        "IndyNullCallSite", "nullSite", "()I", "I", lambda _pool: _invoke(), 2)
    classes["IndyWrongBootstrapResult"] = _program(
        "IndyWrongBootstrapResult", "wrongSite", "()I", "I", lambda _pool: _invoke(), 2,
        bootstrap_descriptor=_BOOTSTRAP_OBJECT_DESC)
    classes["IndyBootstrapThrows"] = _program(
        "IndyBootstrapThrows", "throwing", "()I", "I", lambda _pool: _invoke(), 2)
    classes["IndyReentrantBootstrap"] = _program(
        "IndyReentrantBootstrap", "reentrant", "()I", "I",
        lambda _pool: _invoke(), 2, counter=True)
    classes["IndyCachedFailure"] = _cached_failure_class()
    return classes
