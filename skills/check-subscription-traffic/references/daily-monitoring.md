# Daily Airport Traffic Monitoring

Session-derived pattern for monitoring multiple proxy/VPN/airport subscriptions.

## Use Case

User has multiple airport subscription URLs and wants a daily Telegram summary via Hermes cron / home channel.

## Storage Pattern

Store subscription credentials outside the skill, under private Hermes state:

```text
~/.hermes/private/airport_subscriptions.json
```

Recommended schema:

```json
{
  "subscriptions": [
    {
      "name": "机场 A",
      "url": "https://example.com/subscription/token-a",
      "enabled": true
    },
    {
      "name": "机场 B",
      "url": "https://example.com/subscription/token-b",
      "enabled": true
    }
  ]
}
```

Security:

```bash
chmod 700 ~/.hermes/private
chmod 600 ~/.hermes/private/airport_subscriptions.json
```

Do not save real subscription URLs in memory or skills.

## Snapshot History

Append one JSON record per subscription per run:

```text
~/.hermes/data/airport_traffic_history.jsonl
```

Fields worth storing:

- `checked_at`
- `name`
- `url_masked`
- `used`
- `total`
- `remaining`
- `used_percent`
- `remaining_percent`
- `expire_local`
- `delta_used`
- `daily_rate`
- `projected_days_to_empty`
- `error`

Compare the current `used = upload + download` against the previous snapshot for the same `name` to compute daily consumption.

## Telegram Markdown Template

Telegram Bot Markdown is not full CommonMark. Hyphen lists may not render as bullets reliably. Prefer compact card-style formatting with:

- `##` for the main title only;
- `**bold**` for numbers and key values;
- `*italic*` for short status labels;
- inline-code progress bars for stable monospace rendering;
- literal separators like `━━━━━━━━━━━━━━` instead of Markdown tables.

Current preferred template has no separator lines, no footer, and no management text:

```markdown
📡 **机场流量日报** · `2026-05-04 23:13 CST`
订阅 **4** · 本周消耗 **282.12 MiB**

🏄‍♀️ **iGuge**
`██░░░░░░░░░░░░`  **12.66%**
剩余 **25.32 GiB** / 200.00 GiB
速率 1.07 GiB/d · 到期 2027-04-18（349天）
```

Progress bar convention:

- The bar shows remaining quota, not used quota.
- `█` means remaining; `░` means used.
- Always wrap the bar in inline code so Telegram renders it monospace.

Status emoji heuristic uses absolute remaining traffic:

- `⚠️`: remaining < 5 GiB
- `🟡`: 5 GiB <= remaining <= 20 GiB
- `🏄‍♀️`: remaining > 20 GiB
- `⚪`: unknown

Do not append operational footers such as `To stop or manage...` to Telegram reports.

## Hermes Cron Pattern

Create a deterministic script under:

```text
~/.hermes/scripts/check_airport_traffic_daily.py
```

Hermes cron script paths must be relative to `~/.hermes/scripts/`, not absolute:

```text
script="check_airport_traffic_daily.py"
```

A useful cron prompt:

```text
直接发送脚本输出本身作为 Telegram Markdown 日报，不要添加开场白、解释、总结或代码块。脚本已经会 mask 订阅 URL；不要尝试恢复或暴露完整 URL。如果脚本提示没有启用订阅，就只发送该提示。不要递归创建 cron job。
```

For daily 09:00 CST:

```text
schedule="0 9 * * *"
deliver="telegram"
```

## Delivery Quirk

`deliver="telegram"` targets the Hermes Telegram home channel. In a Telegram gateway/DM setup, this may appear in the currently visible chat as a cron result. If the user wants to avoid that, use a more specific Telegram target if supported by the gateway, or change delivery to local/log-only and route notifications separately.

## Pitfalls

- Do not parse YAML/base64 node bodies unless the `subscription-userinfo` header is absent and the user explicitly asks.
- Try multiple User-Agent values before declaring a provider unsupported.
- For very short intervals between manual tests, projected daily consumption can look silly; treat it as informative only after at least one real daily interval.
- If a provider resets traffic monthly, negative `delta_used` should be treated as a reset rather than negative consumption.
