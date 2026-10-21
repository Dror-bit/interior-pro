# Run with Ruby outside SketchUp. Exercises production update_door against an
# importer which commits the active operation, as a first-use SKP import can.
module Sketchup
 class << self;attr_accessor :active_model;end
end
module UI
 def self.messagebox(text);raise text;end
end
module InteriorPro
 class DoorTool
  DOOR_DEBUG_LOG=false
  attr_accessor :handle_style,:category
  def handle_enabled?;!handle_style.to_s.empty? && handle_style!='none';end
  def handle_kind;category=='exterior' ? 'front' : 'interior';end
 end
 module DoorLibraryDialog
  def self.apply_to_tool(tool,settings);tool.handle_style=settings['handle_style'];tool.category=settings['door_category'];end
 end
 module DoorHandles
  class << self;attr_accessor :fail_import;end
  def self.assets_dir(_kind);__dir__;end
  def self.definition_for(model,name,kind)
   key="InteriorPro_Handle_#{kind}_#{name}"
   return model.definitions[key] if model.definitions[key]
   model.events<<:import
   raise 'import failure' if fail_import
   model.commit_operation # the native import closes the caller's operation
   model.start_operation('Native SKP import',true)
   model.definitions[key]=Struct.new(:valid?).new(true)
   model.commit_operation
   model.definitions[key]
  end
 end
end
load File.expand_path('../door_manager.rb',__dir__)
class TestDoor
 attr_accessor :settings,:body
 def initialize;@settings={'width'=>32.0,'height'=>80.0,'floor_offset'=>0.0,'handle_style'=>'none','door_category'=>'interior','leaf_style'=>'Flush'};@body='original';end
 def valid?;true;end
 def get_attribute(*);nil;end
 def snapshot;[settings.dup,body];end
 def restore(s);@settings,@body=s;end
end
class TestModel
 attr_accessor :door,:definitions,:events
 def initialize;@door=TestDoor.new;@definitions={};@events=[];@stack=[];end
 def start_operation(*args);@events<<[:start,*args];@snapshot=door.snapshot;true;end
 def commit_operation;@stack<<@snapshot if @snapshot;@snapshot=nil;true;end
 def abort_operation;door.restore(@snapshot) if @snapshot;@snapshot=nil;@events<<:abort;end
 def undo;door.restore(@stack.pop);end
end
module InteriorPro::DoorManager
 def self.door_entity?(_);true;end
 def self.params_from_door(door);door.settings.dup;end
 def self.settings_from_door(door);door.settings.dup;end
 def self.find_wall_by_id(*);Object.new;end
 def self.wall_geometry(*);{floor_z:0,ceiling_z:100};end
 def self.opening_context(*);{width:32.0,height:80.0,floor_offset:0.0,t:10};end
 def self.validate_position(*);true;end
 def self.door_regen!(door,settings:)
  door.settings=settings.dup
  tool=InteriorPro::DoorTool.new
  InteriorPro::DoorLibraryDialog.apply_to_tool(tool,settings)
  InteriorPro::DoorHandles.definition_for(Sketchup.active_model,tool.handle_style,tool.send(:handle_kind)) if tool.send(:handle_enabled?)
  door.body='new geometry'
  raise 'Fixture regen failure' if @fail_regen
  true
 end
end
def check(value,message);raise message unless value;end
# File.file? is replaced only for this fixture's virtual handle asset.
class << File
 alias_method :door_test_file?,:file?
 def file?(path);path.end_with?('/fixture.skp') || door_test_file?(path);end
end
manager=InteriorPro::DoorManager
%w[interior exterior].each do |kind|
 model=Sketchup.active_model=TestModel.new
 original=model.door.snapshot
 settings=model.door.settings.merge('handle_style'=>'fixture','leaf_style'=>'2 Panel Shaker','door_category'=>kind)
 check(manager.update_door(model.door,settings),'Edit rejected')
 check(model.events.index(:import)<model.events.index([:start,'Edit Door',true]),'SKP import occurred inside door edit')
 check(model.events.grep(Array).all?{|e|e.length==3},'An operation was made transparent')
 model.undo
 check(model.door.snapshot==original,'One Undo did not restore the complete door')
 model.events.clear
 check(manager.update_door(model.door,settings),'Cached edit rejected')
 check(model.events==[[:start,'Edit Door',true]],'Cached handle added an operation')
 model.undo;check(model.door.snapshot==original,'Cached handle Undo failed')
end
model=Sketchup.active_model=TestModel.new
original=model.door.snapshot
InteriorPro::DoorHandles.fail_import=true
begin
 manager.update_door(model.door,model.door.settings.merge('handle_style'=>'fixture'))
 raise 'Import failure was ignored'
