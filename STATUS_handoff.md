# סטטוס והעברה — Interior Pro

## הקשר
תוסף SketchUp (Ruby, מודול InteriorPro), SketchUp 2024, Windows. ענף git: door-stabilize.
מתודת עבודה: עברית קצרה; צעד אחד בכל פעם; בדיקה על **סצנה נקייה** + commit אחרי כל ירוק; לא לשבור קיים.

## עיקרון-ליבה (חוק)
**הגיאומטריה תמיד נבנית מחדש מהנתונים — לא מתוקנת/מטולאת.** attributes = מקור-אמת; כל עריכה = שינוי נתונים → rebuild מלא. אסור boolean/fill/heal בזרימות החיות.

## הערות סביבה / כלים
- Python לא מותקן. עריכות רק דרך Edit tool / PowerShell.
- ה-bash mount מפגר לפעמים אחרי עריכות — **מקור-האמת לתחביר הוא `InteriorPro.reload!` ב-SketchUp**, לא `ruby -c`.
- שינוי toolbar/menu או קובץ חדש ב-main.rb → **הפעלה-מחדש מלאה** של SketchUp. שינוי דיאלוג HTML → לסגור ולפתוח את הדיאלוג. שאר → `InteriorPro.reload!`.

## מה עובד (נבדק)
### קירות
ציור, ספרייה, חומרים, מיטר-פינות — כולל קירות עם פתחים (`apply_native_miter_corners!` ב-wall_tool.rb).

### דלתות — native מלא
הצבה / עריכה / הזזה / מחיקה, כולן regenerate-from-data (door_manager.rb: `delete_door`, `move_door`, `update_door`, עוזרים `remove/update_native_opening_t!/dims!`). דלת עוקבת אחרי הזזת-קיר (`move_hosted_doors!`). סף (threshold) כבוי.

### חלונות — native מלא, מאוחד עם דלתות
- **אותה רשימת פתחים** כמו דלתות (חלון = פתח מורם, floor_offset=סף), שורד rebuild ועוקב אחרי הזזת-קיר.
- **סוגים:** Casement, Casement XX, Single Hung, Slider XO, Slider XOX, Garden Window, XOX Single Hung (ב-window_library.rb + PRESETS).
- גוף פר-פאנל (`build_pane`), slider/hung עם עומק-מסילות + interlock, XOX (hung+picture+hung), Garden (קופסה בולטת + מדף לבן + רַיל צדדים + עומק מתכוונן `garden_depth`).
- **גרידים** (muntins ⅜″) בתוך זכוכית ¼″ (`build_pane_grid`), נבחר ב-dialog (None/2x2/3x3/2x3/3x2).
- **כלים:** WindowTool (הצבה + ריבוע-רפאים), WindowEditTool/MoveTool/DeleteTool (window_manager.rb), אייקונים ייעודיים (window_edit/move/delete.svg).
- דיאלוג זוכר בחירה אחרונה בין החלפות-כלי (@last), מתאפס רק בסגירת SketchUp.

## קבצים מרכזיים
wall_tool.rb (native rebuild + miter + build_pane וכו'), door_manager.rb (native door ops + עוזרי-פתחים גנריים), window_tool.rb (WindowTool + build_casement/garden/pane/grid), window_manager.rb (edit/move/delete + tools), window_library.rb / window_library_dialog.rb, toolbar.rb, main.rb.

## הצעד הבא / פתוח
1. **casing** לחלונות (טרים חיצוני/פנימי סביב הפתח) — עוד לא נעשה.
2. **Radius window** (חלון קשת) — דורש פתח מעוגל (שינוי במודל-הפתחים + בנאי-הקיר). הפיצ'ר הכבד.
3. גרידים ל-Garden (כרגע רק לחלונות מבוססי-פאנל).
4. מהחזון: מצב שרטוט 2D נעול, אוטומציה ל-LayOut, מטבחים פרמטריים.

## מסמכים
`RETRO_and_plan.md` (רטרו + ארכיטקטורה), `CORNER_MITER_plan.md` (עיצוב המיטר).
