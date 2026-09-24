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

## חוק: כל כלי חדש נועל על נקודות — ומראה את זה (2026-09-23)

הוא כתב: *"אבל למה הוא שוב לא ננעל על פינה, סוף קו וכו'? למה כל פעם צריך
להזכיר את זה מחדש? תרשום את זה בחוק בבקשה, זה כבר מתסכל."*

צודק. זה חזר יותר מפעם אחת, אז זה חוק:

**כל כלי בעורך שלוקח נקודה מהעכבר חייב לעבור דרך `snapPoint`, גם בזמן
תזוזת העכבר וגם בלחיצה — ולצייר איפה הוא ננעל.**

- `snapPoint` תופס פינות, סופי קווים, אמצעים, קצוות של קירות וצורות,
  ופינות מְמוּטָרות של הבנד. אל תשתמש ב-`cursor` הגולמי אף פעם.
- אותם צבעים כמו בכל מקום: ירוק = פינה/סוף קו, ציאן = אמצע,
  מג'נטה = על הקצה. בלי טבעת = לא ננעל כלום. `snapColor(kind)`.
- הלחיצה והתזוזה חייבות להשתמש ב**אותה** נקודה. אם התזוזה מציירת סמן
  גולמי והלחיצה משתמשת בנקודה נעולה — הוא מכוון על פינה ולא רואה כלום,
  וזה בדיוק מה שתסכל אותו.
- זה תופס גם על כלי עזר וכלי מדידה, לא רק על ציור קירות.

איפה זה נשבר בפועל (כדי לזהות את זה מהר בפעם הבאה): כלי העיגון החדש קרא
ל-`snapPoint` בלחיצה, אבל צייר את הסמן על `cursor` הגולמי — הנעילה עבדה
ולא נראתה. וגם: `orthoNow` אופס בסוף `snapPoint` במקום בהתחלה, בזמן שכל
נעילות הנקודה עושות `return` מוקדם — אז הדגל נשאר מהתזוזה הקודמת.

## חוק: כל חלון חדש נפתח במלואו (2026-09-18)

הוא ביקש את זה יותר מפעם אחת: *"כל פעם שאנחנו יוצרים חלון חדש לכלי כל
שהוא הוא יפתח במלואו ולא צריך יהיה להגדיל אותו כדי לראות את הכל."*

**כל `UI::HtmlDialog` חדש מקבל את מנגנון `fit_height`** — הדף מודד את
עצמו אחרי שנטען (`ipFitWindow` ב-JS, `scrollHeight` של ה-body) וקורא
ל-`sketchup.fit_height(h)`, והרובי עושה `dlg.set_size(width, h + 46)` עם
מינימום ומקסימום. התבנית: `floor_dialog.rb`, `roof_dialog.rb`,
`tile_wall_edit_tool.rb`. חלון שנפתח עם כפתור מתחת לגלילה = באג.

## חוק: כל פקודת CMD מתחילה ב-cd לתיקיית התוסף (2026-09-18)

ה-CMD שלו נפתח ב-`C:\Users\rordt`, לא בתיקיית התוסף, וכל פקודת git בלי
cd לפניה נופלת על `fatal: not a git repository`. זה קרה פעמיים באותו יום.

**כל הוראת CMD נפתחת תמיד בשורה הזאת, באותה קופסה, גם בפעם העשירית:**

```
cd /d "C:\Users\rordt\AppData\Roaming\SketchUp\SketchUp 2024\SketchUp\Plugins\interior_pro"
```

## חוק: אפשר לדקור פינה או סוף קו, וזה נמתח לשם (2026-09-18)

הוא כתב: *"אם אני מצייר קיר שהוא מקביל לקיר אחר או למשהו אחר אני רוצה שיהיה
אפשר לדקור פינה או סוף של קו והקיר יימתח אוטומטית לשם, כמו בכל דבר
בסקצ'אפ. תכניס את זה לחוקים שזה יהיה ככה לעתיד, נמאס לי להזכיר לך."*

צודק, וזה חוק:

