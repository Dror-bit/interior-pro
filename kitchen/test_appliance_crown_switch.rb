require 'json'
load File.join(__dir__,'kitchen_crown.rb')
module KitchenLab
  class << self
    attr_accessor :audit_document, :audit_built
    def document; audit_document; end
    def crown_ceiling_for(_); nil; end
    def write_document!(data,settings); self.audit_document={'cabinets'=>data,'settings'=>settings}; end
    def cabinets; []; end
    def build(d); audit_built << d['id']; end
  end
end
%w[fridge wall_oven microwave].each do |kind|
  device={'id'=>'device','kind'=>kind}
  left={'id'=>'left','kind'=>'filler','surround_for'=>'device','surround_part'=>'left','z'=>0,'height'=>96,'width'=>0.75,'depth'=>24}
  right=left.merge('id'=>'right','surround_part'=>'right')
  upper={'id'=>'upper','kind'=>'wall','surround_for'=>'device','surround_part'=>'upper','z'=>70,'height'=>20,'width'=>30,'depth'=>24}
  KitchenLab.audit_document={'cabinets'=>[device,left,right,upper], 'settings'=>{}}
  %w[flat crown none flat crown flat].each do |profile|
    KitchenLab.audit_document['settings']={'crown_profile'=>profile,'crown_match_house'=>false,'crown_height'=>6}
    KitchenLab.audit_built=[]
    KitchenLab.fit_cabinet_crowns!(profile=='none' ? 0 : 6)
    expected=profile=='flat' ? 96 : 90
    raise "#{kind} #{profile} panel failed" unless [left,right].all? { |p|p['height']==expected }
    raise 'Upper cabinet changed during profile switch' unless upper['height']==20
    carriers=KitchenLab::CrownJoints.carriers(KitchenLab.audit_document['cabinets'],KitchenLab.audit_document['settings'])
    raise 'Disabled molding left a carrier' if profile=='none' && !carriers.empty?
    if profile=='flat'
      raise 'Flat front must fit between panels' unless carriers.length==1 && carriers.first['crown_front_only'] && carriers.first['width']==30
    elsif profile=='crown'
      raise 'Decorative crown must wrap outside panels' unless carriers.length==1 && !carriers.first['crown_front_only'] && carriers.first['width']==31.5
    end
  end
end
puts 'PASS repeated flat/decorative/off transitions for fridge, oven, coffee/microwave surrounds'
