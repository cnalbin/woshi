"""Verify archive layout and the real ARM64 Mach-O binary; never package placeholders."""
import plistlib
import argparse
from pathlib import PurePosixPath
import struct
import zipfile


def verify(filename, version=None, build=None, display_name=None, revision=None):
    with zipfile.ZipFile(filename) as archive:
        names = archive.namelist()
        roots = {PurePosixPath(n).parts[1] for n in names if n.startswith("Payload/") and len(PurePosixPath(n).parts) > 1}
        assert roots == {"QingJi.app"}, f"Unexpected app roots: {roots}"
        prefix = "Payload/QingJi.app/"
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        for key, expected in [("CFBundleShortVersionString", version), ("CFBundleVersion", build),
                              ("CFBundleDisplayName", display_name), ("QingJiSourceRevision", revision)]:
            if expected is not None:
                assert info.get(key) == expected, f"{key}: expected {expected!r}, got {info.get(key)!r}"
        executable = archive.read(prefix + info["CFBundleExecutable"])
        # Release device builds are thin ARM64. Reject simulator and non-native placeholders.
        assert executable[:4] == bytes.fromhex("cffaedfe"), "Expected 64-bit Mach-O executable"
        cpu = struct.unpack_from("<I", executable, 4)[0]
        assert cpu == 0x0100000C, f"Expected ARM64, got {cpu:#x}"
        assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
        assert info["MinimumOSVersion"] == "17.0"
        assert prefix + "Assets.car" in names
        alternates = info.get("CFBundleIcons", {}).get("CFBundleAlternateIcons", {})
        assert all(f"Member{index:02}" in alternates for index in range(1, 6)), "Missing alternate icon declarations"
        assert not any(n.endswith((".env", ".p12", ".mobileprovision")) for n in names)
        print(f"Verified unsigned iPhoneOS ARM64 IPA: {info['CFBundleIdentifier']} "
              f"{info['CFBundleShortVersionString']} ({info['CFBundleVersion']}) · {info['CFBundleDisplayName']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("filename")
    parser.add_argument("--version")
    parser.add_argument("--build")
    parser.add_argument("--display-name")
    parser.add_argument("--revision")
    args = parser.parse_args()
    verify(args.filename, args.version, args.build, args.display_name, args.revision)
