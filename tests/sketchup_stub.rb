# encoding: utf-8
# Minimal SketchUp API stand-in - enough to actually RUN the PlanEditor Ruby.
require_relative 'geom_stub'

# SketchUp adds String#to_l (text -> a length in inches). Plain Ruby does not,
# so any tool that reads a typed length could not be tested without this.
# Handles: 12, 7.5, 1', 6", 1'6", 1' 6". Anything else raises, exactly like
# the real one, so the callers' rescue paths get exercised.
unless String.method_defined?(:to_l)
  class String
    def to_l
      s = strip
      raise ArgumentError, "bad length #{inspect}" if s.empty?
      if (m = s.match(/\A(-?\d+(?:\.\d+)?)\s*'\s*(?:(\d+(?:\.\d+)?)\s*")?\z/))
        feet = m[1].to_f
        inches = m[2].to_f
        return feet * 12.0 + (feet.negative? ? -inches : inches)
      end
      if (m = s.match(/\A(-?\d+(?:\.\d+)?)\s*"\z/))
        return m[1].to_f
      end
      if (m = s.match(/\A-?\d+(?:\.\d+)?\z/))
        return m[0].to_f
      end
      raise ArgumentError, "bad length #{inspect}"
    end
  end
end

module Sketchup
  class ModelObserver; end

  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0); @x = x.to_f; @y = y.to_f; @z = z.to_f; end
    def distance(o); Math.hypot(Math.hypot(@x - o.x, @y - o.y), @z - o.z); end
    def transform(_t); self; end
    def to_a; [@x, @y, @z]; end
  end

  class Edge
    attr_accessor :soft, :smooth, :a, :b
    def initialize(a, b); @a = a; @b = b; end
  end
  class Face; end

  class Entities
    include Enumerable
    def initialize; @list = []; end
    def each(&b); @list.each(&b); end
    def length; @list.length; end
    def grep(k); @list.select { |e| e.is_a?(k) }; end
    def add_group; g = Group.new; @list << g; g; end
    def add_curve(pts); pts.each_cons(2).map { |a, b| e = Edge.new(a, b); @list << e; e }; end
    def add_line(a, b); e = Edge.new(a, b); @list << e; e; end
    def add_face(_pts); f = Face.new; @list << f; f; end
    def add_3d_text(*_a); true; end
    def clear!; @list = []; true; end
    def erase_entity(e); @list.delete(e); end
  end

  class BBox
    attr_reader :center
    def initialize(c = nil); @center = c || Geom::Point3d.new(0, 0, 0); end
  end

  class Group
    attr_accessor :name
    attr_reader :entities, :parent_list
    def initialize; @attrs = {}; @entities = Entities.new; @valid = true; @name = ''; end
    def set_attribute(d, k, v); (@attrs[d] ||= {})[k] = v; v; end
    def get_attribute(d, k, dflt = nil); (@attrs[d] || {}).key?(k) ? @attrs[d][k] : dflt; end
    def delete_attribute(d, k); (@attrs[d] || {}).delete(k); end
    def valid?; @valid; end
    def erase!; @valid = false; Sketchup.active_model.entities.erase_entity(self); end
    def bounds; BBox.new; end
    # Really compose it, so a test can ask where a body ended up
    # (2026-08-12: rt37 moves doors when their wall bends).
    def transform!(t)
      @transformation = t.is_a?(Geom::Transformation) ? t * transformation : transformation
      self
    end
    attr_writer :transformation
    def transformation; @transformation ||= Geom::Transformation.new; end
  end

  class Layer
    attr_accessor :line_style
    def initialize(n); @n = n; end
  end
  class Layers
    def initialize; @h = {}; end
    def [](n); @h[n] ||= Layer.new(n); end
  end

  class Color
    def initialize(*_a); end
  end

  class Texture
    attr_accessor :size
    attr_reader :filename
    def initialize(f = nil); @filename = f; end
  end

  class Material
    attr_accessor :color, :alpha, :name
    attr_reader :texture
    def initialize(n); @name = n; end
    def texture=(f); @texture = f.nil? ? nil : Texture.new(f); end
  end
  class Materials
    def initialize; @h = {}; end
    def [](n); @h[n]; end
    def add(n); @h[n] = Material.new(n); end
    def remove(n); @h.delete(n); end
  end

  class Model
    attr_reader :entities, :layers
    attr_accessor :ops
    def initialize; @attrs = {}; @entities = Entities.new; @layers = Layers.new; @ops = []; @materials = Materials.new; end
    def materials; @materials; end
    def set_attribute(d, k, v); (@attrs[d] ||= {})[k] = v; v; end
    def get_attribute(d, k, dflt = nil); (@attrs[d] || {}).key?(k) ? @attrs[d][k] : dflt; end
    def delete_attribute(d, k); (@attrs[d] || {}).delete(k); end
    # Real signature: (name, disable_ui, next_transparent, transparent) -
    # the transparent flag folds an op into the previous undo step.
    def start_operation(n, _disable_ui = nil, _next_tr = nil, transparent = false)
      @ops << [:start, n, transparent ? :transparent : nil].compact
      true
    end
    def commit_operation; @ops << [:commit]; true; end
    def abort_operation; @ops << [:abort]; true; end
    def add_observer(_o); true; end
    def remove_observer(_o); true; end
    def line_styles; nil; end
    def respond_to_line_styles?; false; end
  end

  @model = Model.new
  class << self
    def active_model; @model; end
    def reset_model!; @model = Model.new; end
    def send_action(_a); true; end
  end
end

module UI
  class HtmlDialog
    attr_reader :callbacks, :scripts
    def initialize(_opts = {}); @callbacks = {}; @scripts = []; end
    def add_action_callback(name, &blk); @callbacks[name] = blk; end
    def execute_script(s); @scripts << s; end
    def set_html(_h); end
    def set_on_closed(&_b); end
    def show; end
    def close; end
    def visible?; true; end
  end
  def self.messagebox(_m); nil; end
  def self.openpanel(*_a); nil; end
  def self.start_timer(_t, _r = false); nil; end
end

module InteriorPro
  def self.assign_tag(_g, _name); true; end
  module WallTool
    USE_NATIVE_OPENINGS = true
    def self.read_door_openings(_w); []; end
  end
end

module InteriorPro
  module FakeRoomManager
    def self.rooms_in_model
      Sketchup.active_model.entities.grep(Sketchup::Group).select do |g|
        g.valid? && g.get_attribute('InteriorPro', 'type') == 'room'
      end
    end
    def self.build_label!(_g, _name, _area); @label_calls = (@label_calls || 0) + 1; true; end
    def self.label_calls; @label_calls || 0; end
    def self.sync_rooms!; true; end
  end
end

# The rt/rt2/rt3/rt4 suites use the light fake; rt5 loads the REAL room_manager.
unless ENV['REAL_ROOMS']
  module InteriorPro
    RoomManager = FakeRoomManager
  end
end
