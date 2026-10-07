
function jvm_launch_runner() {
  const { spawnSync } = require("node:child_process");
  const { resolve } = require("node:path");
  const args = process.argv.slice(2);
  if (!args.some(value => !value.startsWith("-") && !/^\d+$/.test(value)) && process.env.BENDJVM_CLASSFILE) {
    args.push(process.env.BENDJVM_CLASSFILE);
  }
  const result = spawnSync(process.env.PYTHON || "python3",
    [process.env.BENDJVM_RUNNER || resolve("scripts/run.py"), ...args], { stdio: "inherit", env: process.env });
  return result.status == null ? 1 : result.status;
}
