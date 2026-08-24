# encoding: utf-8
# Minimal SketchUp API stand-in - enough to actually RUN the PlanEditor Ruby.
require_relative 'geom_stub'

# SketchUp defines these at the top level, so tool code says them bare. Without
# them any tool that writes to the status bar dies with NameError the moment a
# suite drives its mouse - which is exactly what rt64 hit on the garden wall
# (2026-08-17). Real values, so a suite could assert on them if it ever cares.
SB_PROMPT   = 0 unless defined?(SB_PROMPT)
SB_VCB_LABEL = 1 unless defined?(SB_VCB_LABEL)
SB_VCB_VALUE = 2 unless defined?(SB_VCB_VALUE)

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
# Was `self` - a lie that would let a wrong local-vs-world fix pass green
# (2026-08-18C §8). Nothing in the plugin uses Sketchup::Point3d - it uses
# Geom::Point3d, whose transform in geom_stub.rb is real - but a stub that
# quietly does nothing is a trap, so it does the real thing now.
def transform(t)
  Geom::Point3d.new(@x, @y, @z).transform(t)
end
    def to_a; [@x, @y, @z]; end
  end

  # A vertex, so plugin code can use the real API (edge.start.position)
  # instead of reaching into the stub's own fields (2026-08-13, rt46).
  class Vertex
    attr_reader :position
    def initialize(p); @position = p; end
  end

  @next_pid = 0
  def self.next_pid; @next_pid += 1; end

  class Edge
    attr_accessor :soft, :smooth, :a, :b
    def initialize(a, b); @a = a; @b = b; end
    def start; Vertex.new(@a); end
    def end; Vertex.new(@b); end
    def soft?; @soft == true; end
    def smooth?; @smooth == true; end
    def valid?; true; end
    def persistent_id; @pid ||= Sketchup.next_pid; end
  end
  # A face that REMEMBERS its outline, so a test can ask where a solid was
  # actually built instead of only that something was built (2026-08-15,
  # rt57 - Landscape Pro's fence). It used to be an empty class, which meant
  # any tool that calls pushpull could not be run in the cloud at all.
  #
  # normal is the real Newell normal of the outline, so the "which way does
  # this face happen to be facing" branches that every builder has - and that
  # are exactly the ones that go wrong - run here the same way they run in
  # SketchUp.
  class Face
    attr_reader :points, :pushpulls
    attr_accessor :material, :back_material

    def initialize(pts = [])
      @points = Array(pts)
      @pushpulls = []
    end

    def valid?; true; end

    def normal
      n = [0.0, 0.0, 0.0]
      pts = @points
      return Geom::Vector3d.new(0, 0, 1) if pts.length < 3
      pts.each_with_index do |p, i|
        q = pts[(i + 1) % pts.length]
        n[0] += (p.y - q.y) * (p.z + q.z)
        n[1] += (p.z - q.z) * (p.x + q.x)
        n[2] += (p.x - q.x) * (p.y + q.y)
      end
      v = Geom::Vector3d.new(n[0], n[1], n[2])
      v.length.zero? ? Geom::Vector3d.new(0, 0, 1) : v.normalize
    end

    # Records the distance instead of making new geometry - which is enough
    # to prove a builder pushed the right way by the right amount. A test
    # that needs the resulting solid needs SketchUp, not a stub.
    def pushpull(d); @pushpulls << d.to_f; true; end

    def all_connected; [self]; end

    # Real faces hand out vertices, and code that measures a loaded model
    # walks them (2026-08-16, the reference fence reader).
    Vertex = Struct.new(:position) unless const_defined?(:Vertex, false)
    def vertices; @points.map { |p| Vertex.new(p) }; end

    # Where the outline sits, for tests that check heights.
    def z_range
      zs = @points.map(&:z)
      zs.empty? ? [0.0, 0.0] : [zs.min, zs.max]
    end
  end

  class Entities
    include Enumerable
    def initialize; @list = []; end
    def each(&b); @list.each(&b); end
    def length; @list.length; end
    def grep(k); @list.select { |e| e.is_a?(k) }; end
    def add_group; g = Group.new; g.parent_entities = self; @list << g; g; end
    # An instance of a definition, placed with a transformation - the one call
    # the reference fence tool is made of (2026-08-16).
    def add_instance(defn, tr)
      i = ComponentInstance.new(defn)
      i.transformation = tr
      i.parent_entities = self
      defn.instances << i if defn.respond_to?(:instances)
      @list << i
      i
    end
    def add_curve(pts); pts.each_cons(2).map { |a, b| e = Edge.new(a, b); @list << e; e }; end
    def add_line(a, b); e = Edge.new(a, b); @list << e; e; end
    # Real SketchUp REFUSES a face with a repeated point - "Duplicate
    # points in array" - and a builder that swallows that raise loses
    # every face after it. The stub used to accept them silently, so
    # rt84 passed green while the user's gable soffit was not being
    # built at all (2026-08-24). It refuses them now, like the real one.
    def add_face(pts)
      # ...and it works to 1/1000", so two points a ten-thousandth apart
      # are the SAME point to it, however different they look in Ruby.
      key = Array(pts).map { |p| [p.x.round(3), p.y.round(3), p.z.round(3)] }
      raise ArgumentError, 'Duplicate points in array' if key.uniq.length < key.length
      f = Face.new(pts)
      @list << f
      f
    end
    def add_3d_text(*_a); true; end
    def clear!; @list = []; true; end
    def erase_entity(e); @list.delete(e); end
    def erase_entities(list); Array(list).each { |e| @list.delete(e) }; true; end
    def to_a; @list.dup; end
    # The stub cannot intersect geometry; the reference fence tool's knife
    # calls this and then erases whatever lies beyond the plane, which the
    # stub CAN do. So the intersect is a no-op and the erase is real
    # (2026-08-17).
    def intersect_with(*_a); true; end
    # Explode: the instance's geometry, transformed, becomes ours. Enough for
    # a suite to see what a cut left behind.
    def explode_into!(inst)
      tr = inst.transformation
      src = inst.respond_to?(:definition) ? inst.definition.entities : inst.entities
      src.each do |e|
        if e.is_a?(Face)
          f = Face.new(e.points.map { |p| p.transform(tr) })
          f.material = e.material
          @list << f
        elsif e.is_a?(Edge)
          @list << Edge.new(e.a.transform(tr), e.b.transform(tr))
        elsif e.is_a?(Group) || e.is_a?(ComponentInstance)
          g = ComponentInstance.new(e.respond_to?(:definition) ? e.definition : nil)
          g.transformation = tr * e.transformation
          g.parent_entities = self
          @list << g
        end
      end
      @list.delete(inst)
      true
    end
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
    def persistent_id; @pid ||= Sketchup.next_pid; end
    attr_accessor :parent_entities
    def make_unique; self; end
    def explode
      return [] unless @parent_entities
      @parent_entities.explode_into!(self)
      @valid = false
      []
    end
  end

  # Behaves like a Group but keeps its edges on a definition, exactly like the
  # real one - plan_geometry has to walk both (2026-08-13, rt46).
  class ComponentDefinition
    attr_reader :entities
    attr_accessor :name, :path
    def initialize(name = ''); @entities = Entities.new; @name = name; @attrs = {}; end
    # Real definitions carry attribute dictionaries, and roof_tile_parts.rb
    # stamps every piece with its part name and coverage width. Without these
    # a suite could not run it at all (2026-08-19).
    def set_attribute(d, k, v); ((@attrs ||= {})[d] ||= {})[k] = v; v; end
    def get_attribute(d, k, dflt = nil)
      ((@attrs ||= {})[d] || {}).key?(k) ? @attrs[d][k] : dflt
    end
    # Real definitions know their instances; the reference fence tool never
    # asks, but a suite counting placements might (2026-08-16).
    def instances; @instances ||= []; end
    def bounds
      b = BoundsBox.new
      each_point(@entities, Geom::Transformation.new) { |p| b.add(p) }
      b
    end
    def each_point(ents, tr, &blk)
      ents.grep(Face).each { |f| f.points.each { |p| blk.call(p.transform(tr)) } }
      ents.each do |e|
        next unless e.is_a?(Group) || e.is_a?(ComponentInstance)
        sub = e.respond_to?(:definition) ? e.definition.entities : e.entities
        each_point(sub, tr * e.transformation, &blk)
      end
    end
  end

  # A box that really has a min and a max, for the few places that measure a
  # definition instead of a group (2026-08-16).
  class BoundsBox
    attr_reader :min, :max
    def initialize; @min = nil; @max = nil; end
    def add(p)
      if @min.nil?
        @min = Geom::Point3d.new(p.x, p.y, p.z); @max = Geom::Point3d.new(p.x, p.y, p.z)
      else
        @min = Geom::Point3d.new([@min.x, p.x].min, [@min.y, p.y].min, [@min.z, p.z].min)
        @max = Geom::Point3d.new([@max.x, p.x].max, [@max.y, p.y].max, [@max.z, p.z].max)
      end
      self
    end
    def width;  @min ? @max.x - @min.x : 0.0; end
    def height; @min ? @max.y - @min.y : 0.0; end
    def depth;  @min ? @max.z - @min.z : 0.0; end
    def center; @min ? Geom::Point3d.new((@min.x + @max.x) / 2, (@min.y + @max.y) / 2, (@min.z + @max.z) / 2) : Geom::Point3d.new; end
  end

  class ComponentInstance < Group
    attr_accessor :material
    def initialize(defn = nil); super(); @definition = defn; end
    def definition; @definition ||= ComponentDefinition.new; end
  end

  # model.definitions - the reference fence tool loads a .skp through it. In
  # the cloud there is no SketchUp to parse the file, so a suite REGISTERS a
  # ready-made definition against a path first, and load hands it back
  # (2026-08-16). Loading a path nobody registered returns nil, like a bad
  # file would.
  class DefinitionList
    include Enumerable
    def initialize; @list = []; @by_path = {}; end
    def each(&b); @list.each(&b); end
    def length; @list.length; end
    def add(name = ''); d = ComponentDefinition.new(name); @list << d; d; end
    def [](name); @list.find { |d| d.name == name }; end
    def register!(path, defn); @by_path[path.to_s] = defn; @list << defn unless @list.include?(defn); defn; end
    def load(path); @by_path[path.to_s]; end
    def purge_unused; true; end
  end

  class Selection
    include Enumerable
    def initialize; @list = []; end
    def each(&b); @list.each(&b); end
    def to_a; @list.dup; end
    def add(e); Array(e).each { |x| @list << x unless @list.include?(x) }; @list; end
    def clear; @list = []; end
    def length; @list.length; end
    def empty?; @list.empty?; end
    def first; @list.first; end
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
    # A real model knows where it was saved, and answers '' until it has been.
    # The stub had no #path at all, so plan_sheet_dialog blew up in the cloud on
    # code that is perfectly fine in SketchUp (2026-08-14, rt51).
    attr_accessor :path, :title
    def initialize; @attrs = {}; @entities = Entities.new; @layers = Layers.new; @ops = []; @materials = Materials.new; @selection = Selection.new; @path = ''; @title = ''; @definitions = DefinitionList.new; end
    def materials; @materials; end
    def definitions; @definitions; end
    def selection; @selection; end
    # SketchUp has BOTH: entities is the top level, active_entities is
    # whatever group is open for editing. With nothing open they are the same
    # thing, and the stub never opens a group - but a builder that says
    # active_entities (most of them do) could not run here without it.
    def active_entities; @entities; end
    def set_attribute(d, k, v); (@attrs[d] ||= {})[k] = v; v; end
    def get_attribute(d, k, dflt = nil); (@attrs[d] || {}).key?(k) ? @attrs[d][k] : dflt; end
    def delete_attribute(d, k); (@attrs[d] || {}).delete(k); end
    # The real API hands back a dictionary you can list the keys of. Needed by
    # anything that has to FIND state rather than be told where it is
    # (2026-08-15, StateBackup looking for recoverable backups).
    def attribute_dictionary(d, _create = false); @attrs[d]; end
    # Real signature: (name, disable_ui, next_transparent, transparent) -
    # the transparent flag folds an op into the previous undo step.
    def start_operation(n, _disable_ui = nil, _next_tr = nil, transparent = false)
      @ops << [:start, n, transparent ? :transparent : nil].compact
      true
    end
    def commit_operation; @ops << [:commit]; true; end
    def abort_operation; @ops << [:abort]; true; end
    # save_copy writes the whole model somewhere WITHOUT changing the file
    # the user is working on - which is the only reason a background backup
    # can be invisible. The stub writes a marker file so a test can see that
    # a copy really landed (2026-08-15).
    attr_reader :copies
    def save_copy(path)
      @copies ||= []
      @copies << path.to_s
      File.write(path.to_s, "stub skp copy\n")
      true
    end
    def add_observer(_o); true; end
    def remove_observer(_o); true; end
    def line_styles; nil; end
    def respond_to_line_styles?; false; end
    # Handing the mouse to a tool. The stub had no select_tool at all, so any
    # window whose job ENDS in "now go draw it" could not be run in the cloud -
    # the one thing worth proving about such a window (2026-08-16, fence
    # library). It remembers the tool so a suite can ask which one it got.
    attr_reader :selected_tool
    def select_tool(tool); @selected_tool = tool; true; end
  end

  @model = Model.new
  class << self
    def active_model; @model; end
    def reset_model!; @model = Model.new; end
    def send_action(_a); true; end
    # The status bar and the measurement box. Tools talk to these constantly;
    # without them a tool cannot be run in the cloud at all (2026-08-15).
    def set_status_text(*_a); true; end
    def vcb_label=(_v); _v; end
    def vcb_value=(_v); _v; end
    def format_length(v); v.to_s; end
    def platform; :platform_win; end
  end
