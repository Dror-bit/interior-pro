# encoding: utf-8
# cleanup_test_materials - removes ONLY the throwaway materials this
# session created, and only if NO face anywhere uses them. Anything the
# user painted with is left alone, no matter what it is called.
module IPCleanup
  OUT = File.join(File.dirname(__FILE__), 'cleanup_report.txt')
  PATTERNS = [/\AIP_VRMAT_/, /\AIP_FRESH_/, /\AIP_VRAY_TEST\z/, /\AStucco#\d+\z/]

  def self.say(l)
    File.open(OUT, 'a') { |f| f.puts l ; f.flush ; (f.fsync rescue nil) }
    puts "[cleanup] #{l}"
  end

  def self.used_names(model)
    used = Hash.new(0)
    collect = lambda do |ents|
      ents.grep(Sketchup::Face).each do |f|
        used[f.material.display_name.to_s] += 1 if f.material
        used[f.back_material.display_name.to_s] += 1 if f.back_material
      end
    end
    collect.call(model.entities)
    model.definitions.each { |d| collect.call(d.entities) }
    used
  end

  def self.run
    File.open(OUT, 'w') { |f| f.puts "==== #{Time.now} ====" }
    model = Sketchup.active_model
    used = used_names(model)

    doomed = model.materials.select do |m|
      n = m.display_name.to_s
      PATTERNS.any? { |p| n =~ p } && used[n].zero?
    end

    if doomed.empty?
      say 'nothing to remove'
      return UI.messagebox('אין מה למחוק.')
    end

    say "removing #{doomed.length}:"
    doomed.each { |m| say "  #{m.display_name}" }

    model.start_operation('Interior Pro: cleanup test materials', true)
    gone = 0
    doomed.each do |m|
      begin
        model.materials.remove(m)
        gone += 1
      rescue StandardError => e
        say "  could not remove #{m.display_name}: #{e.message}"
      end
    end
    model.commit_operation
    say "removed #{gone}"
    UI.messagebox("נמחקו #{gone} חומרי בדיקה.")
  rescue StandardError => e
    (Sketchup.active_model.abort_operation rescue nil)
    say "ERR #{e.class}: #{e.message}"
  end
end
IPCleanup.run
