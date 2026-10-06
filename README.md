# Create Extensions

Additions to Ballest of Them All's track editor, as a plugin for the
[Ballest plugin manager](https://github.com/AnythingGoes-ballest/ballest-plugin-manager) (host 0.16.1 or newer).

- **Drag to select** (setting, on by default): press on empty space and drag to draw a box; letting go selects every
  piece whose middle is inside it. Pieces show the selection outline while the box covers them. **Shift+drag** or
  **Ctrl+drag** adds them to the pieces already selected. Presses on a piece or the gizmo work as before.
- **Whole-unit placement:** a piece placed from the palette lands on whole-unit coordinates, never fractions.
- **Placement distance** (setting, default 0): places new pieces this far in front of the camera; 0 leaves them where
  the game puts them. Set it with the slider or type an exact value. The move/rotate/scale gizmo goes with the piece.
- **Snap moved pieces to whole units** (setting, off by default): after a move, selected pieces are rounded to whole
  units.
- **Rotated copy:** a section in the details panel (under transform and paint). Tick X, Y and/or Z, set each angle
  (180 by default) and **create rotated copy** duplicates the selection and turns the copy about its centre. The
  copy is left selected.
- **Tab / Shift+Tab** move between the nine transform boxes (location, rotation, scale; X, Y, Z).
- **Rotate modes:** a rotate button in the editor's toolbar, next to the globe, with a dropdown for how two or more
  pieces rotate:
  - **default**: the editor's own, about the last selected piece;
  - **center**: about the middle of the selection;
  - **mirrored**: each piece turns in place, and the pieces on either side of the middle turn opposite ways, as
    mirror images (the side of the last selected piece turns the way you drag).
- **Last run's path** (setting, on by default): during a test run the ball's path is drawn behind it as a see-through
  trail, and stays when you go back to editing, so you can see where the ball went. A new test run, or a restart in
  one, starts a new path. **Path colour** (a hue), **Path thickness** and **Path opacity** (default 25%) are settings.

## Install

In game: footer **plugins** > **browse** > **Create Extensions** > **install**. Its settings are under
**installed** > Create Extensions > **settings**.

## License

MIT

## Removed in 0.8.0

The game's October 6 update added its own grouping (**Ctrl+G**), turned the editor's piece budget off, and made
**Ctrl+click** on a selected piece deselect it, so this plugin's groups (G / U, Alt+click one piece), its **No piece
limit** setting and its Shift/Ctrl+click deselect are gone. Groups saved by earlier versions stay in the plugin's
storage but are no longer used.
