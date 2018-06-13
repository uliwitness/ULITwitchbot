//
//  ULIRCChatbot.m
//  ULITwitchbot
//
//  Created by Uli Kusterer on 12.03.18.
//  Copyright © 2018 Uli Kusterer. All rights reserved.
//

#import "ULIRCChatbot.h"
#import <CFNetwork/CFNetwork.h>


// Based on http://chi.cs.uchicago.edu/chirc/irc_examples.html and https://help.twitch.tv/customer/portal/articles/1302780-twitch-irc


#define IRC_PROTOCOL_MESSAGE_LENGTH_LIMIT	512


@interface ULIRCUserInfo : NSObject

@property (getter=isModerator) BOOL moderator;
@property (getter=isSubscriber) BOOL subscriber;
@property (getter=isTurbo) BOOL turbo;
@property (getter=isBroadcaster) BOOL broadcaster;
@property (getter=isPartner) BOOL partner;
@property (getter=isPrime) BOOL prime;
@property NSInteger bitBadgeAmount;
@property (copy) NSString *htmlColor;
@property (copy) NSString *displayName;

-(instancetype) initWithTags:(NSDictionary *)inTags;

@end

@interface ULIRCChatbot () <NSStreamDelegate>

@property NSInputStream * readStream;
@property NSOutputStream * writeStream;
@property NSMutableString * receivedText;

@property NSMutableDictionary<NSString *,ULIRCProtocolCommandHandler> * protocolCommands;
@property NSMutableDictionary<NSString *,ULIRCBotCommandHandler> * botCommands;

@property NSMutableDictionary<NSString *,NSNumber *> * counters;
@property NSMutableDictionary<NSString *,NSDate *> * lastCommandUseTimes;
@property NSDate *startupTime;
@property NSMutableDictionary<NSString *,ULIRCUserInfo *> * userInfos;

@property NSMutableArray<NSTimer *> * messageTimers;

@end


@implementation ULIRCChatbot

@synthesize settingsFolderURL = _settingsFolderURL;

-(instancetype) init
{
	self = [super init];
	if( self )
	{
		self.protocolCommands = [NSMutableDictionary new];
		self.botCommands = [NSMutableDictionary new];
		self.messageTimers = [NSMutableArray new];
		self.lastCommandUseTimes = [NSMutableDictionary new];
		self.userInfos = [NSMutableDictionary new];

		[self registerHandler:^(NSString *inCommandName, NSString *inNickname, NSArray<NSString *> *inParameters, NSString *inPrefix, NSDictionary *inTags)
		{
			NSLog(@"ANSWERING [%@] %@: %@ %@ %@", inPrefix, inNickname, inCommandName, inParameters, inTags);
			[self sendString:[NSString stringWithFormat: @"PONG %@", inParameters.firstObject ?: @""]];
		} forProtocolCommand: @"PING"];
	}
	
	return self;
}


-(void) dealloc
{
	[self.messageTimers makeObjectsPerformSelector:@selector(invalidate)];
}


-(void) setSettingsFolderURL: (NSURL *)settingsFolderURL
{
	_settingsFolderURL = settingsFolderURL;
	
	if( _settingsFolderURL )
	{
		NSURL * commandsFolderURL = [settingsFolderURL URLByAppendingPathComponent: @"Commands"];
		NSArray *commandDirectoryURLs = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:commandsFolderURL includingPropertiesForKeys:nil options: NSDirectoryEnumerationSkipsSubdirectoryDescendants | NSDirectoryEnumerationSkipsPackageDescendants | NSDirectoryEnumerationSkipsHiddenFiles error: NULL];
		for( NSURL * currCommandDirectory in commandDirectoryURLs )
		{
			[self loadCommandFromDirectory: currCommandDirectory];
		}
		
		NSURL * countersURL = [settingsFolderURL URLByAppendingPathComponent: @"Counters.plist"];
		self.counters = [([NSDictionary dictionaryWithContentsOfURL: countersURL error: NULL] ?: @{}) mutableCopy];
	}
}

-(NSURL *)settingsFolderURL
{
	return _settingsFolderURL;
}


