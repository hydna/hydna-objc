//
//  Channel.m
//  hydna-objc
//

#import "HYChannel.h"
#import "HYURL.h"

#ifdef HYDNADEBUG
#import "DebugHelper.h"
#endif

@interface HYChannel ()

@property(nonatomic) NSUInteger m_ch;
@property(nonatomic, strong) NSString *m_path;
@property(nonatomic, strong) NSString *m_token;
@property(nonatomic, strong) NSString *m_message;

@property(nonatomic, strong) HYConnection *m_connection;

@property(nonatomic) BOOL m_connected;
@property(nonatomic) BOOL m_closing;
@property(nonatomic, strong) HYFrame *m_pendingClose;
@property(nonatomic) BOOL m_readable;
@property(nonatomic) BOOL m_writable;
@property(nonatomic) BOOL m_emitable;
@property(nonatomic) BOOL m_resolved;

@property(nonatomic, strong) NSString *m_error;

@property(nonatomic) NSUInteger m_mode;

@property(nonatomic, strong) HYOpenRequest *m_openRequest;
@property(nonatomic, strong) HYOpenRequest *m_resolveRequest;

@property(nonatomic, strong) NSMutableArray *m_dataQueue;
@property(nonatomic, strong) NSMutableArray *m_signalQueue;

@property(nonatomic, strong) NSLock *m_dataMutex;
@property(nonatomic, strong) NSLock *m_signalMutex;
@property(nonatomic, strong) NSLock *m_connectMutex;

@end

@implementation HYChannel

- (id)init
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self.m_ch = 0;
    self.m_message = @"";
    self.m_connection = nil;
    self.m_connected = NO;
    self.m_pendingClose = NO;
    self.m_readable = NO;
    self.m_writable = NO;
    self.m_emitable = NO;
    self.m_resolved = NO;
    self.m_error = @"";
    self.m_openRequest = nil;
    self.m_resolveRequest = nil;
    
    self.m_dataQueue = [[NSMutableArray alloc] init];
    self.m_signalQueue = [[NSMutableArray alloc] init];
    
    self.m_dataMutex = [[NSLock alloc] init];
    self.m_signalMutex = [[NSLock alloc] init];
    
    return self;
}

- (void)dealloc
{
    [self.m_message release];
    [self.m_dataQueue release];
    [self.m_dataMutex release];
    [self.m_signalQueue release];
    [self.m_signalMutex release];
    
    [super dealloc];
}

- (BOOL)getFollowRedirects
{
    return [HYConnection getFollowRedirects];
}

- (void)setFollowRedirects:(BOOL)value
{
    [HYConnection setFollowRedirects:value];
}

- (BOOL)isConnected
{
    [self.m_connectMutex lock];
    BOOL result = self.m_connected;
    [self.m_connectMutex unlock];
    return result;
}

- (BOOL)isClosing
{
    [self.m_connectMutex lock];
    BOOL result = self.m_closing;
    [self.m_connectMutex unlock];
    return result;
}

- (BOOL)isReadable
{
    [self.m_connectMutex lock];
    BOOL result = self.m_connected && self.m_readable;
    [self.m_connectMutex unlock];
    return result;
}

- (BOOL)isWritable
{
    [self.m_connectMutex lock];
    BOOL result = self.m_connected && self.m_writable;
    [self.m_connectMutex unlock];
    return result;
}

- (BOOL)hasSignalSupport
{
    [self.m_connectMutex lock];
    BOOL result = self.m_connected && self.m_emitable;
    [self.m_connectMutex unlock];
    return result;
}

- (NSUInteger)channel
{
    [self.m_connectMutex lock];
    NSUInteger result = self.m_ch;
    [self.m_connectMutex unlock];
    return result;
}

- (NSString*)message
{
    [self.m_connectMutex lock];
    NSString *result = [NSString stringWithString:self.m_message];
    [self.m_connectMutex unlock];
    return result;    
}

