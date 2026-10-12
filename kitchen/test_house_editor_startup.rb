module Sketchup
  class ModelObserver; end
end
require_relative '../plan_editor'
def check(value,message);raise message unless value;end
check(InteriorProKitchenStartup.instance_variable_get(:@installed),'House editor did not install kitchen')
check(KitchenLab::ROOT==File.expand_path(__dir__),'Kitchen loaded from outside this checkout')
check(KitchenLab.instance_variable_get(:@model).nil?,'Startup must not bind or mutate a model')
html=InteriorPro::PlanEditor.build_html
check(html.scan('if(window.KP)window.KP.draw();').length==1,'Kitchen draw hook missing or duplicated')
check(html.include?('sketchup.editor_ready()'),'Original editor ready callback missing')
load File.expand_path('../plan_editor.rb',__dir__)
check(InteriorPro::PlanEditor.singleton_class.ancestors.count(InteriorPro::KitchenPlan::EditorPreview)==1,'Reload duplicated hook')
check(InteriorPro::PlanEditor.build_html.scan('if(window.KP)window.KP.draw();').length==1,'Reload duplicated drawing')
puts 'PASS: actual house editor loads its bundled kitchen, preserves editor-ready and installs one draw hook across reloads without model writes.'
