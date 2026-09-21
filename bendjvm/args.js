function jvm_args() {
  const forwarded = process.env.BENDJVM_FLAGS || "";
  return process.argv.slice(2).concat(forwarded ? forwarded.split(" ") : []);
}

function jvm_value(flag, fallback) {
  const args = jvm_args();
  const index = args.indexOf(flag);
  if (index < 0 || index + 1 >= args.length) return fallback;
  const value = Number.parseInt(args[index + 1], 10);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}

function jvm_class_path() {
  if (process.env.BENDJVM_CLASSFILE) return process.env.BENDJVM_CLASSFILE;
  const args = jvm_args();
  for (let i = args.length - 1; i >= 0; i -= 1) {
    if (args[i].endsWith(".class")) return args[i];
  }
  return "";
}
function jvm_class_files() {
  return process.env.BENDJVM_CLASSFILES || jvm_class_path();
}

function jvm_entry_name() {
  if (process.env.BENDJVM_ENTRY) return process.env.BENDJVM_ENTRY;
  const selected = process.env.BENDJVM_CLASSFILE || jvm_args().find(value => value.endsWith(".class")) || "";
  const normalized = selected.replaceAll("\\", "/");
  const absolute = normalized.startsWith("/") || /^[A-Za-z]:\//.test(normalized);
  const slash = normalized.lastIndexOf("/");
  const name = absolute && slash >= 0 ? normalized.slice(slash + 1) : normalized.replace(/^\.\/+/, "");
  return name.endsWith(".class") ? name.slice(0, -6) : name;
}

function jvm_application_args() {
  if (process.env.BENDJVM_APP_ARGS) {
    try {
      const parsed = JSON.parse(process.env.BENDJVM_APP_ARGS);
      if (Array.isArray(parsed)) return parsed.map(value => String(value)).join("\n");
    } catch (_) {}
    return process.env.BENDJVM_APP_ARGS;
  }
  const args = jvm_args();
  const separator = args.indexOf("--");
  if (separator >= 0) return args.slice(separator + 1).join("\n");
  const valueFlags = new Set(["--fuel", "--max-heap"]);
  const result = [];
  for (let index = 0; index < args.length; index += 1) {
    const value = args[index];
    if (value.endsWith(".class")) continue;
    if (valueFlags.has(value)) { index += 1; continue; }
    if (value === "--dump-class" || value === "--disassemble" || value === "--trace") continue;
    result.push(value);
  }
  return result.join("\n");
}

function jvm_fuel() {
  return jvm_value("--fuel", 1000000);
}

function jvm_max_heap() {
  return jvm_value("--max-heap", 1024);
}

function jvm_mode() {
  const args = jvm_args();
  if (args.includes("--dump-class")) return 1;
  if (args.includes("--disassemble")) return 2;
  if (args.includes("--trace")) return 3;
  return 0;
}
