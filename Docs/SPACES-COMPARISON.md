# Local Spaces comparison

Two explicitly named preview apps use different bundle IDs, settings, website
containers and sample sessions. Neither reads the installed browser profile.
The installed release and GitHub feed are not replaced by this comparison.

- Moon Minimal Preview: automatic left-swipe creation, right-swipe return,
  no setup form; discreet name and dots only with multiple spaces.
- Moon Zen Preview: native workspace heading with management menu, 30-point
  icon strip, explicit new-workspace popover, and cyclic workspace navigation.
- Both: Rename and Delete in each space's context menu; Option-Command-Delete
  while hovering targets that space, asks for confirmation and protects home.

The Zen preview ports workspace navigation and layout from Zen Browser revision
37513f03c5dcb0eb2520c839e3870b59cdc8aefe, `ZenSpaceManager.mjs` and
`zen-workspaces.css`. It does not claim Firefox-container, sync, or library
feature parity. The adapted Swift source is MPL-2.0; see THIRD_PARTY_NOTICES.md.

The two intentional previews remain available for the user's comparison.
Remove them after a design is selected, using the project's install hygiene.

Decision: retain the minimal Moon UX for 0.4.14 and retire both comparison app bundles after installation. The Zen proposal source is retained for reference only.