- (void)connect:(NSString *)expr
           mode:(NSUInteger)mode
          token:(NSString *)token
{
    HYFrame *frame;
    HYOpenRequest *request;
    
    [self.m_connectMutex lock];
    if (self.m_connection) {
        [self.m_connectMutex unlock];
        [NSException raise:@"Error" format:@"Already connected"];
    }
    
    [self.m_connectMutex unlock];
    
    if (mode < LISTEN || mode > READWRITEEMIT) {
        [NSException raise:@"Error" format:@"Invalid channel mode"];
    }
    
    if (!expr) {
        [NSException raise:@"Error" format:@"No channel to connect to"];
    }
    
    self.m_mode = mode;
    
    self.m_readable = ((self.m_mode & READ) == READ);
    self.m_writable = ((self.m_mode & WRITE) == WRITE);
    self.m_emitable = ((self.m_mode & EMIT) == EMIT);
    
    HYURL* url = [[[HYURL alloc] initWithExpr:expr] autorelease];
    
    unichar slash = '/';
    
    if (![[url protocol] isEqualToString:@"http" ]) {
        if ([[url protocol] isEqualToString:@"https"]) {
            [NSException raise:@"Error" format:@"The protocol HTTPS is not supported"];
        } else {
            [NSException raise:@"Error" format:@"Unknown protocol, \"%@\"", [url protocol]];
        }
    }
    
    if (![[url error] isEqualToString:@""]) {
        [NSException raise:@"Error" format:@"%@", [url error]];
    }
    
    self.m_path = [NSString stringWithFormat:@"%@%@", @"/", [url path]];
    
    if (self.m_path.length == 0 || (self.m_path.length == 1 && [self.m_path characterAtIndex:0] != slash)) {
        self.m_path = @"/";
    }
    
    self.m_token = [url token];
    self.m_ch = RESOLVE_CHANNEL;
    
    self.m_connection = [HYConnection getConnectionWithHost:[url host] port:[url port] auth:[url auth]];
    
    [self.m_connection allocChannel];
    
    if (token || [self.m_token isEqualToString: @""]) {
        self.m_token = token;
    }
    
    frame = [[HYFrame alloc] initWithChannel:self.m_ch ctype:CTYPE_UTF8 op:RESOLVE flag:0 payload:[self.m_path dataUsingEncoding:NSUTF8StringEncoding]];

    request = [[HYOpenRequest alloc] initWith:self ch:self.m_ch path:self.m_path token:self.m_token frame:frame];
    
    if (![self.m_error isEqualToString: @""]) {
        [self.m_error release];
    }
    
    self.m_error = @"";
    
    // TODO: check this error msg
    if (![self.m_connection requestResolve:request]) {
        [self checkForChannelError];
        [NSException raise:@"IOError" format:@"Channel could not resolve"];
    }
    
    self.m_resolveRequest = request;
}

- (void)writeBytes:(NSData *)data
          priority:(NSUInteger)priority
             ctype:(NSUInteger)ctype
{
    BOOL result;
    
    [self.m_connectMutex lock];
    
    if (!self.m_connected || !self.m_connection) {
        [self.m_connectMutex unlock];
        [self checkForChannelError];
        [NSException raise:@"IOError" format:@"Channel is not connected"];
    }
    
    [self.m_connectMutex unlock];
    
    if (!self.m_writable) {
        [NSException raise:@"Error" format:@"Channel is not writable"];
    }
    
    if (priority > 3) {
        [NSException raise:@"RangeError" format:@"Priority must be between 0-3"];
    }
    
    HYFrame *frame = [[HYFrame alloc] initWithChannel:self.m_ch ctype:ctype op:DATA flag:priority payload:data];
    
    [self.m_connectMutex lock];
    HYConnection *connection = self.m_connection;
    [self.m_connectMutex unlock];
    result = [connection writeBytes:frame];
    
    if (!result) {
        [self checkForChannelError];
    }
}

- (void)writeBytes:(NSData *)data
             ctype:(NSUInteger)ctype
{
    [self writeBytes:data priority:0 ctype:ctype];
}

- (void)writeString:(NSString *)string
{
    [self writeBytes:[string dataUsingEncoding:NSUTF8StringEncoding] priority:0 ctype:CTYPE_UTF8];
}

- (void)writeString:(NSString *)string
           priority:(NSInteger)priority
{
    [self writeBytes:[string dataUsingEncoding:NSUTF8StringEncoding] priority:priority ctype:CTYPE_UTF8];
}

