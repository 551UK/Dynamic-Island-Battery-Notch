#import "IBNRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>

static NSString *const IBNDomain = @"com.551.islandbatterynotch";
@implementation IBNRootListController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize((__bridge CFStringRef)IBNDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)IBNDomain);
    return value ? CFBridgingRelease(value) : [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)IBNDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)IBNDomain);
    notify_post("com.551.islandbatterynotch/preferences.changed");
}
@end
