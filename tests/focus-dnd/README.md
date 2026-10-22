# Live integration tests (DO NOT run automatically)

These tests interact with the live Focus Timer Flatpak, the active D-Bus session,
Plasma DND, and the running `focus-dnd.service`. 

**Safety requirements:**
- Run only with explicit opt-in and user awareness
- Preserve the user's initial DND state and timer settings
- Restore them safely on exit
- Fail safely if restoration cannot be verified
- Never run as part of packaging/CI

They are provided for manual verification only.
