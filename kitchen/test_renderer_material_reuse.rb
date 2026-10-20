require 'json'
require 'digest'
root=ARGV.fetch(0,File.dirname(__FILE__))
module Sketchup
  class Color
    def initialize(*v);@v=v.length==1 ? v[0] : v;end
    def to_a;@v;end
  end
end
class FakeMaterial
  attr_accessor :name
  attr_reader :writes
  def initialize(name,color);@name=name;@color=Sketchup::Color.new(color);@writes=0;end
  def color;@color;end
  def color=(v);@color=v;@writes+=1;end
end
class FakeMaterials
  attr_reader :added
  def initialize(rows);@rows=rows.to_h{|m|[m.name,m]};@added=[];end
  def [](name);@rows[name];end
  def add(name);@added<<name;@rows[name]=FakeMaterial.new(name,nil);end
end
module KitchenLab
  def self.settings;{};end
end
source=File.read(File.join(root,'kitchen_lab.rb'))
Kernel.eval('module KitchenLab;'+source[/  def self.material\(key,color\).*?(?=  def self.box)/m]+'end')
load File.join(root,'countertop_materials.rb')
color='#E8E4DA'
original=FakeMaterial.new('KitchenLab / ivory',color)
normalized=FakeMaterial.new('KitchenLab _ ivory',color)
[original,normalized].each do |mat|
  materials=FakeMaterials.new([mat]);model=Struct.new(:materials).new(materials)
  KitchenLab.instance_variable_set(:@model,model)
  3.times { raise 'Did not reuse finish' unless KitchenLab.material('ivory',color).equal?(mat) }
  raise 'Unnecessary color write' unless mat.writes==0
  raise 'Duplicate finish' unless materials.added.empty?
  KitchenLab.material('ivory','#000000')
  raise 'Color edit ignored' unless mat.writes==1
end
card={'color'=>[210,210,205]};key=Digest::SHA256.hexdigest(JSON.generate(card));value={'card'=>card,'key'=>key}
['Kitchen countertop / ','Kitchen countertop _ '].each do |prefix|
  mat=FakeMaterial.new(prefix+key,nil);materials=FakeMaterials.new([mat]);model=Struct.new(:materials).new(materials)
  raise 'Countertop duplicated after renderer rename' unless KitchenLab::CountertopMaterials.resolve(model,value).equal?(mat) && materials.added.empty?
end
puts 'PASS renderer-normalized finishes, no-op color assignments, real color changes, countertop reuse'
