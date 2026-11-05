fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'gryn_gruppe'
description 'Gruppe 6 cash-in-transit job with groups, levels, van robberies and a black market.'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua', -- https://coxdocs.dev/ox_lib (enables lib.* in every script)
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/jobs.lua',
    'client/robbery.lua',
    'client/blackmarket.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- https://coxdocs.dev/oxmysql
    'server/main.lua',
    'server/progression.lua',
    'server/groups.lua',
    'server/jobs.lua',
    'server/robbery.lua',
    'server/blackmarket.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'es_extended',
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target',
}
