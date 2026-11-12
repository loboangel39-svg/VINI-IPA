#import "AppDelegate.h"
#import "ViniNativeBootstrap.h"

@interface AppDelegate ()
@property(nonatomic, copy) NSString *diagnostic;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application; (void)launchOptions;
    ViniBootstrapStart();
    self.diagnostic = @"ViniNativeBootstrap ejecutado explícitamente";
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *diagnosticController = [[UIViewController alloc] init];
    diagnosticController.view.backgroundColor = UIColor.blackColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = self.diagnostic; label.textColor = UIColor.whiteColor; label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [diagnosticController.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[label.centerXAnchor constraintEqualToAnchor:diagnosticController.view.centerXAnchor], [label.centerYAnchor constraintEqualToAnchor:diagnosticController.view.centerYAnchor]]];
    self.window.rootViewController = diagnosticController;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
