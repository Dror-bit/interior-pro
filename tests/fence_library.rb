# encoding: utf-8
# Landscape Pro - Fence Library (2026-08-16)
#
# A fence TYPE is nothing but a bag of numbers. It owns no geometry, calls no
# SketchUp API, and cannot draw anything: it is handed to FenceTool, which
# hands the numbers to FenceMath, which is the only place fence arithmetic
# lives. Adding a type must never mean adding a builder.
#
# WHY PRESETS AND SAVED TYPES ARE TWO DIFFERENT THINGS
#
# The wall library starts empty, so a new user sees a blank window and has to
# invent a wall before drawing one. A fence has a handful of shapes everybody
# already knows, so they ship built in. They are NOT written to the JSON file -
# the file holds only what the user made himself. That means:
#
#   * a preset can be improved in a later version and every user gets it
#   * a user type can never be lost by an update
#   * "delete" on a type the user edited puts the original preset back,
#     because deleting only ever removes his own copy
#
# `all` is the one list the dialog shows: the presets, each replaced by the
# user's copy if he saved one under the same name, then whatever else he made.
#
# WHAT A TYPE NOW HAS TO SAY (2026-08-16)
#
# A type is no longer height-spacing-boards. Measuring six real fences showed
# that a fence is four things stacked: POSTS, the RAILS between them, the
# INFILL between the rails, and sometimes a CAP on the post. All four are
# numbers in the type; not one of them is a new builder. FenceMath turns them
# into boxes and FenceTool draws the boxes.
#
#   infill  boards      upright, touching     - privacy fence
#           spaced      upright, even gaps    - picket, baluster, iron
#           horizontal  lying down, even gaps - modern slat fence
#           glass       one panel per bay
#           none        rails only
#
# 'bars' is still accepted as the old name for 'spaced'.

require 'json'

