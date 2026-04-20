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

#include <CoreCompiler/CCLinker.h>
#include <lld/Common/Driver.h>
#include <lld/Common/ErrorHandler.h>
#include <llvm/ADT/ArrayRef.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Support/CrashRecoveryContext.h>
#include <lld/Common/CommonLinkerContext.h>

namespace lld {
namespace macho {

bool link(llvm::ArrayRef<const char *> args, llvm::raw_ostream &stdoutOS,
          llvm::raw_ostream &stderrOS, bool exitEarly, bool disableOutput);

} // namespace macho
} // namespace lld

Boolean CCLinkerJobExecute(CCJobRef job,
                           CFArrayRef *outDiagnostics)
{
    assert(job != nullptr);
    assert(CCJobGetType(job) == CCJobTypeLinker);
    
    CFArrayRef argsArray = CCJobGetArguments(job);
    CFIndex count = CFArrayGetCount(argsArray);

    llvm::SmallVector<std::string, 64> argStorage;
    llvm::SmallVector<const char *, 64> Args;
    argStorage.reserve(count);
    Args.reserve(count);
    
    argStorage.push_back("ld64.lld");   /* have to inject */
    Args.push_back(argStorage.back().c_str());

    for(CFIndex i = 0; i < count; i++)
    {
        CFStringRef s = (CFStringRef)CFArrayGetValueAtIndex(argsArray, i);
        CFIndex len = CFStringGetMaximumSizeForEncoding(CFStringGetLength(s), kCFStringEncodingUTF8) + 1;
        argStorage.push_back(std::string(len, '\0'));
        CFStringGetCString(s, argStorage.back().data(), len, kCFStringEncodingUTF8);
        argStorage.back().resize(strlen(argStorage.back().c_str()));
        Args.push_back(argStorage.back().c_str());
    }
    
    std::vector<LDDiagnostic> diagnostics;
    int retCode;
    
    llvm::CrashRecoveryContext CRC;
    CRC.RunSafely([&]{
        const lld::DriverDef drivers[] = {
            {lld::Darwin, &lld::macho::link},
        };
        
        lld::Result result = lld::lldMain(Args, llvm::nulls(), llvm::nulls(), drivers, [&diagnostics](const LDDiagnostic &diag) {
            diagnostics.push_back(diag);
        });
        retCode = result.retCode;
        
        lld::CommonLinkerContext::destroy();
    });
    
    if(outDiagnostics != nullptr)
    {
        /* process error returns */
        CFAllocatorRef allocator = CFGetAllocator(job);
        CFMutableArrayRef result = CFArrayCreateMutable(allocator, diagnostics.size(), &kCFTypeArrayCallBacks);
        if(result == nullptr)
        {
            return retCode == 0;
        }
        
        for(auto it = diagnostics.begin(); it != diagnostics.end(); ++it)
        {
            CFStringRef message = CFStringCreateWithCString(allocator, it->message.c_str(), kCFStringEncodingUTF8);
            CCDiagnosticRef diagnosticRef = CCDiagnosticCreate(allocator, CCDiagnosticTypeInternal, (it->kind == LDDiagnostic::Kind::Error) ? CCDiagnosticLevelError : CCDiagnosticLevelWarning, nullptr, message);
            CFRelease(message);
            if(diagnosticRef != nullptr)
            {
                CFArrayAppendValue(result, diagnosticRef);
                CFRelease(diagnosticRef);
            }
        }
        
        *outDiagnostics = result;
    }
    
    return retCode == 0;
}
