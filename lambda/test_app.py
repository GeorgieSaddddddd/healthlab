# Run: python test_app.py   (no AWS needed: boto3 is mocked)
import json
import sys
from datetime import datetime, timezone
from unittest import mock

sys.modules['boto3'] = mock.MagicMock()
import app  # noqa: E402

assert app.parse_key('uploads/u1/r1') == ('u1', 'r1')

r = app.clean({'summary': 's', 'advice': 'a', 'critical_alert': False, 'status': [
    {'name': 'LDL', 'value': '158', 'status': 'สูง', 'meaning': 'm'},
    {'name': 'X', 'value': '1', 'status': 'weird'}]})
assert [s['status'] for s in r['status']] == ['high', 'unknown']
assert r['critical_alert'] is False
assert app.clean({'status': [{'status': 'Critical'}]})['critical_alert'] is True

mail = app.email_report(app.clean({'summary': 'S', 'advice': 'A', 'status': [
    {'name': 'HDL', 'value': '50', 'status': 'normal', 'meaning': 'good'},
    {'name': 'LDL', 'value': '158', 'status': 'high', 'meaning': 'bad'}]}))
assert mail.index('LDL: 158') < mail.index('HDL: 50')  # abnormal first
assert 'ผิดปกติ 1 รายการ' in mail and 'bad' in mail and 'A' in mail and '🚨' not in mail

now = datetime(2026, 11, 15, tzinfo=timezone.utc)
old = '2026-01-01T00:00:00+00:00'
items = [
    {'userId': 'a', 'reportId': '20260101', 'status': 'DONE', 'abnormal': True, 'createdAt': old},
    {'userId': 'b', 'reportId': '20260101', 'status': 'DONE', 'abnormal': True, 'createdAt': old},
    {'userId': 'b', 'reportId': '20261110', 'status': 'DONE', 'abnormal': False,
     'createdAt': '2026-11-10T00:00:00+00:00'},  # b re-tested and is fine -> no reminder
    {'userId': 'c', 'reportId': '20260101', 'status': 'DONE', 'abnormal': True, 'createdAt': old,
     'remindedAt': old},  # already reminded
    {'userId': 'd', 'reportId': '20261114', 'status': 'DONE', 'abnormal': True,
     'createdAt': '2026-11-14T00:00:00+00:00'},  # too recent
]
assert [i['userId'] for i in app.due_reminders(items, now, 90)] == ['a']
assert sorted(i['userId'] for i in app.due_reminders(items, now, 0)) == ['a', 'd']


def ev(route, body=None, pid=None):
    return {'routeKey': route, 'body': json.dumps(body) if body else None,
            'pathParameters': {'id': pid} if pid else None,
            'requestContext': {'authorizer': {'jwt': {'claims': {'sub': 'u1'}}}}}


assert app.api(ev('POST /upload-url', {'contentType': 'application/zip'}), None)['statusCode'] == 400
app.s3.generate_presigned_post.return_value = {'url': 'https://b.s3.amazonaws.com/', 'fields': {'key': 'k'}}
res = app.api(ev('POST /upload-url', {'contentType': 'image/png'}), None)
assert res['statusCode'] == 200 and json.loads(res['body'])['url']
assert app.s3.generate_presigned_post.call_args.args[1].startswith('uploads/u1/')  # scoped to caller

app.table.get_item.return_value = {}
assert app.api(ev('GET /reports/{id}', pid='nope'), None)['statusCode'] == 404
assert app.api(ev('POST /ask', {'reportId': 'x', 'question': 'hi'}), None)['statusCode'] == 400

# analyzer marks ERROR instead of crashing when Gemini fails
app.s3.get_object.return_value = {'ContentLength': 3, 'ContentType': 'text/plain', 'Body': mock.Mock(read=lambda: b'abc')}
with mock.patch.object(app, 'gemini', side_effect=RuntimeError('boom')), mock.patch.object(app, 'save') as save:
    app.analyzer({'Records': [{'s3': {'bucket': {'name': 'b'}, 'object': {'key': 'uploads/u1/r1'}}}]}, None)
assert save.call_args.kwargs['status'] == 'ERROR'

# console "Create folder" keys are skipped, not analyzed
with mock.patch.object(app, 'save') as save:
    app.analyzer({'Records': [{'s3': {'bucket': {'name': 'b'}, 'object': {'key': k}}}
                              for k in ('uploads/', 'uploads/test-user/')]}, None)
assert not save.called

print('ok')
