fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dg_parcels'
description 'House parcels: grab parcels from doorsteps, cut them open for loot. Some are trapped.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua', -- enables lib.* and cache.* in every script
    'config.lua',
}

client_script 'client/main.lua'
server_script 'server/main.lua'

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target',
}
