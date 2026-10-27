---
name: ssh-remote-server-access
description: SSH remote access and inventory workflow for the user's research servers R940xa and T630; use non-interactive SSH probes, project directory conventions, CCDS project setup, and server capability notes.
---

# SSH Remote Server Access

## 场景

用户让你访问、检查、管理或在远程服务器上运行科研/生信/工程任务，尤其是 `R940xa` 和 `T630`。

当前 SSH 配置里 1Password 相关内容已被用户注释掉；不要再建议配置 1Password SSH agent，除非用户明确重新启用。

## 基本连接方式

优先使用非交互 SSH，避免卡在密码、passphrase 或授权提示：

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 <host> '<command>'
```

常用 SSH host（当前 `~/.ssh/config` 里是小写；OpenSSH `Host` 匹配在这台 Mac 上不要依赖大小写转换）：

```text
r940xa
t630
```

如果旧笔记里写 `R940xa` / `T630`，实际执行时优先改成小写，避免落到 DNS 解析 `t630` / `r940xa` 而不是 SSH alias。

## 连接前核对别名与地址

连接或批量执行前，先做本地解析（不发起连接），并与清单对照：

```bash
ssh -G <host> | grep -E '^(hostname|user) '
/usr/local/bin/tailscale status | grep <hostname-or-ip>
```

- `hostname` 必须与 `servers.md` 记录的地址一致，或与 tailnet 中同名节点的 IP 一致；节点 owner 必须是本人账号下的节点。
- 不一致时停止，不要沿用新地址执行 apt、写文件或安装。2026-10-14 案例：`wp` 别名被改指向另一个 tailnet 账号（`weipenglink@`）的 `super-super-server`，清单仍是旧地址，等用户确认后才能改。
- `ssh -G` 只读本地配置，不发起连接。

## 项目目录约定

用户现在基本都在 `project/projects` 目录里，用 `ccds` 创建项目。

- R940xa: `~/projects/`
- T630: `~/project/`

目录探查：

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 <host> '
if [ -d ~/projects ]; then
  printf "DIR=~/projects\n"
  find ~/projects -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
elif [ -d ~/project ]; then
  printf "DIR=~/project\n"
  find ~/project -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
else
  echo NOT_FOUND
fi'
```

## CCDS

两台服务器都使用 `ccds` 创建科研项目。检查来源时不要只看 `command -v`，还要看 symlink、pipx 和版本：

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 <host> '
command -v ccds || true
ls -l ~/.local/bin/ccds 2>/dev/null || true
file ~/.local/bin/ccds 2>/dev/null || true
pipx list 2>/dev/null | grep -A4 -B1 cookiecutter-data-science || true
ccds --version 2>&1 || ccds --help 2>&1 | head -n 25 || true'
```

## 环境管理策略

**首选 pixi**（project-local，基于 conda 生态）：
- 环境隔离在项目目录内，不需要全局 activate
- 每个 CCDS 项目里用 `pixi.toml` 管理依赖
- 比 mamba/conda 更 reproducible，不会污染全局环境
- 远程执行时直接 `cd project_dir && pixi run <command>`

**后备 mamba**（全局环境）：
- 当 pixi 不适用时（如需要快速临时环境、或者项目没有 pixi.toml）
- 两台服务器都装在 `/home/gyk/miniforge3/bin/mamba`，版本 `2.5.0`
- batch SSH 的 PATH 不含 Miniforge，需要绝对路径或 source init

## Mamba / Conda 检测注意事项

R940xa 和 T630 都装了 Mamba：路径均为 `/home/gyk/miniforge3/bin/mamba`，版本均为 `2.5.0`。之前 inventory 用普通非登录 shell 没检测到，是因为 batch/login shell 的 PATH 没包含 Miniforge。远程执行时可直接调用绝对路径，或显式 source conda/mamba init。

检查时使用 login shell 和常见安装路径：

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 <host> 'bash -lc '\''
for c in mamba micromamba conda; do command -v $c || true; done
for p in "$HOME/mambaforge/bin/mamba" "$HOME/miniforge3/bin/mamba" "$HOME/miniconda3/bin/mamba" "$HOME/micromamba/bin/micromamba" "$HOME/.local/bin/mamba" "$HOME/.local/bin/micromamba" "/opt/mambaforge/bin/mamba" "/opt/miniforge3/bin/mamba"; do [ -x "$p" ] && echo "$p"; done
'\'''
```

