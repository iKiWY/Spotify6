#!/usr/bin/env python3
"""Run the production MMAudioStream buffer against ordinary and mapped allocations."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source_path = Path(os.environ.get("MMAUDIO_SOURCE_OVERRIDE", root / "music/Spot/MMAudio.m"))
source = source_path.read_text()
start = source.index("@implementation MMAudioStream")
end = source.index("@end", start) + len("@end")
implementation = source[start:end]
harness = r'''
#import <Foundation/Foundation.h>
#import <sys/mman.h>
#import <unistd.h>
#import "MMAudio.h"
IMPLEMENTATION
static void check(NSString *name, BOOL condition) { NSCAssert(condition,@"%@",name); printf("PASS %s\n",[name UTF8String]); }
int main(void) { NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    MMAudioStream *memory=[[MMAudioStream alloc] initWithLength:4096];
    check(@"legacy music stream gets contiguous buffer", memory.bytes!=NULL && memory.length==4096);
    check(@"music stream keeps the existing NSData cache path", [memory completedData]!=nil);
    ((unsigned char *)memory.bytes)[123]=0x5a;
    check(@"memory stream remains writable", ((unsigned char *)memory.bytes)[123]==0x5a);
    MMAudioStream *mapped=[[MMAudioStream alloc] initWithLength:256*1024*1024 diskBacked:YES];
    check(@"large podcast stream uses mapped backing", mapped.bytes!=NULL && mapped.length==256*1024*1024);
    check(@"mapped podcast stream avoids a full NSData allocation", [mapped completedData]==nil);
    ((unsigned char *)mapped.bytes)[mapped.length-1]=0x6b;
    check(@"mapped stream supports writes at far offsets", ((unsigned char *)mapped.bytes)[mapped.length-1]==0x6b);
    mapped.avail=mapped.length; mapped.complete=YES;
    check(@"stream progress flags remain available", mapped.avail==mapped.length && mapped.complete);
    [pool drain]; return 0;
}
'''.replace("IMPLEMENTATION", implementation)

with tempfile.TemporaryDirectory(prefix="spotify6-podcast-buffer-") as directory:
    path = Path(directory)
    (path / "test.m").write_text(harness)
    flags = shlex.split(subprocess.check_output(["gnustep-config", "--objc-flags"], text=True))
    libs = shlex.split(subprocess.check_output(["gnustep-config", "--base-libs"], text=True))
    objc_include = subprocess.check_output(["gcc", "-print-file-name=include"], text=True).strip()
    subprocess.run(["clang", *flags, "-I", str(root / "music/Spot"), "-I", objc_include,
                    str(path / "test.m"), "-o", str(path / "test"), *libs], check=True)
    subprocess.run([str(path / "test")], check=True)