end

module UI
  class HtmlDialog
    attr_reader :callbacks, :scripts
    def initialize(_opts = {}); @callbacks = {}; @scripts = []; end
    def add_action_callback(name, &blk); @callbacks[name] = blk; end
    def execute_script(s); @scripts << s; end
    def set_html(h); @html = h; end
    attr_reader :html, :closed
    # Real HtmlDialogs can be resized after they open - several windows here
    # do it to escape a size SketchUp remembered (2026-08-16).
    def set_size(w, h); @size = [w, h]; end
    attr_reader :size
    def set_on_closed(&_b); end
    def show; @shown = true; end
    def shown?; @shown == true; end
    def close; @closed = true; end
    def visible?; true; end
  end
  def self.messagebox(_m); nil; end
  def self.openpanel(*_a); nil; end

  # Timers used to return nil and drop the block on the floor, so anything
  # that runs on a timer could not be tested at all (2026-08-15, AutoBackup).
  # They now hand back an id and keep the block, so a suite can fire it.
  @timers = {}
  @timer_seq = 0
  class << self
    attr_reader :timers
    def start_timer(secs, repeat = false, &blk)
      @timer_seq += 1
      @timers[@timer_seq] = { secs: secs, repeat: repeat, block: blk }
      @timer_seq
    end
    def stop_timer(id); !@timers.delete(id).nil?; end
    def fire_timer!(id); (@timers[id] || {})[:block]&.call; end
    def reset_timers!; @timers.clear; end
  end
