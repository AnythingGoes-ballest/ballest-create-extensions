// Create Extensions: additions to Ballest's track editor.
//
//   * Placing a piece from the palette puts it on whole-unit coordinates (never fractions), optionally further in
//     front of the camera (the Placement distance setting; 0 leaves it where the game puts it).
//   * "Snap moved pieces to whole units" (a setting, off by default) rounds selected pieces after they are moved.
//   * A "rotated copy" section in the details panel, under transform: tick X, Y and/or Z, set each angle (180 by
//     default) and "create rotated copy" duplicates the selection and turns the copy about its centre.
//   * Tab and Shift+Tab move between the transform boxes (location, rotation, scale; X, Y, Z).
//   * "Rotate multiple pieces around their centre" (a setting, off by default): rotating two or more pieces turns
//     them about the centre of the selection instead of the last selected piece.

[Setting name="Placement distance" min=0 max=2000 description="How far in front of the camera new pieces are placed (0: where the game puts them)"]
int PlacementDistance = 0;

[Setting name="Snap moved pieces to whole units" description="After a move, selected pieces are rounded to whole units"]
bool SnapMoves = false;

[Setting name="Rotate multiple pieces around their centre" description="Instead of around the last selected piece"]
bool RotateAroundCenter = false;

UI::Window@ section;
array<UI::CheckBox@> axisBoxes;
array<UI::TextInput@> angleBoxes;
UI::Button@ copyButton;
int copyRequested = 0;           // frames until the angles typed in the boxes are read (they are submitted first)

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
    OnSettingsChanged();
    Log::Info("create extensions ready");
}

void OnSettingsChanged()
{
    Editor::SetRotateAroundCenter(RotateAroundCenter);
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

// New pieces from the palette: further in front of the camera if asked, then onto whole units.
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

void Update(float dt)
{
    bool open = Editor::IsOpen();
    section.visible = open;
    Editor::SetTabCycling(open);
    if (!open)
        return;
    PlaceNewPieces();
    SnapSelection();

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
