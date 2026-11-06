/*
 * BendJVM supervised native-plugin helper (plan 05).
 *
 * The JVM host starts this process when Java code first loads an allowed
 * native library. It loads plugins with dlopen, reads their versioned
 * registration (bendjvm_plugin.h), and runs calls on a small worker pool, so a
 * slow call never blocks the others. Java objects never reach it: requests
 * carry flattened 32-bit words (bendjvm/java/natives.bend) and replies return
 * words. A crash here ends only this process.
 *
 * Protocol, one line per message on stdin/stdout:
 *   L <id> <path as hex>                        -> B <id> <n> (<owner> <name> <descriptor> <static>){n}
 *   C <id> <owner> <name> <descriptor> <static> <n> <word>{n}  -> W <id> <n> <word>{n}
 * Any failure replies E <id> <"java/lang/Class: message" as hex>.
 */
#include <dlfcn.h>
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bendjvm_plugin.h"

#define WORKERS 4
#define MAX_REPLY_WORDS (4u * 1024u * 1024u)
#define MAX_PARAMS 255

typedef struct library {
    char *path;
    void *dl;
    const bendjvm_registration *registration;
    pthread_mutex_t lock; /* held around calls unless thread_safe */
} library;

typedef struct binding_entry {
    library *lib;
    const bendjvm_binding *binding;
} binding_entry;

typedef struct handle_entry {
    int64_t id;
    library *lib;
    int64_t raw;
} handle_entry;

static library **libraries;
static size_t library_count;
static binding_entry *bindings;
static size_t binding_count;
static handle_entry *handles;
static size_t handle_count, handle_capacity;
static int64_t next_handle = 1;
static pthread_mutex_t state = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t output = PTHREAD_MUTEX_INITIALIZER;

/* ---- output ------------------------------------------------------------ */

static void reply_error(const char *id, const char *format, ...) {
    char message[512];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof message, format, args);
    va_end(args);
    pthread_mutex_lock(&output);
    printf("E %s ", id);
    for (const unsigned char *p = (const unsigned char *) message; *p; p++) {
        printf("%02x", *p);
    }
    printf("\n");
    fflush(stdout);
    pthread_mutex_unlock(&output);
}

/* ---- descriptors --------------------------------------------------------- */

/* Splits "(I[BLjava/lang/String;)J" into parameter codes and a result code:
 * 'I' 'J' 'F' 'D' 'Z' 'B' 'C' 'S', 'T' for String, lower case for a primitive
 * array of that element, 'V' for void. Returns the parameter count, or -1. */
static int parse_descriptor(const char *d, char *params, char *result) {
    static const char *string = "Ljava/lang/String;";
    int count = 0;
    if (*d++ != '(') {
        return -1;
    }
    while (*d && *d != ')') {
        if (count >= MAX_PARAMS) {
            return -1;
        }
        if (*d == '[') {
            d++;
            if (!strchr("IJFDZBCS", *d) || !*d) {
                return -1;
            }
            params[count++] = (char) (*d - 'A' + 'a');
            d++;
        } else if (*d == 'L') {
            if (strncmp(d, string, strlen(string)) != 0) {
                return -1;
            }
            params[count++] = 'T';
            d += strlen(string);
        } else if (strchr("IJFDZBCS", *d)) {
            params[count++] = *d++;
        } else {
            return -1;
        }
    }
    if (*d++ != ')') {
        return -1;
    }
    if (strcmp(d, string) == 0) {
        *result = 'T';
    } else if (d[0] && !d[1] && strchr("IJFDZBCSV", d[0])) {
        *result = d[0];
    } else {
        return -1;
    }
    return count;
}

static uint32_t kind_of(char code) {
    switch (code) {
        case 'I': return BENDJVM_INT;
        case 'J': return BENDJVM_LONG;
        case 'F': return BENDJVM_FLOAT;
        case 'D': return BENDJVM_DOUBLE;
        case 'Z': return BENDJVM_BOOLEAN;
        case 'B': return BENDJVM_BYTE;
        case 'C': return BENDJVM_CHAR;
        case 'S': return BENDJVM_SHORT;
        case 'T': return BENDJVM_STRING;
        case 'V': return BENDJVM_VOID;
        default: return BENDJVM_ARRAY | kind_of((char) (code - 'a' + 'A'));
    }
}

static size_t element_size(char element) {
    switch (element) {
        case 'j': case 'd': return 8;
        case 'i': case 'f': return 4;
        case 'c': case 's': return 2;
        default: return 1;
    }
}

/* ---- loading --------------------------------------------------------------- */

