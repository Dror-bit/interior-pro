# encoding: utf-8
# rt47 - real pictures inside the PDF (2026-08-14).
#
# Until now plan_pdf drew an empty rectangle where a render should be, so a
# sheet could never carry a Lumion image. This suite pins the new behaviour:
# a JPEG travels into the file untouched, a PNG is unpacked, a see-through PNG
# grows a grey mask, and a missing file still exports a sheet instead of
# throwing the whole job away.
#
# Pure Ruby - no SketchUp, no stub. The pictures are built here in the test so
# nothing depends on a file lying about on someone's disk.
require 'zlib'
require './plan_doc'
require './plan_pdf'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PD = InteriorPro::PlanDoc
PP = InteriorPro::PlanPDF

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt47_tmp')
require 'fileutils'
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }

def tmp(name)
  File.join(TMP, name)
end

# ---------------------------------------------------------------- builders
# A PNG written by hand, so the test knows exactly which pixels went in.
def png(path, w, h, ct, rows, opts = {})
  chan = { 0 => 1, 2 => 3, 3 => 1, 4 => 2, 6 => 4 }[ct]
  raw = +''.b
  rows.each_with_index do |row, i|
    raw << (opts[:filter] ? opts[:filter][i] : 0).chr
    raw << row.pack('C*')
  end
  ihdr = [w, h].pack('N2') + [8, ct, 0, 0, 0].pack('C5')
  body = +"\x89PNG\r\n\x1A\n".b
  add = lambda do |kind, data|
    body << [data.bytesize].pack('N') << kind.b << data.b
    body << [Zlib.crc32(kind.b + data.b)].pack('N')
  end
  add.call('IHDR', ihdr)
  add.call('PLTE', opts[:plte]) if opts[:plte]
  add.call('tRNS', opts[:trns]) if opts[:trns]
  add.call('IDAT', Zlib::Deflate.deflate(raw))
  add.call('IEND', '')
  File.binwrite(path, body)
  path
end

# A JPEG that carries no real pixels - only the markers the reader walks.
def jpg(path, w, h, ncomp = 3)
  sof = [8, h, w, ncomp].pack('CnnC') + ("\x01\x11\x00".b * ncomp)
  out = +"\xFF\xD8".b
  out << "\xFF\xE0".b << [16].pack('n') << "JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00".b
  out << "\xFF\xC0".b << [sof.bytesize + 2].pack('n') << sof
  out << "\xFF\xDA".b << [8].pack('n') << "\x01\x01\x00\x00\x3F\x00".b
  out << "\x12\x34\x56".b << "\xFF\xD9".b
  File.binwrite(path, out)
  path
end

# ------------------------------------------------------------------- JPEG
j = jpg(tmp('r.jpg'), 640, 480)
info = PP.load_image(j)
ok('a JPEG is read at all', !info.nil?)
ok('its size is read from the markers', info && [info[:w], info[:h]] == [640, 480],
   info && [info[:w], info[:h]])
ok('it stays a JPEG - PDF decodes it itself', info && info[:filter] == '/DCTDecode',
   info && info[:filter])
ok('three colours means RGB', info && info[:cs] == '/DeviceRGB', info && info[:cs])
ok('not one byte of the file was touched',
   info && info[:data] == File.binread(j), 'the bytes changed')
ok('no mask on a JPEG', info && info[:smask].nil?)

g = PP.load_image(jpg(tmp('g.jpg'), 8, 4, 1))
ok('one colour means grey', g && g[:cs] == '/DeviceGray', g && g[:cs])
ok('a tall thin JPEG keeps width and height apart',
   g && [g[:w], g[:h]] == [8, 4], g && [g[:w], g[:h]])

# -------------------------------------------------------------------- PNG
rows2 = [[255, 0, 0, 0, 255, 0], [0, 0, 255, 9, 9, 9]]
p2 = PP.load_image(png(tmp('rgb.png'), 2, 2, 2, rows2))
ok('a plain RGB PNG is read', !p2.nil?)
ok('and goes in still compressed, with the predictor', p2 && p2[:filter] == '/FlateDecode' &&
   p2[:parms].to_s.include?('/Predictor 15') && p2[:parms].to_s.include?('/Colors 3'),
   p2 && p2[:parms])
ok('a plain PNG needs no mask', p2 && p2[:smask].nil?)

