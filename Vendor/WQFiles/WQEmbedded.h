#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
void WQIntegratedInitialize(void);
UIViewController *WQIntegratedMakeViewController(void);
NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *WQIntegratedIdentities(NSArray<NSString *> *paths);
NSDictionary<NSString *, id> *WQIntegratedRuntimeReport(void);
NS_ASSUME_NONNULL_END