static int protected_owner(const char *owner) {
    return strncmp(owner, "java/", 5) == 0 || strncmp(owner, "javax/", 6) == 0 || strncmp(owner, "sun/", 4) == 0 || strncmp(owner, "jdk/", 4) == 0;
}

static int same_binding(const bendjvm_binding *a, const bendjvm_binding *b) {
    return strcmp(a->owner, b->owner) == 0 && strcmp(a->name, b->name) == 0 && strcmp(a->descriptor, b->descriptor) == 0 && (a->is_static != 0) == (b->is_static != 0);
}

static void reply_bindings(const char *id, library *lib) {
    const bendjvm_registration *r = lib->registration;
    pthread_mutex_lock(&output);
    printf("B %s %u", id, r->binding_count);
    for (uint32_t i = 0; i < r->binding_count; i++) {
        const bendjvm_binding *b = &r->bindings[i];
        printf(" %s %s %s %d", b->owner, b->name, b->descriptor, b->is_static ? 1 : 0);
    }
    printf("\n");
    fflush(stdout);
    pthread_mutex_unlock(&output);
}

static int hex_value(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void load(const char *id, const char *hex) {
    size_t length = strlen(hex) / 2;
    char *path = calloc(length + 1, 1);
    for (size_t i = 0; i < length; i++) {
        int high = hex_value(hex[2 * i]), low = hex_value(hex[2 * i + 1]);
        if (high < 0 || low < 0) {
            free(path);
            reply_error(id, "java/lang/IllegalArgumentException: malformed native request");
            return;
        }
        path[i] = (char) (high * 16 + low);
    }
    pthread_mutex_lock(&state);
    for (size_t i = 0; i < library_count; i++) {
        if (strcmp(libraries[i]->path, path) == 0) {
            library *lib = libraries[i];
            pthread_mutex_unlock(&state);
            free(path);
            reply_bindings(id, lib);
            return;
        }
    }
    pthread_mutex_unlock(&state);
    void *dl = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!dl) {
        reply_error(id, "java/lang/UnsatisfiedLinkError: %s: %s", path, dlerror());
        free(path);
        return;
    }
    bendjvm_register_fn reg = (bendjvm_register_fn) dlsym(dl, "bendjvm_register_v1");
    const bendjvm_registration *r = reg ? reg() : NULL;
    const char *problem = NULL;
    char detail[256] = "";
    if (!reg) {
        problem = "missing bendjvm_register_v1";
    } else if (!r) {
        problem = "empty registration";
    } else if (r->abi_version != BENDJVM_PLUGIN_ABI) {
        snprintf(detail, sizeof detail, "unsupported plugin ABI version %u", r->abi_version);
        problem = detail;
    }
    for (uint32_t i = 0; !problem && i < r->binding_count; i++) {
        const bendjvm_binding *b = &r->bindings[i];
        char params[MAX_PARAMS], result;
        if (!b->owner || !b->name || !b->descriptor || !b->function) {
            problem = "incomplete binding";
        } else if (parse_descriptor(b->descriptor, params, &result) < 0) {
            snprintf(detail, sizeof detail, "unsupported native descriptor %s", b->descriptor);
            problem = detail;
        } else if (protected_owner(b->owner)) {
            snprintf(detail, sizeof detail, "cannot bind protected class %s", b->owner);
            problem = detail;
        }
        for (uint32_t j = 0; !problem && j < i; j++) {
            if (same_binding(b, &r->bindings[j])) {
                snprintf(detail, sizeof detail, "duplicate binding %s.%s%s", b->owner, b->name, b->descriptor);
                problem = detail;
            }
        }
    }
    pthread_mutex_lock(&state);
    for (uint32_t i = 0; !problem && i < r->binding_count; i++) {
        for (size_t j = 0; !problem && j < binding_count; j++) {
            if (same_binding(&r->bindings[i], bindings[j].binding)) {
                snprintf(detail, sizeof detail, "conflicting binding %s.%s%s", r->bindings[i].owner, r->bindings[i].name, r->bindings[i].descriptor);
                problem = detail;
            }
        }
    }
    if (problem) {
        pthread_mutex_unlock(&state);
        reply_error(id, "java/lang/UnsatisfiedLinkError: %s: %s", path, problem);
        dlclose(dl);
        free(path);
        return;
    }
    library *lib = calloc(1, sizeof *lib);
    lib->path = path;
    lib->dl = dl;
    lib->registration = r;
    pthread_mutex_init(&lib->lock, NULL);
    libraries = realloc(libraries, (library_count + 1) * sizeof *libraries);
    libraries[library_count++] = lib;
    bindings = realloc(bindings, (binding_count + r->binding_count) * sizeof *bindings);
    for (uint32_t i = 0; i < r->binding_count; i++) {
        bindings[binding_count].lib = lib;
        bindings[binding_count].binding = &r->bindings[i];
        binding_count++;
    }
    pthread_mutex_unlock(&state);
    reply_bindings(id, lib);
}

