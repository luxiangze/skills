#!/usr/bin/env python3
"""Export Yuque Markdown using an isolated configuration and audit local files."""

import argparse
import json
import os
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote, urlsplit


IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp", ".avif", ".bmp", ".tif", ".tiff", ".ico", ".heic"}
IMAGE_RE = re.compile(r"!\[[^\]]*\]\(([^\n]+?)\)")
LINK_RE = re.compile(r"(?<!!)\[[^\]]*\]\(([^\n]+?)\)")


def private_json(path, value):
    """Create credential-bearing JSON with owner-only permissions."""
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump(value, handle, ensure_ascii=False)
        handle.write("\n")


def read_cookie(path):
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("Cookie 文件必须是 JSON 对象")
    cookie = value.get("data") or value.get("cookies")
    if not isinstance(cookie, (str, list)) or not cookie:
        raise ValueError("Cookie 文件需要非空 data 或 cookies 字段")
    if isinstance(cookie, str) and ("=" not in cookie or "\r" in cookie or "\n" in cookie):
        raise ValueError("Cookie 字符串格式无效")
    if isinstance(cookie, list) and not all(isinstance(item, str) and "=" in item and "\n" not in item and "\r" not in item for item in cookie):
        raise ValueError("Cookie 列表格式无效")
    # Version 2.3.5 uses an inverted cache timestamp branch; zero selects reuse.
    return {"expired": 0, "data": cookie}


def link_target(value):
    value = value.strip()
    if value.startswith("<") and ">" in value:
        return value[1:value.index(">")]
    return re.split(r'\s+[\"\']', value, maxsplit=1)[0]


def audit(root):
    if not root.is_dir():
        raise ValueError("输出目录不存在")
    files = [p for p in root.rglob("*") if p.is_file() and not p.is_symlink() and ".meta" not in p.relative_to(root).parts]
    docs = [p for p in files if p.suffix.lower() == ".md" and p != root / "导出报告.md"]
    remote_images = missing = remote_links = 0
    for doc in docs:
        text = doc.read_text(encoding="utf-8", errors="replace")
        for match in IMAGE_RE.finditer(text):
            target = link_target(match.group(1))
            parsed = urlsplit(target)
            if parsed.scheme in {"http", "https"} or target.startswith("//"):
                remote_images += 1
            elif target and not parsed.scheme and not target.startswith("#"):
                candidate = (doc.parent / unquote(parsed.path)).resolve()
                if not candidate.exists():
                    missing += 1
        for match in LINK_RE.finditer(text):
            parsed = urlsplit(link_target(match.group(1)))
            host = parsed.hostname or ""
            if any(host == domain or host.endswith("." + domain) for domain in ("yuque.com", "nlark.com", "aliyuncs.com")):
                remote_links += 1
    report = root / "导出报告.md"
    lines = report.read_text(encoding="utf-8", errors="replace").splitlines() if report.is_file() else []
    failures = [line for line in lines if "导出失败" in line]
    return {
        "output": str(root), "markdown_documents": len(docs),
        "markdown_files_including_report": len(docs) + int(report.is_file()),
        "empty_markdown_documents": sum(p.stat().st_size == 0 for p in docs),
        "local_image_files": sum(p.suffix.lower() in IMAGE_SUFFIXES for p in files),
        "remote_image_references": remote_images, "missing_local_image_references": missing,
        "remote_yuque_or_attachment_links": remote_links,
        "report_exists": report.is_file(), "report_failure_records": len(failures),
        "report_non_markdown_records": sum("非Markdown" in line or "非 Markdown" in line for line in failures),
        "audit_scope": "本地 Markdown 行内链接静态扫描；不含 HTML、引用式图片或远程可访问性核验",
        "completeness": "未按远端唯一文档清单对账，不能视为完整离线备份",
    }


def audit_status(summary):
    if not summary["markdown_documents"] or not summary["report_exists"]:
        return 1
    if any(summary[key] for key in ("report_failure_records", "missing_local_image_references", "local_image_files", "empty_markdown_documents")):
        return 2
    return 0


def export(args):
    config_path = args.config.expanduser().resolve(strict=True)
    executable = Path(args.ytool).expanduser().resolve(strict=True)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if not isinstance(config, dict):
        raise ValueError("配置必须是 JSON 对象")
    if not os.access(executable, os.X_OK):
        raise ValueError("ytool 不可执行")
    if config.get("host"):
        host = urlsplit(config["host"])
        if host.scheme != "https" or not host.hostname or host.username or host.password:
            raise ValueError("团队 host 必须是无内嵌凭据的 HTTPS 地址")
    scope = config.get("tocRange")
    if not isinstance(scope, list) or not scope or not all(isinstance(item, str) and item for item in scope):
        raise ValueError("请在私有配置中明确指定非空 tocRange（全量为 [\"all\"]）")
    output = args.output.expanduser().absolute()
    if output.is_symlink():
        raise ValueError("输出目录不能是符号链接")
    output = output.resolve()
    protected = [config_path, executable]
    if args.cookie_file:
        protected.append(args.cookie_file.expanduser().resolve(strict=True))
    if any(path == output or output in path.parents for path in protected):
        raise ValueError("输出目录不能包含配置、工具或 Cookie 来源")
    cookie = read_cookie(protected[-1]) if args.cookie_file else None
    if not cookie and not (config.get("userName") and config.get("password")):
        raise ValueError("需要 Cookie 文件或配置中的账号密码")
    if output.exists():
        if not args.backup_existing or not output.is_dir():
            raise ValueError("目标已存在；需要重新导出时显式使用 --backup-existing")
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup = output.with_name(output.name + ".backup-" + stamp)
        if backup.exists():
            raise ValueError("备份路径冲突")
        output.rename(backup)
        print("已有目录备份至：" + str(backup), flush=True)
    output.mkdir(parents=True, mode=0o700)
    (output / ".meta").mkdir(mode=0o700)
    if cookie:
        private_json(output / ".meta" / "cookies.json", cookie)
    config["output"] = str(output)
    with tempfile.TemporaryDirectory(prefix="yuque-export-") as temporary:
        private_json(Path(temporary) / "yuque.config.json", config)
        # Pass arguments separately; credentials stay out of the process arguments.
        result = subprocess.run([str(executable), "pull"], cwd=temporary, check=False)
    summary = audit(output)
    summary["process_exit_code"] = result.returncode
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if result.returncode != 0:
        return 1
    return audit_status(summary)


def main():
    parser = argparse.ArgumentParser(description="导出语雀 Markdown；保留远程图片链接")
    parser.add_argument("--config", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ytool")
    parser.add_argument("--cookie-file", type=Path)
    parser.add_argument("--backup-existing", action="store_true")
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    if not args.validate_only and not (args.config and args.ytool):
        parser.error("导出需要 --config 和 --ytool")
    try:
        if args.validate_only:
            summary = audit(args.output.expanduser().resolve())
            print(json.dumps(summary, ensure_ascii=False, indent=2))
            return audit_status(summary)
        return export(args)
    except (OSError, ValueError) as error:
        # Avoid echoing JSON parsing content or credentials in error messages.
        if isinstance(error, json.JSONDecodeError):
            print("错误：配置或 Cookie 文件不是有效 JSON")
        elif isinstance(error, OSError):
            print("错误：文件或工具访问失败；请检查输入路径和权限")
        else:
            print("错误：配置、Cookie、链接或目标目录无效；请检查输入格式、导出范围和目录冲突")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
