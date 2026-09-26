// Create Extensions: additions to Ballest's track editor.
//
//   * Placing a piece from the palette puts it on whole-unit coordinates (never fractions), optionally further in
//     front of the camera (the Placement distance setting; 0 leaves it where the game puts it). The editor's gizmo
//     follows the piece there.
//   * "Snap moved pieces to whole units" (a setting, off by default) rounds selected pieces after they are moved.
//   * A "rotated copy" section in the details panel, under transform: tick X, Y and/or Z, set each angle (180 by
//     default) and "create rotated copy" duplicates the selection and turns the copy about its centre.
//   * Tab and Shift+Tab move between the transform boxes (location, rotation, scale; X, Y, Z).
//   * A rotate button in the editor's toolbar, after the world/local toggle, with a dropdown for how two or more
//     pieces rotate: default (the editor's own, about the last selected piece), center (about the middle of the
//     selection) or mirrored (each piece turns in place, the two sides of the middle opposite ways).
//   * Shift+click or Ctrl+click on a selected piece deselects it (the game's own clicks only ever add).
//   * Groups: G groups the selected pieces, U ungroups them (both listed in the editor's key list). Clicking any
//     piece of a group selects the whole group; Alt+click selects just that piece. Groups are saved per map in this
//     plugin's storage (the map file is not changed) and found again by each piece's kind and position.

[Setting name="Placement distance" min=0 max=2000 description="How far in front of the camera new pieces are placed (0: where the game puts them)"]
int PlacementDistance = 0;

[Setting name="Snap moved pieces to whole units" description="After a move, selected pieces are rounded to whole units"]
bool SnapMoves = false;

UI::Window@ section;
array<UI::CheckBox@> axisBoxes;
array<UI::TextInput@> angleBoxes;
UI::Button@ copyButton;
int copyRequested = 0;           // frames until the angles typed in the boxes are read (they are submitted first)

UI::Window@ toast;               // a short message after grouping
UI::Text@ toastText;
double toastUntil = 0;

const array<string> ROTATE_OPTIONS = {"default", "center", "mirrored"};
int rotateChoice = -1;           // the toolbar dropdown
int rotateMode = 0;

void Main()
{
    //   rotated copy
    //   [x] X [180]   [ ] Y [180]   [ ] Z [180]
    //   [create rotated copy]
    @section = UI::CreateWindow();
    section.DockInEditorDetails();
    section.SetBackground(0, 0, 0, 0);
    section.AddText("rotated copy", 18).SetColor(0.7f, 0.7f, 0.75f, 1);
    section.NewRow();
    // Each axis label in its colour on the rotation gizmo (Unreal's axis colours, linear): X red, Y green, Z blue.
    array<string> axes = {"X", "Y", "Z"};
    array<float> red = {0.594f, 0.1349f, 0.0251f};
    array<float> green = {0.0197f, 0.3959f, 0.207f};
    array<float> blue = {0, 0, 0.85f};
    for (uint i = 0; i < axes.length(); i++)
    {
        UI::CheckBox@ box = section.AddCheckBox(axes[i], 16);
        box.SetColor(red[i], green[i], blue[i], 1);
        box.checked = i == 2;               // Z is the usual one: a copy turned around on the ground
        axisBoxes.insertLast(box);
        UI::TextInput@ angle = section.AddTextInput(56, "180", 16);
        angle.clearOnSubmit = false;
        angle.value = "180";
        angleBoxes.insertLast(angle);
    }
    section.NewRow();
    @copyButton = section.AddButton("create rotated copy");

    @toast = UI::CreateWindow();
    toast.SetAnchor(0.5f, 1.0f);
    toast.SetPivot(0.5f, 1.0f);
    toast.SetOffset(0, -110);
    @toastText = toast.AddText("", 16);
    toast.visible = false;

    // 0.2's "Rotate multiple pieces around their centre" setting becomes the dropdown's "center".
    string oldSetting = Storage::Get("setting.RotateAroundCenter", "false") == "true" ? "1" : "0";
    rotateMode = int(parseInt(Storage::Get("rotateMode", oldSetting)));
    if (rotateMode < 0 || rotateMode >= int(ROTATE_OPTIONS.length()))
        rotateMode = 0;
    rotateChoice = Editor::AddToolbarChoice("/Game/Art/UI/Textures/Editor/t_rotateIcon.t_rotateIcon", ROTATE_OPTIONS, rotateMode);
    Editor::SetRotateMode(Editor::RotateMode(rotateMode));

    string folder = Plugins::Folder();
    Editor::AddHotkey(folder + "keyboard_g.png", "group");
    Editor::AddHotkey(folder + "keyboard_u.png", "ungroup");
    Editor::AddHotkey("/Game/Art/UI/Textures/KeyboardMouse/keyboard_alt.keyboard_alt", "select one piece",
                      "/Game/Art/UI/Textures/KeyboardMouse/mouse_left.mouse_left");
    Log::Info("create extensions ready");
}