rescue RuntimeError=>e
 raise unless e.message=='import failure'
end
check(model.door.snapshot==original && model.events.include?(:abort),'Import failure changed the door')
InteriorPro::DoorHandles.fail_import=false
manager.send(:remove_const,:USE_PRELOAD_DOOR_HANDLES);manager.const_set(:USE_PRELOAD_DOOR_HANDLES,false)
model=Sketchup.active_model=TestModel.new
manager.update_door(model.door,model.door.settings.merge('handle_style'=>'fixture'))
check(model.events.first==[:start,'Edit Door',true],'Kill switch did not restore old path')
puts 'PASS cold/cached interior and front handles: one Undo, normal operations, import failure, kill switch'

manager.send(:remove_const,:USE_PRELOAD_DOOR_HANDLES);manager.const_set(:USE_PRELOAD_DOOR_HANDLES,true)
module UI
 class << self;attr_accessor :pending;end
 self.pending=[]
 def self.start_timer(_delay,_repeat,&work);pending<<work;pending.length;end
end
model=Sketchup.active_model=TestModel.new
original=model.door.snapshot;done=nil
manager.update_door(model.door,model.door.settings.merge('handle_style'=>'fixture')){|ok|done=ok}
check(done.nil? && model.door.snapshot==original,'Door changed before import observers finished')
UI.pending.shift.call
check(done==true && model.door.body=='new geometry','Deferred edit did not complete')
model.undo;check(model.door.snapshot==original,'Deferred edit required multiple Undos')
model=Sketchup.active_model=TestModel.new;done=nil
manager.update_door(model.door,model.door.settings.merge('handle_style'=>'fixture')){|ok|done=ok}
model.door.settings['leaf_style']='User changed this while waiting'
UI.pending.shift.call
check(done==false && model.door.body=='original','A stale queued edit overwrote a newer change')
module InteriorPro::DoorLibrary
 def self.normalize_category(c);c || 'interior';end
end
module InteriorPro::MoldingManager
 class << self;attr_accessor :refreshes;end
 self.refreshes=0
 def self.refresh!;self.refreshes+=1;end
end
module InteriorPro::FloorManager
 class << self;attr_accessor :refreshes;end
 self.refreshes=0
 def self.refresh_door_patches!;self.refreshes+=1;end
end
load File.expand_path('../door_library_dialog.rb',__dir__)
# Keep this fixture's light tool adapter; the callback under test is production.
module InteriorPro::DoorLibraryDialog
 def self.apply_to_tool(tool,settings);tool.handle_style=settings['handle_style'];tool.category=settings['door_category'];end
end
require 'json'
class TestDialog
 attr_reader :callbacks,:closed
 def initialize;@callbacks={};@closed=false;end
 def add_action_callback(name,&work);callbacks[name]=work;end
 def close;@closed=true;end
end
model=Sketchup.active_model=TestModel.new;original=model.door.snapshot
dialog=TestDialog.new
InteriorPro::DoorLibraryDialog.wire_edit_dialog_callbacks(dialog,model.door)
dialog.callbacks['apply_edit'].call(nil,JSON.generate(model.door.settings.merge('handle_style'=>'fixture','leaf_style'=>'2 Panel Shaker')))
check(!dialog.closed,'Dialog closed before deferred edit finished')
UI.pending.shift.call
check(dialog.closed,'Dialog did not close after edit')
check(InteriorPro::MoldingManager.refreshes==0 && InteriorPro::FloorManager.refreshes==0,'Body-only dialog edit rebuilt molding/floors')
model.undo;check(model.door.snapshot==original,'Dialog edit required multiple Undos')
puts 'PASS deferred completion, stale-edit guard, actual dialog callback, no unrelated floor/molding rebuild'

module UI
 class << self;attr_accessor :messages;end
 self.messages=[]
 def self.messagebox(text);messages<<text;nil;end
end
model=Sketchup.active_model=TestModel.new
model.definitions['InteriorPro_Handle_interior_fixture']=Struct.new(:valid?).new(true)
original=model.door.snapshot
model.start_operation('Previous user action',true);model.door.body='user prior change';model.commit_operation
prior=model.door.snapshot
manager.instance_variable_set(:@fail_regen,true)
check(manager.update_door(model.door,model.door.settings.merge('handle_style'=>'fixture'))==false,'Failed edit reported success')
manager.instance_variable_set(:@fail_regen,false)
check(model.door.snapshot==prior,'Failed edit rolled back the preceding user action')
model.undo
check(model.door.snapshot==original,'The preceding user action no longer had its own Undo')
puts 'PASS failed door regeneration rolls back only its own edit and preserves preceding user Undo'
