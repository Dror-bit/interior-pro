# encoding: utf-8
# rt319 - THE KITCHEN FACE BY A RAY (2026-10-15 14:26, his "המתגים והשקעים יושבים מאחורי הקאונטר טופ באק ספלאש"; measured
# elec_face_report: the backsplash is one L-shaped solid 1.5" thick, its box 145.9" deep, so the box rule skipped it and the
# outlet and the switch stayed at 0.375 behind its face). A ray finds the face; our own plates are passed through.
require './sketchup_stub'
require './electrical_library'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
L = InteriorPro::ElectricalLibrary
ok('kill switch is there and on', L::USE_KITCHEN_RAY == true)
Tag = Struct.new(:dict, :key, :val) do
  def get_attribute(d, k); d == dict && k == key ? val : nil; end
end
# the wall face along x, the room toward +y (n = 0,1)
fr = { ox: 0.0, oy: 0.0, ux: 1.0, uy: 0.0, nx: 0.0, ny: 1.0, floor_z: 0.0 }
plate = Tag.new('InteriorPro', 'type', 'electrical')
splash = Tag.new('KitchenLab', 'kind', 'worktop')
cab = Tag.new('KitchenLab', 'kind', 'kitchen_unit')
Fake = Struct.new(:faces) do      # faces: [[y of the face, path]] nearest the room first
  def raytest(ray, _w = true)
    p, = ray
    f = faces.find { |y, _| y < p.y - 1e-9 }
    f ? [Geom::Point3d.new(p.x, f[0], p.z), f[1]] : nil
  end
end
m1 = Fake.new([[0.582, [plate]], [1.5, [splash]], [0.0, []]].sort_by { |y, _| -y })
ok('the backsplash face 1.5 off the wall is found, through our own plate', (L.kitchen_face_ray(fr, 95.8, 98.5, 39.8, 44.3, m1) - 1.5).abs < 1e-9,
   L.kitchen_face_ray(fr, 95.8, 98.5, 39.8, 44.3, m1))
m2 = Fake.new([[0.0, []]])
ok('bare wall: 0', L.kitchen_face_ray(fr, 10, 13, 15, 20, m2) == 0.0)
m3 = Fake.new([[24.0, [cab]], [0.0, []]])
ok('a cabinet in front (24" deep) is not a face to stand on', L.kitchen_face_ray(fr, 10, 13, 15, 20, m3) == 0.0)
m4 = Fake.new([[5.0, [splash]], [0.0, []]])
ok('a kitchen face farther than KITCHEN_FRONT_MAX does not count', L.kitchen_face_ray(fr, 10, 13, 40, 44, m4) == 0.0)
ok('no raytest (stub model): 0, no crash', L.kitchen_face_ray(fr, 10, 13, 40, 44, Object.new) == 0.0)
src = File.read('./electrical_library.rb')
ok('check and refront! take the larger of the box rule and the ray',
   src.scan('kitchen_face_ray(fr, u0, u1, z0, z1').size == 3 && src.include?('kf = [kf, kitchen_face_ray(fr, u0, u1, z0, z1, model)].max'))
ok(%q(refront! can run inside the kitchen operation (op: false): no operation of its own), src.include?(%q(def self.refront!(model = Sketchup.active_model, op: true))) && src.include?(%q(start_operation(%q(Electrical To The Face), true) if op).sub(%q(%q(Electrical To The Face)), %q('Electrical To The Face'))) && src.include?(%q(model.commit_operation if op)))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
