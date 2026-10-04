import json
import unittest
from unittest.mock import Mock, patch

from news_alerts.delivery import send_device_test
from news_alerts.fcm import FcmSender, sender_configuration_error
from news_alerts.models import secret_hash


class NotificationDeliveryTests(unittest.TestCase):
    def setup_device(self):
        repository = Mock()
        repository.get.return_value = {'enabled': True, 'deviceSecretHash': secret_hash('b' * 64),
            'fcmToken': 'one-device-only', 'locationLabel': 'Bengaluru'}
        sender = Mock()
        sender.send.return_value = 'projects/test/messages/message-1'
        return repository, sender

    def test_only_authenticated_saved_device_receives_test(self):
        repository, sender = self.setup_device()
        body, status = send_device_test(repository, 'a' * 32, 'b' * 64, lambda: sender)
        self.assertEqual(status, 200)
        self.assertTrue(body['accepted'])
        self.assertEqual(sender.send.call_args.args[0], 'one-device-only')
        self.assertEqual(sender.send.call_args.args[3], {'type': 'test', 'test': 'true', 'testId': body['testId']})
        self.assertEqual(send_device_test(repository, 'a' * 32, 'b' * 64, lambda: sender)[1], 429)
        self.assertEqual(sender.send.call_count, 1)

    def test_wrong_secret_cannot_trigger_notification(self):
        repository, sender = self.setup_device()
        self.assertEqual(send_device_test(repository, 'a' * 32, 'c' * 64, lambda: sender)[1], 403)
        sender.send.assert_not_called()
        repository.upsert.assert_not_called()

    @patch.dict('os.environ', {'FIREBASE_SERVICE_ACCOUNT_JSON': json.dumps({'project_id': 'old-project'})})
    def test_sender_rejects_old_firebase_project(self):
        self.assertIn('does not match', sender_configuration_error())
        with self.assertRaises(RuntimeError):
            FcmSender()

    @patch('news_alerts.fcm.requests.post')
    def test_fcm_acknowledgment_and_cached_access_token(self, post):
        sender = object.__new__(FcmSender)
        sender._credentials = Mock(valid=True, token='ephemeral-test-token')
        sender._project_id = 'globe-news-ecafc'
        post.return_value.json.return_value = {'name': 'projects/test/messages/test'}
        self.assertEqual(sender.send('device', 'title', 'body', {}), 'projects/test/messages/test')
        sender._credentials.refresh.assert_not_called()
        payload = post.call_args.kwargs['json']['message']
        self.assertEqual(payload['android']['notification']['channel_id'], 'nearby_news')
        self.assertNotIn('topic', payload)
