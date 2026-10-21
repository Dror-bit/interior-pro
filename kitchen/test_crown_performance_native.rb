require 'json'
module CrownPerformanceCheck
 ROOT='C:/Users/rordt/OneDrive/Documents/ChatGPT/Kitchen Plugin/.crown-action-perf'
 def self.run
  m=Sketchup.active_model
  raise 'Wrong performance model' unless Process.pid==3032 && File.basename(m.path)=='kitchen-gallery-qa.skp'
  InteriorPro::KitchenPlan.bind_active_model!
  # Run against the installed code already loaded in this model.
  load 'C:/Users/rordt/AppData/Roaming/SketchUp/SketchUp 2024/SketchUp/Plugins/interior_pro/debug_slow_probe.rb'
  report={pid:Process.pid,path:m.path};clock=->{Process.clock_gettime(Process::CLOCK_MONOTONIC)}
  m.start_operation('Crown performance regression',true)
  begin
   t=clock.call
   KitchenLab.with_document_snapshot do
    KitchenLab.unpack_units!
    KitchenLab.crowns!
    KitchenLab.pack_units!(refresh_baseboards:false)
   end
   report[:first_refresh]=clock.call-t
   t=clock.call;result=KitchenLab.crowns!;report[:unchanged_refresh]=clock.call-t
   report[:skipped]=result==:unchanged
   raise 'Unchanged crown rebuilt' unless report[:skipped]
   raise 'Unchanged crown exceeds 2 seconds' unless report[:unchanged_refresh]<2
   t=clock.call;KitchenLab::CrownJoints.refresh_from_house!;report[:house_refresh]=clock.call-t
   raise 'Unchanged house crown exceeds 2 seconds' unless report[:house_refresh]<2
   s=KitchenLab.settings;shape=KitchenLab::CrownJoints.shape(KitchenLab.crown_settings(s))
   t=clock.call
   g=KitchenLab.crown_piece(m.entities,'Timing only',shape,nil){|side,d,z|[side*30,d,z]}
   report[:piece_seconds]=clock.call-t;report[:profile_vertices]=shape.length;report[:piece_solid]=g.manifold?;g.erase!
   # A remote wall must not invalidate crown geometry; a nearby wall must.
   before=KitchenLab.with_document_snapshot{KitchenLab.crown_dependency_signature}
   dummy=m.entities.add_group
   dummy.set_attribute('InteriorPro','type','wall');dummy.set_attribute('InteriorPro','id','crown-perf-probe')
   dummy.entities.add_line([100000,100000,0],[100010,100000,96])
   remote=KitchenLab.with_document_snapshot{KitchenLab.crown_dependency_signature}
   raise 'Remote wall invalidated crown' unless before==remote
   d=KitchenLab.document['cabinets'].first
   point=KitchenLab.cabinet_transform(d).origin
   dummy.transformation=Geom::Transformation.translation([point.x-100000,point.y-100000,point.z])
   near=KitchenLab.with_document_snapshot{KitchenLab.crown_dependency_signature}
   raise 'Nearby wall failed to invalidate crown' if before==near
   dummy.erase!
   report[:remote_wall_skipped]=true;report[:near_wall_detected]=true
   m.set_attribute(KitchenLab::DICT,'backsplash_opening_signature',KitchenLab::Backsplash.opening_signature(m))
   t=clock.call;KitchenLab.sync_unit_moves!(m);report[:unrelated_commit_sync]=clock.call-t
   raise 'Unrelated commit exceeds 2 seconds' unless report[:unrelated_commit_sync]<2

   # Force one actual profile change, then verify the second call is a no-op.
   doc=KitchenLab.document
   KitchenLab.write_document!(doc['cabinets'],doc['settings'].merge('crown_height'=>5.5,'crown_match_house'=>false,'crown_profile'=>'crown'))
   t=clock.call
   KitchenLab.with_document_snapshot{KitchenLab.unpack_units!;KitchenLab.crowns!;KitchenLab.pack_units!(refresh_baseboards:false)}
   report[:changed_profile]=clock.call-t
   raise 'Profile rebuild exceeded 30 seconds' unless report[:changed_profile]<30
   raise 'Rebuilt profile not cached' unless KitchenLab.crowns! == :unchanged
   report[:pass]=true
  ensure
   m.abort_operation
  end
  File.write(File.join(ROOT,'native-result.json'),JSON.pretty_generate(report))
  puts report.inspect
 rescue Exception=>e
  File.write(File.join(ROOT,'native-result.json'),JSON.pretty_generate({pass:false,error:e.message,backtrace:e.backtrace.first(10),partial:report}))
  puts 'Crown performance check: '+e.message
 end
end
UI.start_timer(0.2,false){CrownPerformanceCheck.run}
