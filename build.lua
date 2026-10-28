return {
  -- basic settings:
  name = 'TheFightBug', -- name of the game for your executable
  developer = 'Pablo Fornet', -- dev name used in metadata of the file
  output = '~/Desktop', -- output location for your game, defaults to $SAVE_DIRECTORY
  version = '0.1', -- 'version' of your game, used to name the folder in output
  love = '11.5', -- version of LÖVE to use, must match github releases
  ignore = {'dist', 'ignoreme.txt'}, -- folders/files to ignore in your project
  icon = 'resources/art/icon.png', -- 256x256px PNG icon for game, will be converted for you
  -- optional settings:
  use32bit = false, -- set true to build windows 32-bit as well as 64-bit
  -- platforms = {'macos'} -- set if you only want to build for a specific platform
}
