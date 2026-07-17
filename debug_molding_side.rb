# debug_molding_side.rb - diagnosis only, does NOT modify the model.
# Prints every wall's category and which sides get molding.
ws = InteriorPro::MoldingManager.walls
cent = {}
InteriorPro::MoldingManager.wall_components(ws).each do |comp|
  cc = InteriorPro::MoldingManager.house_centroid(comp)
  comp.each { |w| cent[w] = cc }
end
puts "== rooms=#{InteriorPro::MoldingManager.room_polys.length} walls=#{ws.length} =="
ws.each_with_index do |w, i|
  sides = begin
    InteriorPro::MoldingManager.sides_for(w, cent[w])
  rescue StandardError => e
    "ERR: #{e.message}"
  end
  puts format('wall%-2d id=%s cat=%-8s len=%7.1f sides=%s%s',
              i,
              w.get_attribute('InteriorPro', 'id').to_s[-4..].to_s,
              (w.get_attribute('InteriorPro', 'wall_category') || 'nil').to_s,
              w.get_attribute('InteriorPro', 'length_in').to_f,
              sides.inspect,
              w.get_attribute('InteriorPro', 'no_molding') ? ' EXCLUDED' : '')
end
puts '== done =='
