"""Split publication failures, exact byte preservation and independent interoperability."""
import ctypes as C
import os
from pathlib import Path
import tempfile
import unittest
import subprocess

lib=C.CDLL(os.environ['ARKIV_TEST_LIBRARY'])
class Limits(C.Structure):
    _fields_=[('entries',C.c_uint64),('bytes',C.c_uint64)]
Progress=C.CFUNCTYPE(None,C.c_void_p,C.c_uint64,C.c_uint64)
lib.arkiv_create_archive_split.argtypes=[C.POINTER(C.c_char_p),C.c_size_t,C.c_char_p,C.c_char_p,C.c_char_p,C.c_char_p,C.c_size_t,Limits,C.c_void_p,Progress,C.c_void_p,C.c_char_p,C.c_size_t,C.c_char_p,C.c_int,C.c_int,C.c_uint32,C.c_uint,C.c_int,C.c_uint64,C.c_uint64]
class SplitCreationTests(unittest.TestCase):
    def run_create(self, root, callback=lambda *_:None, password=None, headers=0, solid=0):
        source=root/'file';source.write_bytes(bytes(range(256))*100)
        stage=root/'.stage';stage.mkdir(mode=0o700)
        sources=(C.c_char_p*1)(os.fsencode(source));error=C.create_string_buffer(1024)
        result=lib.arkiv_create_archive_split(sources,1,os.fsencode(root),b'.stage',b'result.7z',C.create_string_buffer(512),512,Limits(100000,20<<30),None,Progress(callback),None,error,len(error),password,headers,5,0,2,solid,0,128)
        return result,error.value
    def test_exact_encoded_bytes_and_independent_reader(self):
        for password,headers,solid in [(None,0,0),(b'fixture password',0,0),(b'fixture password',1,1)]:
            with tempfile.TemporaryDirectory() as t:
                root=Path(t).resolve();encoded=[]
                def progress(*_):
                    p=root/'.stage/archive.7z'
                    # Capture after parts exist: encoding/verification has completed.
                    if not encoded and (root/'.stage/result.7z.001').exists():encoded.append(p.read_bytes())
                result,error=self.run_create(root,progress,password,headers,solid)
                self.assertEqual(result,0,error)
                parts=sorted(root.glob('result.7z.*'));self.assertGreaterEqual(len(parts),3)
                self.assertEqual(b''.join(p.read_bytes() for p in parts),encoded[0])
                self.assertFalse((root/'.stage').exists())
                tool=os.environ.get('ARKIV_INDEPENDENT_7ZZ')
                if tool:
                    command=[tool,'t',str(parts[0])]
                    if password:command+=['-pfixture password'] # Public fixture password only.
                    self.assertEqual(subprocess.run(command,stdout=subprocess.DEVNULL).returncode,0)
    @unittest.skipUnless(hasattr(os,'fork'),'POSIX fault isolation')
    def test_write_exhaustion_rolls_back_and_cleans(self):
        with tempfile.TemporaryDirectory() as t:
            root=Path(t).resolve();pid=os.fork()
            if pid==0:
                import resource,signal
                signal.signal(signal.SIGXFSZ,signal.SIG_IGN)
                def progress(*_):
                    if (root/'.stage/result.7z.001').exists():resource.setrlimit(resource.RLIMIT_FSIZE,(64,64))
                result,_=self.run_create(root,progress)
                os._exit(0 if result!=0 else 1)
            _,status=os.waitpid(pid,0);self.assertEqual(os.waitstatus_to_exitcode(status),0)
            self.assertEqual(sorted(p.name for p in root.iterdir()),['file'])
if __name__=='__main__':unittest.main()