void Toast(const string &in message)
{
    toastText.text = message;
    toast.visible = true;
    toastUntil = Host::Time() + 2;
    Log::Info(message);
}

double Round(double v)
{
    return double(int64(v >= 0 ? v + 0.5 : v - 0.5));
}

bool Whole(double v)
{
    double r = Round(v);
    return r - v < 0.0001 && v - r < 0.0001;
}

double Abs(double v)
{
    return v < 0 ? -v : v;
}

bool Contains(const array<int>@ list, int value)
{
    return list.find(value) >= 0;
}

// New pieces from the palette: further in front of the camera if asked, then onto whole units. The editor keeps its
// own copy of where the selection is (the gizmo), so a moved piece that is selected is selected again.
void PlaceNewPieces()
{
    array<int>@ placed = Editor::Placed();
    if (placed.length() == 0)
        return;
    double fx, fy, fz;
    Editor::ViewForward(fx, fy, fz);
    for (uint i = 0; i < placed.length(); i++)
    {
        double x, y, z;
        if (!Editor::GetLocation(placed[i], x, y, z))
            continue;
        x += fx * PlacementDistance;
        y += fy * PlacementDistance;
        z += fz * PlacementDistance;
        Editor::SetLocation(placed[i], Round(x), Round(y), Round(z));
    }
    array<int>@ selection = Editor::Selection();
    for (uint i = 0; i < placed.length(); i++)
        if (Contains(selection, placed[i]))
        {
            Editor::Select(selection);
            break;
        }
}

// Once a move has finished (the mouse is up), selected pieces off whole units are rounded.
void SnapSelection()
{
    if (!SnapMoves || Input::Down(Input::MouseLeft))
        return;
    array<int>@ selection = Editor::Selection();
    bool changed = false;
    for (uint i = 0; i < selection.length(); i++)
    {
        double x, y, z;
        if (!Editor::GetLocation(selection[i], x, y, z) || (Whole(x) && Whole(y) && Whole(z)))
            continue;
        Editor::SetLocation(selection[i], Round(x), Round(y), Round(z));
        changed = true;
    }
    if (changed)
        Editor::Select(selection);          // the editor's own pivot follows the pieces
}

double Angle(uint axis)
{
    if (!axisBoxes[axis].checked)
        return 0;
    string text = angleBoxes[axis].text;
    return text == "" ? 180 : parseFloat(text);
}

void CreateRotatedCopy()
{
    array<int>@ copies = Editor::DuplicateSelection();
    if (copies.length() == 0)
    {
        Log::Warn("nothing selected to copy");
        return;
    }
    double cx = 0, cy = 0, cz = 0;
    for (uint i = 0; i < copies.length(); i++)
    {
        double x, y, z;
        Editor::GetLocation(copies[i], x, y, z);
        cx += x / copies.length();
        cy += y / copies.length();
        cz += z / copies.length();
    }
    Editor::RotatePieces(copies, cx, cy, cz, Angle(0), Angle(1), Angle(2));
    Editor::Select(copies);
    Log::Info("rotated copy of " + copies.length() + " piece(s) by " + Angle(0) + ", " + Angle(1) + ", " + Angle(2));
}

// --- rotate mode -------------------------------------------------------------------------------------------------------
void FollowRotateChoice()
{
    int chosen = Editor::ToolbarChoice(rotateChoice);
    if (chosen < 0 || chosen == rotateMode)
        return;
    rotateMode = chosen;
    Editor::SetRotateMode(Editor::RotateMode(rotateMode));
    Storage::Set("rotateMode", "" + rotateMode);
    Log::Info("rotate: " + ROTATE_OPTIONS[rotateMode]);
}

