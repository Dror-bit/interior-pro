# Interior Pro - Door Casing Profiles
# Smooth 2D cross-sections built from lines + quadratic Bezier curves.
# Shared library for door casing now; base/crown molding reuses the same profiles.
#
# Dimensions match catalog convention:
#   width  = face height (e.g. 3-1/4", 4", 5-1/4")
#   depth  = thickness off wall (e.g. 7/16", 9/16", 11/16")

module InteriorPro
  module DoorCasingProfiles

    remove_const(:CURVE_STEPS) if const_defined?(:CURVE_STEPS, false)
    remove_const(:SPECS) if const_defined?(:SPECS, false)

    CURVE_STEPS = 20

    # Segment commands (u_frac 0 = jamb edge, v_frac 0 = wall face, 1 = max depth):
    #   [:m, u, v]              — move to start
    #   [:l, u, v]              — line
    #   [:q, cu, cv, u, v]      — quadratic Bezier (optional 6th arg = step count)
    SPECS = {
      'flat' => {
        width: 2.0, depth: 0.625,
        segments: [
          [:m, 0, 0], [:l, 1, 0], [:l, 1, 1], [:l, 0, 1], [:l, 0, 0]
        ]
      },
      'ranch' => {
        width: 2.0, depth: 0.5625,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.98, 0.10, 0.88, 0.28],
          [:q, 0.55, 0.52, 0, 0.54],
          [:l, 0, 0]
        ]
      },
      'colonial' => {
        width: 2.0, depth: 0.625,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 1.00, 0.22, 0.94, 0.52],
          [:q, 0.76, 0.98, 0.56, 0.84],
          [:q, 0.34, 0.56, 0.16, 0.28],
          [:q, 0.04, 0.06, 0, 0]
        ]
      },
      'stafford' => {
        width: 2.0, depth: 0.625,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.98, 0.16, 0.90, 0.36],
          [:q, 0.82, 0.54, 0.72, 0.56],
          [:q, 0.60, 0.44, 0.52, 0.34],
          [:q, 0.42, 0.58, 0.30, 0.78],
          [:q, 0.16, 0.98, 0.06, 0.20],
          [:l, 0, 0]
        ]
      },
      'windsor' => {
        width: 2.0, depth: 0.625,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.97, 0.18, 0.88, 0.48],
          [:q, 0.70, 0.90, 0.50, 0.56],
          [:q, 0.30, 0.88, 0.10, 0.34],
          [:q, 0.03, 0.08, 0, 0]
        ]
      },
      'belly' => {
        width: 2.0, depth: 0.625,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.96, 0.14, 0.82, 0.38],
          [:q, 0.64, 0.98, 0.50, 0.98],
          [:q, 0.18, 0.38, 0, 0],
          [:l, 0, 0]
        ]
      },
      'kb103' => {
        width: 3.0, depth: 0.75, steps: 20,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 1.00, 0.20, 0.93, 0.48],
          [:q, 0.82, 0.90, 0.66, 0.80],
          [:q, 0.46, 0.52, 0.28, 0.34],
          [:q, 0.12, 0.12, 0, 0]
        ]
      },
      'kb106' => {
        width: 3.5, depth: 0.875, steps: 20,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.99, 0.14, 0.92, 0.34],
          [:q, 0.82, 0.56, 0.72, 0.58],
          [:q, 0.60, 0.46, 0.50, 0.36],
          [:q, 0.38, 0.60, 0.24, 0.82],
          [:q, 0.10, 0.98, 0, 0]
        ]
      },
      'kb117' => {
        width: 4.0, depth: 1.0, steps: 20,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.98, 0.12, 0.88, 0.32],
          [:q, 0.72, 0.58, 0.54, 0.76],
          [:q, 0.36, 0.94, 0.18, 0.72],
          [:q, 0.06, 0.36, 0, 0]
        ]
      },

      # --- Baseboard / catalog profiles (for casing + future base molding) ---
      'bm325' => {
        width: 3.25, depth: 0.4375, category: :base,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.97, 0.10, 0.88, 0.32],
          [:q, 0.42, 0.92, 0, 1],
          [:l, 0, 0]
        ]
      },
      'bm400' => {
        width: 4.0, depth: 0.4375, category: :base,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.86, 0.52, 0.50, 1.0],
          [:q, 0.14, 0.52, 0, 0],
          [:l, 0, 0]
        ]
      },
      'bm325_bevel' => {
        width: 3.25, depth: 0.5625, category: :base,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.92, 0.18, 0.76, 0.52],
          [:q, 0.32, 0.96, 0, 1],
          [:l, 0, 0]
        ]
      },
      'bm425' => {
        width: 4.25, depth: 0.5625, category: :base,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.96, 0.14, 0.86, 0.38],
          [:q, 0.68, 0.58, 0.58, 0.52],
          [:q, 0.30, 0.94, 0, 1],
          [:l, 0, 0]
        ]
      },
      'bm388_ogee' => {
        width: 3.875, depth: 0.5625, category: :base, steps: 20,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.98, 0.16, 0.90, 0.38],
          [:q, 0.76, 0.58, 0.64, 0.52],
          [:q, 0.48, 0.72, 0.32, 0.88],
          [:q, 0.10, 0.28, 0, 0]
        ]
      },
      'bm525_cove' => {
        width: 5.25, depth: 0.6875, category: :base, steps: 20,
        segments: [
          [:m, 0, 0], [:l, 1, 0],
          [:q, 0.98, 0.10, 0.86, 0.36],
          [:q, 0.52, 0.98, 0.32, 0.98],
          [:q, 0.10, 0.52, 0, 0]
        ]
      }
    }.freeze

    def self.build_profile(segments, steps: CURVE_STEPS)
      pts = []
      segments.each do |seg|
        case seg[0]
        when :m
          pts << [seg[1].to_f, seg[2].to_f]
        when :l
          pts << [seg[1].to_f, seg[2].to_f]
        when :q
          p0 = pts.last
          ctrl = [seg[1].to_f, seg[2].to_f]
          p2 = [seg[3].to_f, seg[4].to_f]
          n = seg[5] || steps
          (1..n).each { |i| pts << bezier2(p0, ctrl, p2, i.to_f / n) }
        end
      end
      dedupe_points(pts)
    end

    def self.bezier2(p0, ctrl, p2, t)
      u = 1.0 - t
      [
        u * u * p0[0] + 2 * u * t * ctrl[0] + t * t * p2[0],
        u * u * p0[1] + 2 * u * t * ctrl[1] + t * t * p2[1]
      ]
    end

    def self.dedupe_points(pts, eps: 0.0005)
      return pts if pts.empty?
      out = [pts.first]
      rest = pts.length > 1 ? pts[1..-1] : []
      rest.each do |p|
        last = out.last
        dist = Math.hypot(p[0] - last[0], p[1] - last[1])
        out << p if dist > eps
      end
      out
    end

    def self.spec(style)
      raw = SPECS[style.to_s] || SPECS['flat']
      steps = raw[:steps] || CURVE_STEPS
      {
        width: raw[:width],
        depth: raw[:depth],
        category: raw[:category] || :casing,
        profile: build_profile(raw[:segments], steps: steps)
      }
    end

    def self.profile_names
      SPECS.keys
    end

    def self.base_profile_names
      SPECS.select { |_, v| v[:category] == :base }.keys
    end

    def self.casing_profile_names
      SPECS.reject { |_, v| v[:category] == :base }.keys
    end

  end
end
