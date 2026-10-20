require_relative 'wardrobe_domain'
def check(v,label);raise label unless v;end
def rejects;begin;yield;rescue ArgumentError;return;end;raise 'Expected rejection';end
core=InteriorPro::Cabinetry;domain=InteriorPro::Storage::WardrobeDomain
c=domain.cabinet('test');doc=core.create(domain:'wardrobe',assembly_id:'test');doc['cabinets']=[c]
check(domain.validate(core.validate(doc)),'Default product rejected')
check(c['sections'].sum { |s|s['height'] }==78.5,'Interior heights lost precision')
c['sections']=(core.divide(28,4).map.with_index { |h,i|{'id'=>"drawer-#{i}",'kind'=>'drawer','height'=>h} })+[{'id'=>'hanging','kind'=>'hanging','height'=>50.5}]
check(domain.validate(core.validate(doc)),'Four 7-inch drawers + hanging rejected')
check(core.section_layout(c['sections'],start:4.75).first(4).map { |r|r['height'] }==[7,7,7,7],'Nominal drawer deduction leaked')
c['sections'][0]['height']=6.875;rejects { domain.validate(core.validate(doc)) };c['sections'][0]['height']=7
c['depth']=19;rejects { domain.validate(doc) };c['depth']=24
%w[open single double].each { |f|c['front']=f;check(domain.validate(doc),'Door mode rejected') }
c['front']='drawers';rejects { domain.validate(doc) };c['front']='open'
c['sections'][0]['height']=4;rejects { domain.validate(doc) };c['sections'][0]['height']=7
second=core.copy(c);second['id']='second';second['position']['x']=30;doc['cabinets']<<second
check(domain.validate(doc),'Touching cabinets rejected')
second['position']['x']=29.875;rejects { domain.validate(doc) }
second['position'].merge!('x'=>54,'angle'=>90);check(domain.validate(doc),'Rotated non-overlapping cabinets rejected')
doc['domain']='laundry';rejects { domain.validate(doc) }
puts 'PASS: wardrobe dimensions, exact section sums, 28/4 drawers, hanging clearance, doors, fit rejection, touching/rotated footprints, domain isolation.'