-(void) loadCommandFromDirectory: (NSURL *)commandDirectory
{
	NSDictionary<NSString *,id> *commandInfo = [NSDictionary dictionaryWithContentsOfURL:[commandDirectory URLByAppendingPathComponent: @"Info.plist"] error: NULL];
	NSString * commandName = commandDirectory.lastPathComponent;
	NSString * commandType = commandInfo[@"ULIRCCommandType"];
	
	NSLog(@"Loading command %@", commandName);
	
	ULIRCChatbot * __weak weakSelf = self;
	if( [commandType.lowercaseString isEqualToString: @"counter"] )
	{
		NSString * msgFormat = commandInfo[@"ULIRCCommandMessage"] ?: @"%CHANNEL% has a %COMMANDNAME% count of %COUNT%.";
		msgFormat = [msgFormat stringByReplacingOccurrencesOfString:@"%COMMANDNAME%" withString:commandName];

		NSString * queryCommandName = commandInfo[@"ULIRCQueryCommandName"] ?: [commandName stringByAppendingString: @"count"];

		[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix, NSDictionary *inTags )
		 {
			 typeof(self) strongSelf = weakSelf;
			 if( strongSelf )
			 {
				 NSNumber * currentCount = [strongSelf.counters objectForKey: inCommandName.lowercaseString];
				 [strongSelf.counters setObject: [NSNumber numberWithInteger: currentCount.integerValue + 1] forKey: inCommandName.lowercaseString];
				 NSString * msg = [msgFormat stringByReplacingOccurrencesOfString:@"%COUNT%" withString:[NSString stringWithFormat: @"%ld", (long)currentCount.integerValue + 1]];
				 msg = [msg stringByReplacingOccurrencesOfString:@"%CHANNEL%" withString:self.channelName];
				 [strongSelf sendChatMessage: msg];

				 NSURL * countersURL = [strongSelf->_settingsFolderURL URLByAppendingPathComponent: @"Counters.plist"];
				 [self.counters writeToURL: countersURL error:NULL];
			 }
		 } forBotCommand: commandName];
		[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix, NSDictionary *inTags )
		 {
			 typeof(self) strongSelf = weakSelf;
			 if( strongSelf )
			 {
				 NSNumber * currentCount = [strongSelf.counters objectForKey: commandName.lowercaseString];
				 NSString * msg = [msgFormat stringByReplacingOccurrencesOfString:@"%COUNT%" withString:[NSString stringWithFormat: @"%ld", (long)currentCount.integerValue]];
				 msg = [msg stringByReplacingOccurrencesOfString:@"%CHANNEL%" withString:self.channelName];
				 [strongSelf sendChatMessage: msg];
			 }
		 } forBotCommand: queryCommandName];
	}
	else if( [commandType.lowercaseString isEqualToString: @"quote"] )
	{
		[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix, NSDictionary *inTags )
		 {
			 typeof(self) strongSelf = weakSelf;
			 if( strongSelf )
			 {
				 NSURL * quotesURL = [[strongSelf->_settingsFolderURL URLByAppendingPathComponent: @"Quotes"] URLByAppendingPathComponent: [NSString stringWithFormat: @"%@.txt", commandName]];
				 NSString * quotesData = [NSString stringWithContentsOfURL: quotesURL encoding: NSUTF8StringEncoding error: NULL];
				 NSArray * quotes = (quotesData.length > 0) ? [quotesData componentsSeparatedByString: @"\n"] : @[];
				 if( quotes.count > 0 )
				 {
					 NSInteger quoteIndex = (inMessage.length > 0) ? (inMessage.integerValue - 1) : (rand() % quotes.count);
					 if( quoteIndex < quotes.count )
					 {
						 NSString * quoteLine = [quotes objectAtIndex: quoteIndex];
						 [strongSelf sendChatMessage: [NSString stringWithFormat: @"%ld: %@", quoteIndex + 1, quoteLine]];
					 }
					 else
						 [strongSelf sendChatMessage: @"Not found."];
				 }
				 else
					 [strongSelf sendChatMessage: @"Not found."];
			 }
		 } forBotCommand: commandName];
		
		NSString * addCommandName = commandInfo[@"ULIRCAddCommandName"];
		if( addCommandName || [commandInfo[@"ULIRCEditable"] boolValue] )
		{
			if( !addCommandName )
				addCommandName = [@"add" stringByAppendingString:commandName];
			
			[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix, NSDictionary *inTags )
			 {
				 typeof(self) strongSelf = weakSelf;
				 if( strongSelf )
				 {
					 NSURL * quotesURL = [[strongSelf->_settingsFolderURL URLByAppendingPathComponent: @"Quotes"] URLByAppendingPathComponent: [NSString stringWithFormat: @"%@.txt", commandName]];
					 NSMutableString * quotesData = [NSMutableString stringWithContentsOfURL: quotesURL encoding: NSUTF8StringEncoding error: NULL];
					 if (!quotesData)
						 quotesData = [NSMutableString new];
					 inMessage = [inMessage stringByReplacingOccurrencesOfString:@"\r\n" withString: @" "];
					 inMessage = [inMessage stringByReplacingOccurrencesOfString:@"\r" withString: @" "];
					 inMessage = [inMessage stringByReplacingOccurrencesOfString:@"\n" withString: @" "];
					 if( quotesData.length > 0 )
						 [quotesData appendString: @"\n"];
					 [quotesData appendString: inMessage];
					 [quotesData writeToURL:quotesURL atomically:YES encoding:NSUTF8StringEncoding error:NULL];
					 [strongSelf sendChatMessage: @"Added."];
				 }
			 } forBotCommand: addCommandName];
		}
		NSString * dequeueCommandName = commandInfo[@"ULIRCDequeueCommandName"];
		if( dequeueCommandName )
		{
			if( !dequeueCommandName )
				dequeueCommandName = [@"dequeue" stringByAppendingString:commandName];
			
			[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix, NSDictionary *inTags )
			 {
				 typeof(self) strongSelf = weakSelf;
				 if( strongSelf )
				 {
					 NSURL * quotesURL = [[strongSelf->_settingsFolderURL URLByAppendingPathComponent: @"Quotes"] URLByAppendingPathComponent: [NSString stringWithFormat: @"%@.txt", commandName]];
					 NSMutableString * quotesData = [NSMutableString stringWithContentsOfURL: quotesURL encoding: NSUTF8StringEncoding error: NULL];
					 NSRange lineBreakRange = [quotesData rangeOfString: @"\n"];
					 if( lineBreakRange.location == NSNotFound )
					 {
						 lineBreakRange.location = quotesData.length;
						 lineBreakRange.length = 0;
					 }
					 NSRange firstLineRange = NSMakeRange(0, NSMaxRange(lineBreakRange));
					 [strongSelf sendChatMessage:[quotesData substringWithRange: firstLineRange]];
					 [quotesData deleteCharactersInRange:firstLineRange];
					 [quotesData writeToURL:quotesURL atomically:YES encoding:NSUTF8StringEncoding error:NULL];
				 }
			 } forBotCommand: dequeueCommandName];
		}
	}
	else if( [commandType.lowercaseString isEqualToString: @"message"] )
	{
		NSString * message = commandInfo[@"ULIRCMessage"];
		NSTimeInterval intervalBetweenMessages = [commandInfo[@"ULIRCInterval"] doubleValue];
		NSTimeInterval intervalBeforeMessages = [commandInfo[@"ULIRCInitialInterval"] doubleValue];
		BOOL quietMessage = [commandInfo[@"ULIRCQuietly"] boolValue];

		[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix, NSDictionary *inTags )
		 {
			 typeof(self) strongSelf = weakSelf;
			 if( strongSelf )
			 {
				 if( quietMessage )
				 {
					 [strongSelf processOneSelfSentChatMessage:[self stringByReplacingPlaceholders: message forCommand: commandName parameters: [inMessage componentsSeparatedByString:@" "]]];
				 }
				 else
				 {
					 [strongSelf sendChatMessage:[self stringByReplacingPlaceholders: message forCommand: commandName parameters: [inMessage componentsSeparatedByString:@" "]]];
				 }
			 }
		 } forBotCommand: commandName];
		
		if( intervalBetweenMessages > 0.0 || intervalBeforeMessages > 0.0 )
		{
			NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval:intervalBetweenMessages repeats:(intervalBetweenMessages > 0.0) block:^(NSTimer * _Nonnull timer)
			{
				typeof(self) strongSelf = weakSelf;
				if( strongSelf )
				{
					if( quietMessage )
					{
						[strongSelf processOneSelfSentChatMessage:[self stringByReplacingPlaceholders: message forCommand: commandName parameters: @[]]];
					}
					else
					{
						[strongSelf sendChatMessage:[self stringByReplacingPlaceholders: message forCommand: commandName parameters: @[]]];
					}
				}
			}];
			
			if( intervalBeforeMessages > 0.0 )
			{
				timer.fireDate = [NSDate dateWithTimeIntervalSinceNow:intervalBeforeMessages];
			}
			
			[self.messageTimers addObject:timer];
		}
	}
	else
	{
		NSLog(@"Failed to load command '%@', type '%@' unknown.", commandName, commandType);
	}
}


