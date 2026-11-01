fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dg_cocaine'
description 'Cocaine.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua', 
    'server.lua',
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target',
}
