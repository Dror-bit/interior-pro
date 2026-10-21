if defined?(Sketchup) && Sketchup.respond_to?(:active_model)
  model=Sketchup.active_model
  model.start_operation('Crown shell regression - discarded',true)
  begin
    holder=model.entities.add_group
    [[0,0],[1,1]].each do |x,y|
      part=holder.entities.add_group
      face=part.entities.add_face([[x,y,0],[x+1,y,0],[x+1,y+1,0],[x,y+1,0]])
      face.pushpull(1)
      raise 'Fixture cube not closed' unless part.manifold?
      part.explode
    end
    raise 'Fixture must reproduce edge-touching shells' if holder.manifold?
    area=holder.entities.grep(Sketchup::Face).sum(&:area)
    pieces=KitchenLab::CrownJoints.closed_crown_parts(holder)
    raise 'Failed to separate edge-touching pieces' unless pieces.length==2 && pieces.all?(&:manifold?)
    raise 'Surface area changed' unless (pieces.sum{|p|p.entities.grep(Sketchup::Face).sum(&:area)}-area).abs<1e-7
    raise 'Solid volume changed' unless (pieces.sum(&:volume)-2.0).abs<1e-7
    puts 'PASS: native SketchUp edge-touching cubes separated; all faces, area and volume preserved.'
  ensure
    model.abort_operation
  end
else
  puts 'SKIP: native SketchUp geometry regression requires SketchUp.'
end
