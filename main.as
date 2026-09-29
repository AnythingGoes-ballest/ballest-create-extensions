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
//   * Drag to select (a setting, on by default): pressing on empty space and dragging draws a box, and letting go
//     selects every piece whose middle is inside it; with Shift or Ctrl held they are added to the selection.
//   * Last run's path (a setting, on by default): during a test run the ball's path is drawn behind it as a
//     see-through trail, and stays when you go back to editing, so you can see where the ball went. A new test run,
//     or a restart in one, starts a new path.

[Setting name="Placement distance" min=0 max=2000 description="How far in front of the camera new pieces are placed (0: where the game puts them)"]
int PlacementDistance = 0;

[Setting name="Snap moved pieces to whole units" description="After a move, selected pieces are rounded to whole units"]
bool SnapMoves = false;

[Setting name="Drag to select" description="Drag on empty space to select every piece inside the box (Shift or Ctrl adds them)"]
bool DragSelect = true;

[Setting name="Last run's path" description="Draw the ball's path during a test run and keep it while you edit, until the next test run"]
bool ShowPath = true;

[Setting name="Path colour" min=0 max=360 description="The path's colour, as a hue (0 red, 120 green, 200 blue)"]
int PathHue = 190;

[Setting name="Path thickness" min=1 max=20 description="How thick the path is (cm)"]
float PathThickness = 5;

[Setting name="Path opacity" min=5 max=100 description="How see-through the path is (percent opaque)"]
int PathOpacity = 25;

// --- last run's path ---
// The ball's positions this attempt (x, y, z each), a point every PATH_STEP cm; drawn as tubes of PATH_CHUNK points
// each, the last (still growing) one drawn again at most every PATH_REDRAW seconds.
const double PATH_STEP = 25, PATH_JUMP = 1500, PATH_REDRAW = 0.1;
const int PATH_CHUNK = 40;
array<double> pathPoints;
array<int> pathTubes;                    // Draw ids of the finished chunks
int pathLive = 0;                        // the growing chunk's Draw id
int pathDrawnPoints = 0;                 // points in the finished chunks' tubes
double pathRedrawAt = 0;
bool pathTesting = false;
int pathRestarts = -1;
int pathMap = -1;                        // the map the tubes were drawn on (they go with it)
string pathLook;                         // the settings they were drawn with

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
    Editor::AddHotkey("/Game/Art/UI/Textures/KeyboardMouse/mouse_left.mouse_left", "drag: select in a box");

    // The box: a faint fill and four edges, placed over the viewport while dragging.
    for (uint i = 0; i < 5; i++)
    {
        UI::Window@ part = UI::CreateWindow();
        if (i == 0)
            part.SetBackground(0.25f, 0.55f, 1.0f, 0.12f);
        else
            part.SetBackground(0.35f, 0.65f, 1.0f, 0.9f);
        part.SetRect(0, 0, 1, 1);
        part.visible = false;
        boxParts.insertLast(part);
    }
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
        {
            // A press on empty space: the start of a drag to select, unless the button is already up.
            if (DragSelect && !alt)
                ArmBox(adding);
            continue;
        }
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

// --- drag to select --------------------------------------------------------------------------------------------------
// A press on empty space arms the box; once the mouse has moved a few pixels with the button down, the box shows,
// and when the button is let go every piece whose middle is on screen inside it is selected (added, with Shift or
// Ctrl). The selection only changes after the button is up, so no drag of the game's is ever cut short.
const float BOX_START = 6;         // pixels the mouse must move before a press becomes a box
const float BOX_EDGE = 1.5f;
array<UI::Window@> boxParts;        // fill, then top, bottom, left, right
bool boxArmed = false, boxShown = false, boxAdding = false;
float boxX0, boxY0, boxX1, boxY1;
array<int> boxBase;                 // the selection it adds to (Shift or Ctrl): as it was before the press
array<int> outlined;                // pieces given the selection outline while the box is up (not selected yet)

void ArmBox(bool adding)
{
    // Only a press on empty space: the game's own handling of one leaves nothing selected (with or without Shift or
    // Ctrl), while a press on the gizmo keeps the selection (measured; the editor's IsHoveringGizmo answers no even
    // then on this game version).
    if (Editor::Selection().length() > 0)
        return;
    float x, y;
    if (!Input::Down(Input::MouseLeft) || !Input::MousePosition(x, y))
    {
        if (adding && !SameSet(lastSelection, Editor::Selection()))
            Editor::Select(lastSelection);      // a quick Shift or Ctrl click on empty space keeps the selection
        return;
    }
    boxArmed = true;
    boxShown = false;
    boxAdding = adding;
    boxX0 = boxX1 = x;
    boxY0 = boxY1 = y;
    // The game's own Shift or Ctrl press on empty space clears the selection (measured: "the game left 0
    // selected"), so the one to add to is last frame's, from before the press.
    boxBase = adding ? lastSelection : array<int>();
}

