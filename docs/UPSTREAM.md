# Upstream post draft (for Focus Timer)

**Title:** Community integration: Focus Timer + KDE Plasma Do Not Disturb (Flatpak-safe, host-side service)

**Body:**

Hi Focus Timer team,

I've put together a community integration that automatically toggles KDE Plasma's "Do Not Disturb" during focus/pomodoro sessions on Linux with KDE Plasma 6.

**Approach:**
- Host-side Python D-Bus service that observes Focus Timer's session bus API (Option A'). No changes to the app required, and it works with the Focus Timer Flatpak without adding broad Flatpak permissions.
- Strict ownership rules: never clears a user-initiated DND, respects manual toggles, guards against composite inhibition sources.
- Handles KDE's quirks (manual DND flag vs composite inhibition, timestamp format).

**Repository (community-maintained):** [link will be added once published]

**Notes:**
- This is community-maintained and not officially endorsed.
- Would you consider linking to community integrations in the docs/README, or mentioning a workaround for KDE Plasma users? If there's a preferred place/channel for such integrations, I'm happy to follow your guidance.

Thanks!
