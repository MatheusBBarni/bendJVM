/*
 * BendJVM native plugin ABI, version 1.
 *
 * This is BendJVM's own restricted bridge, not JNI. A plugin library exports
 * one symbol, bendjvm_register_v1, returning a static registration that maps
 * exact Java owner/name/descriptor/staticness tuples to functions. The JVM
 * loads plugins only from paths the launcher allows (--native-library,
 * --native-allow) into a supervised helper process; Java objects, heap
 * pointers, callbacks into Java and attached native threads never cross.
 *
 * Values are copied: strings arrive as UTF-16 code units, primitive arrays as
 * a buffer the function may modify (the JVM copies the final contents back to
 * the Java array after a successful return). Every pointer an argument holds
 * stays valid only for the duration of the call.
 *
 * Plugins run real native code with the helper process's OS permissions.
 * Process separation keeps a crash away from the JVM; it is not a sandbox.
 */
#ifndef BENDJVM_PLUGIN_H
#define BENDJVM_PLUGIN_H

#include <stdint.h>

#define BENDJVM_PLUGIN_ABI 1

enum bendjvm_kind {
    BENDJVM_VOID = 0,
    BENDJVM_INT = 1,     /* I */
    BENDJVM_LONG = 2,    /* J (also opaque resource handles) */
    BENDJVM_FLOAT = 3,   /* F */
    BENDJVM_DOUBLE = 4,  /* D */
    BENDJVM_BOOLEAN = 5, /* Z */
    BENDJVM_BYTE = 6,    /* B */
    BENDJVM_CHAR = 7,    /* C */
    BENDJVM_SHORT = 8,   /* S */
    BENDJVM_STRING = 9,  /* java.lang.String: UTF-16 units, as.chars + length */
    /* A primitive array: BENDJVM_ARRAY | element kind, as.data + length. */
    BENDJVM_ARRAY = 0x100
};

enum bendjvm_status { BENDJVM_OK = 0, BENDJVM_ERROR = 1 };

typedef struct bendjvm_value {
    uint32_t kind;
    uint32_t length;   /* units (strings) or elements (arrays); 0 otherwise */
    uint32_t is_null;  /* a null String or array reference */
    uint32_t reserved;
    union {
        int32_t i;
        int64_t j;
        float f;
        double d;
        const uint16_t *chars;
        void *data;
    } as;
} bendjvm_value;

typedef struct bendjvm_call {
    uint32_t argc;
    bendjvm_value *args;
    /* Set by the function; its kind must match the descriptor's return type.
     * A returned string's units must stay valid until the call returns. */
    bendjvm_value result;
    /* On BENDJVM_ERROR: a Java exception class listed in the registration's
     * exceptions (binary name with '/'), and a NUL-terminated message. */
    char error_class[128];
    char error_message[256];
} bendjvm_call;

typedef int32_t (*bendjvm_function)(bendjvm_call *call);

typedef struct bendjvm_binding {
    const char *owner;        /* "demo/NativeDemo" */
    const char *name;         /* "add" */
    const char *descriptor;   /* "(II)I" */
    uint32_t is_static;
    /* Opaque resource handles (long parameters/results): bit i marks parameter
     * i as a handle the plugin issued earlier; the helper rejects any other
     * value before calling. `released_params` marks handles the call frees. */
    uint32_t handle_params;
    uint32_t released_params;
    uint32_t returns_handle;
    bendjvm_function function;
} bendjvm_binding;

typedef struct bendjvm_registration {
    uint32_t abi_version;     /* BENDJVM_PLUGIN_ABI */
    uint32_t thread_safe;     /* 0: the helper serializes calls into this library */
    uint32_t binding_count;
    const bendjvm_binding *bindings;
    uint32_t exception_count;
    const char *const *exceptions;
} bendjvm_registration;

typedef const bendjvm_registration *(*bendjvm_register_fn)(void);

#endif
