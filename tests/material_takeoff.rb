# encoding: utf-8
# Interior Pro - HOW MUCH OF EACH MATERIAL (2026-09-18)
#
# WHY. He does not want a material card in the plugin - his own business
# software already holds supplier, code and price, pulled by its clipper.
# What it cannot know is how much of each material his DESIGN uses. That
# is the one number only the model has: "Stone - 412 sq ft".
#
# It feeds two things: the table he types into his software, and the
# plans he produces.
#
# HOW. Every face in the model is measured and charged to a material.
# Two rules that decide whether the number is right:
#   1. A face with no material of its own wears the material of the
#      GROUP or COMPONENT it sits in - that is what SketchUp shows, so
#      that is what has to be counted. The walk carries that down.
#   2. A face inside a scaled or mirrored instance is not the size it
#      is drawn at. Every area is measured THROUGH the transformation
#      it is seen with.
# A material is charged by its permanent id (material_ids.rb), never by
# name - the whole reason that id exists.
#
# No kill switch: this reads the model and writes a text file. It builds
# no geometry and changes nothing, so there is nothing to switch off.
module InteriorPro
  module MaterialTakeoff
    SQIN_PER_SQFT = 144.0
    NO_MATERIAL = '(no material)'.freeze

    # PURE. Square inches to square feet, rounded the way a quantity is
    # read: two decimals.
    def self.sqft(sqin)
      (sqin.to_f / SQIN_PER_SQFT).round(2)
    end

    # PURE. Add up [key, area] pairs. Returns { key => [total, count] }.
    def self.tally(pairs)
      out = {}
      Array(pairs).each do |(k, a)|
        next if k.nil?
        area = a.to_f
        next if area <= 0.0
        row = (out[k] ||= [0.0, 0])
        row[0] += area
        row[1] += 1
      end
      out
    end

    # PURE. The tally as rows, biggest first. `names` maps key -> the
    # name to show; a key with no name shows the key.
    def self.rows(tally, names = {})
      tally.map do |k, (sqin, faces)|
        { key: k, name: (names[k] || k).to_s, faces: faces,
          sqin: sqin.round(2), sqft: sqft(sqin) }
      end.sort_by { |r| -r[:sqin] }
    end

    # PURE. One line per material, for his software.
    def self.to_csv(rows)
      out = ["material_id,name,area_sqft,area_sqin,faces"]
      rows.each do |r|
        nm = r[:name].to_s.gsub('"', '""')
        nm = %("#{nm}") if nm =~ /[,"]/
        out << "#{r[:key]},#{nm},#{r[:sqft]},#{r[:sqin]},#{r[:faces]}"
      end
      out.join("\n")
    end

    # The material a face really wears: its own, else the one painted on
    # its back, else the material of the group it lives in.
    def self.face_material(face, inherited = nil)
      face.material || face.back_material || inherited
    rescue StandardError
      inherited
    end

    # Walk the model. `acc` collects [key, area] pairs and `names` the
    # display name for each key.
    def self.collect(entities = nil, tr = nil, inherited = nil,
                     acc = [], names = {})
      entities ||= Sketchup.active_model.entities
      entities.each do |e|
        next unless e.respond_to?(:valid?) ? e.valid? : true
        case e
        when Sketchup::Face
          mat = face_material(e, inherited)
          key = material_key(mat)
          names[key] ||= mat.nil? ? NO_MATERIAL : mat.display_name.to_s
          acc << [key, face_area(e, tr)]
        when Sketchup::Group, Sketchup::ComponentInstance
          sub = e.is_a?(Sketchup::Group) ? e.entities : e.definition.entities
          next if sub.nil?
          own = (e.material rescue nil) || inherited
          t2 = combine(tr, (e.transformation rescue nil))
          collect(sub, t2, own, acc, names)
        end
      end
      [acc, names]
    rescue StandardError => e
      puts "[MaterialTakeoff] collect: #{e.message}"
      [acc, names]
    end

    # The permanent id if the material has one, its name if it somehow
    # does not, and NO_MATERIAL for a bare face.
    def self.material_key(mat)
      return NO_MATERIAL if mat.nil?
      id = defined?(InteriorPro::MaterialIds) ? InteriorPro::MaterialIds.id_of(mat) : nil
      id || mat.display_name.to_s
    rescue StandardError
      NO_MATERIAL
    end

    # Measured THROUGH the transformation it is seen with - a face in a
    # scaled instance is not the size it was drawn.
    def self.face_area(face, tr = nil)
      return face.area(tr) if tr && face.method(:area).arity != 0
      face.area
    rescue StandardError
      begin
        face.area
      rescue StandardError
        0.0
      end
    end

    def self.combine(a, b)
      return b if a.nil?
      return a if b.nil?
      a * b
    rescue StandardError
      a
    end

    # The whole answer for a model.
    def self.take(model = nil)
      model ||= Sketchup.active_model
      acc, names = collect(model.entities)
      rows(tally(acc), names)
    end

    # Write it next to the plugin: a table to read and a csv to feed his
    # software.
    def self.report!(model = nil, dir = nil)
      model ||= Sketchup.active_model
      dir ||= File.dirname(__FILE__)
      rs = take(model)
      txt = []
      txt << "TIME #{Time.now}"
      txt << "model: #{model.title}"
      txt << "materials used: #{rs.length}"
      txt << format('total: %.2f sq ft', rs.sum { |r| r[:sqft] })
      txt << ''
      txt << format('   %-38s %12s %10s %7s', 'material', 'sq ft', 'sq in', 'faces')
      rs.each do |r|
        txt << format('   %-38s %12.2f %10.0f %7d',
                      r[:name].to_s[0, 38], r[:sqft], r[:sqin], r[:faces])
      end
      File.write(File.join(dir, 'takeoff_report.txt'), txt.join("\n") + "\n")
      File.write(File.join(dir, 'takeoff.csv'), to_csv(rs) + "\n")
      rs.length
    rescue StandardError => e
      puts "[MaterialTakeoff] report!: #{e.message}"
      0
    end
  end
end
