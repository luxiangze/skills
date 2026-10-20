# 条件化请求设计

## state 中保留什么

建议使用命名字段组织上下文：

- `target_model`、`platform`、`phase`：谁执行、在哪里、当前是哪一步。
- `deliverable`、`task_summary`：完成后应产生什么，哪些决策仍未解决。
- `facts`、`inferences`、`unknowns`：已核对事实、主助手推断和未确认信息。
- `effort_definitions`、`sources`：实际支持的档位、界面映射、来源与查阅日期。
- `preferences`：用户偏好；预算未知时写清未知。

摘要是判断依据的一部分。保留会改变选档的事实，不为追求短而删掉关键约束；也不要
上传与选档无关的日志、数据、完整源码或凭据。公开资料可给出来源和经过核对的摘要，
无需逐字复制整篇文章。Jev 是文本输入模型，截图需要先转成标签与上下文。

## 一问一个条件

英文通常适合发送给 Jev；报告仍使用用户语言。关键条件必须写入 `instructions`，
不能只放在问题 ID 中。示例：

```text
Assuming the reviewed plan specifies the architecture, data split and acceptance
checks, which verified effort setting is an appropriate starting point for
implementing it while balancing quality, latency and token cost?
```

可以在同一请求中增加独立的另一问：

```text
If implementation reaches a failure that requires tracing interactions among
tokenization, masking and optimization, which verified setting is appropriate
for that debugging stage, with correctness prioritized over latency?
```

这些条件不是用户已确定的事实。只有实际存在已审查方案时才把它作为事实；否则保留
“假设方案已明确”的条件。运行命令需要的 GPU 时长与助手的思考深度是不同维度。

## 候选项与未知标签

`criteria` 的键可用实际界面标签，值采用准确的当前官方定义。不要套用另一模型的档位
定义，也不要给某个候选写更多“正确、稳妥”之类的诱导性形容词。

保留 `insufficient_information`，说明它涵盖上下文不足、映射未知或无法可靠选择。
若界面有未知标签，在 state 记录，并从可推荐候选中排除；必要时请用户补充该平台的
说明。不要将历史案例里的 High 或 Max 当作待填模板的答案。

[request-template.json](../assets/request-template.json) 是可编辑的结构模板。其选项是
示意，替换成目标模型已核实的实际档位。所有 `{{...}}` 替换标记需要填好。

## 使用脚本和证据文件

脚本支持 Choice 判断，并做输入与返回格式检查；它不负责下载材料、核实模型定义或
判断发送材料的权限，这些工作由使用技能的助手完成。`--dry-run` 只在本地校验，
不读取凭据（包括 `--env-file` 指定的文件）、不创建结果目录、不发起网络请求。

需要读取用户指定的项目 `.env` 时加 `--env-file /path/to/.env`。它只读取
`TYPESAFE_API_KEY`，不会导出其他变量或执行文件内容；显式文件中的密钥覆盖进程密钥。

实际调用成功时保留请求、经过凭据防泄漏处理的返回和元数据。元数据记录请求哈希、
UTC 时间、端点、返回模型、耗时和 token 用量。API 失败时保留已发起调用的记录和
HTTP 状态或错误类型，不打印原始错误体或自动重试。该调用的耗时包含网络开销，
不能作为目标模型执行耗时。

需要固定 Jev 版本复查时，使用实际返回的模型 ID 构造新请求。模型版本固定也不保证
每次判断完全相同。保存原请求，不把后来的修改伪装成先前发送的内容。

## 解释结果

`choice` 是此问题条件下概率最高的选项。`confidence` 是分布的摘要，不是独立验证，
也不能直接跨不同问题、候选集合或模型比较质量。

当各档位接近或选择信息不足时，找出缺失材料或未决偏好，再给暂定建议或补充信息。
当最大概率为 1.00 时，仍说明这是判断而非性能证据，避免显示成“正确率 100%”。
用于分享的结论要附适用条件，不宣传成“已证明某档位最好”。

来源：

- [TypeSafe Choice](https://docs.typesafe.ai/primitives/choice)
- [TypeSafe Confidence](https://docs.typesafe.ai/confidence)
- [TypeSafe HTTP API](https://docs.typesafe.ai/api)
