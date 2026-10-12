module Sketchup
  class ModelObserver;end
  def self.active_model;@model ||= Model.new;end
  class Model
    def entities;[];end
    def get_attribute(*);nil;end
  end
end
require_relative 'kitchen_lab'
require_relative 'kitchen_plan'
def check(value,message);raise message unless value;end
class ContractDialog
  attr_reader :callbacks,:scripts,:registrations
  def initialize;@callbacks={};@scripts=[];@registrations=Hash.new(0);end
  def add_action_callback(name,&block);@callbacks[name]=block;@registrations[name]+=1;end
  def execute_script(code);@scripts<<code;end
end
class ContractHost
  attr_accessor :html
  attr_reader :dialog,:built,:refreshes
  def initialize;@html='drawRooms();';@refreshes=0;end
  def show
    @dialog=ContractDialog.new
    @dialog.add_action_callback('save_draft'){|_,json|[:original_save,json]}
    @dialog.add_action_callback('undo_model'){[:original_undo]}
    @built=build_html
    :host_opened
  end
  def build_html;@html;end
  def push_walls(dlg);@refreshes+=1;:host_refreshed;end
  prepend InteriorPro::KitchenPlan::EditorPreview
end
plan=InteriorPro::KitchenPlan
plan.define_singleton_method(:bind_active_model!){raise 'Open cabinet draft' if @test_bind_failure}
plan.define_singleton_method(:walls_payload){[]}
host=ContractHost.new
check(host.show==:host_opened,'Host show changed')
check(host.dialog.callbacks['save_draft'].call(nil,'draft')==[:original_save,'draft'],'Draft callback replaced')
check(host.dialog.registrations['save_draft']==1,'Draft registered twice')
check(host.dialog.callbacks['undo_model'].call==[:original_undo],'Undo callback replaced')
check(!host.dialog.callbacks.key?('kitchen_undo'),'Second Undo route')
check(host.built.include?('window.KP.draw()'),'No drawing hook')
host.push_walls(host.dialog)
first=host.dialog.scripts.length
check(first==2,'Expected one script bundle and one payload')
host.push_walls(host.dialog)
check(host.dialog.scripts.length==first+1,'Scripts reinjected on refresh')
check(host.dialog.scripts.last.start_with?('if(window.KP)window.KP.load('),'Refresh sent more than payload')
old=host.dialog;host.show;host.push_walls(host.dialog)
check(host.dialog!=old&&host.dialog.scripts.length==2,'New window did not receive its own bundle')
['no marker','drawRooms(); drawRooms();'].each do |html|
 host.html=html
 check(host.show==:host_opened && host.built==html,'Marker mismatch blocked/modified host')
 host.push_walls(host.dialog)
 check(host.dialog.scripts.empty?,'Disabled kitchen injected scripts')
 check(!host.dialog.callbacks.key?('kitchen_open_catalog'),'Disabled kitchen registered editing callbacks')
end
host.html='drawRooms();';plan.instance_variable_set(:@test_bind_failure,true)
check(host.show==:host_opened&&host.built==host.html,'Bind failure blocked host')
host.push_walls(host.dialog)
check(host.dialog.scripts.empty?,'Bind failure injected scripts')
plan.instance_variable_set(:@test_bind_failure,false)
check(host.show==:host_opened&&host.built.include?('window.KP.draw()'),'Next window did not recover')
puts 'PASS: fail-open host, original draft/Undo callbacks, disabled editing, per-window script loading, payload-only refresh and recovery.'
