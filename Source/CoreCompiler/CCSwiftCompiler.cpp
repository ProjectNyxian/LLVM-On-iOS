/*
 * MIT License
 *
 * Copyright (c) 2026 Kyle-Ye
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

#include <CoreCompiler/CCSwiftCompiler.h>
#include <CoreCompiler/CCUtils.h>
#include <swift/Basic/InitializeSwiftModules.h>
#include <swift/FrontendTool/FrontendTool.h>
#include <llvm/Support/ErrorHandling.h>
#include <fcntl.h>
#include <mutex>
#include <unistd.h>

static std::once_flag SwiftModulesInitOnce;
static std::mutex SwiftFrontendMutex;

static CFStringRef CCStringCreateWithFileDescriptor(CFAllocatorRef allocator, int fd)
{
    if(fd < 0)
    {
        return CFSTR("");
    }

    lseek(fd, 0, SEEK_SET);

    CFMutableDataRef data = CFDataCreateMutable(allocator, 0);
    if(data == nullptr)
    {
        return CFSTR("");
    }

    char buffer[4096];
    ssize_t count = 0;
    while((count = read(fd, buffer, sizeof(buffer))) > 0)
    {
        CFDataAppendBytes(data, reinterpret_cast<const UInt8 *>(buffer), count);
    }

    CFStringRef string = CFStringCreateFromExternalRepresentation(allocator, data, kCFStringEncodingUTF8);
    CFRelease(data);

    if(string == nullptr)
    {
        return CFSTR("");
    }

    return string;
}

Boolean CCSwiftCompilerExecute(CFArrayRef arguments, CFStringRef *outOutput)
{
    assert(arguments != nullptr);
    std::lock_guard<std::mutex> lock(SwiftFrontendMutex);

    CFIndex count = CFArrayGetCount(arguments);
    llvm::SmallVector<std::string, 64> argStorage;
    llvm::SmallVector<const char *, 64> args;
    argStorage.reserve(count);
    args.reserve(count);

    for(CFIndex i = 0; i < count; i++)
    {
        CFStringRef s = (CFStringRef)CFArrayGetValueAtIndex(arguments, i);
        CFIndex len = CFStringGetMaximumSizeForEncoding(CFStringGetLength(s), kCFStringEncodingUTF8) + 1;
        argStorage.push_back(std::string(len, '\0'));
        CFStringGetCString(s, argStorage.back().data(), len, kCFStringEncodingUTF8);
        argStorage.back().resize(strlen(argStorage.back().c_str()));
        args.push_back(argStorage.back().c_str());
    }

    std::call_once(SwiftModulesInitOnce, [] {
        initializeSwiftModules();
    });

    char templatePath[] = "/tmp/nyxian-swift-frontend.XXXXXX";
    int diagnosticsFD = mkstemp(templatePath);
    int savedStderr = dup(STDERR_FILENO);

    if(diagnosticsFD >= 0 && savedStderr >= 0)
    {
        dup2(diagnosticsFD, STDERR_FILENO);
    }

    llvm::remove_fatal_error_handler();
    int status = swift::performFrontend(args, "swift-frontend", nullptr);
    CCInstallLLVMFatalErrorHandler();

    if(savedStderr >= 0)
    {
        dup2(savedStderr, STDERR_FILENO);
        close(savedStderr);
    }

    if(outOutput != nullptr)
    {
        *outOutput = diagnosticsFD >= 0 ? CCStringCreateWithFileDescriptor(kCFAllocatorSystemDefault, diagnosticsFD) : CFSTR("");
    }

    if(diagnosticsFD >= 0)
    {
        close(diagnosticsFD);
        unlink(templatePath);
    }

    return status == 0;
}
