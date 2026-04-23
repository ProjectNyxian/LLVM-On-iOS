/*
 * MIT License
 *
 * Copyright (c) 2024 light-tech
 * Copyright (c) 2026 cr4zyengineer
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <CoreCompiler/CCDriver.h>
#include <CoreCompiler/CCUtils.h>
#include <clang/Basic/Diagnostic.h>
#include <clang/Basic/DiagnosticOptions.h>
#include <clang/Basic/SourceManager.h>
#include <clang/CodeGen/CodeGenAction.h>
#include <clang/Driver/Compilation.h>
#include <clang/Driver/Driver.h>
#include <clang/Driver/Tool.h>
#include <clang/Frontend/CompilerInstance.h>
#include <clang/Frontend/CompilerInvocation.h>
#include <clang/Frontend/FrontendDiagnostic.h>
#include <clang/Frontend/TextDiagnosticPrinter.h>
#include <llvm/Support/FileSystem.h>
#include <llvm/Support/ManagedStatic.h>
#include <llvm/Support/Path.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Target/TargetMachine.h>
#include <llvm/Support/TargetSelect.h>

using namespace clang;
using namespace clang::driver;
using namespace llvm::opt;

static CFTypeID gCCDriverTypeID = _kCFRuntimeNotATypeID;

struct opaque_ccdriver {
    CFRuntimeBase _base;
    IntrusiveRefCntPtr<DiagnosticsEngine> diags;
    std::unique_ptr<Driver> driver;
    std::unique_ptr<Compilation> compilation;
    llvm::SmallVector<std::string, 64> argStorage;
    void *outputPathCallbackContext;
    CCOutputPathCallback callback;
};

static CFTypeRef CCDriverCopy(CFAllocatorRef allocator,
                              CFTypeRef cf)
{
    return CFRetain(cf);
}

static void CCDriverFinalize(CFTypeRef cf)
{
    CCDriverRef driverRef = (CCDriverRef)cf;
    driverRef->compilation.reset();
    driverRef->driver.reset();
    driverRef->compilation.~unique_ptr<Compilation>();
    driverRef->driver.~unique_ptr<Driver>();
    driverRef->diags.~IntrusiveRefCntPtr<DiagnosticsEngine>();
    driverRef->argStorage.~SmallVector<std::string, 64>();
}

static const CFRuntimeClass gCCDriverClass = {
    0,                              /* version */
    "CCKDriver",                    /* class name (later for OBJC type) */
    NULL,                           /* init */
    CCDriverCopy,                   /* copy */
    CCDriverFinalize,               /* finalize */
    NULL,                           /* equal */
    NULL,                           /* hash */
    NULL,                           /* copyFormattingDesc */
    NULL,                           /* copyDebugDesc */
    NULL,
    NULL,
    0
};

CFTypeID CCDriverGetTypeID(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gCCDriverTypeID = _CFRuntimeRegisterClass(&gCCDriverClass);
    });
    return gCCDriverTypeID;
}

CCDriverRef CCDriverCreate(CFAllocatorRef allocator,
                           CFArrayRef arguments)
{
    assert(arguments != nullptr);

    CCDriverRef driverRef = (CCDriverRef)_CFRuntimeCreateInstance(allocator, CCDriverGetTypeID(), sizeof(struct opaque_ccdriver) - sizeof(CFRuntimeBase), NULL);
    if(driverRef == nullptr)
    {
        return nullptr;
    }

    driverRef->argStorage = CCArrayToStringVector(arguments);
    driverRef->argStorage.insert(driverRef->argStorage.begin(), "-fuse-ld=lld");
    driverRef->argStorage.insert(driverRef->argStorage.begin(), "clang");
    driverRef->outputPathCallbackContext = nullptr;

    /* setting up clang driver */
    IntrusiveRefCntPtr<DiagnosticIDs> DiagID(new DiagnosticIDs());
    DiagnosticOptions DiagOpts;
    IntrusiveRefCntPtr<DiagnosticsEngine> Diags(new DiagnosticsEngine(DiagID, DiagOpts, new clang::IgnoringDiagConsumer(), /*ShouldOwnClient=*/true));

    /* building compilation */
    new (&driverRef->diags) IntrusiveRefCntPtr<DiagnosticsEngine>();
    new (&driverRef->driver) std::unique_ptr<Driver>();
    new (&driverRef->compilation) std::unique_ptr<Compilation>();

    driverRef->callback = nullptr;
    driverRef->diags = Diags;

    try
    {
        driverRef->driver = std::make_unique<Driver>("clang", "", *Diags);
    }
    catch (...)
    {
        CFRelease(driverRef);
        return nullptr;
    }

    return driverRef;
}

static CCJobType _CCJobTypeGetFromCommand(const clang::driver::Command *Cmd)
{
    const clang::driver::Action &source = Cmd->getSource();

    if(clang::isa<clang::driver::CompileJobAction>(source) ||
       clang::isa<clang::driver::AssembleJobAction>(source))
    {
        return CCJobTypeCompiler;
    }
    else if(clang::isa<clang::driver::LinkJobAction>(source))
    {
        return CCJobTypeLinker;
    }
    else
    {
        return CCJobTypeUnknown;
    }
}

