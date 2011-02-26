//
//  signals.m
//  hydna-objc
//

#import "Stream.h"
#import "StreamSignal.h"

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
    
    Stream *stream = [[ Stream alloc ] init ];
    [ stream connect:@"localhost/x00112233" mode:READWRITE_EMIT token:nil ];
    
    while (![ stream isConnected ]) {
        [ stream checkForStreamError ];
        sleep(1);
    }
    
    [ stream emitString:@"ping" ];
    
    for (;;) {
        if (![ stream isSignalEmpty ]) {
            StreamSignal* signal = [ stream popSignal ];
            NSData *payload = [ signal content ];
            
            NSString *message = [[ NSString alloc ] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [ message UTF8String ]);
            
            [ message release ];
            break;
        } else {
            [ stream checkForStreamError ];
        }
    }
    
    [ stream close ];
    [ stream release ];
    [ pool release ];
}
