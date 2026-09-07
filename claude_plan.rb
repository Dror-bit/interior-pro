# Interior Pro - reading a plan with Claude (2026-09-22)
#
# Claude is shown the SAME page the user already calibrated in the 2D editor,
# and answers in PIXEL coordinates of that image. The pixels are turned into
# inches HERE, from the calibration the user did by hand - so the scale is
# always his measurement, never a number Claude invented.
#
# THE ARCHITECTURE RULE (VRAY_POC_PLAN.md): numbers only. Nothing that comes
# back is eval'd, and every number is range-checked before it can become a
# wall. Whatever fails a check is dropped and counted, not repaired.

module InteriorPro
  module ClaudePlan
    # Kill switch: false = the button answers "off" and no call is made.
    USE_CLAUDE_PLAN = true

    MAX_WALLS  = 300
    MIN_LEN_PX = 6
    TH_MIN     = 2.0
    TH_MAX     = 24.0

    class << self
      def prompt(img_w, img_h)
        <<~TXT
          You are looking at one page of an architectural floor plan.
          The image is #{img_w} pixels wide and #{img_h} pixels tall.

          Return the WALLS as straight centreline segments, in PIXEL
          coordinates of this image (x to the right, y down, origin at the
          top-left corner).

          Answer with JSON ONLY - no prose, no explanation, no code fence:
          {"walls":[{"x1":0,"y1":0,"x2":0,"y2":0,"thickness_in":6,"kind":"exterior"}]}

          Rules:
          - One segment per straight wall run. Do NOT break a straight wall
            into pieces at a door or a window opening.
          - Corners must MEET: two walls at the same corner share the exact
            same endpoint. A closed room must come back as a closed loop.
          - Almost every wall on a plan is exactly horizontal or exactly
            vertical. If a wall looks horizontal, give both ends the SAME y.
            If it looks vertical, give both ends the SAME x. Only give a
            slanted wall two different values.
          - A wall is drawn as a PAIR of parallel lines (often with hatching
            or a solid fill between them). The centreline runs down the
            middle of that pair - not on either line.
          - The plan may show DIMENSION text such as 23' 8". Use it to place
            the ends correctly relative to each other, and prefer it over
            what you measure by eye.
          - If the image shows several separate floor plans, read ONLY the
            largest and most complete one.
          - "kind" is either "exterior" or "interior".
          - "thickness_in" is in inches. Use the plan if it states it,
            otherwise 6 for exterior and 4 for interior.
          - Ignore dimension lines, leaders, text, hatching, furniture,
            fixtures, appliances, stairs and the title block. Walls only.
          - At most #{MAX_WALLS} walls.
        TXT
      end

      def read_walls(img_b64, img_w, img_h, media = 'png')
        raise 'USE_CLAUDE_PLAN is off' unless USE_CLAUDE_PLAN
        raise 'bad image size' unless img_w > 10 && img_h > 10
        j = InteriorPro::ClaudeAPI.ask_json(prompt(img_w, img_h), img_b64,
                                            max_tokens: 16_000, media: media)
        validate(j, img_w, img_h)
      end

      # Everything below treats the answer as untrusted numbers.
      def validate(j, img_w, img_h)
        rows = j.is_a?(Hash) ? j['walls'] : nil
        raise 'the answer had no "walls" list' unless rows.is_a?(Array)

        out = []
        dropped = 0
        rows.each do |r|
          unless r.is_a?(Hash)
            dropped += 1
            next
          end
          x1 = num(r['x1']); y1 = num(r['y1'])
          x2 = num(r['x2']); y2 = num(r['y2'])
          if [x1, y1, x2, y2].any?(&:nil?) ||
             !inside?(x1, y1, img_w, img_h) || !inside?(x2, y2, img_w, img_h) ||
             Math.hypot(x2 - x1, y2 - y1) < MIN_LEN_PX
            dropped += 1
            next
          end
          kind = r['kind'].to_s == 'interior' ? 'interior' : 'exterior'
          th = num(r['thickness_in'])
          th = (kind == 'interior' ? 4.0 : 6.0) unless th && th >= TH_MIN && th <= TH_MAX
          out << { 'x1' => x1, 'y1' => y1, 'x2' => x2, 'y2' => y2,
                   'th' => th, 'kind' => kind }
          break if out.length >= MAX_WALLS
        end
        puts "[ClaudePlan] kept #{out.length} walls, dropped #{dropped}"
        out
      end

      def num(v)
        return v.to_f if v.is_a?(Numeric)
        return v.to_f if v.is_a?(String) && v =~ /\A-?\d+(\.\d+)?\z/
        nil
      end

      def inside?(x, y, w, h)
        x >= -2 && y >= -2 && x <= w + 2 && y <= h + 2
      end
    end
  end
end
