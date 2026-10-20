require_relative 'plan'
class PlanTestModel
  def initialize;@dict={};end
  def attribute_dictionary(*);@dict;end
  def get_attribute(_,key);@dict[key];end
  def set_attribute(_,key,value);@dict[key]=value;end
end
m=PlanTestModel.new;store=InteriorPro::Cabinetry::ModelStore.new(m)
%w[laundry wardrobe vanity].each do |domain|
 d=InteriorPro::Cabinetry.create(domain:domain,assembly_id:'same')
 d['cabinets']=[InteriorPro::Storage::WardrobeDomain.cabinet('same')]
 d['cabinets'][0]['position']={'x'=>10,'y'=>20,'z'=>0,'angle'=>90}
 store.write(d,expected_revision:nil)
end
before=Marshal.dump(m)
rows=InteriorPro::Storage::Plan.payload(m,1)['cabinets']
raise 'Domain collision' unless rows.map{|r|r['domain']}.sort==%w[laundry wardrobe]
raise 'Wrong rotation/coordinates' unless rows.all? { |r|r['polygon'].zip([[10,20],[10,50],[34,50],[34,20]]).all?{|a,b|a.zip(b).all?{|x,y|(x-y).abs<1e-6}} }
raise 'Wrong level' unless InteriorPro::Storage::Plan.payload(m,2)['cabinets'].empty?
raise 'Read changed model' unless Marshal.dump(m)==before
puts 'PASS: 2D world coordinates, rotation, per-domain identity, level filtering and read-only payload.'