- (void)emitBytes:(NSData *)data
            ctype:(NSUInteger)ctype
{
    BOOL result;
    
    [self.m_connectMutex lock];
    
    if (!self.m_connected || !self.m_connection) {
        [self.m_connectMutex unlock];
        [self checkForChannelError];
        [NSException raise:@"IOError" format:@"Channel is not connected"];
    }
    
    [self.m_connectMutex unlock];
    
    if (!self.m_emitable) {
        [NSException raise:@"Error" format:@"You do not have permission to send signals"];
    }
    
    HYFrame *frame = [[HYFrame alloc] initWithChannel:self.m_ch ctype:ctype op:SIGNAL flag:SIG_EMIT payload:data];
    
    [self.m_connectMutex lock];
    HYConnection *connection = self.m_connection;
    [self.m_connectMutex unlock];
    result = [connection writeBytes:frame];
    
    if (!result) {
        [self checkForChannelError];
    }
}

- (void)emitString:(NSString *)string
{
    [self emitBytes:[string dataUsingEncoding:NSUTF8StringEncoding] ctype:CTYPE_UTF8];
}

- (void)close
{
    HYFrame *frame;
    
    [self.m_connectMutex lock];
    if (!self.m_connection || self.m_closing) {
        [self.m_connectMutex unlock];
        return;
    }
    
    self.m_closing = YES;
    self.m_readable = NO;
    self.m_writable = NO;
    self.m_emitable = NO;
    
    // TODO add control for resolve request
    
    if (self.m_openRequest && [self.m_connection cancelOpen:self.m_openRequest]) {
        // Open request hasn't been posted yet, which means that it's
        // safe to destroy channel immediately.
        self.m_openRequest = nil;
        [self.m_connectMutex unlock];
        
        [self destroy:nil];
        return;
    }
    
    frame = [[HYFrame alloc] initWithChannel:self.m_ch ctype:CTYPE_UTF8 op:SIGNAL flag:SIG_END payload:nil];
    
    if (self.m_openRequest) {
        // Open request is not responded to yet. Wait to send ENDSIG until
        // we get an OPENRESP.
        
        self.m_pendingClose = frame;
        [self.m_connectMutex unlock];
    } else {
        [self.m_connectMutex unlock];
        
        @try {
#ifdef HYDNADEBUG
            debugPrint(@"Connection", self.m_ch, @"Sending close signal");
#endif
            
            [self.m_connectMutex lock];
            HYConnection *connection = self.m_connection;
            [self.m_connectMutex unlock];
            
            [connection writeBytes:frame];
            [frame release];
        }
        @catch (NSException *e) {
            [self.m_connectMutex unlock];
            [frame release];
            [self destroy:[HYChannelError errorWithDesc:[e reason] wasClean:NO hadError:YES wasDenied:NO]];
        }
    }
}

- (void)resolveSuccess:(NSUInteger)respch
                  path:(NSString *)path
                 token:(NSString *)token
{
    
    if(self.m_resolved == YES){
        [NSException raise:@"Error" format:@"Channel is already resolved"];
    }

    HYFrame *frame;
    HYOpenRequest *request;

    self.m_ch = respch;
        
    frame = [[HYFrame alloc] initWithChannel:self.m_ch ctype:0 op:OPEN flag:self.m_mode payload:[token dataUsingEncoding:NSUTF8StringEncoding]];
    
    request = [[HYOpenRequest alloc] initWith:self ch:self.m_ch path:path token:token frame:frame];

    if (![self.m_connection requestOpen:request]) {
        [NSException raise:@"Error" format:@"Channel already open"];
    }

    self.m_openRequest = request;

    self.m_resolved = YES;
}

