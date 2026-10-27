---
name: r-pixi-renv
description: 使用 pixi 配置独立 R 运行时和编译依赖，使用 pak 安装 R 包，并通过 renv 隔离项目包库、锁定版本和恢复环境。适用于新项目 R 环境初始化、已有 pixi/renv 项目恢复及 R 依赖维护；不执行具体生物信息分析。
license: BSD-3-Clause
---

# R 项目环境：pixi + pak + renv

pixi 管理 R、编译器和系统依赖；pak 安装 R 包；renv 管理项目库和锁文件。业务包统一通过启用了 pak 的 `renv::install()` 或 `renv::restore()` 安装。不要用全局 R 库代替项目库。

以下配置来自 `bm_pirna`，参考基线为 Linux、R 4.5.3、renv 1.2.3、pak 0.11.1。已有项目以其配置和锁文件为准。需要核对原项目任务、镜像和例外时，阅读 [项目实例](references/bm-pirna-example.md)。

## 1. 先检查目标项目

从项目根目录操作，检查 `pixi.toml` 或 `pyproject.toml` 中的 pixi 配置、`pixi.lock`、`.Rprofile`、`.Renviron`、`renv.lock`、`renv/activate.R` 和已有依赖声明。

- 确认实际平台和锁定的 R/renv/pak/Bioconductor 版本；不要把 Linux 示例直接用于 macOS 或 Windows，也不要为解决安装失败自动升级版本。
- 已有配置只做必要合并，保留原有启动逻辑、镜像和其他环境。项目使用 `pyproject.toml` 管理 pixi 时，合并对应配置，不再创建第二份清单。
- 恢复前检查锁文件的 `Local` 包及本地 `RemoteUrl` 指向的源文件是否存在。缺失时报告包名、版本和路径，找回匹配源文件后再继续，不能拿已安装包证明可恢复。
- 不复制其他项目的 `.pixi/`、renv 安装库、缓存、凭据或绝对库路径。不改用户级 `.Rprofile`、`.Renviron`、`Makevars`。

## 2. 配置独立的 pixi R 环境

新建 Linux 项目可使用以下 `pixi.toml`；已有项目仅合并缺少的部分。版本是本技能的参考基线，不代表最新版本。

```toml
[workspace]
name = "r-project"
version = "0.1.0"
channels = ["conda-forge"]
platforms = ["linux-64"]

[feature.r.dependencies]
r-base = "==4.5.3"
r-renv = "==1.2.3"
r-pak = "==0.11.1"
compilers = "==2.0.0"
make = "==4.4.1"
pkg-config = "==0.29.2"

[feature.r.tasks]
r-bootstrap = "Rscript --vanilla -e 'renv::activate(project = \".\")'"
r-restore = "RENV_CONFIG_AUTOLOADER_ENABLED=FALSE RENV_CONFIG_PAK_ENABLED=TRUE Rscript --vanilla -e 'renv::load(project = \".\"); renv::restore(project = \".\", prompt = FALSE)'"
r-status = "Rscript --vanilla -e 'renv::status(project = \".\")'"

[environments]
r = { features = ["r"], no-default-feature = true }
```

按需要更改项目名。编译报错时依据实际缺失的头文件或库，在该环境补充系统依赖并固定版本；GLPK 等不属于所有 R 项目的必装项。

已有匹配锁文件时：

```bash
pixi install -e r --locked
```

新项目尚无锁文件，或本次已授权修改了清单时：

```bash
pixi install -e r
```

保留生成的 `pixi.lock`。已有锁文件不匹配时先解释差异，不能静默重新求解整个环境。

## 3. 初始化 renv 并准备项目库中的 pak

仅在新项目尚无 renv 配置时执行初始化：

```bash
pixi run -e r Rscript --vanilla -e 'renv::init(project = ".", bare = TRUE, restart = FALSE)'
```

`r-bootstrap` 是激活任务，不要把它当作每次恢复前的必需步骤。已有完整项目直接进入检查和恢复；缺少 `renv/activate.R` 时，先使用与项目匹配的 renv 恢复激活文件。

在项目 `.Rprofile` 中合并下列代码，把 pak 选项放在激活代码前；已有 `source()` 时不重复添加：

```r
options(renv.config.pak.enabled = TRUE)
source("renv/activate.R")
```

pixi 中有 `r-pak` 并不保证隔离后的项目库有 pak。新项目使用以下独立进程，借助 pixi 的 pak 把固定版本安装到 renv 库；已有项目缺少 pak 时采用同样方法，但将 `pak_version` 改为该项目锁文件中的 pak 版本，无记录时使用其明确固定的 pixi pak 版本。

```bash
RENV_CONFIG_AUTOLOADER_ENABLED=FALSE pixi run -e r Rscript --vanilla -e '
pixi_library <- .Library
target <- renv::paths$library(project = ".")
dir.create(target, recursive = TRUE, showWarnings = FALSE)
pak_version <- "0.11.1"
installed <- file.exists(file.path(target, "pak", "DESCRIPTION"))
matches <- installed && as.character(utils::packageVersion("pak", lib.loc = target)) == pak_version
if (!matches) {
  loadNamespace("pak", lib.loc = pixi_library)
  stopifnot(normalizePath(pixi_library) != normalizePath(target))
  pak::pkg_install(paste0("pak@", pak_version), lib = target, ask = FALSE)
}
stopifnot(as.character(utils::packageVersion("pak", lib.loc = target)) == pak_version)
cat("Project pak:", pak_version, "\nLibrary:", target, "\n")
'
```

