//
//  Channel.m
//  hydna-objc
//

#import "Channel.h"
#import "URL.h"

#ifdef HYDNADEBUG
#import "DebugHelper.h"
#endif

@implementation Channel

- (id) init
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_ch = 0;
	self->m_message = @"";
    self->m_connection = nil;
    self->m_connected = NO;
    self->m_pendingClose = NO;
    self->m_readable = NO;
    self->m_writable = NO;
    self->m_emitable = NO;
    self->m_resolved = NO;
    self->m_error = @"";
    self->m_openRequest = nil;
    self->m_resolveRequest = nil;
    
    self->m_dataQueue = [[ NSMutableArray alloc ] init ];
    self->m_signalQueue = [[ NSMutableArray alloc ] init ];
    
    self->m_dataMutex = [[ NSLock alloc ] init ];
    self->m_signalMutex = [[ NSLock alloc ] init ];
    
    return self;
}

- (void) dealloc
{
	[ m_message release ];
    [ m_dataQueue release ];
    [ m_dataMutex release ];
    [ m_signalQueue release ];
    [ m_signalMutex release ];
    
    [ super dealloc ];
}

- (BOOL) getFollowRedirects
{
	return [ Connection getFollowRedirects ];
}

- (void) setFollowRedirects:(BOOL)value
{
	[ Connection setFollowRedirects:value ];
}

- (BOOL) isConnected
{
    [ m_connectMutex lock ];
    BOOL result = m_connected;
    [ m_connectMutex unlock ];
    return result;
}

- (BOOL) isClosing
{
    [ m_connectMutex lock ];
    BOOL result = m_closing;
    [ m_connectMutex unlock ];
    return result;
}

- (BOOL) isReadable
{
    [ m_connectMutex lock ];
    BOOL result = m_connected && m_readable;
    [ m_connectMutex unlock ];
    return result;
}

- (BOOL) isWritable
{
    [ m_connectMutex lock ];
    BOOL result = m_connected && m_writable;
    [ m_connectMutex unlock ];
    return result;
}

- (BOOL) hasSignalSupport
{
    [ m_connectMutex lock ];
    BOOL result = m_connected && m_emitable;
    [ m_connectMutex unlock ];
    return result;
}

- (NSUInteger) channel
{
    [ m_connectMutex lock ];
    NSUInteger result = m_ch;
    [ m_connectMutex unlock ];
    return result;
}

- (NSString*) message
{
    [ m_connectMutex lock ];
    NSString *result = [ NSString stringWithString:m_message ];
    [ m_connectMutex unlock ];
    return result;	
}

- (void) connect:(NSString *)expr mode:(NSUInteger)mode token:(NSData *)token
{
    Frame* frame;
    OpenRequest* request;
    
    [ m_connectMutex lock ];
    if (m_connection) {
        [ m_connectMutex unlock ];
        [NSException raise:@"Error" format:@"Already connected"];
    }
    [ m_connectMutex unlock ];
    
    if (mode == 0x04 || mode < READ || mode > READWRITEEMIT) {
        [NSException raise:@"Error" format:@"Invalid channel mode"];
    }
    
    if (!expr) {
        [NSException raise:@"Error" format:@"No channel to connect to"];
    }
    
    m_mode = mode;
    
    m_readable = ((m_mode & READ) == READ);
    m_writable = ((m_mode & WRITE) == WRITE);
    m_emitable = ((m_mode & EMIT) == EMIT);
    
	URL* url = [[[ URL alloc ] initWithExpr:expr ] autorelease ];
    
    unichar slash = '/';
	
	if (![[ url protocol ] isEqualToString:@"http" ]) {
		if ([[ url protocol ] isEqualToString:@"https" ]) {
			[NSException raise:@"Error" format:@"The protocol HTTPS is not supported"];
		} else {
			[NSException raise:@"Error" format:@"Unknown protocol, \"%@\"", [ url protocol ]];
		}
	}
	
    if (![[ url error ] isEqualToString:@"" ]) {
        [NSException raise:@"Error" format:@"%@", [ url error ]];
    }
	
	m_path = [NSString stringWithFormat:@"%@%@", @"/", [url path]];
    
    if (m_path.length == 0 || (m_path.length == 1 && [m_path characterAtIndex:0] != slash)) {
        m_path = @"/";
    }
	
	m_token = [ url token ];
    m_ch = RESOLVE_CHANNEL;
    
    m_connection = [Connection getConnectionWithHost:[ url host ] port:[ url port ] auth:[ url auth ]];
    
    [ m_connection allocChannel ];
    
    if (token || [m_token isEqualToString: @""]) {
        m_token = [[NSString alloc] initWithData:token encoding:NSUTF8StringEncoding];
    }
    
    frame = [[ Frame alloc ] initWithChannel:m_ch ctype:CTYPE_UTF8 op:RESOLVE flag:0 payload:[ m_path dataUsingEncoding:NSUTF8StringEncoding]];

    request = [[ OpenRequest alloc ] initWith:self ch:m_ch path:m_path token:m_token frame:frame ];
    
    if (![m_error isEqualToString: @""]) {
        [ m_error release ];
    }
    
    m_error = @"";
    
    if (![ m_connection requestResolve:request ]) {
        [ self checkForChannelError ];
        [NSException raise:@"Error" format:@"Channel already open"];
    }
    
    m_resolveRequest = request;
}

