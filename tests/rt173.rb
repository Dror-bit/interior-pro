# encoding: utf-8
# rt173 - the vendor photo shows the tile more than once (2026-09-17).
#
# He put a Bedrosians tile on a floor and saw a grout line he had not asked
# for. It was not ours: the product photo IS two 24x48 tiles with the joint
# between them. The tool has to notice that by itself, and he has to be able
# to correct it by hand when it gets it wrong.
#
# Three pure pieces, no SketchUp: read the size string, read the photo's
# pixel size out of its own header, and work out how many tiles are in it.
module InteriorPro
  module MaterialLibrary
    CARD_VERSION = 1 unless const_defined?(:CARD_VERSION)
  end
end
require './material_import'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

M = InteriorPro::MaterialImport

# ---- 1. the size string -----------------------------------------------
ok('24x48', M.parse_size('24x48') == [24.0, 48.0], M.parse_size('24x48'))
ok('spaces and a capital X', M.parse_size('24 X 48') == [24.0, 48.0], M.parse_size('24 X 48'))
ok('inch marks and a vendor prefix',
   M.parse_size('bedrosians 24" x 48"') == [24.0, 48.0], M.parse_size('bedrosians 24" x 48"'))
ok('a decimal', M.parse_size('11.8x23.6') == [11.8, 23.6], M.parse_size('11.8x23.6'))
ok('nothing usable is nil', M.parse_size('large format').nil?)
ok('an empty string is nil', M.parse_size('').nil?)
ok('a zero is nil', M.parse_size('0x48').nil?)

# ---- 2. the photo's own header ----------------------------------------
png = "\x89PNG\r\n\x1a\n".b + [13].pack('N') + 'IHDR'.b +
      [1320].pack('N') + [660].pack('N') + "\x08\x02\x00\x00\x00".b
ok('a PNG header', M.image_pixels(png) == [1320, 660], M.image_pixels(png))

# FFD8 | APP0 (16 bytes) | SOF0 saying 2560 high x 2560 wide
app0 = "\xFF\xE0".b + [16].pack('n') + ('JFIF' + "\x00" * 10).b
sof0 = "\xFF\xC0".b + [17].pack('n') + "\x08".b + [2560].pack('n') + [2560].pack('n') + "\x03".b + ("\x00" * 9).b
jpg = "\xFF\xD8".b + app0 + sof0
ok('a JPEG header behind an APP0 block', M.image_pixels(jpg) == [2560, 2560], M.image_pixels(jpg))
ok('junk is nil, not a crash', M.image_pixels('hello').nil?)
ok('nil is nil', M.image_pixels(nil).nil?)

# ---- 3. how many tiles are in the photo -------------------------------
# HIS case: a square photo of a 24x48 tile is two tiles stacked.
ok('square photo, 24x48 tile -> 2 tiles', M.tile_fit(48, 24, 2560, 2560) == [1, 2],
   M.tile_fit(48, 24, 2560, 2560))
ok('the other card, same shape', M.tile_fit(48, 24, 1320, 1320) == [1, 2],
   M.tile_fit(48, 24, 1320, 1320))
ok('a photo already the shape of the tile is ONE tile',
   M.tile_fit(48, 24, 2560, 1280) == [1, 1], M.tile_fit(48, 24, 2560, 1280))
ok('a square tile in a square photo is one tile',
   M.tile_fit(24, 24, 1000, 1000) == [1, 1], M.tile_fit(24, 24, 1000, 1000))
ok('two tiles side by side', M.tile_fit(24, 48, 1000, 1000) == [2, 1],
   M.tile_fit(24, 48, 1000, 1000))
# A crop has to be EARNED: a shape that fits nothing stays one tile, so a
# bad guess can never eat three quarters of somebody's picture.
ok('a shape that fits nothing stays one tile', M.tile_fit(48, 24, 1000, 777) == [1, 1],
   M.tile_fit(48, 24, 1000, 777))
ok('no size, no crash', M.tile_fit(0, 0, 100, 100) == [1, 1])
ok('no pixels, no crash', M.tile_fit(48, 24, 0, 0) == [1, 1])

# ---- 4. the card carries BOTH numbers ----------------------------------
# the tile is what the layout repeats; the texture is what the photo covers.
card = M.card_for({ 'id' => 'p1', 'name' => 'Proj' },
                  { 'id' => 'm1', 'name' => 'Poetry Stone', 'size' => '24x48' },
                  'textures/x.jpg', jpg)
ok('card tile size', [card['tile_w_inches'], card['tile_l_inches']] == [24.0, 48.0],
   [card['tile_w_inches'], card['tile_l_inches']])
ok('card says the photo holds 2 tiles',
   [card['image_tiles_x'], card['image_tiles_y']] == [2, 1],
   [card['image_tiles_x'], card['image_tiles_y']])
ok('card texture covers all of them',
   [card['texture_width_inches'], card['texture_height_inches']] == [48.0, 48.0],
   [card['texture_width_inches'], card['texture_height_inches']])

puts($fails.zero? ? 'rt173 all green' : "rt173 #{$fails} FAILED")
exit($fails.zero? ? 0 : 1)
