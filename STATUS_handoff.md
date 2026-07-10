# STATUS_handoff — Interior Pro (עודכן 2026-07-10)

## מה הושלם בסבב 2026-07-10 (קרא ראשון!)
- **יש אישור מפורש מהמשתמש לעבוד גם על קירות וחלונות** (מולדינג/קשתות). CLAUDE.md עדיין אומר דלתות בלבד — האישור גובר.
- **ידיות Front Door** — הושלם ונבדק (ראה סעיף 07-07 למטה).
- **צבעים לדלת ולפריים:** door_color/frame_color ב-DOOR_SETTING_KEYS (restart!), בוררי צבע קטנים בדיאלוג + צ'קבוקס "Frame same color as door". door_frame_material/door_leaf_material ב-door_tool; DoorLeafStyles.build_leaf_body! מקבל leaf_mat:.
- **גלריות מתקפלות:** עיצובי כנף פנים + Front Door נפתחים בלחיצה (כמו ידיות).
- **מולדינג — פיצ'ר חדש שלם:** קבצים חדשים molding_library.rb / molding_tool.rb / molding_dialog.rb (רשומים ב-main.rb):
  - MoldingManager.apply_all!/remove_all!/refresh! — לכל הבית; קירות פנים = שני צדדים, חוץ = צד פנימי (היוריסטיקת מרכז).
  - מיטרים 45° בפינות (resolve_miters! + extrude_profile! עם caps מוזחים).
  - חורים לדלתות לפי bbox של גוף הדלת (כולל קייסינג!) — door_bbox_gaps (דלתות = Group/ComponentInstance עם type='door').
  - רענון אוטומטי אחרי הצבה/הזזה/מחיקה של דלת (hooks ב-door_tool/door_move_tool/door_delete_tool).
  - MoldingToggleTool — קליק על קיר מחריג/מחזיר (no_molding attr).
  - כפתורי toolbar + תפריט + אייקונים (molding_tool.svg, molding_toggle.svg).
  - MoldingDialog — גלריה עם SVG שנוצר מהפרופילים עצמם.
- **ספריית פרופילים של המשתמש:** `assets/MOLDING PROFILES` — BASE-1..3, CROWN-1..3, CASING-1 (.skp). skp_profile_points קורא פאה מהקובץ (זיהוי מישור אוטומטי). קטלוגי הקייסינג צומצמו ל-none/flat + CASING-*.skp (דינמי, DoorLibrary.casing_styles + DoorCasingProfiles.skp_spec).
- **קייסינג:** יושב על הפריים (CASING_REVEAL=0.25, היסט פנימה ב-build_u_casing_followme); הבייסבורד נעצר בקצה הקייסינג.

## הבעיה הפתוחה שבה עצרנו (להתחיל כאן!)
קריאת הפרופילים מה-skp מחזירה **מלבנים** — כנראה המשתמש מידל גופים תלת-ממדיים ולא פאה שטוחה אחת, ו-max_by(&:area) תופס פאה לא נכונה. שתי דרכים: (א) המשתמש ישמור כל קובץ כפאת חתך אחת בלבד; (ב) להרחיב את הקורא לחלץ חתך מגוף (למשל הפאה עם השטח הקטן ביותר בין שתי המקבילות, או section). לבדוק עם המשתמש איך הקבצים בנויים.

## לקחים חדשים
- reload! משתמש ב-plugin_files שבזיכרון — קובץ חדש שנוסף ל-main.rb לא ייטען עד restart (או load ידני מפורש).
- שינויי דיאלוג = cp + InteriorPro.reload! + סגירה/פתיחה של הדיאלוג בלבד. restart מלא רק ל-DOOR_SETTING_KEYS.
- ב-Plugins היה קובץ-זבל בשם "MOLDING PROFILES" שחסם יצירת התיקייה (EEXIST) — נמחק. אם mkdir נכשל על EEXIST כשהתיקייה "לא קיימת" — לבדוק File.file?.
- ה-shell של קלוד מציג לפעמים קבצים קטומים — לוודא מול Read לפני בהלה.

## הצעדים הבאים (סדר מוצע)
1. לתקן קריאת פרופילים מ-skp (הבעיה הפתוחה למעלה) + לוודא שכל 7 הפרופילים נראים נכון בגלריה ובבית.
2. כיול מיקום/צורה: קראון בפועל על קיר, מפגשי קייסינג-בייסבורד בכל הפרופילים.
3. צבע למולדינג (כמו דלתות).
4. חלונות/דלתות עגולים וקשתות (יש אישור קירות/חלונות).

---

# היסטוריה: סבב 2026-07-07

קרא את זה ראשון בכל צ'אט חדש. משלים את CLAUDE.md (מוגבל לדלתות) ואת ה-RETRO.

