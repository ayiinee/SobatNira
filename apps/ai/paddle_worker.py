"""One bounded, restartable native worker. No unbounded inference queue."""
import atexit
import multiprocessing
import threading


def _serve(connection, handler):
    try:
        while True:
            args = connection.recv()
            try:
                connection.send((True, handler(*args)))
            except Exception:
                connection.send((False, None))
    except (EOFError, BrokenPipeError):
        pass
    finally:
        connection.close()


class NativeWorker:
    def __init__(self, handler, timeout=180):
        self.handler = handler
        self.timeout = timeout
        self.lock = threading.Lock()
        self.process = None
        self.connection = None
        atexit.register(self.close)

    def close(self):
        if self.process is not None:
            self.process.terminate()
            self.process.join(timeout=2)
            if self.process.is_alive():
                self.process.kill()
                self.process.join()
            self.process.close()
            self.process = None
        if self.connection is not None:
            self.connection.close()
            self.connection = None

    def run(self, *args):
        if not self.lock.acquire(blocking=False):
            raise RuntimeError("OCR_WORKER_BUSY")
        try:
            if self.process is None or not self.process.is_alive():
                self.close()
                context = multiprocessing.get_context("spawn")
                self.connection, child = context.Pipe()
                self.process = context.Process(target=_serve, args=(child, self.handler), daemon=True)
                self.process.start()
                child.close()
            self.connection.send(args)
            if not self.connection.poll(self.timeout):
                raise RuntimeError("OCR_WORKER_TIMEOUT")
            success, result = self.connection.recv()
            if not success:
                raise RuntimeError("OCR_WORKER_FAILED")
            return result
        except (RuntimeError, OSError, EOFError):
            self.close()
            raise RuntimeError("OCR inference unavailable; retry later") from None
        finally:
            self.lock.release()
