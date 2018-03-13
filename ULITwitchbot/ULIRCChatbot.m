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


@interface ULIRCChatbot () <NSStreamDelegate>

@property NSInputStream * readStream;
@property NSOutputStream * writeStream;
@property NSMutableString * receivedText;

@property NSMutableDictionary<NSString *,ULIRCProtocolCommandHandler> * protocolCommands;
@property NSMutableDictionary<NSString *,ULIRCBotCommandHandler> * botCommands;

@property NSMutableDictionary<NSString *,NSNumber *> * counters;

@end


@implementation ULIRCChatbot

@synthesize settingsFolderURL = _settingsFolderURL;

-(instancetype) init
{
	self = [super init];
	if( self )
	{
		self.protocolCommands = [NSMutableDictionary dictionary];
		self.botCommands = [NSMutableDictionary dictionary];

		[self registerHandler:^(NSString *inCommandName, NSString *inNickname, NSArray<NSString *> *inParameters, NSString *inPrefix)
		{
			NSLog(@"ANSWERING [%@] %@: %@ %@", inPrefix, inNickname, inCommandName, inParameters);
			[self sendString:[NSString stringWithFormat: @"PONG %@", inParameters.firstObject ?: @""]];
		} forProtocolCommand: @"PING"];
	}
	
	return self;
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
	
	ULIRCChatbot * __weak weakSelf = self;
	if( [commandType.lowercaseString isEqualToString: @"counter"] )
	{
		NSString * msgFormat = commandInfo[@"ULIRCCommandMessage"] ?: @"%CHANNEL% has a %COMMANDNAME% count of %COUNT%.";
		msgFormat = [msgFormat stringByReplacingOccurrencesOfString:@"%COMMANDNAME%" withString:commandName];

		NSString * queryCommandName = commandInfo[@"ULIRCQueryCommandName"] ?: [commandName stringByAppendingString: @"count"];

		[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix )
		 {
			 typeof(self) strongSelf = weakSelf;
			 if( strongSelf )
			 {
				 NSNumber * currentCount = [strongSelf.counters objectForKey: inCommandName];
				 [strongSelf.counters setObject: [NSNumber numberWithInteger: currentCount.integerValue + 1] forKey: inCommandName];
				 NSString * msg = [msgFormat stringByReplacingOccurrencesOfString:@"%COUNT%" withString:[NSString stringWithFormat: @"%ld", (long)currentCount.integerValue + 1]];
				 msg = [msg stringByReplacingOccurrencesOfString:@"%CHANNEL%" withString:self.channelName];
				 [strongSelf sendChatMessage: msg];

				 NSURL * countersURL = [_settingsFolderURL URLByAppendingPathComponent: @"Counters.plist"];
				 [self.counters writeToURL: countersURL error:NULL];
			 }
		 } forBotCommand: commandName];
		[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix )
		 {
			 typeof(self) strongSelf = weakSelf;
			 if( strongSelf )
			 {
				 NSNumber * currentCount = [strongSelf.counters objectForKey: commandName];
				 NSString * msg = [msgFormat stringByReplacingOccurrencesOfString:@"%COUNT%" withString:[NSString stringWithFormat: @"%ld", (long)currentCount.integerValue]];
				 msg = [msg stringByReplacingOccurrencesOfString:@"%CHANNEL%" withString:self.channelName];
				 [strongSelf sendChatMessage: msg];
			 }
		 } forBotCommand: queryCommandName];
	}
	else if( [commandType.lowercaseString isEqualToString: @"quote"] )
	{
		[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix )
		 {
			 typeof(self) strongSelf = weakSelf;
			 if( strongSelf )
			 {
				 NSURL * quotesURL = [[_settingsFolderURL URLByAppendingPathComponent: @"Quotes"] URLByAppendingPathComponent: [NSString stringWithFormat: @"%@.txt", commandName]];
				 NSString * quotesData = [NSString stringWithContentsOfURL: quotesURL encoding: NSUTF8StringEncoding error: NULL];
				 NSArray * quotes = [quotesData componentsSeparatedByString: @"\n"];
				 NSInteger quoteIndex = (inMessage.length > 0) ? (inMessage.integerValue - 1) : (rand() % quotes.count);
				 if( quoteIndex < quotes.count )
				 {
					 NSString * quoteLine = [quotes objectAtIndex: quoteIndex];
					 [strongSelf sendChatMessage: [NSString stringWithFormat: @"%ld: %@", quoteIndex + 1, quoteLine]];
				 }
				 else
					 [strongSelf sendChatMessage: @"Not found."];
			 }
		 } forBotCommand: commandName];
		
		if( [commandInfo[@"ULIRCEditable"] boolValue] )
		{
			[self registerHandler: ^( NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix )
			 {
				 typeof(self) strongSelf = weakSelf;
				 if( strongSelf )
				 {
					 NSURL * quotesURL = [[_settingsFolderURL URLByAppendingPathComponent: @"Quotes"] URLByAppendingPathComponent: [NSString stringWithFormat: @"%@.txt", commandName]];
					 NSMutableString * quotesData = [NSMutableString stringWithContentsOfURL: quotesURL encoding: NSUTF8StringEncoding error: NULL];
					 inMessage = [inMessage stringByReplacingOccurrencesOfString:@"\r\n" withString: @" "];
					 inMessage = [inMessage stringByReplacingOccurrencesOfString:@"\r" withString: @" "];
					 inMessage = [inMessage stringByReplacingOccurrencesOfString:@"\n" withString: @" "];
					 if( quotesData.length > 0 )
						 [quotesData appendString: @"\n"];
					 [quotesData appendString: inMessage];
					 [quotesData writeToURL:quotesURL atomically:YES encoding:NSUTF8StringEncoding error:NULL];
					 [strongSelf sendChatMessage: @"Added."];
				 }
			 } forBotCommand: [@"add" stringByAppendingString:commandName]];
		}
	}
	else
	{
		NSLog(@"Failed to load command '%@', type '%@' unknown.", commandName, commandType);
	}
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
	
	[self sendString: [NSString stringWithFormat: @"JOIN #%@", self.channelName.lowercaseString]];

	*outError = nil;
}


-(void) sendChatMessage: (NSString *)text
{
	[self sendString: [NSString stringWithFormat: @"PRIVMSG #%@ :%@", self.channelName.lowercaseString, text]];
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
		[self.receivedText appendString: messageStr];
		//NSLog(@"Received %ld bytes: %@ [%ld,%ld]", (long)bytesRead, messageStr);
		[self processReceivedText];
	}
}


-(void) processOneMessage: (NSString*)inMessage
{
	NSString * currMessage = inMessage;
	NSString * username = @"";
	NSString * prefix = @"";
	NSMutableArray * messageParts = [NSMutableArray array];
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
	[self handleMessage: messageParts.firstObject forNickname: username parameters: [messageParts subarrayWithRange:NSMakeRange(1,messageParts.count - 1)] prefix: prefix];
}


-(void) handleMessage: (NSString*)messageName forNickname: (NSString*)inNickname parameters:(NSArray<NSString *> *)inParameters prefix: (NSString *)prefix
{
	if( [messageName isEqualToString:@"PRIVMSG"] )
	{
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
					handler( botCommandName, inNickname, botCommandMessage, prefix );
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
		handler( messageName, inNickname, inParameters, prefix );
	}

	//NSLog(@"[%@] %@: %@ %@", prefix, inNickname, messageName, inParameters);
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

@end
