# Interior Pro - Pull Roof Edge Tool (2026-10-06)
# The user: "קודם כל תיצור כפתור לשינויים האלו" - the pull-out of a roof
# edge gets a button of its own. Click a wall, type how far the roof edge
# over it comes out, and the roof is rebuilt - and the roofs it meets
# follow. 0 puts the edge back where it stood.
#
# NOTHING NEW IS BUILT HERE. The number, the builder and the follow are the
# ones the Roof End menu already uses (RoofManager.set_edge_pull!, measured
# on his Aetna model 2026-10-05). This is the same wall-picking tool as
# RoofGableTool - same hover, same highlight - with a click that asks for
# the one number only.
#   InteriorPro::RoofPullTool::USE_PULL_TOOL = false  -> the button says so
#   and does nothing; the Roof End menu still carries the number.
require 'stringio'
module InteriorPro
  class RoofPullTool < RoofGableTool
    USE_PULL_TOOL = true unless const_defined?(:USE_PULL_TOOL, false)
    TITLE = 'Interior Pro - Pull Roof Edge' unless const_defined?(:TITLE, false)

    def activate
      @preview_wall = nil
      Sketchup.set_status_text('Click a wall: type how far the roof edge over it is pulled out, in inches (0 = back where it was)', SB_PROMPT)
    end

    def onLButtonDown(_flags, x, y, view)
      unless USE_PULL_TOOL
        puts '[RoofPullTool] switched off (USE_PULL_TOOL = false) - nothing was changed'
        return UI.messagebox('Pull Roof Edge is switched off.')
      end
      wall = pick_wall(view, x, y)
      return UI.messagebox('Click an Interior Pro wall') unless wall
      rm = InteriorPro::RoofManager
      wid = wall.get_attribute('InteriorPro', 'id')
      kind = rm.roof_end_of(wid)
      # the same two ends the Roof End menu refuses - said BEFORE he types
      if kind == :dutch || kind == :shed
        self.class.trace("wall #{wid}: #{kind} end - refused before the number")
        return UI.messagebox('A Dutch gable or a shed eave cannot be pulled out yet.')
      end
      was = rm.edge_pulls[wid].to_f
      res = UI.inputbox(['Pull out (in)'], [was.round(2).to_s.sub(/\.0\z/, '')], [''], TITLE)
      return unless res
      pull = rm.parse_pull(res[0])
      log = self.class.capture { rm.set_edge_pull!(wall, pull) }
      got = rm.edge_pulls[wid].to_f
      built = log =~ /\[Roof\] (?:edge|eave) #{Regexp.escape(wid.to_s[0, 8])} pulled out/
      self.class.trace(format('wall %s (%s end): typed %s -> %.2f" (was %.2f"), saved %.2f", %s', wid, kind, res[0].inspect, pull, was, got,
                              built ? 'BUILT' : (got > 0.01 ? 'NOT BUILT' : 'back in place')))
      log.lines.grep(/pull|Roof\] (?:edge|eave|valley)/i).each { |l| self.class.trace('    ' + l.strip) }
      # NOT SILENTLY (the law of 2026-09-23): a number that was saved but
      # did not move the edge says why, in the builder's own words.
      # held short of a roof in front of it (2026-10-09): built, and he is told how far
      held = log.lines.grep(/\] edge #{Regexp.escape(wid.to_s[0, 8])} is held to/).first
      UI.messagebox(held.strip.sub(/\A\[Roof\]\s*/, '')) if built && held
      if got > 0.01 && !built
        # the valley lines are about the roofs meeting, never about the pull
        # (his box on 2026-10-09 carried "nothing is carried on" as a reason)
        why = log.lines.grep(/not pulled out|not built|left out|nothing (?:is|was)/).grep_v(/\] valley:/).map { |l| l.strip.sub(/\A\[Roof\]\s*/, '') }.uniq
        why = ['The roof was not rebuilt - see the Ruby Console.'] if why.empty?
        UI.messagebox("The edge was not pulled out:\n\n" + why.first(3).join("\n\n"))
      end
      view.invalidate
    rescue StandardError => e
      puts "[RoofPullTool] error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      self.class.trace("ERROR #{e.class}: #{e.message}")
    end

    # Runs the block with the console held, hands the lines back - and
    # prints them to the console all the same, so nothing is hidden.
    def self.capture
      old = $stdout
      io = StringIO.new
      begin
        $stdout = io
        yield
      ensure
        $stdout = old
      end
      puts io.string unless io.string.empty?
      io.string
    end

    # One line per click to roof_pull_trace.txt next to the code - so a
    # pull that went wrong shows WHY without him pasting anything.
    def self.trace(msg)
      File.open(File.join(__dir__, 'roof_pull_trace.txt'), 'a:UTF-8') { |f| f.puts "#{Time.now.strftime('%m-%d %H:%M:%S')}   #{msg}" }
    rescue StandardError
      nil
    end
  end
end
