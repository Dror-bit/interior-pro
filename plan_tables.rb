# encoding: utf-8
# plan_tables.rb - the door and window schedules, ON PAPER.
#
# The numbers come from plan_generator (the same marks, the same widths, the
# same type names it already prints in SketchUp) - this file only decides
# where the table sits on the sheet and how wide the columns are, which is a
# paper question and belongs here.
#
# A table is a plain :table shape in the drawing document, so the PDF engine
# and the sheet window both draw it without knowing anything about doors.

require File.join(File.dirname(__FILE__), 'plan_doc') unless
  defined?(InteriorPro::PlanDoc)

module InteriorPro
  module PlanTables
    LAYER = 'SCHEDULES' unless const_defined?(:LAYER, false)

    # paper inches
    WIDTH    = 4.7   unless const_defined?(:WIDTH, false)
    GAP      = 0.35  unless const_defined?(:GAP, false)
    ROW_H    = 0.20  unless const_defined?(:ROW_H, false)
    TEXT_H   = 0.075 unless const_defined?(:TEXT_H, false)
    TITLE_H  = 0.12  unless const_defined?(:TITLE_H, false)
    # how much bigger they get when they have a sheet to themselves
    FULL_ZOOM = 1.7  unless const_defined?(:FULL_ZOOM, false)

    WINDOW_COLS = [0.55, 0.7, 0.7, 1.8, 0.95].freeze unless const_defined?(:WINDOW_COLS, false)
    DOOR_COLS   = [0.55, 0.7, 0.7, 1.8, 0.95].freeze unless const_defined?(:DOOR_COLS, false)

    WINDOW_HEADERS = ['MARK', 'R.O. W', 'R.O. H', 'TYPE', 'HEAD'].freeze unless
      const_defined?(:WINDOW_HEADERS, false)
    DOOR_HEADERS = ['MARK', 'WIDTH', 'HEIGHT', 'TYPE', 'FUNCTION'].freeze unless
      const_defined?(:DOOR_HEADERS, false)

    class << self
      # Turns plan_generator's door/window records into table rows. The labels
      # and the feet-and-inches formatting are ITS methods, called - not copied.
      def rows_from(doors, windows)
        pg = InteriorPro::PlanGenerator
        {
          'windows' => Array(windows).sort_by { |b| b[:mark].to_s }.map do |b|
            [b[:mark].to_s,
             pg.send(:fmt_feet, b[:width].to_f),
             pg.send(:fmt_feet, b[:height].to_f),
             (b[:wtype].to_s.empty? ? 'WINDOW' : b[:wtype].to_s.upcase),
             pg.send(:fmt_feet, b[:header].to_f)]
          end,
          'doors' => Array(doors).sort_by { |b| b[:mark].to_s }.map do |b|
            [b[:mark].to_s,
             pg.send(:fmt_feet, b[:width].to_f),
             pg.send(:fmt_feet, b[:height].to_f),
             pg.send(:door_type_label, b),
             b[:category].to_s == 'interior' ? 'INTERIOR' : 'EXTERIOR']
          end
        }
      rescue StandardError => e
        puts "[PlanTables] rows_from: #{e.message}"
        { 'windows' => [], 'doors' => [] }
      end

      def any?(doc)
        s = doc.schedules
        return false unless s.is_a?(Hash)
        !Array(s['doors']).empty? || !Array(s['windows']).empty?
      end

      # How much of the sheet the tables take on the right. 0 when there is
      # nothing to print or the layer is off, so the plan gets the whole page.
      def reserved_width(doc, hidden = [])
        return 0.0 if hidden.include?(LAYER) || !any?(doc)
        WIDTH + GAP
      end

      # Draw them into the page, in paper inches.
      #   default        - a narrow column down the right of the plan sheet
      #   full: true     - a sheet of their own, bigger and starting top left
      def place!(page, doc, opts = {})
        lay = page.layer(LAYER)
        lay.shapes.clear
        return lay unless any?(doc)

        full = opts[:full] ? true : false
        k    = full ? FULL_ZOOM : 1.0
        fx, fy, fw, fh = page.frame
        x   = full ? fx + 0.25 : fx + fw - WIDTH
        top = fy + fh - (full ? 0.6 : 0.15)

        [['WINDOW SCHEDULE', doc.schedules['windows'], WINDOW_HEADERS, WINDOW_COLS],
         ['DOOR SCHEDULE',   doc.schedules['doors'],   DOOR_HEADERS,   DOOR_COLS]].each do |title, rows, headers, cols|
          rows = Array(rows)
          next if rows.empty?
          lay.text(title, x, top + 0.06 * k, h: TITLE_H * k, bold: true)
          lay.table(x, top, headers, rows,
                    col_widths: cols.map { |c| c * k }, row_h: ROW_H * k,
                    h: TEXT_H * k)
          top -= (rows.length + 1) * ROW_H * k + 0.45 * k
        end
        lay
      end
    end
  end
end
