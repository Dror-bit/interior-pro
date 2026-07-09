# Interior Pro - Molding Library
# Baseboard + crown profiles (dimensions from the Metrie catalog).

module InteriorPro
  module MoldingLibrary

    # t = thickness (in), h = height (in)
    BASEBOARDS = {
      'Base 5-3/16"' => { t: 0.5625, h: 5.1875 },
      'Base 4-1/8"'  => { t: 0.5625, h: 4.125 }
    }.freeze unless const_defined?(:BASEBOARDS, false)

    CROWNS = {
      'Crown 5-1/4"'  => { t: 0.5625, h: 5.25 },
      'Crown 6-5/16"' => { t: 1.1875, h: 6.3125 }
    }.freeze unless const_defined?(:CROWNS, false)

    # Crown cross-section as [depth-from-wall, height] pairs, hung from the
    # ceiling (wall_h) at a ~45 deg spring angle.
    def self.crown_profile(spec, wall_h)
      w = spec[:h].to_f          # catalog face width
      proj = w * 0.71            # ceiling projection
      drop = w * 0.71            # wall drop
      t = spec[:t].to_f
      top = wall_h
      bot = wall_h - drop
      [
        [0.0, bot], [t, bot + drop * 0.10], [proj * 0.55, top - drop * 0.18],
        [proj * 0.85, top - drop * 0.10], [proj, top], [0.0, top]
      ]
    end

    # Baseboard cross-section as [depth-from-wall, height] pairs.
    # Flat back at d=0, flat bottom, eased colonial top.
    def self.baseboard_profile(spec)
      t = spec[:t].to_f
      h = spec[:h].to_f
      [
        [0.0, 0.0], [t, 0.0], [t, h * 0.72],
        [t * 0.85, h * 0.80], [t * 0.55, h * 0.86],
        [t * 0.55, h * 0.94], [t * 0.30, h], [0.0, h]
      ]
    end

  end
end