## שיטת העבודה הנוכחית (חשוב!)
- **אין Cursor.** העוזר עורך ישירות בתיקיית המקור `C:\InteriorPro_Agent\source_readonly` (באישור המשתמש לכל צעד).
- הפלאגין החי רץ מ: `C:\Users\rordt\AppData\Roaming\SketchUp\SketchUp 2024\SketchUp\Plugins\interior_pro` (`InteriorPro::PLUGIN_DIR`).
- סנכרון: `FileUtils.cp` ב-Ruby Console (מקור ← Plugins) ואז `InteriorPro.reload!`. שינויי דיאלוג: לסגור ולפתוח את הדיאלוג. שינוי ב-DOOR_SETTING_KEYS (door_manager.rb, מוגן ב-const_defined?) — **חובה הפעלה מחדש מלאה של SketchUp**.
- **git: רק בתיקיית ה-Plugins** (branch: door-stabilize). **בתיקיית המקור אין git!** commit דרך טרמינל cmd עם `git -C "<נתיב Plugins>" ...`.
- **אזהרה קריטית (תקרית 2026-07-07): לפני עריכת קובץ משותף — לוודא שהמקור מסונכרן עם ה-Plugins!** תיקיית המקור הייתה מיושנת (door_manager/door_tool), העתקה דרסה קוד חי ושברה הכל. שוחזר מ-git. הדרך: `copy /Y` מ-Plugins למקור לפני עבודה על קובץ שלא נגענו בו בסשן.
- הדבקות ארוכות בקונסול נקטעות — סקריפטים לקובץ ואז `load`. בשורש: `debug_door.rb`, `debug_handles.rb`, `debug_front_doors.rb`, `debug_front_door.rb`.
- בדיקות תמיד על סצנה נקייה; **רכיבי ידיות/דלתות נשמרים במודל (cache) — בדיקות בקובץ חדש לגמרי (File → New)!**
- המשתמש מדביק פקודות בלבד — לתת פקודות מוכנות עם puts ופלט ברור, ולציין איפה מדביקים (Ruby Console / cmd).

## מה הושלם בסבב 2026-07-07
### ידיות — סגור
- ידית 5: `yflip: true` (שיקוף קדימה-אחורה סביב מרכז הרכיב, לא מזיז כיול) + dy מכויל -3.6875.
- ידית M-8: `yflip: true` + dy מכויל -3.25.
- נושא ה-leader lines ירד — המשתמש אישר שאין קו נראה. לא לגעת.
- דיאלוג: בחירת ידית = גלריה נפתחת בלחיצה (סגורה כברירת מחדל), ציורי SVG 2D פר-ידית, 5 עמודות. ה-select המקורי מוסתר ונשאר לתאימות.
- גריד עיצובי כנף (פנים): 2 שורות של 5, חצי גודל, בלי שמות (tooltip בריחוף).

### תיקונים קריטיים
- **שוחזר `move_hosted_doors!`** ב-door_manager.rb (נמחק בטעות ב-2026-07-02 בעוד הקריאה ב-ui_dialogs.rb נשארה — הזזת קיר עם דלת הייתה שבורה). מזיז דלתות+חלונות של הקיר.
- **`exterior_effective_n`** ב-door_tool.rb: דלתות חוץ נבנו החוצה מהקיר כשגוף הקיר בצד ה-שלילי של פאת הקליק. עכשיו בודקים מהפאות (wall_v_span_from_faces) והופכים את n בצורך. קירות תקינים לא מושפעים.
- אזהרת Yes/No בהצבת דלת חוץ על קיר פנים (wall_category).
- הסף (threshold): מדרגות ה-nose החיצוני הוסרו לגמרי — נשאר בסיס בלבד (append_exterior_threshold_nose! ריק).

### Front Door — פיצ'ר חדש (עובד)
- סוג 'Front Door' ראשון ב-EXTERIOR_TYPES. ברירת מחדל 36×80.
- **תצורות (front_config):** single / single_1sl / single_2sl / double. sidelite = פאנל מזוגג + mullion ‏1.5″. רוחב מתעדכן אוטומטית בדיאלוג לפי תצורה.
- **Transom:** צ'קבוקס + גובה; סימון מגדיל את גובה הפתח אוטומטית (הכנף שומרת גובה). בר אופקי + זכוכית מעל.
- **6 עיצובי כנף (front_leaf_style, גלריה בדיאלוג):**
  1. Craftsman 3-Lite — 3 חלונות למעלה + 2 פאנלים שקועים בשני הצדדים (בלי מדף).
  2. 5-Lite Ladder — 5 זכוכיות אופקיות.
  3. Steel Glass — מסגרת פלדה שחורה + זכוכית מלאה; גריד מ-Glass Grid (none=חלק).
  4. Farmhouse 4-Lite — זכוכית למעלה, גובה ב-% (front_glass_ratio, ברירת מחדל 50) + גריד מ-Glass Grid.
  5. Modern Lines — כנף חלקה + 4 פסים אופקיים כהים.
  6. Steel Arch — קשת פלדה + זכוכית + גריד קבוע (קו אמצע עד הרצפה), מילוי אטום בפינות מעל הקשת (הפתח בקיר נשאר מלבני!).
