# MapChooser Extended

Currently supported fork of the original [MapChooser Extended by Powerlord](https://forums.alliedmods.net/showthread.php?t=156974).

## History

This fork started in roughly 2017, when the base SourceMod mapchooser, nominations, and rockthevote plugins started seeing some valuable updates, which had deisrable features and fixes. The existing syntax of powerlord's fork was deprecated, and if memory serves, would not compile on the stable SourceMod 1.10 compiler. I wanted to fix that.

The secondary goal which came along a bit over a year later, was to implement a fully-featured mapchooser/nomination/rtv plugin that would be universal across all server types - simple or complex. Want to use advanced features? Absolutely! Want to keep things simple, while being able to have more configuration options over stock SourceMod plugins? This can do that too.

Third goal: A modern, up-to-date, feature-rich fork of MCE. With the growing number of forks that exist of MCE, a single version that can be contributed to by the community at large would benefit all.

## MCE Updates

The route this fork took was from [Powerlord's original MCE repository](https://github.com/powerlord/sourcemod-mapchooser-extended), to [MitchDizzle's maps-names branch](https://github.com/MitchDizzle/sourcemod-mapchooser-extended/tree/map-names), to now. The changes since Powerlord's version are listed below.

- Added custom map names, natives, and universal replacements
- Updated to Transitional syntax, utilize methodmaps
- Utilize engine's fuzzy map search/autocompletion for nominations
- Proper rounding for RTV
- Added optional tier menu
- Added SteamID to nomination logging
- Removed NativeVotes support
- Fix issue in translations
- Added configurable chat prefix
- Added no-vote extend option
- Removed minimums for map extensions
- Added menu which displays partial map matches rather than nominating first match
- Auto generate nominations config file
- Normalized all convar naming conventions
- Utilize [Multi-Colors](https://github.com/Bara/Multi-Colors) for up to date, multi-game support

## Resources

- [Mapcycle Generator for KZ Global Maps](https://devruto.github.io/KZMapcycleGenerator/) by [Ruto](https://github.com/devruto)
