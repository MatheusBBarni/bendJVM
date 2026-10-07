"""Hand-encoded Java 8 metadata inputs for the independent Bend parser.

No host annotation parser or Java execution is involved. Each case supplies its
expected structural result so the harness can feed bytes to P.parse directly.
"""
from dataclasses import dataclass
import struct


def u2(value):
    return struct.pack(">H", value)


def u4(value):
    return struct.pack(">I", value)


@dataclass(frozen=True)
class MetadataCase:
    name: str
    data: bytes
    valid: bool


class ClassBytes:
    def __init__(self):
        self.pool = []
        self.utf_indexes = {}
        self.name = self.class_constant("MetadataParserCase")
        self.parent = self.class_constant("java/lang/Object")
        self.annotation = self.utf("LCaseAnnotation;")
        self.member_name = self.utf("value")
        self.string = self.utf("sample")
        self.void = self.utf("V")
        self.enum_type = self.utf("LKind;")
        self.enum_name = self.utf("ONLY")
        self.integer = self.add(b"\x03" + u4(7))

    def add(self, entry):
        self.pool.append(entry)
        return len(self.pool)

    def utf(self, text):
        if text not in self.utf_indexes:
            encoded = text.encode("utf-8")
            self.utf_indexes[text] = self.add(b"\x01" + u2(len(encoded)) + encoded)
        return self.utf_indexes[text]

    def class_constant(self, text):
        return self.add(b"\x07" + u2(self.utf(text)))

    def attribute(self, name, payload):
        return u2(self.utf(name)) + u4(len(payload)) + payload

    def annotation_value(self, value=None):
        if value is None:
            return u2(self.annotation) + u2(0)
        return u2(self.annotation) + u2(1) + u2(self.member_name) + value

    def annotations(self, value=None):
        return u2(1) + self.annotation_value(value)

    def type_annotation(self, target, info=b"", path=b"\x00"):
        return u2(1) + bytes([target]) + info + path + self.annotation_value()

    def member(self, name, descriptor, attrs=(), flags=0x0401):
        return (u2(flags) + u2(self.utf(name)) + u2(self.utf(descriptor))
                + u2(len(attrs)) + b"".join(attrs))

    def code(self, attrs=(), handlers=(), code=b"\xb1", locals_count=1):
        return (u2(0) + u2(locals_count) + u4(len(code)) + code
                + u2(len(handlers)) + b"".join(handlers)
                + u2(len(attrs)) + b"".join(attrs))

    def finish(self, attrs=(), fields=(), methods=(), flags=0x0421):
        # All names must be interned before the constant-pool bytes are emitted.
        body = (u2(flags) + u2(self.name) + u2(self.parent) + u2(0)
                + u2(len(fields)) + b"".join(fields)
                + u2(len(methods)) + b"".join(methods)
                + u2(len(attrs)) + b"".join(attrs))
        return b"\xca\xfe\xba\xbe" + u2(0) + u2(52) + u2(len(self.pool) + 1) + b"".join(self.pool) + body


