# encoding: UTF-8
require 'json'
require 'fileutils'
require 'securerandom'
require 'base64'

module InteriorPro
  # Local workflow UI. No AI/network calls are made by this initial adapter.
  module RenderAgent
    class << self
      def setup!
        return if @command
        @command = UI::Command.new('Room Render Agent') { show }
        @command.tooltip = 'Room Render Agent — review and send renders to Sheet'
        @command.status_bar_text = 'Choose a room and camera, render with V-Ray, review and approve for Sheet'
        icon = File.join(__dir__, 'render_agent.svg')
        @command.small_icon = icon
        @command.large_icon = icon
        @toolbar = UI::Toolbar.new('Interior Pro Render')
        @toolbar.add_item(@command)
        @toolbar.restore
        UI.menu('Extensions').add_item(@command)
      end

      def show
        if @dialog
          @dialog.bring_to_front
          return
        end
        @model = Sketchup.active_model
        @jobs = []
        @dialog = UI::HtmlDialog.new(dialog_title: 'INTERIOR PRO | Room Render Agent',
          preferences_key: 'InteriorPro.RenderAgent', width: 960, height: 760,
          resizable: true, style: UI::HtmlDialog::STYLE_DIALOG)
        %w[ready prepare render import approve reject].each do |action|
          @dialog.add_action_callback("agent_#{action}") do |_, raw|
            begin
              guard_model!
              data = raw.to_s.empty? ? {} : JSON.parse(raw)
              case action
              when 'ready' then push
              when 'prepare' then prepare(data)
              when 'render' then render_job(data)
              when 'import' then import_result(data)
              when 'approve' then approve(data)
              when 'reject' then reject(data)
              end
            rescue StandardError => e
              @dialog.execute_script("report(#{JSON.generate(e.message)}, true)") if @dialog
            end
          end
        end
        @dialog.set_on_closed { @dialog = nil; @jobs = []; @model = nil }
        @dialog.set_file(File.join(__dir__, 'render_agent.html'))
        @dialog.show
      end

      def guard_model!
        raise 'המודל הפעיל השתנה. סגור את החלון ופתח אותו בפרויקט הרצוי.' unless @model.equal?(Sketchup.active_model)
      end

      def rooms
        InteriorPro::RoomManager.rooms_in_model.map do |r|
          { 'id' => r.get_attribute('InteriorPro', 'id').to_s,
            'name' => r.get_attribute('InteriorPro', 'name').to_s,
            'level' => r.get_attribute('InteriorPro', 'level') }
        end
      end

      def push(message = nil)
        payload = { rooms: rooms, scenes: @model.pages.map(&:name),
          project: @model.title, target: InteriorPro::PlanSheetDialog.sets_info(@model)['active'],
          jobs: @jobs.map { |j| j.reject { |k, _| k.start_with?('_') } },
          vray: defined?(VRay::Command) && VRay::Command.respond_to?(:render_production) }
        @dialog.execute_script("receive(#{JSON.generate(payload)})")
        @dialog.execute_script("report(#{JSON.generate(message)}, false)") if message
      end

      def prepare(data)
        raise 'שמור את קובץ SketchUp לפני הכנת רינדור.' if @model.path.to_s.empty?
        room = rooms.find { |r| r['id'] == data['room'].to_s }
        raise 'בחר חדר קיים.' unless room
        scene = data['scene'].to_s
        raise 'הזווית שנבחרה אינה קיימת.' unless scene.empty? || @model.pages.any? { |p| p.name == scene }
        cam = scene.empty? ? @model.active_view.camera : @model.pages.find { |p| p.name == scene }.camera
        raise 'בחר זווית בפרספקטיבה לרינדור פנים.' unless cam.perspective?
        id = SecureRandom.uuid
        dir = File.join(File.dirname(@model.path), 'InteriorPro_sheet', 'renders', id)
        FileUtils.mkdir_p(dir)
        camera = Sketchup::Camera.new(cam.eye, cam.target, cam.up)
        camera.perspective = true
        camera.fov = cam.fov
        camera.aspect_ratio = cam.aspect_ratio
        job = { 'id' => id, 'room_id' => room['id'], 'room_name' => room['name'],
          'scene' => scene.empty? ? 'מבט נוכחי' : scene,
          'target' => InteriorPro::PlanSheetDialog.sets_info(@model)['active'],
          'notes' => data['notes'].to_s[0, 4000], 'status' => 'prepared',
          '_camera' => camera, '_dir' => dir }
        preview = File.join(dir, 'camera-preview.png')
        old = @model.active_view.camera
        begin
          @model.active_view.camera = camera
          @model.active_view.refresh
          ok = @model.active_view.write_image(filename: preview, width: 900, height: 600, antialias: true)
          raise 'צילום הזווית נכשל.' unless ok && File.file?(preview)
        ensure
          @model.active_view.camera = old
        end
        job['preview'] = image_url(preview)
        @jobs << job
        push('הזווית מוכנה. זהו צילום בדיקה מהמודל; הפעל V-Ray להפקת הרינדור.')
      end

      def job_for(data)
        @jobs.find { |j| j['id'] == data['id'] } || raise('המשימה לא נמצאה.')
      end

      def render_job(data)
        job = job_for(data)
        raise 'המשימה כבר נסגרה.' if %w[published rejected].include?(job['status'])
        raise 'V-Ray אינו זמין.' unless defined?(VRay::Command) && VRay::Command.respond_to?(:render_production)
        @model.active_view.camera = job['_camera']
        @model.active_view.refresh
        VRay::Command.render_production
        job['status'] = 'awaiting_result'
        push('V-Ray הופעל בזווית שנבחרה. בסיום שמור PNG או JPEG וטען אותו לבדיקה. ההנחיות נשמרו; Astra עדיין אינו מחובר לביצוע שלהן.')
      end

      def image_url(path)
        ext = File.extname(path).downcase
        mime = ext == '.png' ? 'image/png' : 'image/jpeg'
        "data:#{mime};base64,#{Base64.strict_encode64(File.binread(path))}"
      end

      def import_result(data)
        job = job_for(data)
        raise 'המשימה כבר נסגרה.' if %w[published rejected].include?(job['status'])
        path = UI.openpanel('בחר רינדור מוגמר מ־V-Ray', job['_dir'], 'Images|*.png;*.jpg;*.jpeg||')
        return push('טעינת התמונה בוטלה.') unless path
        attach_result(job, path)
      end

      def attach_result(job, path)
        ext = File.extname(path).downcase
        raise 'בחר PNG או JPEG.' unless %w[.png .jpg .jpeg].include?(ext)
        raise 'התמונה גדולה מדי (מעל 30MB).' if File.size(path) > 30 * 1024 * 1024
        rep = Sketchup::ImageRep.new
        rep.load_file(path)
        raise 'קובץ התמונה אינו תקין.' unless rep.width > 0 && rep.height > 0
        # A fresh immutable path means re-import never overwrites an approved asset.
        dest = File.join(job['_dir'], "result-#{SecureRandom.hex(5)}#{ext}")
        FileUtils.copy_file(path, dest)
        job['_result'] = dest
        job['preview'] = image_url(dest)
        job['status'] = 'review'
        push('בדוק שהתמונה מתאימה לחדר ולזווית. רק אישור ושליחה יוסיפו אותה לתוכניות.')
      end

      def approve(data)
        job = job_for(data)
        return push('התמונה כבר נשלחה לתוכניות.') if job['status'] == 'published'
        raise 'טען קודם רינדור לבדיקה.' unless job['status'] == 'review' && File.file?(job['_result'].to_s)
        raise 'החדר הוסר מהמודל.' unless rooms.any? { |r| r['id'] == job['room_id'] }
        active = InteriorPro::PlanSheetDialog.sets_info(@model)['active']
        raise "יעד המשימה הוא #{job['target']}. פתח את קובץ התוכניות הזה ונסה שוב." unless active == job['target']
        path = job['_result'].tr('\\', '/')
        # Existing publication adapter; duplicate paths are removed by that method.
        @model.start_operation('Approve room render to Sheet', true)
        begin
          InteriorPro::ElevationTool.add_to_sheet!([path], { path => "#{job['room_name']} — #{job['scene']}" })
          state = InteriorPro::PlanSheetDialog.load_state
          raise 'שמירת התמונה בגיליון נכשלה.' unless Array(state['images']).include?(path)
          @model.commit_operation
        rescue StandardError
          @model.abort_operation
          raise
        end
        job['status'] = 'published'
        push('התמונה המאושרת נוספה לתוכניות. שמור את מודל SketchUp כדי לשמור את הגיליונות.')
        InteriorPro::PlanSheetDialog.show
      end

      def reject(data)
        job = job_for(data)
        raise 'תמונה שכבר נשלחה מנוהלת מתוך התוכניות.' if job['status'] == 'published'
        job['status'] = 'rejected'
        push('התמונה נדחתה ולא נשלחה לתוכניות.')
      end
    end
  end
end

# The loader runs on SketchUp's UI thread; keep toolbar setup out of file loading.
UI.start_timer(0, false) { InteriorPro::RenderAgent.setup! }