- (void)openSuccess:(NSUInteger)respch
            message:(NSString *)message
{
    [self.m_connectMutex lock];
    NSUInteger origch = self.m_ch;
    HYFrame *frame;
    
    self.m_openRequest = nil;
    self.m_ch = respch;
    self.m_connected = YES;
    self.m_message = message;
    
    if (self.m_pendingClose) {
        frame = self.m_pendingClose;
        self.m_pendingClose = nil;
        
        [self.m_connectMutex unlock];
        
        if (origch != respch) {
            // channel is changed. We need to change the channel of the
            //frame before sending to server
            
            [frame setChannel:respch];
        }
        
        @try {
#ifdef HYDNADEBUG
            debugPrint(@"Connection", self.m_ch, @"Sending close signal");
#endif
            
            [self.m_connectMutex lock];
            HYConnection *connection = self.m_connection;
            [self.m_connectMutex unlock];
            
            [connection writeBytes:frame];
            [frame release];
        }
        @catch (NSException *e) {
            // Something wen't terrible wrong. Queue frame and wait
            // for a reconnect.
            
            [self.m_connectMutex unlock];
            [frame release];
            [self destroy:[HYChannelError errorWithDesc:[e reason] wasClean:NO hadError:YES wasDenied:NO]];
        }
    } else {
        
        // TODO: validate
        if (self.delegate && [self.delegate respondsToSelector:@selector(channelOpen:message:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate channelOpen:self message:message];
            });
        }
        
        [self.m_connectMutex unlock];
    }

}

- (void)checkForChannelError
{
    [self.m_connectMutex lock];
    if (![self.m_error isEqualToString: @""]) {
        [self.m_connectMutex unlock];
        [NSException raise:@"ChannelError" format:@"%@", self.m_error];
    } else {
        [self.m_connectMutex unlock];
    }
}

- (void)destroy:(HYChannelError *)error
{
    [self.m_connectMutex lock];
    HYConnection *connection = self.m_connection;
    BOOL connected = self.m_connected;
    NSUInteger ch = self.m_ch;
    
    self.m_ch = 0;
    self.m_connected = NO;
    self.m_writable = NO;
    self.m_readable = NO;
    self.m_pendingClose = nil;
    self.m_closing = NO;
    self.m_openRequest = nil;
    self.m_resolveRequest = nil;
    self.m_resolved = NO;
    self.m_connection = nil;
    
    if (connection) {
        [connection deallocChannel:connected ? ch : 0];
    }
    
    if (error) {
        self.m_error = [error.reason copy];
    }
    
    
    [self.m_connectMutex unlock];
    
    // TODO: test if no error
    
    if (error) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(channelClose:error:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate channelClose:self error:error];
            });
        }
    }
}

- (void)addData:(HYChannelData *)data
{
    // TODO: validate
    if (self.delegate && [self.delegate respondsToSelector:@selector(channelMessage:data:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate channelMessage:self data:data];
        });
    } else {
        [self.m_dataMutex lock];
        [self.m_dataQueue addObject:data];
        [self.m_dataMutex unlock];
    }

}

- (HYChannelData *)popData
{
    if ([self isDataEmpty]) {
        return nil;
    }
    
    [self.m_dataMutex lock];
    
    HYChannelData *result = [self.m_dataQueue objectAtIndex:0];
    [self.m_dataQueue removeObjectAtIndex:0];
    
    [self.m_dataMutex unlock];
    
    return result;    
}

- (BOOL)isDataEmpty
{
    [self.m_dataMutex lock];
    BOOL result = [self.m_dataQueue count] == 0;
    [self.m_dataMutex unlock];
    return result;
}

- (void)addSignal:(HYChannelSignal *)signal
{
    // TODO: validate
    if (self.delegate && [self.delegate respondsToSelector:@selector(channelSignal:data:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate channelSignal:self data:signal];
        });
    } else {
        [self.m_signalMutex lock];
        [self.m_signalQueue addObject:signal];
        [self.m_signalMutex unlock];
    }
}

- (HYChannelSignal *)popSignal
{
    if ([self isSignalEmpty]){
        return nil;
    }
    
    [self.m_signalMutex lock];
    
    HYChannelSignal *result = [self.m_signalQueue objectAtIndex:0];
    [self.m_signalQueue removeObjectAtIndex:0];
    
    [self.m_signalMutex unlock];
    
    return result;
}

- (BOOL)isSignalEmpty
{
    [self.m_signalMutex lock];
    BOOL result = [self.m_signalQueue count] == 0;
    [self.m_signalMutex unlock];
    return result;
}

@end