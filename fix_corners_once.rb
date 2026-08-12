# encoding: utf-8
# Interior Pro - one command: reload the code, PROVE the new code is loaded,
# re-join every corner, and verify every curve seam. Safe to run again.
#
# Ruby Console:
#   load 'C:/Users/rordt/AppData/Roaming/SketchUp/SketchUp 2024/SketchUp/Plugins/interior_pro/fix_corners_once.rb'

begin
  InteriorPro.reload!
rescue StandardError => e
  puts "[fix] reload נכשל: #{e.message}"
end

wt = InteriorPro::WallTool
missing = []
missing << 'weld_corner!' unless wt.instance_methods.include?(:weld_corner!)
missing << 'CURVE_MITER_REACH' unless wt.const_defined?(:CURVE_MITER_REACH)

if missing.any?
  puts "[fix] *** הקוד החדש לא נטען! חסר: #{missing.join(', ')} ***"
  puts '[fix] סגור את סקצ׳אפ לגמרי, פתח מחדש, והרץ שוב את אותה שורה.'
else
  puts '[fix] קוד עדכני טעון (weld + reach cap).'
  model = Sketchup.active_model
  tool  = wt.new
  walls = model.active_entities.grep(Sketchup::Group)
               .select { |g| g.get_attribute('InteriorPro', 'type') == 'wall' }
  model.start_operation('InteriorPro Fix Corners', true)
  begin
    2.times { walls.each { |w| tool.join_corners(w, model) } }
    model.commit_operation
    puts "[fix] הפינות חושבו מחדש על #{walls.size} קירות."
  rescue StandardError => e
    model.abort_operation
    puts "[fix] נכשל, כלום לא השתנה: #{e.message}"
  end

  bad = 0
  curved = walls.select { |w| wt.curved_wall?(w) }
  puts "[fix] קירות מעוגלים במודל: #{curved.size}"
  curved.each do |cw|
    [%w[start_x start_y], %w[end_x end_y]].each do |kx, ky|
      px = cw.get_attribute('InteriorPro', kx).to_f
      py = cw.get_attribute('InteriorPro', ky).to_f
      nb = walls.find do |o|
        next false if o == cw
        [%w[start_x start_y], %w[end_x end_y]].any? do |okx, oky|
          Math.hypot(o.get_attribute('InteriorPro', okx).to_f - px,
                     o.get_attribute('InteriorPro', oky).to_f - py) < 1.0
        end
      end
      next unless nb
      c1 = cw.get_attribute('InteriorPro', 'corners_xy')
      c2 = nb.get_attribute('InteriorPro', 'corners_xy')
      unless c1.is_a?(Array) && c1.length == 8 && c2.is_a?(Array) && c2.length == 8
        puts "[fix] ! פינה (#{px.round}, #{py.round}) בלי corners שמורים"
        bad += 1
        next
      end
      p1 = c1.each_slice(2).to_a
      p2 = c2.each_slice(2).to_a
      shared = p1.any? { |a| p2.any? { |b| Math.hypot(a[0] - b[0], a[1] - b[1]) < 0.1 } }
      if shared
        puts "[fix] פינה (#{px.round}, #{py.round}) — תפר משותף, תקין"
      else
        puts "[fix] ! פינה (#{px.round}, #{py.round}) — אין תפר משותף"
        bad += 1
      end
    end
  end
  if bad.zero?
    puts '[fix] סיום: כל הפינות עם קשת תקינות. פתח מחדש את עורך ה-2D.'
  else
    puts "[fix] סיום עם #{bad} בעיות — תעתיק לי את כל הפלט."
  end
end
