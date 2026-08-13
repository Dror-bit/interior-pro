# encoding: utf-8
# Geometry stand-ins rich enough to run the REAL room_manager.rb maths.
module Geom
  class Vector3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def length; Math.sqrt(@x * @x + @y * @y + @z * @z); end
    def %(o); @x * o.x + @y * o.y + @z * o.z; end
    def *(o); Vector3d.new(@y * o.z - @z * o.y, @z * o.x - @x * o.z, @x * o.y - @y * o.x); end
    def reverse!; @x = -@x; @y = -@y; @z = -@z; self; end
    def reverse; Vector3d.new(-@x, -@y, -@z); end
    def normalize; l = length; l.zero? ? self : Vector3d.new(@x / l, @y / l, @z / l); end
    def normalize!; l = length; unless l.zero?; @x /= l; @y /= l; @z /= l; end; self; end
    def to_a; [@x, @y, @z]; end
    def cross(o); Vector3d.new(@y * o.z - @z * o.y, @z * o.x - @x * o.z, @x * o.y - @y * o.x); end
    def dot(o); (@x * o.x) + (@y * o.y) + (@z * o.z); end
    def clone; Vector3d.new(@x, @y, @z); end
    def valid?; length > 0; end
    # A direction is TURNED by a transformation but never shifted.
    # (2026-08-12, rt40: plan_generator turns wall directions into world
    # space when it draws the dimension chains.)
    def transform(t)
      return self if t.nil?
      Vector3d.new(t.m00 * @x + t.m01 * @y, t.m10 * @x + t.m11 * @y, @z)
    end
  end

  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def +(v); Point3d.new(@x + v.x, @y + v.y, @z + v.z); end
    def -(o)
      o.is_a?(Point3d) ? Vector3d.new(@x - o.x, @y - o.y, @z - o.z)
                       : Point3d.new(@x - o.x, @y - o.y, @z - o.z)
    end
    def distance(o); Math.sqrt((@x - o.x)**2 + (@y - o.y)**2 + (@z - o.z)**2); end
    def transform(t)
      return self if t.nil?
      Point3d.new(t.m00 * @x + t.m01 * @y + t.ox,
                  t.m10 * @x + t.m11 * @y + t.oy,
                  @z + t.oz)
    end
    def offset(v, d = nil)
      u = d.nil? ? v : (l = v.length; l.zero? ? Vector3d.new : Vector3d.new(v.x / l * d, v.y / l * d, v.z / l * d))
      Point3d.new(@x + u.x, @y + u.y, @z + u.z)
    end
    def to_a; [@x, @y, @z]; end
    def inspect; "(#{@x.round(2)},#{@y.round(2)})"; end
  end

  # A turn about the Z axis plus a shift - enough for everything the plugin
  # does to a wall, a door or a window in plan. m00..m11 is the 2x2 rotation,
  # ox/oy/oz the shift. A plain Transformation.new(point) is still a pure
  # shift, exactly as it was before rotation was modelled (2026-08-12).
  class Transformation
    attr_reader :ox, :oy, :oz, :m00, :m01, :m10, :m11
    def initialize(pt = nil, m = nil)
      @ox = pt ? pt.x : 0.0
      @oy = pt ? pt.y : 0.0
      @oz = pt ? pt.z : 0.0
      @m00, @m01, @m10, @m11 = m || [1.0, 0.0, 0.0, 1.0]
    end
    def origin; Point3d.new(@ox, @oy, @oz); end
  end

  class Transformation
    def self.rotation(center, axis, ang)
      # Only a turn about Z is modelled; any other axis stays a no-op, which
      # is what the old stub did for every axis.
      return new if axis.nil? || (axis.respond_to?(:z) && axis.z.abs < 0.5)
      c = Math.cos(ang)
      s = Math.sin(ang)
      cx = center ? center.x : 0.0
      cy = center ? center.y : 0.0
      new(Point3d.new(cx - (c * cx - s * cy), cy - (s * cx + c * cy), 0.0),
          [c, -s, s, c])
    end

    def self.translation(v); new(Geom::Point3d.new(v.x, v.y, v.z)); end

    # self * other: apply `other` first, then self - the SketchUp order.
    def *(o)
      return self unless o.is_a?(Transformation)
      Transformation.new(
        Point3d.new(@m00 * o.ox + @m01 * o.oy + @ox,
                    @m10 * o.ox + @m11 * o.oy + @oy,
                    @oz + o.oz),
        [@m00 * o.m00 + @m01 * o.m10, @m00 * o.m01 + @m01 * o.m11,
         @m10 * o.m00 + @m11 * o.m10, @m10 * o.m01 + @m11 * o.m11]
      )
    end

    def identity?
      @ox.abs < 1e-12 && @oy.abs < 1e-12 && @oz.abs < 1e-12 &&
        (@m00 - 1.0).abs < 1e-12 && (@m11 - 1.0).abs < 1e-12 &&
        @m01.abs < 1e-12 && @m10.abs < 1e-12
    end

    def inverse
      det = @m00 * @m11 - @m01 * @m10
      det = 1.0 if det.abs < 1e-12
      i00 =  @m11 / det; i01 = -@m01 / det
      i10 = -@m10 / det; i11 =  @m00 / det
      Transformation.new(
        Point3d.new(-(i00 * @ox + i01 * @oy), -(i10 * @ox + i11 * @oy), -@oz),
        [i00, i01, i10, i11]
      )
    end
  end

  def self.intersect_line_line(l1, l2)
    p1, d1 = l1[0], l1[1]
    p2, d2 = l2[0], l2[1]
    den = d1.x * d2.y - d1.y * d2.x
    return nil if den.abs < 1e-12
    t = ((p2.x - p1.x) * d2.y - (p2.y - p1.y) * d2.x) / den
    Point3d.new(p1.x + d1.x * t, p1.y + d1.y * t, 0)
  end
end
TextAlignCenter = 1 unless defined?(TextAlignCenter)
