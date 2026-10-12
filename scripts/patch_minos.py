#!/usr/bin/env python3
"""Raise the arm64e slice's min OS version of a (possibly universal) Mach-O
binary so dyld picks the arm64 slice on devices below the given version.

Usage: patch_minos.py <binary> <version>   e.g. patch_minos.py lara 26.2.0

dyld eliminates main-executable slices whose min OS is newer than the running
OS, then prefers the best remaining slice (arm64e over arm64). Raising the
arm64e slice's min OS to 26.2 therefore yields:
  - iOS < 26.2  -> arm64 process  (loads arm64 business dylibs)
  - iOS >= 26.2 -> arm64e process (normal pipeline)
"""
import struct
import sys

CPU_TYPE_ARM64 = 0x0100000C
CPU_SUBTYPE_ARM64E = 0x2
LC_BUILD_VERSION = 0x32
LC_VERSION_MIN_IPHONEOS = 0x25


def parse_version(s):
    parts = [int(x) for x in s.split(".")]
    while len(parts) < 3:
        parts.append(0)
    major, minor, patch = parts[:3]
    return (major << 16) | (minor << 8) | patch


def patch_slice(data, offset, new_minos):
    """data: whole file bytes, offset: start of the Mach-O slice. Returns
    (patched_data, was_patched)."""
    if data[offset:offset + 4] != b"\xcf\xfa\xed\xfe":
        return data, False
    ncmds = struct.unpack_from("<I", data, offset + 16)[0]
    cmd = offset + 32
    for _ in range(ncmds):
        lc, cmdsize = struct.unpack_from("<II", data, cmd)
        if lc == LC_BUILD_VERSION:
            # cmd, cmdsize, platform, minos, sdk, ntools...
            struct.pack_into("<I", data, cmd + 12, new_minos)
            return data, True
        if lc == LC_VERSION_MIN_IPHONEOS:
            # cmd, cmdsize, version, sdk
            struct.pack_into("<I", data, cmd + 8, new_minos)
            return data, True
        cmd += cmdsize
    return data, False


def main():
    if len(sys.argv) < 3:
        print("usage: patch_minos.py <binary> <version>")
        sys.exit(2)
    path = sys.argv[1]
    new_minos = parse_version(sys.argv[2])
    with open(path, "r+b") as f:
        data = bytearray(f.read())
        magic = data[:4]
        if magic == b"\xca\xfe\xba\xbe":
            # fat binary: big-endian fat_arch entries
            nfat = struct.unpack_from(">I", data, 4)[0]
            patched = False
            for i in range(nfat):
                e = 8 + i * 20
                cputype, cpusubtype, off = struct.unpack_from(">III", data, e)
                if cputype == CPU_TYPE_ARM64 and cpusubtype == CPU_SUBTYPE_ARM64E:
                    data, ok = patch_slice(data, off, new_minos)
                    patched = patched or ok
                    print(f"arm64e slice @0x{off:x}: minos -> {sys.argv[2]} "
                          f"(patched={ok})")
            if not patched:
                print("no arm64e slice found — nothing patched")
            f.seek(0)
            f.write(data)
        elif magic == b"\xcf\xfa\xed\xfe":
            # thin binary: patch only if it is the arm64e slice
            cputype, cpusubtype = struct.unpack_from("<II", data, 4)
            if cputype == CPU_TYPE_ARM64 and cpusubtype == CPU_SUBTYPE_ARM64E:
                data, ok = patch_slice(data, 0, new_minos)
                print(f"thin arm64e binary: minos -> {sys.argv[2]} "
                      f"(patched={ok})")
                f.seek(0)
                f.write(data)
            else:
                print("thin non-arm64e binary — nothing patched")
        else:
            print(f"unknown magic {magic.hex()} — nothing patched")


if __name__ == "__main__":
    main()