p0 = PP.load_image(png(tmp('grey.png'), 3, 1, 0, [[10, 20, 30]]))
ok('a grey PNG is grey', p0 && p0[:cs] == '/DeviceGray', p0 && p0[:cs])
ok('and says one colour', p0 && p0[:parms].to_s.include?('/Colors 1'), p0 && p0[:parms])

plte = [255, 0, 0, 0, 255, 0, 0, 0, 255].pack('C*')
p3 = PP.load_image(png(tmp('pal.png'), 3, 1, 3, [[0, 1, 2]], plte: plte))
ok('a palette PNG keeps its palette', p3 && p3[:cs].to_s.start_with?('[/Indexed /DeviceRGB 2 <'),
   p3 && p3[:cs])

# ------------------------------------------------------- PNG that sees through
rgba = [[255, 0, 0, 255, 0, 255, 0, 128], [0, 0, 255, 0, 1, 2, 3, 64]]
p6 = PP.load_image(png(tmp('rgba.png'), 2, 2, 6, rgba))
ok('an RGBA PNG is read', !p6.nil?)
ok('it becomes plain RGB', p6 && p6[:cs] == '/DeviceRGB', p6 && p6[:cs])
ok('and grows a mask', p6 && !p6[:smask].nil?)
if p6
  ok('the colours came out in the right order',
     Zlib::Inflate.inflate(p6[:data]).bytes == [255, 0, 0, 0, 255, 0, 0, 0, 255, 1, 2, 3],
     Zlib::Inflate.inflate(p6[:data]).bytes)
  ok('the see-through amounts came out in the right order',
     Zlib::Inflate.inflate(p6[:smask][:data]).bytes == [255, 128, 0, 64],
     Zlib::Inflate.inflate(p6[:smask][:data]).bytes)
  ok('the mask is the same size as the picture',
     p6[:smask][:w] == 2 && p6[:smask][:h] == 2)
end

p4 = PP.load_image(png(tmp('ga.png'), 2, 1, 4, [[200, 255, 100, 0]]))
ok('grey plus see-through works too',
   p4 && p4[:cs] == '/DeviceGray' &&
   Zlib::Inflate.inflate(p4[:data]).bytes == [200, 100] &&
   Zlib::Inflate.inflate(p4[:smask][:data]).bytes == [255, 0],
   p4 && [Zlib::Inflate.inflate(p4[:data]).bytes,
          Zlib::Inflate.inflate(p4[:smask][:data]).bytes])

pt = PP.load_image(png(tmp('palt.png'), 3, 1, 3, [[0, 1, 2]],
                       plte: plte, trns: [0, 128].pack('C*')))
ok('a palette with see-through entries grows a mask too',
   pt && pt[:smask] &&
   Zlib::Inflate.inflate(pt[:smask][:data]).bytes == [0, 128, 255],
   pt && pt[:smask] && Zlib::Inflate.inflate(pt[:smask][:data]).bytes)

# -------------------------------------------------- every PNG row filter works
# The SAME three grey pixels five times over, each row written with a different
# filter. Encoded by hand here, so the answer is known before the code runs:
# whichever filter a row used, it must come back as 10, 20, 30.
#   row 0  None     the pixels as they are
#   row 1  Sub      each byte less the one to its left
#   row 2  Up       each byte less the one above
#   row 3  Average  less the average of left and above
#   row 4  Paeth    left, above or above-left, whichever the rule picks
enc = [[10, 20, 30],
       [10, 10, 10],
       [0, 0, 0],
       [5, 5, 5],
       [0, 0, 0]]
png(tmp('filters.png'), 3, 5, 0, enc, filter: [0, 1, 2, 3, 4])
got = PP.png_unfilter(
  Zlib::Inflate.inflate(PP.png_chunks(File.binread(tmp('filters.png')))[:idat]),
  3, 5, 1
).bytes
ok('all five PNG row filters are undone', got == [10, 20, 30] * 5, got)

# --------------------------------------------------------- an unreadable file
PP.forget_images!
ok('a file that is not there gives nothing, quietly',
   PP.load_image(tmp('nope.jpg')).nil?)
File.binwrite(tmp('junk.jpg'), 'this is not a picture')
ok('rubbish gives nothing, quietly', PP.load_image(tmp('junk.jpg')).nil?)
ok('nil gives nothing', PP.load_image(nil).nil?)