-(NSString *)stringByReplacingPlaceholders:(NSString *)inString forCommand:(NSString *)inCommandName parameters: (NSArray<NSString *> *)parameters
{
	NSMutableString * result = [inString mutableCopy];
	
	if( [result containsString:@"%COUNT%"] )
	{
		NSNumber * currentCount = [self.counters objectForKey: inCommandName.lowercaseString];
		NSNumber * newCount = [NSNumber numberWithInteger: currentCount.integerValue + 1];
		[self.counters setObject: newCount forKey: inCommandName.lowercaseString];

		[result replaceOccurrencesOfString:@"%COUNT%" withString:[NSString stringWithFormat:@"%@", newCount] options: 0 range:NSMakeRange(0, result.length)];
		
		NSURL * countersURL = [_settingsFolderURL URLByAppendingPathComponent: @"Counters.plist"];
		[self.counters writeToURL: countersURL error:NULL];
	}
	
	[result replaceOccurrencesOfString:@"%CHANNEL%" withString:self.channelName options: 0 range:NSMakeRange(0, result.length)];
	
	[result replaceOccurrencesOfString:@"%COMMANDNAME%" withString:inCommandName options: 0 range:NSMakeRange(0, result.length)];
	
	if( [result containsString:@"%LASTUSEINTERVAL%"] )
	{
		NSDate * lastUseTime = self.lastCommandUseTimes[inCommandName.lowercaseString];
		if( !lastUseTime )
		{
			lastUseTime = self.startupTime;
		}
		
		NSDateComponentsFormatter *componentFormatter = [NSDateComponentsFormatter new];
		
		componentFormatter.unitsStyle = NSDateComponentsFormatterUnitsStyleFull;
		componentFormatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorDropAll;
		
		NSString * formattedString = [componentFormatter stringFromTimeInterval:NSDate.timeIntervalSinceReferenceDate - lastUseTime.timeIntervalSinceReferenceDate];

		[result replaceOccurrencesOfString:@"%LASTUSEINTERVAL%" withString:formattedString options: 0 range:NSMakeRange(0, result.length)];
	}

	if( [result containsString:@"%LASTUSETIME%"] )
	{
		NSDate * lastUseTime = self.lastCommandUseTimes[inCommandName.lowercaseString];
		if( !lastUseTime )
		{
			lastUseTime = self.startupTime;
		}
		
		NSDateFormatter * dateFormatter = [NSDateFormatter new];
		dateFormatter.timeStyle = NSDateFormatterShortStyle;
		dateFormatter.dateStyle = NSDateFormatterShortStyle;
		NSString * formattedString = [dateFormatter stringFromDate:lastUseTime];

		[result replaceOccurrencesOfString:@"%LASTUSETIME%" withString:formattedString options: 0 range:NSMakeRange(0, result.length)];
	}
	
	for( NSInteger x = 1; x <= parameters.count; ++x )
	{
		NSString * currPlaceholder = [NSString stringWithFormat:@"%%%ld%%", (long)x];
		if( [result containsString:currPlaceholder] )
		{
			[result replaceOccurrencesOfString:currPlaceholder withString:parameters[x - 1] options: 0 range:NSMakeRange(0, result.length)];
		}
	}

	return result;
}


