# 分享链接下载

分享 URL 在这些命令中是 `authorization_code`，提取码是另一个参数 `ac`。以下路径和 key 都是示例，必须按实际任务替换。文件内保存完整分享 URL，不附加 shell 命令；macOS/Linux 的私有文件权限设为 `600`，Windows 限制文件 ACL。不要复制原始交付文档中的示例 token。

## macOS / Linux

以下假设可执行文件位于当前目录，授权码文件已由用户安全准备为 `/private/path/share-url.txt`。省略 `-ac` 时由 obsutil 交互提示提取码。

列举少量对象，确认授权范围和完整 key：

```bash
./obsutil share-ls 'file:///private/path/share-url.txt' -limit=20
```

按前缀列举：

```bash
./obsutil share-ls 'file:///private/path/share-url.txt' '-prefix=delivery/sample1/' -limit=1000
```

`-limit` 未设置时默认 1000；未列全时使用返回的 marker 继续，或对已确认规模的范围设 `-limit=0`。小规模预览不代表完整清单。key 应是桶内对象名，列表出现 `obs://bucket/` 时去除协议和桶部分，保留其后全部路径；授权路径已经包含的前缀不能重复拼接。[官方列举说明](https://support.huaweicloud.com/utiltg-obs/obs_11_0063.html)

下载整个授权范围：

```bash
./obsutil share-cp 'file:///private/path/share-url.txt' '/data/delivery' -r -u -vlength -threshold=52428800 '-cpd=/data/task-state/checkpoints' '-o=/data/task-state/reports'
```

只下载某个样本目录：

```bash
./obsutil share-cp 'file:///private/path/share-url.txt' '/data/delivery' '-key=delivery/sample1/' -r -u -vlength -threshold=52428800 '-cpd=/data/task-state/checkpoints' '-o=/data/task-state/reports'
```

只下载一个文件，明确本地文件名：

```bash
./obsutil share-cp 'file:///private/path/share-url.txt' '/data/delivery/sample1_1.fq.gz' '-key=delivery/sample1/sample1_1.fq.gz' -u -vlength -fr '-o=/data/task-state/reports' '-cpd=/data/task-state/checkpoints' -threshold=52428800
```

上述命令选择长度检查；确认对象具有 MD5 元数据且不涉及加密时，可再加 `-vmd5`。若只准备命令，不声称上述占位路径已创建或对象已存在。

## Windows

PowerShell 使用 `./obsutil.exe`（也可用 `& 'C:\tools\obsutil.exe'`）；cmd 使用 `obsutil.exe`，从当前目录启动。下面是 PowerShell 示例：

```powershell
./obsutil.exe share-cp 'file://D:/private/share-url.txt' 'D:\delivery' '-key=delivery/sample1/' -r -u -vlength -threshold=52428800 '-cpd=D:\task-state\checkpoints' '-o=D:\task-state\reports'
```

cmd 将这些单引号改为双引号，不能混用 shell 引用规则。完整 URL 含有 `&` 等字符时必须作为一个参数传入；授权码文件能避免命令行直接展示链接。

## 选择范围与参数

- `-r` 按前缀批量下载，单文件省略它。`-key` 限制下载范围，`share-ls` 则用 `-prefix`；前缀必须在分享授权范围内。
- 默认保留工具规定的目录结构；`-flat` 会改变保存层级，且部分授权前缀格式会使结果为空。仅在用户要求改变布局且预览确认后使用。
- 单文件目标不存在且没有尾部路径分隔符时会被当成文件名；目标已存在时可能被覆盖。使用明确文件名或已确认的目录。
- 自动执行已授权批量任务时可加 `-f`；增加 `-dryRun` 为预演，实际下载时移除。

[官方授权码下载说明](https://support.huaweicloud.com/utiltg-obs/obs_11_0064.html)；恢复、校验及失败排查见 [续传与核验](resume-verify.md)。
