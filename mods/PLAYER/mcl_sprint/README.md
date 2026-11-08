# Sprint Mod for VoxeLibre
Forked from [sprint] by GunshipPenguin  

## Description
Allows the player to sprint by holding the “Use” key (default: Ctrl) while
moving forwards, or by double-tapping the forward key, both like Minecraft.
By default, sprinting will make the player travel 30% faster. 

Licence: CC0 (see COPYING file)

## Mod developer settings (`init.lua`)
### `mcl_sprint.SPEED`
How fast the player will move when sprinting as opposed to normal 
movement speed. 1.0 represents normal speed so 1.5 would mean that a 
sprinting player would travel 50% faster than a walking player and 
2.4 would mean that a sprinting player would travel 140% faster than 
a walking player.

### `mcl_sprint.DOUBLE_TAP_TIME`
How close together (in seconds) two presses of the forward key have to be
to start a sprint. Default: 0.3.