-(void) connectReturningError: (NSError **)outError
{
	self.receivedText = [NSMutableString string];
	
	CFReadStreamRef readStream = NULL;
	CFWriteStreamRef writeStream = NULL;
	
	CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, CFSTR("irc.chat.twitch.tv"), 6667, &readStream, &writeStream);
	
	self.readStream = (__bridge_transfer NSInputStream *)readStream;
	self.writeStream = (__bridge_transfer NSOutputStream *)writeStream;
	
	self.readStream.delegate = self;
	[self.readStream open];
	[self.readStream scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
	[self.writeStream open];
	[self.writeStream scheduleInRunLoop: [NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];

	[self sendString: [NSString stringWithFormat: @"PASS %@", self.oauthToken]];
	
	[self sendString: [NSString stringWithFormat: @"NICK %@", self.nickname]];

	[self sendString: @"CAP REQ :twitch.tv/membership"];
	[self sendString: @"CAP REQ :twitch.tv/tags"];
	[self sendString: @"CAP REQ :twitch.tv/commands"];

	[self sendString: [NSString stringWithFormat: @"JOIN #%@", self.channelName.lowercaseString]];
	
	self.startupTime = [NSDate date];
	
	*outError = nil;
}


-(void) disconnect
{
	[self sendString: [NSString stringWithFormat: @"PART #%@", self.channelName.lowercaseString]];
	[self sendString: @"QUIT :bot disconnecting."];

	[self.writeStream close];
}


-(void) processOneSelfSentChatMessage: (NSString *)text
{
	NSString * fullMessage = [NSString stringWithFormat: @":%1$@!%1$@@%1$@.tmi.twitch.tv PRIVMSG #%2$@ :%3$@", self.nickname, self.channelName.lowercaseString, text];
	[self processOneMessage: fullMessage];
}


-(void) sendChatMessage: (NSString *)text
{
	[self sendString: [NSString stringWithFormat: @"PRIVMSG #%@ :%@", self.channelName.lowercaseString, text]];
	[self processOneSelfSentChatMessage: text];
}


-(void) sendString: (NSString*)inString
{
	NSLog(@"Sending: %@", inString);
	
	const char * inStringCStr = [[inString stringByAppendingString: @"\r\n"] UTF8String];
	NSInteger len = strlen(inStringCStr);
	NSInteger bytesWritten = [self.writeStream write: (const uint8_t *)inStringCStr maxLength: len];
	if( bytesWritten != len )
	{
		NSLog(@"Tried to write %ld bytes, only managed to write %ld", (long) len, (long) bytesWritten);
	}
}


-(void) stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
	if( eventCode == NSStreamEventHasBytesAvailable )
	{
		uint8_t currStr[IRC_PROTOCOL_MESSAGE_LENGTH_LIMIT + 1] = {};
		NSInteger bytesRead = [self.readStream read:currStr maxLength:IRC_PROTOCOL_MESSAGE_LENGTH_LIMIT];
		if( bytesRead < 0 )
			return;
		currStr[bytesRead] = 0;
		NSString *messageStr = [NSString stringWithUTF8String:(char*)currStr];
		if( !messageStr )
			messageStr = [NSString stringWithCString:(char*)currStr encoding:NSISOLatin1StringEncoding];
		if( messageStr )
			[self.receivedText appendString: messageStr];
		NSLog(@"Received %ld bytes: %@", (long)bytesRead, messageStr);
		[self processReceivedText];
	}
}


