# Tests

Offline checks that run without a game client (Node.js required):

```
cd tests && npm install && npm test
```

- `check-syntax.js` parses every Lua file as Lua 5.1.
- `test-core.js` loads the addon into a mocked WoW API, once shaped like the
  classic client (TBC Anniversary) and once like the modern client (WoW Forever),
  and exercises save, load, rank fallback, macro creation, pets, combat queueing,
  and export/import across the two.
