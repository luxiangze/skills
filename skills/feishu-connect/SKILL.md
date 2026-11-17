---
name: feishu-connect
description: >
  用官方 lark-cli 把 Muse 接到飞书，并为课题组成员拟定飞书实验日志和组会周报草稿。成员想让 Muse 写飞书日志、接飞书、或把草稿移进实验日志知识库时用这个技能。
license: BSD-3-Clause
---

# Muse × 飞书：接入与日志草稿

## 谁用这个技能

- 课题组成员：自己的飞书账号，在自己电脑或课题组服务器上的 Muse 里用。
- 每人用自己的自建应用和自己的账号。不要共用别人的应用，不要把密钥发进聊天。
- 命令以本机为准：`lark-cli <domain> --help`。以下命令在 lark-cli 1.0.98 / 1.0.100 上验证过。

## 第一步：接入（每人做一次）

1. **安装 lark-cli**：需要 Node.js（实测 Node 24 可用）。
   ```bash
   npm install -g @larksuite/cli
   lark-cli --version
   ```
2. **建自建应用**：到 open.feishu.cn 开发者后台，创建一个企业自建应用，名字用自己的名字，例如“李振辉的飞书 CLI”。也可以用 `lark-cli config init --new`，按浏览器里的提示完成。
   - 权限至少开通 docs、drive、wiki 的读权限；要让应用发通知，再加 im。
   - 应用的可用范围要覆盖自己。权限申请按飞书后台的流程走。
3. **绑定应用**：Secret 从 stdin 读，不要写进命令行、不要发进聊天。
   ```bash
   lark-cli config init --app-id <App ID> --app-secret-stdin
   ```
   Secret 只存在 lark-cli 的加密存储里。
4. **登录个人身份**：设备码流程，命令行给一个网址和验证码，在浏览器里打开确认。
   ```bash
   lark-cli auth login
   ```
   Muse 代跑时用 `lark-cli auth login --no-wait --json`，把 verification URL 发给本人，本人确认后再用 `--device-code` 完成。
   - 分清两个身份：**bot 身份**是应用的身份，只能发通知，看不到知识库；**user 身份**是你本人。日志草稿必须用 user 身份建（`--as user`），文档才归你所有。
5. **验证**：
   ```bash
   lark-cli doctor          # 全 pass
   lark-cli auth status     # 看到自己的账号
   lark-cli wiki +space-list  # 能列出知识库
   ```

## 第二步：拟日志草稿

- 动笔前先问清四件事：日期、今天做了什么（实验/分析）、关键数字或结果、遇到的问题、下一步。
- 模板见 [references/log-templates.md](references/log-templates.md)：今日进展 / 存在问题 / 后续计划；必须记试剂批次、仪器型号、实验条件；原始数据可追溯（贴路径或链接）。
- 写作要求：只记当天科研/实验进展；短，只留 headline 结果和一两个关键数字；原因就是故事本身时原因先给；下一步写动作本身，不写“要先和谁商定”这种安排；不确定的直说。
- 建草稿（先放个人文档库）：
  ```bash
  lark-cli docs +create --as user \
    --title "2026-11-17 实验日志-李振辉" \
    --parent-position my_library \
    --doc-format markdown --content @draft.md
  ```
  - `--parent-position my_library` 是个人文档库，不要用 `my_space`。
  - 多行内容先写进文件，用 `@file` 传，别拼进命令行。
- 建完读回核对：owner 是本人、位置在个人文档库，确认后再报完成。

## 第三步：移进实验日志知识库（本人操作）

- 草稿先放个人文档库；成员自己在飞书里把它移进实验日志知识库自己名下的月份文件夹，路径形如：
  `实验日志/<姓名>_<年级>级_<学位>/2026年实验日志/2026年11月份实验日志/`
- 不知道自己的文件夹在哪：先 `lark-cli wiki +space-list` 找到实验日志知识库，再 `wiki +node-list --space-id <知识库 ID>` 往下找；找不到问管理员。
- 命令行移动可用 `lark-cli wiki +move`，但目标位置须本人确认后再动。

## 组会周报

- 同样先放个人文档库，标题形如「组会周报-李振辉」；内容结构见 [references/log-templates.md](references/log-templates.md)。
- 周报走组会模板：本周进展 / 存在问题 / 下周计划。

## 常见问题

- **直连，不走代理**：飞书走机器直连。不要用 Mac 代理包装器。
- **登录过期或 wiki 看不到**：`lark-cli auth login` 重新登录个人身份，再 `lark-cli doctor` 排查。bot 身份看不到知识库是正常的。
- **Mac 上 SSH 下个人身份读不了**：已知问题（钥匙串不可用），改在能直连的机器上登录。
- **密钥纪律**：App Secret、密码、验证码一律不进聊天、不进技能文件。Muse 看不到也不该要。
