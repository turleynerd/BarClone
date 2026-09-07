# BarClone

Save your action bars as named profiles and load them on any character.
Built for WoW TBC Anniversary (Interface 20506).

## What it saves

All 120 action slots, which covers the main bar, all bar pages, the four
extra bars, and the stance / form / stealth bars. Each slot stores:

- **Spells** by spell ID, plus the name and rank as a fallback.
- **Items** by item ID.
- **Macros** by name, with the icon and body so they can be recreated.

Profiles are account-wide (WTF\Account\<account>\SavedVariables\BarClone.lua),
so a profile saved on one warrior can be loaded on another.

## Usage

Open the window with `/bc` (or `/barclone`).

- Type a name and click **Save New** to capture your current bars.
- Select a profile and click **Load**, or double-click it.
- **Overwrite** replaces the selected profile with your current bars.
- **Rename** renames the selected profile to whatever is in the name box.
- **Delete** removes it.
- **Export** shows a text code for the selected profile. **Import** accepts
  one (see below).

Slash commands do the same without the window:

```
/bc save <name>
/bc load <name>
/bc delete <name>
/bc export <name>
/bc import
/bc list
```

## Sharing across accounts

Profiles are stored per WoW account, so a second account (or a friend) cannot
see them directly. Export and Import bridge that gap:

1. Select a profile and click **Export**. The code is pre-selected; press
   Ctrl+C.
2. On the other account, open BarClone, click **Import**, and press Ctrl+V.
   The code is validated on the spot and the window shows the class and slot
   counts it contains.
3. Adjust the name if you like and click **Import**.

Codes look like `BC1:...:...` and include a checksum, so a partial or mangled
paste is rejected instead of importing garbage. Line breaks or spaces picked
up along the way are ignored.

## Loading on another character

- Spells the character knows are placed by ID. If that exact rank is not
  known (for example a lower level character), the highest known rank of the
  same spell is used instead.
- Items are placed if they are in your bags or equipped.
- Macros are looked up by name. If the macro does not exist and
  "Create macros this character is missing" is enabled, it is created
  (character-specific or account-wide, matching where it originally lived,
  falling back to whichever pool has room).
- Anything that cannot be placed is skipped and listed in chat.

Loading is not possible in combat. If you try, the load runs automatically
when combat ends.

## Options

- **Clear slots that are empty in the profile** (default on): makes your bars
  match the profile exactly. Turn it off to only overwrite the slots the
  profile actually uses.
- **Create macros this character is missing** (default on).
- **Only my class**: filters the profile list. Profiles from other classes can
  still be loaded, but unknown abilities are skipped.

## Compatibility

Works with the default bars and with any bar addon that uses the standard
action slots (Bartender4, Dominos, ElvUI).
