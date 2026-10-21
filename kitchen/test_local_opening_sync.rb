require 'json'
module Sketchup;class Group;end;end
module Geom
  class Point3d
    def initialize(*p);@p=p.flatten;end
    def transform(t);self.class.new(@p.zip(t.offset).map{|a,b|a+b});end
    def to_a;@p;end
  end
end
Transform=Struct.new(:offset) do
  def to_a;[1,0,0,0,0,1,0,0,0,0,1,0,*offset,1];end
end
Bounds=Struct.new(:min,:max)
class LocalEntity
  attr_accessor :bounds,:transformation
  attr_reader :attrs,:persistent_id
  def initialize(id,type,min,max)
    @persistent_id=id;@attrs={'id'=>id.to_s,'type'=>type}
    @bounds=Bounds.new(Geom::Point3d.new(min),Geom::Point3d.new(max));@transformation=Transform.new([0,0,0])
  end
  def get_attribute(dict,key,default=nil);@attrs.fetch(key,default);end
  def attribute_dictionary(dict);@attrs;end
end
module InteriorPro
  module WallTool
    def self.anchor_side_offsets(t,ha);[0,-t];end
    def self.native_floor_z(va,h);0;end
    def self.read_door_openings(w);w.attrs.fetch('door_openings',[]);end
    def self.opening_pocket(sx,sy,ex,ey,sag,t,width)
      len=Math.hypot(ex-sx,ey-sy);u=[(ex-sx)/len,(ey-sy)/len]
      {p0:[sx+u[0]*(t-width/2.0),sy+u[1]*(t-width/2.0)],p1:[sx+u[0]*(t+width/2.0),sy+u[1]*(t+width/2.0)],dir:u}
    end
  end
end
module KitchenLab
  DICT='KitchenLab'
  class DocumentUndoObserver;end
  module Document;def self.read(raw);JSON.parse(raw);end;end
  def self.unit_groups;[];end
  def self.cabinets;[];end
  def self.write_document!(*);end
  def self.worktops!(previous:);@builds=(@builds||0)+1;end
  def self.publish;end
end
load File.join(__dir__,'kitchen_spatial.rb')
load File.join(__dir__,'kitchen_backsplash.rb')
load File.join(__dir__,'kitchen_units.rb')
class LocalModel
  attr_accessor :entities,:doc
  attr_reader :starts
  def initialize
    @entities=[];@attrs={};@starts=0
    @doc={'settings'=>{},'cabinets'=>[{'id'=>'cab','kind'=>'doors','wall'=>'A','x'=>0,'z'=>0,'width'=>36,'depth'=>24,'height'=>34.5}]}
  end
  def active_path;nil;end
  def get_attribute(dict,key,default=nil);key=='document' ? JSON.generate(@doc) : @attrs.fetch(key,default);end
  def set_attribute(dict,key,value);@attrs[key]=value;end
  def start_operation(*);@starts+=1;end
  def commit_operation;end
  def abort_operation;end
end
def check(v,msg);raise msg unless v;end
def signature(m);KitchenLab::Backsplash.opening_signature(m);end
def observer(m);KitchenLab::DocumentUndoObserver.new.onTransactionCommit(m);end
m=LocalModel.new
near=LocalEntity.new(1,'wall',[-5,-5,0],[600,0,96]);near.attrs.merge!('start_x'=>0,'start_y'=>0,'end_x'=>600,'end_y'=>0,'height'=>96,'thickness'=>5)
far=LocalEntity.new(2,'wall',[500,300,0],[600,305,96])
window=LocalEntity.new(3,'window',[500,-5,36],[530,0,72])
m.entities=[near,far,window]
b=KitchenLab::Backsplash
m.set_attribute('KitchenLab','backsplash_opening_signature',b.opening_signature(m,local:false))
b.prime_opening_signature!(m)
KitchenLab.instance_variable_set(:@model,m)
far.attrs['height']=110;observer(m)
check(m.starts==0,'First far edit after upgrading rebuilt kitchen')
before=signature(m);window.attrs['width_in']=35;observer(m)
check(m.starts==0 && signature(m)==before,'Far window rebuilt kitchen')
near.attrs['door_openings']=[{t:500,width:30,height:72,floor_offset:24}];observer(m)
check(m.starts==0,'Far native opening on kitchen wall rebuilt kitchen')
near.attrs['door_openings']<<{t:20,width:20,height:72,floor_offset:24};observer(m)
check(m.starts==1,'Near native opening did not reach production observer sync')
m.set_attribute('KitchenLab','backsplash_opening_signature',signature(m))
near.attrs['door_openings'].last[:height]=60;observer(m)
check(m.starts==2,'Near native opening edit did not rebuild')
m.set_attribute('KitchenLab','backsplash_opening_signature',signature(m))
near.attrs['door_openings'].pop;observer(m)
check(m.starts==3,'Deleting near opening did not rebuild')
m.set_attribute('KitchenLab','backsplash_opening_signature',signature(m))
window.bounds=Bounds.new(Geom::Point3d.new([10,-5,36]),Geom::Point3d.new([35,0,72]));observer(m)
check(m.starts==4,'Moving window into kitchen did not rebuild')
m.set_attribute('KitchenLab','backsplash_opening_signature',signature(m))
m.entities.delete(window);observer(m)
check(m.starts==5,'Deleting kitchen window did not rebuild')
m.set_attribute('KitchenLab','backsplash_opening_signature',signature(m))
upper=LocalEntity.new(4,'window',[10,-5,144],[35,0,180]);m.entities<<upper;observer(m)
check(m.starts==5,'Upstairs opening rebuilt downstairs kitchen')
near.attrs['height']=100;observer(m)
check(m.starts==6,'Kitchen wall change did not rebuild')
# Rotated/mirrored house placement and upper floor are taken from saved data.
m.doc['settings']={'kitchen_pose'=>{'z'=>144}}
m.doc['cabinets'][0].merge!('house_placement'=>{'x'=>200,'y'=>300,'angle'=>90,'handedness'=>-1},'flip_x'=>true)
r=b.opening_regions(m).first
check(r[0]<200 && r[3]>200 && r[1]<300 && r[4]>330 && r[2]==132,'Placement influence region incorrect')
b.send(:remove_const,:USE_LOCAL_OPENING_SIGNATURE);b.const_set(:USE_LOCAL_OPENING_SIGNATURE,false)
check(signature(m)==b.opening_signature(m,local:false),'Kill switch does not restore legacy signature')
puts 'PASS: production observer skips remote walls/windows/native openings, migrates old documents without rebuilding, rebuilds nearby edits/additions/deletions, excludes other floors, supports rotated mirrored placement and kill switch.'
