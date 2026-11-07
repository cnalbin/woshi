"""Verify archive layout and the real ARM64 Mach-O binary; never package placeholders."""
import plistlib
from pathlib import PurePosixPath
import struct
import sys
import zipfile


def verify(filename):
    with zipfile.ZipFile(filename) as archive:
        names = archive.namelist()
        roots = {PurePosixPath(n).parts[1] for n in names if n.startswith("Payload/") and len(PurePosixPath(n).parts) > 1}
        assert roots == {"QingJi.app"}, f"Unexpected app roots: {roots}"
        prefix = "Payload/QingJi.app/"
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        executable = archive.read(prefix + info["CFBundleExecutable"])
        # Release device builds are thin ARM64. Reject simulator and non-native placeholders.
        assert executable[:4] == bytes.fromhex("cffaedfe"), "Expected 64-bit Mach-O executable"
        cpu = struct.unpack_from("<I", executable, 4)[0]
        assert cpu == 0x0100000C, f"Expected ARM64, got {cpu:#x}"
        assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"]
        assert info["MinimumOSVersion"] == "17.0"
        assert prefix + "Assets.car" in names
        assert not any(n.endswith((".env", ".p12", ".mobileprovision")) for n in names)
        print(f"Verified unsigned iPhoneOS ARM64 IPA: {info['CFBundleIdentifier']} {info['CFBundleShortVersionString']}")


if __name__ == "__main__":
    verify(sys.argv[1])
