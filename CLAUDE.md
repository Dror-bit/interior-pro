# Project Rules for Claude

SketchUp interior design plugin, Ruby, module `InteriorPro`.
Live folder (edit in place, no RBZ):
`C:\Users\rordt\AppData\Roaming\SketchUp\SketchUp 2024\SketchUp\Plugins\interior_pro`

## שתי מכונות (2026-09-09)
- ווינדוס: SketchUp **2024**, הנתיב למעלה. זו המכונה שעובדים עליה.
- מאק: SketchUp **2026** -
  `~/Library/Application Support/SketchUp 2026/SketchUp/Plugins/interior_pro`
  מתעדכן ב-git: `git push origin door-stabilize` בווינדוס, ואז
  `git pull origin door-stabilize` במאק, ואז `InteriorPro.reload!`.

## איך אנחנו עובדים — הכללים המלאים (2026-09-04)
##
## הועברו לכאן מהודעת הפתיחה, כדי שההודעה בצ'אט חדש תהיה שלוש שורות.
## הקובץ הזה נקרא בתחילת כל צ'אט.

מי עושה מה
המשתמש לא כותב קוד. אתה עורך את הקבצים בעצמך, הוא מדביק פקודות, מריץ
InteriorPro.reload! ובודק בסקצ'אפ. git — רק דרך ה-CMD שלו, אף פעם לא אתה.

בדיקות
אין לו רובי על ה-Windows, אבל ל-VM שדרכו רצות הפקודות יש רובי ו-node, אז
אתה מריץ את החבילה בעצמך בתיקיית התוסף:
  cd tests && LANG=C.UTF-8 bash run_all.sh ..
צריכות לצאת 156 ירוקות (rt51/rt52 אדומות מסיבה ישנה — ראה המסירה).
כל קריאת shell מוגבלת ל-45 שניות; להריץ ברקע עם nohup ולקרוא את הלוג.
תמיד run_all.sh, לא קובץ טסט לבד. בדיקה חדשה — להריץ גם נגד הקוד הישן
ולוודא שהיא נופלת. אם בדיקה ישנה נופלת — קודם להניח שהתיקון רחב מדי.

איך לדבר אליו
עברית פשוטה, משפט-שניים, כמו לילד בן 5, בלי הרצאות. כל פקודה בקופסה
נפרדת עם "Ruby Console" או "CMD". הוא כותב לפעמים עברית עם מקלדת
אנגלית — לפענח לבד, לא לשאול.

גודל צעדים
צעד אחד בכל פעם, וקטן. בדיוק מה שביקש, בלי לשפר דברים שלא ביקש.
אם הוא ביקש דבר קטן ואתה משנה כיוון ב-180 מעלות — עצור. (2026-09-03: הוא
ביקש להגביל רעף שנכנס פנימה וקיבל לֵיין ריק של פוט מסביב לדורמר.)

תמדוד, אל תנחש — החוק הכי חשוב
למדוד לפני שמשנים. אף פעם לא "זה עובד" מתוך תמונה — אם לא מדדת, תגיד
שלא מדדת. כשהוא אומר "לא עובד": קובץ שרק מודד, כותב דוח לתיקייה, ואתה
קורא את הדוח בעצמך — הוא לא מדביק כלום. דוגמאות בשורש:
debug_ribs_edge.rb, debug_rib_defn.rb, debug_dormer_cut.rb,
debug_after_delete.rb, debug_dormer_panels.rb.
הוא לא יכול לבחור קרש בודד בתוך קבוצה — אל תבקש ממנו לסמן.

לפני שבונים
לשאול איך הוא רוצה שזה ייראה ולצייר לו: תמונה מרונדרת עם המידות
האמיתיות של המודל שלו, ואז שאלה אחת קצרה. ASCII הוא לא מבין.
כשהוא אומר מה לבנות — לבנות. דעה אחת קצרה, ואם הוא חזר על עצמו —
להפסיק להסביר ולבנות.

