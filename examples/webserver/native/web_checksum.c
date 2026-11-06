/* The web example's native plugin: a 32-bit FNV-1a checksum over a byte[]. */
#include "bendjvm_plugin.h"

static int32_t fnv1a(bendjvm_call *call) {
    uint32_t hash = 2166136261u;
    const uint8_t *bytes = call->args[0].as.data;
    for (uint32_t i = 0; !call->args[0].is_null && i < call->args[0].length; i++) {
        hash = (hash ^ bytes[i]) * 16777619u;
    }
    call->result.kind = BENDJVM_INT;
    call->result.as.i = (int32_t) hash;
    return BENDJVM_OK;
}

static const bendjvm_binding bindings[] = {
    {"example/web/Checksum", "fnv1a", "([B)I", 1, 0, 0, 0, fnv1a},
};

static const bendjvm_registration registration = {
    BENDJVM_PLUGIN_ABI, 1, 1, bindings, 0, 0,
};

const bendjvm_registration *bendjvm_register_v1(void) {
    return &registration;
}
