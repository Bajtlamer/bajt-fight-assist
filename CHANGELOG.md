# Changelog

## First release (Core 0.4.6, Hunter 0.4.5, Rogue 0.3.4)

Bajt's Fight Assist for WoW Forever (interface 16001): a core addon plus small class modules that show fight-relevant state next to your target and its nameplate.

Core 0.4.6
- Range badge with estimated distance brackets, indicator rows on the target frame and nameplate, `/bfa` settings window, minimap button, diagnostic log in SavedVariables.
- Addon list icon.

Hunter 0.4.5
- Ranged attack range, ammo, Hunter's Mark, aspect and pet indicators.
- Addon list icon.

Rogue 0.3.4
- THROW IN RANGE badge while Throw can be used, green MELEE ATTACK inside melee reach.
- Poison timers for both weapons, combo points coloured by count, Backstab readiness icon (shown only when Backstab can be used with a dagger in the main hand).
- Poison timers, Backstab and combo points are also shown next to the nameplate.
- Addon list icon.

Limits: standing behind the target cannot be read from the client, so Backstab readiness covers weapon, reach, energy and usability only. Combo point colours are still being tuned.

Install: unzip BajtFightAssist plus the class module you play into `Interface/AddOns`. Modules require the core.
