//
//  AppDelegate.m
//  ULITwitchbot
//
//  Created by Uli Kusterer on 12.03.18.
//  Copyright © 2018 Uli Kusterer. All rights reserved.
//

#import "AppDelegate.h"
#import "ULIRCChatbot.h"


@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextField *messageField;
@property (weak) IBOutlet NSTextField *userNameField;
@property (weak) IBOutlet NSTextField *channelNameField;
@property (weak) IBOutlet NSSecureTextField *oauthTokenField;
@property (strong) ULIRCChatbot *chatbot;
@property (nonatomic) BOOL shouldLoadBotCommands;
@property (nonatomic) BOOL makeChannelNameMatchUserName;

@end

@implementation AppDelegate

-(NSString*) oauthToken
{
	NSString * userName = [NSUserDefaults.standardUserDefaults objectForKey: @"ULIRCUserName"];
	if( !userName )
		return @"";
	NSDictionary * secItemInfo = @{
								   (__bridge NSString *)kSecAttrService: @"Twitch.tv OAuth Token",
								   (__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassGenericPassword,
								   (__bridge NSString *)kSecAttrAccount: userName,
								   (__bridge NSString *)kSecReturnData: @YES,
								   (__bridge NSString *)kSecMatchLimit: (__bridge NSString *)kSecMatchLimitOne
								   };
	CFTypeRef outData = NULL;
	SecItemCopyMatching( (__bridge CFDictionaryRef) secItemInfo, &outData );
	NSData * theData = (__bridge_transfer NSData*)outData;
	NSString *oauthToken = [[NSString alloc] initWithData:theData encoding:NSUTF8StringEncoding] ?: @"";
	
	return oauthToken;
}


-(NSString *) userName
{
	return [NSUserDefaults.standardUserDefaults objectForKey: @"ULIRCUserName"] ?: @"";
}


-(NSString *) channelName
{
	NSString * channelName = [NSUserDefaults.standardUserDefaults objectForKey: @"ULIRCChannelName"] ?: @"";
	if( !channelName || channelName.length == 0 )
	{
		channelName = self.userName;
	}
	return channelName;
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	self.userNameField.stringValue = self.userName;
	self.channelNameField.stringValue = self.channelName;
	self.oauthTokenField.stringValue = self.oauthToken;
	
	self.makeChannelNameMatchUserName = [self.userName caseInsensitiveCompare:self.channelName] == NSOrderedSame;

	NSNumber *loadBotCommandsObject = [NSUserDefaults.standardUserDefaults objectForKey:@"ULIRCLoadBotCommands"];
	BOOL loadBotCommands = loadBotCommandsObject ? loadBotCommandsObject.boolValue : YES;
	self.shouldLoadBotCommands = loadBotCommands;
}


- (void)applicationWillTerminate: (NSNotification *)notification
{
	NSString * userName = self.userNameField.stringValue;
	[NSUserDefaults.standardUserDefaults setObject: userName forKey:@"ULIRCUserName"];

	NSDictionary * secItemInfo = @{
								   (__bridge NSString *)kSecAttrService: @"Twitch.tv OAuth Token",
								   (__bridge NSString *)kSecClass: (__bridge NSString *)kSecClassGenericPassword,
								   (__bridge NSString *)kSecAttrAccount: userName,
								   (__bridge NSString *)kSecValueData: [self.oauthTokenField.stringValue dataUsingEncoding: NSUTF8StringEncoding]
								   };
	SecItemDelete( (__bridge CFDictionaryRef) secItemInfo );
	SecItemAdd( (__bridge CFDictionaryRef) secItemInfo, NULL );
}


-(IBAction)establishConnection:(nullable id)sender
{
	if (self.chatbot != nil)
	{
		[self willChangeValueForKey:@"enableShouldLoadBotCommands"];
		[self willChangeValueForKey:@"connectButtonTitle"];
		
		[self.chatbot disconnect];
		self.chatbot = nil;
		
		[self didChangeValueForKey:@"enableShouldLoadBotCommands"];
		[self didChangeValueForKey:@"connectButtonTitle"];
		return;
	}
	
	NSURL *settingsURL = [NSURL fileURLWithPath: [@"~/Library/Application Support/ULITwitchbot/" stringByExpandingTildeInPath]];
	if( ![settingsURL checkResourceIsReachableAndReturnError:NULL] )
	{
		[[NSFileManager defaultManager] copyItemAtURL:[NSBundle.mainBundle URLForResource:settingsURL.lastPathComponent withExtension:nil] toURL:settingsURL error:NULL];
	}
	
	[self willChangeValueForKey:@"enableShouldLoadBotCommands"];
	[self willChangeValueForKey:@"connectButtonTitle"];

	self.chatbot = [ULIRCChatbot new];
	self.chatbot.settingsFolderURL = _shouldLoadBotCommands ? settingsURL : nil;
	self.chatbot.oauthToken = self.oauthToken;
	self.chatbot.nickname = self.userName;
	self.chatbot.channelName = self.userName;

	[self didChangeValueForKey:@"enableShouldLoadBotCommands"];
	[self didChangeValueForKey:@"connectButtonTitle"];

	if (_shouldLoadBotCommands)
	{
		NSLog(@"Settings folder: %@", self.chatbot.settingsFolderURL);
	}
	
	[self.chatbot registerHandler:^(NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix)
	{
		NSLog(@"%@ BOT COMMAND TRIGGERED", inCommandName);
	} forBotCommand:@"*"];
	
	[self.chatbot registerHandler:^(NSString *inCommandName, NSString *inNickname, NSArray<NSString *> *inParameters, NSString *inPrefix)
	{
		NSLog(@"[%@] %@: %@", (inParameters.count > 0) ? inParameters[0] : @"", inNickname, (inParameters.count > 1) ? inParameters[1] : @"");
	} forProtocolCommand: @"PRIVMSG"];
	
	NSError * err = nil;
	[self.chatbot connectReturningError:&err];
	if (err) NSLog(@"%@", err);
}

-(IBAction) sendAMessage: (nullable id)sender
{
	[self.chatbot sendChatMessage: self.messageField.stringValue];
}

-(IBAction) openTokenPageURL: (nullable id)sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"https://twitchapps.com/tmi/"]];
}

-(void) setShouldLoadBotCommands:(BOOL)shouldLoadBotCommands
{
	_shouldLoadBotCommands = shouldLoadBotCommands;
	[NSUserDefaults.standardUserDefaults setBool:shouldLoadBotCommands forKey:@"ULIRCLoadBotCommands"];
}

-(BOOL) enableShouldLoadBotCommands
{
	return self.chatbot == nil;
}

-(NSString *)connectButtonTitle
{
	if( self.chatbot == nil )
	{
		return @"Connect";
	}
	else
	{
		return @"Disconnect";
	}
}

-(void)	controlTextDidChange: (NSNotification *)notification
{
	if( notification.object == self.userNameField )
	{
		if( self.makeChannelNameMatchUserName )
		{
			self.channelNameField.stringValue = self.userNameField.stringValue;
			[NSUserDefaults.standardUserDefaults setObject:self.channelNameField.stringValue forKey:@"ULIRCChannelName"];
		}
		[NSUserDefaults.standardUserDefaults setObject:self.userNameField.stringValue forKey:@"ULIRCUserName"];
	}
	else if( notification.object == self.channelNameField )
	{
		[NSUserDefaults.standardUserDefaults setObject:self.channelNameField.stringValue forKey:@"ULIRCChannelName"];
		self.makeChannelNameMatchUserName = [self.userName caseInsensitiveCompare:self.channelName] == NSOrderedSame;
	}
}

@end
