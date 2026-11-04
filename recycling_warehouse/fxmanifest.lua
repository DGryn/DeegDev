fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'recycling_warehouse'
description 'Warehouse recycling job: carry boxes to the skip, trade recycle boxes for materials.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua', -- enables lib.* in every script
    'config.lua',
}

client_script 'client.lua'
server_script 'server.lua'

dependencies {
    '/onesync',     -- the server reads player positions for its distance checks
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target',
}
