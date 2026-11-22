#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Returns the first App Group from this process' effective, signed
/// `com.apple.security.application-groups` entitlement whose container the
/// current sandbox actually exposes.
///
/// This is a read-only query of entitlements the app already has. It does not
/// add, request, or synthesize an entitlement. If the signed build has no
/// usable App Group, this returns nil and worse_query stays unavailable.
NSString * _Nullable WQAuthorizedAppGroup(void);

NS_ASSUME_NONNULL_END