该 bootstrap 进程使用 `--vanilla`，通过 `renv::paths$library()` 解析目标库，不激活项目，再从 pixi 库加载 pak 并显式指定安装目标。不要在这个过程增加 `renv::load()`：renv 默认 sandbox 会重写 `.Library` 并改变库搜索路径，影响外部 pak 的发现。结束此进程后再进行业务包安装，使下一会话激活项目并从项目库加载 pak；不要在已加载其他 pak 版本的会话中尝试切换。

`pak::pkg_install()` 的目标库参数是 `lib=`，`renv::install()` 的参数是 `library=`，不能混用。renv 能自动 bootstrap pak，但该行为只保证最低兼容版本，不能代替上述版本检查。

## 4. 恢复已有 R 包环境

完成源文件和 pak 预检后：

```bash
pixi run -e r r-restore
pixi run -e r r-status
```

保留现有 `renv.lock`，恢复时不执行 `snapshot()` 来掩盖缺包或版本差异。模板中的 `RENV_CONFIG_PAK_ENABLED=TRUE` 确保恢复走 pak。

`Rscript --vanilla` 跳过 `.Rprofile` 和 `.Renviron`；仅写在这些文件中的 pak 或镜像设置不会生效。需要镜像时，在恢复调用中、`renv::load()` 和 `restore()` 前显式设置相应选项，见项目实例。已有项目的恢复任务若设置了 `RENV_CONFIG_PAK_ENABLED=FALSE`，需按本次环境配置目标改为 `TRUE`。

## 5. 安装业务包并维护锁文件

在新的项目 R 进程中安装明确版本的包，例如下列已在原项目使用的 ggplot2 版本：

```bash
RENV_CONFIG_PAK_ENABLED=TRUE pixi run -e r Rscript -e 'renv::install("ggplot2@4.0.1", project = ".", prompt = FALSE)'
```

包名和版本替换为目标项目实际需要的依赖；Bioconductor 包遵循项目锁定的 Bioconductor 版本。不要默认安装原项目的物种注释包。

renv 默认的 `implicit` 快照扫描代码依赖。安装成功不代表包已写入锁文件：先更新实际代码或已有 `DESCRIPTION` 等依赖声明。普通脚本项目没有其他声明方式时，可在项目根目录维护 `dependencies.R`，例如：

```r
library(pak)
library(ggplot2)
```

这是供依赖扫描的声明文件，无需在分析时执行。保留其他已声明依赖，然后生成快照：

```bash
pixi run -e r Rscript -e 'renv::snapshot(project = ".", prompt = FALSE)'
```

对照安装目标审阅 `renv.lock` 差异，确认 pak 和新增依赖均已锁定，无意外移除。若需立即增量记录，可使用 `renv::snapshot(project = ".", packages = c("pak", "ggplot2"), update = TRUE, prompt = FALSE)`；此后仍须维护依赖声明，避免后续 implicit 快照遗漏。不要默认使用 `type = "all"` 收录无关库中的包。

## 6. 验证与交付

先运行 `r-status`，再检查项目库和 pak 集成：

```bash
RENV_CONFIG_AUTOLOADER_ENABLED=FALSE RENV_CONFIG_PAK_ENABLED=TRUE pixi run -e r Rscript --vanilla -e '
renv::load(project = ".")
target <- renv::paths$library(project = ".")
stopifnot(normalizePath(.libPaths()[1L]) == normalizePath(target))
stopifnot(isTRUE(renv::config$pak.enabled()))
pak_path <- find.package("pak", lib.loc = target)
loadNamespace("pak", lib.loc = target)
stopifnot(normalizePath(getNamespaceInfo("pak", "path")) == normalizePath(pak_path))
cat(R.version.string, "\nrenv:", as.character(packageVersion("renv")),
    "\npak:", as.character(packageVersion("pak", lib.loc = target)), "\n")
print(.libPaths())
s <- renv::status(project = ".")
stopifnot(isTRUE(s$synchronized))
print(sessionInfo())
'
```

将输出版本与目标锁文件逐项核对，并实际加载本次需要的包。运行真实脚本时从项目根目录执行 `pixi run -e r Rscript scripts/example.R`，脚本路径以文件树为准；R 路径优先使用 `here::here()` 等项目根定位方式。

提交或交付 `pixi.toml`（或对应 `pyproject.toml`）、`pixi.lock`、`renv.lock`、项目 `.Rprofile`、`renv/activate.R`、已有 `renv/settings.json` 和依赖声明。忽略 `.pixi/`、`renv/library/`、`renv/staging/`、缓存及会话文件；配置忽略规则时保留激活文件和设置文件。

报告 R/renv/pak 版本、包库路径、锁文件同步结果、业务包加载结果和未解决的问题。不要将配置检查或语法检查描述成完整安装验证。
