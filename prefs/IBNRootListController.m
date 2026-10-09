#import "IBNRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static NSString *const IBNDomain = @"com.551.islandbatterynotch";
static NSString *const IBNChanged = @"com.551.islandbatterynotch/preferences.changed";

@interface IBNRootListController () <UIColorPickerViewControllerDelegate>
@end
@implementation IBNRootListController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Island Battery Notch";
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id def = [specifier propertyForKey:@"default"];
    if (!key) return def;
    CFPreferencesAppSynchronize((__bridge CFStringRef)IBNDomain);
    CFPropertyListRef stored = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)IBNDomain);
    return stored ? CFBridgingRelease(stored) : def;
}
- (void)notifyChange {
    CFPreferencesAppSynchronize((__bridge CFStringRef)IBNDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)IBNChanged, NULL, NULL, YES);
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)IBNDomain);
    [self notifyChange];
}
- (PSSpecifier *)prefNamed:(NSString *)name key:(NSString *)key cell:(PSCellType)cell
              defaultValue:(id)value {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self
                        set:@selector(setPreferenceValue:specifier:)
                        get:@selector(readPreferenceValue:) detail:nil cell:cell edit:nil];
    [s setProperty:key forKey:@"key"];
    [s setProperty:IBNDomain forKey:@"defaults"];
    [s setProperty:value forKey:@"default"];
    return s;
}
- (void)addSlider:(NSMutableArray *)items name:(NSString *)name key:(NSString *)key
              value:(double)value min:(double)lo max:(double)hi {
    PSSpecifier *s = [self prefNamed:name key:key cell:PSSliderCell defaultValue:@(value)];
    [s setProperty:@(lo) forKey:@"min"];
    [s setProperty:@(hi) forKey:@"max"];
    [s setProperty:@YES forKey:@"showValue"];
    [items addObject:s];
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"Battery progress"];
    [group setProperty:@"Two mirrored outline arcs shrink on every reported 1% change. Visible on Lock Screen, Home Screen and inside apps." forKey:@"footerText"];
    [items addObject:group];
    [items addObject:[self prefNamed:@"Enabled" key:@"enabled" cell:PSSwitchCell defaultValue:@YES]];
    [items addObject:[self prefNamed:@"Automatic battery colours" key:@"autoColor" cell:PSSwitchCell defaultValue:@YES]];
    PSSpecifier *colGroup = [PSSpecifier groupSpecifierWithName:@"Colours"];
    [colGroup setProperty:@"0–20% red, 21–60% yellow, 61–100% green. Turn off automatic colours to use the manual colour." forKey:@"footerText"];
    [items addObject:colGroup];
    PSSpecifier *picker = [PSSpecifier preferenceSpecifierNamed:@"Manual outline colour"
                         target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [picker setButtonAction:@selector(openColourPicker)];
    [items addObject:picker];
    PSSpecifier *pos = [PSSpecifier groupSpecifierWithName:@"Island alignment"];
    [pos setProperty:@"Adjust the resting Dynamic Island outline on your iPhone 14 Pro Max." forKey:@"footerText"];
    [items addObject:pos];
    [self addSlider:items name:@"Width" key:@"width" value:126 min:110 max:150];
    [self addSlider:items name:@"Height" key:@"height" value:37.33 min:30 max:50];
    [self addSlider:items name:@"Top offset" key:@"offsetY" value:11 min:0 max:30];
    [self addSlider:items name:@"Line thickness" key:@"thickness" value:2.5 min:0.5 max:8];
    PSSpecifier *about = [PSSpecifier groupSpecifierWithName:@"About"];
    [items addObject:about];
    PSSpecifier *repo = [PSSpecifier preferenceSpecifierNamed:@"Project on GitHub"
                   target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [repo setButtonAction:@selector(openGitHub)];
    [items addObject:repo];
    _specifiers = [items copy];
    return _specifiers;
}
- (NSString *)currentHex {
    CFPreferencesAppSynchronize((__bridge CFStringRef)IBNDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("fixedColor"), (__bridge CFStringRef)IBNDomain);
    id obj = value ? CFBridgingRelease(value) : nil;
    return [obj isKindOfClass:NSString.class] ? obj : @"#30D158";
}
- (void)openColourPicker {
    NSString *hex = [self currentHex];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    unsigned int rgb=0;
    if (hex.length != 6 || ![[NSScanner scannerWithString:hex] scanHexInt:&rgb]) rgb=0x30D158;
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.supportsAlpha = NO;
    picker.selectedColor = [UIColor colorWithRed:((rgb>>16)&255)/255.0
           green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)openColourPicker:(id)sender { [self openColourPicker]; }
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)picker {
    CGFloat r=0,g=0,b=0,a=0;
    if (![picker.selectedColor getRed:&r green:&g blue:&b alpha:&a]) return;
    NSString *hex=[NSString stringWithFormat:@"#%02X%02X%02X",
         (unsigned)lrint(r*255), (unsigned)lrint(g*255), (unsigned)lrint(b*255)];
    CFPreferencesSetAppValue(CFSTR("fixedColor"), (__bridge CFPropertyListRef)hex, (__bridge CFStringRef)IBNDomain);
    [self notifyChange];
}
- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/551UK/Dynamic-Island-Battery-Notch"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}
- (void)openGitHub:(id)sender { [self openGitHub]; }
@end
