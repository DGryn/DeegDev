# gryn_gruppe

A Gruppe 6 cash-in-transit job for ESX Legacy, built on ox_lib, ox_inventory, ox_target and oxmysql. It has a criminal side too: other players can thermite a job van and fence what they take.

- **Three tasks:** bank pickup and ATM run, multi-bank collection, and private crate delivery.
- **Groups:** work solo or in a group of up to 4. Pay and XP are split equally, with +10% per extra member.
- **Progression:** 25 levels, an unlock table in `config.lua`, reputation, a daily reward and a cooldown.
- **NUI:** a tablet with Overview, Progress and Jobs pages. The same NUI draws the black market menu, the invite prompt and the thermite minigame.

## Install

1. Copy `gryn_gruppe/` into your resources folder.
2. Add the items from `install/items.lua` to `ox_inventory/data/items.lua`. Put `g6_thermite.png`, `g6_moneybag.png` and `g6_crate.png` in `ox_inventory/web/images/`.
3. The database table is created on start. `install/gryn_gruppe.sql` is the same table if you prefer to run it yourself.
4. Add `ensure gryn_gruppe` to `server.cfg`, after `es_extended`, `oxmysql`, `ox_lib`, `ox_inventory` and `ox_target`.
5. Replace the placeholder coordinates in `config.lua`: the HQ, banks, ATMs, crate pickups, drop-offs and the black market NPC.

## Files

| Path | What it does |
| --- | --- |
| `config.lua` | Every tunable value |
| `server/main.lua` | Shared helpers, database table, progress cache, logging |
| `server/progression.lua` | XP curve, unlock table, reputation, cooldown, daily reward, tablet data |
| `server/groups.lua` | Groups, invites, kicks, leaving, disconnect and death |
| `server/jobs.lua` | Job engine: start, steps, payout, failure, van and timer watchdog |
| `server/robbery.lua` | Thermite checks, loot, thief cooldown, `SendDispatchAlert` placeholder |
| `server/blackmarket.lua` | Buy, sell, and open-it-yourself payouts |
| `client/main.lua` | HQ NPC, tablet open/close, NUI callbacks, invites |
| `client/jobs.lua` | Blips, ox_target zones, carrying, van props, drop-off NPC, timer |
| `client/robbery.lua` | Thermite option, `StartThermiteMinigame`, door blast, loot |
| `client/blackmarket.lua` | Black market NPC and the `openStolen` item export |
| `web/` | NUI (`index.html`, `style.css`, `app.js`) |

To preview the NUI in a normal browser, open `web/index.html?demo=overview` (or `progress`, `jobs`, `job`, `market`, `invite`, `minigame`).

## How the numbers work

- **Pay:** items × `ratePerItem` × difficulty multiplier, × (1 + 10% per extra member), split equally. Each member's share then gets their own level money bonus plus reputation bonus.
- **XP:** the same, using `xpPerItem` and the level XP bonus.
- **Levels:** XP to go from level n to n+1 = `floor(500 × 1.2^(n-1))`.
- **Deposit:** taken from the leader's bank at start. It is refunded to the leader on completion and lost on failure.
- **Cooldown:** 40 minutes, minus the level's cooldown reduction. It starts for every member when the job ends, and for a member who leaves when they leave.

## Test checklists

Work through the parts in order. Set `Config.Debug = true` to see ox_target zones.

### 1. Foundation (manifest, config, database, progression, items)

- [ ] The resource starts with no errors, and the `gryn_gruppe_players` table exists.
- [ ] The three items appear in ox_inventory with their images.
- [ ] Opening the tablet creates a row for your identifier.
- [ ] Set `xp` in the database to 3000 and reopen the tablet. You should be level 5 and the Jobs page should unlock Multi-bank.

### 2. NUI tablet, NPC, groups and invites

