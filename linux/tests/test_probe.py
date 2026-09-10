import http.server
import threading
import time
import unittest

from pingstats.probe import parse_address, probe


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/slow":
            time.sleep(1)
        self.send_response(503 if self.path == "/failure" else 200)
        self.end_headers()

    def log_message(self, *_):
        pass


class ProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.port = cls.server.server_port

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def test_address_modes(self):
        self.assertEqual(parse_address("::1"), ("ping", "::1", None))
        self.assertEqual(parse_address("[::1]:443"), ("tcp", "::1", 443))
        for address in ("-c", "host:0", "host:65536", "http://", ""):
            with self.assertRaises(ValueError):
                parse_address(address)

    def test_local_icmp(self):
        latency, error = probe("127.0.0.1", 1)
        self.assertIsNone(error)
        self.assertGreaterEqual(latency, 0)

    def test_local_tcp(self):
        latency, error = probe("127.0.0.1:%s" % self.port, 1)
        self.assertIsNone(error)
        self.assertGreaterEqual(latency, 0)

    def test_http_success_and_error(self):
        url = "http://127.0.0.1:%s" % self.port
        self.assertIsNone(probe(url, 1)[1])
        self.assertEqual(probe(url + "/failure", 1), (None, "HTTP 503"))

    def test_http_deadline(self):
        start = time.monotonic()
        latency, error = probe("http://127.0.0.1:%s/slow" % self.port, .2)
        self.assertIsNone(latency)
        self.assertIsNotNone(error)
        self.assertLess(time.monotonic() - start, .9)


if __name__ == "__main__":
    unittest.main()
