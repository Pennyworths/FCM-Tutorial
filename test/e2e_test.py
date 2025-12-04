#!/usr/bin/env python3

import os
import sys
import json
import time
import uuid
from urllib.parse import urljoin
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from pathlib import Path

def load_env_file():
    """Load .env file if it exists"""
    env_path = Path(__file__).parent / '.env'
    if env_path.exists():
        print(f'[INFO] Loading environment from {env_path}')
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Remove quotes if present
                    value = value.strip().strip('"').strip("'")
                    os.environ.setdefault(key.strip(), value)

# Load .env file first
load_env_file()

# Load environment variables
API_BASE_URL = os.environ.get('API_BASE_URL', '').rstrip('/')
TEST_USER_ID = os.environ.get('TEST_USER_ID', 'debug-user-1')
TIMEOUT_SECONDS = int(os.environ.get('TIMEOUT_SECONDS', '30'))

if not API_BASE_URL:
    print('[ERROR] API_BASE_URL is not set', file=sys.stderr)
    sys.exit(1)

def http_request(url, method='GET', headers=None, data=None):
    """Make HTTP request and return (status_code, body)"""
    if headers is None:
        headers = {}
    
    if data:
        headers['Content-Type'] = 'application/json'
        if isinstance(data, dict):
            data = json.dumps(data).encode('utf-8')
    
    req = Request(url, data=data, headers=headers, method=method)
    
    try:
        with urlopen(req) as response:
            body = response.read().decode('utf-8')
            return (response.status, body)
    except HTTPError as e:
        body = e.read().decode('utf-8') if e.fp else ''
        return (e.code, body)
    except URLError as e:
        raise Exception(f'Request failed: {e.reason}')

def main():
    try:
        # 1. Generate nonce (UUID)
        nonce = str(uuid.uuid4())
        print(f'[INFO] Using nonce = {nonce}')

        # 2. POST /messages/send
        send_url = f'{API_BASE_URL}/messages/send'
        print(f'[INFO] POST {send_url}')

        payload = {
            'user_id': TEST_USER_ID,
            'title': 'FCM E2E Test',
            'body': 'Test message',
            'data': {
                'type': 'e2e_test',
                'nonce': nonce,
            },
        }

        print(f'[DEBUG] Payload: {json.dumps(payload)}')

        status_code, body = http_request(send_url, method='POST', data=payload)
        print(f'[INFO] /messages/send HTTP {status_code}, body={body}')

        if status_code >= 400:
            print('[ERROR] /messages/send returned error', file=sys.stderr)
            sys.exit(1)

        # 3. Poll GET /test/status?nonce={nonce}
        status_url = f'{API_BASE_URL}/test/status?nonce={nonce}'
        deadline = time.time() + TIMEOUT_SECONDS

        print(f'[INFO] Start polling {status_url} for up to {TIMEOUT_SECONDS}s')

        while time.time() < deadline:
            try:
                status_code, body = http_request(status_url)
                print(f'[DEBUG] GET {status_url} -> HTTP {status_code}, body={body}')

                if status_code == 200:
                    try:
                        status_data = json.loads(body)
                        status = (status_data.get('status') or status_data.get('Status') or '').upper()
                    except (json.JSONDecodeError, KeyError):
                        # If JSON parse fails, try simple string matching
                        if 'ACKED' in body.upper():
                            print('[SUCCESS] Status became ACKED 🎉')
                            sys.exit(0)
                        time.sleep(2)
                        continue

                    if status == 'ACKED':
                        print('[SUCCESS] Status became ACKED 🎉')
                        sys.exit(0)
            except Exception as e:
                # Continue polling on error
                print(f'[DEBUG] Polling error: {e}')

            time.sleep(2)

        print('[ERROR] TIMEOUT waiting for status=ACKED', file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f'[ERROR] Test failed: {e}', file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
