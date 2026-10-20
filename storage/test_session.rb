require_relative 'session'
class StorageTestModel
  def initialize;@attributes={};end
  def get_attribute(dict,key);@attributes[[dict,key]];end
  def set_attribute(dict,key,value);@attributes[[dict,key]]=value;end
end
def check(value,message);raise message unless value;end
def rejects;begin;yield;rescue ArgumentError;return;end;raise 'Expected rejection';end
core=InteriorPro::Cabinetry
model=StorageTestModel.new;store=core::ModelStore.new(model)
%w[laundry wardrobe vanity].each do |domain|
  %w[main second].each { |id|store.write(core.create(domain:domain,assembly_id:id,settings:{'sentinel'=>domain+id}),expected_revision:nil) }
end
before=Marshal.dump(model)
session=InteriorPro::Storage::Session.new(model)
check(session.document['settings']['sentinel']=='laundrymain','Existing laundry document lost')
session.switch('laundry','second')
session.switch('wardrobe','main')
check(session.document['settings']['sentinel']=='wardrobemain','Mode crossed source namespace')
check(session.service.is_a?(InteriorPro::Storage::WardrobeService),'Wardrobe adapter missing')
session.switch('laundry')
check(session.assembly_id=='second','Per-mode assembly selection lost')
request={'domain'=>'laundry','assembly_id'=>'second','revision'=>0}
session.check_request!(request)
rejects { session.check_request!(request.merge('domain'=>'wardrobe')) }
rejects { session.check_request!(request.merge('assembly_id'=>'main')) }
rejects { session.check_request!(request.merge('revision'=>1)) }
rejects { session.switch('vanity') }
rejects { session.switch('laundry','../main') }
session.switch('wardrobe','new-design')
check(session.document['cabinets'].empty?,'New design not empty')
check(Marshal.dump(model)==before,'Opening or switching modified model data')
puts 'PASS: mode namespaces, existing designs, per-mode assemblies, stale/cross-domain requests, wardrobe adapter, rejected IDs, no writes on open.'