עוד שלושה כללים, עם הסיבה שלהם (2026-09-06)

הוא מודד בעצמו, ואז מוסר לך מספר.
כשהוא אומר "זה עדיין 3 אינץ' בתוך הגג" — הוא מדד את זה בסקצ'אפ, זה לא
רושם מתמונה. אל תענה לו "אני לא מנחש, מדדתי" — זה נשמע כאילו אתה אומר
שהוא ניחש, וזה עצבן אותו בצדק. תגיד מה מדדת ותשווה למספר שלו.

כשהוא אומר משהו קצר, זה בדיוק מה שהוא מתכוון.
"תוריד את הגג" זה להוריד את הגג. באותו יום זה נקרא אצלי "לתכנן מחדש את
הסופיט ואת הרייק", ובזבזתי לו שני סבבים שלמים עד שהוא כתב במפורש:
"אתה לא מגדיל כלום ולא מקטין כלום ולא משנה שום צורה, אתה בסך הכל מוריד
את הגג — אני יכול לעשות את זה ידנית בסקצ'אפ". אם הבקשה שלו היא פעולה
אחת פשוטה, התיקון הוא פעולה אחת פשוטה. אם אתה מוצא את עצמך משנה צורה של
חלק כדי לענות על בקשה של הזזה — עצור, אתה בכיוון הלא נכון.

לפני שמוסיפים גיאומטריה חדשה — לשאול.
הרמתי גג והרווח שנפתח מעל הקיר נסגר ברצועת קיר שנבנתה בקבוצת הגג. היא
הייתה צבועה נכון ובמקום הנכון, והוא פסל אותה בשנייה: "נראה כאילו הוספת
קירות נוספים מתחת לגג... תמחק את רצועת הקיר הזאת ואל תוסיף כלום". חלק
שהוא לא ביקש הוא חלק שהוא יראה ולא ירצה. תשאל לפני, לא אחרי.

קומפוננט ישן במודל שלו מנצח את הקוד
roof_tile_parts מושך קומפוננטים לפי שם (fetch_or_build). אם נראה שהקוד
"לא עובד" — למדוד קודם את הדפיניציה עצמה.

הסטאב בענן הוא לא המודל שלו
אין בו פיצול פאות, רכס-קאפ, רעפים תלת-מימדיים, לולאות/קצוות או חומרים
אמיתיים. צבעים, חיתוך אמיתי וסגירת חורים נבדקים רק אצלו.

תתקן את הסיבה, לא את המספר. אל תוריד את ההפרש.

סבב שנגמר
commit דרך ה-CMD שלו אחרי כל צעד עובד, ואז מעדכנים את קובץ המסירה.

זהירות — זה שובר לו את המודל
build_roof! בלי replace: או level: מוחק את כל הגגות שלו. תמיד:
  InteriorPro::RoofManager.roofs.each { |r| InteriorPro::RoofManager.build_roof!(replace: r) }

אל תיגע בקבצים שלו: לא להזיז ולא למחוק בלי לבדוק שהם לא ב-git.

חיפוש באינטרנט: כשהוא שואל איך עושים משהו בבתים אמיתיים — לחפש, ולהביא
כללי אצבע ומספרים, לא תיאוריה.

## How we work (set by the user, 2026-08-10)

- Hebrew only. One or two sentences. Explain it the way you would to a
  five-year-old.
- Every command goes in its OWN copy box, labelled with where to paste it
  (Ruby Console / CMD).
- The user does NOT use Cursor. The assistant edits the files itself; the
  user tests inside SketchUp.
- The user has no Ruby installed, so the `rt*` suites give a FALSE FAIL on
  his machine. The assistant runs them in the cloud:
  `cd tests` then `"C:\Program Files\Git\bin\bash.exe" run_all.sh ..`
- The assistant NEVER runs git, not even read-only - it leaves `index.lock`
  stuck. Give the user CMD commands instead.
- Read the relevant file in full before changing it. Never trust another
  chat's summary - verify against the live code.
