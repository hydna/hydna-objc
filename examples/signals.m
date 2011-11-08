//
//  signals.m
//  hydna-objc
//

#import "Channel.h"
#import "ChannelSignal.h"

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
    
    Channel *channel = [[ Channel alloc ] init ];
    [ channel connect:@"localhost/x00112233" mode:READWRITEEMIT token:nil ];
    
    while (![ channel isConnected ]) {
        [ channel checkForChannelError ];
        sleep(1);
    }
    
    [ channel emitString:@"ping" ];
    
    for (;;) {
        if (![ channel isSignalEmpty ]) {
            ChannelSignal* signal = [ channel popSignal ];
            NSData *payload = [ signal content ];
            
            NSString *message = [[ NSString alloc ] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [ message UTF8String ]);
            
            [ message release ];
            break;
        } else {
            [ channel checkForChannelError ];
        }
    }
    
    [ channel close ];
    [ channel release ];
    [ pool release ];
}
