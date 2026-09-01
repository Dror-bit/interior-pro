# encoding: utf-8
# rt130 - EVERY ROOF STYLE CARRIES ITS OWN COLOUR (2026-09-11).
#
# WHY
# The user asked for it by name, style by style: shingles grey, the metal
# roof almost black charcoal, Roman and Spanish the same red-orange clay,
# and the square flat tile a grey leaning slightly purple. Until now every
# roof was born the one brown DEFAULT_ROOF_COLOR and he had to fix it by
# hand each time.
#
# WHAT IS PINNED HERE
# The resolution rule, which is the whole feature: a colour he picked by
# hand ALWAYS wins; otherwise the style's own colour; and the OLD global
# default counts as "not picked", so a roof built before today takes its
# style's colour on the next build instead of staying brown.
ENV['REAL_ROOMS'] = '1'
require './sketchup_stub'
require './roof_manager'

RF = InteriorPro::RoofManager

FAILS = []
def ok(name, cond, extra = nil)
  if cond
    puts "PASS  #{name}"
  else
    puts "FAIL  #{name}#{extra.nil? ? '' : "   << #{extra.inspect}"}"
    FAILS << name
  end
end

def surf(mat, col)
  RF.roof_surface_color(roof_material: mat, roof_color: col)
end

OLD = InteriorPro::RoofManager::DEFAULT_ROOF_COLOR

# --- every style he named has a colour, and they are the right family ---
ok('shingles are grey', RF.roof_colors['shingle'] == '#7f8385',
   RF.roof_colors['shingle'])
ok('standing seam metal is charcoal', RF.roof_colors['seam'] == '#33383b',
   RF.roof_colors['seam'])
ok('Roman and Spanish share one clay',
   RF.roof_colors['roman'] == RF.roof_colors['metaltile'] &&
   RF.roof_colors['roman'] == '#b0552f', RF.roof_colors['roman'])
ok('the flat slate tile has its own grey', RF.roof_colors['slate'] == '#7b7681',
   RF.roof_colors['slate'])
ok('Solid color has no colour of its own', RF.roof_colors['color'].nil?,
   RF.roof_colors['color'])

# --- the old brown default hands over to the style ---------------------
%w[shingle seam roman metaltile slate].each do |mat|
  ok("#{mat}: a roof still on the old default takes the style colour",
     surf(mat, OLD) == RF.roof_colors[mat], surf(mat, OLD))
end
ok('an empty colour takes the style colour too',
   surf('shingle', '') == '#7f8385', surf('shingle', ''))

# --- a hand-picked colour always wins ----------------------------------
ok('a picked colour beats the style', surf('metaltile', '#123456') == '#123456',
   surf('metaltile', '#123456'))
ok('...even when it is another style\'s colour',
   surf('shingle', '#b0552f') == '#b0552f', surf('shingle', '#b0552f'))
ok('picking the style\'s OWN colour reads as not picked (harmless)',
   !RF.roof_color_picked?(roof_material: 'seam', roof_color: '#33383b'))

# --- unknown / missing style falls back to the old default -------------
ok('an unknown material falls back to the old default',
   surf('something_else', OLD) == OLD, surf('something_else', OLD))
ok('Solid color keeps the picker', surf('color', '#ff0000') == '#ff0000',
   surf('color', '#ff0000'))

if FAILS.empty?
  puts 'ALL OK'
else
  puts "*** #{FAILS.length} FAILED ***"
  exit 1
end
