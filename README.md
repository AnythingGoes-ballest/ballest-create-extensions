# Create Extensions

Additions to Ballest of Them All's track editor, as a plugin for the
[Ballest plugin manager](https://github.com/AnythingGoes-ballest/ballest-plugin-manager) (host 0.6.0 or newer).

- **Whole-unit placement:** a piece placed from the palette lands on whole-unit coordinates, never fractions.
- **Placement distance** (setting, default 0): places new pieces this far in front of the camera; 0 leaves them where
  the game puts them. Set it with the slider or type an exact value.
- **Snap moved pieces to whole units** (setting, off by default): after a move, selected pieces are rounded to whole
  units.
- **Rotated copy:** a section in the details panel (under transform and paint). Tick X, Y and/or Z, set each angle
  (180 by default) and **create rotated copy** duplicates the selection and turns the copy about its centre. The
  copy is left selected.
- **Tab / Shift+Tab** move between the nine transform boxes (location, rotation, scale; X, Y, Z).
- **Rotate multiple pieces around their centre** (setting, off by default): rotating two or more pieces turns them
  about the centre of the selection instead of the last selected piece.

## Install

In game: footer **plugins** > **open** > **plugins** > **Create Extensions** > **install**. Settings are under
**settings** in the same menu.

## License

MIT