/* ---- handles ------------------------------------------------------------- */

static int64_t issue_handle(library *lib, int64_t raw) {
    pthread_mutex_lock(&state);
    if (handle_count == handle_capacity) {
        handle_capacity = handle_capacity ? handle_capacity * 2 : 16;
        handles = realloc(handles, handle_capacity * sizeof *handles);
    }
    int64_t id = next_handle++;
    handles[handle_count].id = id;
    handles[handle_count].lib = lib;
    handles[handle_count].raw = raw;
    handle_count++;
    pthread_mutex_unlock(&state);
    return id;
}

static int raw_handle(library *lib, int64_t id, int64_t *raw) {
    int found = 0;
    pthread_mutex_lock(&state);
    for (size_t i = 0; i < handle_count; i++) {
        if (handles[i].id == id && handles[i].lib == lib) {
            *raw = handles[i].raw;
            found = 1;
            break;
        }
    }
    pthread_mutex_unlock(&state);
    return found;
}

static void release_handle(int64_t id) {
    pthread_mutex_lock(&state);
    for (size_t i = 0; i < handle_count; i++) {
        if (handles[i].id == id) {
            handles[i] = handles[--handle_count];
            break;
        }
    }
    pthread_mutex_unlock(&state);
}

/* ---- calls --------------------------------------------------------------- */

typedef struct request {
    char *line; /* owned; tokens point into it */
    struct request *next;
} request;

typedef struct words {
    uint32_t *data;
    size_t count, capacity;
} words;

static int push(words *w, uint32_t value) {
    if (w->count == w->capacity) {
        if (w->capacity >= MAX_REPLY_WORDS) {
            return 0;
        }
        w->capacity = w->capacity ? w->capacity * 2 : 64;
        w->data = realloc(w->data, w->capacity * sizeof *w->data);
    }
    w->data[w->count++] = value;
    return 1;
}

static int push64(words *w, uint64_t bits) {
    return push(w, (uint32_t) (bits >> 32)) && push(w, (uint32_t) bits);
}

