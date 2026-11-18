# FS25 Not So Easy Developer Controls

Farming Simulator 25 mod. Adds an admin console command that clears the fertilizer state (ground layer) of a field. This lets players spread fertilizer on the same field again, with different products.

## What it does

With a console command, the mod cleans the fertilizer state/layer of the specified field, or of the field the player is standing on.

- Only the fertilizer value is removed. Other spray types (manure, lime, ...) stay untouched.
- Field data such as row orientation is not changed.
- In multiplayer, only admins can run the command. The change is applied on the server.

## Command

Open the developer console and run:

```
nseClearFertilizerState [fieldId]
```

Clear fertilizer on field 12:

```
nseClearFertilizerState 12
```

Clear fertilizer on the field the player is standing on:

```
nseClearFertilizerState
```

## Growth state commands

```
nseGetGrowthState [fieldId]
nseSetGrowthState [fieldId] <state>
```

- `nseGetGrowthState` shows, per crop on the field, which growth states are present and their share (any player).
- `nseSetGrowthState` sets the growth state of the dominant crop (largest area) on the field to `<state>` (a number). Other crops on the field are left alone. Nothing is planted on empty ground. If `<state>` is out of range for the dominant crop, nothing changes. Admin only, applied on the server.
- With one argument to `nseSetGrowthState` it is the state and the field under the player is used.

```
nseGetGrowthState 12
nseSetGrowthState 12 3
nseSetGrowthState 3
```

## Ground type command

```
nseSetGroundType <id>
```

Sets the ground type of the whole field the player is standing on. Admin only, applied on the server. `<id>` is the `FieldGroundType` id:

1 NONE, 2 STUBBLE_TILLAGE, 3 CULTIVATED, 4 SEEDBED, 5 PLOWED, 6 ROLLED_SEEDBED, 7 RIDGE, 8 SOWN, 9 DIRECT_SOWN, 10 PLANTED, 11 RIDGE_SOWN, 12 ROLLER_LINES, 13 HARVEST_READY, 14 HARVEST_READY_OTHER, 15 GRASS, 16 GRASS_CUT

```
nseSetGroundType 3
```

## Why this mod exists

- We ran a fairly realistic multiplayer server where fields get fertilized with multiple passes of fertilizer. Because the fertilizer state was already painted, we needed a way to clear this layer so fertilizer could be spread again.
- The [Easy Development Controls](https://www.farming-simulator.com/mod.php?mod_id=324487&title=fs2025) mod by GtX can achieve the same result, but it updates multiple field properties, for example row orientation.
- RowCropSystem is used in our game, so row orientation must not be lost.
- If a crop was planted with fertilization at the same time, spreading fertilizer on the field was impossible.
