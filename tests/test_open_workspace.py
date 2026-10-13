"""Owned Open workspace cleanup under the ordinary macOS descriptor budget."""
import ctypes as C
import os
from pathlib import Path
import resource
import tempfile
import unittest
import uuid

LIB = C.CDLL(os.environ['ARKIV_TEST_LIBRARY'])
LIB.arkiv_open_workspace_new.argtypes = [C.c_char_p, C.c_char_p]
LIB.arkiv_open_workspace_new.restype = C.c_void_p
LIB.arkiv_open_workspace_path.argtypes = [C.c_void_p]
LIB.arkiv_open_workspace_path.restype = C.c_char_p
LIB.arkiv_open_workspace_free.argtypes = [C.c_void_p]
LIB.arkiv_open_sweep.argtypes = [C.c_char_p]

class OpenWorkspaceTests(unittest.TestCase):
    def test_cleanup_and_stale_sweep_at_supported_depth_with_256_descriptors(self):
        # Isolate the descriptor limit from the parent test harness.
        with tempfile.TemporaryDirectory() as directory:
            parent = Path(directory).resolve()
            pid = os.fork()
            if pid == 0:
                try:
                    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
                    resource.setrlimit(resource.RLIMIT_NOFILE, (min(256, soft), hard))
                    w = LIB.arkiv_open_workspace_new(os.fsencode(parent), ('session-' + str(uuid.uuid4())).encode())
                    if not w: os._exit(2)
                    session = Path(os.fsdecode(LIB.arkiv_open_workspace_path(w)))
                    def populate(base):
                        deep = base / ('file-' + str(uuid.uuid4())) / 'extracted'
                        deep = deep.joinpath(*(['d'] * 63))
                        deep.mkdir(parents=True)
                        (deep / 'private.txt').write_bytes(b'private')
                    populate(session)
                    LIB.arkiv_open_workspace_free(w)
                    if session.exists(): os._exit(3)
                    stale = session.parent / ('session-' + str(uuid.uuid4()))
                    stale.mkdir(mode=0o700)
                    populate(stale)
                    LIB.arkiv_open_sweep(os.fsencode(parent))
                    os._exit(4 if stale.exists() else 0)
                except BaseException:
                    os._exit(5)
            _, status = os.waitpid(pid, 0)
            self.assertTrue(os.WIFEXITED(status))
            self.assertEqual(os.WEXITSTATUS(status), 0)

if __name__ == '__main__': unittest.main()
