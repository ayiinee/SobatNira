import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from paddle_worker import NativeWorker


def synthetic_inference(delay):
    time.sleep(delay)
    return "done"


class NativeWorkerTest(unittest.TestCase):
    def test_timeout_recovers_and_busy_rejects(self):
        worker = NativeWorker(synthetic_inference, timeout=1)
        try:
            with ThreadPoolExecutor(max_workers=1) as pool:
                pending = pool.submit(worker.run, 10)
                deadline = time.monotonic() + 2
                while not worker.lock.locked() and time.monotonic() < deadline:
                    time.sleep(0.01)
                with self.assertRaisesRegex(RuntimeError, "BUSY"):
                    worker.run(0)
                with self.assertRaises(RuntimeError):
                    pending.result(timeout=5)
            worker.timeout = 10
            self.assertEqual(worker.run(0), "done")
        finally:
            worker.close()