void ShowBox(bool on)
{
    for (uint i = 0; i < boxParts.length(); i++)
        boxParts[i].visible = on;
    if (!on)
        return;
    float left = Min(boxX0, boxX1), top = Min(boxY0, boxY1);
    float width = Max(1.0f, Abs(boxX1 - boxX0)), height = Max(1.0f, Abs(boxY1 - boxY0));
    boxParts[0].SetRect(left, top, width, height);
    boxParts[1].SetRect(left, top, width, BOX_EDGE);
    boxParts[2].SetRect(left, top + height - BOX_EDGE, width, BOX_EDGE);
    boxParts[3].SetRect(left, top, BOX_EDGE, height);
    boxParts[4].SetRect(left + width - BOX_EDGE, top, BOX_EDGE, height);
}

void UpdateBox()
{
    if (!boxArmed)
        return;
    if (Input::Down(Input::MouseLeft))
    {
        float x, y;
        if (Input::MousePosition(x, y))
        {
            boxX1 = x;
            boxY1 = y;
        }
        if (!boxShown && (Abs(boxX1 - boxX0) > BOX_START || Abs(boxY1 - boxY0) > BOX_START))
            boxShown = true;
        if (boxShown)
            ShowBox(true);
        // While the button is down the pieces that will be selected show the editor's outline: those selected
        // before (the game's Shift or Ctrl press on empty space took theirs away) and those in the box.
        array<int> preview = boxBase;
        if (boxShown)
        {
            array<int>@ inside = InsideBox();
            for (uint i = 0; i < inside.length(); i++)
                if (!Contains(preview, inside[i]))
                    preview.insertLast(inside[i]);
        }
        Outline(preview);
        return;
    }
    if (boxShown)
        SelectInBox();
    else if (boxAdding && !SameSet(boxBase, Editor::Selection()))
        Editor::Select(boxBase);            // a Shift or Ctrl click on empty space keeps the selection
    array<int> none;
    Outline(none);                          // the selection draws its own outlines from here
    ShowBox(false);
    boxArmed = boxShown = false;
}

// The pieces whose middle is on screen inside the box.
array<int>@ InsideBox()
{
    float left = Min(boxX0, boxX1), right = Max(boxX0, boxX1);
    float top = Min(boxY0, boxY1), bottom = Max(boxY0, boxY1);
    array<int> inside;
    array<int>@ pieces = Editor::Pieces();
    for (uint i = 0; i < pieces.length(); i++)
    {
        float x, y;
        if (Editor::ScreenPosition(pieces[i], x, y) && x >= left && x <= right && y >= top && y <= bottom)
            inside.insertLast(pieces[i]);
    }
    return inside;
}

void SelectInBox()
{
    array<int>@ inside = InsideBox();
    array<int> selection = boxBase;
    for (uint i = 0; i < inside.length(); i++)
        if (!Contains(selection, inside[i]))
            selection.insertLast(inside[i]);
    if (!SameSet(selection, Editor::Selection()))
        Editor::Select(selection);
    Log::Info("drag select: " + inside.length() + " piece(s) in the box" + (boxAdding ? ", added" : ""));
}

// Gives exactly these pieces the outline (on top of the game's own for selected pieces). Pieces that are selected
// keep theirs when taken off the list: the game drew it.
void Outline(const array<int>@ pieces)
{
    array<int>@ selected = Editor::Selection();
    for (int i = int(outlined.length()) - 1; i >= 0; i--)
        if (!Contains(pieces, outlined[i]))
        {
            if (!Contains(selected, outlined[i]))
                Editor::SetOutline(outlined[i], false);
            outlined.removeAt(i);
        }
    for (uint i = 0; i < pieces.length(); i++)
        if (!Contains(outlined, pieces[i]) && !Contains(selected, pieces[i]))
        {
            Editor::SetOutline(pieces[i], true);
            outlined.insertLast(pieces[i]);
        }
}

float Min(float a, float b) { return a < b ? a : b; }
float Max(float a, float b) { return a > b ? a : b; }
float Abs(float a) { return a < 0 ? -a : a; }

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
    UpdateBox();
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