**כל כלי בסקצ'אפ שלוקח נקודה מהעכבר חייב לקבל נעילה על גיאומטריה שאינה
שלו — פינה, סוף קו, אמצע — ולמתוח את מה שהוא בונה עד לשם.**

- הנקודה מגיעה מ-`view.inputpoint(x, y)`, שזה מנוע ההסקה של סקצ'אפ עצמו.
  אם `ip.vertex` קיים, או `ip.degrees_of_freedom == 0`, **ננעלנו על נקודה
  אמיתית** — ואז היא מנצחת, גם אם היא על אובייקט אחר לגמרי.
- נקודה כזאת **מוקרנת** על המישור שהכלי עובד עליו. קיר מקביל, קצה של רהיט,
  סוף של קו עזר — כולם נותנים מידה, וזאת בדיוק המידה שהוא רצה.
- **מציירים איפה שננעל.** ירוק = פינה או סוף קו, ציאן = אמצע,
  מג'נטה = על קצה. בלי טבעת = לא ננעל כלום. אותם צבעים בכל הכלים.
- אותה נקודה בדיוק לתזוזה ולקליק. זה החוק של 2026-09-23, והוא תופס גם כאן.

איפה זה כבר עשוי: `TileWallTool.face_point`, `TileWallStretchTool.edge_value`.
בדיקות: `rt175`, `rt178`.

## חוק: זווית ישרה מנצחת (2026-09-23)

בלשונו: *"זה חייב להינעל על 90 מעלות של פינה גם אם יש סטייה של 10 מעלות
לכאן או לכאן... אני לא יכול לבזבז על זה כל כך הרבה זמן, ואם אני ארצה משהו
אחר אני אשנה את זה ידנית."*

- `ORTHO_SNAP_DEG = 12` — הזווית הישרה נבדקת ראשונה ובחלון רחב.
- `DIAG_SNAP_DEG = 5` — 45 מעלות רק אם מכוונים אליו ממש.
- כשהנעילה על 90 תפסה, `applyParallel` **לא רץ** — אחרת קיר ישן שעומד על
  88 מעלות גורר אליו כל קיר חדש.
- **אסור לעגל קואורדינטות אחרי שהזווית ננעלה.** זה היה הבאג של 89.8/90.2:
  `snapPoint` נעל 90 מדויק ואז עיגל את **שתי** הקואורדינטות לחצי אינץ' —
  וחצי אינץ' לרוחב קיר של 22 רגל הוא `atan(0.5/264)` = 0.11 מעלות. מעגלים
  את **האורך**, ומשאירים את הכיוון מדויק (`out.exact`).
- **ליישר פינה אחת בכל פעם לא יכול לעבוד.** כל קיר נוגע בשתי פינות, אז
  תיקון פינה מזיז קצה ששייך לשכנה, וזה לעולם לא מתכנס — הוא נתקל בזה
  והתעצבן בצדק. הכפתור **"פינות 90°"** פותר את **כל** הלולאה יחד:
  כל קיר מקבל ציר אמיתי (X או Y, האדום והירוק — לא רק ניצב לשכן, כדי
  שהבית לא יישאר מסובב באלכסון), וכל פינה משותפת נוחתת על נקודת החיתוך
  של שני הצירים. `squareUpWalls` + `square_up_walls!`.
- `tests/t55.js`, `tests/t57.js`.

## חוק: ב-JS שבתוך plan_editor.rb אין `\d` — רק `[0-9]` (2026-09-24)

ה-JS של העורך יושב בתוך heredoc של רובי, ורובי מוחק לוכסן בודד:
`/^\d+$/` מגיע לדפדפן בתור `/^d+$/`. הכלי "לא עשה כלום", והבדיקה על
הפונקציה הטהורה עברה. לכן כל הקוד הקיים כותב `[0-9]`, `\\s`, `\\.`.
ובדיקה לכלי עם מקלדת עוברת דרך המקלדת: `__listeners.__win.keydown[0]`
(ראה סוף `tests/t56.js`).

## חוק: קיר רק מתארך או מתקצר — אף פעם לא מתעקם (2026-09-24)

בלשונו: *"השכן חייב להישאר יציב."* אחרי שבוע של פינות 89.9 שהוא לא ידע
להסביר, נמדדו שני מקורות, ושניהם הפרו את אותו חוק:

- **נקודה לא מנצחת זווית ישרה.** נעילה על פינה / אמצע / פאה / קצה של קו
  מה-PDF קובעת את **האורך** בלבד; הכיוון נלקח מהציר (`ORTHO_SNAP_DEG`).
  `pointHit` ב-`snapPoint`. `tests/t58.js`.
- **הארכת קיר לא מזיזה את השכן הצידה.** הקצה של השכן מחליק רק על הקו
  של עצמו (`slideEndAlong` בחלון, אותו דבר ב-`stretch_wall!`). שכן ניצב
  לא זז בכלל — המיטר סוגר את הפינה. `tests/t59.js`, `tests/rt54.rb`.
- הכפתור "פינות 90°" **בוטל על ידו** — נשאר מאחורי `USE_SQUARE_UP = false`.
  לא לפתוח מחדש. הציור עצמו חייב לצאת ישר.
- **העיגון** (2026-09-24, העיצוב שלו): קליק על פינה → מספר → Enter.
  מספר חדש = הפינה נהיית עוגן; מספר קיים = **המבנה** שבפינה עובר לשם.
  0 = ראשית הצירים. `HANDOFF_2026-09-24.md`.

כלל אצבע לכל כלי חדש שמזיז קצה של קיר: אם אתה כותב `sx = np.x` על קיר
שהמשתמש לא נגע בו — עצור. זה הקיר שיצא 89.9.

## חוק: בדיקה שעוברת על החישוב לא מוכיחה שהכלי עובד (2026-09-23)

היום שתי תכונות נשלחו עם בדיקות ירוקות ושתיהן היו שבורות אצלו. הסיבה
זהה בשתיהן: הבדיקה בדקה את **הפונקציה הטהורה** ולא את **המסלול האמיתי**.

- `t56` בדקה ש-`alignPendingToOrigin` מזיז נכון את `pending` — אבל בזרימה
  שלו רוב הקירות כבר במודל (לחיצה על דלת/חלון מריצה Apply אוטומטי), אז
  חצי מהקומה זזה וחצי לא.
- `t57` בדקה ש-`squareUpWalls` מחשב נכון — אבל כל התקלה הייתה בצד הרובי,
  ב-`square_up_walls!`, שאין לו שום בדיקה.

**אם התכונה נוגעת במודל — חייבת גם בדיקת רובי (rt), לא רק JS.**
ולפני "זה עובד": לעבור על המסלול שהוא באמת עושה, כולל מה שכבר הוחל.

## חוק: `next unless x` בלי `puts` הוא באג שמחכה (2026-09-23)

`square_up_walls!` דילג בשקט בשתי שורות (`next unless data`,
`... if c2`). התוצאה: התכונות נכתבו, הגיאומטריה לא נבנתה, והוא ראה שינוי
רק אחרי הפעלה מחדש של סקצ'אפ. לא הייתה שום דרך לדעת בלי לוג.
**כל דילוג שקט בקוד שכותב למודל מקבל `puts` עם שם הקיר והסיבה.**

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

## איך מדברים איתו — הוא חזר על זה, אז זה חוק (2026-09-22)

בלשונו: *"בבקשה תדבר איתי במשפטים פשוטים, שאתה שואל או מסביר משפט או
שתיים, כאילו אני ילד בן 5."*

- **משפט או שניים בכל תשובה.** לא פסקה, לא הרצאה, לא רשימה של הסברים.
- **כל פקודה בקופסה נפרדת**, ומעליה כתוב איפה להדביק: **Ruby Console**
  או **CMD**. גם אם זו אותה פקודה בפעם העשירית.
- **אל תניח שהוא יודע מה הצעד הבא.** בלשונו: *"אם צריך לעדכן אותו או כל
  שלב הבא שאני צריך לעשות, אתה צריך להגיד לי ולא לצפות שאני יודע."*
  אחרי כל שינוי קוד תכתוב לו במפורש: reload, לסגור ולפתוח את החלון,
  מה ללחוץ, ומה הוא אמור לראות. ממוספר.