- (void) writeBytes:(NSData *)data priority:(NSUInteger)priority ctype:(NSUInteger)ctype
{
    BOOL result;
    
    [ m_connectMutex lock ];
    if (!m_connected || !m_connection) {
        [ m_connectMutex unlock ];
        [ self checkForChannelError ];
        [NSException raise:@"IOError" format:@"Channel is not connected" ];
    }
    [ m_connectMutex unlock ];
    
    if (!m_writable) {
        [NSException raise:@"Error" format:@"Channel is not writable" ];
    }
    
    if (priority > 3) {
        [NSException raise:@"RangeError" format:@"Priority must be between 0-3" ];
    }
    
    Frame* frame = [[ Frame alloc ] initWithChannel:m_ch ctype:ctype op:DATA flag:priority payload:data];
    
    [ m_connectMutex lock ];
    Connection *connection = m_connection;
    [ m_connectMutex unlock ];
    result = [ connection writeBytes:frame ];
    
    if (!result) {
        [ self checkForChannelError ];
    }
}

- (void) writeBytes:(NSData *)data ctype:(NSUInteger)ctype
{
    [ self writeBytes:data priority:0 ctype:ctype ];
}

- (void) writeString:(NSString *)string
{
    [ self writeBytes:[string dataUsingEncoding:NSUTF8StringEncoding] priority:0 ctype:CTYPE_UTF8 ];
}

- (void) writeString:(NSString *)string priority:(NSInteger)priority
{
    [ self writeBytes:[string dataUsingEncoding:NSUTF8StringEncoding] priority:priority ctype:CTYPE_UTF8 ];
}

- (void) emitBytes:(NSData *)data ctype:(NSUInteger)ctype
{
    BOOL result;
    
    [ m_connectMutex lock ];
    if (!m_connected || !m_connection) {
        [ m_connectMutex unlock ];
        [ self checkForChannelError ];
        [NSException raise:@"IOError" format:@"Channel is not connected"];
    }
    [ m_connectMutex unlock ];
    
    if (!m_emitable) {
        [NSException raise:@"Error" format:@"You do not have permission to send signals" ];
    }
    
    Frame* frame = [[ Frame alloc ] initWithChannel:m_ch ctype:ctype op:SIGNAL flag:SIG_EMIT payload:data ];
    
    [ m_connectMutex lock ];
    Connection *connection = m_connection;
    [ m_connectMutex unlock ];
    result = [ connection writeBytes:frame ];
    
    if (!result) {
        [ self checkForChannelError ];
    }
}

- (void) emitString:(NSString *)string
{
    [ self emitBytes:[string dataUsingEncoding:NSUTF8StringEncoding] ctype:CTYPE_UTF8 ];
}

- (void) close
{
	Frame *frame;
	
    [ m_connectMutex lock ];
    if (!m_connection || m_closing) {
        [ m_connectMutex unlock ];
        return;
    }
	
	m_closing = YES;
	m_readable = NO;
	m_writable = NO;
	m_emitable = NO;
    
    // TODO add wait for resolve request
    
    if (m_openRequest && [ m_connection cancelOpen:m_openRequest ]) {
		// Open request hasn't been posted yet, which means that it's
		// safe to destroy channel immediately.

		m_openRequest = nil;
		[ m_connectMutex unlock ];
		
		[ self destroy:@"" ];
		return;
	}
	
	frame = [[ Frame alloc ] initWithChannel:m_ch ctype:0 op:SIGNAL flag:SIG_END payload:nil ];
	
	if (m_openRequest) {
		// Open request is not responded to yet. Wait to send ENDSIG until
		// we get an OPENRESP.
		
		m_pendingClose = frame;
		[ m_connectMutex unlock ];
	} else {
		[ m_connectMutex unlock ];
		
		
		@try {
#ifdef HYDNADEBUG
			debugPrint(@"Connection", m_ch, @"Sending close signal");
#endif
			
			[ m_connectMutex lock ];
			Connection *connection = m_connection;
			[ m_connectMutex unlock ];
			
			[ connection writeBytes:frame ];
			[ frame release ];
		}
		@catch (NSException *e) {
			[ m_connectMutex unlock ];
			[ frame release ];
			[ self destroy: [ e reason ] ];
		}
    }
}