static void call(char *line) {
    char *save = NULL;
    strtok_r(line, " \n", &save); /* "C" */
    char *id = strtok_r(NULL, " \n", &save);
    char *owner = strtok_r(NULL, " \n", &save);
    char *name = strtok_r(NULL, " \n", &save);
    char *descriptor = strtok_r(NULL, " \n", &save);
    char *is_static = strtok_r(NULL, " \n", &save);
    char *count_text = strtok_r(NULL, " \n", &save);
    if (!id || !owner || !name || !descriptor || !is_static || !count_text) {
        reply_error(id ? id : "0", "java/lang/IllegalArgumentException: malformed native request");
        return;
    }
    size_t count = strtoul(count_text, NULL, 10);
    uint32_t *in = calloc(count + 1, sizeof *in);
    for (size_t i = 0; i < count; i++) {
        char *word = strtok_r(NULL, " \n", &save);
        if (!word) {
            free(in);
            reply_error(id, "java/lang/IllegalArgumentException: malformed native request");
            return;
        }
        in[i] = (uint32_t) strtoul(word, NULL, 10);
    }
    bendjvm_binding probe = {owner, name, descriptor, (uint32_t) atoi(is_static), 0, 0, 0, NULL};
    binding_entry entry = {NULL, NULL};
    pthread_mutex_lock(&state);
    for (size_t i = 0; i < binding_count; i++) {
        if (same_binding(&probe, bindings[i].binding)) {
            entry = bindings[i];
            break;
        }
    }
    pthread_mutex_unlock(&state);
    if (!entry.binding) {
        char dotted[256];
        snprintf(dotted, sizeof dotted, "%s", owner);
        for (char *p = dotted; *p; p++) {
            if (*p == '/') *p = '.';
        }
        free(in);
        reply_error(id, "java/lang/UnsatisfiedLinkError: %s.%s%s", dotted, name, descriptor);
        return;
    }
    const bendjvm_binding *b = entry.binding;
    char params[MAX_PARAMS], result;
    int argc = parse_descriptor(descriptor, params, &result);
    bendjvm_value *args = calloc((size_t) argc + 1, sizeof *args);
    void **buffers = calloc((size_t) argc + 1, sizeof *buffers);
    int64_t released[32];
    int released_count = 0;
    size_t at = 0;
    const char *failure = NULL;
    for (int i = 0; i < argc && !failure; i++) {
        char p = params[i];
        args[i].kind = kind_of(p);
        if (p == 'J' || p == 'D') {
            if (at + 2 > count) { failure = "malformed"; break; }
            uint64_t bits = ((uint64_t) in[at] << 32) | in[at + 1];
            at += 2;
            if (p == 'D') {
                memcpy(&args[i].as.d, &bits, 8);
            } else {
                args[i].as.j = (int64_t) bits;
                if (b->handle_params >> i & 1) {
                    int64_t raw;
                    if (!raw_handle(entry.lib, args[i].as.j, &raw)) {
                        failure = "handle";
                        break;
                    }
                    if ((b->released_params >> i & 1) && released_count < 32) {
                        released[released_count++] = args[i].as.j;
                    }
                    args[i].as.j = raw;
                }
            }
        } else if (p == 'F') {
            if (at + 1 > count) { failure = "malformed"; break; }
            memcpy(&args[i].as.f, &in[at++], 4);
        } else if (p >= 'A' && p <= 'Z' && p != 'T') {
            if (at + 1 > count) { failure = "malformed"; break; }
            args[i].as.i = (int32_t) in[at++];
        } else {
            if (at + 1 > count) { failure = "malformed"; break; }
            uint32_t tag = in[at++];
            if (tag == 0) {
                args[i].is_null = 1;
                continue;
            }
            if (at + 1 > count) { failure = "malformed"; break; }
            uint32_t n = in[at++];
            if (p == 'T') {
                if (at + n > count) { failure = "malformed"; break; }
                uint16_t *units = calloc((size_t) n + 1, sizeof *units);
                for (uint32_t k = 0; k < n; k++) units[k] = (uint16_t) in[at + k];
                at += n;
                buffers[i] = units;
                args[i].length = n;
                args[i].as.chars = units;
            } else {
                size_t width = (p == 'j' || p == 'd') ? 2 : 1;
                if (at + n * width > count) { failure = "malformed"; break; }
                size_t size = element_size(p);
                unsigned char *data = calloc((size_t) n + 1, size);
                for (uint32_t k = 0; k < n; k++) {
                    if (width == 2) {
                        uint64_t bits = ((uint64_t) in[at + 2 * k] << 32) | in[at + 2 * k + 1];
                        memcpy(data + k * size, &bits, 8);
                    } else if (size == 4) {
                        memcpy(data + k * size, &in[at + k], 4);
                    } else if (size == 2) {
                        uint16_t v = (uint16_t) in[at + k];
                        memcpy(data + k * size, &v, 2);
                    } else {
                        data[k] = (unsigned char) in[at + k];
                    }
                }
                at += n * width;
                buffers[i] = data;
                args[i].length = n;
                args[i].as.data = data;
            }
        }
    }
    words out = {NULL, 0, 0};
    if (failure) {
        reply_error(id, strcmp(failure, "handle") == 0 ? "java/lang/IllegalArgumentException: invalid native handle"
                                                       : "java/lang/IllegalArgumentException: malformed native request");
    } else {
        bendjvm_call c;
        memset(&c, 0, sizeof c);
        c.argc = (uint32_t) argc;
        c.args = args;
        int serial = !entry.lib->registration->thread_safe;
        if (serial) pthread_mutex_lock(&entry.lib->lock);
        int32_t status = b->function(&c);
        if (serial) pthread_mutex_unlock(&entry.lib->lock);
        c.error_class[sizeof c.error_class - 1] = 0;
        c.error_message[sizeof c.error_message - 1] = 0;
        if (status != BENDJVM_OK) {
            const bendjvm_registration *r = entry.lib->registration;
            int registered = 0;
            for (uint32_t k = 0; k < r->exception_count; k++) {
                registered |= strcmp(r->exceptions[k], c.error_class) == 0;
            }
            if (!registered) {
                reply_error(id, "java/lang/IllegalStateException: native code raised unregistered exception %s: %s", c.error_class, c.error_message);
            } else if (c.error_message[0]) {
                reply_error(id, "%s: %s", c.error_class, c.error_message);
            } else {
                reply_error(id, "%s", c.error_class);
            }
        } else if (c.result.kind != kind_of(result)) {
            reply_error(id, "java/lang/IllegalStateException: native function returned the wrong kind");
        } else {
            int ok = 1;
            switch (result) {
                case 'V': break;
                case 'J': {
                    int64_t value = c.result.as.j;
                    if (b->returns_handle) value = issue_handle(entry.lib, value);
                    ok = push64(&out, (uint64_t) value);
                    break;
                }
                case 'D': { uint64_t bits; memcpy(&bits, &c.result.as.d, 8); ok = push64(&out, bits); break; }
                case 'F': { uint32_t bits; memcpy(&bits, &c.result.as.f, 4); ok = push(&out, bits); break; }
                case 'T':
                    if (c.result.is_null) {
                        ok = push(&out, 0xFFFFFFFFu);
                    } else {
                        ok = push(&out, c.result.length);
                        for (uint32_t k = 0; ok && k < c.result.length; k++) ok = push(&out, c.result.as.chars[k]);
                    }
                    break;
                default: ok = push(&out, (uint32_t) c.result.as.i); break;
            }
            for (int i = 0; ok && i < argc; i++) {
                char p = params[i];
                if (!(p >= 'a' && p <= 'z') || args[i].is_null) continue;
                size_t size = element_size(p);
                const unsigned char *data = buffers[i];
                for (uint32_t k = 0; ok && k < args[i].length; k++) {
                    if (size == 8) { uint64_t bits; memcpy(&bits, data + k * 8, 8); ok = push64(&out, bits); }
                    else if (size == 4) { uint32_t bits; memcpy(&bits, data + k * 4, 4); ok = push(&out, bits); }
                    else if (size == 2) { uint16_t v; memcpy(&v, data + k * 2, 2); ok = push(&out, p == 's' ? (uint32_t) (int32_t) (int16_t) v : v); }
                    else ok = push(&out, p == 'b' ? (uint32_t) (int32_t) (int8_t) data[k] : data[k]);
                }
            }
            if (!ok) {
                reply_error(id, "java/lang/OutOfMemoryError: native reply exceeds the payload limit");
            } else {
                for (int k = 0; k < released_count; k++) release_handle(released[k]);
                pthread_mutex_lock(&output);
                printf("W %s %zu", id, out.count);
                for (size_t k = 0; k < out.count; k++) printf(" %" PRIu32, out.data[k]);
                printf("\n");
                fflush(stdout);
                pthread_mutex_unlock(&output);
            }
        }
    }
    for (int i = 0; i < argc; i++) free(buffers[i]);
    free(buffers);
    free(args);
    free(in);
    free(out.data);
}

