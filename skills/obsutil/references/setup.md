# 环境与普通下载

## 检查和准备工具

先检查实际运行系统、CPU 架构与现有工具路径，运行 `obsutil version`，记录版本。PATH 中已安装时可直接运行；否则引用完整路径。首次遇到某个版本时查看：

```bash
./obsutil version
./obsutil help share-cp
./obsutil help share-ls
```

官方提供 Windows 64 位、Linux amd64/arm64、macOS 软件包，解压即可使用。缺少工具时从 [官方下载与安装](https://support.huaweicloud.com/utiltg-obs/obs_11_0003.html) 选择匹配包，校验该包对应的 SHA256，再解压并赋予必要执行权限。不自动修改全局 PATH、替换其他版本、关闭系统安全保护或运行包内的系统安装脚本。

官网 `current` 是动态地址；为重复运行保留下载包、SHA256、来源、下载日期和实际版本，并复用已经核验的具体包。官网输出中的 `5.7.9` 仅为示例，不能据此断言已安装或最新版本。macOS 的 CPU 兼容性以实际包和平台验证结果为准，不猜测存在原生 arm64 包或静默安装兼容层。

无需为了 obsutil 创建 Python/Node 环境；如需增加辅助依赖，遵循项目的包管理规范并固定版本。使用分享授权下载时不要顺带要求长期 AK/SK。

## 普通 OBS 对象下载

用户提供 `obs://bucket/key` 且已有合适凭据时，先通过该版本帮助核对普通 `ls` / `cp`；如确实缺少认证，仅要求相应授权方式，不打印凭据或覆盖已有配置。

精确文件下载示例：

```bash
./obsutil cp 'obs://bucket/delivery/sample1/sample1_1.fq.gz' '/data/delivery/sample1_1.fq.gz' -u -vlength -fr '-o=/data/task-state/reports' '-cpd=/data/task-state/checkpoints' -threshold=52428800
```

样本前缀下载示例：

```bash
./obsutil cp 'obs://bucket/delivery/sample1/' '/data/delivery' -r -u -vlength '-o=/data/task-state/reports' '-cpd=/data/task-state/checkpoints' -threshold=52428800
```

只允许源为 OBS、目标为本地的方向，除非用户另行要求其他操作；不能将 `cp` 源和目标倒置。Windows 根据 cmd 或 PowerShell 修改可执行文件路径和引用形式。普通下载同样可能覆盖文件，且增量跳过不等于内容核验。[官方普通下载](https://support.huaweicloud.com/utiltg-obs/obs_11_0018.html)
