---
name: slurm-cluster-usage
description: Submit, debug, and size jobs on this Slurm cluster. Use whenever the user mentions sbatch, srun, salloc, Slurm, partitions, GPU, module load, Apptainer, OOM, or asks to run, queue, or check a cluster job, including 提交作业, 作业脚本, 集群, 排队, 显卡, 内存不够, 被杀掉. Also use it before choosing --mem, --cpus-per-task, or a partition. Do not use it for generic programming that never runs on this cluster.
license: BSD-3-Clause
metadata:
  short-description: Submit and size jobs on this Slurm cluster
---

# 集群作业规范

分区名和资源上限记录于 2026-10-11。提交前先核对，配置变了就以命令输出为准。

```bash
sinfo
scontrol show config | grep -E 'DefMemPerCPU|TaskPlugin|JobSubmitPlugins'
scontrol show partition
```

只有 `sinfo` 能看到 `compute`、`gpu`、`gpu-cpu` 时，才套用下面的分区规则。如果 `TaskPlugin` 里没有 `task/cgroup`，`--mem` 还不是硬上限，要直接告诉用户，不要假装已经限制住了。

## 必须遵守

- 计算放到计算节点上，用 `sbatch`、`srun` 或 `salloc`。登录节点只做编辑、提交和查看。
- 脚本第一行用 `#!/bin/bash -l`。2026-10-11 实测：普通 `#!/bin/bash` 里没有 `module`；加上 `-l` 之后 `module load` 可用。`sbatch --wrap` 也不是登录 shell，里面不要用 `module`。
- 每个作业都写明分区、CPU、内存、时间、作业名和输出文件。不写 `--mem` 时，默认是每个申请到的 CPU 1G，不是按核平分整机，也不是不限制。
- `--mem` 在 `task/cgroup` 启用后是 cgroup 硬上限。匿名内存超出会被 OOM kill，`sacct` 状态是 `OUT_OF_MEMORY`。读文件产生的页缓存可以被回收，不等于必须申请那么多内存。`sacct` 的 MaxRSS 包含页缓存，会明显偏大，不要按 MaxRSS 原数申请。
- 先提交一个小任务，确认不是 `OUT_OF_MEMORY`，再提交 array 或大批量作业。
- 只取消自己的作业。array 并发很大、多于 1 块 GPU、超过 32 核或 64G 内存之前，先问用户。
- 对外说明不要写 IP、账号或密码。

## 分区

提交前再跑一次 `sinfo`。2026-10-11 的情况是：

- `compute`：默认分区，纯 CPU。优先用它。
- `gpu`：要 GPU 时用，必须带 `--gres=gpu:N` 或 `--gpus=N`。建议每块 GPU 不超过 16 核。不申请 GPU 却投到 `gpu` 的作业会被改投到 `gpu-cpu`，提交时会看到提示，这不是失败。
- `gpu-cpu`：GPU 节点上的纯 CPU 作业。每个节点最多 80 核、大约 80G。内存申请超过“核数 × 1G”时，Slurm 会把核数调高，所以 4 核 16G 会变成 16 核。不要在这个分区申请 GPU，那样会被改回 `gpu`。

## 做法

1. 看 `sinfo` 和 `squeue`，确认分区和空闲资源。
2. 从本 skill 的 `templates/` 选一个脚本改命令和资源，不要从零发明一套指令。
3. 运行本 skill 目录里的 `scripts/check_sbatch.sh`。它报错就先改脚本。
4. `sbatch` 提交。只操作当前用户自己的作业。
5. 用 `squeue -u "$USER"` 和 `sacct -j <id>` 跟踪。失败时读 [references/troubleshooting.md](references/troubleshooting.md)。

用到再读，不要一次全读：

- [references/cluster-notes.md](references/cluster-notes.md)：存储、登录节点、公平使用
- [references/modules.md](references/modules.md)：module 和环境
- [references/containers.md](references/containers.md)：Apptainer
- [references/troubleshooting.md](references/troubleshooting.md)：排队、OOM、路径错误