- One step at a time. Test in SketchUp, then commit, then next step.
- Do not break what already works.

## BOARDS MEET, THEY NEVER RUN INSIDE EACH OTHER (user's law, 2026-08-26)

Set by the user after catching it three times in one day: *"תרשום לעצמך
חוק שהם חייבים להיפגש ולא להיכנס אחד לתוך השני."*

Whenever two trim pieces (fascia, drip, soffit, rake board, deck strip -
any two solids) share a corner or a line, exactly ONE of them owns the
shared block and the other is CUT BACK to end flush on its face. Never
let both build into the same piece of space - overlapping solids show as
seams and doubled lines on the face, and the user sees them immediately.
Before adding any new trim piece, ask: which existing piece does each of
its ends run into, and is it cut to end exactly there?
`RoofManager.rake_meet_span` is the helper for rake-vs-band corners.

## כל קרש בקבוצה משלו (חוק, 2026-09-12 — זה הפיל את סקצ'אפ)

שני גופים שנוגעים פאה בפאה על אותו מישור, בתוך אותה קבוצה, הם לא רק
מכוערים — סקצ'אפ ממזג פאות חופפות, ו-pushpull לתוך המיזוג הזה **מפיל
את התוכנה**. קרה בסיידינג האופקי על משולש הגמלון: במקום שהרייק חותך
את השורה, הקרשים השכנים יושבים זה לצד זה.

קבוצה היא החומה של סקצ'אפ עצמו בין שני גופים. כשבונים סדרה של גופים
קטנים שנוגעים — כל אחד בקבוצה משלו. אל תאחד אותם חזרה "כדי לחסוך
קבוצות". (הקיר עצמו לא נתקל בזה כי השורות שלו חתוכות על ידי חלונות
ולא מונחות זו לצד זו.)

זה לא סותר את חוק "הקרשים נפגשים ולא נכנסים אחד לתוך השני" — הוא על
חפיפת נפח, וזה על מיזוג פאות. שניהם חייבים להתקיים.

## קריסה לא משאירה שגיאה — משאירים עקבות בדיסק (2026-09-12)

כשסקצ'אפ נופל אין backtrace ואין קונסול. הדרך היחידה למצוא איפה: קובץ
שכותב שורה לדיסק לפני כל צעד ועושה `flush` + `fsync`, ואז בונים פעמיים
— פעם עם התכונה החדשה כבויה ופעם דלוקה. השורה האחרונה שנשארה בקובץ
מצביעה על הצעד. `debug_apply_probe.rb` בשורש הוא התבנית.

לכן כל תכונה חדשה שבונה גיאומטריה מקבלת דגל כיבוי מיד — הוא מה שמאפשר
את הבידוד הזה. הנוכחיים למטה.

## מדידה על קומה שנייה, לא רק על קומת קרקע (2026-09-12)

`group.bounds` הוא בקואורדינטות של ההורה; מה שבונים בתוך הקבוצה הוא
בקואורדינטות שלה. בקומת קרקע שני המספרים זהים, אז באג כזה שורד שנים
ומתגלה רק כשמישהו בונה קומה שנייה. כל חישוב שמערבב bounds עם גיאומטריה
פנימית — לבדוק אותו על קיר עם `base_z` שאינו אפס.

## Current phase: curved walls, then 2D plans to PDF

(The old "doors only" restriction is retired - it was from the 2026-04 phase
and no longer applies. Doors, windows, walls, floors, roofs, moldings and the
2D editor are all live code now.)

Priority 1 - CURVED WALLS. Both entry points are wanted: dragging an existing
wall's middle to bow it, AND a 3-click arc tool. Both in the 2D editor and in
SketchUp itself.

Priority 2 - 2D PLANS TO PDF. Exterior plans first, no elevations yet. Needs a
page template, page size (Arch D / Arch E / A1...), a fixed scale, images and
dimensions. Check what the 2D editor and `plan_generator.rb` already do before
building anything twice.