-(void) processOneMessage: (NSString*)inMessage
{
	//NSLog(@"RECEIVED: %@", inMessage);
	
	NSString * currMessage = inMessage;
	NSString * username = @"";
	NSString * prefix = @"";
	NSString * tags = @"";
	NSMutableArray * messageParts = [NSMutableArray array];
	NSMutableDictionary * tagsDict = [NSMutableDictionary new];

	if( [currMessage hasPrefix:@"@"])
	{
		NSRange tagsEndRange = [currMessage rangeOfString: @" "];
		if( tagsEndRange.location != NSNotFound )
		{
			tags = [currMessage substringWithRange:NSMakeRange(1, tagsEndRange.location - 1)];
			currMessage = [currMessage substringFromIndex: tagsEndRange.location +tagsEndRange.length];
			
			NSArray * tagsArray = [tags componentsSeparatedByString:@";"];
			for( NSString *currLine in tagsArray )
			{
				NSRange separatorRange = [currLine rangeOfString:@"="];
				if (separatorRange.location != NSNotFound)
				{
					NSString * tagName = [currLine substringToIndex: separatorRange.location];
					NSString * tagBody = [currLine substringFromIndex: NSMaxRange(separatorRange)];
					tagsDict[tagName] = tagBody;
				}
			}
		}
	}
	
	NSRange firstPartEndRange = [currMessage rangeOfString: @" "];
	if( firstPartEndRange.location != NSNotFound )
	{
		prefix = [currMessage substringToIndex:firstPartEndRange.location];
		currMessage = [currMessage substringFromIndex: firstPartEndRange.location +firstPartEndRange.length];
		if( [prefix hasPrefix: @":"] )
		{
			NSRange userSeparatorRange = [prefix rangeOfString:@"!"];
			if( userSeparatorRange.location != NSNotFound )
			{
				NSRange userNameRange = { 1, userSeparatorRange.location - 1 };
				NSRange prefixRange = { userSeparatorRange.location + userSeparatorRange.length, 0 };
				prefixRange.length = prefix.length - prefixRange.location;
				username = [prefix substringWithRange:userNameRange];
				prefix = [prefix substringWithRange:prefixRange];
			}
			else
			{
				prefix = [prefix substringFromIndex:1];
			}
		}
		else
		{
			[messageParts addObject:prefix];
			prefix = @"";
		}
		while(YES)
		{
			NSRange partEndRange = [currMessage rangeOfString: @" "];
			if( partEndRange.location == NSNotFound )
			{
				if( currMessage.length != 0 )
				{
					if( [currMessage hasPrefix:@":"] )
						[messageParts addObject:[currMessage substringFromIndex: 1]];
					else
						[messageParts addObject:currMessage];
				}
				break;
			}
			NSString * currPart = [currMessage substringToIndex: partEndRange.location];
			if( currPart.length > 0 && [currPart characterAtIndex: 0] == ':' )
			{
				partEndRange.location = currMessage.length;
				partEndRange.length = 0;
				currPart = [currMessage substringWithRange: NSMakeRange(1, partEndRange.location - 1)];
			}
			currMessage = [currMessage substringFromIndex: partEndRange.location +partEndRange.length];
			[messageParts addObject:currPart];
		}
	}
	else
	{
		[messageParts addObject:currMessage];
	}
	//NSLog(@"%@", inMessage);
	[self handleMessage: messageParts.firstObject forNickname: username parameters: (messageParts.count > 1) ? [messageParts subarrayWithRange:NSMakeRange(1,messageParts.count - 1)] : @[] prefix: prefix tags: tagsDict];
}


