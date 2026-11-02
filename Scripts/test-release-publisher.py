#!/usr/bin/env python3
"""Offline checks for the release publisher's public-upload boundaries."""
import base64
import hashlib
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location("publisher", Path(__file__).with_name("publish-release.py"))
publisher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publisher)
COMMIT = "a" * 40


class ReleasePublisherTests(unittest.TestCase):
    def setUp(self):
        names = ["Moon-0.3.2-arm64.zip", "Moon-0.3.2-arm64.dmg", "Moon-0.3.2-source.tar.gz",
                 "appcast.xml", "SHA256SUMS.txt", "Install-ReadMe.txt"]
        self.bytes = {name: ("synthetic " + name).encode() for name in names}
        self.plan = {"repository": publisher.REPO, "tag": "v0.3.2-beta", "build": "2026110201",
                     "title": "Synthetic release", "notes": "Fixture", "assets": [
                         {"name": name, "blob": f"{index + 1:040x}", "size": len(self.bytes[name]),
                          "sha256": hashlib.sha256(self.bytes[name]).hexdigest()}
                         for index, name in enumerate(names)]}
        self.calls = []
        self.bad_blob = False
        self.bad_upload = False

    def request(self, url, method="GET", payload=None, binary=False):
        self.calls.append((url, method))
        if "/git/ref/" in url:
            return {"object": {"sha": COMMIT}}
        if "/git/blobs/" in url:
            asset = next(a for a in self.plan["assets"] if url.endswith(a["blob"]))
            data = self.bytes[asset["name"]]
            if self.bad_blob:
                data = bytes([data[0] ^ 1]) + data[1:]
            return {"encoding": "base64", "size": len(data), "content": base64.b64encode(data).decode()}
        if "/releases/tags/" in url:
            raise HTTPError(url, 404, "Missing fixture release", {}, None)
        if url.endswith("/releases?per_page=100") or "/assets?per_page=100" in url:
            return []
        if url.endswith("/releases") and method == "POST":
            return {"id": 123, "draft": True}
        if "uploads.github.com" in url:
            return {"state": "uploaded", "size": len(payload),
                    "digest": "sha256:" + ("0" * 64 if self.bad_upload else hashlib.sha256(payload).hexdigest())}
        if url.endswith("/releases/123") and method == "PATCH":
            return {"html_url": "https://github.com/fixture", "draft": False}
        if "/contents/appcast.xml" in url:
            return {"sha": "f" * 40, "content": base64.b64encode(b"old feed").decode()}
        raise AssertionError("Unexpected fixture request")

    def run_publish(self):
        with patch.dict(os.environ, {"GITHUB_REPOSITORY": publisher.REPO,
                                     "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": COMMIT}), \
                patch.object(publisher, "request", self.request):
            publisher.publish(self.plan)

    def test_assets_precede_release_and_feed_publication(self):
        self.run_publish()
        uploads = [i for i, (url, _) in enumerate(self.calls) if "uploads.github.com" in url]
        release = next(i for i, (url, method) in enumerate(self.calls) if method == "PATCH")
        feed = next(i for i, (_, method) in enumerate(self.calls) if method == "PUT")
        self.assertEqual(len(uploads), 6)
        self.assertLess(max(uploads), release)
        self.assertLess(release, feed)

    def test_altered_blob_stops_before_any_write(self):
        self.bad_blob = True
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.run_publish()
        self.assertTrue(all(method == "GET" for _, method in self.calls))

    def test_uploaded_digest_mismatch_cannot_publish_release_or_feed(self):
        self.bad_upload = True
        with self.assertRaisesRegex(ValueError, "checksum"):
            self.run_publish()
        self.assertFalse(any(method in ("PUT", "PATCH") for _, method in self.calls))

    def test_wrong_repository_stops_before_requests(self):
        self.plan["repository"] = "other/repository"
        with self.assertRaisesRegex(ValueError, "repository"):
            self.run_publish()
        self.assertEqual(self.calls, [])

    def test_path_escape_is_rejected(self):
        self.plan["assets"][0]["name"] = "../outside.zip"
        with self.assertRaisesRegex(ValueError, "asset name"):
            self.run_publish()
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
