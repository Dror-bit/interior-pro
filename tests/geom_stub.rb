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
      Point3d.new(@x + t.ox, @y + t.oy, @z + t.oz)
    end
    def offset(v, d = nil)
      u = d.nil? ? v : (l = v.length; l.zero? ? Vector3d.new : Vector3d.new(v.x / l * d, v.y / l * d, v.z / l * d))
      Point3d.new(@x + u.x, @y + u.y, @z + u.z)
    end
    def to_a; [@x, @y, @z]; end
    def inspect; "(#{@x.round(2)},#{@y.round(2)})"; end
  end

  class Transformation
    attr_reader :ox, :oy, :oz
    def initialize(pt = nil)
      @ox = pt ? pt.x : 0.0
      @oy = pt ? pt.y : 0.0
      @oz = pt ? pt.z : 0.0
    end
    def origin; Point3d.new(@ox, @oy, @oz); end
  end

  class Transformation
    def self.rotation(_c, _axis, _ang); new; end
    def self.translation(v); new(Geom::Point3d.new(v.x, v.y, v.z)); end
    # The stub only ever models a plain shift, so "no shift" is identity.
    def identity?; @ox.zero? && @oy.zero? && @oz.zero?; end
    def inverse; Transformation.new(Geom::Point3d.new(-@ox, -@oy, -@oz)); end
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