- **מפתחות חדשים ב-DOOR_SETTING_KEYS:** front_config, front_leaf_style, front_glass_ratio, sidelite_width, transom, transom_height (+ attributes תואמים). שינוי בהם = restart.
- **בנאים ב-door_tool.rb:** build_front_door_geometry!, front_door_spans, build_front_leaf_styled!, build_front_arch_leaf!, build_front_panel_with_holes!, add_front_grid_bars!, add_front_bar!, front_door_mats (חומרים: InteriorPro_Front_Steel, InteriorPro_Front_Groove).
- **תצוגת כל העיצובים:** File → New ואז `load 'C:/InteriorPro_Agent/source_readonly/debug_front_doors.rb'` — בונה את כולן ממוספרות בשורה.

## לקחים מהסבב (קריטי!)
- **לא להעתיק קובץ מהמקור ל-Plugins בלי לוודא שהמקור עדכני** — זו הייתה התקלה הגדולה של הסשן.
- אחרי כל צעד ירוק — commit מיד. ה-git הציל את הסשן.
- כשגוף/פאה נמחקים אחרי erase של פאה פנימית — לאתר מחדש את הפאה (grep(Sketchup::Face).first) לפני pushpull.
- פוליגון קשת: בלי נקודות כפולות בקצוות, ולשמור על סדר נקודות רציף (self-intersection שובר add_face).
- דלתות חוץ ופנים משתמשות בקונבנציות עומק שונות — פנים לפי פאות הקיר, חוץ 0..thickness + היפוך n בצורך.

## הושלם 2026-07-07 (סבב ב')
- **עריכת Front Door נבדקה** — כל השדות חוזרים, rebuild תקין.
- **ידיות Front Door עובדות end-to-end:** קבצים 1-4.skp ב-`assets/FRONT DOOR HANDLES`; טבלת כיול נפרדת `FRONT_HANDLE_FIT` ב-door_handles.rb (שמות מספריים לא מתנגשים עם interior); תמיכה ב-rz (סיבוב אנכי) ב-fit_transform; `fit_offset/fit_transform/both_sides?` מקבלים kind; door_tool: `handle_kind`, `handle_enabled?` כולל front, הצבה ב-build_front_door_geometry! (single לפי swing, double במרכז, עוגן 3" מהקצה); דיאלוג: גלריה + thumbs נפרדים ל-front (`FRONT_HANDLE_NAMES`, `frontHandleThumbSvg`), רשימת ידיות מוחלפת לפי סוג דלת. נבדק: single, double, עריכה.
- סצנת כיול: `debug_front_handles.rb` (שני צדדים). **לקח: מוסך ה-shell של קלוד הציג קבצים קטומים — אם ruby -c נכשל על EOF, לבדוק את הקובץ האמיתי לפני בהלה.**

## נושאים פתוחים / הצעדים הבאים (לפי סדר שסוכם)
3. **ידיות לדלתות ארון** — תיקייה: `assets/CLOSET DOOR HANDLES`.
4. **סוגי Casing** — הרחבת הקטלוג (המשתמש רצה, טרם פורט).
5. **מולדינג בייסבורד + תקרה (crown)** — חורג מ"דלתות בלבד"; דורש אישור מפורש + קבצים חדשים נפרדים.
6. **פתחים מעוגלים בקיר** (קשת אמיתית + Radius window) — הפיצ'ר הכבד; דורש שינוי במודל הפתחים ובבנאי הקיר (wall_tool.rb אסור כרגע).
7. UI פתוח: גריד עיצובי כנף פנים שייפתח רק בלחיצה (כמו הידיות).
8. חוב ישן: באג מיטר Merge Wall; 4 סוגי חלונות placeholder.

## קבצים זמניים בשורש
- `debug_front_doors.rb` — תצוגת עיצובי Front Door (להשאיר).
- `debug_front_door.rb` — דיבוג מיקום דלת מול קיר (להשאיר).
- `debug_handles.rb` — סצנת כיול ידיות (להשאיר).
- `report_handle_lines.rb`, `door_manager_before_delete.rb`, `dh_c319962.rb` — אפשר למחוק.
