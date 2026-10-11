# 容器（Apptainer）

计算节点有 Apptainer。GPU 作业里要加 `--nv`，并且作业本身必须申请了 GPU，否则容器里看不到显卡。

```bash
apptainer exec --nv /path/to/image.sif python train.py
```

登录 shell 会把临时文件和缓存放到节点本地磁盘，避免写到 NFS：

- `APPTAINER_TMPDIR=/tmp`
- `APPTAINER_CACHEDIR=/tmp/apptainer-cache-$USER`

脚本如果不是 `#!/bin/bash -l`，这两项不会自动设置。那时在脚本里自己 export，不要把缓存放到共享存储。

镜像文件放在共享存储上，不要放在只存在于登录节点本地的目录里。拉大镜像之前先看 `df -h /share` 和作业节点上的 `df -h /tmp`。2026-10-11 时计算节点的 `/tmp` 大约 98G。作业结束时删掉自己在 `/tmp` 里的临时文件。

节点上没有安装 CUDA toolkit。需要 CUDA 时，用自带 CUDA 的容器，或使用已经打包了 CUDA 运行库的 conda/pip 环境。GPU 节点上的 `nvidia-smi` 只在申请了 GPU 的作业里使用。
