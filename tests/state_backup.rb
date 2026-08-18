# encoding: utf-8
# Interior Pro - State Backup (2026-08-15)
#
# WHY THIS FILE EXISTS
#
# The user lost a day's tracing. The 2D editor parks unapplied work on the
# model as a draft (`plan_draft`). He pressed "Apply to Model", the build
# quietly produced nothing, and the window then wrote an EMPTY draft straight
# over the good one. One attribute, overwritten in a fraction of a second,
# and both the work and its only copy were gone.
#
# The lesson is not "fix that one button". It is that anything the user made
# and cannot make again must not be replaceable by a single write. So every
# piece of saved state in the plugin goes through this file, and every write
# keeps the version it replaced.
#
# HOW IT WORKS
#
# write!(key, json) does three things, in this order:
#   1. reads what is there now
#   2. if it is different from what is about to be written, pushes it onto a
#      history list kept beside it
#   3. writes the new value
#
# Nothing is ever deleted by a write - only pushed back one place. The
# history is bounded, both by count and by bytes, so a big draft cannot bloat
# the .skp without limit.
#
# WHAT IT DELIBERATELY DOES NOT DO
#
# It does not decide whether a write is a good idea. That is the caller's
# job, and the caller usually knows more (the editor now refuses to clear a
# draft when the build returned nothing). This file is the net UNDER that
# decision, for the day the decision is wrong again.
#
# RECOVERY, FOR A PANICKING FUTURE SESSION
#
#   InteriorPro::StateBackup.list                 # what is recoverable
#   InteriorPro::StateBackup.report               # same, written to a file
#   InteriorPro::StateBackup.restore!('plan_draft')      # newest backup
#   InteriorPro::StateBackup.restore!('plan_draft', 2)   # two versions back

require 'json'

