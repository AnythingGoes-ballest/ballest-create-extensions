# Create Extensions

Additions to Ballest of Them All's track editor, as a plugin for the
[Ballest plugin manager](https://github.com/AnythingGoes-ballest/ballest-plugin-manager) (host 0.10.0 or newer).

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
- **Deselect with Shift/Ctrl+click:** Shift+click or Ctrl+click on a selected piece takes it out of the selection (the
  game's own clicks only add).
- **Groups:** **G** groups the selected pieces, **U** ungroups them (both are in the editor's key list, with Alt+click). Clicking any
  piece of a group selects the whole group; **Alt+click** selects just that one piece. Groups are remembered per map
  by this plugin (the map file isn't changed, so other players see separate pieces), and found again by each piece's
  kind and position.

## Install

In game: footer **plugins** > **browse** > **Create Extensions** > **install**. Its settings are under
**installed** > Create Extensions > **settings**.

## License

MIT
