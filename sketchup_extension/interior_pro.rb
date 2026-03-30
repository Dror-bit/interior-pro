# Interior Pro - SketchUp Extension
# Main loader file

require 'sketchup.rb'
require 'extensions.rb'

module InteriorPro
  EXTENSION = SketchupExtension.new('Interior Pro', 'interior_pro/main.rb')
  EXTENSION.description = 'כלי מקצועי לעיצוב פנים - קירות, דלתות, חלונות ועוד'
  EXTENSION.version = '1.0.0'
  EXTENSION.creator = 'Interior Pro'
  Sketchup.register_extension(EXTENSION, true)
end
