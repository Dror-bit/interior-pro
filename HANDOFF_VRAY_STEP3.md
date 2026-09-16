# Interior Pro ↔ V-Ray — שלב 3 (2026-09-16 ערב) — הכתיבה נתפסת ורואים ברינדור

קרא עם `HANDOFF_VRAY_STEP2.md` ו-`VRAY_POC_PLAN.md`.
**כל שורה כאן היא מדידה עם קובץ דוח בשורש.**

## מה נסגר היום — הראשון שמראה משהו ברינדור

**הרינדור הראה את זה.** קיר אחד (חומר `IP_FRESH_1789531182`) יצא מראה,
כל שאר הבית נשאר כמו שהיה. המשתמש: "רק הקיר שסימנתי היה מראה, אני
רואה את זה בברור." (דוח: `vray_userdata_report.txt`, 14:58.)

## למה זה חזר אחורה עד עכשיו — התאום

`vray_dump_report.txt` מראה ש-`BRDFVRayMtl` מחזיק ליד ה-params גם
`userdata`, ושם לכל כפתור שאפשר לשים עליו טקסטורה יש **תאום**:

```
reflect_glossiness_float = 1,  reflect_glossiness_tex = "",
reflect_glossiness_tex_on = 1, reflect_glossiness_tex_mult = 1
reflect_color = [0,0,0],       reflect_tex = "" ...
metalness_float = 0 ...
```

ל-`fresnel` **אין** תאום. כל כפתור שחזר אחורה — יש לו תאום; היחיד שנתפס —
אין לו. V-Ray for SketchUp בונה מחדש את ה-param האמיתי מהתאום אחרי כל
commit. לכן:

- כתיבה ל-`b[:reflect_glossiness]` → 0.05 בתוך הבלוק, 1.0 אחריו
  (`vray_float_report.txt`, גם עם Asset Editor סגור — ההשערה על ה-UI
  נפסלה).
- כתיבה ל-`b[:reflect_glossiness_float]` → נשאר 0.05, וגם ה-param
  האמיתי מתעדכן ל-0.05 (`vray_userdata_report.txt`).

## הדרך שעובדת (זה החוק מעכשיו)

```ruby
scene = VRay::Context.active.scene
m = scene['/' + mat.display_name]        # או VRay::Material.load(mat).main_plugin
scene.change do
  b = m[:brdf]                           # את הידית לוקחים בתוך הבלוק
  b[:reflect_color]            = VRay::Color.new(1.0, 1.0, 1.0)
  b[:reflect_glossiness_float] = 0.05    # במצב Use Roughness: 0.05 = מראה
  b[:fresnel]                  = false   # אין תאום — כותבים ישר
  b[:option_use_roughness]     = true
end
```

- **סימבולים בלבד** בתוך `scene.change`. מחרוזת מפילה את סקצ'אפ.
- כפתור עם תאום → כותבים ל-`<שם>_float` / `<שם>_color`. בלי תאום → ישר.
  איך יודעים: `m[:brdf].dump` ולחפש ב-`userdata`.
- `m[:brdf]` נלקח **בתוך** הבלוק.

## הצעד הבא

1. `material_library.rb` → `apply_vray_numbers!` כותב היום דרך
   `convert_to_vray` (לא מגיע לרינדור). להחליף לקוד למעלה, מאחורי
   `USE_MATERIAL_LIBRARY`. צעד קטן, ואז רינדור.
2. ייבוא `.vrmat` לתוך ה-scene החי (`scene.import`? יש ב-scene methods:
   `import, import_buffer, import_plugins`) — עדיין לא נמדד.

## קבצי מדידה מהיום

- `debug_vray_pick.rb` — מה מסומן (פעמיים היה 0 — צריך כלי חץ + קליק).
- `debug_vray_float.rb` — כפתור-כפתור: float חוזר, int נשאר.
- `debug_vray_userdata.rb` — **הטוב**: כותב לתאומים, נשאר.
- `debug_vray_after_render.rb` — קריאה בלבד אחרי רינדור (לא הורץ).
