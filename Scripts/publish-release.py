#!/usr/bin/env python3
"""Publish locally signed assets through GitHub Actions, without signing keys.

Only a main-branch release manifest triggers this workflow. Artifact blobs stay
outside the source tree. Their lengths and SHA-256 digests must match before any
release is created. The signed appcast is published only after every asset.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

REPO = "madetonight/moon-browser"
API = f"https://api.github.com/repos/{REPO}"
LIMIT = 64 * 1024 * 1024


def require(condition, message):
    if not condition:
        raise ValueError(message)


def request(url, method="GET", payload=None, binary=False):
    require(url.startswith(API + "/") or url.startswith(f"https://uploads.github.com/repos/{REPO}/"),
            "Unexpected API destination")
    headers = {"Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
               "Accept": "application/vnd.github+json", "User-Agent": "Moon-release",
               "X-GitHub-Api-Version": "2022-11-28"}
    if payload is not None:
        if binary:
            headers["Content-Type"] = "application/octet-stream"
        else:
            payload = json.dumps(payload).encode()
            headers["Content-Type"] = "application/json"
    with urlopen(Request(url, data=payload, headers=headers, method=method), timeout=120) as response:
        data = response.read(LIMIT * 2 + 1)
        require(len(data) <= LIMIT * 2, "API response too large")
        return json.loads(data)


def validate_manifest(plan):
    require(plan["repository"] == REPO, "Wrong release repository")
    require(re.fullmatch(r"v\d+\.\d+\.\d+-beta", plan["tag"]) is not None, "Invalid beta tag")
    require(re.fullmatch(r"\d+", plan["build"]) is not None, "Invalid build")
    require(1 <= len(plan["assets"]) <= 10, "Invalid asset count")
    names = set()
    for asset in plan["assets"]:
        name = asset["name"]
        require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,100}", name) is not None, "Invalid asset name")
        require(name not in names, "Duplicate release asset")
        names.add(name)
        require(re.fullmatch(r"[a-f0-9]{40}", asset["blob"]) is not None, "Invalid blob")
        require(re.fullmatch(r"[a-f0-9]{64}", asset["sha256"]) is not None, "Invalid digest")
        require(type(asset["size"]) is int and 0 < asset["size"] <= LIMIT, "Invalid asset size")
    require({"appcast.xml", "SHA256SUMS.txt", "Install-ReadMe.txt"} <= names, "Missing release metadata")
    require(any(n.endswith(".dmg") for n in names) and any(n.endswith("-arm64.zip") for n in names)
            and any(n.endswith("-source.tar.gz") for n in names), "Missing release archive")


def publish(plan):
    validate_manifest(plan)
    require(os.environ.get("GITHUB_REPOSITORY") == REPO
            and os.environ.get("GITHUB_REF") == "refs/heads/main", "Publish from the main repository only")
    commit = os.environ["GITHUB_SHA"]
    require(re.fullmatch(r"[a-f0-9]{40}", commit) is not None, "Invalid source commit")
    head = request(API + "/git/ref/heads/main")["object"]["sha"]
    require(head == commit, "Main has changed; review and rerun the release from its new head")

    # Verify every locally signed byte before creating a draft or exposing a feed.
    artifacts = {}
    for asset in plan["assets"]:
        blob = request(API + "/git/blobs/" + asset["blob"])
        require(blob["encoding"] == "base64" and blob["size"] == asset["size"], "Blob metadata mismatch")
        data = base64.b64decode(blob["content"].replace("\n", ""), validate=True)
        require(len(data) == asset["size"] and hashlib.sha256(data).hexdigest() == asset["sha256"],
                "Release artifact checksum mismatch")
        artifacts[asset["name"]] = data

    try:
        release = request(API + "/releases/tags/" + quote(plan["tag"]))
    except HTTPError as error:
        if error.code != 404:
            raise
        # The tag endpoint omits drafts. Find an interrupted attempt first.
        matches = [r for r in request(API + "/releases?per_page=100") if r["tag_name"] == plan["tag"]]
        require(len(matches) <= 1, "Multiple releases have this tag")
        release = matches[0] if matches else request(API + "/releases", "POST", {
            "tag_name": plan["tag"], "target_commitish": commit, "name": plan["title"],
            "body": plan["notes"], "draft": True, "prerelease": True})

    existing = {a["name"]: a for a in request(API + f"/releases/{release['id']}/assets?per_page=100")}
    for asset in plan["assets"]:
        old = existing.get(asset["name"])
        if old:
            require(old["size"] == asset["size"] and old.get("digest") == "sha256:" + asset["sha256"],
                    "Existing release asset differs; refusing to overwrite it")
            continue
        require(release["draft"], "Cannot add files to an already published release")
        uploaded = request(f"https://uploads.github.com/repos/{REPO}/releases/{release['id']}/assets?name="
                           + quote(asset["name"]), "POST", artifacts[asset["name"]], binary=True)
        require(uploaded["state"] == "uploaded" and uploaded["size"] == asset["size"]
                and uploaded.get("digest") == "sha256:" + asset["sha256"], "Uploaded artifact checksum mismatch")

    if release["draft"]:
        release = request(API + f"/releases/{release['id']}", "PATCH", {"draft": False, "prerelease": True,
                                                                      "make_latest": "false"})
    current = request(API + "/contents/appcast.xml?ref=main")
    feed = artifacts["appcast.xml"]
    previous = base64.b64decode(current["content"])
    if previous != feed:
        require(request(API + "/git/ref/heads/main")["object"]["sha"] == commit,
                "Main changed; release published but feed update requires a fresh run")
        request(API + "/contents/appcast.xml", "PUT", {
            "message": f"Publish signed update feed for {plan['tag']}", "branch": "main",
            "sha": current["sha"], "content": base64.b64encode(feed).decode()})
    print(f"Published {release['html_url']} and its signed update feed")


if __name__ == "__main__":
    try:
        require(len(sys.argv) == 2, "Pass the release manifest path")
        publish(json.loads(Path(sys.argv[1]).read_text()))
    except Exception as error:
        # Do not print API request headers, credentials, or response bodies.
        print(f"Release stopped: {type(error).__name__}: {error}", file=sys.stderr)
        sys.exit(1)