- [ ] The HQ NPC spawns with a blip, and ox_target opens the tablet. ESC closes it and gives back control.
- [ ] Overview shows your level, XP bar, bonuses, jobs completed, XP today and money today.
- [ ] Claim the daily reward: you get cash and XP, and the button changes to a countdown.
- [ ] The Progress page shows one card per entry in `Config.Unlocks`, marked Unlocked, Current or Locked.
- [ ] Jobs: locked tasks show the level they need.
- [ ] Invite a nearby player (within 20 m). They see Accept and Decline, and the invite expires after 60 s.
- [ ] Kick removes the member. Leave works. A non-leader cannot press Start.

### 3. Job engine and Task 1

- [ ] Start takes the deposit, spawns the Stockade at HQ and blips the bank.
- [ ] Bags: 3 solo, 4 with two players, up to 6.
- [ ] Collect a bag (progress bar, prop in hand, no sprint or vehicles), then load it at the rear of the van. A prop appears inside the van.
- [ ] A player outside the job sees none of the options.
- [ ] After the last bag is loaded, one ATM is blipped per bag. Take a bag from the van and refill each ATM.
- [ ] Park within 12 m of the return point and use Return Stockade. Every member is paid, the leader gets the deposit back, and cooldowns start.
- [ ] Destroy the van mid-job: the job fails, the deposit is lost and cooldowns start.
- [ ] Disconnect while carrying a bag: the bag goes back to the bank and the next member becomes leader.

### 4. Tasks 2 and 3

- [ ] Multi-bank: 3 to 5 banks are blipped and can be done in any order. Bags go into the van, then from the van to the HQ hand-in, one at a time. Return the van to finish.
- [ ] Crates: 3 to 5 pickups with one crate each, using the box-carry animation. When all crates are loaded, the drop-off NPC is blipped. Hand over every crate, then return to HQ.
- [ ] The crate timer shows at the top of the screen. Letting it run out fails the job.

### 5. Robbery, minigame and dispatch

- [ ] Without thermite, or with fewer than 2 police online, the option fails with a message.
- [ ] A job member cannot thermite their own van.
- [ ] Starting the attempt prints the dispatch line in the server console.
- [ ] Minigame pass: the thermite is used up, the rear doors blow off, the group's job fails, and Take loot gives one `g6_moneybag` or `g6_crate` per item that was in the van, with a value in its metadata.
- [ ] Minigame fail: the thermite is used up and nothing opens. Burn damage applies only if `burnDamage > 0`.
- [ ] Thermite is blocked for 25 minutes after an attempt.

### 6. Black market

- [ ] The NPC opens the menu. Buy takes clean or dirty cash, as configured.
- [ ] Sell pays 70% of the stored value in clean cash.
- [ ] Using a stolen item from the inventory runs a progress bar. It then pays 130% in `black_money`, or has a 25% chance to be inked and pay nothing.

## Decisions made where the spec left room

- **Task 3 timer:** it starts when the job starts, as the spec says. The open doc comment asks whether it should start after the last crate is loaded instead. If so, `deadline` in `server/jobs.lua` would be set in `advance()` instead.
- **Level checks:** a task's level lock is checked against the leader's level, since only the leader picks the task.
- **Deposit refund:** the deposit goes back to the player who paid it, if they are still in the group at completion. If they left, it is lost.
- **Death:** dying only removes a player while their group is on a job. This uses ESX's `esx:onPlayerDeath` event.
- **Joining mid-job:** nobody can join a group while it is on a job.
- **"Special items made available at the NPC":** an item listed in a level's `items` can only be bought at the black market from that level. Items can also have a `rep` requirement.
- **Stolen item values:** these are set in `Config.Robbery.lootValue` per bag or crate. They are not tied to the job's pay.
- **Van props:** props inside the van are local, so only the job's members see them. Robbers use the loot count stored on the van.
- **Explosion:** the door blast uses `AddExplosion` with 0 damage and is fired once, by the client that owns the van.
