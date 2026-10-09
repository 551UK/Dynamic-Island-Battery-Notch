#import "IBNRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

static NSString *const IBNDomain = @"com.551.islandbatterynotch";
static NSString *const IBNChanged = @"com.551.islandbatterynotch/preferences.changed";

@interface IBNRootListController () <UIColorPickerViewControllerDelegate>
@end
@implementation IBNRootListController {
    NSString *_activeColourKey;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Dynamic Island Battery Notch";
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id def = [specifier propertyForKey:@"default"];
    if (!key) return def;
    CFPreferencesAppSynchronize((__bridge CFStringRef)IBNDomain);
    CFPropertyListRef stored = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)IBNDomain);
    id result = stored ? CFBridgingRelease(stored) : def;
    // Clamp preferences saved by older versions too, so Settings never
    // displays a thickness below the new physical minimum of 1.5 pt.
    if ([key isEqualToString:@"thickness"] && [result respondsToSelector:@selector(doubleValue)])
        return @(MAX(1.5, MIN(8.0, [result doubleValue])));
    if ([key isEqualToString:@"chargingThickness"]) {
        // Preserve the existing appearance when upgrading from versions that
        // did not have a separate charging-thickness slider.
        if (!stored) {
            CFPropertyListRef normal = CFPreferencesCopyAppValue(CFSTR("thickness"), (__bridge CFStringRef)IBNDomain);
            if (normal) result = CFBridgingRelease(normal);
        }
        if ([result respondsToSelector:@selector(doubleValue)])
            return @(MAX(1.5, MIN(12.0, [result doubleValue])));
    }
    return result;
}
- (void)notifyChange {
    CFPreferencesAppSynchronize((__bridge CFStringRef)IBNDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)IBNChanged, NULL, NULL, YES);
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    if ([key isEqualToString:@"thickness"] && [value respondsToSelector:@selector(doubleValue)])
        value = @(MAX(1.5, MIN(8.0, [value doubleValue])));
    if ([key isEqualToString:@"chargingThickness"] && [value respondsToSelector:@selector(doubleValue)])
        value = @(MAX(1.5, MIN(12.0, [value doubleValue])));
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
    // The footer belongs to the group that ENDS with the automatic-colours
    // switch, so it appears below that switch rather than the manual picker.
    [group setProperty:@"0–20% red, 21–60% yellow, 61–100% green. Turn off automatic colours to use the manual colour." forKey:@"footerText"];
    [items addObject:group];
    [items addObject:[self prefNamed:@"Enabled" key:@"enabled" cell:PSSwitchCell defaultValue:@YES]];
    [items addObject:[self prefNamed:@"Automatic battery colours" key:@"autoColor" cell:PSSwitchCell defaultValue:@YES]];
    // A new footer-free section prevents the automatic colour note from
    // being displayed underneath the Manual Outline Colour button.
    PSSpecifier *manualGroup = [PSSpecifier groupSpecifierWithName:@"Manual Colour"];
    [items addObject:manualGroup];
    PSSpecifier *picker = [PSSpecifier preferenceSpecifierNamed:@"Manual Outline Colour"
                         target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [picker setButtonAction:@selector(openColourPicker)];
    [items addObject:picker];
    PSSpecifier *chargingGroup = [PSSpecifier groupSpecifierWithName:@"Charging"];
    [chargingGroup setProperty:@"Choose the colour used whenever your phone is connected to power, including when fully charged. This overrides the normal colour while plugged in." forKey:@"footerText"];
    [items addObject:chargingGroup];
    PSSpecifier *chargingPicker = [PSSpecifier preferenceSpecifierNamed:@"Charging Colour"
                         target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [chargingPicker setButtonAction:@selector(openChargingColourPicker)];
    [items addObject:chargingPicker];
    [items addObject:[self prefNamed:@"Pulsing Charging" key:@"pulseCharging" cell:PSSwitchCell defaultValue:@NO]];
    PSSpecifier *chargingThicknessGroup = [PSSpecifier groupSpecifierWithName:@"Charging Thickness"];
    [chargingThicknessGroup setProperty:@"Increasing this makes the charging pulse look stronger. Your normal battery line thickness stays unchanged." forKey:@"footerText"];
    [items addObject:chargingThicknessGroup];
    [self addSlider:items name:@"Charging Line Thickness" key:@"chargingThickness" value:2.5 min:1.5 max:12];
    PSSpecifier *thicknessGroup = [PSSpecifier groupSpecifierWithName:@"NORMAL LINE THICKNESS"];
    [thicknessGroup setProperty:@"Minimum 1.5 pt (slider fully left), up to 8 pt. The Island position and shape remain fixed." forKey:@"footerText"];
    [items addObject:thicknessGroup];
    [self addSlider:items name:@"Line Thickness" key:@"thickness" value:2.5 min:1.5 max:8];
    PSSpecifier *about = [PSSpecifier groupSpecifierWithName:@"About"];
    [about setProperty:@"Made by 551UK" forKey:@"footerText"];
    [items addObject:about];
    PSSpecifier *repo = [PSSpecifier preferenceSpecifierNamed:@"Project on GitHub"
                   target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [repo setButtonAction:@selector(openGitHub)];
    [items addObject:repo];
    _specifiers = [items copy];
    return _specifiers;
}

#pragma mark - Centre the About section without changing ordinary Preferences cells

// The About section is deliberately last in -specifiers. A dedicated
// centre-aligned overlay avoids dependence on PSButtonCell's native inset.
static const NSInteger IBNGitHubTextTag = 551029;
static void IBNHideLinkTextInView(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.tag != IBNGitHubTextTag &&
            [label.text isEqualToString:@"Project on GitHub"]) label.hidden = YES;
    }
    for (UIView *child in view.subviews) {
        if (child.tag != IBNGitHubTextTag) IBNHideLinkTextInView(child);
    }
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if (!cell || indexPath.section != tableView.numberOfSections - 1) return cell;
    IBNHideLinkTextInView(cell.contentView);
    UILabel *link = [cell.contentView viewWithTag:IBNGitHubTextTag];
    if (!link) {
        link = [[UILabel alloc] initWithFrame:cell.contentView.bounds];
        link.tag = IBNGitHubTextTag;
        link.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        link.backgroundColor = UIColor.clearColor;
        link.textAlignment = NSTextAlignmentCenter;
        link.userInteractionEnabled = NO; // Preserve PSButtonCell's tap action.
        [cell.contentView addSubview:link];
    }
    link.text = @"Project on GitHub";
    link.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    link.textColor = cell.tintColor;
    return cell;
}

