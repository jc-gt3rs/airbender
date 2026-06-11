#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SMCWrapperObjC : NSObject

- (nullable instancetype)initWithError:(NSError **)error;

- (NSInteger)fanCount;
- (double)fanSpeedForIndex:(NSInteger)index;
- (double)fanMinSpeedForIndex:(NSInteger)index;
- (double)fanMaxSpeedForIndex:(NSInteger)index;

- (BOOL)setFanTargetSpeedForIndex:(NSInteger)index rpm:(double)rpm error:(NSError **)error NS_SWIFT_NAME(setFanTargetSpeed(index:rpm:));
- (BOOL)setManualMode:(BOOL)enabled fanCount:(NSInteger)fanCount error:(NSError **)error NS_SWIFT_NAME(setManualMode(enabled:fanCount:));

@end

NS_ASSUME_NONNULL_END