CFArrayRef CCDriverCreateJobs(CCDriverRef driver)
{
    llvm::SmallVector<const char *, 64> Args = StringVectorToCStrings(driver->argStorage);

    driver->compilation.reset(driver->driver->BuildCompilation(Args));
    if(driver->compilation == nullptr)
    {
        return nullptr;
    }

    llvm::StringMap<const char *> pathRemap;
    llvm::SmallPtrSet<const Command *, 8> skippedJobs;

    /* generating jobs and invoking delegation */
    if(driver->callback != nullptr)
    {
        for(auto &Job : driver->compilation->getJobs())
        {
            if(!isa<Command>(Job))
            {
                continue;
            }

            Command &Cmd = const_cast<Command &>(cast<Command>(Job));
            const Action &Src = Cmd.getSource();

            bool isCompile = isa<CompileJobAction>(Src) || isa<AssembleJobAction>(Src);
            if(!isCompile)
            {
                continue;
            }

            const Action *leaf = &Src;
            while(!leaf->getInputs().empty())
            {
                leaf = leaf->getInputs()[0];
            }

            const char *baseInput = nullptr;
            if(auto *IA = dyn_cast<InputAction>(leaf))
            {
                baseInput = IA->getInputArg().getValue();
            }

            bool skip = false;
            CFStringRef newCF = driver->callback(baseInput, &skip, driver->outputPathCallbackContext);
            if(newCF == nullptr)
            {
                continue;
            }

            std::string s;
            const char *fast = CFStringGetCStringPtr(newCF, kCFStringEncodingUTF8);
            if(fast)
            {
                s.assign(fast);
            }
            else
            {
                CFIndex len = CFStringGetLength(newCF);
                CFIndex max = CFStringGetMaximumSizeForEncoding(len, kCFStringEncodingUTF8) + 1;
                s.resize(max);
                CFIndex used = 0;
                CFStringGetBytes(newCF, CFRangeMake(0, len), kCFStringEncodingUTF8, 0, false, (UInt8 *)s.data(), max, &used);
                s.resize(used);
            }
            CFRelease(newCF);

            const char *newArg = driver->compilation->getArgs().MakeArgString(s);

            ArgStringList newArgs;
            const auto &old = Cmd.getArguments();
            for(size_t i = 0; i < old.size(); ++i)
            {
                if(StringRef(old[i]) == "-o" && i + 1 < old.size())
                {
                    pathRemap[old[i + 1]] = newArg;
                    newArgs.push_back(old[i]);
                    newArgs.push_back(newArg);
                    ++i;
                }
                else
                {
                    newArgs.push_back(old[i]);
                }
            }
            Cmd.replaceArguments(newArgs);

            if(skip)
            {
                skippedJobs.insert(&Cmd);
            }
        }
    }

    /* rewrite linker inputs using pathRemap */
    if(!pathRemap.empty())
    {
        for(auto &Job : driver->compilation->getJobs())
        {
            if(!isa<Command>(Job))
            {
                continue;
            }

            Command &Cmd = const_cast<Command &>(cast<Command>(Job));
            if(!isa<LinkJobAction>(Cmd.getSource()))
            {
                continue;
            }

            ArgStringList newArgs;
            for(const char *a : Cmd.getArguments())
            {
                auto it = pathRemap.find(a);
                newArgs.push_back(it != pathRemap.end() ? it->second : a);
            }
            Cmd.replaceArguments(newArgs);
        }
    }

    /* emit CCJobs... filtering skipped commands */
    CFAllocatorRef allocator = CFGetAllocator(driver);
    CFMutableArrayRef jobsArray = CFArrayCreateMutable(allocator, 0, &kCFTypeArrayCallBacks);

    for(auto &Job : driver->compilation->getJobs())
    {
        if(!isa<Command>(Job))
        {
            continue;
        }

        const Command &Cmd = cast<Command>(Job);
        if(skippedJobs.contains(&Cmd))
        {
            continue;
        }

        CCJobType type = _CCJobTypeGetFromCommand(&Cmd);

        const llvm::opt::ArgStringList &cmdArgs = Cmd.getArguments();
        CFMutableArrayRef argsArray = CFArrayCreateMutable(allocator, cmdArgs.size(), &kCFTypeArrayCallBacks);
        for(const char *arg : cmdArgs)
        {
            if(!arg)
            {
                continue;
            }
            CFStringRef s = CFStringCreateWithCString(allocator, arg, kCFStringEncodingUTF8);
            if(s)
            {
                CFArrayAppendValue(argsArray, s);
                CFRelease(s);
            }
        }

        CCJobRef jobRef = CCJobCreate(allocator, type, argsArray);
        CFRelease(argsArray);

        if(jobRef)
        {
            CFArrayAppendValue(jobsArray, jobRef);
            CFRelease(jobRef);
        }
    }

    return jobsArray;
}

void CCDriverSetOutputPathCallback(CCDriverRef driver,
                                   CCOutputPathCallback callback,
                                   void *context)
{
    driver->callback = callback;
    driver->outputPathCallbackContext = context;
}

void *CCDriverGetOutputPathCallbackContext(CCDriverRef driver)
{
    return driver->outputPathCallbackContext;
}

CFURLRef CCDriverCopySysrootURL(CCDriverRef driver)
{
    std::string cxxstr = driver->compilation->getSysRoot().str();
    if(cxxstr.empty())
    {
        return nullptr;
    }

    const char *sysroot = cxxstr.c_str();

    CFAllocatorRef allocator = CFGetAllocator(driver);
    CFStringRef str = CFStringCreateWithCString(allocator, sysroot, kCFStringEncodingUTF8);
    if(str == nullptr)
    {
        return nullptr;
    }

    CFURLRef url = CFURLCreateWithFileSystemPath(allocator, str, kCFURLPOSIXPathStyle, true);
    CFRelease(str);
    return url;
}

CCSDKRef CCDriverCopySDK(CCDriverRef driver)
{
    CFURLRef sdkRoot = CCDriverCopySysrootURL(driver);
    if(sdkRoot == nullptr)
    {
        return nullptr;
    }

    CCSDKRef sdk = CCSDKCreateWithFileURL(CFGetAllocator(driver), sdkRoot);
    CFRelease(sdkRoot);
    return sdk;
}