/* ---- worker pool ---------------------------------------------------------- */

static request *queue_head, *queue_tail;
static int closing;
static pthread_mutex_t queue_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t queue_ready = PTHREAD_COND_INITIALIZER;

static void *worker(void *unused) {
    (void) unused;
    for (;;) {
        pthread_mutex_lock(&queue_lock);
        while (!queue_head && !closing) pthread_cond_wait(&queue_ready, &queue_lock);
        request *r = queue_head;
        if (!r) {
            pthread_mutex_unlock(&queue_lock);
            return NULL;
        }
        queue_head = r->next;
        if (!queue_head) queue_tail = NULL;
        pthread_mutex_unlock(&queue_lock);
        call(r->line);
        free(r->line);
        free(r);
    }
}

int main(void) {
    pthread_t threads[WORKERS];
    for (int i = 0; i < WORKERS; i++) pthread_create(&threads[i], NULL, worker, NULL);
    char *line = NULL;
    size_t capacity = 0;
    while (getline(&line, &capacity, stdin) > 0) {
        if (line[0] == 'L') {
            char *save = NULL;
            strtok_r(line, " \n", &save);
            char *id = strtok_r(NULL, " \n", &save);
            char *hex = strtok_r(NULL, " \n", &save);
            if (id && hex) load(id, hex);
            else reply_error(id ? id : "0", "java/lang/IllegalArgumentException: malformed native request");
        } else if (line[0] == 'C') {
            request *r = calloc(1, sizeof *r);
            r->line = strdup(line);
            pthread_mutex_lock(&queue_lock);
            if (queue_tail) queue_tail->next = r; else queue_head = r;
            queue_tail = r;
            pthread_cond_signal(&queue_ready);
            pthread_mutex_unlock(&queue_lock);
        }
    }
    pthread_mutex_lock(&queue_lock);
    closing = 1;
    pthread_cond_broadcast(&queue_ready);
    pthread_mutex_unlock(&queue_lock);
    for (int i = 0; i < WORKERS; i++) pthread_join(threads[i], NULL);
    free(line);
    return 0;
}
