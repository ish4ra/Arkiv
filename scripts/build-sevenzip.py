#!/usr/bin/env python3
"""Build the pinned, RAR-free 7z engine as a replaceable dynamic library."""
import argparse, concurrent.futures, os, pathlib, platform, subprocess
p=argparse.ArgumentParser();p.add_argument('--output',default='.build/sevenzip');p.add_argument('--arch',choices=['arm64','x86_64']);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent.parent;vendor=root/'Vendor/7zip';out=pathlib.Path(a.output).resolve();out.mkdir(parents=True,exist_ok=True)
mac=platform.system()=='Darwin';flags=['-O2','-fPIC','-DNDEBUG','-D_REENTRANT','-D_FILE_OFFSET_BITS=64','-D_LARGEFILE_SOURCE','-fvisibility=hidden']
if mac:flags+=['-mmacosx-version-min=13.0']+(['-arch',a.arch] if a.arch else [])
include=['-I'+str(vendor),'-I'+str(root/'Sources/CArkiv/vendor'),'-I'+str(root/'Sources/CArkivSeven/include')]
sources=[vendor/x for x in (vendor/'sources.txt').read_text().splitlines()]+[root/'Sources/CArkivSeven/ArkivSeven.cpp']
def build(src):
 obj=out/(src.stem+'.o');cc=os.environ.get('CC','cc') if src.suffix=='.c' else os.environ.get('CXX','c++')
 cmd=[cc,*flags,*include]+([] if src.suffix=='.c' else ['-std=c++11'])+['-c',str(src),'-o',str(obj)]
 subprocess.run(cmd,check=True)
 return str(obj)
with concurrent.futures.ThreadPoolExecutor(max_workers=min(8,os.cpu_count() or 2)) as pool:objects=list(pool.map(build,sources))
lib=out/('libArkivSeven.dylib' if mac else 'libArkivSeven.so')
link=['-dynamiclib','-Wl,-install_name,@rpath/libArkivSeven.dylib'] if mac else ['-shared','-Wl,-z,defs']
subprocess.run([os.environ.get('CXX','c++'),*flags,*link,*objects,'-larchive','-lpthread',*([] if mac else ['-ldl']),'-o',str(lib)],check=True)
print(lib)
