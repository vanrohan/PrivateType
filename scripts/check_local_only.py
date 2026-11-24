"""Check local-only source and privacy declarations before release."""

from pathlib import Path
import plistlib
import re
import sys

FORBIDDEN = re.compile(r"\b(?:URLSession|NSURLConnection|NWConnection|WKWebView|Firebase|Sentry|Mixpanel|Amplitude)\b|import\s+(?:Network|WebKit)\b")


def violations(root):
    issues = []
    for folder in ["App", "Keyboard", "Core", "Neural"]:
        for path in (root / folder).rglob("*.swift"):
            if FORBIDDEN.search(path.read_text()):
                issues.append(str(path.relative_to(root)) + ": review the network or analytics API")
    with (root / "Keyboard/Info.plist").open("rb") as stream:
        extension = plistlib.load(stream)["NSExtension"]["NSExtensionAttributes"]
    if extension.get("RequestsOpenAccess") is not False:
        issues.append("Keyboard/Info.plist: Full Access must stay disabled")
    with (root / "App/PrivacyInfo.xcprivacy").open("rb") as stream:
        privacy = plistlib.load(stream)
    if privacy.get("NSPrivacyTracking") is not False or privacy.get("NSPrivacyCollectedDataTypes") != []:
        issues.append("App/PrivacyInfo.xcprivacy: review the privacy declarations")
    return issues


def main():
    issues = violations(Path(__file__).resolve().parents[1])
    print("\n".join(issues) if issues else "Local-only source and privacy checks pass.")
    return bool(issues)


if __name__ == "__main__":
    sys.exit(main())
