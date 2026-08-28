# fix_orphan_holes.rb - CHANGES THE MODEL. One operation, one Ctrl+Z.
# Closes every hole in a roof skin that has NO dormer standing over it, and
# erases every bare line left inside it. A hole under a standing dormer is
# never touched.
module InteriorPro
  module FixOrphanHoles
    def self.run
      model = Sketchup.active_model
      model.start_operation('Close orphan roof holes', true)
      total = 0
      InteriorPro::RoofManager.roofs.each_with_index do |roof, ri|
        ents = roof.entities
        boxes = []
        ents.grep(Sketchup::Group).each do |g|
          next unless g.get_attribute('InteriorPro', 'type').to_s == 'dormer'
          b = InteriorPro::DormerManager.dormer_plan_box(g, 2.0)
          boxes << b if b
        end
        orphans = []
        ents.grep(Sketchup::Face).each do |f|
          next if f.normal.z.abs < 0.2
          next unless f.respond_to?(:loops) && f.loops.length > 1
          f.loops.each do |lp|
            next if lp.outer?
            ps = lp.vertices.map(&:position)
            covered = boxes.any? do |b|
              ps.all? do |p|
                p.x.to_f >= b[0] && p.x.to_f <= b[1] &&
                  p.y.to_f >= b[2] && p.y.to_f <= b[3]
              end
            end
            next if covered
            orphans << [lp, f, ps]
          end
        end
        puts format('[Fix] roof %d: %d dormer(s), %d orphan hole(s)',
                    ri, boxes.length, orphans.length)
        orphans.each do |lp, host, ps|
          box = [ps.map(&:x).min.to_f - 1.0, ps.map(&:x).max.to_f + 1.0,
                 ps.map(&:y).min.to_f - 1.0, ps.map(&:y).max.to_f + 1.0]
          total += 1 if InteriorPro::DormerManager.close_loop!(ents, lp, host, nil)
          InteriorPro::DormerManager.heal_box!(ents, box)
        end
        # AND LAY THE FIELD AGAIN. Closing the deck does not put the panels
        # back - they were laid while the hole was there, so the hole is
        # still in them: "ניסגר אבל רק השכבה שמתחת לפנלים ולא הפנלים עצמם".
        next if orphans.empty?
        InteriorPro::DormerManager.relay_runs!(roof)
      end
      model.commit_operation
      puts "[Fix] closed #{total} orphan hole(s)"
      total
    rescue StandardError => e
      model.commit_operation rescue nil
      puts "[FixOrphanHoles] #{e.message}"
      puts e.backtrace.first(6)
      0
    end
  end
end
InteriorPro::FixOrphanHoles.run
