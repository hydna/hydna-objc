//
//  Stream.m
//  hydna-objc
//

#import "Stream.h"

@implementation Stream

- (id) init
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self->m_host = @"";
    self->m_port = 7010;
    self->m_ch = 0;
    self->m_socket = nil;
    self->m_connected = NO;
    self->m_pendingClose = NO;
    self->m_readable = NO;
    self->m_writable = NO;
    self->m_emitable = NO;
    self->m_error = @"";
    self->m_openRequest = nil;
    
    self->m_dataQueue = [[ NSMutableArray alloc ] init ];
    self->m_signalQueue = [[ NSMutableArray alloc ] init ];
    
    self->m_dataMutex = [[ NSLock alloc ] init ];
    self->m_signalMutex = [[ NSLock alloc ] init ];
    
    return self;
}

- (void) dealloc
{
    [ m_dataQueue release ];
    [ m_dataMutex release ];
    [ m_signalQueue release ];
    [ m_signalMutex release ];
    
    [ super dealloc ];
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

- (NSUInteger) getChannel
{
    [ m_connectMutex lock ];
    NSUInteger result = m_ch;
    [ m_connectMutex unlock ];
    return result;
}

- (void) connect:(NSString *)expr mode:(NSUInteger)mode token:(NSData *)token
{
    Packet* packet;
    OpenRequest* request;
    
    [ m_connectMutex lock ];
    if (m_socket) {
        [ m_connectMutex unlock ];
        [NSException raise:@"Error" format:@"Already connected"];
    }
    [ m_connectMutex unlock ];
    
    if (mode == 0x04 || mode < READ || mode > READWRITEEMIT) {
        [NSException raise:@"Error" format:@"Invalid stream mode"];
    }
    
    if (!expr) {
        [NSException raise:@"Error" format:@"No channel to connect to"];
    }
    
    m_mode = mode;
    
    m_readable = ((m_mode & READ) == READ);
    m_writable = ((m_mode & WRITE) == WRITE);
    m_emitable = ((m_mode & EMIT) == EMIT);
    
    NSString *host = expr;
    NSUInteger port = 7010;
    NSUInteger ch = 1;
    NSString *tokens = @"";
    NSRange pos;
    
    pos = [ host rangeOfString:@"?" ];
    if (pos.length != 0) {
        tokens = [ host substringFromIndex:pos.location + 1];
        host = [ host substringToIndex:pos.location ];
    }
    
    pos = [ host rangeOfString:@"/x" ];
    if (pos.length != 0) {
        unsigned int addri;
        NSString* addrs = [ host substringFromIndex:pos.location + 2];
        host = [ host substringToIndex:pos.location ];
        
        BOOL result = [[NSScanner scannerWithString:addrs] scanHexInt:&addri];
        
        if (!result) {
            [NSException raise:@"Error" format:@"Could not read the channel \"%@\"", addrs];
        } else {
            ch = addri;
        }

    } else {
        pos = [ host rangeOfString:@"/" ];
        if (pos.length != 0) {
            ch = [[ host substringFromIndex:pos.location + 1] integerValue];
            host = [ host substringToIndex:pos.location ];
        }
    }
    
    pos = [ host rangeOfString:@":" ];
    if (pos.length != 0) {
        port = [[ host substringFromIndex:pos.location + 1] integerValue];
        host = [ host substringToIndex:pos.location ];
    }
    
    m_host = host;
    m_port = port;
    m_ch = ch;
    
    m_socket = [ExtSocket getSocketWithHost:m_host port:m_port];
    
    [ m_socket allocStream ];
    
    if (token || tokens == @"") {
        packet = [[ Packet alloc ] initWithChannel:m_ch op:OPEN flag:mode payload:token];
    } else {
        packet = [[ Packet alloc ] initWithChannel:m_ch op:OPEN flag:mode payload:[ tokens dataUsingEncoding:NSUTF8StringEncoding]];
    }

    request = [[ OpenRequest alloc ] initWith:self ch:m_ch packet:packet ];
    
    if (m_error != @"") {
        [ m_error release ];
    }
    
    m_error = @"";
    
    if (![ m_socket requestOpen:request ]) {
        [ self checkForStreamError ];
        [NSException raise:@"Error" format:@"Stream already open"];
    }
    
    m_openRequest = request;
}

- (void) writeBytes:(NSData *)data priority:(NSUInteger)priority
{
    BOOL result;
    
    [ m_connectMutex lock ];
    if (!m_connected || !m_socket) {
        [ m_connectMutex unlock ];
        [ self checkForStreamError ];
        [NSException raise:@"IOError" format:@"Stream is not conected" ];
    }
    [ m_connectMutex unlock ];
    
    if (!m_writable) {
        [NSException raise:@"Error" format:@"Stream is not writable" ];
    }
    
    if (priority > 3 || priority == 0) {
        [NSException raise:@"RangeError" format:@"Priority must be between 1-3" ];
    }
    
    Packet* packet = [[ Packet alloc ] initWithChannel:m_ch op:DATA flag:priority payload:data];
    
    [ m_connectMutex lock ];
    ExtSocket *socket = m_socket;
    [ m_connectMutex unlock ];
    result = [ socket writeBytes:packet ];
    
    if (!result) {
        [ self checkForStreamError ];
    }
}

- (void) writeBytes:(NSData *)data
{
    [ self writeBytes:data priority:1 ];
}

- (void) writeString:(NSString *)string
{
    [ self writeBytes:[string dataUsingEncoding:NSUTF8StringEncoding] ];
}

- (void) emitBytes:(NSData *)data type:(NSUInteger)type
{
    BOOL result;
    
    [ m_connectMutex lock ];
    if (!m_connected || !m_socket) {
        [ m_connectMutex unlock ];
        [ self checkForStreamError ];
        [NSException raise:@"IOError" format:@"Stream is not connected"];
    }
    [ m_connectMutex unlock ];
    
    if (!m_emitable) {
        [NSException raise:@"Error" format:@"You do not have permission to send signals" ];
    }
    
    Packet* packet = [[ Packet alloc ] initWithChannel:m_ch op:SIGNAL flag:type payload:data ];
    
    [ m_connectMutex lock ];
    ExtSocket *socket = m_socket;
    [ m_connectMutex unlock ];
    result = [ socket writeBytes:packet ];
    
    if (!result) {
        [ self checkForStreamError ];
    }
}

- (void) emitBytes:(NSData *)data
{
    [ self emitBytes:data type:0 ];
}

- (void) emitString:(NSString *)string type:(NSUInteger)type
{
    [ self emitBytes:[string dataUsingEncoding:NSUTF8StringEncoding] type:type ];
}

- (void) emitString:(NSString *)string
{
    [ self emitBytes:[string dataUsingEncoding:NSUTF8StringEncoding] ];
}

- (void) close
{
	Packet *packet;
	
    [ m_connectMutex lock ];
    if (!m_socket || m_closing) {
        [ m_connectMutex unlock ];
        return;
    }
	
	m_closing = YES;
	m_readable = NO;
	m_writable = NO;
	m_emitable = NO;
    
    if (m_openRequest && [ m_socket cancelOpen:m_openRequest ]) {
		// Open request hasn't been posted yet, which means that it's
		// safe to destroy stream immediately.

		m_openRequest = nil;
		[ m_connectMutex unlock ];
		
		[ self destroy:@"" ];
		return;
	}
	
	packet = [[ Packet alloc ] initWithChannel:m_ch op:SIGNAL flag:SIG_END payload:nil ];
	
	if (m_openRequest) {
		// Open request is not responded to yet. Wait to send ENDSIG until
		// we get an OPENRESP.
		
		m_pendingClose = packet;
		[ m_connectMutex unlock ];
	} else {
		[ m_connectMutex unlock ];
		
		
		@try {
#ifdef HYDNADEBUG
			NSLog(@"Stream: Sending close signal");	
#endif
			
			[ m_connectMutex lock ];
			ExtSocket *socket = m_socket;
			[ m_connectMutex unlock ];
			
			[ socket writeBytes:packet ];
			[ packet release ];
		}
		@catch (NSException *e) {
			[ m_connectMutex unlock ];
			[ packet release ];
			[ self destroy: [ e reason ] ];
		}
    }
}

- (void) openSuccess:(NSUInteger)respch
{
    [ m_connectMutex lock ];
	NSUInteger origch = m_ch;
	Packet *packet;
	
	m_openRequest = nil;
    m_ch = respch;
    m_connected = YES;
    
    if (m_pendingClose) {
		packet = m_pendingClose;
		m_pendingClose = nil;
		
        [ m_connectMutex unlock ];
        
		if (origch != respch) {
			// channel is changed. We need to change the channel of the
			//packet before sending to serv
			
			[ packet setChannel:respch ];
		}
		
		@try {
#ifdef HYDNADEBUG
			NSLog(@"Stream: Sending close signal");	
#endif
			
			[ m_connectMutex lock ];
			ExtSocket *socket = m_socket;
			[ m_connectMutex unlock ];
			
			[ socket writeBytes:packet ];
			[ packet release ];
		}
		@catch (NSException *e) {
			// Something wen't terrible wrong. Queue packet and wait
			// for a reconnect.
			
			[ m_connectMutex unlock ];
			[ packet release ];
			[ self destroy: [ e reason ] ];
		}
    } else {
        [ m_connectMutex unlock ];
    }

}

- (void) checkForStreamError
{
    [ m_connectMutex lock ];
    if (m_error != @"") {
        [ m_connectMutex unlock ];
        [NSException raise:@"StreamError" format:@"%@", m_error];
    } else {
        [ m_connectMutex unlock ];
    }
}

- (void) destroy:(NSString*)error
{
    [ m_connectMutex lock ];
	ExtSocket *socket = m_socket;
	BOOL connected = m_connected;
	NSUInteger ch = m_ch;
    
	m_ch = 0;
	m_connected = NO;
    m_writable = NO;
    m_readable = NO;
	m_pendingClose = nil;
	m_closing = NO;
	m_openRequest = nil;
	m_socket = nil;
    
    if (socket) {
        [ socket deallocStream:connected ? ch : 0 ];
    }
    
    m_error = [ error copy ];
    
    [ m_connectMutex unlock ];
}

- (void) addData:(StreamData*)data
{
    [ m_dataMutex lock ];
    [ m_dataQueue addObject:data ];
    [ m_dataMutex unlock ];
}

- (StreamData*) popData
{
    
    if ([ self isDataEmpty ])
        return nil;
    
    [ m_dataMutex lock ];
    
    StreamData* result = [ m_dataQueue objectAtIndex:0 ];
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

- (void) addSignal:(StreamSignal*)signal
{
    [ m_signalMutex lock ];
    [ m_signalQueue addObject:signal ];
    [ m_signalMutex unlock ];
}

- (StreamSignal*) popSignal
{
    
    if ([ self isSignalEmpty ])
        return nil;
    
    [ m_signalMutex lock ];
    
    StreamSignal* result = [ m_signalQueue objectAtIndex:0 ];
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
