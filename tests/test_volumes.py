"""Bounded descriptor discovery, independent split fixtures and hostile volume sets."""
import ctypes as C, hashlib, json, os, shutil, tempfile, unittest
from pathlib import Path
import test_integrity as I
LIB=I.LIB
LIB.arkiv_volumes_reconstruct.argtypes=[C.c_char_p,C.c_char_p,C.c_uint64,C.c_void_p,I.PROGRESS,C.c_void_p,C.POINTER(C.c_void_p),C.c_char_p,C.c_size_t]
LIB.arkiv_volumes_free.argtypes=[C.c_void_p]
LIB.arkiv_volumes_validate.argtypes=[C.c_void_p,C.c_void_p,C.c_char_p,C.c_size_t]
FIX=Path(__file__).parent/'fixtures/split-sevenzip'
class VolumeTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name).resolve();self.out=self.root/'private';self.out.mkdir(mode=0o700);self.token=LIB.arkiv_cancel_new()
  for f in FIX.glob('store.7z.*'):shutil.copyfile(f,self.root/f.name)
 def tearDown(self):LIB.arkiv_cancel_free(self.token);self.temp.cleanup()
 def reconstruct(self,limit=4<<30,callback=None):
  handle=C.c_void_p();error=C.create_string_buffer(1024)
  code=LIB.arkiv_volumes_reconstruct(bytes(self.root/'store.7z.002'),bytes(self.out/'archive.7z'),limit,self.token,I.PROGRESS(callback or (lambda *a:None)),None,C.byref(handle),error,len(error))
  if handle:
   self.assertEqual(LIB.arkiv_volumes_validate(handle,self.token,error,len(error)),0);LIB.arkiv_volumes_free(handle)
  else:self.assertFalse((self.out/'archive.7z').exists())
  return code,error.value
 def test_independent_reconstruction_and_fixture_provenance(self):
  for name,digest in json.loads((FIX/'provenance.json').read_text())['sha256'].items():self.assertEqual(hashlib.sha256((FIX/name).read_bytes()).hexdigest(),digest)
  self.assertEqual(self.reconstruct()[0],0)
  self.assertEqual((self.out/'archive.7z').read_bytes(),(FIX/'store.7z.001').read_bytes()+(FIX/'store.7z.002').read_bytes())
 def test_cancel_and_mutation_leave_no_spool(self):
  self.assertNotEqual(self.reconstruct(callback=lambda *a:(self.root/'store.7z.002').write_bytes(b'changed'))[0],0)
  shutil.copyfile(FIX/'store.7z.002',self.root/'store.7z.002')
  self.assertEqual(self.reconstruct(callback=lambda *a:LIB.arkiv_cancel_set(self.token))[0],2)
 def test_budgets_ambiguous_sequence_and_hardlink_reject(self):
  self.assertEqual(self.reconstruct(limit=100)[0],8)
  shutil.copyfile(FIX/'store.7z.002',self.root/'store.7z.0002');self.assertEqual(self.reconstruct()[0],8);(self.root/'store.7z.0002').unlink()
  os.link(self.root/'store.7z.002',self.root/'other');self.assertNotEqual(self.reconstruct()[0],0)
 def test_parent_symlink_and_replaced_volume_are_rejected(self):
  part=self.root/'store.7z.002';part.unlink();part.symlink_to((FIX/'store.7z.002').resolve());self.assertNotEqual(self.reconstruct()[0],0)
  part.unlink();shutil.copyfile(FIX/'store.7z.002',part)
  def change(*args):
   replacement=self.root/'replacement';replacement.write_bytes(part.read_bytes());replacement.replace(part)
  self.assertNotEqual(self.reconstruct(callback=change)[0],0)
 def test_replaced_output_parent_does_not_delete_foreign_spool(self):
  moved=self.root/'moved';foreign=self.out/'archive.7z'
  def change(*args):
   if moved.exists():return
   self.out.rename(moved);self.out.mkdir();foreign.write_bytes(b'foreign')
   LIB.arkiv_cancel_set(self.token)
  handle=C.c_void_p();error=C.create_string_buffer(1024)
  code=LIB.arkiv_volumes_reconstruct(bytes(self.root/'store.7z.001'),bytes(foreign),4<<30,self.token,I.PROGRESS(change),None,C.byref(handle),error,len(error))
  self.assertNotEqual(code,0);self.assertEqual(foreign.read_bytes(),b'foreign')
  self.assertFalse((moved/'archive.7z').exists())
if __name__=='__main__':unittest.main()
