"""Exercise packaging failure boundaries without requiring macOS disk images."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]

class DMGPackagingTests(unittest.TestCase):
    def run_failure(self, phase):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "scripts").mkdir()
            (root / "build/Arkiv.app").mkdir(parents=True)
            shutil.copy2(REPO / "scripts/build-dmg.sh", root / "scripts/build-dmg.sh")
            verify = root / "scripts/verify-app.sh"
            verify.write_text("#!/bin/sh\nexit 0\n"); verify.chmod(0o755)
            bin = root / "bin"; bin.mkdir()
            stub = bin / "stub"
            stub.write_text("""#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
tool=pathlib.Path(sys.argv[0]).name; args=sys.argv[1:]
if tool=="uname":
    print("Darwin"); sys.exit(0)
if tool=="ditto":
    shutil.copytree(args[0],args[1]); sys.exit(0)
with open(os.environ["DMG_TRACE"],"a") as f: f.write(json.dumps(args)+"\\n")
if args[0]==os.environ["DMG_FAIL"]:
    print("hdiutil: "+args[0]+" failed - corrupt image",file=sys.stderr); sys.exit(5)
if args[0]=="create":
    pathlib.Path(args[-1]).write_bytes(b"private uncompressed image")
elif args[0]=="convert":
    pathlib.Path(args[args.index("-o")+1]).write_bytes(b"compressed image")
else:
    sys.exit("Unexpected packaging command")
""")
            stub.chmod(0o755)
            for name in ["uname","ditto","hdiutil"]:
                (bin / name).symlink_to(stub)
            trace = root / "trace"
            env = dict(os.environ, PATH=str(bin)+os.pathsep+os.environ["PATH"],
                       ARKIV_ARCH="universal", DMG_TRACE=str(trace), DMG_FAIL=phase)
            result = subprocess.run(["bash",str(root / "scripts/build-dmg.sh")],
                                    env=env,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            calls = [json.loads(line) for line in trace.read_text().splitlines()]
            self.assertEqual(calls[0][calls[0].index("-format")+1],"UDRW")
            if phase != "create":
                self.assertEqual(calls[1][0],"convert")
                self.assertEqual(calls[1][calls[1].index("-format")+1],"UDZO")
                self.assertEqual(calls[1][1],calls[0][-1])
            if phase == "verify":
                self.assertEqual(calls[2][0],"verify")
                self.assertEqual(calls[2][1],calls[1][calls[1].index("-o")+1])
            self.assertEqual([c[0] for c in calls],
                             {"create":["create"],"convert":["create","convert"],
                              "verify":["create","convert","verify"]}[phase])
            self.assertEqual(list((root/"build").glob("dmg-work.*")),[])
            self.assertFalse((root/"build/Arkiv-universal-development.dmg").exists())

    def test_create_failure_never_compresses_or_publishes(self):
        self.run_failure("create")
    def test_conversion_failure_never_verifies_or_publishes(self):
        self.run_failure("convert")
    def test_corrupt_image_never_mounts_or_publishes(self):
        self.run_failure("verify")

if __name__ == "__main__":
    unittest.main()