def metadata_cases():
    cases = []

    def declaration(name, payload, valid, attr="RuntimeVisibleAnnotations", site="class"):
        c = ClassBytes()
        attribute = c.attribute(attr, payload(c))
        if site == "field":
            data = c.finish(fields=[c.member("field", "I", [attribute], flags=1)])
        elif site == "method":
            data = c.finish(methods=[c.member("method", "(I)V", [attribute])])
        elif site == "code":
            code = c.attribute("Code", c.code([attribute]))
            data = c.finish(methods=[c.member("method", "(I)V", [code], flags=9)])
        else:
            data = c.finish(attrs=[attribute])
        cases.append(MetadataCase(name, data, valid))

    declaration("visible-empty", lambda c: u2(0), True)
    declaration("invisible-structured", lambda c: c.annotations(b"s" + u2(c.string)), True,
                attr="RuntimeInvisibleAnnotations")
    declaration("unknown-tag", lambda c: c.annotations(b"\xff"), False)
    declaration("wrong-constant-kind", lambda c: c.annotations(b"I" + u2(c.string)), False)
    declaration("bad-cp-index", lambda c: c.annotations(b"s" + u2(65535)), False)
    declaration("truncated-annotation", lambda c: c.annotations()[:-1], False)
    declaration("trailing-annotation", lambda c: c.annotations() + b"\x00", False)
    declaration("excess-annotation-count", lambda c: u2(4097), False)
    declaration("excess-element-count", lambda c: u2(1) + u2(c.annotation) + u2(4097), False)
    declaration("excess-array-count", lambda c: c.annotations(b"[" + u2(4097)), False)
    declaration("declaration-inside-code", lambda c: c.annotations(), False, site="code")
    for site in ("class", "field", "code"):
        declaration("parameters-on-" + site, lambda c: b"\x00", False,
                    attr="RuntimeVisibleParameterAnnotations", site=site)
        declaration("default-on-" + site, lambda c: b"c" + u2(c.void), False,
                    attr="AnnotationDefault", site=site)
    declaration("parameter-count-exceeds-arity", lambda c: b"\x02" + u2(0) * 2, False,
                attr="RuntimeVisibleParameterAnnotations", site="method")
    declaration("parameter-count-short-without-prefix", lambda c: b"\x00", False,
                attr="RuntimeVisibleParameterAnnotations", site="method")
    declaration("parameter-count-matches", lambda c: b"\x01" + u2(0), True,
                attr="RuntimeVisibleParameterAnnotations", site="method")
    declaration("void-Class-element", lambda c: c.annotations(b"c" + u2(c.void)), True)
    for leaf_name in ("empty-annotation", "enum", "Class", "empty-array", "primitive"):
        for depth in (64, 65):
            def payload(c, leaf_name=leaf_name, depth=depth):
                leaves = {
                    "empty-annotation": b"@" + c.annotation_value(),
                    "enum": b"e" + u2(c.enum_type) + u2(c.enum_name),
                    "Class": b"c" + u2(c.void),
                    "empty-array": b"[" + u2(0),
                    "primitive": b"I" + u2(c.integer),
                }
                # Nested annotation is itself an additional recursive entry.
                wrappers = depth - (1 if leaf_name == "empty-annotation" else 0)
                return c.annotations((b"[" + u2(1)) * wrappers + leaves[leaf_name])
            declaration("array-depth-%s-%d" % (leaf_name, depth), payload, depth == 64)
    for depth in (64, 65):
        def nested(c, depth=depth):
            value = c.annotation_value()
            for _ in range(depth):
                value = c.annotation_value(b"@" + value)
            return u2(1) + value
        declaration("annotation-depth-%d" % depth, nested, depth == 64)

    for target in (0x43, 0x44, 0x45, 0x46):
        declaration("code-offset-target-%02x" % target,
                    lambda c, target=target: c.type_annotation(target, u2(0)), True,
                    attr="RuntimeVisibleTypeAnnotations", site="code")
    for target in range(0x47, 0x4c):
        declaration("code-typeargument-target-%02x" % target,
                    lambda c, target=target: c.type_annotation(target, u2(0) + b"\x00"), True,
                    attr="RuntimeInvisibleTypeAnnotations", site="code")
    for target in (0x40, 0x41):
        declaration("localvar-zero-table-%02x" % target,
                    lambda c, target=target: c.type_annotation(target, u2(0)), True,
                    attr="RuntimeVisibleTypeAnnotations", site="code")
        declaration("localvar-one-table-%02x" % target,
                    lambda c, target=target: c.type_annotation(target, u2(1) + u2(0) + u2(1) + u2(0)), True,
                    attr="RuntimeVisibleTypeAnnotations", site="code")
    for kind in (0, 1, 2):
        declaration("nonzero-path-index-%d" % kind,
                    lambda c, kind=kind: c.type_annotation(0x13, path=bytes([1, kind, 1])), False,
                    attr="RuntimeVisibleTypeAnnotations", site="field")
    declaration("unknown-path-kind", lambda c: c.type_annotation(0x13, path=b"\x01\x04\x00"), False,
                attr="RuntimeVisibleTypeAnnotations", site="field")
    declaration("field-target-on-class", lambda c: c.type_annotation(0x13), False,
                attr="RuntimeVisibleTypeAnnotations")
    declaration("formal-parameter-out-of-bounds", lambda c: c.type_annotation(0x16, b"\x01"), False,
                attr="RuntimeVisibleTypeAnnotations", site="method")
    declaration("throws-out-of-bounds", lambda c: c.type_annotation(0x17, u2(0)), False,
                attr="RuntimeVisibleTypeAnnotations", site="method")
    declaration("supertype-out-of-bounds", lambda c: c.type_annotation(0x10, u2(0)), False,
                attr="RuntimeVisibleTypeAnnotations")
    declaration("code-offset-out-of-bounds", lambda c: c.type_annotation(0x43, u2(1)), False,
                attr="RuntimeVisibleTypeAnnotations", site="code")
    declaration("catch-index-out-of-bounds", lambda c: c.type_annotation(0x42, u2(0)), False,
                attr="RuntimeVisibleTypeAnnotations", site="code")
    declaration("localvar-range-out-of-bounds", lambda c: c.type_annotation(0x40, u2(1) + u2(0) + u2(2) + u2(0)), False,
                attr="RuntimeVisibleTypeAnnotations", site="code")
    declaration("localvar-slot-out-of-bounds", lambda c: c.type_annotation(0x40, u2(1) + u2(0) + u2(1) + u2(1)), False,
                attr="RuntimeVisibleTypeAnnotations", site="code")

    c = ClassBytes()
    attr = c.attribute("RuntimeVisibleAnnotations", c.annotations())
    cases.append(MetadataCase("duplicate-attribute", c.finish(attrs=[attr, attr]), False))
    c = ClassBytes()
    attr = c.attribute("UnknownMetadata", b"")
    cases.append(MetadataCase("attribute-count-preallocation", c.finish(attrs=[attr] * 4097), False))
    c = ClassBytes()
    # Each member fits its individual byte budget, but the class total does not.
    payload = c.annotations(b"[" + u2(4096) + (b"I" + u2(c.integer)) * 4096)
    attr = c.attribute("RuntimeVisibleAnnotations", payload)
    fields = [c.member("field%d" % i, "I", [attr], flags=1) for i in range(22)]
    cases.append(MetadataCase("aggregate-class-node-budget", c.finish(fields=fields), False))
    c = ClassBytes()
    default = c.attribute("AnnotationDefault", b"c" + u2(c.void))
    method = c.member("value", "()Ljava/lang/Class;", [default])
    cases.append(MetadataCase("void-Class-default", c.finish(methods=[method], flags=0x2601), True))
    return cases
