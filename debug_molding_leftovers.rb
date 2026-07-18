# debug_molding_leftovers.rb - diagnosis only, does NOT modify the model.
# Finds molding leftovers: nested molding groups, loose top-level edges/faces,
# and stray edges inside wall groups near the baseboard zone.
model = Sketchup.active_model

def ip_scan(ents, path, out)
  ents.each do |e|
    next unless e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    t = e.get_attribute('InteriorPro', 'type').to_s
    nm = e.respond_to?(:name) ? e.name.to_s : ''
    label = "#{path}/#{nm.empty? ? e.class.to_s.split('::').last : nm}"
    out << "#{label} type=#{t} depth=#{path.count('/')}" if %w[baseboard crown].include?(t) || %w[Baseboard Crown].include?(nm)
    inner = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
    ip_scan(inner, label, out)
  end
end

out = []
ip_scan(model.entities, '', out)
puts "== molding-like groups found: #{out.length} =="
out.each { |l| puts l }

loose_edges = model.entities.grep(Sketchup::Edge)
loose_faces = model.entities.grep(Sketchup::Face)
puts "== loose TOP-LEVEL entities: edges=#{loose_edges.length} faces=#{loose_faces.length} =="
loose_edges.first(10).each do |e|
  s = e.start.position
  f = e.end.position
  puts format('edge z=%.2f..%.2f (%.1f,%.1f)->(%.1f,%.1f)', s.z, f.z, s.x, s.y, f.x, f.y)
end

puts '== stray low horizontal edges inside walls (z 0.1-8, not face borders) =='
model.entities.grep(Sketchup::Group).each do |g|
  next unless g.get_attribute('InteriorPro', 'type') == 'wall'
  strays = g.entities.grep(Sketchup::Edge).select do |e|
    z1 = e.start.position.z
    z2 = e.end.position.z
    (z1 - z2).abs < 0.01 && z1 > 0.1 && z1 < 8.0
  end
  next if strays.empty?
  puts "wall id=#{g.get_attribute('InteriorPro', 'id').to_s[-4..]}: #{strays.length} edge(s) at z=#{strays.map { |e| e.start.position.z.round(2) }.uniq.inspect}"
end
puts '== done =='
