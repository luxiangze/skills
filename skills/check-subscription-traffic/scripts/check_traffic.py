#!/usr/bin/env python3
import argparse
import datetime as dt
import re
import sys
import urllib.request
import urllib.error
from urllib.parse import urlparse


def human_bytes(num):
    if num is None:
        return 'N/A'
    value = float(num)
    units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB']
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f'{int(value)} {unit}' if unit == 'B' else f'{value:.2f} {unit}'
        value /= 1024


def mask_url(url):
    parsed = urlparse(url)
    parts = parsed.path.strip('/').split('/') if parsed.path else []
    masked_parts = []
    for p in parts:
        if len(p) >= 16:
            masked_parts.append(p[:6] + '...' + p[-6:])
        else:
            masked_parts.append(p)
    path = '/' + '/'.join(masked_parts) if masked_parts else parsed.path
    query = '***' if parsed.query else ''
    return parsed._replace(path=path, query=query).geturl()


def parse_userinfo(header):
    info = {}
    if not header:
        return info
    for part in header.split(';'):
        if '=' not in part:
            continue
        key, value = part.strip().split('=', 1)
        key = key.strip().lower()
        value = value.strip()
        if re.fullmatch(r'\d+', value):
            info[key] = int(value)
        else:
            info[key] = value
    return info


def fetch(url, user_agent, timeout):
    req = urllib.request.Request(url, headers={'User-Agent': user_agent, 'Accept': '*/*'})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        status = resp.status
        headers = dict(resp.headers.items())
        body_prefix = resp.read(500)
    userinfo = None
    for k, v in headers.items():
        if k.lower() == 'subscription-userinfo':
            userinfo = v
            break
    return status, headers, userinfo, body_prefix


def build_report(url, status, userinfo):
    info = parse_userinfo(userinfo)
    upload = info.get('upload')
    download = info.get('download')
    total = info.get('total')
    expire = info.get('expire')

    used = upload + download if isinstance(upload, int) and isinstance(download, int) else None
    remaining = max(total - used, 0) if isinstance(total, int) and isinstance(used, int) else None

    lines = []
    lines.append(f'URL: {mask_url(url)}')
    lines.append(f'HTTP: {status}')

    if not userinfo:
        lines.append('No subscription-userinfo header found.')
        return '\n'.join(lines)

    lines.append(f'Upload: {human_bytes(upload)}')
    lines.append(f'Download: {human_bytes(download)}')
    lines.append(f'Used: {human_bytes(used)}')
    lines.append(f'Total: {human_bytes(total)}')
    lines.append(f'Remaining: {human_bytes(remaining)}')

    if isinstance(total, int) and total > 0 and isinstance(used, int):
        lines.append(f'Used percent: {used / total * 100:.2f}%')
        lines.append(f'Remaining percent: {remaining / total * 100:.2f}%')

    if isinstance(expire, int) and expire > 0:
        expire_dt = dt.datetime.fromtimestamp(expire)
        days_left = (expire_dt - dt.datetime.now()).total_seconds() / 86400
        lines.append(f'Expire local: {expire_dt.strftime("%Y-%m-%d %H:%M:%S")}')
        lines.append(f'Days left: {days_left:.1f}')

    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description='Check proxy subscription traffic from Subscription-Userinfo header.')
    parser.add_argument('url')
    parser.add_argument('--user-agent', default='ClashforWindows/0.20.39')
    parser.add_argument('--timeout', type=int, default=20)
    args = parser.parse_args()

    try:
        status, headers, userinfo, body_prefix = fetch(args.url, args.user_agent, args.timeout)
    except urllib.error.HTTPError as e:
        print(f'HTTP error: {e.code} {e.reason}', file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f'Request failed: {e!r}', file=sys.stderr)
        sys.exit(2)

    print(build_report(args.url, status, userinfo))


if __name__ == '__main__':
    main()
