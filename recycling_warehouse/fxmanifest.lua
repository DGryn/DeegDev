fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'recycling_warehouse'
description 'Warehouse recycling job: carry boxes to the skip, trade recycle boxes for materials.'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua', -- enables lib.* in every script
    'config.lua',
}

client_script 'client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- database (XP, stats, daily goals)
    'server.lua',
}

-- Custom screens (laptop + trader)
ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/*.png', -- optional logo (Config.UI.logo)
}

dependencies {
    '/onesync',     -- the server reads player positions for its distance checks
    'es_extended',
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'ox_target',
}