# ------------------------------------------------------------- keeping shape
ok('a wide photo in a square box keeps its shape',
   PP.fit_box(1000, 500, 0.0, 0.0, 4.0, 4.0, false).map { |v| v.round(3) } ==
   [0.0, 1.0, 4.0, 2.0],
   PP.fit_box(1000, 500, 0.0, 0.0, 4.0, 4.0, false))
ok('a tall photo in a square box keeps its shape',
   PP.fit_box(500, 1000, 0.0, 0.0, 4.0, 4.0, false).map { |v| v.round(3) } ==
   [1.0, 0.0, 2.0, 4.0],
   PP.fit_box(500, 1000, 0.0, 0.0, 4.0, 4.0, false))
ok('asking to stretch fills the whole box',
   PP.fit_box(1000, 500, 1.0, 2.0, 4.0, 4.0, true) == [1.0, 2.0, 4.0, 4.0])

# ------------------------------------------------------------ the whole file
def sheet(shapes)
  doc = PD::Document.new('t')
  pg  = doc.add_page('A-101', 'LETTER')
  lay = pg.layer('PAPER')
  shapes.each { |s| lay.image(s[0], s[1], s[2], s[3], s[4]) }
  doc
end

PP.forget_images!
out = tmp('one.pdf')
PP.export(sheet([[j, 1.0, 1.0, 4.0, 3.0]]), out)
pdf = File.binread(out)
ok('the PDF was written', File.size(out) > 0)
ok('it holds a picture object', pdf.include?('/Subtype /Image'))
ok('the picture is still a JPEG inside the PDF', pdf.include?('/DCTDecode'))
ok('the page knows how to reach it', pdf =~ %r{/XObject << /Im1 \d+ 0 R >>}, pdf[0, 0])
ok('the picture is actually painted', pdf.include?('/Im1 Do'))
ok('the JPEG bytes themselves are in the file', pdf.include?(File.binread(j)))
ok('the box keeps the photo shape: 4 wide, 3 tall fits exactly',
   pdf =~ /288\.000 0 0 216\.000 /, pdf[/[\d.]+ 0 0 [\d.]+ [\d.]+ [\d.]+ cm/])

PP.forget_images!
out2 = tmp('mask.pdf')
PP.export(sheet([[tmp('rgba.png'), 1.0, 1.0, 2.0, 2.0]]), out2)
pdf2 = File.binread(out2)
ok('a see-through PNG puts its mask in the file', pdf2 =~ %r{/SMask \d+ 0 R})
ok('and the mask is grey', pdf2.scan('/DeviceGray').length >= 1)

PP.forget_images!
out3 = tmp('twice.pdf')
PP.export(sheet([[j, 0.5, 0.5, 2.0, 2.0], [j, 3.0, 0.5, 2.0, 2.0]]), out3)
pdf3 = File.binread(out3)
ok('the same photo used twice is stored once',
   pdf3.scan('/DCTDecode').length == 1 && pdf3.scan('/Im1 Do').length == 2,
   [pdf3.scan('/DCTDecode').length, pdf3.scan('/Im1 Do').length])

PP.forget_images!
out4 = tmp('missing.pdf')
begin
  PP.export(sheet([[tmp('nope.jpg'), 1.0, 1.0, 4.0, 3.0]]), out4)
  ok('a missing photo does not lose the sheet', File.size(out4) > 0)
  ok('it falls back to the old empty frame', File.binread(out4).include?(' re S'))
  ok('and no picture object is invented', !File.binread(out4).include?('/Subtype /Image'))
rescue StandardError => e
  ok('a missing photo does not lose the sheet', false, e.message)
end

# ----------------------------------------------- nothing else moved (rt39-46)
PP.forget_images!
plain = PD::Document.new('t')
pgp = plain.add_page('A-101', 'LETTER')
pgp.layer('PAPER').text('HELLO', 1.0, 1.0, h: 0.2)
outp = tmp('plain.pdf')
PP.export(plain, outp)
txt = File.binread(outp)
ok('a sheet with no pictures has no picture plumbing at all',
   !txt.include?('/XObject') && !txt.include?('/Subtype /Image'))
ok('and still writes its words', txt.include?('(HELLO) Tj'))

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
