#!/usr/bin/env python3
"""
Integration Test for FCM API + Database

This test verifies the integration between:
- API Gateway endpoints
- Lambda functions
- RDS PostgreSQL database

It does NOT test FCM push notifications or Android app.
Use e2e_test.py for full end-to-end testing.
"""

import os
import sys
import json
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
                    value = value.strip().strip('"').strip("'")
                    os.environ.setdefault(key.strip(), value)

# Load .env file first
load_env_file()

# Load environment variables
API_BASE_URL = os.environ.get('API_BASE_URL', '').rstrip('/')

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

def test_device_registration():
    """Test POST /devices/register endpoint"""
    print('\n[TEST] Device Registration')
    print('=' * 50)
    
    test_user_id = str(uuid.uuid4())
    test_device_id = str(uuid.uuid4())
    test_fcm_token = f'test-fcm-token-{uuid.uuid4()}'
    
    url = f'{API_BASE_URL}/devices/register'
    payload = {
        'user_id': test_user_id,
        'device_id': test_device_id,
        'fcm_token': test_fcm_token,
        'platform': 'android'
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 200:
        print(f'[FAIL] Expected 200, got {status_code}')
        return False
    
    try:
        response_data = json.loads(body)
        if not response_data.get('ok'):
            print(f'[FAIL] Response ok is not true: {response_data}')
            return False
        print('[PASS] Device registration successful')
        return test_user_id, test_device_id
    except json.JSONDecodeError:
        print(f'[FAIL] Invalid JSON response: {body}')
        return False

def test_send_message(user_id, expect_zero_devices=False):
    """Test POST /messages/send endpoint"""
    print('\n[TEST] Send Message')
    print('=' * 50)
    
    url = f'{API_BASE_URL}/messages/send'
    payload = {
        'user_id': user_id,
        'title': 'Integration Test Message',
        'body': 'Test message body',
        'data': {
            'test': 'integration_test'
        }
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 200:
        print(f'[FAIL] Expected 200, got {status_code}')
        return False
    
    try:
        response_data = json.loads(body)
        sent_count = response_data.get('sent_count', 0)
        ok = response_data.get('ok', False)
        
        if expect_zero_devices:
            # When expecting zero devices: ok should be false, sent_count should be 0
            if sent_count != 0:
                print(f'[FAIL] Expected sent_count=0, got {sent_count}')
                return False
            if ok != False:
                print(f'[FAIL] Expected ok=false when sent_count=0, got ok={ok}')
                return False
            print('[PASS] Message send correctly returned ok=false, sent_count=0 (no devices)')
        else:
            # When expecting devices: ok should be true, sent_count should be > 0
            if not ok:
                print(f'[FAIL] Expected ok=true, got ok={ok}')
                return False
            if sent_count == 0:
                print(f'[FAIL] Expected sent_count > 0, got {sent_count}')
                return False
            print(f'[PASS] Message send successful, sent_count={sent_count}')
        return True
    except json.JSONDecodeError:
        print(f'[FAIL] Invalid JSON response: {body}')
        return False

def test_test_status():
    """Test GET /test/status endpoint"""
    print('\n[TEST] Test Status (Non-existent)')
    print('=' * 50)
    
    # Test with non-existent nonce (should return 404)
    nonce = str(uuid.uuid4())
    url = f'{API_BASE_URL}/test/status?nonce={nonce}'
    
    print(f'GET {url}')
    
    status_code, body = http_request(url)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 404:
        print(f'[FAIL] Expected 404 for non-existent nonce, got {status_code}')
        return False
    
    print('[PASS] Test status correctly returned 404 for non-existent nonce')
    return True

def test_test_ack(nonce=None):
    """Test POST /test/ack endpoint"""
    if nonce:
        print('\n[TEST] Test Ack (Valid)')
    else:
        print('\n[TEST] Test Ack (Non-existent)')
    print('=' * 50)
    
    # Test with non-existent nonce (should fail gracefully) or valid nonce
    if not nonce:
        nonce = str(uuid.uuid4())
    url = f'{API_BASE_URL}/test/ack'
    payload = {
        'nonce': nonce
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if nonce:
        # Valid nonce should succeed
        if status_code != 200:
            print(f'[FAIL] Expected 200, got {status_code}')
            return False
        try:
            response_data = json.loads(body)
            if not response_data.get('ok'):
                print(f'[FAIL] Expected ok=true, got {response_data}')
                return False
            print('[PASS] Test ack successful')
            return True
        except json.JSONDecodeError:
            print(f'[FAIL] Invalid JSON response: {body}')
            return False
    else:
        # Should return error for non-existent nonce
        if status_code < 400:
            print(f'[FAIL] Expected error status (4xx), got {status_code}')
            return False
        print('[PASS] Test ack correctly returned error for non-existent nonce')
        return True

def test_device_registration_duplicate(user_id, device_id):
    """Test registering the same device again (should update, not fail)"""
    print('\n[TEST] Device Registration (Duplicate - Should Update)')
    print('=' * 50)
    
    new_fcm_token = f'updated-fcm-token-{uuid.uuid4()}'
    url = f'{API_BASE_URL}/devices/register'
    payload = {
        'user_id': user_id,
        'device_id': device_id,
        'fcm_token': new_fcm_token,
        'platform': 'android'
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    print(f'Note: Registering same device_id again should update FCM token')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 200:
        print(f'[FAIL] Expected 200 for duplicate registration (should update), got {status_code}')
        return False
    
    try:
        response_data = json.loads(body)
        if not response_data.get('ok'):
            print(f'[FAIL] Expected ok=true, got {response_data}')
            return False
        print('[PASS] Duplicate device registration successfully updated')
        return True
    except json.JSONDecodeError:
        print(f'[FAIL] Invalid JSON response: {body}')
        return False

def test_device_registration_ios(user_id):
    """Test registering an iOS device"""
    print('\n[TEST] Device Registration (iOS Platform)')
    print('=' * 50)
    
    device_id = str(uuid.uuid4())
    fcm_token = f'ios-fcm-token-{uuid.uuid4()}'
    url = f'{API_BASE_URL}/devices/register'
    payload = {
        'user_id': user_id,
        'device_id': device_id,
        'fcm_token': fcm_token,
        'platform': 'ios'
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 200:
        print(f'[FAIL] Expected 200, got {status_code}')
        return False
    
    try:
        response_data = json.loads(body)
        if not response_data.get('ok'):
            print(f'[FAIL] Expected ok=true, got {response_data}')
            return False
        print('[PASS] iOS device registration successful')
        return True
    except json.JSONDecodeError:
        print(f'[FAIL] Invalid JSON response: {body}')
        return False

def test_device_registration_invalid_platform(user_id):
    """Test registering with invalid platform (should return 400)"""
    print('\n[TEST] Device Registration (Invalid Platform)')
    print('=' * 50)
    
    device_id = str(uuid.uuid4())
    fcm_token = f'test-fcm-token-{uuid.uuid4()}'
    url = f'{API_BASE_URL}/devices/register'
    payload = {
        'user_id': user_id,
        'device_id': device_id,
        'fcm_token': fcm_token,
        'platform': 'windows'  # Invalid platform
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    print('Note: Platform "windows" is invalid, should return 400')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 400:
        print(f'[FAIL] Expected 400 for invalid platform, got {status_code}')
        return False
    
    print('[PASS] Invalid platform correctly rejected')
    return True

def test_device_registration_missing_fields():
    """Test registering device with missing fields (should return 400)"""
    print('\n[TEST] Device Registration (Missing Fields)')
    print('=' * 50)
    
    url = f'{API_BASE_URL}/devices/register'
    payload = {
        'user_id': str(uuid.uuid4()),
        # Missing device_id, fcm_token, platform
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    print('Note: Missing required fields, should return 400')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 400:
        print(f'[FAIL] Expected 400 for missing fields, got {status_code}')
        return False
    
    print('[PASS] Missing fields correctly rejected')
    return True

def test_send_message_with_test_run(user_id):
    """Test sending message with e2e_test data type (creates test run)"""
    print('\n[TEST] Send Message (Create Test Run)')
    print('=' * 50)
    
    nonce = str(uuid.uuid4())
    url = f'{API_BASE_URL}/messages/send'
    payload = {
        'user_id': user_id,
        'title': 'E2E Test Message',
        'body': 'Test message for creating test run',
        'data': {
            'type': 'e2e_test',
            'nonce': nonce
        }
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    print(f'Generated nonce: {nonce}')
    print('Note: This should create a test_run record in database')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 200:
        print(f'[FAIL] Expected 200, got {status_code}')
        return None
    
    try:
        response_data = json.loads(body)
        # Note: ok may be false if sent_count=0, but test run should still be created
        ok = response_data.get('ok', False)
        sent_count = response_data.get('sent_count', 0)
        
        if ok:
            print(f'[INFO] Message sent successfully (sent_count={sent_count})')
        else:
            print(f'[INFO] Message sent with ok=false (sent_count={sent_count}), but test run should still be created')
        
        # Immediately verify test run was created
        print(f'\n[VERIFY] Checking if test run was created for nonce: {nonce}')
        status_url = f'{API_BASE_URL}/test/status?nonce={nonce}'
        verify_status, verify_body = http_request(status_url)
        
        if verify_status == 200:
            try:
                verify_data = json.loads(verify_body)
                if verify_data.get('nonce') == nonce and verify_data.get('status') == 'PENDING':
                    print(f'[VERIFY] ✓ Test run confirmed created with status=PENDING')
                    return nonce
                else:
                    print(f'[FAIL] Test run exists but has unexpected data: {verify_data}')
                    return None
            except json.JSONDecodeError:
                print(f'[FAIL] Invalid JSON in verification response: {verify_body}')
                return None
        else:
            print(f'[FAIL] Test run was NOT created (status check returned {verify_status})')
            print(f'[FAIL] Verification response: {verify_body}')
            print(f'[FAIL] This means the test_run record was not inserted into the database')
            print(f'[FAIL] Possible reasons:')
            print(f'[FAIL]   1. Database error during CreateTestRun (check Lambda logs)')
            print(f'[FAIL]   2. test_runs table does not exist or has wrong schema')
            print(f'[FAIL]   3. Data format issue preventing test run creation')
            return None
        
    except json.JSONDecodeError:
        print(f'[FAIL] Invalid JSON response: {body}')
        return None

def test_test_status_valid(nonce):
    """Test GET /test/status with valid nonce"""
    print('\n[TEST] Test Status (Valid Nonce)')
    print('=' * 50)
    
    url = f'{API_BASE_URL}/test/status?nonce={nonce}'
    print(f'GET {url}')
    
    status_code, body = http_request(url)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 200:
        print(f'[FAIL] Expected 200, got {status_code}')
        return False
    
    try:
        response_data = json.loads(body)
        if response_data.get('nonce') != nonce:
            print(f'[FAIL] Nonce mismatch: expected {nonce}, got {response_data.get("nonce")}')
            return False
        if response_data.get('status') != 'PENDING':
            print(f'[FAIL] Expected status=PENDING, got status={response_data.get("status")}')
            return False
        print('[PASS] Test status correctly returned PENDING')
        return True
    except json.JSONDecodeError:
        print(f'[FAIL] Invalid JSON response: {body}')
        return False

def test_send_message_user_not_found():
    """Test sending message to non-existent user (should return ok=false)"""
    print('\n[TEST] Send Message (User Not Found)')
    print('=' * 50)
    
    fake_user_id = str(uuid.uuid4())
    url = f'{API_BASE_URL}/messages/send'
    payload = {
        'user_id': fake_user_id,
        'title': 'Test Message',
        'body': 'Test message body',
        'data': {}
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    print('Note: User does not exist, should return ok=false, sent_count=0')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 200:
        print(f'[FAIL] Expected 200, got {status_code}')
        return False
    
    try:
        response_data = json.loads(body)
        ok = response_data.get('ok', True)
        sent_count = response_data.get('sent_count', -1)
        
        if ok != False:
            print(f'[FAIL] Expected ok=false for non-existent user, got ok={ok}')
            return False
        if sent_count != 0:
            print(f'[FAIL] Expected sent_count=0 for non-existent user, got sent_count={sent_count}')
            return False
        print('[PASS] Non-existent user correctly returned ok=false, sent_count=0')
        return True
    except json.JSONDecodeError:
        print(f'[FAIL] Invalid JSON response: {body}')
        return False

def test_send_message_missing_fields():
    """Test sending message with missing fields (should return 400)"""
    print('\n[TEST] Send Message (Missing Fields)')
    print('=' * 50)
    
    url = f'{API_BASE_URL}/messages/send'
    payload = {
        'user_id': str(uuid.uuid4()),
        # Missing title and body
    }
    
    print(f'POST {url}')
    print(f'Payload: {json.dumps(payload, indent=2)}')
    print('Note: Missing required fields, should return 400')
    
    status_code, body = http_request(url, method='POST', data=payload)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 400:
        print(f'[FAIL] Expected 400 for missing fields, got {status_code}')
        return False
    
    print('[PASS] Missing fields correctly rejected')
    return True

def test_test_status_missing_nonce():
    """Test GET /test/status without nonce parameter (should return 400)"""
    print('\n[TEST] Test Status (Missing Nonce)')
    print('=' * 50)
    
    url = f'{API_BASE_URL}/test/status'
    print(f'GET {url}')
    print('Note: Missing nonce parameter, should return 400')
    
    status_code, body = http_request(url)
    print(f'Response: HTTP {status_code}')
    print(f'Body: {body}')
    
    if status_code != 400:
        print(f'[FAIL] Expected 400 for missing nonce, got {status_code}')
        return False
    
    print('[PASS] Missing nonce parameter correctly rejected')
    return True

def main():
    """Run all integration tests"""
    print('=' * 50)
    print('FCM API Integration Tests')
    print('=' * 50)
    print(f'API Base URL: {API_BASE_URL}')
    
    tests_passed = 0
    tests_failed = 0
    user_id = None
    device_id = None
    
    # Test Suite 1: Device Registration
    print('\n' + '=' * 50)
    print('Test Suite 1: Device Registration')
    print('=' * 50)
    
    # Test 1.1: Basic Device Registration
    result = test_device_registration()
    if result:
        tests_passed += 1
        user_id, device_id = result
    else:
        tests_failed += 1
        print('[SKIP] Cannot continue without successful device registration')
        user_id = str(uuid.uuid4())  # Use dummy user_id for remaining tests
    
    if user_id and device_id:
        # Test 1.2: Duplicate Registration (should update)
        if test_device_registration_duplicate(user_id, device_id):
            tests_passed += 1
        else:
            tests_failed += 1
        
        # Test 1.3: Register iOS Device
        if test_device_registration_ios(user_id):
            tests_passed += 1
        else:
            tests_failed += 1
    
    # Test 1.4: Invalid Platform
    if user_id and test_device_registration_invalid_platform(user_id):
        tests_passed += 1
    else:
        tests_failed += 1
    
    # Test 1.5: Missing Fields
    if test_device_registration_missing_fields():
        tests_passed += 1
    else:
        tests_failed += 1
    
    # Test Suite 2: Send Message
    print('\n' + '=' * 50)
    print('Test Suite 2: Send Message')
    print('=' * 50)
    
    if user_id:
        # Test 2.1: Send Message (no devices found)
        if test_send_message(user_id, expect_zero_devices=True):
            tests_passed += 1
        else:
            tests_failed += 1
        
        # Test 2.2: Send Message with Test Run (creates test run record)
        test_run_nonce = test_send_message_with_test_run(user_id)
        if test_run_nonce:
            # Verify test run was actually created by checking status
            url = f'{API_BASE_URL}/test/status?nonce={test_run_nonce}'
            status_code, body = http_request(url)
            if status_code == 200:
                try:
                    response_data = json.loads(body)
                    if response_data.get('status') == 'PENDING':
                        tests_passed += 1
                        print('[PASS] Test run verified in database')
                    else:
                        tests_failed += 1
                        print(f'[FAIL] Test run exists but status is not PENDING: {response_data.get("status")}')
                        test_run_nonce = None
                except json.JSONDecodeError:
                    tests_failed += 1
                    print('[FAIL] Test run may not have been created (status check failed)')
                    test_run_nonce = None
            else:
                tests_failed += 1
                print(f'[FAIL] Test run was not created (status check returned {status_code})')
                test_run_nonce = None
        else:
            tests_failed += 1
            test_run_nonce = None
        
        # Test 2.3: Send Message to Non-existent User
        if test_send_message_user_not_found():
            tests_passed += 1
        else:
            tests_failed += 1
    else:
        test_run_nonce = None
    
    # Test 2.4: Missing Fields
    if test_send_message_missing_fields():
        tests_passed += 1
    else:
        tests_failed += 1
    
    # Test Suite 3: Test Status
    print('\n' + '=' * 50)
    print('Test Suite 3: Test Status')
    print('=' * 50)
    
    # Test 3.1: Test Status (non-existent)
    if test_test_status():
        tests_passed += 1
    else:
        tests_failed += 1
    
    # Test 3.2: Test Status (valid nonce)
    if test_run_nonce:
        if test_test_status_valid(test_run_nonce):
            tests_passed += 1
        else:
            tests_failed += 1
    else:
        print('[SKIP] Test Status (Valid) - no test run created')
    
    # Test 3.3: Test Status (missing nonce)
    if test_test_status_missing_nonce():
        tests_passed += 1
    else:
        tests_failed += 1
    
    # Test Suite 4: Test Acknowledgment
    print('\n' + '=' * 50)
    print('Test Suite 4: Test Acknowledgment')
    print('=' * 50)
    
    # Test 4.1: Test Ack (valid nonce) - ack the test run we created, then verify status
    if test_run_nonce:
        # Double-check that test run still exists before attempting to ack
        print(f'\n[VERIFY] Verifying test run exists before ack: nonce={test_run_nonce}')
        url = f'{API_BASE_URL}/test/status?nonce={test_run_nonce}'
        status_code, body = http_request(url)
        if status_code != 200:
            tests_failed += 1
            print(f'[FAIL] Test run no longer exists (status check returned {status_code}) before ack attempt')
            print(f'[FAIL] Response: {body}')
            test_run_nonce = None
        else:
            try:
                response_data = json.loads(body)
                status = response_data.get('status')
                if status != 'PENDING':
                    tests_failed += 1
                    print(f'[FAIL] Test run status is {status}, expected PENDING before ack')
                    test_run_nonce = None
                else:
                    print(f'[VERIFY] Test run confirmed exists with status=PENDING, proceeding with ack')
                    if test_test_ack(test_run_nonce):
                        tests_passed += 1
                        
                        # Test 4.2: Verify status changed to ACKED
                        print('\n[TEST] Test Status (After Ack - Should be ACKED)')
                        print('=' * 50)
                        url = f'{API_BASE_URL}/test/status?nonce={test_run_nonce}'
                        status_code, body = http_request(url)
                        if status_code == 200:
                            try:
                                response_data = json.loads(body)
                                if response_data.get('status') == 'ACKED':
                                    print('[PASS] Test status correctly shows ACKED after acknowledgment')
                                    tests_passed += 1
                                else:
                                    print(f'[FAIL] Expected status=ACKED, got status={response_data.get("status")}')
                                    tests_failed += 1
                            except json.JSONDecodeError:
                                print(f'[FAIL] Invalid JSON response: {body}')
                                tests_failed += 1
                        else:
                            print(f'[FAIL] Expected 200, got {status_code}')
                            tests_failed += 1
                    else:
                        tests_failed += 1
            except json.JSONDecodeError:
                tests_failed += 1
                print(f'[FAIL] Invalid JSON when verifying test run: {body}')
                test_run_nonce = None
    else:
        print('[SKIP] Test Ack (Valid) and status verification - no test run created')
    
    # Summary
    print('\n' + '=' * 50)
    print('Test Summary')
    print('=' * 50)
    print(f'Passed: {tests_passed}')
    print(f'Failed: {tests_failed}')
    print(f'Total: {tests_passed + tests_failed}')
    print(f'Success Rate: {(tests_passed / (tests_passed + tests_failed) * 100):.1f}%')
    
    if tests_failed > 0:
        print('\n[FAIL] Some tests failed')
        sys.exit(1)
    else:
        print('\n[SUCCESS] All integration tests passed!')
        sys.exit(0)

if __name__ == '__main__':
    main()

