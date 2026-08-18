# encoding: utf-8
# Interior Pro - Automatic project backup (2026-08-15)
#
# WHY
#
# "I go out and take measurements, I trace the whole thing, I come home and
# everything is deleted." That must never be possible again, and no button
# the user has to remember to press can promise it.
#
# So: every few minutes this saves a COPY of the whole project into a folder
# beside it. Not the state, not the draft - the entire .skp. If anything at
# all goes wrong, from a bug of ours to a crash to a wrong click, there is a
# whole file from a few minutes ago sitting on the disk.
#
# HOW IT BEHAVES
#
# - It runs by itself. Nothing to press, nothing to switch on.
# - It uses save_copy, so the file the user is working on is NOT touched and
#   the title bar never changes. He cannot tell it happened.
# - Copies go to `InteriorPro_backups` next to the project, named with the
#   date and time so the newest is obvious.
# - It keeps the newest KEEP copies and deletes the rest, so the folder
#   cannot grow forever.
# - A model that has never been saved still gets backed up, into the user's
#   Documents. That is the case where losing everything hurts most.
# - It can never take SketchUp down with it: every step is wrapped, and a
#   failure just means no copy this time.
#
# TO TURN IT OFF
#   InteriorPro::AutoBackup.stop!

module InteriorPro
  module AutoBackup

    # The user's choice, 2026-08-15.
    EVERY_SECONDS = 300 unless const_defined?(:EVERY_SECONDS, false)

    # How many copies to keep. 20 x 5 minutes is over an hour and a half of
    # history, which is far more than the few minutes anyone actually needs.
    KEEP = 20 unless const_defined?(:KEEP, false)

    FOLDER = 'InteriorPro_backups' unless const_defined?(:FOLDER, false)

    UNSAVED_BASE = 'Untitled' unless const_defined?(:UNSAVED_BASE, false)

    # ------------------------------------------------------------- naming
    #
    # Pure string work, kept apart from the disk so it can be proved right
    # without writing a single file.

    def self.stamp_for(at)
      at.strftime('%Y-%m-%d_%H%M%S')
    end

    # The project's name without its extension. An unsaved model has no name.
    def self.base_for(model_path)
      p = model_path.to_s
      return UNSAVED_BASE if p.empty?
      b = File.basename(p, '.*')
      b.empty? ? UNSAVED_BASE : b
    end

    # Where the copies live: beside the project. An unsaved project has no
    # "beside", so its copies go somewhere the user can actually find.
    def self.backup_dir(model_path, home = nil)
      p = model_path.to_s
      return File.join(fallback_home(home), FOLDER) if p.empty?
      File.join(File.dirname(p), FOLDER)
    end

    def self.fallback_home(home = nil)
      h = (home || ENV['USERPROFILE'] || ENV['HOME'] || '.').to_s.tr('\\', '/')
      docs = File.join(h, 'Documents')
      File.directory?(docs) ? docs : h
    end

    def self.backup_name(model_path, at)
      "#{base_for(model_path)}_#{stamp_for(at)}.skp"
    end

    # Which files to delete, given everything currently in the folder.
    # Pure: a list of names in, a list of names out. Newest KEEP survive.
    #
    # Only files belonging to THIS project are ever considered - a second
    # project backing up into the same folder must not have its copies
    # deleted by this one.
    def self.prune_list(names, base, keep = KEEP)
      mine = Array(names).select do |n|
        n.to_s.start_with?("#{base}_") && n.to_s.end_with?('.skp')
      end
      # The stamp sorts chronologically as text, so newest first is just a
      # reverse sort - no dates to parse and get wrong.
      mine.sort.reverse.drop([keep.to_i, 0].max)
    end

    # --------------------------------------------------------------- doing

    # One backup, right now. Returns the path written, or nil.
    def self.tick!(model = Sketchup.active_model)
      return nil unless model
      return nil unless worth_backing_up?(model)
      path = model.path.to_s
      dir  = backup_dir(path)
      Dir.mkdir(dir) unless File.directory?(dir)
      out = File.join(dir, backup_name(path, Time.now))
      return nil if File.exist?(out)          # same second, nothing new to say
      model.save_copy(out)
      prune!(dir, base_for(path))
      @last = out
      out
    rescue StandardError => e
      puts "[AutoBackup] #{e.class}: #{e.message}"
      nil
    end

    def self.last
      @last
    end

    # An empty model is not work. Backing it up would only push real copies
    # out of the folder.
    def self.worth_backing_up?(model)
      model.entities.length > 0
    rescue StandardError
      false
    end

    def self.prune!(dir, base, keep = KEEP)
      names = Dir.entries(dir)
      prune_list(names, base, keep).each do |n|
        begin
          File.delete(File.join(dir, n))
        rescue StandardError => e
          puts "[AutoBackup] could not remove #{n}: #{e.message}"
        end
      end
    rescue StandardError => e
      puts "[AutoBackup] prune!: #{e.message}"
      nil
    end

    # ------------------------------------------------------------- the timer

    def self.running?
      !@timer.nil?
    end

    # Starting twice must not leave two timers running - reload! calls this
    # again every time, and two timers would double the copies and halve the
    # history for no reason.
    def self.start!(seconds = EVERY_SECONDS)
      stop!
      @timer = UI.start_timer(seconds.to_f, true) { tick! }
      puts "[AutoBackup] on - a copy of the project every #{(seconds.to_f / 60).round} min"
      @timer
    rescue StandardError => e
      puts "[AutoBackup] start!: #{e.class}: #{e.message}"
      @timer = nil
    end

    def self.stop!
      return false unless @timer
      begin
        UI.stop_timer(@timer)
      rescue StandardError
        nil
      end
      @timer = nil
      true
    end

  end
end