如果 `bash -lc` 仍找不到，但用户确认存在，再检查 shell init 文件中的 PATH/conda hook：

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 <host> 'grep -nE "mamba|conda|miniforge|mambaforge|micromamba" ~/.bashrc ~/.profile ~/.zshrc 2>/dev/null || true'
```

## 软件来源判断

不要只看 `command -v`。尤其远程服务器上常见：

- login shell 与 batch shell PATH 不同
- mamba/conda hook 只在 `.bashrc` 生效
- pipx app 在 `~/.local/bin`
- Docker/Apptainer 可用但普通工具未全局安装

通用探查：

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 <host> '
command -v <tool> || true
ls -l ~/.local/bin/<tool> 2>/dev/null || true
file ~/.local/bin/<tool> 2>/dev/null || true
<tool> --version 2>&1 || <tool> --help 2>&1 | head -n 25 || true'
```

## 已知服务器

完整科研计算清单在：

```text
~/.hermes/server-inventory.md
```

### R940xa

- Hostname: `dell-PowerEdge-R940xa`
- SSH alias: `r940xa`
- User: `gyk`
- OS: Ubuntu 22.04
- CPU: 4× Xeon Platinum 8270 = 208 logical CPUs
- RAM: 1.2 TiB
- GPU: RTX 4090 24GB
- Project dir: `~/projects/`
- Containers: Docker + Apptainer/Singularity
- Mamba: `/home/gyk/miniforge3/bin/mamba`, version `2.5.0`; not on batch SSH PATH by default
- Mamba envs: `base`, `biopython`, `easydock`, `luciferases`, `tensorflow`
- Scheduler: no SLURM/PBS detected
- Disk: root 48T, 88% used
- Best for: GPU, protein/docking/deep learning, large-memory tasks

### T630

- Hostname: `dell-PowerEdge-T630`
- SSH alias: `t630`
- User: `gyk`
- OS: Ubuntu 24.04
- CPU: 2× Xeon E5-2673 v4 = 80 logical CPUs
- RAM: 251 GiB
- GPU: Tesla P40 24GB
- Project dir: `~/project/`
- Data dir: `/data1`, about 1.2T free in latest inventory
- Containers: Docker + Apptainer/Singularity
- Mamba: `/home/gyk/miniforge3/bin/mamba`, version `2.5.0`; not on batch SSH PATH by default
- Pixi: `/home/gyk/.pixi/bin/pixi`; installed but not on batch SSH PATH by default, so use the absolute path in non-interactive SSH commands
- Mamba envs include: `base`, `3t-seq`, `R`, `bedtools`, `biopython`, `crispresso2`, `deeptools`, `fastq-dl`, `hicexplorer`, `luciferases`, `ncbi`, `pandas`, `ppi`, `samtools`, `seaborn`, `seqkit`, `sicris`, `snHiC`, `snakemake`, `surfdock`, `tensorflow`, `transformers`, `trimgalore`, `tuna`
- Detected tools: `samtools`, `bedtools`, `R`, `Rscript`
- Scheduler: no SLURM/PBS detected
- Disk: root 17T, 96% used; prefer `/data1` for new large files
- Best for: CPU-heavy bioinformatics and existing piRNA/RNA-seq project work

## apt 安全巡检验证

- 解析 `apt list --upgradable` 时按包名/套件/版本字段识别，或显式设置 `LC_ALL=C`；不要只匹配英文 `upgradable from`，中文 locale 会漏掉全部候选。
- 安装前用 `dpkg-query` 检查非 ii/hi/rc 状态；若有待配置的排除类内核包，暂缓 apt 安装，因为定点升级其他包也会触发待处理内核配置。
- 实际安装前检查 `apt-get -s install -y --only-upgrade` 的全部 Inst/Conf，确保依赖没有带入非安全来源或排除类包。
- 安全库更新后的 needrestart 可能自动重启 slurmd 与网络服务；安装后重新 SSH 检查关键服务与 uptime，并在日报如实记录，不把未重启主机等同于未重启服务。

## Operational guidance

- Mac mini Hermes 是控制端，R940xa/T630 是计算端。
- 新项目优先在服务器的 project/projects 目录中用 `ccds` 创建。
- 环境管理首选 pixi（project-local），mamba 是后备。
- 大文件写入前先检查磁盘；T630 优先 `/data1`。
- 不要默认有 SLURM/PBS。
- 不要默认 Mamba 不存在；如果普通 SSH 检测不到，优先怀疑 PATH/init 问题。
