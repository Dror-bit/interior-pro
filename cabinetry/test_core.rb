require_relative 'model_store'
def assert(value); raise 'Assertion failed' unless value; end
def rejects
  begin; yield; rescue ArgumentError; return; end
  raise 'Expected rejection'
end
core=InteriorPro::Cabinetry
cab={'id'=>'c1','product_id'=>'base','width'=>30,'height'=>34.5,'depth'=>24,
     'position'=>{'x'=>0,'y'=>0,'z'=>0,'angle'=>0},'sections'=>[]}
a=core.create(domain:'laundry',assembly_id:'room1')
b=core.create(domain:'wardrobe',assembly_id:'room1')
added=core.plan(a,[{'type'=>'add','cabinet'=>cab}],expected_revision:0,validator:->(_){true})
assert(a['cabinets'].empty? && b['cabinets'].empty? && added['revision']==1)
rejects { core.plan(added,[{'type'=>'add','cabinet'=>cab}],expected_revision:1,validator:->(_){true}) }
rejects { core.plan(added,[{'type'=>'remove','id'=>'c1'}],expected_revision:0,validator:->(_){true}) }
rejects { core.plan(a,[{'type'=>'add','cabinet'=>cab}],expected_revision:0,validator:->(_){false}) }
assert(a['cabinets'].empty?)
assert(core.divide(28,4)==[7,7,7,7])
assert(core.divide(28,3).sum==28 && core.divide(28,3).all? { |h| (h*8)%1==0 })
rejects { core.divide(28.01,4) }
rows=core.section_layout(core.divide(28,4).each_with_index.map { |h,i|{'id'=>"d#{i}",'height'=>h} })
assert(rows.last['top']==28 && rows.first['height']==7 && rows.first['face_height']==6.875)
v=core.create(domain:'vanity',assembly_id:'room1')
assert(core.domains_for_tool('storage')==%w[laundry wardrobe])
assert(core.tool_for_domain('laundry')=='storage' && core.tool_for_domain('wardrobe')=='storage')
assert(core.tool_for_domain('vanity')=='vanity')
core.domains_for_tool('storage').clear
assert(core.domains_for_tool('storage')==%w[laundry wardrobe])
rejects { core.domains_for_tool('kitchen') }
rejects { core.create(domain:'pantry',assembly_id:'room1') }
fake=Class.new do
  attr_reader :data
  def initialize; @data={}; end
  def get_attribute(d,k); @data[[d,k]]; end
  def set_attribute(d,k,v); @data[[d,k]]=v; end
end.new
fake.set_attribute('KitchenLab','document','untouched')
store=core::ModelStore.new(fake)
store.write(a,expected_revision:nil); store.write(b,expected_revision:nil)
store.write(v,expected_revision:nil)
store.write(added,expected_revision:0)
rejects { store.write(added,expected_revision:0) }
assert(store.read(domain:'wardrobe',assembly_id:'room1')['cabinets'].empty?)
assert(store.read(domain:'vanity',assembly_id:'room1')==v)
assert(fake.get_attribute('KitchenLab','document')=='untouched')
assert(core.plan(added,[{'type'=>'remove','id'=>'c1'}],expected_revision:1,validator:->(_){true})['cabinets'].empty?)
puts 'PASS: isolated tools/assemblies, atomic edits, stale writes, product validation, exact eighth-inch sections, kitchen preservation.'