-(void) handleMessage: (NSString*)messageName forNickname: (NSString*)inNickname parameters:(NSArray<NSString *> *)inParameters prefix: (NSString *)prefix tags: (NSDictionary *)tags
{
	if( [messageName isEqualToString:@"USERSTATE"] )
	{
		if( inNickname.length == 0 )
		{
			inNickname = tags[@"display-name"];
		}
		self.userInfos[inNickname.lowercaseString] = [[ULIRCUserInfo alloc] initWithTags:tags];
		NSLog(@"user %@ tags changed to %@", inNickname, self.userInfos[inNickname.lowercaseString]);
	}
	else if( [messageName isEqualToString:@"PRIVMSG"] )
	{
		if( tags.count > 0 && inNickname.length > 0 )
		{
			self.userInfos[inNickname.lowercaseString] = [[ULIRCUserInfo alloc] initWithTags:tags];
			NSLog(@"user %@ tags changed to %@", inNickname, self.userInfos[inNickname.lowercaseString]);
		}

		if( inParameters.count > 1 )
		{
			NSString *theMessage = inParameters[1];
			if( [theMessage hasPrefix: @"!"] )
			{
				NSString * botCommandMessage = theMessage;
				NSString * botCommandName = nil;
				NSRange commandSeparator = [theMessage rangeOfString:@" "];
				if( commandSeparator.location != NSNotFound )
				{
					botCommandName = [theMessage substringWithRange:NSMakeRange(1, commandSeparator.location - 1)];
					botCommandMessage = [theMessage substringFromIndex: commandSeparator.location + commandSeparator.length];
				}
				else
				{
					botCommandName = [theMessage substringFromIndex: 1];
					botCommandMessage = @"";
				}
				
				ULIRCBotCommandHandler _Nullable handler = self.botCommands[botCommandName];
				if( !handler )
					handler = self.botCommands[@"*"];
				if( handler )
				{
					handler( botCommandName, inNickname, botCommandMessage, prefix, tags );
					self.lastCommandUseTimes[botCommandName.lowercaseString] = [NSDate date];
					return;
				}
			}
		}
	}
	
	ULIRCProtocolCommandHandler _Nullable handler = self.protocolCommands[messageName];
	if( !handler )
		handler = self.protocolCommands[@"*"];
	if( handler )
	{
		handler( messageName, inNickname, inParameters, prefix, tags );
	}

	//NSLog(@"[%@] %@: %@ %@ %@", prefix, inNickname, messageName, inParameters, tags);
}


