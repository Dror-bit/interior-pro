# Native regression: inspect real geometry, restore the document after each case.
module KitchenHoodMoldingCheck
  def self.run
    m=Sketchup.active_model;before=KitchenLab.document
    hood=before['cabinets'].find{|d|d['kind']=='hood'};raise 'No hood to test' unless hood
    parts=before['cabinets'].select{|d|d['surround_for']==hood['id']}
    front=parts.find{|d|d['surround_part']=='hood_front'};side=parts.find{|d|d['surround_part']=='left'}
    counts=lambda do
      owners=[];visit=lambda{|ents|ents.grep(Sketchup::Group).each{|g|owners<<g.get_attribute(KitchenLab::DICT,'owner_id') if g.get_attribute(KitchenLab::DICT,'kind')=='crown';visit.call(g.entities)}};visit.call(m.entities);owners
    end
    original_cabinet_crowns=counts.call.reject{|id|id==hood['id']}.sort
    report=[]
    [[false,'flat',96],[true,'flat',90],[true,'none',90]].each do |enabled,profile,expected|
      command={'type'=>'update_hood_cover','payload'=>{'id'=>hood['id'],'style'=>front['style'],'height'=>front['height'],'depth'=>side['depth'],'molding'=>enabled}}
      plan=KitchenLab.command_engine.plan(before,[command])
      data=plan['document']['cabinets'];owner=data.find{|d|d['id']==hood['id']}
      raise 'Choice not persisted' unless owner['hood_molding']==enabled
      raise 'JSON roundtrip lost option' unless JSON.parse(JSON.generate(owner))['hood_molding']==enabled
      m.start_operation('Kitchen: temporary hood molding test',true)
      begin
        KitchenLab.write_document!(data,before['settings'].merge('crown_profile'=>profile,'crown_match_house'=>false))
        KitchenLab.unpack_units!;KitchenLab.crowns!;KitchenLab.pack_units!
        current=KitchenLab.state['cabinets'].find{|d|d['id']==front['id']}
        raise 'Wrong cover top' unless (current['z']+current['height']-expected).abs<0.001
        crowns=counts.call
        raise 'Wrong hood crown count' unless crowns.count(hood['id'])==(enabled ? 1 : 0)
        raise 'Cabinet molding changed' if profile=='flat' && crowns.reject{|id|id==hood['id']}.sort!=original_cabinet_crowns
        report<<{enabled:enabled,cabinet_profile:profile,cover_top:expected,hood_crowns:crowns.count(hood['id'])}
      ensure
        m.abort_operation
      end
    end
    raise 'Test altered model' unless KitchenLab.document==before
    File.write('C:/Users/rordt/OneDrive/InteriorPro/hood_molding_verified.json',JSON.pretty_generate(report))
    puts JSON.generate(report)
  end
end
KitchenHoodMoldingCheck.run
