# 软件环境（module）

2026-10-11 实测：批处理脚本如果是普通 `#!/bin/bash`，里面没有 `module` 命令。第一行必须是 `#!/bin/bash -l`，登录 shell 才会加载 Lmod。`sbatch --wrap` 也不是登录 shell，不要在里面调用 `module`。

交互会话同样要登录 shell：

```bash
srun --pty -p compute -c 1 --mem=1G --time=01:00:00 bash -l
```

作业脚本里把环境写清楚，方便以后复现：

```bash
module purge
module load rosetta/2018.09
module list
```

模块名要带版本。不要依赖“默认最新版”，以后装了新版本，不带版本的加载结果会变。

当前共享模块在 `/share/apps/modulefiles`，软件本体在 `/share/apps/software`。`rosetta/2018.09` 是示例：可执行文件以 `.static.linuxgccrelease` 结尾，`ROSETTA3` 指向 `main/source`，`ROSETTA3_DB` 指向 `main/database`。提交前用 `module avail` 看实际有哪些模块，不要假设还没装的软件已经在里面。

自己编译的软件放在家目录，例如 `~/modulefiles/<name>/<version>.lua`，使用前执行：

```bash
module use --append "$HOME/modulefiles"
module load <name>/<version>
```

`/share/apps` 由管理员维护。不要往共享目录里安装软件，也不要改别人的 modulefile。需要新软件时向管理员申请。
