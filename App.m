#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "SaverExporter.h"

@protocol VSMDropDelegate <NSObject>
- (void)addVideoURLs:(NSArray<NSURL *> *)urls;
- (BOOL)acceptsFiles;
@end

@interface VSMDropView : NSView <NSDraggingDestination>
@property(nonatomic, weak) id<VSMDropDelegate> receiver;
@property(nonatomic) BOOL highlighted;
@end
@implementation VSMDropView
- (instancetype)init {
    if ((self = [super init])) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
        self.wantsLayer = YES;
        self.layer.cornerRadius = 14;
        self.layer.borderWidth = 2;
    }
    return self;
}
- (void)updateLayer {
    self.layer.backgroundColor = [NSColor.controlAccentColor colorWithAlphaComponent:self.highlighted ? .16 : .05].CGColor;
    self.layer.borderColor = [NSColor.controlAccentColor colorWithAlphaComponent:self.highlighted ? .9 : .3].CGColor;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if (![self.receiver acceptsFiles]) return NSDragOperationNone;
    self.highlighted = YES; self.needsDisplay = YES;
    return NSDragOperationCopy;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender { self.highlighted = NO; self.needsDisplay = YES; }
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender { return [self.receiver acceptsFiles]; }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.highlighted = NO; self.needsDisplay = YES;
    NSArray *urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey:@YES}];
    [self.receiver addVideoURLs:urls];
    return urls.count > 0;
}
@end

@interface VSMAppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, VSMDropDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTableView *table;
@property(nonatomic, strong) NSTextField *nameField;
@property(nonatomic, strong) NSTextField *summary;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSPopUpButton *order;
@property(nonatomic, strong) NSPopUpButton *fit;
@property(nonatomic, strong) NSButton *exportButton;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) NSMutableArray<NSURL *> *videos;
@property(nonatomic, strong) NSMutableArray<NSControl *> *editingControls;
@property(nonatomic) BOOL working;
@end

static NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return label;
}

