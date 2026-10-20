require 'json'

module InteriorPro
  # Standalone groups own their data: native Move/Delete/Undo need no rebuild watcher.
  module StandaloneShelves
    remove_const(:ENABLED) if const_defined?(:ENABLED, false)
    ENABLED = true
    DICT = 'InteriorPro::StandaloneShelf' unless const_defined?(:DICT, false)
    DEFAULTS = {'width'=>36.0,'depth'=>12.0,'thickness'=>1.5,'height'=>60.0}.freeze unless const_defined?(:DEFAULTS, false)
    module_function

    def dimension(value)
      text=value.to_s.strip
      match=text.match(/\A(?:(\d+)\s+)?(\d+)\/(\d+)\z/)
      n=match ? match[1].to_f+Float(match[2])/Float(match[3]) : Float(text)
      raise ArgumentError, 'Enter a finite dimension in inches.' unless n.finite?
      raise ArgumentError, 'Use whole inches or increments of 1/8 inch.' if (n*8-(n*8).round).abs>0.00001
      n
    end

    def validate(values)
      d=DEFAULTS.keys.to_h { |key| [key,dimension(values.fetch(key))] }
      raise ArgumentError, 'Width, depth and thickness must be positive.' unless %w[width depth thickness].all? { |key| d[key]>0 }
      raise ArgumentError, 'Height above the floor cannot be negative.' if d['height']<0
      raise ArgumentError, 'Shelf thickness cannot exceed its width or depth.' if d['thickness']>[d['width'],d['depth']].min
      d
    end

    def shelf?(group)
      group.respond_to?(:entities) && group.valid? && stored(group,'dimensions').is_a?(String)
    end

    def stored(group,key,fallback=nil)
      group.get_attribute(DICT,key,group.definition.get_attribute(DICT,key,fallback))
    end

    def dimensions(group)
      d=JSON.parse(stored(group,'dimensions'))
      t=group.transformation
      d['width']*=t.xaxis.length;d['depth']*=t.yaxis.length;d['thickness']*=t.zaxis.length
      d['height']=t.origin.z.to_f-stored(group,'floor_z',0).to_f
      d
    end

    def fill(group, data)
      w=data['width'];d=data['depth'];h=data['thickness']
      group.entities.clear!
      face=group.entities.add_face([0,0,0],[w,0,0],[w,-d,0],[0,-d,0])
      face.reverse! if face.normal.z<0
      face.pushpull(h)
      group.set_attribute(DICT,'dimensions',JSON.generate(data))
      group.definition.set_attribute(DICT,'dimensions',JSON.generate(data))
      group.name='Shelf'
      group
    end

    # Caller owns the transaction. Origin is the chosen back-left point on the floor.
    def create(model, data, floor_point, angle=0)
      d=validate(data)
      g=model.entities.add_group
      fill(g,d)
      g.set_attribute(DICT,'floor_z',floor_point.z.to_f)
      g.definition.set_attribute(DICT,'floor_z',floor_point.z.to_f)
      origin=Geom::Point3d.new(floor_point.x,floor_point.y,floor_point.z+d['height'])
      g.transformation=Geom::Transformation.translation(origin.to_a)*Geom::Transformation.rotation(ORIGIN,Z_AXIS,angle)
      g
    end

    def update(group, data)
      raise ArgumentError, 'Select an unlocked standalone shelf.' unless shelf?(group) && !group.locked?
      d=validate(data);old=group.transformation
      raise ArgumentError, 'Keep the shelf horizontal before editing its height.' unless old.zaxis.parallel?(Z_AXIS) && old.zaxis.dot(Z_AXIS)>0
      floor=stored(group,'floor_z',0).to_f
      origin=Geom::Point3d.new(old.origin.x,old.origin.y,floor+d['height'])
      # Read live placement so moving/rotating a shelf never restores an old position.
      group.make_unique
      fill(group,d)
      group.transformation=Geom::Transformation.axes(origin,old.xaxis.normalize,old.yaxis.normalize,old.zaxis.normalize)
      group
    end

    def transaction(model, label)
      model.start_operation(label,true)
      result=yield
      model.commit_operation
      result
    rescue StandardError
      model.abort_operation
      raise
    end

    def show
      return unless ENABLED
      model=Sketchup.active_model
      raise 'Close the current group before placing or editing a shelf.' if model.active_path
      selected=model.selection.to_a
      group=selected.length==1 && shelf?(selected.first) ? selected.first : nil
      current=group ? dimensions(group) : DEFAULTS.dup
      prompts=['Width (in)','Depth (in)','Thickness (in)','Height to shelf underside above floor (in)']
      loop do
        values=UI.inputbox(prompts,DEFAULTS.keys.map { |k| format('%.3f',current[k]).sub(/\.?0+$/,'') },group ? 'Edit shelf' : 'Standalone shelf')
        return unless values
        begin
          data=validate(DEFAULTS.keys.zip(values).to_h)
          if group
            transaction(model,'Edit shelf') { update(group,data) }
          else
            model.select_tool(Placement.new(model,data))
          end
          return
        rescue ArgumentError=>e
          UI.messagebox(e.message)
        end
      end
    rescue StandardError=>e
      UI.messagebox(e.message)
    end

    class Placement
      def initialize(model,data)
        @model=model;@data=data;@point=Sketchup::InputPoint.new;@angle=0.0
      end
      def activate
        Sketchup.status_text='Shelf: click its back-left point on the FLOOR. Left/Right arrows rotate 90 degrees. Esc cancels.'
      end
      def onMouseMove(flags,x,y,view)
        @point.pick(view,x,y);view.invalidate
      end
      def onKeyDown(key,repeat,flags,view)
        @angle+=(key==37 ? -Math::PI/2 : Math::PI/2) if [37,39].include?(key)
        view.invalidate
      end
      def corners
        p=@point.position
        t=Geom::Transformation.translation([p.x,p.y,p.z+@data['height']])*Geom::Transformation.rotation(ORIGIN,Z_AXIS,@angle)
        [0,@data['thickness']].flat_map { |z| [[0,0,z],[@data['width'],0,z],[@data['width'],-@data['depth'],z],[0,-@data['depth'],z]].map { |v| Geom::Point3d.new(v).transform(t) } }
      end
      def draw(view)
        return unless @point.valid?
        @point.draw(view);v=corners;view.drawing_color='#365f50';view.line_width=2
        view.draw(GL_LINE_LOOP,v[0,4]);view.draw(GL_LINE_LOOP,v[4,4])
        view.draw(GL_LINES,(0..3).flat_map { |i| [v[i],v[i+4]] })
      end
      def getExtents
        box=Geom::BoundingBox.new
        corners.each { |p| box.add(p) } if @point.valid?
        box
      end
      def onLButtonDown(flags,x,y,view)
        @point.pick(view,x,y);return unless @point.valid?
        raise 'Return to the model root before placing a shelf.' if @model.active_path
        group=StandaloneShelves.transaction(@model,'Place shelf') { StandaloneShelves.create(@model,@data,@point.position,@angle) }
        @model.selection.clear;@model.selection.add(group)
        @model.select_tool(nil)
      rescue StandardError=>e
        UI.messagebox(e.message)
      end
      def onCancel(reason,view);@model.select_tool(nil);end
      def deactivate(view);view.invalidate;end
    end

    def install!
      return unless ENABLED && defined?(UI) && UI.respond_to?(:menu)
      return if @installed
      UI.menu('Plugins').add_item('Standalone shelf...') { InteriorPro::StandaloneShelves.show }
      UI.add_context_menu_handler do |menu|
        selection=Sketchup.active_model.selection.to_a
        if ENABLED && selection.length==1 && shelf?(selection.first)
          menu.add_item('Edit shelf...') { InteriorPro::StandaloneShelves.show }
        end
      end
      @installed=true
    end
  end
end
InteriorPro::StandaloneShelves.install!