end

module InteriorPro
  def self.assign_tag(_g, _name); true; end

  # In SketchUp this is a CLASS, and plan_editor really does say
  # `InteriorPro::WallTool.new` after moving a wall end, to rebuild the band
  # and re-join the corners. The stub had it as a module, so every code path
  # that got that far died on "undefined method new for module" - the
  # coordinates had already been written, so the test LOOKED like it passed
  # while the operation had actually failed (2026-08-14, rt54).
  #
  # It is a class now, with the handful of methods that path calls. They do
  # nothing to the geometry - there is no geometry here - but they let the
  # real code run to the end, which is the whole point of the stub.
  module WallTool
    USE_NATIVE_OPENINGS = true
    def self.read_door_openings(_w); []; end
    def self.persist_door_openings!(w, list)
      w.set_attribute('InteriorPro', 'door_openings',
                      list.map { |o| [o[:t], o[:width], o[:height]] })
    end

    # A module, not a class, ON PURPOSE. In SketchUp WallTool IS a class, but a
    # dozen suites reopen it here as `module InteriorPro; module WallTool` to
    # feed it their own openings, and a class would make every one of them die
    # on "WallTool is not a module". A module that answers .new behaves exactly
    # the same for every caller, which is what the stub is for.
    def self.new; Builder.new; end

    class Builder
    def wall_data(group)
      return nil unless group && group.valid?
      { group: group,
        sx: group.get_attribute('InteriorPro', 'start_x').to_f,
        sy: group.get_attribute('InteriorPro', 'start_y').to_f,
        ex: group.get_attribute('InteriorPro', 'end_x').to_f,
        ey: group.get_attribute('InteriorPro', 'end_y').to_f,
        th: group.get_attribute('InteriorPro', 'thickness').to_f }
    end

    # The four band corners, square to the wall - enough shape for anything
    # that only wants to know they were recomputed.
    def compute_perpendicular_corners_from_data(d)
      return nil unless d
      len = Math.hypot(d[:ex] - d[:sx], d[:ey] - d[:sy])
      return nil if len < 1e-9
      ux = (d[:ex] - d[:sx]) / len
      uy = (d[:ey] - d[:sy]) / len
      hx = -uy * d[:th]
      hy = ux * d[:th]
      [d[:sx], d[:sy], d[:ex], d[:ey],
       d[:ex] + hx, d[:ey] + hy, d[:sx] + hx, d[:sy] + hy]
    end

    def save_corners_attr(group, corners)
      group.set_attribute('InteriorPro', 'corners_xy', corners)
    end

    def rebuild_wall_geometry(group, _corners, _data)
      group.set_attribute('InteriorPro', 'rebuilt',
                          group.get_attribute('InteriorPro', 'rebuilt').to_i + 1)
      true
    end

    def join_corners(group, _model, allow_centerline_fallback: false)
      group.set_attribute('InteriorPro', 'joined',
                          group.get_attribute('InteriorPro', 'joined').to_i + 1)
      allow_centerline_fallback
    end
    end
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