module InteriorPro
  module Landscape
    module FenceLibrary

      INFILLS = %w[boards spaced horizontal glass none].freeze unless const_defined?(:INFILLS, false)
      INFILL_ALIASES = { 'bars' => 'spaced' }.freeze unless const_defined?(:INFILL_ALIASES, false)
      MODES   = %w[rake step].freeze unless const_defined?(:MODES, false)

      # Every number that is a length. normalize turns each of them into a
      # Float and refuses the ones that would build something impossible.
      SIZES = %w[height max_spacing post_size board_width board_gap
                 board_thickness rail_height rail_thickness rail_bottom_z
                 post_extra cap_size cap_height].freeze unless const_defined?(:SIZES, false)

      # Sizes that must be greater than zero or the type is nonsense. The rest
      # (gaps, insets, the cap) are allowed to be zero - zero cap means no cap.
      POSITIVE = %w[height max_spacing post_size board_width
                    board_thickness].freeze unless const_defined?(:POSITIVE, false)

      # Every number a type must have, and what it means if it is missing.
      # normalize fills all of these in, so no half-written JSON can ever
      # reach the builder.
      DEFAULTS = {
        'name'            => 'Fence',
        'height'          => 72.0,
        'max_spacing'     => 96.0,
        'post_size'       => 4.0,
        'board_width'     => 5.5,
        'board_gap'       => 0.0,
        'board_thickness' => 0.75,
        'color'           => '#A1887F',
        'infill'          => 'boards',
        'mode'            => 'rake',
        # The anatomy (2026-08-16). Rails default to ON here even though they
        # default to OFF on the tool, and the split is deliberate: a bare
        # FenceTool with nothing behind it must still build exactly what it
        # built yesterday, but nobody picking a type out of a library wants a
        # fence with no rails - all six of the real fences that were measured
        # had them. An old saved type with no rail_count key therefore GAINS
        # rails, which is the whole point of this round.
        'rail_count'      => 2,
        'rail_height'     => 3.5,
        'rail_thickness'  => 1.5,
        'rail_bottom_z'   => 2.0,
        'post_extra'      => 2.0,
        'cap_size'        => 0.0,
        'cap_height'      => 0.0
      }.freeze unless const_defined?(:DEFAULTS, false)

      # THE PRESETS ARE MEASURED, NOT INVENTED (rebuilt 2026-08-16)
      #
      # The user built six fences in another tool and sent them over. They were
      # loaded into SketchUp and every part in them measured - see
      # landscape/reference/fence_ref_report.txt, and debug_fence_ref.rb which
      # produced it. The numbers below are those measurements, rounded to
      # something a person would actually order.
      #
      # What the measuring showed, and what the first version got wrong:
      # EVERY ONE of the six had a rail along the bottom and a rail along the
      # top, with the infill between them. Two of them had a cap on the post.
      # One of them laid its boards down flat instead of standing them up.
      # None of them was posts and boards alone, which is all the first
      # version could build.
      #
      # Chain Link is still deliberately absent - a real mesh is a different
      # engine and the user chose to see these first.
      PRESETS = [
        # Ordinary 6ft cedar privacy fence. Boards touch, so 'boards' (fill and
        # shave) is the right division here.
        { 'name'            => 'Wood Privacy',
          'height'          => 72.0,
          'max_spacing'     => 96.0,
          'post_size'       => 4.0,
          'board_width'     => 5.5,
          'board_gap'       => 0.0,
          'board_thickness' => 0.75,
          'infill'          => 'boards',
          'rail_count'      => 2,
          'rail_height'     => 3.5,
          'rail_thickness'  => 1.5,
          'rail_bottom_z'   => 2.0,
          'post_extra'      => 2.0,
          'cap_size'        => 0.0,
          'cap_height'      => 0.0,
          'color'           => '#A1887F',
          'mode'            => 'rake' },

        # From "wood Fence": boards 1 x 5 with a 0.69 gap, on two 1 x 4 rails
        # at z=2 and z=48. Spaced boards, so the board keeps its 5" and the
        # gap absorbs the rounding.
        { 'name'            => 'Wood Picket',
          'height'          => 63.0,
          'max_spacing'     => 72.0,
          'post_size'       => 4.0,
          'board_width'     => 5.0,
          'board_gap'       => 0.69,
          'board_thickness' => 1.0,
          'infill'          => 'spaced',
          'rail_count'      => 2,
          'rail_height'     => 4.0,
          'rail_thickness'  => 1.0,
          'rail_bottom_z'   => 2.0,
          'post_extra'      => 3.0,
          'cap_size'        => 0.0,
          'cap_height'      => 0.0,
          'color'           => '#A1887F',
          'mode'            => 'rake' },

        # From "Modern Wood Fence": 3x3 posts every 96", 3x3 rails at z=2 and
        # z=67, and eighteen 1 x 5.75 boards LYING DOWN at a 6" pitch. This is
        # the one the first version could not have built at all.
        { 'name'            => 'Modern Horizontal',
          'height'          => 72.0,
          'max_spacing'     => 96.0,
          'post_size'       => 3.0,
          'board_width'     => 5.75,
          'board_gap'       => 0.25,
          'board_thickness' => 1.0,
          'infill'          => 'horizontal',
          'rail_count'      => 2,
          'rail_height'     => 3.0,
          'rail_thickness'  => 3.0,
          'rail_bottom_z'   => 2.0,
          'post_extra'      => 2.0,
          'cap_size'        => 0.0,
          'cap_height'      => 0.0,
          'color'           => '#9E8877',
          'mode'            => 'rake' },

        # From "Vinyl fance": 4" pickets at a 4.36 pitch, rails 1.5 x 5 at
        # z=2 and z=51, and a 6x6 cap sitting in the top 1.5" of the 60"
        # height. Vinyl comes as preassembled panels and a preassembled panel
        # cannot be tilted, so this one steps down a slope.
        { 'name'            => 'Vinyl Privacy',
          'height'          => 60.0,
          'max_spacing'     => 96.0,
          'post_size'       => 5.0,
          'board_width'     => 4.0,
          'board_gap'       => 0.36,
          'board_thickness' => 0.75,
          'infill'          => 'spaced',
          'rail_count'      => 2,
          'rail_height'     => 5.0,
          'rail_thickness'  => 1.5,
          'rail_bottom_z'   => 2.0,
          'post_extra'      => 0.0,
          'cap_size'        => 6.0,
          'cap_height'      => 1.5,
          'color'           => '#F5F5F5',
          'mode'            => 'step' },

        # From "Glass Railing": 3/8" panels 31" wide at a 32" pitch, a 1.5"
        # cap along the top and a 1" shoe along the bottom. The glass gets its
        # own see-through material in fence_tool - a glass panel painted the
        # same flat colour as the posts is why the first attempt did not look
        # like glass.
        { 'name'            => 'Glass Panel',
          'height'          => 42.0,
          'max_spacing'     => 32.0,
          'post_size'       => 2.0,
          'board_width'     => 32.0,
          'board_gap'       => 0.0,
          'board_thickness' => 0.375,
          'infill'          => 'glass',
          'rail_count'      => 2,
          'rail_height'     => 1.5,
          'rail_thickness'  => 2.0,
          'rail_bottom_z'   => 0.0,
          'post_extra'      => 0.0,
          'cap_size'        => 0.0,
          'cap_height'      => 0.0,
          'color'           => '#B0BEC5',
          'mode'            => 'step' },

        # From "Simple iron Fence": 37 bars of 1/2" square at a 3.88 pitch,
        # 1.5" posts every 72", and a 1.5 x 0.5 rail top and bottom.
        { 'name'            => 'Wrought Iron',
          'height'          => 42.0,
          'max_spacing'     => 72.0,
          'post_size'       => 1.5,
          'board_width'     => 0.5,
          'board_gap'       => 3.38,
          'board_thickness' => 0.5,
          'infill'          => 'spaced',
          'rail_count'      => 2,
          'rail_height'     => 0.5,
          'rail_thickness'  => 1.5,
          'rail_bottom_z'   => 0.0,
          'post_extra'      => 0.0,
          'cap_size'        => 0.0,
          'cap_height'      => 0.0,
          'color'           => '#37474F',
          'mode'            => 'step' },

        # From "Trax Railing": 5.5" posts every 96" standing 7" proud of the
        # top rail with a cap on top, 3.5 x 1.5 rails, and 5/8" spindles at a
        # 4" pitch. A deck rail, so it steps.
        { 'name'            => 'Deck Railing',
          'height'          => 46.5,
          'max_spacing'     => 96.0,
          'post_size'       => 5.5,
          'board_width'     => 0.625,
          'board_gap'       => 3.375,
          'board_thickness' => 0.625,
          'infill'          => 'spaced',
          'rail_count'      => 2,
          'rail_height'     => 1.5,
          'rail_thickness'  => 3.5,
          'rail_bottom_z'   => 0.0,
          'post_extra'      => 7.0,
          'cap_size'        => 5.5,
          'cap_height'      => 1.0,
          'color'           => '#8D6E63',
          'mode'            => 'step' }
      ].freeze unless const_defined?(:PRESETS, false)

      # The shipped types, as fresh mutable copies. PRESETS itself is frozen
      # so nothing downstream can quietly edit what everybody else will get.
      def self.presets
        PRESETS.map { |p| normalize(p) }
      end

      # ------------------------------------------------------------ the file

      # Overridable so a test can point it at a scratch file instead of the
      # user's real library.
      def self.library_file
        @library_file ||= File.join(ENV['APPDATA'] || ENV['HOME'] || '.',
                                    'InteriorPro', 'fence_library.json')
      end

      def self.library_file=(path)
        @library_file = path
      end

      def self.ensure_dir
        dir = File.dirname(library_file)
        require 'fileutils'
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      rescue StandardError => e
        puts "[FenceLibrary] could not make #{File.dirname(library_file)}: #{e.message}"
      end

      # Only the types the user made himself. Never the presets.
      def self.load
        return [] unless File.exist?(library_file)
        data = JSON.parse(File.read(library_file))
        return [] unless data.is_a?(Array)
        data.map { |t| normalize(t) }
      rescue StandardError => e
        puts "[FenceLibrary] could not read the library: #{e.message}"
        []
      end

      # Writing never throws: a library that cannot be saved must not take the
      # fence tool down with it.
      def self.save(list)
        ensure_dir
        File.write(library_file, JSON.pretty_generate(Array(list).map { |t| normalize(t) }))
        true
      rescue StandardError => e
        puts "[FenceLibrary] could not save the library: #{e.message}"
        false
      end

      # ------------------------------------------------------------ the list

      # What the dialog shows. Presets first, in their fixed order, each one
      # replaced by the user's own version if he saved one under that name;
      # then everything else he made, in the order he made it.
      def self.all
        mine = load
        by_name = {}
        mine.each { |t| by_name[t['name'].to_s] = t }

        out = PRESETS.map do |p|
          saved = by_name[p['name']]
          saved ? normalize(saved).merge('builtin' => true) :
                  normalize(p).merge('builtin' => true)
        end
        preset_names = PRESETS.map { |p| p['name'] }
        mine.each do |t|
          next if preset_names.include?(t['name'].to_s)
          out << normalize(t).merge('builtin' => false)
        end
        out
      end

      def self.find(name)
        all.find { |t| t['name'].to_s == name.to_s }
      end

      # ------------------------------------------------------------- editing
      #
      # By NAME, never by row number: the visible list mixes presets and saved
      # types, so a row number means nothing outside the window that drew it.

      # The name is checked BEFORE normalize, not after: normalize deliberately
      # gives an unnamed type a fallback name so nothing downstream can crash
      # on it, which would quietly turn "the user forgot to type a name" into
      # a type called Fence sitting in his library for ever.
      def self.save_type(type)
        raw = type.is_a?(Hash) ? (type['name'] || type[:name]) : nil
        return false if raw.to_s.strip.empty?
        t = normalize(type)
        list = load
        i = list.find_index { |x| x['name'].to_s == t['name'] }
        i ? list[i] = t : list << t
        save(list)
      end

      # Removes the user's copy only. If the name is a preset, the preset comes
      # back - which is exactly what "undo my edit" should mean.
      def self.delete_type(name)
        list = load
        before = list.length
        list.reject! { |x| x['name'].to_s == name.to_s }
        return false if list.length == before
        save(list)
      end

      def self.preset?(name)
        PRESETS.any? { |p| p['name'] == name.to_s }
      end

      # Only meaningful for a name the user actually saved over.
      def self.customised?(name)
        load.any? { |t| t['name'].to_s == name.to_s }
      end

      # --------------------------------------------------------- normalizing
      #
      # A type that reaches the builder is ALWAYS complete and always sane.
      # Nothing downstream is allowed to guess.
      def self.normalize(type)
        src = type.is_a?(Hash) ? type : {}
        src = src.each_with_object({}) { |(k, v), h| h[k.to_s] = v }

        out = {}
        out['name'] = (src['name'] || DEFAULTS['name']).to_s.strip
        out['name'] = DEFAULTS['name'] if out['name'].empty?

        SIZES.each do |k|
          v = src.key?(k) ? src[k].to_f : DEFAULTS[k]
          v = DEFAULTS[k] if v.nil?
          out[k] = v.to_f
        end

        # A number that would build nothing, or build something impossible,
        # falls back to the default rather than reaching FenceMath.
        POSITIVE.each { |k| out[k] = DEFAULTS[k].to_f if out[k] <= 0 }
        # These are allowed to be zero - zero cap means no cap, zero rail
        # height means no rail - but never negative.
        %w[board_gap rail_height rail_thickness rail_bottom_z post_extra
           cap_size cap_height].each { |k| out[k] = 0.0 if out[k] < 0 }

        rc = src.key?('rail_count') ? src['rail_count'].to_i : DEFAULTS['rail_count'].to_i
        rc = 0 if rc < 0
        rc = 6 if rc > 6
        out['rail_count'] = rc

        c = src['color'].to_s.strip
        out['color'] = c.empty? ? DEFAULTS['color'] : c

        inf = src['infill'].to_s.strip.downcase
        inf = INFILL_ALIASES[inf] if INFILL_ALIASES.key?(inf)
        out['infill'] = INFILLS.include?(inf) ? inf : DEFAULTS['infill']

        md = src['mode'].to_s.strip.downcase
        out['mode'] = MODES.include?(md) ? md : DEFAULTS['mode']

        # A cap needs both numbers or it is not a cap. Half a cap - a height
        # with no size - would silently eat that much off the top of every
        # post and put nothing back.
        if out['cap_size'] <= 0 || out['cap_height'] <= 0
          out['cap_size'] = 0.0
          out['cap_height'] = 0.0
        end

        # The rails and the cap between them must leave something for the
        # infill, or the type builds a fence with a hole where its middle
        # should be. Rather than refuse it, give the rails back their room.
        clear = out['height'] - out['rail_bottom_z'] - out['cap_height'] -
                out['post_extra'] - out['rail_height'] * [out['rail_count'], 2].min
        if out['rail_count'] > 0 && clear <= 0
          out['rail_count']    = DEFAULTS['rail_count']
          out['rail_height']   = DEFAULTS['rail_height']
          out['rail_bottom_z'] = DEFAULTS['rail_bottom_z']
          out['post_extra']    = 0.0
        end

        out
      end

      # Hand a normalized type to a FenceTool. This is the ONLY place that
      # knows which library field maps to which tool setting, so a new field
      # is wired in one place instead of three.
      def self.apply_to_tool(tool, type, ground_start = 0.0, ground_end = 0.0)
        t = normalize(type)
        tool.height          = t['height']
        tool.max_spacing     = t['max_spacing']
        tool.post_size       = t['post_size']
        tool.board_width     = t['board_width']
        tool.board_gap       = t['board_gap']
        tool.board_thickness = t['board_thickness']
        tool.color           = t['color']
        tool.mode            = t['mode'].to_sym
        tool.infill          = t['infill']
        tool.rail_count      = t['rail_count']
        tool.rail_height     = t['rail_height']
        tool.rail_thickness  = t['rail_thickness']
        tool.rail_bottom_z   = t['rail_bottom_z']
        tool.post_extra      = t['post_extra']
        tool.cap_size        = t['cap_size']
        tool.cap_height      = t['cap_height']
        tool.ground_start    = ground_start.to_f
        tool.ground_end      = ground_end.to_f
        tool
      end

    end
  end
end