// --- groups ------------------------------------------------------------------------------------------------------------
// A group is its pieces (editor ids, which only live while the map is open) with each one's kind, to notice an id that
// has come to mean another piece. Saved as "kind x y z;kind x y z|..." under "groups:<map>".
class Group
{
    array<int> ids;
    array<string> kinds;
}
array<Group@> groups;
string groupsMap = "";           // the map the groups belong to ("" while the editor is closed)
array<string> unresolved;        // saved groups whose pieces have not been found (yet): kept as saved
double resolveUntil = 0;         // keep looking for them until then (pieces arrive while the map loads)
double nextResolve = 0;
string savedText = "";
double nextSaveCheck = 0;
array<int> singles;              // picked alone with Alt: their groups are not completed around them
array<int> lastSelection;

int GroupOf(int piece)
{
    for (uint g = 0; g < groups.length(); g++)
        if (Contains(groups[g].ids, piece))
            return int(g);
    return -1;
}

string MapKey()
{
    string map = Editor::MapName();
    return "groups:" + (map == "" ? "(unsaved)" : map);
}

string Fixed(double v)
{
    return formatFloat(Round(v * 10) / 10, "", 0, 1);
}

string Describe(const Group@ g)
{
    array<string> members;
    for (uint i = 0; i < g.ids.length(); i++)
    {
        double x, y, z;
        Editor::GetLocation(g.ids[i], x, y, z);
        members.insertLast(g.kinds[i] + " " + Fixed(x) + " " + Fixed(y) + " " + Fixed(z));
    }
    return join(members, ";");
}

string GroupsText()
{
    array<string> parts;
    for (uint g = 0; g < groups.length(); g++)
        parts.insertLast(Describe(groups[g]));
    for (uint u = 0; u < unresolved.length(); u++)
        parts.insertLast(unresolved[u]);
    return join(parts, "|");
}

void SaveGroups()
{
    string text = GroupsText();
    if (text == savedText)
        return;
    Storage::Set(groupsMap, text);
    savedText = text;
}

// A saved group whose every piece is on the map (same kind, within a unit of where it was saved): made a group again.
bool Resolve(const string &in saved, const array<int>@ pieces, array<int>@ taken)
{
    array<string>@ members = saved.split(";");
    Group g;
    for (uint m = 0; m < members.length(); m++)
    {
        array<string>@ f = members[m].split(" ");
        if (f.length() != 4)
            return false;
        double sx = parseFloat(f[1]), sy = parseFloat(f[2]), sz = parseFloat(f[3]);
        int found = -1;
        for (uint p = 0; p < pieces.length() && found < 0; p++)
        {
            if (Contains(taken, pieces[p]) || Contains(g.ids, pieces[p]) || Editor::PieceClass(pieces[p]) != f[0])
                continue;
            double x, y, z;
            Editor::GetLocation(pieces[p], x, y, z);
            if (Abs(x - sx) <= 1 && Abs(y - sy) <= 1 && Abs(z - sz) <= 1)
                found = pieces[p];
        }
        if (found < 0)
            return false;
        g.ids.insertLast(found);
        g.kinds.insertLast(f[0]);
    }
    if (g.ids.length() < 2)
        return false;
    for (uint i = 0; i < g.ids.length(); i++)
        taken.insertLast(g.ids[i]);
    groups.insertLast(g);
    return true;
}

void ResolveSaved()
{
    if (unresolved.length() == 0 || Host::Time() < nextResolve)
        return;
    nextResolve = Host::Time() + 1;
    array<int>@ pieces = Editor::Pieces();
    array<int> taken;
    for (uint g = 0; g < groups.length(); g++)
        for (uint i = 0; i < groups[g].ids.length(); i++)
            taken.insertLast(groups[g].ids[i]);
    for (int u = int(unresolved.length()) - 1; u >= 0; u--)
        if (Resolve(unresolved[u], pieces, taken))
            unresolved.removeAt(u);
    if (Host::Time() > resolveUntil && unresolved.length() > 0)
    {
        Log::Warn(unresolved.length() + " saved group(s) of " + groupsMap + " not found on the map; kept in storage");
        nextResolve = 1e300;                // stop looking; they stay saved in case the pieces come back
    }
}

