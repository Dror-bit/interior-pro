require 'json'
module Sketchup; class ModelObserver; end; end
module KitchenLab
  DICT='KitchenLab'
  module Document
    class << self;attr_accessor :reads;end
    self.reads=0
    def self.read(raw);self.reads+=1;JSON.parse(raw);end
  end
  def self.guard!;end
end
load File.join(__dir__,'kitchen_store.rb')
Model=Struct.new(:raw) do
  def get_attribute(*);raw;end
end
m=Model.new(JSON.generate({'revision'=>0,'cabinets'=>[]}))
KitchenLab.instance_variable_set(:@model,m)
start=Process.clock_gettime(Process::CLOCK_MONOTONIC)
KitchenLab.with_document_snapshot do
  1000.times{KitchenLab.document}
  raise 'More than one read per unchanged operation' unless KitchenLab::Document.reads==1
  m.raw=JSON.generate({'revision'=>1,'cabinets'=>[]})
  raise 'Write returned stale snapshot' unless KitchenLab.document['revision']==1
  KitchenLab.with_document_snapshot{KitchenLab.document}
  raise 'Nested operation lost snapshot' unless KitchenLab::Document.reads==2
end
raise 'Memo hot path exceeded 0.5 seconds' unless Process.clock_gettime(Process::CLOCK_MONOTONIC)-start<0.5
raise 'Snapshot leaked outside operation' if KitchenLab.instance_variable_get(:@document_snapshot)
begin
  KitchenLab.with_document_snapshot{KitchenLab.document;raise 'abort'}
rescue RuntimeError
end
raise 'Abort leaked snapshot' if KitchenLab.instance_variable_get(:@document_snapshot)
KitchenLab.send(:remove_const,:USE_OPERATION_DOCUMENT_MEMO)
KitchenLab.const_set(:USE_OPERATION_DOCUMENT_MEMO,false)
n=KitchenLab::Document.reads
KitchenLab.with_document_snapshot{3.times{KitchenLab.document}}
raise 'Kill switch ignored' unless KitchenLab::Document.reads==n+3
puts 'PASS scoped document memo: one read, write invalidation, nesting, abort cleanup, timing and kill switch'
