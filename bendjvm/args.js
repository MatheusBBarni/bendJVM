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
