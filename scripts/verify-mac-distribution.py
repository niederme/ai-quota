#!/usr/bin/env python3
"""Check the built app, not just project settings, before choosing a distribution route."""
import argparse
from pathlib import Path
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("channel", choices=["direct", "testflight"])
parser.add_argument("app", type=Path)
args = parser.parse_args()
app = args.app.resolve()

def require(condition, message):
    if not condition:
        raise SystemExit(message)

def plist(path):
    return plistlib.loads(path.read_bytes())

def entitlements(bundle):
    result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)],
                            capture_output=True, check=True)
    return plistlib.loads(result.stdout) if result.stdout else {}

info = plist(app / "Contents/Info.plist")
widget = app / "Contents/PlugIns/AIQuotaWidget.appex"
require(widget.exists(), "Missing widget extension")
widget_info = plist(widget / "Contents/Info.plist")
require(info["CFBundleVersion"] == widget_info["CFBundleVersion"], "App/widget build numbers differ")
require(info["CFBundleShortVersionString"] == widget_info["CFBundleShortVersionString"], "App/widget versions differ")
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
linked = subprocess.check_output(["otool", "-L", str(app / "Contents/MacOS" / info["CFBundleExecutable"])], text=True)
sparkle = list(app.rglob("Sparkle.framework"))
if args.channel == "testflight":
    require(not sparkle and "Sparkle" not in linked, "TestFlight build includes Sparkle")
    require(not any(key.startswith("SU") for key in info), "TestFlight plist contains Sparkle settings")
    for bundle, metadata in [(app, info), (widget, widget_info)]:
        require(metadata.get("AIQuotaAppStoreBuild") is True, f"Missing store runtime policy: {bundle.name}")
        e = entitlements(bundle)
        require(e.get("com.apple.security.app-sandbox") is True, f"Sandbox disabled: {bundle.name}")
        require(e.get("com.apple.security.network.client") is True, f"Network access disabled: {bundle.name}")
        require("group.com.niederme.AIQuota" in e.get("com.apple.security.application-groups", []), f"Missing widget app group: {bundle.name}")
        require(any(value.endswith("com.niederme.AIQuota") for value in e.get("keychain-access-groups", [])), f"Missing shared Keychain: {bundle.name}")
else:
    require(bool(sparkle) and "Sparkle" in linked, "Direct build lost Sparkle")
    require(bool(info.get("SUFeedURL")), "Direct build lost its update feed")
    require(not info.get("AIQuotaAppStoreBuild", False), "Direct build uses store runtime policy")
    require(not entitlements(app).get("com.apple.security.app-sandbox", False), "Direct build unexpectedly sandboxed")
print(f"Verified {args.channel}: {app.name} {info['CFBundleShortVersionString']} ({info['CFBundleVersion']})")
