#import "ViniLoginViewController.h"
#import <Security/Security.h>

static NSString * const ViniEndpoint = @"https://vini-v2-api.loboangel39.workers.dev/api/app/validate-license";
static NSString * const ViniKeychainService = @"com.vini.bootstrap.test";

@interface ViniLoginViewController ()
@property(nonatomic, copy) NSString *diagnostic;
@property(nonatomic, strong) UITextField *licenseField;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIActivityIndicatorView *spinner;
@property(nonatomic, strong) UIButton *activateButton;
@end

@implementation ViniLoginViewController

- (instancetype)initWithDiagnostic:(NSString *)diagnostic {
    self = [super init];
    if (self) { _diagnostic = [diagnostic copy]; }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    UILabel *title = [self label:@"VINI LICENSE" size:28 color:UIColor.whiteColor];
    UILabel *subtitle = [self label:@"Introduce tu licencia" size:17 color:UIColor.redColor];
    self.licenseField = [[UITextField alloc] init];
    self.licenseField.placeholder = @"Introduce tu licencia";
    self.licenseField.textColor = UIColor.whiteColor;
    self.licenseField.backgroundColor = [UIColor colorWithWhite:1 alpha:.12];
    self.licenseField.borderStyle = UITextBorderStyleRoundedRect;
    self.licenseField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.activateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.activateButton setTitle:@"ACTIVAR LICENCIA" forState:UIControlStateNormal];
    [self.activateButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.activateButton.backgroundColor = UIColor.redColor;
    self.activateButton.layer.cornerRadius = 8;
    [self.activateButton addTarget:self action:@selector(activate) forControlEvents:UIControlEventTouchUpInside];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.color = UIColor.whiteColor;
    self.statusLabel = [self label:self.diagnostic size:12 color:UIColor.lightGrayColor];
    self.statusLabel.numberOfLines = 0;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, subtitle, self.licenseField, self.activateButton, self.spinner, self.statusLabel]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 16; stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] init]; label.text = text; label.font = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold]; label.textColor = color; label.textAlignment = NSTextAlignmentCenter; return label;
}

- (void)activate {
    NSString *key = [self.licenseField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (key.length == 0) { self.statusLabel.text = @"Introduce una licencia."; return; }
    self.activateButton.enabled = NO; [self.spinner startAnimating]; self.statusLabel.text = @"Verificando licencia...";
    NSString *hwid = [self keychainValue:@"hwid"] ?: NSUUID.UUID.UUIDString;
    [self setKeychainValue:hwid key:@"hwid"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:ViniEndpoint]];
    request.HTTPMethod = @"POST"; [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"licenseKey":key, @"hwid":hwid} options:0 error:nil];
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.activateButton.enabled = YES; [self.spinner stopAnimating];
            if (error || ![response isKindOfClass:NSHTTPURLResponse.class]) { self.statusLabel.text = @"No se pudo conectar con el servidor."; return; }
            NSInteger code = ((NSHTTPURLResponse *)response).statusCode;
            NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (code < 200 || code >= 300 || ![json[@"valid"] boolValue]) { self.statusLabel.text = json[@"error"] ?: @"Licencia inválida."; return; }
            [self setKeychainValue:key key:@"license"]; if ([json[@"token"] isKindOfClass:NSString.class]) [self setKeychainValue:json[@"token"] key:@"token"];
            self.statusLabel.text = [NSString stringWithFormat:@"Licencia activa\nUsuario: %@\nVencimiento: %@", json[@"username"] ?: @"—", json[@"licenseExpiresAt"] ?: @"según el servidor"];
        });
    }];
    [task resume];
}

- (NSString *)keychainValue:(NSString *)key { NSDictionary *q=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:ViniKeychainService,(__bridge id)kSecAttrAccount:key,(__bridge id)kSecReturnData:@YES,(__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitOne}; CFTypeRef result=NULL; if(SecItemCopyMatching((__bridge CFDictionaryRef)q,&result)==errSecSuccess){NSData *d=CFBridgingRelease(result);return [[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding];} return nil; }
- (void)setKeychainValue:(NSString *)value key:(NSString *)key { NSDictionary *q=@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:ViniKeychainService,(__bridge id)kSecAttrAccount:key}; SecItemDelete((__bridge CFDictionaryRef)q); NSMutableDictionary *add=[q mutableCopy]; add[(__bridge id)kSecValueData]=[value dataUsingEncoding:NSUTF8StringEncoding]; add[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; SecItemAdd((__bridge CFDictionaryRef)add,NULL); }
@end
