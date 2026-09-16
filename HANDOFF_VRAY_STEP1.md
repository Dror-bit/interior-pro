# Interior Pro ↔ V-Ray — שלב 1 מוכח (2026-09-15)

קרא את זה עם `VRAY_POC_PLAN.md`. **אל תסמוך על הסיכום — תאמת מול הקוד החי.**

## מה נסגר היום

V-Ray 7.40.02 הותקן על הווינדוס (SketchUp 2024). נמדד — לא נוחש — שהתוסף
**יכול לקרוא ולשנות חומר של V-Ray מרובי**. זה שלב 1 בתוכנית, פריטים 3–4.

השרשרת המלאה, כל חוליה נמדדה:

```ruby
VRay::MaterialSync.to_vray(skp_material)   # חומר סקצ'אפ -> V-Ray (כותב VRayInfo+VRayPlugins)
vm   = VRay::Material.load(skp_material)   # הידית. klass = "_HostMaterial" בשלב הזה
plug = vm.convert_to_vray                  # -> VRay::Scene::Plugin, klass נהיה "MtlSingleBRDF"
brdf = plug[:brdf]                         # -> VRay::Scene::Plugin, type = :BRDFVRayMtl
brdf[:reflect_glossiness]                  # 1.0
brdf[:reflect_glossiness] = 0.6            # ונקרא בחזרה 0.6000000238418579
```

### חמישה דברים שעלו דם ושאסור לאבד

1. **`VRay::Scene::Plugin` מקבל סימבול, לא מחרוזת.** `plug["brdf"]` זורק
   `TypeError: wrong argument type String (expected Symbol)`. זה היה הקיר
   שחזר שוב ושוב.
2. **`VRay::Material.load` נכשל על חומר רגיל** (`UserFriendlyError: Failed to
   load special object`). חייבים `MaterialSync.to_vray` לפניו.
   `VRay::Material.valid?(mat)` הוא `false` עד שממירים.
3. **`convert_to_vray` מחזיר `nil` על חומר שכבר הומר.** חומר שורד
   `abort_operation`, אז הרצה שנייה על אותו שם החזירה nil ורדפתי אחרי ריק
   דוח שלם. כל הרצת בדיקה מייצרת שם חדש ומוחקת אותו בסוף.
4. **`MaterialTranslate.find_brdf(vm)` מחזיר `nil`** — לא הדרך פנימה.
   הדרך היא `plug[:brdf]`, או `plug.each_child` (מחזיר
   `/NAME/BRDFVRayMtl (BRDFVRayMtl)`).
5. **`VRay::Context.active` הפיל את סקצ'אפ.** `debug_vray_set.rb` נפל בלי
   שום הודעה; `debug_vray_trace.rb`, שכותב לדיסק לפני כל צעד, עבר את כל
   אותם צעדים חוץ מהחלק הזה. **לא לגעת ב-Context עד שיש סיבה.**

## הכפתורים עצמם (מתוך `BRDFVRayMtl` האמיתי, לא מהתיעוד)

| פרמטר | מה זה | מה נמדד |
|---|---|---|
| `:reflect` | כמה מחזיר אור | `VRay::Color` |
| `:reflect_glossiness` | חד (1.0) ↔ מטושטש | `1.0` |
| `:option_use_roughness` | האם לעבוד ב-roughness | `true` |
| `:roughness` | חספוס | `0.0` |
| `:diffuse` | הצבע הבסיסי | `VRay::Color` |

בגרף של חומר אמיתי (`wood2`) יש גם `/Bump`, `/Displacement`,
`TexBitmap` + `BitmapBuffer` (עם נתיב הקובץ) ו-`UVWGenChannel` (קנה מידה
וכיוון). כלומר PBR ו-UV נגישים — בדיוק מה ש-Tile צריך לדעת.

## קבצי המדידה (לא ב-git, `debug_*.rb`)

| קובץ | מה הוא ענה |
|---|---|
| `debug_vray_api.rb` | איזו גרסה, איזה מודול. `VRay` קיים, 186 קבועים |
| `debug_vray_mat.rb` | V-Ray שומר גרף plugins כ-JSON על החומר עצמו |
| `debug_vray_brdf.rb` | שמות הפרמטרים האמיתיים על `BRDFVRayMtl` |
| `debug_vray_args.rb` | ה-arity של כל פונקציה — `load(entity)`, `find(plugin_name, context:)` |
| `debug_vray_convert.rb` | ההמרה עובדת; הידית עובדת |
| `debug_vray_plugin2.rb` | סימבול ולא מחרוזת |
| `debug_vray_trace.rb` | **הקובץ הטוב** — קורא, כותב, וקורא בחזרה. עבר במלואו |
| `debug_vray_set.rb` | **מפיל את סקצ'אפ** (Context). לא להריץ |

