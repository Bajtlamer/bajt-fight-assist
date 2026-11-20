-- Bajt's Fight Assist: Hunter module.
-- The addon vararg table is private to each addon, so the shared core is reached through its global.
local BFA = _G.BajtFightAssist

BFA:RegisterModule("Hunter", {
    apiVersion = 1,
    -- Spell probes for range. primary = the attack the state is judged against (first known wins).
    -- Melee spells are deliberately not probed: their range check reported "in range" at any distance on this client.
    ranged = {
        { id = 75, primary = true, fmin = 5, fmax = 35 },   -- Auto Shot
        { id = 3044, primary = true, fmin = 5, fmax = 35 }, -- Arcane Shot
        { id = 1978, primary = true, fmin = 5, fmax = 35 }, -- Serpent Sting
        { id = 5116, fmin = 5, fmax = 35 },                 -- Concussive Shot
        { id = 1130, fmin = 0, fmax = 100 },                -- Hunter's Mark
        { id = 1513 },                                      -- Scare Beast
        { id = 19503 },                                     -- Scatter Shot
        { id = 20736 },                                     -- Distracting Shot
    },
    indicators = {},
})
