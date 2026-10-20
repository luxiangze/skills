#!/usr/bin/env python3
"""Validate and execute a reviewed TypeSafe Choice request; never retry implicitly."""

import argparse
from datetime import datetime, timezone
import getpass
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import sys
import time
import urllib.error
import urllib.request

ENDPOINT = 'https://api.typesafe.ai/v1/systemone'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def validate_request(request):
    if not isinstance(request, dict):
        raise ValueError('Request must be a JSON object.')
    if not isinstance(request.get('model'), str) or not request['model'].strip():
        raise ValueError('A nonempty TypeSafe model ID is required.')
    if not isinstance(request.get('state'), (str, dict, list)):
        raise ValueError('state must be text, an object or an array.')
    questions = request.get('questions')
    if not isinstance(questions, dict) or not questions:
        raise ValueError('At least one question is required.')
    for question in questions.values():
        if not isinstance(question, dict) or question.get('type') != 'choice':
            raise ValueError('This helper supports Choice questions only.')
        instructions = question.get('instructions')
        if not isinstance(instructions, (str, dict, list)) or not instructions:
            raise ValueError('Each question needs nonempty instructions.')
        criteria = question.get('criteria')
        if not isinstance(criteria, dict) or not 2 <= len(criteria) <= 255:
            raise ValueError('Each Choice needs 2 to 255 candidates.')
        if any(not isinstance(value, (str, dict, list, type(None))) for value in criteria.values()):
            raise ValueError('Candidate descriptions must be text, objects, arrays or null.')
    text = json.dumps(request, ensure_ascii=False)
    if re.search(r'\{\{[A-Z][A-Z0-9_]*\}\}', text):
        raise ValueError('Replace template markers before validating or sending.')
    if re.search(r'apikey_[A-Za-z0-9_]{20,}', text):
        raise ValueError('A credential-like value is present in the request; remove it.')


def unit_number(value):
    return (isinstance(value, (int, float)) and not isinstance(value, bool)
            and math.isfinite(value) and 0 <= value <= 1)


def validate_response(response, request):
    if not isinstance(response, dict) or not isinstance(response.get('model'), str):
        raise ValueError('Missing response model.')
    answers = response.get('answers')
    if not isinstance(answers, dict) or set(answers) != set(request['questions']):
        raise ValueError('Returned question IDs do not match the request.')
    for name, answer in answers.items():
        if not isinstance(answer, dict) or answer.get('type') != 'choice':
            raise ValueError('Expected a Choice answer.')
        probabilities = answer.get('probabilities')
        options = request['questions'][name]['criteria']
        if not isinstance(probabilities, dict) or set(probabilities) != set(options):
            raise ValueError('Returned candidates do not match the request.')
        if not all(unit_number(p) for p in probabilities.values()):
            raise ValueError('Invalid probabilities.')
        if not math.isclose(sum(probabilities.values()), 1, abs_tol=0.02):
            raise ValueError('Probabilities do not sum to approximately one.')
        choice = answer.get('choice')
        if choice not in probabilities or probabilities[choice] < max(probabilities.values()):
            raise ValueError('Choice is not a highest-probability candidate.')
        if not unit_number(answer.get('confidence')):
            raise ValueError('Invalid confidence.')


def write_json(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w', encoding='utf-8') as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2, allow_nan=False)
        handle.write('\n')


def read_env_file_key(path):
    """Read only the single-line TypeSafe key; never evaluate shell syntax."""
    key = ''
    for raw_line in path.read_text(encoding='utf-8-sig').splitlines():
        line = re.sub(r'^export\s+', '', raw_line.strip())
        name, separator, value = line.partition('=')
        if not separator or name.strip() != 'TYPESAFE_API_KEY':
            continue
        try:
            parts = shlex.split(value, comments=True, posix=True)
        except ValueError:
            raise ValueError('Invalid quoting for TYPESAFE_API_KEY in the specified env file.') from None
        if len(parts) > 1:
            raise ValueError('TYPESAFE_API_KEY must be one single-line value.')
        key = parts[0].strip() if parts else ''
    return key


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('request', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--dry-run', action='store_true', help='Validate locally; no network or credentials.')
    parser.add_argument('--prompt-key', action='store_true', help='Hidden input if the environment key is absent.')
    parser.add_argument('--env-file', type=Path, help='Read only TYPESAFE_API_KEY from this file; overrides the process key.')
    parser.add_argument('--timeout', type=float, default=45)
    args = parser.parse_args()
    request = json.loads(args.request.read_text(encoding='utf-8'))
    validate_request(request)
    if args.dry_run:
        print(json.dumps({'status': 'validated_offline', 'model': request['model'],
                          'question_count': len(request['questions'])}))
        return 0
    if args.output_dir is None:
        raise ValueError('--output-dir is required for an API call.')
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        raise ValueError('--timeout must be positive and finite.')
    api_key = (read_env_file_key(args.env_file) if args.env_file is not None
               else os.environ.get('TYPESAFE_API_KEY', '').strip())
    if not api_key and args.prompt_key:
        if not sys.stdin.isatty():
            raise ValueError('--prompt-key requires an interactive terminal.')
        api_key = getpass.getpass('TypeSafe API key: ').strip()
    if not api_key:
        raise ValueError('TYPESAFE_API_KEY is missing; configure it locally, specify --env-file or use --prompt-key.')
    payload = json.dumps(request, ensure_ascii=False, allow_nan=False).encode('utf-8')
    if api_key in payload.decode('utf-8'):
        raise ValueError('The credential must not appear in the request.')
    args.output_dir.mkdir(mode=0o700, parents=True, exist_ok=False)
    write_json(args.output_dir / 'request.json', request)
    metadata = {'started_at': datetime.now(timezone.utc).isoformat(), 'endpoint': ENDPOINT,
                'requested_model': request['model'], 'request_sha256': hashlib.sha256(payload).hexdigest()}
    transport_request = urllib.request.Request(
        ENDPOINT, data=payload, method='POST',
        headers={'Authorization': 'Bearer ' + api_key, 'Content-Type': 'application/json'})
    started = time.monotonic()
    status = 'failed'
    result = None
    try:
        opener = urllib.request.build_opener(NoRedirect())
        with opener.open(transport_request, timeout=args.timeout) as response:
            text = response.read().decode('utf-8').replace(api_key, '[REDACTED]')
        result = json.loads(text)
        write_json(args.output_dir / 'response.json', result)
        validate_response(result, request)
        metadata['returned_model'] = result['model']
        metadata['usage'] = result.get('usage', {})
        status = 'completed'
    except urllib.error.HTTPError as error:
        metadata['http_status'] = error.code
    except (urllib.error.URLError, TimeoutError, UnicodeError, ValueError) as error:
        metadata['error_type'] = type(error).__name__
    finally:
        metadata['status'] = status
        metadata['elapsed_seconds'] = round(time.monotonic() - started, 3)
        write_json(args.output_dir / 'metadata.json', metadata)
    if status != 'completed':
        print(json.dumps({'status': status, 'output_dir': str(args.output_dir),
                          'http_status': metadata.get('http_status'),
                          'error_type': metadata.get('error_type')}), file=sys.stderr)
        return 1
    print(json.dumps({'status': status, 'model': result['model'], 'answers': result['answers'],
                      'usage': result.get('usage', {}), 'output_dir': str(args.output_dir)}, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, TypeError) as error:
        print('Operation failed: ' + str(error), file=sys.stderr)
        sys.exit(2)