void OpenGroups()
{
    groupsMap = MapKey();
    groups.resize(0);
    unresolved.resize(0);
    singles.resize(0);
    savedText = Storage::Get(groupsMap, "");
    if (savedText != "")
    {
        array<string>@ saved = savedText.split("|");
        for (uint i = 0; i < saved.length(); i++)
            unresolved.insertLast(saved[i]);
    }
    resolveUntil = Host::Time() + 15;
    nextResolve = 0;
}

// Pieces that were deleted, or whose id now means another piece, leave their group; a group of one is no group.
void DropMissing()
{
    array<int>@ pieces = Editor::Pieces();
    bool changed = false;
    for (int g = int(groups.length()) - 1; g >= 0; g--)
    {
        Group@ group = groups[g];
        for (int i = int(group.ids.length()) - 1; i >= 0; i--)
            if (!Contains(pieces, group.ids[i]) || Editor::PieceClass(group.ids[i]) != group.kinds[i])
            {
                group.ids.removeAt(i);
                group.kinds.removeAt(i);
                changed = true;
            }
        if (group.ids.length() < 2)
        {
            groups.removeAt(g);
            changed = true;
        }
    }
    if (changed)
        SaveGroups();
}

void AddGroupTo(array<int>@ selection, int g)
{
    for (uint i = 0; i < groups[g].ids.length(); i++)
        if (!Contains(selection, groups[g].ids[i]))
            selection.insertLast(groups[g].ids[i]);
}

void RemoveGroupFrom(array<int>@ selection, int g)
{
    for (uint i = 0; i < groups[g].ids.length(); i++)
    {
        int at = selection.find(groups[g].ids[i]);
        if (at >= 0)
            selection.removeAt(at);
    }
}

// Clicks on the world, as the editor handled them: a grouped piece brings its group; Shift/Ctrl on a selected piece
// takes it (and its group) out again; Alt works on the one piece only.
void HandleClicks()
{
    int piece, flags;
    bool wasSelected;
    while (Editor::NextClick(piece, flags, wasSelected))
    {
        if ((flags & Editor::ClickOnGizmo) != 0)
            continue;                       // a drag of the gizmo, not a pick
        bool alt = (flags & Editor::ClickAlt) != 0;
        bool adding = (flags & (Editor::ClickShift | Editor::ClickCtrl)) != 0;
        array<int>@ selection = Editor::Selection();
        if (piece < 0)
            continue;
        int g = GroupOf(piece);
        if (alt)
        {
            if (!adding)
                selection.resize(0);
            int at = selection.find(piece);
            if (adding && wasSelected && at >= 0)
                selection.removeAt(at);
            else if (at < 0)
                selection.insertLast(piece);
            if (!Contains(singles, piece))
                singles.insertLast(piece);
        }
        else if (adding && wasSelected)
        {
            int at = selection.find(piece);
            if (at >= 0)
                selection.removeAt(at);
            if (g >= 0)
                RemoveGroupFrom(selection, g);
        }
        else if (g >= 0)
        {
            AddGroupTo(selection, g);
        }
        if (!alt && g >= 0)
            for (uint i = 0; i < groups[g].ids.length(); i++)
            {
                int s = singles.find(groups[g].ids[i]);
                if (s >= 0)
                    singles.removeAt(s);
            }
        // Only when it changes: selecting again while the button is still down ends the drag the press began (the
        // gizmo is bound to the selection), so pieces could not be moved (reported after the game's 2026-09-25 update).
        if (!SameSet(selection, Editor::Selection()))
            Editor::Select(selection);
    }
}

bool SameSet(const array<int>@ a, const array<int>@ b)
{
    if (a.length() != b.length())
        return false;
    for (uint i = 0; i < a.length(); i++)
        if (!Contains(b, a[i]))
            return false;
    return true;
}

