require 'json'
root=__dir__
m=Sketchup.active_model
raise 'Wrong model' unless KitchenLab.instance_variable_get(:@model).equal?(m)
report={model:m.path,tests:{}}
saved=KitchenLab.instance_variable_get(:@unit_syncing)
KitchenLab.instance_variable_set(:@unit_syncing,true)
m.start_operation('Kitchen feedback regression (aborted)',true)
begin
  KitchenLab.with_document_snapshot do
    bases=m.entities.grep(Sketchup::Group).select { |g|g.get_attribute('InteriorPro','type')=='baseboard' }
    bases.each { |g|g.delete_attribute('KitchenLab','baseboard_cut_signature') }
    t=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    KitchenLab.refresh_kitchen_baseboards!
    report[:tests][:missing_signature]={seconds:Process.clock_gettime(Process::CLOCK_MONOTONIC)-t,rebuilt:KitchenLab.instance_variable_get(:@last_baseboard_updates)}
    t=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    KitchenLab.refresh_kitchen_baseboards!
    report[:tests][:repeat]={seconds:Process.clock_gettime(Process::CLOCK_MONOTONIC)-t,rebuilt:KitchenLab.instance_variable_get(:@last_baseboard_updates)}
    signature=KitchenLab.crown_dependency_signature
    house=m.entities.grep(Sketchup::Group).select { |g|g.get_attribute('InteriorPro','type')=='crown' }
    clones=house.map do |g|
      copy=g.copy
      copy.material=g.material;copy.layer=g.layer;copy.hidden=g.hidden?
      g.attribute_dictionaries.each { |dict|dict.each_pair { |k,v|copy.set_attribute(dict.name,k,v) } }
      g.erase!;copy
    end
    report[:tests][:recreated_crowns_stable]=signature==KitchenLab.crown_dependency_signature
    clones.each { |g|g.transform!(Geom::Transformation.translation([1,0,0])) }
    report[:tests][:moved_crowns_detected]=signature!=KitchenLab.crown_dependency_signature
  end
  report[:pass]=report[:tests][:missing_signature][:rebuilt]==0 && report[:tests][:repeat][:rebuilt]==0 && report[:tests][:repeat][:seconds]<1 && report[:tests][:recreated_crowns_stable] && report[:tests][:moved_crowns_detected]
rescue => e
  report[:error]=[e.message,*e.backtrace.first(7)];report[:pass]=false
ensure
  m.abort_operation
  KitchenLab.instance_variable_set(:@unit_syncing,saved)
end
puts JSON.generate(report.reject { |k,_|k==:diff })

raise 'Kitchen molding feedback regression failed' unless report[:pass]
