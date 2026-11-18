#import "WQEntitlements.h"
#import <dlfcn.h>

// SecTask is resolved dynamically so this file does not need private headers.
// It only reads the app's own effective entitlements; it does not modify them.
typedef CFTypeRef (*WQSecTaskCreateFn)(CFAllocatorRef);
typedef CFTypeRef (*WQSecTaskCopyEntitlementFn)(CFTypeRef, CFStringRef, CFErrorRef *);

NSString *WQAuthorizedAppGroup(void) {
    void *security = dlopen(
        "/System/Library/Frameworks/Security.framework/Security",
        RTLD_LAZY | RTLD_LOCAL
    );
    if (!security) return nil;

    WQSecTaskCreateFn createTask =
        (WQSecTaskCreateFn)dlsym(security, "SecTaskCreateFromSelf");
    WQSecTaskCopyEntitlementFn copyEntitlement =
        (WQSecTaskCopyEntitlementFn)dlsym(security, "SecTaskCopyValueForEntitlement");
    if (!createTask || !copyEntitlement) {
        dlclose(security);
        return nil;
    }

    CFTypeRef task = createTask(NULL);
    if (!task) {
        dlclose(security);
        return nil;
    }

    CFErrorRef error = NULL;
    CFTypeRef value = copyEntitlement(
        task,
        CFSTR("com.apple.security.application-groups"),
        &error
    );
    if (error) CFRelease(error);
    CFRelease(task);
    if (!value) {
        dlclose(security);
        return nil;
    }

    NSString *result = nil;
    if (CFGetTypeID(value) == CFArrayGetTypeID()) {
        for (id item in (__bridge NSArray *)value) {
            if (![item isKindOfClass:NSString.class]) continue;
            NSString *group = (NSString *)item;
            if (![group hasPrefix:@"group."]) continue;

            // Only report a group whose container is genuinely reachable.
            // A string in the entitlement list alone is not proof of access.
            NSURL *container = [[NSFileManager defaultManager]
                containerURLForSecurityApplicationGroupIdentifier:group];
            if (container) {
                result = group;
                break;
            }
        }
    }

    CFRelease(value);
    dlclose(security);
    return result;
}
