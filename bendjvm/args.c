#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>


uint32_t jvm_launch_runner(void) {
  const char *runner = getenv("BENDJVM_RUNNER");
  const char *selected = getenv("BENDJVM_CLASSFILE");
  const char *python = getenv("PYTHON");
  if (!selected) return 2u;
  pid_t child = fork();
  if (child < 0) return 1u;
  if (child == 0) {
    execlp(python ? python : "python3", python ? python : "python3",
           runner ? runner : "scripts/run.py", selected, (char *)0);
    _exit(1);
  }
  int status;
  if (waitpid(child, &status, 0) < 0 || !WIFEXITED(status)) return 1u;
  return (uint32_t)WEXITSTATUS(status);
}
