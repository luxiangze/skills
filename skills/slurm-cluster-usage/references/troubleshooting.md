# 排错

先看作业状态，再改资源。不要一失败就加满整机。

## 一直 PENDING

```bash
scontrol show job <jobid>
sinfo
squeue
```

常见原因：申请的核数、内存或 GPU 超过节点上限；分区里的节点都在忙；节点处于 drain 或 down。`Reason=` 会写明卡在哪里。

投到 `gpu` 但没有申请 GPU 时，作业会被改到 `gpu-cpu`。提交命令会打印说明，这不是错误。`gpu-cpu` 每个节点最多大约 80 核、80G。

## OUT_OF_MEMORY

`sacct -j <jobid> --format=JobID,State,Elapsed,MaxRSS` 里状态是 `OUT_OF_MEMORY` 时，是匿名内存超过了 `--mem`。这是硬上限，作业会被杀掉。

不要把 MaxRSS 原样当成下次的 `--mem`。MaxRSS 包含页缓存，读大文件时会远高于程序真正占用的内存。先用一个任务试跑，在确认不会被杀掉的前提下，把 `--mem` 设得比真实占用略高，再批量提交。

## module: command not found

脚本不是登录 shell。改成 `#!/bin/bash -l`，不要用 `sbatch --wrap` 来加载模块。

## couldn't chdir

工作目录在计算节点上不存在。把脚本和数据放到共享存储，并在脚本里 `cd` 到那个路径。

## GPU 不可用

确认同时有 `-p gpu` 和 `--gres=gpu:N`（或 `--gpus=N`）。只投到 `gpu` 分区、不申请 GPU 的作业会进 `gpu-cpu`，那里不会把显卡分给这个作业。容器还要加 `apptainer exec --nv`。

## 查看历史用量

```bash
sacct -j <jobid> --format=JobID,JobName,Partition,State,Elapsed,AllocCPUS,ReqMem,MaxRSS
```

MaxRSS 只作参考。判断下次申请多少内存时，以试跑是否 `OUT_OF_MEMORY` 为准。
