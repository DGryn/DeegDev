fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dg_cocaine'
description 'Cocaine: trade for seeds, grow on the islands, process at a hidden lab, bag bricks.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua', -- https://coxdocs.dev/ox_lib (enables lib.* in every script)
    'config.lua',
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- https://coxdocs.dev/oxmysql
    'server.lua',
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target',
}
