# bm_pirna 项目实例

本实例依据 2026-10-27 对项目配置、锁文件和已安装包元数据的检查。用于解释技能来源，不是其他项目的必装包清单，也不保证这些版本始终可下载。

## 已观察到的配置

| 配置 | 当前项目的值 |
| --- | --- |
| pixi 平台 | `linux-64` |
| channels | `conda-forge`、`bioconda` |
| R | 清单 `4.5.3.*`，锁定 `4.5.3` |
| renv | `1.2.3` |
| pak | 清单 `>=0.11.1,<0.12`，锁定及已安装版本 `0.11.1` |
| 编译工具 | compilers `2.0.0`、make `4.4.1`、pkg-config `0.29.2` |
| 额外系统依赖 | GLPK `>=5.0,<6`、zlib `>=1.3.1,<2` |
| R 环境 | `r = { features = ["r"], no-default-feature = true }` |
| Bioconductor | `renv.lock` 中为 `3.22` |
| renv 锁文件 | 176 个包条目，包含 Repository、Bioconductor、Local、URL 来源 |

来源文件为项目根目录的 `pixi.toml`、`pixi.lock`、`.Rprofile`、`renv.lock`、`renv/activate.R`，以及项目库和 pixi R 库中的包元数据。未发现 `renv/settings.json`，不能把该文件描述成已存在。

项目与 pixi R 库均已安装 pak 0.11.1。本项目的 renv 1.2.3 支持 install/restore 委托 pak，最低要求 pak 0.9.0；技能使用明确固定的 0.11.1，避免依赖自动 bootstrap 选版。

## 原任务与 pak 调整

原项目的 `r-bootstrap` 使用 `renv::activate(project = ".")`，`r-status` 使用 `renv::status(project = ".")`，二者均通过 `Rscript --vanilla` 执行。

原 `r-restore` 显式设置 `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` 和 `RENV_CONFIG_PAK_ENABLED=FALSE`，然后显式 `renv::load()`、`renv::restore()`。技能模板按用户要求将 pak 开关改为 `TRUE`，这是新技能的选择，并非声称原项目已这样配置。

原 `.Rprofile` 只设置 Bioconductor 镜像并激活 renv：

```r
options(
  BioC_mirror = "https://mirrors.westlake.edu.cn/bioconductor",
  BIOCONDUCTOR_CONFIG_FILE =
    "https://mirrors.westlake.edu.cn/bioconductor/release/config.yaml"
)
source("renv/activate.R")
```

技能应用时在激活前合并 `options(renv.config.pak.enabled = TRUE)`。不得覆盖目标项目已有启动逻辑。

## --vanilla 下显式配置镜像

只有目标项目需要沿用这个镜像时才使用以下命令：

```bash
RENV_CONFIG_AUTOLOADER_ENABLED=FALSE RENV_CONFIG_PAK_ENABLED=TRUE pixi run -e r Rscript --vanilla -e '
options(
  renv.config.pak.enabled = TRUE,
  BioC_mirror = "https://mirrors.westlake.edu.cn/bioconductor",
  BIOCONDUCTOR_CONFIG_FILE =
    "https://mirrors.westlake.edu.cn/bioconductor/release/config.yaml"
)
renv::load(project = ".")
renv::restore(project = ".", prompt = FALSE)
'
```

这保证本进程显式设置了选项，不保证 pak 的所有下载都会改走该镜像。锁文件中的包来源、pak 的仓库解析和实际下载位置仍需核对；镜像不应改变锁定的包版本或 Bioconductor 发布版本。不要把 URL 中的 `release/config.yaml` 当作固定发布快照。

锁文件还记录了 Posit Package Manager `https://packagemanager.posit.co/cran/latest` 和 CRAN `https://cloud.r-project.org`。`latest` 不是日期快照；可复现性依赖包版本、来源和源文件可用性，不能仅凭仓库 URL 保证。

## 恢复预检发现的例外

### 本地注释包源文件缺失

锁文件中的 `org.Bmori.eg.db` 为 0.2，本地来源为：

```text
data/external/bm_ncbi/org.Bmori.eg.db_0.2.tar.gz
```

检查时未在 `data/external/` 找到匹配的源包，尽管项目库已安装 0.2。完整恢复前应找回版本匹配的原始源文件，不能默认替换成其他版本或把该包加到通用配置。

`scripts/00_build_orgdb.R` 构建的是 0.3.0，并包含清理旧目录和 tarball 的操作。不能自动调用它来补回锁定的 0.2。

### 脚本目录与历史文档不一致

实际脚本目录为 `scripts/`，部分 README、AGENTS 和脚本仍引用旧的 `R_scripts/`。运行前检查目标脚本及其内部 source 路径；提炼技能不附带修复这些文件。

`scripts/R/project_paths.R` 使用 `here::here()`；参考运行形式为：

```bash
pixi run -e r Rscript scripts/plot/plot_ping_pong_signature.R
```

该命令展示运行方式，不属于环境配置的必跑测试，也不应在其他项目中直接运行。

## 文档来源

- pak 官方文档：<https://pak.r-lib.org/>。
- renv 的 pak 集成说明：<https://pak.r-lib.org/reference/faq.html>。
- renv 配置说明：<https://rstudio.github.io/renv/reference/config.html>。
- 本地 renv 1.2.3 的 NEWS 和命名空间实现，核对了 pak 启用、目标库、bootstrap 和快照行为。
