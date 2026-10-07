# encoding: utf-8
# rt268 - Escape puts every tool down (2026-10-07).
#
# The user: "צריכה להיות אופציה שאם אני מסמן משהו למחיקה או כל פעולה אחרת בכל
# התוסף הזה ואני לוחץ אסקייפ זה יוצא לי אוטומטית מהפעולה שאני עושה."
# Line 1 of the iron law in CLAUDE.md.
#
# The plugin was gone through tool by tool. Six of them had nothing for Escape
# at all - Delete Door, Edit Door, Delete Wall, Edit Wall, Move Wall and the
# molding toggle. They are the click-and-it-happens tools: no step to cancel,
# so nobody had written a cancel, and Escape left him holding a tool that
# deletes whatever he clicks next.
#
# Two things are pinned here:
#   1. each of those six, given Escape, hands him the select arrow;
#   2. THE LAW ITSELF: no file in the plugin has a tool in it without an answer
#      to Escape. A new tool that forgets fails this suite on the day it is
#      written, instead of being found by him months later.
require './sketchup_stub'
MB_YESNO = 4 unless defined?(MB_YESNO)
IDYES    = 6 unless defined?(IDYES)

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

# ---------------------------------------------------------------------------
# 1. the six
# ---------------------------------------------------------------------------
%w[door_delete_tool door_edit_tool wall_split_tool wall_delete_tool wall_edit_tool wall_move_tool].each do |f|
  begin
    require "./#{f}"
  rescue StandardError, LoadError => e
    ok("#{f}.rb loads", false, "#{e.class}: #{e.message}")
  end
end
begin
  require './molding_library' if File.exist?('./molding_library.rb')
  require './molding_tool'
rescue StandardError, LoadError => e
  ok('molding_tool.rb loads', false, "#{e.class}: #{e.message}")
end

SIX = { 'Delete Door' => 'DoorDeleteTool', 'Edit Door' => 'DoorEditTool', 'Delete Wall' => 'WallDeleteTool',
        'Edit Wall' => 'WallEditTool', 'Move Wall' => 'WallMoveTool', 'Molding toggle' => 'MoldingToggleTool' }.freeze
VIEW = Object.new
def VIEW.invalidate; end
M = Sketchup.active_model

SIX.each do |name, klass|
  unless InteriorPro.const_defined?(klass)
    ok("#{name}: the tool exists", false, klass)
    next
  end
  tool = InteriorPro.const_get(klass).allocate          # no window, no model work - just the tool
  ok("#{name}: it answers Escape at all", tool.respond_to?(:onCancel))
  next unless tool.respond_to?(:onCancel)
  M.select_tool(tool)
  tool.onCancel(0, VIEW)
  ok("#{name}: ESCAPE PUTS THE TOOL DOWN - he is back on the select arrow", M.selected_tool.nil?, M.selected_tool.class)
  M.select_tool(tool)
  tool.onCancel(1, VIEW)
  ok("#{name}: picking the same tool again does not throw him out of it", M.selected_tool.equal?(tool))
  tool.onCancel(2, VIEW)
  ok("#{name}: an undo does not throw him out of it either", M.selected_tool.equal?(tool))
end

# ---------------------------------------------------------------------------
# 2. THE LAW: every file with a tool in it answers Escape
# ---------------------------------------------------------------------------
ROOT  = File.expand_path('..', Dir.pwd)
FILES = (Dir[File.join(ROOT, '*.rb')] + Dir[File.join(ROOT, 'landscape', '*.rb')])
        .reject { |p| File.basename(p) =~ /\Adebug_|before_delete|\Adh_|\Areport_|\Afix_/ }
SRC   = FILES.each_with_object({}) { |p, h| h[p] = File.read(p, encoding: 'UTF-8').scrub }

def tool_file?(s)
  s =~ /^\s*def onLButtonDown\b/ || s =~ /^\s*def onMouseMove\b/
end

def own_escape?(s)
  s =~ /^\s*def onCancel\b/ || s.include?('VK_ESCAPE') || s =~ /key\s*==\s*27\b/
end

# class Child < Parent, anywhere in the plugin
PARENT = {}
SRC.each_value do |s|
  s.scan(/^\s*class\s+([A-Z]\w*)\s*<\s*(?:InteriorPro::)?([A-Z]\w*)/) { |c, par| PARENT[c] = par }
end
WHERE = {}
SRC.each { |p, s| s.scan(/^\s*class\s+([A-Z]\w*)/) { |c,| WHERE[c] ||= p } }

def escape_reaches?(path, seen = {})
  return false if path.nil? || seen[path]
  seen[path] = true
  s = SRC[path]
  return true if own_escape?(s)
  # a tool that inherits its Escape from the tool it is built on
  s.scan(/^\s*class\s+([A-Z]\w*)\s*<\s*(?:InteriorPro::)?([A-Z]\w*)/).any? do |_c, par|
    escape_reaches?(WHERE[par], seen)
  end
end

tools   = SRC.select { |_p, s| tool_file?(s) }.keys
missing = tools.reject { |p| escape_reaches?(p) }.map { |p| File.basename(p) }
ok('the plugin was really looked through', tools.length >= 30, tools.length)
ok("NO TOOL IN THE PLUGIN IS DEAF TO ESCAPE  <<< THE LAW  (#{tools.length} files with tools)", missing.empty?, missing)

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
