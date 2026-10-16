# encoding: utf-8
# rt327 - SEVERAL SHEET FILES (2026-10-15 17:13, his "קובץ שהוא רק של המטבח או ... של חדר מסויים ... והקובץ הראשי הוא יהיה של
# כל התוכניות ... לערוך רק אותו בלי לגעת בתוכניות"): the open file lives where the one file always lived; switching parks it
# and brings the other; a new file has no plan sheet and no schedules; Main is never thrown away.
require './sketchup_stub'
begin; require './state_backup'; rescue LoadError; end
require './plan_doc' rescue nil
require './plan_sheet_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end
P = InteriorPro::PlanSheetDialog
m = Sketchup.active_model
ok('kill switch is there and on', P::USE_SHEET_SETS == true && P::MAIN_SET == 'Main')
m.set_attribute('InteriorPro', 'sheet_state', JSON.generate('images' => ['C:/a/Room_1_Plan_lines.png'], 'address' => '12 Oak St', 'size' => 'ARCH D'))
ok('a model from before: one file, Main, open', P.sets_info == { 'active' => 'Main', 'names' => ['Main'] }, P.sets_info)
ok('a new file is made and opened', P.new_set!('Room 2') && P.sets_info['active'] == 'Room 2' && P.sets_info['names'] == ['Main', 'Room 2'])
st = P.load_state
ok('the new file: no plan sheet, no schedules, no pictures - the main one\'s title block', st['drop_plan'] == true && st['hidden'].include?('SCHEDULES') &&
   Array(st['images']).empty? && st['address'] == '12 Oak St', st.select { |k, _| %w[drop_plan hidden images address].include?(k) })
st['images'] = ['C:/a/Room_2_Plan_lines.png']
st['elev_size'] = { 'Room 2' => 3 }
P.save_state(st)
ok('elev_size is kept by save_state (not dropped)', P.load_state['elev_size'] == { 'Room 2' => 3 }, P.load_state['elev_size'])
ok('back to Main: its own pictures, untouched', P.switch_set!('Main') && P.load_state['images'] == ['C:/a/Room_1_Plan_lines.png'], P.load_state['images'])
ok('and again to Room 2: its own work is there', P.switch_set!('Room 2') && P.load_state['images'] == ['C:/a/Room_2_Plan_lines.png'])
ok('the same name twice / an empty name: no new file', !P.new_set!('room 2') && !P.new_set!('  ') && P.sets_info['names'].size == 2)
ok('Main can never be thrown away', !P.delete_set!('Main'))
ok('the open file thrown away: Main opens, its pictures are there', P.delete_set!('Room 2') && P.sets_info == { 'active' => 'Main', 'names' => ['Main'] } &&
   P.load_state['images'] == ['C:/a/Room_1_Plan_lines.png'], P.sets_info)
src = File.read('./plan_sheet_dialog.rb')
ok('the window: a "קבצים" list, the three callbacks, the list sent with every load',
   src.include?('id="setsel"') && src.include?("sheet_set_switch") && src.include?("sheet_set_new") && src.include?("sheet_set_delete") &&
   src.include?('sets: (USE_SHEET_SETS ? sets_info : nil)') && src.include?('fillSets(p.sets);'))
puts($fails.zero? ? "\nALL PASS" : "\n#{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
