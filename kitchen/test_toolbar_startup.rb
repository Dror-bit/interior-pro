module UI
  class Command
    attr_accessor :tooltip, :status_bar_text, :small_icon, :large_icon
    def initialize(name, &block); @action=block; end
    def invoke; @action.call; end
  end
  class Toolbar
    attr_reader :items, :restores
    def initialize(name); @items=[]; @restores=0; end
    def add_item(item); @items << item; end
    def restore; @restores+=1; end
    def show; end
  end
end
module InteriorPro
  module KitchenPlan
    def self.bind_active_model!; @bound=true; end
  end
end
module KitchenLab
  ROOT=__dir__
  def self.show
    raise 'Command failed to bind current model' unless InteriorPro::KitchenPlan.instance_variable_get(:@bound)
    @opened=true
  end
end
source=File.read(File.join(__dir__,'kitchen_lab.rb'))
RubyVM::InstructionSequence.compile(source)
RubyVM::InstructionSequence.compile(File.read(File.join(__dir__,'kitchen_bootstrap.rb')))
method_source=source[/  def self\.install_toolbar.*?(?=  def self\.show)/m]
raise 'Missing toolbar method' unless method_source
KitchenLab.module_eval(method_source)
2.times { KitchenLab.install_toolbar(restore: true) }
toolbar=KitchenLab.instance_variable_get(:@toolbar)
raise 'Duplicated toolbar button' unless toolbar.items.length==1
raise 'Did not restore toolbar' unless toolbar.restores==2
raise 'Startup bound a model' if InteriorPro::KitchenPlan.instance_variable_get(:@bound)
raise 'Startup opened editor' if KitchenLab.instance_variable_get(:@opened)
toolbar.items.first.invoke
raise 'Click did not open editor' unless KitchenLab.instance_variable_get(:@opened)
puts 'PASS: startup restores one toolbar without model binding; click binds current model then opens editor.'
