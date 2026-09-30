fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dg_lumberjack'
description 'Civilian lumberjack job: chop trees, haul logs, mill planks, deliver.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua', -- https://coxdocs.dev/ox_lib (enables lib.* in every script)
    'config.lua',
}

client_script 'client.lua'
server_script 'server.lua'

dependencies {
    '/onesync',     -- entity state bags + server-side vehicle natives need OneSync
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target',
}
