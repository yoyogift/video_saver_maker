#import "SaverExporter.h"
#import <AVFoundation/AVFoundation.h>

@implementation VSMSaverExporter
+ (NSError *)error:(NSString *)message {
    return [NSError errorWithDomain:@"VideoSaverMaker" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
+ (BOOL)isVideoURL:(NSURL *)url {
    if (!url.isFileURL) return NO;
    if (![@[@"mp4", @"mov", @"m4v"] containsObject:url.pathExtension.lowercaseString]) return NO;
    NSNumber *regular = nil;
    [url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
    return regular.boolValue;
}
+ (NSURL *)exportVideos:(NSArray<NSURL *> *)videos name:(NSString *)rawName
             directory:(NSURL *)directory shuffle:(BOOL)shuffle fit:(BOOL)fit error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *name = [rawName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([name.lowercaseString hasSuffix:@".saver"]) name = [name stringByDeletingPathExtension];
    if (!name.length || name.length > 100 || [name hasPrefix:@"."] ||
        [name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:\n\r"]].location != NSNotFound) {
        if (error) *error = [self error:@"請輸入 1–100 字的名稱，開頭不可為句點，且不可包含 / 或 :。"];
        return nil;
    }
    if (!videos.count) { if (error) *error = [self error:@"請先加入至少一個影片。"];
        return nil; }
    for (NSURL *video in videos) {
        if (![self isVideoURL:video]) {
            if (error) *error = [self error:[NSString stringWithFormat:@"無法讀取影片：%@。請使用 MP4、MOV 或 M4V。", video.lastPathComponent]];
            return nil;
        }
        // Read the container before exporting; no transcoding or re-encoding.
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:video options:nil];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        BOOL hasVideo = [asset tracksWithMediaType:AVMediaTypeVideo].count > 0;
        BOOL protected = asset.hasProtectedContent;
#pragma clang diagnostic pop
        if (!hasVideo || protected) {
            if (error) *error = [self error:[NSString stringWithFormat:@"%@ 沒有可用的影像軌，或含有受保護的內容。", video.lastPathComponent]];
            return nil;
        }
    }
    NSURL *destination = [directory URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"saver"] isDirectory:YES];
    if ([fm fileExistsAtPath:destination.path]) {
        if (error) *error = [self error:@"這個資料夾已有同名屏保，請更改名稱或選擇其他資料夾。"];
        return nil;
    }
    NSURL *template = [NSBundle.mainBundle URLForResource:@"VideoTemplate" withExtension:@"saver"];
    if (!template) { if (error) *error = [self error:@"找不到內建屏保引擎，請重新建置或下載此程式。"];
        return nil; }
    NSURL *staging = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@".vsm-%@.saver", NSUUID.UUID.UUIDString] isDirectory:YES];
    NSError *failure = nil;
    if (![fm copyItemAtURL:template toURL:staging error:&failure]) {
        [fm removeItemAtURL:staging error:nil];
        if (error) *error = failure;
        return nil;
    }
    NSURL *result = nil;
    @try {
        NSMutableArray *files = [NSMutableArray array];
        for (NSUInteger i = 0; i < videos.count; i++) {
            NSString *file = [NSString stringWithFormat:@"Video-%04lu.%@", (unsigned long)i+1, videos[i].pathExtension.lowercaseString];
            NSURL *target = [staging URLByAppendingPathComponent:[@"Contents/Resources" stringByAppendingPathComponent:file]];
            if (![fm copyItemAtURL:videos[i] toURL:target error:&failure]) break;
            [files addObject:file];
        }
        if (!failure) {
            NSDictionary *playlist = @{@"files":files, @"shuffle":@(shuffle), @"fit":fit ? @"fit" : @"fill"};
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:playlist format:NSPropertyListXMLFormat_v1_0 options:0 error:&failure];
            if (data) [data writeToURL:[staging URLByAppendingPathComponent:@"Contents/Resources/Playlist.plist"] options:NSDataWritingAtomic error:&failure];
        }
        if (!failure) {
            NSURL *infoURL = [staging URLByAppendingPathComponent:@"Contents/Info.plist"];
            NSMutableDictionary *info = [[NSDictionary dictionaryWithContentsOfURL:infoURL] mutableCopy];
            info[@"CFBundleName"] = name;
            info[@"CFBundleDisplayName"] = name;
            // Stable across exports, so rebuilding the same name updates the same saver.
            NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
            const unsigned char *bytes = nameData.bytes;
            uint64_t hash = 14695981039346656037ULL;
            for (NSUInteger i = 0; i < nameData.length; i++) { hash ^= bytes[i]; hash *= 1099511628211ULL; }
            info[@"CFBundleIdentifier"] = [NSString stringWithFormat:@"local.videosavermaker.saver.s%016llx", (unsigned long long)hash];
            // Every exported saver needs its own Objective-C class. System Settings
            // may load several savers into one process while switching previews.
            NSString *className = [NSString stringWithFormat:@"VSMVideoScreenSaver_%016llx", (unsigned long long)hash];
            NSData *oldClass = [@"VSMVideoScreenSaver_0000000000000000" dataUsingEncoding:NSUTF8StringEncoding];
            NSData *newClass = [className dataUsingEncoding:NSUTF8StringEncoding];
            NSURL *binaryURL = [staging URLByAppendingPathComponent:@"Contents/MacOS/VideoSaver"];
            NSMutableData *binary = [[NSData dataWithContentsOfURL:binaryURL options:0 error:&failure] mutableCopy];
            NSUInteger replacements = 0, offset = 0;
            while (binary && offset < binary.length) {
                NSRange found = [binary rangeOfData:oldClass options:0 range:NSMakeRange(offset,binary.length-offset)];
                if (found.location == NSNotFound) break;
                [binary replaceBytesInRange:found withBytes:newClass.bytes length:newClass.length];
                offset = NSMaxRange(found); replacements++;
            }
            if (!failure && !replacements) failure = [self error:@"內建屏保引擎不完整，請重新建置程式。"];
            if (!failure) [binary writeToURL:binaryURL options:NSDataWritingAtomic error:&failure];
            info[@"NSPrincipalClass"] = className;
            NSData *data = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0 options:0 error:&failure];
            if (data && !failure) [data writeToURL:infoURL options:NSDataWritingAtomic error:&failure];
        }
        if (!failure) {
            NSTask *task = [[NSTask alloc] init];
            task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/codesign"];
            task.arguments = @[@"--force", @"--sign", @"-", @"--timestamp=none", staging.path];
            NSPipe *pipe = [NSPipe pipe];
            task.standardError = pipe;
            if ([task launchAndReturnError:&failure]) {
                NSData *output = [pipe.fileHandleForReading readDataToEndOfFile];
                [task waitUntilExit];
                if (task.terminationStatus) failure = [self error:[NSString stringWithFormat:@"屏保簽章失敗：%@", [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding]]];
            }
        }
        if (!failure && [fm moveItemAtURL:staging toURL:destination error:&failure]) result = destination;
    } @catch (NSException *exception) {
        failure = [self error:exception.reason ?: @"輸出失敗。"];
    } @finally {
        if (!result) [fm removeItemAtURL:staging error:nil];
    }
    if (!result && error) *error = failure ?: [self error:@"無法輸出屏保。"];
    return result;
}
@end
