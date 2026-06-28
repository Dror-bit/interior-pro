# עיצוב — מיטר פינות לקירות עם פתח (מוכן ליישום+בדיקה)

> מסמך תכנון בלבד. **לא יושם בקוד.** ליישום רק אחרי אישורך ועל סצנה נקייה.

## הבעיה
קיר **בלי** פתח כבר מתמטר נכון — `build_geometry_in_group` בונה אותו מ-`corners_xy` (פינות ממוטרות). קיר **עם** פתח נבנה ב-`build_wall_with_openings_oriented` מ-`drawn_start/end` ישר, ומתעלם מ-`corners_xy`. לכן הפינה לא נסגרת (החור כן שורד).

## תובנה חדשה (חשובה)
הניסיון הקודם למיטר (`apply_native_miter_corners!`) "שבר" עריכה/מחיקה/הזזה של דלת. אבל עכשיו אנחנו יודעים שהזרימות האלה היו שבורות **בלאו הכי** (boolean/fill). כלומר חוסר-היציבות שיוחס למיטר היה ככל הנראה **הבאג הקיים של עריכת-הדלת, לא הזזת-הקודקודים**. עכשיו שדלתות הן native ונקיות — הסיבוך הזה נעלם, וסביר שהגישה תעבוד.

## הגישה המומלצת (B): בנייה ישרה + הזזת קודקודי-קצה ל-`corners_xy`
שומר על "לבנות את החור" (לא חותך), מינימלי, ומשתמש ב-`transform_by_vectors` (מתועד). המיטר הופך **אינטגרלי** לבנייה — אחרי כל rebuild (כולל עריכת דלת) הקיר נבנה עם הפינה הנכונה.

### הקוד (להוספה ל-`wall_tool.rb`)
מתודה חדשה (class method) מתחת ל-`build_wall_with_openings_oriented`:

```ruby
    def self.apply_native_miter_corners!(wall, drawn_start, drawn_end, thickness_f, h_anchor)
      return unless wall&.valid?
      flat = wall.get_attribute('InteriorPro', 'corners_xy')
      return unless flat && flat.length == 8
      mit = [[flat[0], flat[1]], [flat[2], flat[3]], [flat[4], flat[5]], [flat[6], flat[7]]]

      dx = drawn_end.x - drawn_start.x
      dy = drawn_end.y - drawn_start.y
      len = Math.sqrt(dx * dx + dy * dy)
      return if len < 0.001
      half = thickness_f / 2.0
      nx = -dy / len * half
      ny =  dx / len * half
      case h_anchor
      when 'left'
        perp = [[drawn_start.x + nx * 2, drawn_start.y + ny * 2],
                [drawn_end.x   + nx * 2, drawn_end.y   + ny * 2],
                [drawn_end.x,            drawn_end.y],
                [drawn_start.x,          drawn_start.y]]
      when 'right'
        perp = [[drawn_start.x,          drawn_start.y],
                [drawn_end.x,            drawn_end.y],
                [drawn_end.x   - nx * 2, drawn_end.y   - ny * 2],
                [drawn_start.x - nx * 2, drawn_start.y - ny * 2]]
      else
        perp = [[drawn_start.x + nx, drawn_start.y + ny],
                [drawn_end.x   + nx, drawn_end.y   + ny],
                [drawn_end.x   - nx, drawn_end.y   - ny],
                [drawn_start.x - nx, drawn_start.y - ny]]
      end

      tol = 0.01
      verts = wall.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
      move_verts = []
      move_vecs  = []
      perp.each_with_index do |(px, py), i|
        mx, my = mit[i]
        next if (mx - px).abs < tol && (my - py).abs < tol
        verts.each do |v|
          pos = v.position
          next unless (pos.x - px).abs < tol && (pos.y - py).abs < tol
          move_verts << v
          move_vecs  << Geom::Vector3d.new(mx - px, my - py, 0)
        end
      end
      return if move_verts.empty?
      wall.entities.transform_by_vectors(move_verts, move_vecs)
    rescue StandardError => e
      puts "[WallTool] apply_native_miter_corners!: #{e.message}"
    end
```

חיבור: ב-`rebuild_wall_native_geometry!`, מיד אחרי הקריאה ל-`build_wall_with_openings_oriented(...)` ולפני `paint_wall_long_faces!`, להוסיף שורה:
```ruby
      apply_native_miter_corners!(wall, drawn_start, drawn_end, thickness_f, h_anchor)
```

### למה זה בטוח עכשיו
- no-op אוטומטי כשאין מיטר (perp == corners_xy) או כשאין `corners_xy`.
- עוטף ב-rescue.
- מזיז רק את 8 קודקודי הקצוות; קודקודי הפתח באמצע לא נוגעים.
- הזרימות שקרסו קודם (עריכה/מחיקה) כבר native ונקיות.

## חלופה (A): footprint extrude + חיתוך פתח
לבנות מ-`corners_xy` (footprint ממוטר) → pushpull לגובה → לחתוך כל פתח דרך הפאה. יותר "קנוני" ומאוחד עם קירות בלי-פתח, אבל **מחזיר חיתוך** (pushpull-through) שנטשנו, וכתיבה גדולה יותר. סיכון גבוה יותר. לא מומלץ כצעד ראשון.

## בדיקת clean-room (חובה לפני commit)
1. קיר חדש + קיר שני שנפגשים בפינה.
2. דלת על אחד מהם.
3. הפינה נסגרת במיטר נקי? הקיר `manifold?`?
4. **רגרסיה:** עריכה/הזזה/מחיקה של הדלת — עדיין עובדות וללא חורים? (זה מה שנשבר קודם — חובה לוודא.)
5. רק אם הכל ירוק → commit.

## אם זה שוב שובר משהו
`USE_NATIVE_OPENINGS` לא קשור; פשוט להעיר את שורת החיבור (`# apply_native_miter_corners!...`) ולעשות reload — חוזרים מיד למצב היציב הנוכחי.