- (void) resolveSuccess:(NSUInteger)respch path:(NSString*)path token:(NSString*)token
{
    
    if(m_resolved == YES){
        [NSException raise:@"Error" format:@"Channel is already resolved"];
    }

    Frame* frame;
    OpenRequest* request;

    m_ch = respch;
        
    frame = [[ Frame alloc ] initWithChannel:m_ch ctype:0 op:OPEN flag:m_mode payload:[token dataUsingEncoding:NSUTF8StringEncoding]];
    
    request = [[ OpenRequest alloc ] initWith:self ch:m_ch path:path token:token frame:frame ];

    if (![m_connection requestOpen:request]) {
        [NSException raise:@"Error" format:@"Channel already open"];
    }

    m_openRequest = request;

    m_resolved = YES;
}

- (void) openSuccess:(NSUInteger)respch message:(NSString*)message
{
    [ m_connectMutex lock ];
	NSUInteger origch = m_ch;
	Frame *frame;
	
	m_openRequest = nil;
    m_ch = respch;
    m_connected = YES;
	m_message = message;
    
    if (m_pendingClose) {
		frame = m_pendingClose;
		m_pendingClose = nil;
		
        [ m_connectMutex unlock ];
        
		if (origch != respch) {
			// channel is changed. We need to change the channel of the
			//frame before sending to serv
			
			[ frame setChannel:respch ];
		}
		
		@try {
#ifdef HYDNADEBUG
			debugPrint(@"Connection", m_ch, @"Sending close signal");
#endif
			
			[ m_connectMutex lock ];
			Connection *connection = m_connection;
			[ m_connectMutex unlock ];
			
			[ connection writeBytes:frame ];
			[ frame release ];
		}
		@catch (NSException *e) {
			// Something wen't terrible wrong. Queue frame and wait
			// for a reconnect.
			
			[ m_connectMutex unlock ];
			[ frame release ];
			[ self destroy: [ e reason ] ];
		}
    } else {
        [ m_connectMutex unlock ];
    }

}

- (void) checkForChannelError
{
    [ m_connectMutex lock ];
    if (![m_error isEqualToString: @""]) {
        [ m_connectMutex unlock ];
        [NSException raise:@"ChannelError" format:@"%@", m_error];
    } else {
        [ m_connectMutex unlock ];
    }
}

- (void) destroy:(NSString*)error
{
    [ m_connectMutex lock ];
	Connection *connection = m_connection;
	BOOL connected = m_connected;
	NSUInteger ch = m_ch;
    
	m_ch = 0;
	m_connected = NO;
    m_writable = NO;
    m_readable = NO;
	m_pendingClose = nil;
	m_closing = NO;
	m_openRequest = nil;
    m_resolveRequest = nil;
    m_resolved = NO;
	m_connection = nil;
    
    if (connection) {
        [ connection deallocChannel:connected ? ch : 0 ];
    }
    
    m_error = [ error copy ];
    
    [ m_connectMutex unlock ];
}

- (void) addData:(ChannelData*)data
{
    [ m_dataMutex lock ];
    [ m_dataQueue addObject:data ];
    [ m_dataMutex unlock ];
}

- (ChannelData*) popData
{
    
    if ([ self isDataEmpty ])
        return nil;
    
    [ m_dataMutex lock ];
    
    ChannelData* result = [ m_dataQueue objectAtIndex:0 ];
    [ m_dataQueue removeObjectAtIndex:0 ];
    
    [ m_dataMutex unlock ];
    return result;    
}

- (BOOL) isDataEmpty
{
    [ m_dataMutex lock ];
    BOOL result = [ m_dataQueue count ] == 0;
    [ m_dataMutex unlock ];
    return result;
}

- (void) addSignal:(ChannelSignal*)signal
{
    [ m_signalMutex lock ];
    [ m_signalQueue addObject:signal ];
    [ m_signalMutex unlock ];
}

- (ChannelSignal*) popSignal
{
    
    if ([ self isSignalEmpty ])
        return nil;
    
    [ m_signalMutex lock ];
    
    ChannelSignal* result = [ m_signalQueue objectAtIndex:0 ];
    [ m_signalQueue removeObjectAtIndex:0 ];
    
    [ m_signalMutex unlock ];
    return result;
}

- (BOOL) isSignalEmpty
{
    [ m_signalMutex lock ];
    BOOL result = [ m_signalQueue count ] == 0;
    [ m_signalMutex unlock ];
    return result;
}

@end