module InteriorPro
  module StateBackup

    DICT = 'InteriorPro' unless const_defined?(:DICT, false)

    # How many old versions to keep per key.
    KEEP = 6 unless const_defined?(:KEEP, false)

    # Total bytes of history allowed per key. Oldest entries are dropped
    # until the history fits. A .skp that grows without limit helps nobody.
    MAX_BYTES = 3_000_000 unless const_defined?(:MAX_BYTES, false)

    # A single value larger than this is not worth keeping copies of.
    MAX_ONE = 1_500_000 unless const_defined?(:MAX_ONE, false)

    # The keys this plugin backs up. Listed so `list` and `report` can find
    # everything without being told, and so a new piece of state is added in
    # ONE place. Anything not listed still works - write! takes any key.
    KNOWN_KEYS = %w[
      plan_draft
      sheet_state
      sheet_site_lines
      underlay_state
    ].freeze unless const_defined?(:KNOWN_KEYS, false)

    def self.history_key(key)
      "#{key}__history"
    end

    # ------------------------------------------------------------ writing

    # The one door every saved state goes through.
    # Returns true if the value was written.
    def self.write!(key, value, model = Sketchup.active_model)
      return false unless model
      k   = key.to_s
      new = value.to_s
      old = model.get_attribute(DICT, k).to_s

      # Nothing changed - the editor autosaves every 1.5 seconds, and without
      # this the history would fill up with identical copies within a minute
      # and push the real earlier versions out.
      if old == new
        model.set_attribute(DICT, k, new)
        return true
      end

      push_history!(k, old, model) unless old.empty?
      model.set_attribute(DICT, k, new)
      true
    rescue StandardError => e
      puts "[StateBackup] write! #{key}: #{e.class}: #{e.message}"
      false
    end

    def self.push_history!(key, old_value, model = Sketchup.active_model)
      return if old_value.to_s.empty?
      return if old_value.to_s.bytesize > MAX_ONE
      list = history(key, model)
      list.unshift({ 'at' => stamp, 'bytes' => old_value.to_s.bytesize,
                     'json' => old_value.to_s })
      list = list.first(KEEP)
      # Trim by bytes, oldest first, but never drop the newest one.
      while list.length > 1 &&
            list.map { |h| h['bytes'].to_i }.inject(0) { |a, b| a + b } > MAX_BYTES
        list.pop
      end
      model.set_attribute(DICT, history_key(key), JSON.generate(list))
    rescue StandardError => e
      puts "[StateBackup] push_history! #{key}: #{e.class}: #{e.message}"
    end

    # ------------------------------------------------------------ reading

    def self.history(key, model = Sketchup.active_model)
      raw = model.get_attribute(DICT, history_key(key)).to_s
      return [] if raw.empty?
      out = JSON.parse(raw)
      out.is_a?(Array) ? out : []
    rescue StandardError
      []
    end

    # What is recoverable right now, per key. `n` is how many old versions
    # are kept, `now` how big the live value is.
    def self.list(model = Sketchup.active_model)
      keys = (KNOWN_KEYS + discovered_keys(model)).uniq
      keys.map do |k|
        h = history(k, model)
        { key: k,
          now: model.get_attribute(DICT, k).to_s.bytesize,
          backups: h.length,
          newest: h.first ? h.first['at'] : nil,
          sizes: h.map { |e| e['bytes'].to_i } }
      end
    rescue StandardError => e
      puts "[StateBackup] list: #{e.class}: #{e.message}"
      []
    end

    # Any key that already has a history, even one this file was never told
    # about.
    def self.discovered_keys(model = Sketchup.active_model)
      d = model.attribute_dictionary(DICT)
      return [] unless d
      d.keys.select { |k| k.to_s.end_with?('__history') }
       .map { |k| k.to_s.sub(/__history\z/, '') }
    rescue StandardError
      []
    end

    # The user does not read console output, so the answer goes to a file
    # next to the plugin and gets read from there.
    def self.report(path = nil)
      path ||= File.join(File.dirname(__FILE__), 'backup_report.txt')
      lines = []
      lines << '== what can still be recovered =='
      lines << "measured #{stamp}"
      lines << ''
      lines << format('%-22s %10s %8s  %s', 'key', 'live bytes', 'backups', 'backup sizes')
      lines << ('-' * 78)
      list.each do |r|
        lines << format('%-22s %10d %8d  %s', r[:key], r[:now], r[:backups],
                        r[:sizes].join(', '))
      end
      lines << ''
      lines << 'to put one back:'
      lines << "  InteriorPro::StateBackup.restore!('plan_draft')      # newest"
      lines << "  InteriorPro::StateBackup.restore!('plan_draft', 2)   # older"
      File.write(path, lines.join("\n"))
      path
    rescue StandardError => e
      puts "[StateBackup] report: #{e.class}: #{e.message}"
      nil
    end

    # --------------------------------------------------------- restoring

    # Put an old version back. n = 1 is the newest backup.
    #
    # The value being replaced is itself pushed onto the history first, so
    # restoring the wrong one is not a second disaster - it can be undone by
    # restoring again.
    def self.restore!(key, n = 1, model = Sketchup.active_model)
      k = key.to_s
      list = history(k, model)
      idx = n.to_i - 1
      if idx.negative? || idx >= list.length
        puts "[StateBackup] #{k}: no backup ##{n} (there are #{list.length})"
        return false
      end
      wanted = list[idx]['json'].to_s
      write!(k, wanted, model)
      puts "[StateBackup] #{k}: restored backup ##{n} (#{wanted.bytesize} bytes) " \
           "from #{list[idx]['at']}"
      true
    rescue StandardError => e
      puts "[StateBackup] restore! #{key}: #{e.class}: #{e.message}"
      false
    end

    # ------------------------------------------------------------- helper

    # Date.now is not available inside a workflow script, but this is plain
    # SketchUp Ruby - Time is fine here.
    def self.stamp
      Time.now.strftime('%Y-%m-%d %H:%M:%S')
    rescue StandardError
      '?'
    end

  end
end