## הצעד הבא

לשנות חומר **אמיתי** במודל שלו ולרנדר, כדי לראות את ההבדל בעיניים.
`debug_vray_apply.rb` לוקח את החומר של הפאה המסומנת, מחיל מספרים, ומשאיר
את השינוי במודל (`commit_operation`) — Undo רגיל מחזיר. הרינדור עצמו נעשה
בכפתור של V-Ray, ידנית: `VRay.start_render` דורש 3 ארגומנטים שלא נמדדו,
ואין סיבה לנחש אותם עכשיו.

אחרי שזה נראה במסך — שלב 2: קריאה אחת לקלוד שמחזירה את המספרים.

---

# תיקיית החומרים — נבנה באותו יום (2026-09-15)

אחרי שהרינדור עבד הוא ביקש דבר אחר לפני שלב 2: *"אני רוצה שבפלאג אין יהיה
אפשרות גם לבחור לווירי חומרים מהתיקיה שאני בונה לו."* נבנה ועובד אצלו.

## איך זה בנוי

- `material_library.rb` — הקריאה והכתיבה. כל חומר = כרטיס JSON אחד
  (`IP_MAT_0019.json`) + התמונה ב-`textures/`. הכרטיס נושא שם, צבע,
  גודל האריח, ומספרי V-Ray.
- `material_library_dialog.rb` — חלון הריבועים, עם עץ תיקיות.
- כפתור **Materials** בטולבר (`toolbar.rb`), אייקון `icons/material_library.svg`.
- התיקייה נשמרת **פר-התקנה** (`Sketchup.write_default`,
  `material_library_folder`) ויושבת ב-OneDrive, אז המאק יקבל אותה.
  אצלו: `C:\Users\rordt\OneDrive\InteriorPro\materials`.

## שני דברים שהוא קבע ואסור להפוך

1. **התיקיות בחלון, לא בדיסק.** בלשונו: *"לא איכפת לי שכל החומרים ישמרו
   ביחד במחשב אבל כשאני פותח חומר אני רוצה שזה יהיה מסודר"* — עץ כמו
   `חומרי חוץ / סטאקו, אבנים, לנדסקייפ`. לכן לכל כרטיס יש שדה `path`,
   העץ עצמו יושב ב-`folders.json` (כדי שתיקייה ריקה לא תיעלם), והקבצים
   שטוחים. כרטיס שכן יושב בתת-תיקייה בדיסק מקבל את שמה כ-`path` — מה
   שסידר ביד קודם לא הולך לאיבוד.
2. **מחיקת תיקייה לא מוחקת חומרים** — הם עולים לתיקייה שמעליה.

לחצן ימני על תיקייה: שנה שם / מחק / העבר לתוך. לחצן ימני על חומר: החל /
שנה שם / מחק / העבר. גרירת חומר על תיקייה מעבירה אותו. השורה העליונה
נקראת **"כל החומרים"** (הוא ביקש את השם הזה במפורש) ואינה תיקייה.

## הקריאה של מספרי V-Ray — לא דרך ה-API

`vray_numbers_from_dict` קורא את ה-JSON ש-V-Ray עצמו כותב לתוך
`VRayPlugins` על החומר. זה נבחר **אחרי** ש-`convert_to_vray` החזיר nil
על חומר שכבר הומר ואין דרך מתועדת חזרה לאובייקט (ו-`VRay::Context.active`
מפיל את סקצ'אפ). קריאה מהמילון לא נוגעת ב-API בכלל ולכן לא יכולה להפיל.
`vray_numbers` (דרך ה-API) נשאר כגיבוי.

## מה נשאר פתוח כאן

- **המספרים בכרטיס הם המקוריים.** שינינו ברק ל-0.75 והרינדור הראה את זה,
  אבל ה-`VRayPlugins` על החומר עדיין אמר 1.0 — כלומר השינוי חי בזיכרון
  של V-Ray ולא נכתב חזרה על החומר. לבדוק לפני שבונים "החל מספרים של קלוד".
- החלת חומר מהתיקייה מחזירה תמונה + גודל + צבע, אבל **לא** מחילה עדיין
  את מספרי ה-V-Ray שבכרטיס.
- אין עדיין מפתח PBR (normal/roughness maps) בכרטיס — צריך ל-Tile.
