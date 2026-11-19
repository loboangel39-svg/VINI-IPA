#import <UIKit/UIKit.h>
#import "WQEmbedded.h"
#import "WQAccess.h"
#import "WQCore.h"
#import "WQArchive.h"

@interface WQSmokeScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation WQSmokeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    NSLog(@"WQ integration smoke scene connected");
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = WQIntegratedMakeViewController();
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *checks = [NSMutableArray new];
        NSString *error = nil;
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        BOOL ok = wq_create_dir(dir, &error);
        [checks addObject:@{ @"createDirectory": @(ok) }];
        NSString *file = [dir stringByAppendingPathComponent:@"sample.txt"];
        NSData *first = [@"original" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *second = [@"verified" dataUsingEncoding:NSUTF8StringEncoding];
        ok &= wq_create_file(file, first, &error);
        NSDictionary *version = wq_file_version(file);
        BOOL saved = wq_write_if_unchanged(file, second, version, &error);
        BOOL bytesMatch = [wq_read(file, 0, &error) isEqualToData:second];
        ok &= saved && bytesMatch;
        [checks addObject:@{ @"writeReadBackup": @(saved && bytesMatch) }];
        BOOL staleRejected = !wq_write_if_unchanged(file, first, version, &error);
        ok &= staleRejected;
        [checks addObject:@{ @"staleWriteRejected": @(staleRejected) }];
        unsigned long long bytes = 0;
        BOOL measured = wq_measure_tree(dir, nil, &bytes) == WQMeasureResultKnown && bytes == second.length;
        ok &= measured;
        [checks addObject:@{ @"measureActualTree": @(measured) }];
        NSString *copy = [dir stringByAppendingString:@"-copy"];
        BOOL copied = wq_copy_tree_new(dir, copy, nil, &error);
        ok &= copied && [wq_read([copy stringByAppendingPathComponent:@"sample.txt"], 0, nil) isEqualToData:second];
        [checks addObject:@{ @"copyActualTree": @(copied) }];
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL hosted = self.window.rootViewController.childViewControllers.count == 1;
            [checks addObject:@{ @"embeddedUIKitRoot": @(hosted) }];
            NSDictionary *report = @{ @"passed": @(ok && hosted), @"checks": checks,
                @"environment": @"iOS Simulator, real WQFiles implementations and local files",
                @"deviceSandboxEscapeValidated": @NO };
            NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            [[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil]
                writeToFile:[documents stringByAppendingPathComponent:@"integration-smoke.json"] atomically:YES];
            exit(ok && hosted ? 0 : 1);
        });
    });
}
@end
@interface WQSmokeDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation WQSmokeDelegate
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Smoke" sessionRole:session.role];
    config.delegateClass = WQSmokeScene.class;
    return config;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(WQSmokeDelegate.class)); }
}
