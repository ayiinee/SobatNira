import unittest

from fastapi.testclient import TestClient

from main import app


class DemoApiTest(unittest.TestCase):
    def test_local_fixture_and_health(self):
        with TestClient(app) as client:
            health = client.get("/health")
            self.assertEqual(health.status_code, 200)
            self.assertEqual(health.json()["service"], "sobatnira-ai")

            draft = client.get("/demo/draft")
            self.assertEqual(draft.status_code, 200)
            self.assertEqual(draft.json(), {
                "synthetic": True,
                "lotCode": "DEMO-261114-01",
                "stage": "Penerimaan Tebu",
                "supplier": "Pemasok Demo",
                "netWeightKg": 1250,
            })
