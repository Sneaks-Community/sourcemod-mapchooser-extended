# MapChooser Extended

Currently supported fork of the original [MapChooser Extended by Powerlord](https://forums.alliedmods.net/showthread.php?t=156974).

## History

This fork started in roughly 2017, when the base SourceMod mapchooser, nominations, and rockthevote plugins started seeing some valuable updates, which had deisrable features and fixes. The existing syntax of powerlord's fork was deprecated, and if memory serves, would not compile on the stable SourceMod 1.10 compiler. I wanted to fix that.

The secondary goal which came along a bit over a year later, was to implement a fully-featured mapchooser/nomination/rtv plugin that would be universal across all server types - simple or complex. Want to use advanced features? Absolutely! Want to keep things simple, while being able to have more configuration options over stock SourceMod plugins? This can do that too.

## MCE Updates

The route this fork took was from [Powerlord's original MCE repository](https://github.com/powerlord/sourcemod-mapchooser-extended), to [MitchDizzle's maps-names branch](https://github.com/MitchDizzle/sourcemod-mapchooser-extended/tree/map-names), to now. The changes since Powerlord's version are listed below.

- Added custom map names, natives, and universal replacements
- Updated to Transitional syntax, utilize methodmaps
- Proper rounding for RTV
- Added optional tier menu
- Added SteamID to nomination logging
- Removed NativeVotes support
- Fix issue in translations
- Added configurable chat prefix
- Added no-vote extend option
- Removed minimums for map extensions
- Auto generate nominations config file
- Normalized all convar naming conventions
