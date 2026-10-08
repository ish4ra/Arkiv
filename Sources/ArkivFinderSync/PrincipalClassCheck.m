#import <Foundation/Foundation.h>
#import <FinderSync/FinderSync.h>
#include <stdlib.h>
#include <stdio.h>

// A CI-only command-line probe in the actual shipped executable. Normal launches
// retain Apple's NSExtensionMain entry point and do not instantiate anything here.
__attribute__((constructor)) static void verifyPrincipalClassWhenRequested(void) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.arguments containsObject:@"--verify-principal-class"]) return;
        NSString *principal = NSBundle.mainBundle.infoDictionary[@"NSExtension"][@"NSExtensionPrincipalClass"];
        Class actual = principal ? NSClassFromString(principal) : Nil;
        if (![principal isEqualToString:@"ArkivFinderSync.ArkivFinderSync"] ||
            !actual || ![actual isSubclassOfClass:FIFinderSync.class] ||
            ![NSStringFromClass(actual) isEqualToString:principal]) {
            fputs("Finder Sync principal class does not resolve to the packaged Swift class\n", stderr);
            exit(1);
        }
        puts("Verified runtime Finder Sync principal class: ArkivFinderSync.ArkivFinderSync");
        exit(0);
    }
}
