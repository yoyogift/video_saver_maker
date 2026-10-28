#import <ScreenSaver/ScreenSaver.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface VSMVideoScreenSaver_0000000000000000 : ScreenSaverView
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) id endObserver;
@property(nonatomic, copy) NSArray<NSURL *> *movies;
@property(nonatomic, strong) NSMutableSet<AVPlayerItem *> *ownedItems;
@property(nonatomic) NSUInteger nextIndex;
@end

@implementation VSMVideoScreenSaver_0000000000000000
- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)preview {
    if ((self = [super initWithFrame:frame isPreview:preview])) {
        self.animationTimeInterval = 1;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
    }
    return self;
}

- (AVPlayerItem *)nextItem {
    if (!self.movies.count) return nil;
    NSURL *url = self.movies[self.nextIndex % self.movies.count];
    self.nextIndex = (self.nextIndex + 1) % self.movies.count;
    return [AVPlayerItem playerItemWithURL:url];
}

- (void)startAnimation {
    [super startAnimation];
    if (self.player) { [self.player play]; return; }
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSURL *manifestURL = [bundle URLForResource:@"Playlist" withExtension:@"plist"];
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfURL:manifestURL];
    NSMutableArray<NSURL *> *movies = [NSMutableArray array];
    for (NSString *file in manifest[@"files"]) {
        NSURL *url = [[bundle resourceURL] URLByAppendingPathComponent:file];
        if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) [movies addObject:url];
    }
    if ([manifest[@"shuffle"] boolValue]) {
        for (NSUInteger i = movies.count; i > 1; i--) {
            [movies exchangeObjectAtIndex:i-1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
        }
    }
    self.movies = movies;
    self.nextIndex = 0;
    if (!movies.count) return;
    NSArray *initialItems = @[[self nextItem], [self nextItem]];
    self.ownedItems = [NSMutableSet setWithArray:initialItems];
    self.player = [AVQueuePlayer queuePlayerWithItems:initialItems];
    self.player.muted = YES;
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndAdvance;
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = [manifest[@"fit"] isEqual:@"fit"]
        ? AVLayerVideoGravityResizeAspect : AVLayerVideoGravityResizeAspectFill;
    self.playerLayer.frame = self.bounds;
    self.playerLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    [self.layer addSublayer:self.playerLayer];
    __weak VSMVideoScreenSaver_0000000000000000 *weakSelf = self;
    self.endObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) {
            VSMVideoScreenSaver_0000000000000000 *view = weakSelf;
            if (!view.player) return;
            // Ignore events from players belonging to other screens or previews.
            if (![view.ownedItems containsObject:note.object]) return;
            [view.ownedItems removeObject:note.object];
            // Keep two items queued. The callback can arrive before or after auto-advance.
            AVPlayerItem *item = [view nextItem];
            if (item) {
                [view.ownedItems addObject:item];
                [view.player insertItem:item afterItem:nil];
            }
        }];
    [self.player play];
}

- (void)layout {
    [super layout];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.playerLayer.frame = self.bounds;
    [CATransaction commit];
}

- (void)stopAnimation {
    if (self.endObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.endObserver];
    self.endObserver = nil;
    [self.player pause];
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer.player = nil;
    [self.player removeAllItems];
    self.player = nil;
    self.playerLayer = nil;
    self.movies = nil;
    self.ownedItems = nil;
    [super stopAnimation];
}

- (void)dealloc {
    if (_endObserver) [[NSNotificationCenter defaultCenter] removeObserver:_endObserver];
    [_player pause];
}
- (BOOL)hasConfigureSheet { return NO; }
- (void)animateOneFrame { }
@end