## TODO the user asked to come back to (do not lose)

- **The hand-drawn NOTE looks bad** (2026-08-17). He placed one reading
  "קירות פנים" on his plan, sent a picture, and said: *"עזוב את זה שזה לא
  נראה טוב ואנחנו צריכים לעבוד על זה."* A boxed label with a leader and an
  arrow. Parked deliberately, not forgotten. `PlanCanvas.draw_mark_note`.
- **Colour on the sheet** (2026-08-17). Asked for, not built. There is NO
  concept of a line colour anywhere in the drawing document: `plan_doc.rb`
  carries weight and a polygon fill only, the window writes a hard-coded
  `stroke="#000"` and `plan_pdf.rb` a hard-coded `0 0 0 RG`. Four files have
  to change together or the preview and the PDF will disagree - which is the
  one thing that file set exists to prevent. It joins the double-click panel.
- **The logo is per-MODEL, he wants it per-installation** (2026-08-17). It
  lives in `sheet_state`, which is a model attribute. `Sketchup.write_default`
  / `read_default` is the right tool and the plugin does not use it anywhere
  yet. `text_scale` has the same question open.

- **Corner boards (siding trim): "נראות בסדר אבל יש עוד מה לשפר — למקסם"**
  (2026-08-12). Current state: per-wall width picker (Off/2/3/4), closed 90°
  overlap with the neighbour. Ideas for the polish round: a true single L
  solid instead of two overlapping boards, trim around window/door openings,
  cap the top edge.

## Kill switches (turn a feature off without deleting it)

- `InteriorPro::RoofManager::USE_GABLE_SIDING = false` - the gable
  triangle keeps its white face and gets no boards (2026-09-12).

- `InteriorPro::WallTool::USE_CURVED_WALLS = false` - every wall builds
  straight again, `arc_sag` ignored.
- `InteriorPro::WallTool::USE_NATIVE_OPENINGS = false` - the older opening
  path.
- `InteriorPro::WallTool::AUTO_WELD_ENDS = false` - stop join_corners from
  closing a corner whose two ends missed each other by less than a wall
  thickness (2026-08-18, `tests/rt70.rb`). With it off, such a corner stays
  open and keeps its white square cap, as before.

## Curved walls - how they are stored (2026-08-10)

A curved wall is a NORMAL wall with one extra attribute:

