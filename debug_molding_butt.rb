# debug_molding_butt.rb - diagnosis only, does NOT modify the model.
# Prints the molding plan runs and what resolve_miters!/resolve_tees! detect.
model = Sketchup.active_model
ws = InteriorPro::MoldingManager.walls(model)
cent = {}
InteriorPro::MoldingManager.wall_components(ws).each do |comp|
  cc = InteriorPro::MoldingManager.house_centroid(comp)
  comp.each { |w| cent[w] = cc }
end
plan = []
ws.each do |w|
  next if w.get_attribute('InteriorPro', 'no_molding')
  edges = InteriorPro::MoldingBuilder.wall_edges(w)
  next unless edges
  InteriorPro::MoldingManager.sides_for(w, cent[w]).each do |s|
    geo = InteriorPro::MoldingBuilder.edge_geometry(w, edges[s])
    next unless geo
    plan << { wall: w, side: s, edge: edges[s], geo: geo,
              shifts: { start: 0, end: 0 }, tee_gaps: [] }
  end
end
wid = ->(w) { w.get_attribute('InteriorPro', 'id').to_s[-4..] }
cat = ->(w) { (w.get_attribute('InteriorPro', 'wall_category') || 'ext').to_s[0, 3] }
puts "== #{ws.length} walls, #{plan.length} runs =="
plan.each_with_index do |r, i|
  g = r[:geo]
  e = g[:p0].offset(g[:u], g[:len])
  puts format('run%-2d w=%s(%s) %-4s len=%6.1f p0=(%7.1f,%7.1f) p1=(%7.1f,%7.1f)',
              i, wid[r[:wall]], cat[r[:wall]], r[:side], g[:len],
              g[:p0].x, g[:p0].y, e.x, e.y)
end
puts '== proximity: run endpoints vs other runs (within 6") =='
tol = InteriorPro::MoldingManager::MITER_TOL
plan.each_with_index do |stub, i|
  g = stub[:geo]
  [[g[:p0], :start], [g[:p0].offset(g[:u], g[:len]), :end]].each do |pt, which|
    plan.each_with_index do |r, j|
      next if r.equal?(stub)
      rg = r[:geo]
      v = Geom::Vector3d.new(pt.x - rg[:p0].x, pt.y - rg[:p0].y, 0)
      t = v.dot(rg[:u])
      off = Math.sqrt([(v.length**2) - t**2, 0.0].max)
      next if off > 6 || t < -6 || t > rg[:len] + 6
      flags = []
      flags << 'NEAR-END' if t < tol || t > rg[:len] - tol
      flags << 'SAME-WALL' if r[:wall] == stub[:wall]
      flags << 'OFF>TOL' if off > tol
      puts format('run%d.%-5s -> run%d: t=%8.2f/%6.1f off=%5.2f %s',
                  i, which, j, t, rg[:len], off, flags.join(' '))
    end
  end
end
InteriorPro::MoldingManager.resolve_miters!(plan)
InteriorPro::MoldingManager.resolve_tees!(plan)
puts '== resolved shifts / tee gaps =='
plan.each_with_index do |r, i|
  puts format('run%-2d w=%s(%s) %-4s shifts=%s tees=%s',
              i, wid[r[:wall]], cat[r[:wall]], r[:side],
              r[:shifts].inspect, r[:tee_gaps].inspect)
end
puts '== done =='
