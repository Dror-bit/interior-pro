require 'json'
module KitchenSheetBodyCheck
  def self.run
    et=InteriorPro::ElevationTool;m=Sketchup.active_model
    room=et.kitchen_room(m);poly=et.room_poly(room);kit=et.kitchen_tops(m)
    checked=[]
    et.sides(poly).each do |side|
      fr=et.side_frame(side,poly.first.z)
      kit.each do |e,k,xf|
        c=et.kitchen_cab(e);next unless c
        d=JSON.parse(c.get_attribute('KitchenLab','data').to_s)
        next unless %w[tall corner_upper sink].include?(d['kind'])
        next unless et.kitchen_on(side,e,xf,fr)
        item=et.kitchen_items(side,kit,poly.first.z).find{|i|i[:name]==e.name && (i[:w]-d['width'].to_f).abs<0.01}
        raise 'Missing cabinet' unless item
        raise 'Accessory included in body height' unless (item[:z1]-item[:z0]-d['height'].to_f).abs<0.001
        raise 'Wrong upper/tall top' if %w[tall corner_upper].include?(d['kind']) && (item[:z1]-90).abs>0.001
        checked<<{kind:d['kind'],bottom:item[:z0],top:item[:z1],wall:side.name}
      end
    end
    raise 'Missing coverage' unless %w[tall corner_upper sink].all?{|k|checked.any?{|r|r[:kind]==k}}
    raise 'Invalid data fallback' unless et.kitchen_body_heights(nil,nil,nil,[4,9])==[4,9]
    checked
  end
end
