#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface VSMSaverExporter : NSObject
+ (BOOL)isVideoURL:(NSURL *)url;
+ (nullable NSURL *)exportVideos:(NSArray<NSURL *> *)videos
                           name:(NSString *)name
                      directory:(NSURL *)directory
                        shuffle:(BOOL)shuffle
                            fit:(BOOL)fit
                          error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
