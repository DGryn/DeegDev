# recycling_warehouse

A recycling job for ESX Legacy that uses ox_lib, ox_inventory and ox_target. It pays out in items only, with no cash.

1. Enter the medium cargo warehouse.
2. Open the laptop and start a shift. The laptop shows your level, XP, perks, today's 3 goals, today's trade rates and your lifetime stats.
3. Carry boxes one at a time from the highlighted pickup prop to the skip, which glows while you carry.
   - Each box gives at least 1 **recycle box** and some XP.
   - Sometimes a quick skill check appears. Hitting it gives bonus boxes and bonus XP.
   - Rarely, a box contains something unusual (a "rare find").
4. Trade recycle boxes with the trader for materials. Rates change every day, and the trader screen shows which material is good value today.

Levels unlock perks: extra boxes per delivery, more materials per trade, and a higher rare-find chance.

## Installation

1. Copy the `recycling_warehouse` folder into your `resources` folder.
2. Open `install/ox_inventory_items.lua` and paste its entries into `ox_inventory/data/items.lua`, inside the `return { ... }` table. If you already have any of those item names, skip that entry.
   - The items reuse images that ship with ox_inventory, so you don't need new image files.
3. Add this line to `server.cfg` **after** `oxmysql`, `es_extended`, `ox_lib`, `ox_inventory` and `ox_target`:
   ```
   ensure recycling_warehouse
   ```
4. OneSync must be on. It is the default on current servers.
5. Restart the server. ox_inventory only reads new items on startup.
6. Fill in the placeholders in `config.lua` (see below), then restart the resource:
   ```
   restart recycling_warehouse
   ```

**Database:** the resource creates its one table (`recycling_warehouse_players`) on start. If you'd rather create it yourself, run `install/recycling_warehouse.sql` and set `Config.AutoCreateTable = false`.

**Rare finds:** the example rare-find items (`circuit_board`, `copper_wire`, `gold_watch`) are in the same item file. Swap them in `Config.RareFinds` for items your other jobs use.

## Filling in the placeholders

These values in `config.lua` are marked **PLACEHOLDER**:

- Entrance, `spawnInside`, exit and `spawnOutside`
- The pickup prop positions
- The trader position

### Getting coordinates and headings in-game

The resource includes a helper command. Stand where you want something, face the direction it should face, then type in chat:

```
/rwcoords
```

The command prints `vec4(x, y, z, heading)` to the F8 console and copies it to your clipboard, ready to paste into `config.lua`.

- **Player and ped spots** (`spawnInside`, `spawnOutside`, the trader): paste the value as-is. Your Z is the centre of your body, about 1 m above the floor. The script expects that.
- **Zones** (`Entrance.coords`, `Exit.coords`): these take a `vec3`, so keep the first three numbers and drop the heading.
- **Props** (pickups, skip): stand where the prop should go and paste the value. With `Config.SnapPropsToGround = true` the prop drops onto the floor, so Z doesn't need to be exact.
- **Heading** is the direction you face. 0 = north, 90 = west, 180 = south, 270 = east.

To disable the command, set `Config.CoordsCommand = false`.

### Seeing the interaction zones

Set `Config.Debug = true` and restart the resource. This draws the entrance, exit and laptop zones, and makes the server print every action to its console. Turn it off again when you're done.

### Choosing prop models

You can use any GTA object model for the pickups. Two places to browse them:

- https://forge.plebmasters.de/objects
- https://gta-objects.xyz

If a model name is wrong, F8 shows a warning and that prop is skipped. The rest still works.

## The new features in `config.lua`

| Setting | What it controls |
|---|---|
| `Config.DailyResetHour` | Hour of the server clock when trade rates change and new goals become available |
| `Config.SkillCheck` | Chance of a skill check, its difficulty and keys, and the bonus boxes and XP for a hit |
| `Config.Xp`, `Config.Levels` | XP per box, the XP needed for each level, and each level's perks |
| `Config.Market` | The daily ratings (Great / Normal / Poor value), how much each changes the amount you get, and the most trades allowed in one click |
| `Config.Goals` | How many goals per day and the pool they are picked from (type, target, text, reward) |
| `Config.RareFinds` | The chance per box and the weighted list of items |
| `Config.UI`, `Config.UIText` | The server name, an optional logo, the accent colour, and every word on the two screens |

- **Logo:** put a square PNG in `recycling_warehouse/web/` and set `Config.UI.logo = 'yourlogo.png'`.
- **Screens:** the screen files are plain HTML, CSS and JavaScript in `web/`, with no build step. Colours are at the top of `web/style.css`.
- **Trade rates:** they are worked out from the date, so they stay the same all day for everyone, even after a restart.
- **Goal rewards:** the reward is given the moment a goal is finished. If the inventory is full at that moment, the player gets a **Claim** button on the laptop instead.

## Notes

- **Laptop:** the warehouse interior already has a desk with a laptop, so the script only adds the interaction there. If you see no laptop, set `Config.Laptop.spawnProp = true`.
- **Interior loading:** if another resource already manages this interior (for example an IPL loader), you can set `Config.Interior.loadInterior = false`.
- **`sv_entityLockdown strict`:** if your server uses this setting, set `Config.Carry.networked = false`. The carried box is then visible only to the carrier.
- **Leaving the warehouse** ends the shift, controlled by `Config.Exit.endShiftOnExit`.
- **Dying** while carrying loses the box but keeps the shift. So does getting in a vehicle or leaving the area.

## How cheating is prevented

The server decides everything. The client only sends "I want to do X", plus at most an index number, which the server looks up in `config.lua`.

| Action | The server checks |
|---|---|
| Start shift | Not already on shift, and standing at the laptop |
| Pick up | On shift, not already carrying, it is the one prop the server assigned (random, changes after every delivery), and standing at it |
| Deliver (start) | On shift, carrying a box, and standing at the skip. The **server** rolls whether a skill check happens |
| Deliver (finish) | The same checks again, plus the progress bar time really passed, and room for the boxes. A "hit" only counts if the server asked for a skill check |
| Trade | Standing at the trader, the material exists, a whole number of trades from 1 to `maxTradesAtOnce`, enough recycle boxes, and room for the materials |
| Claim goal | Standing at the laptop, and the goal is finished but not yet claimed |

XP, levels, goal progress and rare finds are all decided on the server. The client never sends an amount of XP or items.

There is one limit: the server can't see the skill-check minigame itself, so a cheat client could always report a hit. It can't make skill checks appear more often (the server rolls that), so the most it gains is the configured bonus on about `chance`% of its deliveries.

For a trade, the cost is removed **first**. If the materials can't be added afterwards, the cost is refunded.

All distance checks use the server's own copy of the player's position, with `Config.Distance.serverTolerance` added for lag.

Job state is wiped when a player disconnects or logs out. A carried box prop is deleted by the server if its owner disconnects.
