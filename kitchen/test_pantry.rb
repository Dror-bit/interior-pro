require 'json'
module KitchenLab
  module PantryTests
    def self.run
      settings=KitchenLab.settings
      base={'id'=>'pantry-regression','kind'=>'tall','width'=>30.0,'height'=>90.0,'depth'=>24.0,'x'=>0.0,'z'=>0.0,'wall'=>'A','style'=>'shaker','finish'=>'ivory','handle'=>'none','toe_height'=>4.0}
      count=0
      %w[single double lift].product(%w[single double],%w[combo_single combo_double drawers],(1..5).to_a).each do |top,middle,bottom,n|
        d=base.merge('pantry'=>Pantry.defaults(base).merge('top'=>top,'middle'=>middle,'bottom'=>bottom,'drawers'=>n))
        validated=KitchenLab.validate(d,settings);rows=KitchenLab.front_rows(validated)
        raise 'Fronts do not fill pantry' unless (rows.sum{|r|r['height']}+0.125*(rows.length-1)-85.75).abs<0.0001
        restored=Document.read(JSON.generate(Document.create(settings,[validated])))
        raise 'Pantry persistence mismatch' unless restored['cabinets'][0]['pantry']==validated['pantry']
        count+=1
      end
      Pantry.choices.each do |choice|
        a=choice['snapshot'];d=base.merge('pantry'=>Pantry.defaults(base).merge('middle'=>a['category'],'appliance'=>a))
        KitchenLab.validate(d,settings)
        if a['category']=='microwave'
          raise 'Drawer microwave offered' if Pantry.fits?(a.merge('appearance'=>{'door'=>'drawer'}),base,30,'microwave')
          raise 'Over-range microwave offered' if Pantry.fits?(a.merge('appearance'=>{'installation'=>'over_range'}),base,30,'microwave')
        end
        [d.merge('width'=>16.0),d.merge('depth'=>18.0),d.merge('pantry'=>d['pantry'].merge('middle_height'=>8.0))].each do |invalid|
          rejected=false
          begin;KitchenLab.validate(invalid,settings);rescue ArgumentError,RuntimeError;rejected=true;end
          raise 'Incompatible appliance accepted' unless rejected
        end
      end
      custom=base.merge('pantry'=>Pantry.defaults(base).merge('bottom'=>'drawers','drawers'=>4,'drawer_heights'=>[5,6,7,9.625]))
      raise 'Custom drawer heights ignored' unless Pantry.rows(custom).select{|r|r['zone']=='bottom'}.map{|r|r['height']}==[5,6,7,9.625]
      [[5,6,7,8],[5,6],[2,6,7,12.625]].each do |heights|
        rejected=false
        begin;Pantry.rows(custom.merge('pantry'=>custom['pantry'].merge('drawer_heights'=>heights)));rescue RuntimeError;rejected=true;end
        raise 'Invalid custom heights accepted' unless rejected
      end
      engine=Engine.new(validator:->(d,s){KitchenLab.validate(d,s)})
      source=Document.create(settings,[])
      created=engine.plan(source,[{'type'=>'create_tall_cabinet','payload'=>{'id'=>'pantry-engine'}}])['document']
      raise 'New pantry missing sections' unless created['cabinets'][0]['pantry']
      puts "#{count} pantry layouts, saved data, compatibility and creation passed"
      true
    end
  end
end