-(void) processReceivedText
{
	while( YES )
	{
		NSRange endMarker = [self.receivedText rangeOfString: @"\r\n"];
		if( endMarker.location == NSNotFound )
			break;
		NSRange firstMessage = {0, endMarker.location + endMarker.length};
		NSString *currMessage = [self.receivedText substringToIndex:endMarker.location];
		[self.receivedText deleteCharactersInRange:firstMessage];
		[self processOneMessage: currMessage];
	}
}


-(void) registerHandler: (ULIRCBotCommandHandler)inHandler forBotCommand: (NSString*)botCommand // Custom command in a PRIVMSG chat message (like !dead or !addquote without the "!").
{
	self.botCommands[botCommand] = inHandler;
}


-(void) registerHandler: (ULIRCProtocolCommandHandler)inHandler forProtocolCommand: (NSString *)inIRCCommandName // Low-level IRC command.
{
	self.protocolCommands[inIRCCommandName] = inHandler;
}


-(void) sendRequest
{
	NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString: @"https://api.twitch.tv/helix/"]];
	[request setValue: [NSString stringWithFormat:@"Bearer %@", self.oauthToken] forHTTPHeaderField: @"Authorization"];
}

@end


@implementation ULIRCUserInfo

-(instancetype) initWithTags:(NSDictionary<NSString *, NSString *> *)inTags
{
	if (self = [super init])
	{
		NSArray<NSString *> *badgeLines = [inTags[@"badges"] componentsSeparatedByString: @","];
		for( NSString *currLine in badgeLines )
		{
			NSArray<NSString *> *parts = [currLine componentsSeparatedByString: @"/"];
			if( [parts.firstObject.lowercaseString isEqualToString: @"subscriber"] )
				_subscriber = YES;
			else if( [parts.firstObject.lowercaseString isEqualToString: @"broadcaster"] )
				_broadcaster = YES;
			else if( [parts.firstObject.lowercaseString isEqualToString: @"partner"] )
				_partner = YES;
			else if( [parts.firstObject.lowercaseString isEqualToString: @"turbo"] )
				_turbo = YES;
			else if( [parts.firstObject.lowercaseString isEqualToString: @"premium"] )
				_prime = YES;
			else if( [parts.firstObject.lowercaseString isEqualToString: @"bits"] )
				_bitBadgeAmount = parts.lastObject.integerValue;
		}
		if( !_turbo )
			_turbo = inTags[@"turbo"].boolValue;
		_moderator = inTags[@"mod"].boolValue;
		if( !_subscriber )
			_subscriber = inTags[@"subscriber"].boolValue;
		_htmlColor = inTags[@"color"];
		_displayName = inTags[@"display-name"];
	}
	return self;
}


-(NSString *) description
{
	NSDictionary * desriptionDict = @{
									  @"subscriber": @(_subscriber),
									  @"broadcaster": @(_broadcaster),
									  @"partner": @(_partner),
									  @"bitBadgeAmount": @(_bitBadgeAmount),
									  @"turbo": @(_turbo),
									  @"prime": @(_prime),
									  @"moderator": @(_moderator),
									  @"htmlColor": _htmlColor ?: @"",
									  @"displayName": _displayName ?: @"",
									  };
	return [NSString stringWithFormat: @"<%@ %p> %@", self.className, self, desriptionDict];
}

@end


