# Bajt's Fight Assist

Core addon plus small class modules that show fight-relevant state next to your target (WoW Forever, Interface 16001).

- `BajtFightAssist`: range engine, badge, indicator row, log, `/bfa` commands, module loader.
- `BajtFightAssist_Hunter`: Hunter module (ranged attack range). More modules and indicators follow.

Rules: show only what is known to be true and current (unknown is hidden), and write all diagnostic data to the log in SavedVariables.

Tools (`tools/`): `check.py` (TOC rules, Lua compilation, offline range tests), `package.py` (zip per addon), `install.py --addons-dir DIR [--apply]`.
Design and plan: see `plan-bajt-fight-assist.md` in the original `target-ranger` repository.
