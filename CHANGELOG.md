# Changelog

## 1.2.0

- WoW Forever support (Interface 16001) alongside TBC Anniversary. A new compatibility layer wraps the APIs that differ between the classic and modern clients.
- Captures all 180 action slots on clients with eight action bars; older clients keep 120. Profiles move between clients, and slots a client does not have are ignored on load.
- Spells are matched by name through the spellbook when an exact spell ID is not known, which also covers profiles saved on the other client.
- The profile list uses its own scroll bar instead of FauxScrollFrame, which modern clients no longer ship.
- `/bc version` prints the detected client and API generation.

## 1.1.0

- Export and import profiles as text codes, so profiles can move between WoW accounts, PCs, or friends. Export and Import buttons in the window, plus `/bc export <name>` and `/bc import`.
- Codes are checksummed and validated before anything is saved.

## 1.0.1

- CurseForge packaging: exclude artwork from the addon zip, stamp the version from the release tag, add the project ID to the TOC.

## 1.0.0

- Initial release.
- Save all 120 action slots (spells, items, macros) as named, account-wide profiles.
- Load profiles on any character, with fallbacks for spell ranks, bag/equipped items, and missing macros.
- Profile window (`/bc`) plus slash commands for save, load, delete, and list.
