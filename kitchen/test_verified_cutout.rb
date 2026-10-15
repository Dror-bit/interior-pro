module Sketchup;class ModelObserver;end;end
require_relative 'kitchen_lab'
def cutout_assert(v,m);raise m unless v;end
settings=KitchenLab::Document.create({'shaker_width'=>2.25,'shaker_inset'=>0.25},[])['settings']
options=KitchenLab::SinkCatalog.options('kohler-k-5287').merge('id'=>'test-template')
cab=KitchenLab.validate(options,settings)
hole=KitchenLab::Sink.cutout(cab)
cutout_assert(hole && (hole[2]-hole[0]-13.25).abs<0.00001 && (hole[3]-hole[1]-13.25).abs<0.00001 && hole[4]==0.5,'Manufacturer dimensions not preserved')
legacy=Marshal.load(Marshal.dump(cab));legacy['sink']['automatic_cutout_available']=false;legacy['sink']['catalog_snapshot']['automatic_cutout_available']=false;legacy['sink']['catalog_snapshot']['cutout']=nil
cutout_assert(KitchenLab::Sink.cutout(KitchenLab.validate(legacy,settings)).nil?,'Existing saved sink changed silently')
forged=Marshal.load(Marshal.dump(cab));forged['sink']['catalog_snapshot']['cutout_radius']=0
cutout_assert(KitchenLab::Sink.cutout(KitchenLab.validate(forged,settings)).nil?,'Unverified contour accepted')
pending=KitchenLab.validate(KitchenLab::SinkCatalog.options('kohler-k-33152').merge('id'=>'test-pending'),settings)
pending['sink']['automatic_cutout_available']=true
cutout_assert(KitchenLab::Sink.cutout(pending).nil?,'K-33152 protection bypassed')
puts 'PASS: verified template dimensions/radius, saved snapshot stability, forged contour rejection and K-33152 prohibition'


