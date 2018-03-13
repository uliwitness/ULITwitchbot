# ULITwitchbot

## What is it?

A simple application that will "listen" to the chat in a Twitch channel and react to certain keywords.

## How do I use it?

Launch the app, enter the channel's name and your Twitch OAuth token. Then click "Connect".
The bot now listens to the chat as if it was you, and will post its replies as your account.

The commands it understands are defined in the Application Support folder. Bot commands follow
the Twitch convention of having to be one word prefixed with an exclamation mark (like "!dead").

### What command types are currently supported?

Currently, the chatbot can create counters that increment each time their command is triggered,
and commands that pick and post a random line of text from a text file and post it (e.g. for quotes).

### Commands in General

Commands are defined by adding a folder with the name of the command to `~/Library/Application Support/ULITwitchbot/Commands/` and placing an Info.plist file in a subfolder of it that contains the settings for the command. Every command has at the least
a type, specified using the `ULIRCCommandType` key.

#### Commands of type "counter"

A counter command will increment a count, which is saved across bot restarts, in `~/Library/Application Support/ULITwitchbot/Counters.plist`. A counter starts at 0, and increments by 1 each time the command is triggered.

A counter also implements a second command that can be used to just query the counter value without incrementing it.

`ULIRCQueryCommandName` - Specify the name of the command here that should be used to query the counter without incrementing it. If this key is missing, the command name is used, with "count" appended. So if you named your command "dead", the query command will be named "deadcount".

`ULIRCCommandMessage` - The message to display when either command is triggered. If you do not provide a message, a default message of "%CHANNEL% has a %COMMANDNAME% count of %COUNT%." will be used. If you use any or all of the three placeholders %CHANNEL%, %COMMANDNAME% or %COUNT%. They will automatically be replaced with the requisite values.

#### Commands of type "quote"

A quote command looks for a text file named the same as the command and randomly displays lines from this file. So for example,
if you named the command's folder "joke", it will look for a file named `~/Library/Application Support/ULITwitchbot/Quotes/joke.txt` and display a random line from that whenever a user types "!joke". If you specify a number after the command, e.g. "!joke 5", it will display the fifth line from that file instead.

`ULIRCEditable` - Specify a boolean (either YES or NO) under this name in the command's Info.plist file to also add an "add"-command for the command, which chatters can use to add additional lines to this text file. If you name your command "joke", this option will add both a "joke" command and an "addjoke" command.


## License

Copyright 2018 by Uli Kusterer.

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
claim that you wrote the original software. If you use this software
in a product, an acknowledgment in the product documentation would be
appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be
misrepresented as being the original software.

3. This notice may not be removed or altered from any source
distribution.



