# Kitchen adapter for Interior Pro's material cards. No host callbacks are replaced.
require 'json'
require 'digest'
module KitchenLab
  module CountertopMaterials
    def self.validate(value)
      return nil if value.nil?
      raise 'Invalid countertop material' unless value.is_a?(Hash) && value['card'].is_a?(Hash) && value['key'].to_s.match?(/\A[0-9a-f]{64}\z/)
      unless Digest::SHA256.hexdigest(JSON.generate(value['card']))==value['key']
        # JavaScript serializes 24.0 as 24. Recover only an unchanged saved snapshot.
        saved=KitchenLab.settings
        candidates=[saved['countertop_material'],saved['island_countertop_material'],saved.dig('backsplash','material')]
        original=candidates.compact.find { |v| v['key']==value['key'] && v['card']==value['card'] && Digest::SHA256.hexdigest(JSON.generate(v['card']))==v['key'] }
        raise 'Countertop material snapshot changed' unless original
        return original
      end
      value
    end
    def self.snapshot(card)
      copy=JSON.parse(JSON.generate(card))
      path=InteriorPro::MaterialLibrary.texture_path(card)
      raise 'The material texture is missing' if !card['texture_file'].to_s.empty? && !path
      copy['texture_file']=path if path
      {'card'=>copy,'key'=>Digest::SHA256.hexdigest(JSON.generate(copy))}
    end
    def self.resolve(model, value)
      validate(value)
      name='Kitchen countertop / '+value['key']
      return model.materials[name] if model.materials[name]
      card=value['card'];mat=model.materials.add(name)
      c=card['color'];mat.color=Sketchup::Color.new(*c.first(3)) if c.is_a?(Array) && c.size>=3
      mat.alpha=card['alpha'] if card['alpha']
      path=card['texture_file'].to_s
      unless path.empty?
        raise 'The saved countertop texture is unavailable' unless File.file?(path)
        mat.texture=path
        w=card['texture_width_inches'];h=card['texture_height_inches']
        mat.texture.size=[w,h] if w && h
      end
      mat.set_attribute('KitchenLab','material_card',JSON.generate(card))
      mat
    end
    def self.for_cabinet(d)
      s=KitchenLab.settings
      value=d['wall']=='I' && s['island_countertop_material'] ? s['island_countertop_material'] : s['countertop_material']
      value ? resolve(Sketchup.active_model,value) : KitchenLab.material('Worktop','#F2F0E9')
    end
    def self.countertop_cards(cards)
      cards.select { |c| %w[countertop countertops].include?(c['path'].to_s.tr('\\','/').split('/').first.to_s.downcase) }
    end
    def self.show_molding
      KitchenLab.guard!
      model=Sketchup.active_model
      @molding_dialog.close if @molding_dialog && @molding_dialog.visible?
      dlg=UI::HtmlDialog.new(dialog_title:'Kitchen molding',preferences_key:'KitchenLab.MoldingSettings',width:820,height:720,resizable:true)
      @molding_dialog=dlg
      dlg.add_action_callback('ready') do
        data={settings:KitchenLab.settings,molding_catalog:KitchenLab::MoldingProfiles.catalog,house_molding:KitchenLab::MoldingProfiles.house_selection}
        dlg.execute_script("receiveKitchen(#{JSON.generate(data)});window.openKitchenMolding();")
      end
      dlg.add_action_callback('surface_update') do |_,json|
        begin
          raise 'Return to the kitchen model' unless Sketchup.active_model.equal?(model)
          KitchenLab.guard!
          raw=JSON.parse(json)
          raise 'Invalid molding settings' unless raw.is_a?(Hash) && (raw.keys-%w[crown_match_house crown_profile crown_height crown_color]).empty?
          KitchenLab.update_settings(raw)
          dlg.close
        rescue StandardError=>e
          dlg.execute_script("document.querySelector('#kitchenMoldingGallery [data-error]').textContent=#{JSON.generate(e.message)}")
        end
      end
      dlg.add_action_callback('close_molding') { dlg.close }
      dlg.set_on_closed { @molding_dialog=nil if @molding_dialog.equal?(dlg) }
      html=<<~HTML
        <!doctype html><meta charset="utf-8"><style>[hidden]{display:none!important}body{font:14px Segoe UI,sans-serif;background:#f7f8f4}button,input,select{font:inherit;padding:8px}label{display:block;margin:12px 0}dialog::backdrop{background:#f7f8f4}</style>
        <div hidden><div id="cabinetControls"></div><div><select id="crown_profile"></select><input id="crown_depth"></div></div>
        <script>const $=id=>document.getElementById(id);let kitchenSettings={};window.receiveKitchen=data=>{kitchenSettings=data.settings||{}};function sendCommands(commands){sketchup.surface_update(JSON.stringify(commands[0].payload))}</script>
        <script>#{File.read(File.join(KitchenLab::ROOT,'molding_gallery.js'))}</script>
        <script>document.querySelector('#kitchenMoldingGallery [data-close]').onclick=()=>sketchup.close_molding();document.getElementById('kitchenMoldingGallery').addEventListener('cancel',()=>sketchup.close_molding());window.addEventListener('DOMContentLoaded',()=>sketchup.ready());</script>
      HTML
      dlg.set_html(html);dlg.show
    end

    def self.show_settings(focus='countertop')
      return show_molding if focus=='molding'
      KitchenLab.guard!
      model=Sketchup.active_model
      @settings_dialog.close if @settings_dialog && @settings_dialog.visible?
      dlg=UI::HtmlDialog.new(dialog_title: focus=='backsplash' ? 'Kitchen backsplash' : 'Kitchen countertops',preferences_key:'KitchenLab.SurfaceSettings',width:540,height:760,resizable:true)
      @settings_dialog=dlg
      check=proc { raise 'Return to the kitchen model' unless Sketchup.active_model.equal?(model); KitchenLab.guard! }
      refresh=proc { dlg.execute_script("receiveKitchen(#{JSON.generate(KitchenLab.settings)});fill();") }
      error=proc { |e| dlg.execute_script("document.getElementById('error').textContent=#{JSON.generate(e.message)}") }
      dlg.add_action_callback('ready') { refresh.call; dlg.execute_script("document.getElementById('backsplashEditor').scrollIntoView()") if focus=='backsplash' }
      dlg.add_action_callback('surface_update') do |_,json|
        begin
          check.call;raw=JSON.parse(json)
          raise 'Invalid surface settings' unless raw.is_a?(Hash) && (raw.keys-%w[backsplash island_countertop_material countertop_thickness]).empty?
          KitchenLab.update_settings(raw);refresh.call
        rescue StandardError=>e;error.call(e);end
      end
      dlg.add_action_callback('countertop_materials') { |_,scope| begin;check.call;show(nil,nil,scope=='island' ? 'island' : 'kitchen');rescue StandardError=>e;error.call(e);end }
      dlg.add_action_callback('backsplash_materials') { |_,id,json| begin;check.call;show('kitchen',JSON.parse(json));rescue StandardError=>e;error.call(e);end }
      dlg.set_on_closed { @settings_dialog=nil if @settings_dialog.equal?(dlg) }
      html=File.read(File.join(KitchenLab::ROOT,'surface_settings.html'))
      html.sub!('Kitchen surfaces',focus=='backsplash' ? 'Kitchen backsplash' : 'Kitchen countertops')
      scripts=focus=='backsplash' ? ['backsplash_editor.js'] : ['countertop_editor.js']
      scripts.each { |name| html.sub!("<!-- #{name} -->",'<script>'+File.read(File.join(KitchenLab::ROOT,name))+'</script>') }
      dlg.set_html(html);dlg.show
    end
    def self.show(cabinet_id=nil, backsplash=nil, scope='kitchen')
      KitchenLab.guard!
      raise 'Interior Pro material library is unavailable' unless defined?(InteriorPro::MaterialLibraryDialog)
      backsplash=Backsplash.validate(backsplash) if cabinet_id
      model=Sketchup.active_model
      @dialog.close if @dialog && @dialog.visible?
      dlg=UI::HtmlDialog.new(dialog_title: cabinet_id ? 'Backsplash · Interior Pro materials' : 'Countertop · Interior Pro materials',preferences_key:'KitchenLab.CountertopMaterials',width:760,height:600,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
      @dialog=dlg
      cards=InteriorPro::MaterialLibrary.cards
      cards=countertop_cards(cards) unless cabinet_id
      data=cards.map { |c| InteriorPro::MaterialLibraryDialog.card_for_js(c) }
      dlg.set_html(File.read(File.join(KitchenLab::ROOT,'countertop_materials.html')))
      dlg.add_action_callback('ready') { dlg.execute_script("render(#{JSON.generate(data)},#{JSON.generate(cabinet_id ? "Backsplash tile materials" : "Countertop materials")},#{JSON.generate(cabinet_id ? "Apply to the entire kitchen backsplash" : (scope=='island' ? "Apply to island countertops only" : "Apply to all kitchen countertops"))})") }
      dlg.add_action_callback('choose') do |_,id|
        begin
          raise 'Return to the kitchen model before choosing a material' unless Sketchup.active_model.equal?(model)
          KitchenLab.guard!
          card=cards.find { |c| c['id']==id };raise 'Material not found' unless card
          value=snapshot(card)
          if cabinet_id
            KitchenLab.update_settings({'backsplash'=>Backsplash.with_material(backsplash,value)})
          else
            KitchenLab.update_settings({(scope=='island' ? 'island_countertop_material' : 'countertop_material')=>value})
          end
          mat=model.materials['Kitchen countertop / '+value['key']]
          if mat && card['vray']
            begin;InteriorPro::MaterialLibrary.apply_vray_numbers!(mat,card['vray']);rescue StandardError=>e;puts '[Kitchen material] V-Ray: '+e.message;end
          end
          @settings_dialog.execute_script("receiveKitchen(#{JSON.generate(KitchenLab.settings)});fill();") if @settings_dialog && @settings_dialog.visible?
          dlg.close
        rescue StandardError=>e
          dlg.execute_script("document.getElementById('error').textContent=#{JSON.generate(e.message)}")
        end
      end
      dlg.set_on_closed { @dialog=nil if @dialog.equal?(dlg) }
      dlg.show
    end
  end
end
