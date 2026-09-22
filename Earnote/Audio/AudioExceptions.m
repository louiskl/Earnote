#import "AudioExceptions.h"

BOOL EarnoteCatchException(void (NS_NOESCAPE ^block)(void), NSError *_Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *reason = exception.reason ?: exception.name;
            *error = [NSError errorWithDomain:@"Earnote.Audio"
                                         code:1
                                     userInfo:@{ NSLocalizedDescriptionKey: reason,
                                                 @"exception": exception.name }];
        }
        return NO;
    }
}