// Supply a genuinely centred, grey footer instead of relying on the
// stock Preferences footer's left-aligned text container.
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != tableView.numberOfSections - 1)
        return [super tableView:tableView viewForFooterInSection:section];
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(tableView.bounds), 36)];
    footer.backgroundColor = UIColor.clearColor;
    UILabel *credit = [UILabel new];
    credit.text = @"Made by 551UK";
    credit.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    credit.textColor = UIColor.secondaryLabelColor;
    credit.textAlignment = NSTextAlignmentCenter;
    credit.backgroundColor = UIColor.clearColor;
    credit.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:credit];
    [NSLayoutConstraint activateConstraints:@[
        [credit.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [credit.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [credit.widthAnchor constraintLessThanOrEqualToAnchor:footer.widthAnchor constant:-24]
    ]];
    return footer;
}
- (NSString *)currentHexForKey:(NSString *)key {
    CFPreferencesAppSynchronize((__bridge CFStringRef)IBNDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)IBNDomain);
    id obj = value ? CFBridgingRelease(value) : nil;
    NSString *fallback = [key isEqualToString:@"chargingColor"] ? @"#00D7FF" : @"#30D158";
    return [obj isKindOfClass:NSString.class] ? obj : fallback;
}
- (void)openPickerForKey:(NSString *)key {
    _activeColourKey = [key copy];
    NSString *hex = [self currentHexForKey:key];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    unsigned int rgb = [key isEqualToString:@"chargingColor"] ? 0x00D7FF : 0x30D158;
    if (hex.length == 6) {
        unsigned int candidate = 0;
        NSScanner *scanner = [NSScanner scannerWithString:hex];
        if ([scanner scanHexInt:&candidate] && scanner.isAtEnd) rgb = candidate;
    }
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.supportsAlpha = NO;
    picker.title = [key isEqualToString:@"chargingColor"] ? @"Charging Colour" : @"Manual Outline Colour";
    picker.selectedColor = [UIColor colorWithRed:((rgb>>16)&255)/255.0
           green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)openColourPicker { [self openPickerForKey:@"fixedColor"]; }
- (void)openColourPicker:(id)sender { [self openColourPicker]; }
- (void)openChargingColourPicker { [self openPickerForKey:@"chargingColor"]; }
- (void)openChargingColourPicker:(id)sender { [self openChargingColourPicker]; }
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)picker {
    CGFloat r=0,g=0,b=0,a=0;
    if (![picker.selectedColor getRed:&r green:&g blue:&b alpha:&a]) return;
    NSString *hex=[NSString stringWithFormat:@"#%02X%02X%02X",
         (unsigned)lrint(r*255), (unsigned)lrint(g*255), (unsigned)lrint(b*255)];
    NSString *key = _activeColourKey ?: @"fixedColor";
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)hex, (__bridge CFStringRef)IBNDomain);
    [self notifyChange];
}
- (void)openGitHub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/551UK/Dynamic-Island-Battery-Notch"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}
- (void)openGitHub:(id)sender { [self openGitHub]; }
@end
