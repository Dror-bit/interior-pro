# debug_molding_side2.rb - diagnosis only, does NOT modify the model.
# Prints room polygons + per exterior wall: both side probes and room hits.
rooms = []
Sketchup.active_model.entities.grep(Sketchup::Group).each do |g|
  next unless g.valid? && g.get_attribute('InteriorPro', 'type') == 'room'
  flat = g.get_attribute('InteriorPro', 'boundary_xy')
  next unless flat && flat.length >= 6
  poly = flat.each_slice(2).map { |x, y| Geom::Point3d.new(x.to_f, y.to_f, 0) }
  rooms << { name: g.get_attribute('InteriorPro', 'name'), poly: poly }
end
puts "== #{rooms.length} rooms =="
rooms.each do |r|
  pts = r[:poly].map { |p| "(#{p.x.to_f.round(1)},#{p.y.to_f.round(1)})" }.join(' ')
  puts "#{r[:name]}: #{pts}"
end

ws = InteriorPro::MoldingManager.walls
puts "== #{ws.length} walls =="
ws.each_with_index do |w, i|
  cat = (w.get_attribute('InteriorPro', 'wall_category') || 'nil').to_s
  edges = InteriorPro::MoldingBuilder.wall_edges(w)
  unless edges
    puts "wall#{i} id=#{w.get_attribute('InteriorPro', 'id').to_s[-4..]} cat=#{cat} NO EDGES"
    next
  end
  line = format('wall%-2d id=%s cat=%-8s', i, w.get_attribute('InteriorPro', 'id').to_s[-4..].to_s, cat)
  %i[pos neg].each do |s|
    geo = InteriorPro::MoldingBuilder.edge_geometry(w, edges[s])
    next unless geo
    probe = geo[:p0].offset(geo[:u], geo[:len] / 2.0).offset(geo[:nd], 2.0)
    hit = rooms.find { |r| Geom.point_in_polygon_2D(probe, r[:poly], true) }
    e = geo[:p0].offset(geo[:u], geo[:len])
    line += format(' | %s p0=(%.1f,%.1f) p1=(%.1f,%.1f) probe=(%.1f,%.1f) room=%s',
                   s, geo[:p0].x, geo[:p0].y, e.x, e.y, probe.x, probe.y,
                   hit ? hit[:name] : '-')
  end
  puts line
end
puts '== done =='
