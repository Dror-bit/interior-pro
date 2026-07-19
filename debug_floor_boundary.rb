# debug_floor_boundary.rb - diagnosis only, does NOT modify the model.
# Prints each room's boundary polygon + checks for duplicate points and
# self-intersections (the usual reasons add_face fails).
def seg_cross?(a, b, c, d)
  d1x = b[0] - a[0]
  d1y = b[1] - a[1]
  d2x = d[0] - c[0]
  d2y = d[1] - c[1]
  den = d1x * d2y - d1y * d2x
  return false if den.abs < 1e-9
  t = ((c[0] - a[0]) * d2y - (c[1] - a[1]) * d2x) / den
  s = ((c[0] - a[0]) * d1y - (c[1] - a[1]) * d1x) / den
  t > 0.001 && t < 0.999 && s > 0.001 && s < 0.999
end

Sketchup.active_model.entities.grep(Sketchup::Group).each do |r|
  next unless r.valid? && r.get_attribute('InteriorPro', 'type') == 'room'
  flat = r.get_attribute('InteriorPro', 'boundary_xy')
  name = r.get_attribute('InteriorPro', 'name')
  unless flat && flat.length >= 6
    puts "#{name}: NO boundary_xy"
    next
  end
  pts = flat.each_slice(2).map { |x, y| [x.to_f, y.to_f] }
  puts "== #{name} (#{r.get_attribute('InteriorPro', 'id')}) #{pts.length} pts =="
  puts pts.map { |x, y| "(#{x.round(1)},#{y.round(1)})" }.join(' ')
  dups = []
  pts.each_with_index do |p, i|
    q = pts[(i + 1) % pts.length]
    dups << i if (p[0] - q[0]).abs < 0.01 && (p[1] - q[1]).abs < 0.01
  end
  segs = pts.each_index.map { |i| [pts[i], pts[(i + 1) % pts.length]] }
  crossings = []
  segs.each_with_index do |(a, b), i|
    segs.each_with_index do |(c, d), j|
      next if j <= i + 1
      next if i.zero? && j == segs.length - 1
      crossings << [i, j] if seg_cross?(a, b, c, d)
    end
  end
  area = 0.0
  pts.each_with_index do |p, i|
    q = pts[(i + 1) % pts.length]
    area += p[0] * q[1] - q[0] * p[1]
  end
  puts "  dup_pts_at=#{dups.inspect} crossings=#{crossings.inspect} area=#{(area / 2.0 / 144.0).round(1)} sqft"
end
puts '== done =='
