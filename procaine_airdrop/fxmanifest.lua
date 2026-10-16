fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'procaine_airdrop'
description 'Plane airdrops that are the only source of procaine'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_script 'client.lua'

server_scripts {
    '@es_extended/imports.lua',
    'server.lua',
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target',
}
