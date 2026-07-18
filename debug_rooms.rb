# debug_rooms.rb - diagnosis only, does NOT modify the model.
# Prints the room-detection graph: segments, nodes, edges, traced faces.
RM = InteriorPro::RoomManager unless defined?(RM)
segs = RM.wall_list.map { |w| RM.centerline(w) }.compact
puts "== centerline segs=#{segs.length} =="
segs2 = RM.split_at_tees(segs)
puts "== after split_at_tees: #{segs2.length} =="
segs2.each_with_index do |sg, i|
  puts format('seg%-2d th=%.1f (%7.1f,%7.1f)->(%7.1f,%7.1f) w=%s', i, sg[:th],
              sg[:s].x.to_f, sg[:s].y.to_f, sg[:e].x.to_f, sg[:e].y.to_f,
              sg[:w].get_attribute('InteriorPro', 'id').to_s[-4..].to_s)
end
nodes, edges = RM.build_graph(segs)
puts "== nodes=#{nodes.length} =="
nodes.each_with_index { |n, i| puts format('node%-2d (%7.1f,%7.1f)', i, n.x.to_f, n.y.to_f) }
puts "== edges=#{edges.length} =="
edges.each_with_index do |e, i|
  puts format('edge%-2d %2d-%-2d th=%.1f w=%s', i, e[:a], e[:b], e[:th],
              e[:wall].get_attribute('InteriorPro', 'id').to_s[-4..].to_s)
end
faces = RM.trace_faces(nodes, edges)
puts "== faces=#{faces.length} =="
faces.each_with_index do |f, i|
  poly = f[:node_ids].map { |ni| nodes[ni] }
  puts format('face%-2d area=%10.1f nodes=%s', i, RM.signed_area(poly), f[:node_ids].inspect)
end
puts '== done =='
