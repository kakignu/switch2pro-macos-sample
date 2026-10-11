#import "USBBulk.h"
#import <IOUSBHost/IOUSBHost.h>

static const NSUInteger kPacketSize = 64;   // wMaxPacketSize of the bulk endpoints

@implementation USBBulkInterface {
    IOUSBHostInterface *_interface;
    IOUSBHostPipe *_outPipe;
    IOUSBHostPipe *_inPipe;
}

- (nullable instancetype)initWithService:(io_service_t)service
                             outEndpoint:(uint8_t)outEP
                              inEndpoint:(uint8_t)inEP
                                   error:(NSError **)error {
    self = [super init];
    if (!self) { return nil; }

    // Succeeds only if no kernel/system driver has claimed this interface.
    _interface = [[IOUSBHostInterface alloc] initWithIOService:service
                                                       options:IOUSBHostObjectInitOptionsNone
                                                         queue:nil
                                                         error:error
                                               interestHandler:nil];
    if (!_interface) { return nil; }

    _outPipe = [_interface copyPipeWithAddress:outEP error:error];
    if (!_outPipe) { [self close]; return nil; }
    _inPipe = [_interface copyPipeWithAddress:inEP error:error];
    if (!_inPipe) { [self close]; return nil; }
    return self;
}

- (nullable NSData *)sendCommand:(NSData *)command
               maxResponseLength:(NSUInteger)maxResponseLength
                         timeout:(NSTimeInterval)timeout
                           error:(NSError **)error {
    if (!_outPipe || !_inPipe) {
        if (error) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENODEV userInfo:nil]; }
        return nil;
    }
    NSMutableData *outData = [command mutableCopy];
    NSUInteger sent = 0;
    if (![_outPipe sendIORequestWithData:outData bytesTransferred:&sent completionTimeout:1.0 error:error]) {
        return nil;
    }

    NSMutableData *response = [NSMutableData data];
    while (response.length < maxResponseLength) {
        // Bulk IN requests should be a multiple of wMaxPacketSize.
        NSMutableData *chunk = [NSMutableData dataWithLength:kPacketSize];
        NSUInteger got = 0;
        if (![_inPipe sendIORequestWithData:chunk bytesTransferred:&got completionTimeout:timeout error:nil]) {
            break;  // timeout / no response
        }
        [response appendBytes:chunk.bytes length:got];
        if (got < kPacketSize) { break; }  // short packet = end of transfer
    }
    return response;
}

- (void)close {
    _inPipe = nil;
    _outPipe = nil;
    if (_interface) { [_interface destroy]; }
    _interface = nil;
}

- (void)dealloc { [self close]; }

@end
