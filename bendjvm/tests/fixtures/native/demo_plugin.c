/* A small, harmless BendJVM native plugin used by the native-bridge tests. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "bendjvm_plugin.h"

static int32_t fail_with(bendjvm_call *call, const char *cls, const char *message) {
    snprintf(call->error_class, sizeof call->error_class, "%s", cls);
    snprintf(call->error_message, sizeof call->error_message, "%s", message);
    return BENDJVM_ERROR;
}

static int32_t add(bendjvm_call *call) {
    call->result.kind = BENDJVM_INT;
    call->result.as.i = call->args[0].as.i + call->args[1].as.i;
    return BENDJVM_OK;
}

static int32_t mul_wide(bendjvm_call *call) {
    call->result.kind = BENDJVM_LONG;
    call->result.as.j = (int64_t) ((uint64_t) call->args[0].as.j * (uint64_t) call->args[1].as.j);
    return BENDJVM_OK;
}

static int32_t scale(bendjvm_call *call) {
    call->result.kind = BENDJVM_DOUBLE;
    call->result.as.d = call->args[0].as.d * call->args[1].as.d;
    return BENDJVM_OK;
}

static int32_t fill(bendjvm_call *call) {
    if (call->args[0].is_null) {
        return fail_with(call, "java/lang/NullPointerException", "buffer");
    }
    int8_t *bytes = call->args[0].as.data;
    for (uint32_t i = 0; i < call->args[0].length; i++) {
        bytes[i] = (int8_t) (call->args[1].as.i + (int32_t) i);
    }
    call->result.kind = BENDJVM_VOID;
    return BENDJVM_OK;
}

static int32_t sum(bendjvm_call *call) {
    int32_t total = 0;
    const int32_t *values = call->args[0].as.data;
    for (uint32_t i = 0; i < call->args[0].length; i++) {
        total += values[i];
    }
    call->result.kind = BENDJVM_INT;
    call->result.as.i = total;
    return BENDJVM_OK;
}

static uint16_t greeting[256];

static int32_t greet(bendjvm_call *call) {
    static const char prefix[] = "hello, ";
    uint32_t n = 0;
    for (; prefix[n]; n++) {
        greeting[n] = (uint16_t) prefix[n];
    }
    for (uint32_t i = 0; i < call->args[0].length && n < 255; i++) {
        greeting[n++] = call->args[0].as.chars[i];
    }
    greeting[n++] = '!';
    call->result.kind = BENDJVM_STRING;
    call->result.length = n;
    call->result.as.chars = greeting;
    return BENDJVM_OK;
}

/* Counters are plugin resources; Java only ever sees opaque handles. */
typedef struct counter { int64_t value; } counter;

static int32_t open_counter(bendjvm_call *call) {
    counter *c = malloc(sizeof *c);
    if (!c) {
        return fail_with(call, "java/lang/OutOfMemoryError", "counter");
    }
    c->value = call->args[0].as.j;
    call->result.kind = BENDJVM_LONG;
    call->result.as.j = (int64_t) (intptr_t) c;
    return BENDJVM_OK;
}

static int32_t increment(bendjvm_call *call) {
    counter *c = (counter *) (intptr_t) call->args[0].as.j;
    c->value += 1;
    call->result.kind = BENDJVM_LONG;
    call->result.as.j = c->value;
    return BENDJVM_OK;
}

static int32_t close_counter(bendjvm_call *call) {
    free((counter *) (intptr_t) call->args[0].as.j);
    call->result.kind = BENDJVM_VOID;
    return BENDJVM_OK;
}

static int32_t fail(bendjvm_call *call) {
    char message[128] = {0};
    for (uint32_t i = 0; i < call->args[0].length && i < 127; i++) {
        message[i] = (char) call->args[0].as.chars[i];
    }
    return fail_with(call, "java/lang/IllegalStateException", message);
}

static int32_t raise_unregistered(bendjvm_call *call) {
    return fail_with(call, "java/lang/Error", "not declared");
}

static int32_t sleep_millis(bendjvm_call *call) {
    struct timespec delay = {call->args[0].as.i / 1000, (long) (call->args[0].as.i % 1000) * 1000000L};
    nanosleep(&delay, NULL);
    call->result.kind = BENDJVM_INT;
    call->result.as.i = call->args[0].as.i;
    return BENDJVM_OK;
}

static int32_t crash(bendjvm_call *call) {
    (void) call;
    abort();
}

static const bendjvm_binding bindings[] = {
    {"NativeDemo", "add", "(II)I", 1, 0, 0, 0, add},
    {"NativeDemo", "mulWide", "(JJ)J", 1, 0, 0, 0, mul_wide},
    {"NativeDemo", "scale", "(DD)D", 1, 0, 0, 0, scale},
    {"NativeDemo", "fill", "([BI)V", 1, 0, 0, 0, fill},
    {"NativeDemo", "sum", "([I)I", 1, 0, 0, 0, sum},
    {"NativeDemo", "greet", "(Ljava/lang/String;)Ljava/lang/String;", 1, 0, 0, 0, greet},
    {"NativeDemo", "openCounter", "(J)J", 1, 0, 0, 1, open_counter},
    {"NativeDemo", "increment", "(J)J", 1, 1, 0, 0, increment},
    {"NativeDemo", "closeCounter", "(J)V", 1, 1, 1, 0, close_counter},
    {"NativeDemo", "fail", "(Ljava/lang/String;)V", 1, 0, 0, 0, fail},
    {"NativeDemo", "raiseUnregistered", "()V", 1, 0, 0, 0, raise_unregistered},
    {"NativeDemo", "sleepMillis", "(I)I", 1, 0, 0, 0, sleep_millis},
    {"NativeDemo", "lockedAdd", "(II)I", 1, 0, 0, 0, add},
    {"NativeDemo", "crash", "()V", 1, 0, 0, 0, crash},
};

static const char *const exceptions[] = {
    "java/lang/IllegalStateException", "java/lang/NullPointerException", "java/lang/OutOfMemoryError",
};

static const bendjvm_registration registration = {
    BENDJVM_PLUGIN_ABI, 1, sizeof bindings / sizeof bindings[0], bindings,
    sizeof exceptions / sizeof exceptions[0], exceptions,
};

const bendjvm_registration *bendjvm_register_v1(void) {
    return &registration;
}