void PathColour(float &out r, float &out g, float &out b)
{
    // a hue at full saturation, then made linear (the game's colours are), roughly
    float h = float(PathHue % 360) / 60.0f;
    int k = int(h);
    float f = h - k, q = 1 - f;
    r = k == 0 || k == 5 ? 1 : k == 1 ? q : k == 4 ? f : 0;
    g = k == 1 || k == 2 ? 1 : k == 0 ? f : k == 3 ? q : 0;
    b = k == 3 || k == 4 ? 1 : k == 2 ? f : k == 5 ? q : 0;
    r *= r; g *= g; b *= b;
}

int PathTube(uint from, uint to)
{
    array<double> points;
    for (uint i = from * 3; i < to * 3 && i < pathPoints.length(); i++)
        points.insertLast(pathPoints[i]);
    if (points.length() < 6)
        return 0;
    float r, g, b;
    PathColour(r, g, b);
    int id = Draw::Tube(points, PathThickness, r, g, b, false, PathOpacity / 100.0f);
    return id > 0 ? id : 0;
}

void RemovePathTubes()
{
    for (uint i = 0; i < pathTubes.length(); i++)
        Draw::Remove(pathTubes[i]);
    pathTubes.resize(0);
    if (pathLive > 0)
        Draw::Remove(pathLive);
    pathLive = 0;
    pathDrawnPoints = 0;
}

void ClearPath()
{
    RemovePathTubes();
    pathPoints.resize(0);
}

// The tubes brought up to the points: finished chunks once, the growing one again now and then.
void DrawPath(bool now)
{
    int count = int(pathPoints.length() / 3);
    while (count - pathDrawnPoints > PATH_CHUNK)
    {
        int end = pathDrawnPoints + PATH_CHUNK;
        int id = PathTube(uint(pathDrawnPoints), uint(end + 1));    // one point shared with the next chunk
        if (id > 0)
            pathTubes.insertLast(id);
        pathDrawnPoints = end;
    }
    if (!now && Host::Time() < pathRedrawAt)
        return;
    pathRedrawAt = Host::Time() + PATH_REDRAW;
    if (pathLive > 0)
        Draw::Remove(pathLive);
    pathLive = PathTube(uint(pathDrawnPoints), uint(count));
}

// A test run records the ball's path (a new one each run and restart); back in the editor it stays drawn.
void UpdatePath()
{
    string look = ShowPath + ":" + PathHue + ":" + PathThickness + ":" + PathOpacity;
    bool testing = Editor::IsTesting();
    bool inEditor = testing || Editor::IsOpen();
    if (!inEditor)
    {
        if (pathPoints.length() > 0)
            ClearPath();                    // left the editor: the path belonged to that track
        pathTesting = false;
        return;
    }
    // The tubes go with the map; drawn again from the points when it changed, or the settings did.
    if (Host::MapNumber() != pathMap || look != pathLook)
    {
        pathMap = Host::MapNumber();
        pathLook = look;
        RemovePathTubes();
        if (ShowPath)
            DrawPath(true);
    }
    if (testing && !pathTesting)
    {
        ClearPath();                        // a new test run: a new path
        pathRestarts = Race::Restarts();
    }
    pathTesting = testing;
    if (!testing || !ShowPath)
        return;
    double x, y, z;
    if (!Race::BallPosition(x, y, z))
        return;
    uint n = pathPoints.length();
    if (n >= 3)
    {
        double dx = x - pathPoints[n - 3], dy = y - pathPoints[n - 2], dz = z - pathPoints[n - 1];
        double d = dx * dx + dy * dy + dz * dz;
        // a restart (its counter, or the ball jumping back): a new path
        if (Race::Restarts() != pathRestarts || d > PATH_JUMP * PATH_JUMP)
        {
            pathRestarts = Race::Restarts();
            ClearPath();
        }
        else if (d < PATH_STEP * PATH_STEP)
            return;
    }
    pathPoints.insertLast(x);
    pathPoints.insertLast(y);
    pathPoints.insertLast(z);
    DrawPath(false);
}

void Update(float dt)
{
    UpdatePath();
    bool open = Editor::IsOpen();
    section.visible = open;
    Editor::SetTabCycling(open);
    if (toast.visible && (!open || Host::Time() > toastUntil))
        toast.visible = false;
    if (!open)
    {
        if (boxArmed)
            ShowBox(false);
        boxArmed = boxShown = false;
        outlined.resize(0);
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
