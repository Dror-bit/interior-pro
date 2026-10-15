# SketchUp adapter owns persistence, geometry and one Undo per command batch.
# UI and future automation call execute_commands with the same JSON envelope.
module KitchenLab
  def self.command_engine
    Engine.new(validator: ->(data,options) { d=validate(data,options);check_shaker(d,options);d },
      settings_validator: ->(raw,current) { validate_settings(raw,current) }, reference_provider: -> { house_context['items'] })
  end

  def self.execute_commands(request, notify=true)
    guard!
    raise 'Invalid command request' unless request.is_a?(Hash)
    previous=document
    commands=JSON.parse(JSON.generate(request.fetch('commands')))
    # The inspector saves through commands, not the legacy apply callback.
    if commands.length==1 && commands[0]['type']=='update_cabinet'
      payload=commands[0].fetch('payload');changes=payload.fetch('changes')
      old=previous['cabinets'].find { |c| c['id']==payload['id'] }
      if old && changes.key?('width')
        candidate=validate(old.merge(changes),previous['settings'])
        resolved=resolve_width_growth(candidate)
        %w[x offset_y house_placement].each { |key| changes[key]=resolved[key] if resolved[key]!=candidate[key] }
      end
    end
    plan=command_engine.plan(previous,commands,expected_revision:request['expected_revision'])
    unless plan['changed_ids'].empty? && !plan['settings_changed']
      @model.start_operation('Kitchen: commands',true)
      begin
        write_document!(plan['document']['cabinets'],plan['document']['settings'])
        before=previous['cabinets'].to_h { |d| [d['id'],d] }
        after=plan['document']['cabinets'].to_h { |d| [d['id'],d] }
        geometry_settings_changed=previous['settings'].reject { |k,_| %w[island_dimensions island_match_kitchen_style].include?(k) }!=plan['document']['settings'].reject { |k,_| %w[island_dimensions island_match_kitchen_style].include?(k) }
        next_settings=plan['document']['settings']
        settings_keys=previous['settings'].keys|next_settings.keys
        molding_only=plan['settings_changed'] && plan['changed_ids'].empty? && settings_keys.select { |k| previous['settings'][k]!=next_settings[k] }.all? { |k| k.start_with?('crown_') }
        surface_only=plan['settings_changed'] && plan['changed_ids'].empty? && settings_keys.select { |k| previous['settings'][k]!=next_settings[k] }.all? { |k| %w[countertop_material island_countertop_material backsplash].include?(k) || k.start_with?('crown_') }
        changed_ids=(molding_only || surface_only) ? [] : geometry_settings_changed ? (before.keys|after.keys) : plan['changed_ids']
        changed_ids.each do |id|
          d=after[id];old=before[id]
          groups=cabinets.select { |g| g.get_attribute(DICT,'id')==id }
          if !plan['settings_changed'] && d && old && d.reject { |k,_| %w[x z wall].include?(k) }==old.reject { |k,_| %w[x z wall].include?(k) } && groups.length==1
            groups.first.transformation=cabinet_transform(d)
            groups.first.set_attribute(DICT,'data',JSON.generate(d))
          else
            groups.each(&:erase!)
            build(d) if d
          end
        end
        if molding_only
          unpack_units!
          crowns!
          pack_units!
        else
          worktops! if surface_only || !changed_ids.empty?
        end
        @model.commit_operation
      rescue StandardError
        @model.abort_operation;raise
      end
    end
    publish(nil,@dialog,plan['results']) if notify
    plan
  end
end
