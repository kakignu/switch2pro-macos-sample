// USBBulk — minimal IOUSBHost wrapper: open an IOUSBHostInterface and talk to
// its bulk OUT / bulk IN endpoints.
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>

NS_ASSUME_NONNULL_BEGIN

@interface USBBulkInterface : NSObject

/// Opens the IOUSBHostInterface for `service` and its two bulk pipes.
- (nullable instancetype)initWithService:(io_service_t)service
                             outEndpoint:(uint8_t)outEP
                              inEndpoint:(uint8_t)inEP
                                   error:(NSError **)error;

/// Writes `command` to the OUT pipe, then reads the IN pipe until a short
/// packet, a timeout, or `maxResponseLength` bytes.
- (nullable NSData *)sendCommand:(NSData *)command
               maxResponseLength:(NSUInteger)maxResponseLength
                         timeout:(NSTimeInterval)timeout
                           error:(NSError **)error;

- (void)close;

@end

NS_ASSUME_NONNULL_END