- **שאלה אחת קצרה בכל פעם.** כשלא ברור מה לא עובד — שתי אפשרויות
  ממוספרות והוא בוחר מספר. זה חסך סבב שלם היום.
- הוא כותב לפעמים עברית במקלדת אנגלית. לפענח לבד, לא לשאול.

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

## הצעד הנוכחי: רצפת מקלחת (2026-09-23)

חלון משלה + אריחים + עריכה + שטחים + **הסכר** + **הביובים שבאמצע** (מרובע,
מרובע עם אריח ותעלה, עגול) — **כולם נסגרו**. קרא `HANDOFF_2026-09-22E.md`.
הביוב הארוך ליד קיר נבנה (רשימת קירות, 2" מהקיר, rt215) — שני הסוגים אושרו ("עובד יפה מאוד"), ותפריט הביובים בציורים.

חוק מהסבב הזה: חור **קמור** בפריסת אריחים נחתך בבת אחת, לא במשולשים —
משולשים יוצרים רסיסים שנזרקים והרובה הלבנה נראית (`pieces_minus_holes`,
rt214).

## חוק: כלי חדש = העתקה של חלון/כלי קיים, שדה-שדה (2026-09-22)

בלשונו: *"פשוט תשתמש בקודים הקיימים ותעתיק אותם לאחד חדש, כבר הכל פועל
כמו שצריך בחלונות אחרים."* חלון המקלחת הוא `floor_dialog.rb` מועתק, עם
אותם שמות attributes, ולכן `FloorPattern` והספירה עובדים עליו בלי קוד
חדש. אל תבנה "גרסה קטנה משלך" (UI.inputbox עם 4 שדות) — זה מה שבזבז
שלושה צ'אטים.

## חוק: חור ברצפה חי על הרצפה, כמו חלון על קיר (2026-09-22)

בלשונו: *"תתקן את זה כמו חלון לקיר."* המספרים של החור (`shower_holes`)
יושבים על קבוצת הרצפה, והפלטה והפריסה **נבנות מראש עם החור** בכל
Build Floors. **לא חותכים גיאומטריה בדיעבד** — נמדד שסקצ'אפ לא חותך
פאה בקו שעובר מעל הגבול שלה, וגם כשמוסיפים נקודות חיתוך חתיכה נשארה
שלמה. `FloorPattern.pieces_minus_holes` הוא הדרך. ובניקוי: קו שעדיין
מחזיק פאה לא נמחק לעולם — מחיקת קו כזה מחקה אריח שלם והשאירה כתם לבן.

## Current phase: the RENDERING program (set by the user, 2026-09-18)

(The old "doors only" restriction is retired - it was from the 2026-04 phase
and no longer applies. Doors, windows, walls, floors, roofs, moldings and the
2D editor are all live code now.)

CURVED WALLS and 2D PLANS TO PDF are DONE and off the list - he closed both
himself: "קירות מעוגלים כבר קיימים וגם PDF, תעיף אותם מהרשימה של המטלות".
Do not re-open either as a priority; a bug in one is a bug, not a phase.

The valley - the garage roof running into the house - was closed on
2026-09-18, all five steps. See `HANDOFF_2026-09-18.md`.

Next: the rendering program = **Interior Pro ↔ Claude API ↔ V-Ray**. It IS
written down now: `VRAY_POC_PLAN.md` in the project root (2026-09-15) -
what it is, who controls what (he designs, Claude tunes V-Ray, V-Ray
renders), the one architecture rule (Claude returns NUMBERS, never code;
the plugin validates and calls predefined V-Ray functions), why it comes
BEFORE the Tile system, the smallest POC, and what was agreed on cost and
quality. Read it before the first step. The first step is a measuring
file - what V-Ray exposes to Ruby on HIS machine - not the docs.

## TODO the user asked to come back to (do not lose)

- **כמה דפי שרטוט בעורך הדו-ממד** (2026-09-23, בלשונו): *"שאני אוכל לפתוח
  כמה דפים לסירטוטים שונים — נגיד יש לי סירטוט שהוא רק סירטוט ולא 3D ואני
  רוצה לשלוח אותו ישירות לתוכניות, או עוד איזה מבנה שארצה לעשות לחוד — אוכל
  לפתוח דף חדש של סירטוט בתוכנה ולסרטט."* כלומר: דף שרטוט חדש ונפרד בעורך,
  שלא חייב להפוך לתלת-ממד, ושאפשר לשלוח אותו ישר לתוכניות (PDF). נרשם בלבד,
  לא התחלנו. לשאול אותו איך זה ייראה לפני שבונים.

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

## חוק: כל כלי של הנישה נכנס לקבוצה של הנישה בסרגל (2026-09-22)

בלשונו: *"כל תוסף לניץ של עריכה, הזזה או מחיקה — תוסיף את זה בתחום
ההפרדה של הניץ."* סרגל המשטחים: ארבעת הכפתורים הישנים, קו מפריד, ואחריו
רק כפתורי הנישה (`niche_buttons` ב-`setup_surfaces_toolbar`). כפתור חדש
נכנס **לסוף** `niche_buttons` — אף פעם לא לאמצע רשימה קיימת (reload רק
מוסיף, והכנסה באמצע שכפלה את Edit Tile). ולא סרגל חדש: סרגל שהיה פתוח
חוזר ריק אחרי שסוגרים אותו בקוד.

## Kill switches (turn a feature off without deleting it)

- `InteriorPro::ShowerFloor::USE_CURB = false` - the raised shower floor
  gets no curb and keeps its whole loop (2026-09-22, `tests/rt209.rb`).
- `InteriorPro::ShowerFloor::USE_DRAIN = false` - no drain is built and the
  shower tiles and pad stay whole (2026-09-22, `tests/rt211.rb`).
- `InteriorPro::ShowerFloor::USE_WALL_JOINTS = false` - "grout lines follow
  the walls" is ignored; the shower grid is laid as before (`tests/rt210.rb`).
- `InteriorPro::TileNiche::USE_NICHES = false` - no niche is cut; the
  stored numbers stay on the wall (2026-09-22, `tests/rt192.rb`).
- `InteriorPro::SkylightManager::USE_SKYLIGHTS = false` - no skylight can
  be placed; nothing standing is touched (2026-09-14).
- `InteriorPro::SkylightManager::USE_SKYLIGHT_SHAFT = false` - a skylight
  cuts the roof only; the ceiling under it is left whole (2026-09-14).

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

### Curved walls - what is wired up (re-measured 2026-09-13)

The old list here said openings, battens and roofs were "not wired up yet".
That list was from 2026-08-10 and had gone STALE - three of its five items
were built in the weeks after and nobody came back to cross them off. It
sent a later chat looking for bugs that did not exist. Measured against the
live code:

- Openings on a curved wall - BUILT. `read_door_openings` feeds
  `curved_footprint_xy`, `punch_curved_openings!` cuts them,
  `RESEAT_OPENINGS_ON_CURVE` carries doors and windows onto the new shape.
- Board and Batten on a curved wall - BUILT. `curved_batten_stations` /
  `batten_stations` walk the arc, `batten_z_bands` breaks a batten around
  an opening.
- Roof over a curved wall - BUILT. `RoofManager.wall_center_arc` returns
  the centreline as an arc and the eave edge is an arc, not a segment.
- The 2D editor draws and bends curved walls (2026-08-12): typed bow in the
  עובי·קשת panel - typed plus = OUTWARD, stored sag is the negative, see
  uiSagToModel/modelSagToUi and `tests/t33.js`.

Still straight, genuinely:

- `plan_generator.rb` - the PRINTED plan (a different file from the 2D
  editor, which is fine). `wall_plan_data` reads only `start_x/y` and
  `end_x/y` and builds `u`, `len`, `seg_points` off the straight line;
  `arc_sag` does not appear in the file at all. A curved wall prints as a
  straight poche band.
- Butt joints (interior wall meeting an exterior one) still use the
  straight line, not the tangent. Not re-measured.
- An INWARD-bulging arc meeting a wall at a shallow angle can leave a
  tooth-sized overlap on the outside - accepted, see the weld rule above.

If you change any of this, fix THIS list in the same step. A stale list
costs a whole chat.

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
