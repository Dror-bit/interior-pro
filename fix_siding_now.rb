# encoding: utf-8
# Rebuild the 3D siding on every wall that has it (2026-09-12).
#
# The boards used to be measured off the wall's WORLD bounds and built in
# the wall's OWN space, so on an upper storey they stood one storey too
# high - the sticks over the roof. The code is fixed; this puts the boards
# back where they belong on the walls that already have the bad ones.
#
#   load 'C:/Users/rordt/AppData/Roaming/SketchUp/SketchUp 2024/SketchUp/Plugins/interior_pro/fix_siding_now.rb'
module InteriorPro
  module FixSidingNow
    NAMES = ['Board and Batten', 'Horizontal Siding'].freeze

    def self.run!
      model = Sketchup.active_model
      walls = InteriorPro::LevelManager.all_walls.select do |w|
        NAMES.include?(w.get_attribute('InteriorPro', 'exterior_material').to_s)
      end
      if walls.empty?
        puts '[FixSiding] no wall uses 3D siding - nothing to do'
        return nil
      end
      model.start_operation('InteriorPro Fix Siding', true)
      wt = InteriorPro::WallTool.new
      walls.each do |w|
        mat = w.get_attribute('InteriorPro', 'exterior_material').to_s
        before = [w.bounds.min.z.round(2), w.bounds.max.z.round(2)]
        wt.add_exterior_siding(w, mat)
        after = [w.bounds.min.z.round(2), w.bounds.max.z.round(2)]
        h = w.get_attribute('InteriorPro', 'height').to_f
        b = w.get_attribute('InteriorPro', 'base_z').to_f
        puts "[FixSiding] #{w.get_attribute('InteriorPro', 'id')} #{mat}: " \
             "bounds #{before.inspect} -> #{after.inspect}  (should be [#{b.round(2)}, #{(b + h).round(2)}])"
      end
      model.commit_operation
      puts "[FixSiding] #{walls.length} wall(s) redone. Now rebuild the roofs:"
      puts '  InteriorPro::RoofManager.roofs.each { |r| InteriorPro::RoofManager.build_roof!(replace: r) }'
      nil
    rescue StandardError => e
      begin
        model.abort_operation
      rescue StandardError
        nil
      end
      puts "[FixSiding] failed: #{e.message}"
      puts e.backtrace.first(6).join("\n")
      nil
    end
  end
end

InteriorPro::FixSidingNow.run!
