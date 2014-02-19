# hydna-objc

Hydna bindings for Objective-C.

## Usage

Import:

    #import "HYChannel.h"

Implement the following optional **<HYChannelDelegate>** methods:

    - (void)channelOpen:(HYChannel *)sender message:(NSString *)message;

    - (void)channelClose:(HYChannel *)sender error:(HYChannelError *)error;

    - (void)channelMessage:(HYChannel *)sender data:(HYChannelData *)data;

    - (void)channelSignal:(HYChannel *)sender data:(HYChannelSignal)data;

Opening a channel:

    HYChannel * channel = [[HYChannel alloc] init];
    [channel setDelegate:self];
    @try {
        [self.channel connect:@"yourdomain.hydna.net" mode:READWRITEEMIT token:@"optionaltoken"];
    }
    @catch (NSException *exception) {
        NSLog(@"Error: %@", exception.reason);
    }

Sending some data:
    
    [channel writeString:@"Hello World"];

Sending a signal:

    [channel emotString:@"Hello Signal"];

Receiving data:
    
    - (void)channelMessage:(HYChannel *)sender data:(HYChannelData *)data
    {
        NSData *payload = [data content];

        if ([data isUtf8Content]) {
            NSString *message = [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding];
            NSLog(@"%@", message);
            
        } else {
            NSLog(@"Binary data received");
        }
    }

## Installation

For convenient install please user our CocoaPod:

    pod "Hydna"

## Info

All the headers can be found in src/ with comments.

The examples are located in examples/.

