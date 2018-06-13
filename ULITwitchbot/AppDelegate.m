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
@property (weak) IBOutlet NSSecureTextField *oauthTokenField;
@property (strong) ULIRCChatbot *chatbot;

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


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	self.userNameField.stringValue = self.userName;
	self.oauthTokenField.stringValue = self.oauthToken;
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

static FILE* theFile = nil;

-(IBAction)establishConnection:(nullable id)sender
{
	NSURL *settingsURL = [NSURL fileURLWithPath: [@"~/Library/Application Support/ULITwitchbot/" stringByExpandingTildeInPath]];
	if( ![settingsURL checkResourceIsReachableAndReturnError:NULL] )
	{
		[[NSFileManager defaultManager] copyItemAtURL:[NSBundle.mainBundle URLForResource:settingsURL.lastPathComponent withExtension:nil] toURL:settingsURL error:NULL];
	}
	self.chatbot = [ULIRCChatbot new];
//    self.chatbot.settingsFolderURL = settingsURL;
	self.chatbot.oauthToken = self.oauthToken;
	self.chatbot.nickname = self.userName;
    self.chatbot.channelName = @"meluist";//self.userName;
	
	NSLog(@"Settings folder: %@", self.chatbot.settingsFolderURL);
	
//    [self.chatbot registerHandler:^(NSString *inCommandName, NSString *inNickname, NSString *inMessage, NSString *inPrefix) {
//        NSLog(@"%@ BOT COMMAND TRIGGERED", inCommandName);
//    } forBotCommand:@"*"];

    theFile = fopen(@"~/MeluistQuotes.txt".stringByExpandingTildeInPath.fileSystemRepresentation, "w");
	[self.chatbot registerHandler:^(NSString *inCommandName, NSString *inNickname, NSArray<NSString *> *inParameters, NSString *inPrefix) {
//        NSLog(@"[%@] %@: %@", (inParameters.count > 0) ? inParameters[0] : @"", inNickname, (inParameters.count > 1) ? inParameters[1] : @"");
        if( inParameters.count > 1 && [inNickname caseInsensitiveCompare:@"melubot"] == NSOrderedSame)
        {
            fprintf(theFile, "%s\r\n", [inParameters[1] UTF8String]);
            fflush(theFile);
            NSLog(@"%@", inParameters[1]);
        }
	} forProtocolCommand: @"PRIVMSG"];
	
	NSError * err = nil;
	[self.chatbot connectReturningError:&err];
	if (err) NSLog(@"%@", err);

    __block NSInteger quoteIndex = 143;
    NSTimer * timer = [NSTimer scheduledTimerWithTimeInterval:20.0 repeats:YES block:^(NSTimer * _Nonnull timer)
                       {
                           NSString * command = [NSString stringWithFormat:@"!quote %ld", (long)++quoteIndex];
                           [self.chatbot sendChatMessage: command];
                           if (quoteIndex >= 790)
                           {
                               [self performSelector:@selector(shutDownWritingWithTimer:) withObject:timer afterDelay:10.0];
                               [timer invalidate];
                           }
                       }];
    timer.tolerance = 2.0;
}

-(void)shutDownWritingWithTimer:(NSTimer *)timer
{
    fclose(theFile);
    theFile = NULL;
    NSLog(@"*** Done. *** ");
}

-(IBAction) sendAMessage: (nullable id)sender
{
	[self.chatbot sendChatMessage: self.messageField.stringValue];
}

-(IBAction) openTokenPageURL: (nullable id)sender
{
	[[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"https://twitchapps.com/tmi/"]];
}

@end