@implementation VSMAppDelegate
- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    [self.editingControls addObject:b];
    return b;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.videos = [NSMutableArray array];
    self.editingControls = [NSMutableArray array];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,800,800)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Video Saver Maker";
    self.window.minSize = NSMakeSize(720,780);
    [self.window center];
    NSStackView *root = [[NSStackView alloc] init];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 12;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:28],
        [root.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-28],
        [root.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:22],
        [root.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor constant:-22]
    ]];
    [root addArrangedSubview:Label(@"把喜歡的影片，變成屏保。",26,NSFontWeightSemibold)];
    NSTextField *intro = Label(@"加入一個或多個影片，輸出可安裝的 .saver 檔案。",13,NSFontWeightRegular);
    intro.textColor = NSColor.secondaryLabelColor;
    [root addArrangedSubview:intro];

    VSMDropView *drop = [[VSMDropView alloc] init];
    drop.receiver = self;
    drop.translatesAutoresizingMaskIntoConstraints = NO;
    [root addArrangedSubview:drop];
    [drop.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
    [drop.heightAnchor constraintEqualToConstant:100].active = YES;
    NSStackView *dropText = [NSStackView stackViewWithViews:@[
        Label(@"↓  拖放影片到這裡",18,NSFontWeightMedium),
        Label(@"MP4 · MOV · M4V",12,NSFontWeightRegular)
    ]];
    dropText.orientation = NSUserInterfaceLayoutOrientationVertical;
    dropText.alignment = NSLayoutAttributeCenterX;
    dropText.spacing = 8;
    dropText.translatesAutoresizingMaskIntoConstraints = NO;
    [drop addSubview:dropText];
    [NSLayoutConstraint activateConstraints:@[
        [dropText.centerXAnchor constraintEqualToAnchor:drop.centerXAnchor],
        [dropText.centerYAnchor constraintEqualToAnchor:drop.centerYAnchor]
    ]];

    self.summary = Label(@"尚未加入影片",12,NSFontWeightMedium);
    [root addArrangedSubview:self.summary];
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    self.table = [[NSTableView alloc] init];
    NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    name.title = @"影片（依列表順序播放）"; name.width = 540; name.minWidth = 300;
    NSTableColumn *size = [[NSTableColumn alloc] initWithIdentifier:@"size"];
    size.title = @"大小"; size.width = 110;
    [self.table addTableColumn:name]; [self.table addTableColumn:size];
    self.table.dataSource = self; self.table.delegate = self;
    self.table.allowsMultipleSelection = YES;
    self.table.rowHeight = 30;
    self.table.usesAlternatingRowBackgroundColors = YES;
    scroll.documentView = self.table;
    [root addArrangedSubview:scroll];
    [scroll.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;
    [scroll setContentHuggingPriority:200 forOrientation:NSLayoutConstraintOrientationVertical];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[
        [self button:@"加入影片…" action:@selector(chooseVideos:)],
        [self button:@"移除所選" action:@selector(removeVideos:)],
        [self button:@"上移" action:@selector(moveUp:)],
        [self button:@"下移" action:@selector(moveDown:)],
        [self button:@"清空" action:@selector(clearVideos:)]
    ]];
    buttons.spacing = 8;
    [root addArrangedSubview:buttons];

    self.nameField = [[NSTextField alloc] init];
    self.nameField.stringValue = @"My Video Saver";
    self.nameField.placeholderString = @"屏保名稱";
    [self.nameField.widthAnchor constraintEqualToConstant:260].active = YES;
    [self.editingControls addObject:self.nameField];
    self.order = [[NSPopUpButton alloc] init];
    [self.order addItemsWithTitles:@[@"依序循環", @"隨機順序循環"]];
    self.fit = [[NSPopUpButton alloc] init];
    [self.fit addItemsWithTitles:@[@"填滿螢幕（裁切邊緣）", @"完整顯示（可能有黑邊）"]];
    [self.editingControls addObjectsFromArray:@[self.order,self.fit]];
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[Label(@"屏保名稱",13,NSFontWeightMedium),self.nameField],
        @[Label(@"播放方式",13,NSFontWeightMedium),self.order],
        @[Label(@"畫面比例",13,NSFontWeightMedium),self.fit]
    ]];
    grid.rowSpacing = 10; grid.columnSpacing = 18;
    [root addArrangedSubview:grid];
    NSTextField *hint = Label(@"靜音播放。影片會內嵌到屏保，安裝後不需保留原始檔案。",12,NSFontWeightRegular);
    hint.textColor = NSColor.secondaryLabelColor;
    [root addArrangedSubview:hint];
    self.status = Label(@"準備好後，選擇輸出位置。",12,NSFontWeightRegular);
    self.status.textColor = NSColor.secondaryLabelColor;
    [root addArrangedSubview:self.status];
    [self.status.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
    self.exportButton = [self button:@"輸出 .saver…" action:@selector(exportSaver:)];
    self.exportButton.bezelStyle = NSBezelStyleRounded;
    self.exportButton.keyEquivalent = @"\r";
    self.exportButton.enabled = NO;
    self.progress = [[NSProgressIndicator alloc] init];
    self.progress.style = NSProgressIndicatorStyleSpinning;
    self.progress.displayedWhenStopped = NO;
    NSStackView *footer = [NSStackView stackViewWithViews:@[self.exportButton,self.progress]];
    footer.spacing = 12;
    [root addArrangedSubview:footer];
    [self setupMenu];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)setupMenu {
    NSMenu *main = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [main addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Video Saver Maker"];
    [appMenu addItemWithTitle:@"關於 Video Saver Maker" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"結束 Video Saver Maker" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    NSMenuItem *fileItem = [[NSMenuItem alloc] init]; [main addItem:fileItem];
    NSMenu *file = [[NSMenu alloc] initWithTitle:@"檔案"];
    NSMenuItem *add = [file addItemWithTitle:@"加入影片…" action:@selector(chooseVideos:) keyEquivalent:@"o"]; add.target = self;
    NSMenuItem *export = [file addItemWithTitle:@"輸出 .saver…" action:@selector(exportSaver:) keyEquivalent:@"s"]; export.target = self;
    fileItem.submenu = file;
    NSMenuItem *editItem = [[NSMenuItem alloc] init]; [main addItem:editItem];
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"編輯"];
    [edit addItemWithTitle:@"復原" action:@selector(undo:) keyEquivalent:@"z"];
    [edit addItemWithTitle:@"剪下" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"複製" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"貼上" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"全選" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = edit;
    NSApp.mainMenu = main;
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (!self.working) return NSTerminateNow;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"正在輸出屏保";
    alert.informativeText = @"請等待輸出完成後再結束程式。";
    [alert runModal];
    return NSTerminateCancel;
}
- (BOOL)acceptsFiles { return !self.working; }
- (void)addVideoURLs:(NSArray<NSURL *> *)urls {
    if (self.working) return;
    NSUInteger skipped = 0;
    for (NSURL *url in urls) {
        NSURL *normalized = url.URLByResolvingSymlinksInPath.URLByStandardizingPath;
        if (![VSMSaverExporter isVideoURL:normalized]) { skipped++; continue; }
        if (![self.videos containsObject:normalized]) [self.videos addObject:normalized];
    }
    [self refresh];
    self.status.stringValue = skipped ? [NSString stringWithFormat:@"已略過 %lu 個不支援的檔案，請使用 MP4、MOV 或 M4V。",(unsigned long)skipped] : @"可繼續加入影片，或直接輸出屏保。";
}
- (void)chooseVideos:(id)sender {
    if (self.working) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"選擇影片"; panel.canChooseDirectories = NO; panel.allowsMultipleSelection = YES;
    panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"mp4"], [UTType typeWithFilenameExtension:@"mov"], [UTType typeWithFilenameExtension:@"m4v"]];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) [self addVideoURLs:panel.URLs];
    }];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.videos.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSURL *url = self.videos[row];
    NSString *value = url.lastPathComponent;
    if ([column.identifier isEqual:@"size"]) {
        NSNumber *size = nil; [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        value = [NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
    }
    NSTextField *label = Label(value,13,NSFontWeightRegular); label.toolTip = url.path;
    NSTableCellView *cell = [[NSTableCellView alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [cell addSubview:label]; cell.textField = label;
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-8],
        [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
    ]];
    return cell;
}
- (void)refresh {
    [self.table reloadData];
    long long total = 0;
    for (NSURL *url in self.videos) {
        NSNumber *size = nil; [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil]; total += size.longLongValue;
    }
    self.summary.stringValue = [NSString stringWithFormat:@"%lu 個影片 · %@", (unsigned long)self.videos.count,
        [NSByteCountFormatter stringFromByteCount:total countStyle:NSByteCountFormatterCountStyleFile]];
    self.exportButton.enabled = self.videos.count && !self.working;
}
- (void)removeVideos:(id)sender {
    if (self.working) return;
    [self.videos removeObjectsAtIndexes:self.table.selectedRowIndexes]; [self refresh];
}
- (void)clearVideos:(id)sender { if (!self.working) { [self.videos removeAllObjects]; [self refresh]; } }
- (void)moveBy:(NSInteger)delta {
    if (self.working || self.table.selectedRowIndexes.count != 1) return;
    NSInteger row = self.table.selectedRow;
    NSInteger target = row + delta;
    if (target < 0 || target >= (NSInteger)self.videos.count) return;
    [self.videos exchangeObjectAtIndex:row withObjectAtIndex:target]; [self refresh];
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:target] byExtendingSelection:NO];
}
- (void)moveUp:(id)sender { [self moveBy:-1]; }
- (void)moveDown:(id)sender { [self moveBy:1]; }
- (void)setBusy:(BOOL)busy {
    self.working = busy;
    for (NSControl *control in self.editingControls) control.enabled = !busy;
    self.table.enabled = !busy;
    self.exportButton.enabled = !busy && self.videos.count > 0;
    if (busy) [self.progress startAnimation:nil]; else [self.progress stopAnimation:nil];
}
- (void)exportSaver:(id)sender {
    if (self.working || !self.videos.count) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"選擇屏保輸出資料夾"; panel.prompt = @"輸出到這裡";
    panel.canChooseFiles = NO; panel.canChooseDirectories = YES; panel.canCreateDirectories = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSArray *videos = [self.videos copy]; NSString *name = self.nameField.stringValue;
        BOOL shuffle = self.order.indexOfSelectedItem == 1; BOOL fit = self.fit.indexOfSelectedItem == 1;
        [self setBusy:YES]; self.status.stringValue = @"正在複製影片及建立屏保，請稍候…";
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            @autoreleasepool {
                NSError *error = nil;
                NSURL *result = [VSMSaverExporter exportVideos:videos name:name directory:panel.URL shuffle:shuffle fit:fit error:&error];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setBusy:NO];
                    NSAlert *alert = [[NSAlert alloc] init];
                    if (result) {
                        self.status.stringValue = [NSString stringWithFormat:@"已輸出 %@",result.lastPathComponent];
                        alert.messageText = @"屏保已建立";
                        alert.informativeText = @"雙擊 .saver 安裝後，在系統設定中選擇這個屏保，並使用預覽確認播放效果。";
                        [alert addButtonWithTitle:@"在 Finder 顯示"];
                        [alert addButtonWithTitle:@"安裝屏保"];
                        [alert addButtonWithTitle:@"完成"];
                    } else {
                        self.status.stringValue = @"輸出未完成，請查看錯誤訊息。";
                        alert.messageText = @"無法輸出屏保"; alert.informativeText = error.localizedDescription;
                        [alert addButtonWithTitle:@"好"];
                    }
                    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse choice) {
                        if (!result) return;
                        if (choice == NSAlertFirstButtonReturn) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[result]];
                        else if (choice == NSAlertSecondButtonReturn) [NSWorkspace.sharedWorkspace openURL:result];
                    }];
                });
            }
        });
    }];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1],"--export") == 0) {
            NSMutableArray<NSURL *> *videos = [NSMutableArray array];
            NSString *name = @"My Video Saver"; NSURL *directory = nil;
            BOOL shuffle = NO, fit = NO;
            for (int i = 2; i < argc; i++) {
                NSString *arg = [NSString stringWithUTF8String:argv[i]];
                if ([arg isEqual:@"--name"] && i+1 < argc) name = [NSString stringWithUTF8String:argv[++i]];
                else if ([arg isEqual:@"--output"] && i+1 < argc) directory = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[++i]] isDirectory:YES];
                else if ([arg isEqual:@"--shuffle"]) shuffle = YES;
                else if ([arg isEqual:@"--fit"]) fit = YES;
                else [videos addObject:[NSURL fileURLWithPath:arg]];
            }
            if (!directory) { fprintf(stderr,"Usage: --export --name NAME --output DIRECTORY [--shuffle] [--fit] VIDEO...\n"); return 2; }
            NSError *error = nil;
            NSURL *result = [VSMSaverExporter exportVideos:videos name:name directory:directory shuffle:shuffle fit:fit error:&error];
            if (!result) { fprintf(stderr,"%s\n",error.localizedDescription.UTF8String); return 1; }
            printf("%s\n",result.path.UTF8String); return 0;
        }
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        __attribute__((objc_precise_lifetime)) VSMAppDelegate *delegate = [[VSMAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
