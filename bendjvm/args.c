#include <stdint.h>

const char *jvm_class_path(void) { return ""; }
const char *jvm_class_files(void) { return ""; }
const char *jvm_entry_name(void) { return ""; }
const char *jvm_application_args(void) { return ""; }
uint32_t jvm_fuel(void) { return 1000000u; }
uint32_t jvm_max_heap(void) { return 1024u; }
uint32_t jvm_mode(void) { return 0u; }
