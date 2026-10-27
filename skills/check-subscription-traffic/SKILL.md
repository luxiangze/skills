---
name: check-subscription-traffic
description: Check proxy/VPN/airport subscription remaining traffic by reading the Subscription-Userinfo HTTP response header from a Clash/V2Ray/Surge subscription URL. Use for 机场流量、订阅剩余流量、套餐到期时间、upload/download/total/expire 统计.
---

# Check Subscription Traffic

## Trigger

Use this skill when the user asks to check remaining traffic, used quota, total quota, or expiration time for a proxy/VPN/airport subscription link.

Typical Chinese phrases:

- 机场流量还剩多少
- 检查订阅链接流量
- Clash/V2Ray/Surge 订阅剩余流量
- 套餐什么时候到期

## Safety

Subscription URLs are credentials. Never print the full URL in final responses. Mask path tokens and query strings. Do not save user subscription URLs in this skill or memory.

## Method

1. Request the subscription URL with a Clash-like User-Agent.
2. Read the HTTP response header `subscription-userinfo` case-insensitively.
3. Parse fields like:

```text
upload=0; download=186861617992; total=214748364800; expire=1808059193
```

4. Compute:

```text
used = upload + download
remaining = total - used
used_percent = used / total * 100
remaining_percent = remaining / total * 100
```

5. Convert byte counts to binary units: KiB / MiB / GiB / TiB.
6. Convert `expire` Unix timestamp to local time and days remaining.

## Recommended command

Use the bundled script:

```bash
python3 ~/.hermes/skills/check-subscription-traffic/scripts/check_traffic.py "$SUB_URL"
```

Prefer environment variables for sensitive URLs:

```bash
export SUB_URL='https://example.com/sub/token'
python3 ~/.hermes/skills/check-subscription-traffic/scripts/check_traffic.py "$SUB_URL"
unset SUB_URL
```

## Multiple Subscriptions + Daily Monitoring

For multiple airport subscriptions, store credentials in a private JSON file rather than memory or the skill itself:

```text
~/.hermes/private/airport_subscriptions.json
```

A starter config is available at `templates/airport_subscriptions.example.json`. A detailed Hermes cron pattern, snapshot schema, Telegram Markdown template, and delivery caveats are in `references/daily-monitoring.md`.

Key conventions:

- Set `~/.hermes/private` to mode `700` and the subscription JSON to mode `600`.
- When the user says “更新某个机场/订阅链接”, update only the matching entry in `~/.hermes/private/airport_subscriptions.json`; preserve entry order, `enabled`, and file mode `600`; create a timestamped `.bak` backup first.
- After updating a stored subscription URL, verify both config and provider response: JSON parses, stored URL exactly matches the user-provided URL, and the monitor script or `check_traffic.py` can read `subscription-userinfo`. Report these separately: “配置已更新” is not the same as “订阅可用”.
- If the updated URL still returns `HTTP 403 Forbidden`, probe with several common clients (`Clash`, `Mihomo`, `Surge`, `Shadowrocket`, `Quantumult X`, `Stash`, `sing-box`, `v2rayNG`, `Hiddify`, `NekoBox`) before concluding it is server-side/provider-side. Do not print the full URL while probing or reporting.
- Append daily snapshots to `~/.hermes/data/airport_traffic_history.jsonl` so consumption can be computed as current `used` minus previous `used`.
- For Telegram output, use literal `•` bullets instead of hyphen bullets; Telegram may not render `-` lists reliably in gateway-delivered Markdown.
- For the user's `airport-traffic-daily-report`, use the compact no-footer Telegram format documented in `references/daily-monitoring.md`: no separator lines, no `To stop or manage...` footer, inline-code remaining-quota bars, and status emoji based on absolute remaining traffic (<5 GiB ⚠️, 5–20 GiB 🟡, >20 GiB 🏄‍♀️).
- Hermes cron script paths must be relative to `~/.hermes/scripts/`; use `script="check_airport_traffic_daily.py"`, not an absolute path.
- `deliver="telegram"` means Telegram home channel and may appear in the currently visible Telegram chat depending on gateway routing.

## Output format

Return a compact report:

```text
HTTP: 200
Total: 200.00 GiB
Used: 174.03 GiB / 87.01%
Remaining: 25.97 GiB / 12.99%
Expire: 2027-04-18 22:39:53
Days left: 349.1
```

Do not include the full subscription URL.

## Pitfalls

- Some providers omit `subscription-userinfo`; then try different User-Agents such as `Clash Verge`, `ClashMetaForAndroid`, `Surge iOS`, `Quantumult X`, or `Shadowrocket`.
- `requests` may not be installed in the Hermes runtime. The bundled script uses Python stdlib `urllib.request` only.
- The response body may be YAML/base64 node data; do not parse it unless the header is absent and the user explicitly asks.