// Selections made other ways (the drag box, select all, undo) take whole groups too.
void CompleteGroups()
{
    array<int>@ selection = Editor::Selection();
    for (int s = int(singles.length()) - 1; s >= 0; s--)
        if (!Contains(selection, singles[s]))
            singles.removeAt(s);
    bool same = selection.length() == lastSelection.length();
    for (uint i = 0; same && i < selection.length(); i++)
        same = selection[i] == lastSelection[i];
    if (same)
        return;
    uint before = selection.length();
    for (uint g = 0; g < groups.length(); g++)
    {
        bool touched = false, single = false;
        for (uint i = 0; i < groups[g].ids.length(); i++)
        {
            touched = touched || Contains(selection, groups[g].ids[i]);
            single = single || Contains(singles, groups[g].ids[i]);
        }
        if (touched && !single)
            AddGroupTo(selection, g);
    }
    if (selection.length() != before)
        Editor::Select(selection);
    lastSelection = Editor::Selection();
}

void GroupSelection()
{
    array<int>@ selection = Editor::Selection();
    if (selection.length() < 2)
    {
        Toast("select two or more pieces to group");
        return;
    }
    // A piece is in one group only: grouping pieces takes them out of the groups they were in.
    for (int g = int(groups.length()) - 1; g >= 0; g--)
    {
        for (int i = int(groups[g].ids.length()) - 1; i >= 0; i--)
            if (Contains(selection, groups[g].ids[i]))
            {
                groups[g].ids.removeAt(i);
                groups[g].kinds.removeAt(i);
            }
        if (groups[g].ids.length() < 2)
            groups.removeAt(g);
    }
    Group g;
    for (uint i = 0; i < selection.length(); i++)
    {
        g.ids.insertLast(selection[i]);
        g.kinds.insertLast(Editor::PieceClass(selection[i]));
    }
    groups.insertLast(g);
    singles.resize(0);
    SaveGroups();
    Toast("grouped " + selection.length() + " pieces");
}

void UngroupSelection()
{
    array<int>@ selection = Editor::Selection();
    int removed = 0;
    for (int g = int(groups.length()) - 1; g >= 0; g--)
    {
        bool touched = false;
        for (uint i = 0; i < selection.length() && !touched; i++)
            touched = Contains(groups[g].ids, selection[i]);
        if (touched)
        {
            groups.removeAt(g);
            removed++;
        }
    }
    SaveGroups();
    Toast(removed == 0 ? "no group selected" : "ungrouped " + removed + (removed == 1 ? " group" : " groups"));
}

void KeepGroups()
{
    if (MapKey() != groupsMap)
    {
        // A map that was just saved for the first time takes its groups along from "(unsaved)".
        string previous = groupsMap;
        bool firstSave = previous == "groups:(unsaved)" && groups.length() > 0;
        if (firstSave)
        {
            groupsMap = MapKey();
            savedText = "";
            SaveGroups();
            Storage::Set(previous, "");
        }
        else
        {
            OpenGroups();
        }
    }
    ResolveSaved();
    DropMissing();
    HandleClicks();
    CompleteGroups();
    if ((Input::Pressed(Input::G) || Input::Pressed(Input::U)) && !Editor::Typing())
    {
        if (Input::Pressed(Input::G))
            GroupSelection();
        else
            UngroupSelection();
    }
    // Moved pieces: their saved positions follow once the mouse is up.
    if (Host::Time() >= nextSaveCheck && !Input::Down(Input::MouseLeft))
    {
        nextSaveCheck = Host::Time() + 1;
        SaveGroups();
    }
}

void Update(float dt)
{
    bool open = Editor::IsOpen();
    section.visible = open;
    Editor::SetTabCycling(open);
    if (toast.visible && (!open || Host::Time() > toastUntil))
        toast.visible = false;
    if (!open)
    {
        groupsMap = "";                     // pieces get new ids when the editor opens again
        groups.resize(0);
        lastSelection.resize(0);
        return;
    }
    PlaceNewPieces();
    SnapSelection();
    FollowRotateChoice();
    KeepGroups();

    // The angles are read from the boxes as submitted text, so they are submitted first and read a frame later.
    if (copyButton.Clicked())
    {
        for (uint i = 0; i < angleBoxes.length(); i++)
            angleBoxes[i].Submit();
        copyRequested = 2;
    }
    if (copyRequested > 0 && --copyRequested == 0)
        CreateRotatedCopy();
}
