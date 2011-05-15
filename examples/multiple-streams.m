//
//  multiple-streams.m
//  hydna-objc
//

#import "Stream.h"
#import "StreamData.h"

int main(int argc, const char* argv[])
{
    NSAutoreleasePool *pool = [[ NSAutoreleasePool alloc ] init ];
    
    Stream *stream = [[ Stream alloc ] init ];
    [ stream connect:@"localhost/x11221133" mode:READWRITE token:nil ];
    
	Stream *stream2 = [[ Stream alloc ] init ];
    [ stream2 connect:@"localhost/x3333" mode:READWRITE token:nil ];
	
    while (![ stream isConnected ]) {
        [ stream checkForStreamError ];
        sleep(1);
    }
	
	while (![ stream2 isConnected ]) {
        [ stream2 checkForStreamError ];
        sleep(1);
    }
    
    [ stream writeString:@"Hello" ];
	[ stream2 writeString:@"World" ];
    
    for (;;) {
        if (![ stream isDataEmpty ]) {
            StreamData* data = [ stream popData ];
            NSData *payload = [ data content ];
            
            NSString *message = [[ NSString alloc ] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [ message UTF8String ]);
            
            [ message release ];
            break;
        } else {
            [ stream checkForStreamError ];
        }
    }
	
	for (;;) {
        if (![ stream2 isDataEmpty ]) {
            StreamData* data = [ stream2 popData ];
            NSData *payload = [ data content ];
            
            NSString *message = [[ NSString alloc ] initWithData:payload encoding:NSUTF8StringEncoding];
            printf("%s\n", [ message UTF8String ]);
            
            [ message release ];
            break;
        } else {
            [ stream2 checkForStreamError ];
        }
    }
    
    [ stream close ];
    [ stream release ];
    [ stream2 close ];
    [ stream2 release ];
    [ pool release ];
}