- `arc_sag` - how far the middle of the wall is pulled sideways off the
  straight line between its two ends, in inches, SIGNED. Positive = to the
  LEFT of start -> end. No attribute, or under `MIN_ARC_SAG` (1/16"), means
  the wall is straight and takes the original code path exactly.

Because the two ends stay ordinary `start_x/y` and `end_x/y`, every tool that
moves a wall (move, stretch, split, the 2D editor) keeps working untouched -
the bow just follows the ends.

- `arc_math.rb` - pure 2D arc maths, no SketchUp API at all. Tested by
  `tests/rt19.rb`.
- `WallTool.curved_footprint_xy` - pure, returns the floor outline. Tested by
  `tests/rt20.rb`.
- `WallTool.set_wall_sag!(wall, sag)` - THE one entry point. Both the drag and
  the arc tool must end here.
- Sign convention: "left" = turn 90 degrees counter-clockwise. Sag is measured
  against the straight line between the ends; wall side offsets are measured
  against the direction of travel along the arc (see the comments in
  `arc_math.rb` - on a half circle the straight-line test flips on floating
  point noise and would swap a wall's inside and outside).

### Curved walls - corners are WELDED, never mitered (2026-08-12)

THE RULE (replaced the 2026-08-11 tangent-miter after it kept producing
spikes, steps and tilted walls on the user's rooms): a same-category corner
with a curve in it ALWAYS goes through `weld_corner!` in `apply_miter`.
The miter math measures face offsets from straight centrelines and lands
the cut sideways on a curve - do not bring it back.

`weld_corner!`: the STRAIGHT wall (owner) keeps its FULL length and its own
plain square cut - never pulled back, never tilted. The curved wall (guest)
is fitted to it: if the two natural cuts nearly coincide (same-side bands)
the guest snaps EXACTLY onto the owner's cut - one shared seam; otherwise
(opposite-side bands) only the touching lip is pulled onto the owner's FAR
lip, a small shoulder that hides the owner's end cap. Verified by RENDERING
the user's exact rooms (sim in the 2026-08-12 session). `tests/rt31.rb`
pins both branches; `rt30.rb` pins the reach-cap safety net. The 2D editor
mirrors the same rule for pending walls (`weldPendingEnds` in
plan_editor.rb, `tests/t34.js`) and ships built walls' footprints WITH
their corner overrides, so 2D and 3D always draw the same seam.
Known small case: an INWARD-bulging arc meeting a wall at a shallow angle
can leave a tooth-sized overlap on the outside - accepted for now.

`fix_corners_once.rb` (project root) = one console line that reloads the
code, VERIFIES the new code actually loaded, re-joins every corner and
checks every curve seam. Use it after any corner-code change - twice this
session "nothing changed" turned out to be stale loaded code.

STRAIGHT-TO-STRAIGHT CORNERS ARE UNTOUCHED. Everything above sits behind
`curved_corner`, so a corner with no curve in it runs the identical old
code. `tests/rt22.rb` guards this.

### Curved walls - NOT wired up yet (deliberate, do not treat as bugs)

- Openings. A wall with doors or windows refuses to curve and says so.
- Butt joints (interior wall meeting an exterior one) still use the straight
  line, not the tangent.
- Board and Batten strips are left off a curved wall.
- `plan_generator.rb` draws it as a straight line in the 2D plan.
- `RoofManager.eave_polygon` treats it as a straight segment. (NEXT UP -
  the user asked for roof over a curved wall after corners closed.)

(The 2D editor DOES draw and bend curved walls now, 2026-08-12: typed bow
in the עובי·קשת panel - typed plus = OUTWARD, stored sag is the negative,
see uiSagToModel/modelSagToUi and tests/t33.js.)

### Curved walls - the 3-click Arc tool (2026-08-11)

`wall_arc_tool.rb`, `WallArcTool < WallTool`. Click start, click end, click the
bow. It owns NO building logic: it fills in `@start_point`, `@end_point` and
`@arc_sag`, then calls the inherited `create_wall`, which bends the finished
wall via `set_wall_sag!` inside the same operation. That is why a curved wall
gets the same attributes, materials, level and corner joining as a straight
one. Do not give it its own builder - `tests/rt23.rb` fails if it grows one.

Reached from Extensions > Interior Pro > "Arc Wall (3 clicks)", which opens the
wall library first exactly like the Wall tool.

## UI rules (added 2026-08-07, set by the user)

### No duplicate ways to do the same thing

**Rotation covers flipping. Never build both.** Flip / mirror buttons
(left-right, up-down) and a rotation control are the same idea wearing a
different hat. Build the ROTATION only - a typed angle plus a quarter-turn
button - and leave flips out.

More generally: before adding a second control, ask whether an existing one
already does that job. If it does, do not add it. Fewer buttons, fewer
clicks. This is the user's standing preference for the whole plugin.

### Fewer clicks, always

- Clicking any tool button immediately runs that tool. No Escape first, no
  cancelling the previous mode by hand - the click itself cancels it.
- Panels stay open when the mode changes; the user must never reopen a panel
  to reach the tool they just used.
- Every action worth reaching for gets a single-letter keyboard shortcut.
  Current map: S select, D door, W window, L line, O guide line, M move,
  R rotate, U flip the guide angle to the other diagonal.
- Icons over words in dense panels: a dashed horizontal line beats the word
  "horizontal".

### Feedback

- A button that was pressed must LOOK pressed (Apply to Model shows a busy
  state until the model is built).
- The mouse cursor becomes the tool's own icon while move / rotate / offset
  are running, so the active mode is always visible.
