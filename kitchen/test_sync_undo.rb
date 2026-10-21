require 'json'
module Sketchup; class Group; end; end
module KitchenLab
  DICT='KitchenLab'
  class DocumentUndoObserver; end
  module Document
    def self.read(raw); JSON.parse(raw); end
  end
  module Backsplash
    def self.openings_changed?(model); true; end
  end
  def self.unit_groups; []; end
  def self.cabinets; []; end
  def self.write_document!(data,settings); @model.set_attribute(DICT,'partial_kitchen',true); end
  def self.worktops!(previous:)
    raise 'Unable to trim intersecting crown solids' if @fail
  end
  def self.publish; @published=true; end
end
load ARGV.fetch(0,File.join(__dir__,'kitchen_units.rb'))
# Model double represents SketchUp's transparent rollback semantics. Exercise
# the production observer and sync path, including a partially written document.
class UndoModel
  attr_reader :attrs,:history,:starts
  def initialize
    @attrs={['KitchenLab','document']=>JSON.generate({'cabinets'=>[],'settings'=>{}})}
    @history=[];@starts=[]
  end
  def active_path; nil; end
  def entities; []; end
  def get_attribute(dict,key,default=nil); @attrs.fetch([dict,key],default); end
  def set_attribute(dict,key,value); @attrs[[dict,key]]=value; end
  def start_operation(name,disable_ui=true,next_transparent=false,transparent=false)
    @starts<<[name,transparent];@before=Marshal.load(Marshal.dump(@attrs));@transparent=transparent
  end
  def commit_operation
    @history<<@before unless @transparent;@before=nil
  end
  def abort_operation
    @attrs=@before;@attrs=@history.pop if @transparent && !@history.empty?;@before=nil
  end
end
def check(value,message); raise message unless value; end
def run_case(fail:,isolated:)
  KitchenLab.send(:remove_const,:USE_ISOLATED_KITCHEN_SYNC)
  KitchenLab.const_set(:USE_ISOLATED_KITCHEN_SYNC,isolated)
  model=UndoModel.new
  model.start_operation('Split Wall');model.set_attribute('InteriorPro','wall_parts',['A','B']);model.commit_operation
  KitchenLab.instance_variable_set(:@model,model)
  KitchenLab.instance_variable_set(:@fail,fail)
  KitchenLab.instance_variable_set(:@published,false)
  KitchenLab::DocumentUndoObserver.new.onTransactionCommit(model)
  check(KitchenLab.instance_variable_get(:@unit_syncing)==false,'Sync reentrancy guard stuck')
  model
end
m=run_case(fail:true,isolated:true)
check(m.get_attribute('InteriorPro','wall_parts')==['A','B'],'Failed sync undid the wall split')
check(!m.get_attribute('KitchenLab','partial_kitchen'),'Failed sync kept partial kitchen changes')
check(m.history.length==1,'Failed sync changed preceding undo history')
check(!KitchenLab.instance_variable_get(:@published),'Failed sync published partial state')
m=run_case(fail:false,isolated:true)
check(m.get_attribute('InteriorPro','wall_parts')==['A','B'],'Successful sync lost wall split')
check(m.get_attribute('KitchenLab','partial_kitchen'),'Successful sync not committed')
check(m.history.length==2,'Successful sync must have separate undo entry')
m=run_case(fail:true,isolated:false)
check(m.get_attribute('InteriorPro','wall_parts').nil?,'Control did not reproduce old transparent rollback bug')
puts 'PASS: production observer preserves previous operation on failure, rolls back partial kitchen changes, commits success separately; legacy control reproduces bug.'
