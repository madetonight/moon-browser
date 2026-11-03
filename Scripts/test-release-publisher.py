#!/usr/bin/env python3
"""Offline regression checks for one-installer releases and safe cleanup."""
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
FEED_COMMIT = "b" * 40


class ReleasePublisherTests(unittest.TestCase):
    def setUp(self):
        self.name = "Moon-0.4.0-arm64.dmg"
        dmg = b"synthetic installer"
        feed = (f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
                f'<sparkle:version>2026110301</sparkle:version><sparkle:shortVersionString>0.4.0</sparkle:shortVersionString>'
                f'<enclosure url="https://github.com/{publisher.REPO}/releases/download/v0.4.0-beta/{self.name}" '
                f'length="{len(dmg)}" sparkle:edSignature="{base64.b64encode(bytes(64)).decode()}"/>'
                '</item></channel></rss>').encode()
        self.bytes = {self.name: dmg, "appcast.xml": feed}
        def artifact(name, number):
            return {"name": name, "blob": f"{number:040x}", "size": len(self.bytes[name]),
                    "sha256": hashlib.sha256(self.bytes[name]).hexdigest()}
        self.plan = {"repository": publisher.REPO, "tag": "v0.4.0-beta", "build": "2026110301",
                     "title": "Fixture", "notes": "Fixture", "keep_latest_only": True,
                     "assets": [artifact(self.name, 1)], "feed": artifact("appcast.xml", 2)}
        self.calls = []; self.bad_blob = False; self.bad_upload = False
        self.fail_feed = False; self.race = False
        self.head = COMMIT; self.feed = b"old feed"; self.exists = False
        self.old_releases = [{"id": 10, "tag_name": "v0.3.7-beta", "draft": False}]
        self.assets = []

    def release(self):
        return {"id": 123, "tag_name": self.plan["tag"], "draft": not self.exists,
                "html_url": "https://github.com/fixture"}

    def request(self, url, method="GET", payload=None, binary=False):
        self.calls.append((url, method))
        if "/git/ref/" in url:
            return {"object": {"sha": "c" * 40 if self.race and self.head == FEED_COMMIT else self.head}}
        if "/git/blobs/" in url:
            asset = next(a for a in self.plan["assets"] + [self.plan["feed"]] if url.endswith(a["blob"]))
            data = self.bytes[asset["name"]]
            if self.bad_blob: data = bytes([data[0] ^ 1]) + data[1:]
            return {"encoding": "base64", "size": len(data), "content": base64.b64encode(data).decode()}
        if "/releases/tags/" in url:
            if self.exists: return self.release()
            raise HTTPError(url, 404, "Missing fixture", {}, None)
        if url.endswith("/releases?per_page=100"):
            return self.old_releases + ([self.release()] if self.exists else [])
        if "/assets?per_page=100" in url: return list(self.assets)
        if url.endswith("/releases") and method == "POST": return self.release()
        if "uploads.github.com" in url:
            item = {"id": 42, "name": self.name, "state": "uploaded", "size": len(payload),
                    "digest": "sha256:" + ("0" * 64 if self.bad_upload else hashlib.sha256(payload).hexdigest())}
            self.assets.append(item); return item
        if url.endswith("/releases/123") and method == "PATCH":
            self.exists = True; return self.release()
        if "/contents/appcast.xml" in url:
            if method == "PUT":
                if self.fail_feed: raise ValueError("Synthetic feed failure")
                self.feed = base64.b64decode(payload["content"]); self.head = FEED_COMMIT
                return {"commit": {"sha": FEED_COMMIT}}
            return {"sha": "f" * 40, "content": base64.b64encode(self.feed).decode()}
        if method == "DELETE":
            if "/releases/assets/" in url:
                self.assets = [a for a in self.assets if not url.endswith('/' + str(a['id']))]
            else: self.old_releases = [r for r in self.old_releases if not url.endswith('/' + str(r['id']))]
            return None
        raise AssertionError(f"Unexpected request: {method} {url}")

    def run_publish(self):
        with patch.dict(os.environ, {"GITHUB_REPOSITORY": publisher.REPO,
                                     "GITHUB_REF": "refs/heads/main", "GITHUB_SHA": self.head}), \
                patch.object(publisher, "request", self.request):
            publisher.publish(self.plan)

    def test_single_installer_and_feed_precede_cleanup(self):
        self.run_publish()
        uploads = [i for i, (url, _) in enumerate(self.calls) if "uploads.github.com" in url]
        feed = next(i for i, (_, method) in enumerate(self.calls) if method == "PUT")
        deletes = [i for i, (_, method) in enumerate(self.calls) if method == "DELETE"]
        self.assertEqual(len(uploads), 1); self.assertLess(uploads[0], feed)
        self.assertLess(feed, min(deletes)); self.assertEqual(self.old_releases, [])

    def test_existing_release_keeps_identical_dmg_and_removes_extra_assets(self):
        self.exists = True
        self.assets = [{"id": 42, "name": self.name, "size": len(self.bytes[self.name]),
                        "digest": "sha256:" + self.plan["assets"][0]["sha256"]},
                       {"id": 43, "name": "old.zip"}]
        self.run_publish()
        self.assertEqual([a['name'] for a in self.assets], [self.name])
        self.assertFalse(any('uploads.github.com' in url for url, _ in self.calls))

    def test_altered_blob_stops_before_any_write(self):
        self.bad_blob = True
        with self.assertRaisesRegex(ValueError, "checksum"): self.run_publish()
        self.assertTrue(all(method == "GET" for _, method in self.calls))

    def test_existing_installer_cannot_be_replaced_with_different_bytes(self):
        self.exists = True
        self.assets = [{"id": 42, "name": self.name, "size": len(self.bytes[self.name]),
                        "digest": "sha256:" + "0" * 64}]
        with self.assertRaisesRegex(ValueError, "refusing to overwrite"): self.run_publish()
        self.assertTrue(all(method == "GET" for _, method in self.calls))

    def test_unrecognized_release_is_preserved_and_blocks_cleanup(self):
        self.old_releases.append({"id": 98, "tag_name": "special-preview"})
        with self.assertRaisesRegex(ValueError, "Unrecognized release"): self.run_publish()
        self.assertTrue(all(method == "GET" for _, method in self.calls))

    def test_uploaded_digest_mismatch_cannot_publish_or_delete(self):
        self.bad_upload = True
        with self.assertRaisesRegex(ValueError, "checksum"): self.run_publish()
        self.assertFalse(any(method in ("PUT", "PATCH", "DELETE") for _, method in self.calls))

    def test_failed_feed_update_never_deletes_downloads(self):
        self.fail_feed = True
        with self.assertRaisesRegex(ValueError, "feed failure"): self.run_publish()
        self.assertFalse(any(method == "DELETE" for _, method in self.calls))

    def test_racing_head_never_deletes_downloads(self):
        self.race = True
        with self.assertRaisesRegex(ValueError, "Main changed"): self.run_publish()
        self.assertFalse(any(method == "DELETE" for _, method in self.calls))

    def test_newer_release_blocks_every_write(self):
        self.old_releases.append({"id": 99, "tag_name": "v0.5.0-beta"})
        with self.assertRaisesRegex(ValueError, "newer release"): self.run_publish()
        self.assertTrue(all(method == "GET" for _, method in self.calls))

    def test_repeated_publish_is_safe(self):
        self.run_publish(); self.calls = []; self.run_publish()
        self.assertFalse(any(method in ("POST", "PUT", "DELETE") for _, method in self.calls))

    def test_extra_app_archive_is_rejected(self):
        self.plan["assets"].append(dict(self.plan["assets"][0]))
        with self.assertRaisesRegex(ValueError, "exactly one"): self.run_publish()
        self.assertEqual(self.calls, [])

    def test_feed_must_target_the_one_current_installer(self):
        self.bytes["appcast.xml"] = self.bytes["appcast.xml"].replace(b".dmg", b".zip")
        self.plan["feed"]["sha256"] = hashlib.sha256(self.bytes["appcast.xml"]).hexdigest()
        with self.assertRaisesRegex(ValueError, "URL mismatch"): self.run_publish()
        self.assertTrue(all(method == "GET" for _, method in self.calls))

    def test_wrong_repository_and_path_escape_are_rejected(self):
        self.plan["repository"] = "other/repository"
        with self.assertRaisesRegex(ValueError, "repository"): self.run_publish()
        self.plan["repository"] = publisher.REPO; self.plan["assets"][0]["name"] = "../outside.dmg"
        with self.assertRaisesRegex(ValueError, "installer name"): self.run_publish()
        self.assertEqual(self.calls, [])


if __name__ == "__main__": unittest.main()
