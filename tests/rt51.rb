# encoding: utf-8
# rt51 - pictures dragged into the sheet window (2026-08-14).
#
# debug_drop.rb was run on the user's machine. He dragged eighteen renders in
# and the window received all eighteen - with this on every one:
#
#     path property: NOT THERE
#     keys the window can see on a file:
#       name, lastModified, lastModifiedDate, webkitRelativePath,
#       size, type, arrayBuffer, slice, stream, text
#
# No address anywhere. That is the browser refusing to say where the disk is,
# not something to work around. So the contents travel to Ruby in pieces and
# get written down beside the model.
#
# The rule that matters is that each piece is decoded ON ITS OWN and the BYTES
# are appended - never the base64 text. Glue the text together instead and the
# padding in the middle makes a file that still looks like a JPEG until you try
# to open it. This suite pins the working way and shows the broken way failing,
# so nobody is tempted to "simplify" it later.
#
# (An earlier draft of this file claimed the piece size had to divide by three.
# The test disagreed, and the test was right: it does not, because the pieces
# are never glued as text. The comment in the code was corrected.)
require 'json'
require 'fileutils'
require './sketchup_stub'
require './plan_doc'
require './plan_sheet_dialog'

$fails = 0
def ok(n, c, x = nil)
  puts((c ? 'PASS  ' : 'FAIL  ') + n + (c ? '' : "   << #{x.inspect}"))
  $fails += 1 unless c
end

PSD = InteriorPro::PlanSheetDialog

TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt51_tmp')
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(TMP)
at_exit { FileUtils.rm_rf(TMP) }

# ------------------------------------------------- the piece size, in the code
src = File.read('./plan_sheet_dialog.rb', encoding: 'UTF-8')
chunk = src[/var\s+CHUNK\s*=\s*(\d+)/, 1].to_i
ok('the window has a piece size at all', chunk > 0, chunk)
ok('it is big enough that a 7MB render is a few trips, not hundreds',
   chunk >= 256 * 1024, chunk)
ok('and small enough that one message is never enormous',
   chunk <= 4 * 1024 * 1024, chunk)
ok('it wastes no room on padding either', chunk % 3 == 0, chunk % 3)

# The window must wait to be told a piece landed before sending the next one,
# or a hundred megabytes of messages pile up at once.
ok('the window waits for Ruby between pieces',
   src.include?('function chunkDone(){ sendChunk(); }'),
   'chunkDone no longer drives the next piece')
ok('and Ruby answers every piece', src.include?("execute_script('chunkDone()')"))

# ------------------------------------- what Ruby does with the pieces it gets
# The window slices the file, base64s each slice, and Ruby appends the bytes.
# Exactly the same thing, on a file with a length that is deliberately awkward.
original = (0..255).to_a.pack('C*') * 400 + 'tail'.b     # 102404 bytes, not a multiple of 3
ok('the test file length is awkward on purpose', original.bytesize % 3 != 0,
   original.bytesize % 3)

# The right way: decode each piece, append the BYTES.
def carry(bytes, piece)
  out = +''.b
  off = 0
  while off < bytes.bytesize
    slice = bytes.byteslice(off, piece)
    off += piece
    b64 = [slice].pack('m0')                # what FileReader hands the window
    out << b64.unpack1('m0')                # what the drop_chunk callback does
  end
  out
end

# The tempting way, and why it must not be done: glue the TEXT, decode once.
def carry_wrong(bytes, piece)
  text = +''
  off = 0
  while off < bytes.bytesize
    text << [bytes.byteslice(off, piece)].pack('m0')
    off += piece
  end
  # 'm' rather than 'm0': the strict decoder simply refuses text with padding
  # in the middle, which is its own kind of proof.
  text.unpack1('m')
end

ok('the real piece size carries the file across untouched',
   carry(original, chunk) == original)
ok('so does a tiny piece size', carry(original, 1000) == original)
ok('so does an awkward one', carry(original, 7) == original)
ok('one single piece is fine too', carry(original, original.bytesize) == original)
ok('gluing the base64 TEXT instead loses bytes - this is the trap',
   carry_wrong(original, 1000) != original,
   'gluing the text happened to work, so the warning above is wrong')
ok('nothing arrives with stray newlines to trip the decoder',
   [original.byteslice(0, 5000)].pack('m0') !~ /\s/)

# ------------------------------------------------------------- the file name
ok('a plain name is left alone', PSD.safe_name('1_1 - Photo.jpg') == '1_1 - Photo.jpg',
   PSD.safe_name('1_1 - Photo.jpg'))
ok('a name cannot climb out of the folder',
   PSD.safe_name('../../windows/system32/evil.jpg') == 'evil.jpg',
   PSD.safe_name('../../windows/system32/evil.jpg'))
ok('nor with backslashes',
   PSD.safe_name('..\\..\\evil.jpg') == 'evil.jpg', PSD.safe_name('..\\..\\evil.jpg'))
ok('a name cannot BE a path',
   !PSD.safe_name('C:/windows/a.jpg').include?(':'), PSD.safe_name('C:/windows/a.jpg'))
ok('characters windows refuses are swapped out',
   PSD.safe_name('a<b>c:d"e|f?g*h.jpg') == 'a_b_c_d_e_f_g_h.jpg',
   PSD.safe_name('a<b>c:d"e|f?g*h.jpg'))
ok('a hidden-file name loses its leading dots',
   !PSD.safe_name('...hidden.jpg').start_with?('.'), PSD.safe_name('...hidden.jpg'))
ok('an empty name still gives something to write to',
   PSD.safe_name('') == 'image.jpg' && PSD.safe_name(nil) == 'image.jpg')
ok('a hebrew name survives', PSD.safe_name('חזית.jpg') == 'חזית.jpg',
   PSD.safe_name('חזית.jpg'))
ok('a very long name is cut short', PSD.safe_name('x' * 400 + '.jpg').length <= 120)

# ------------------------------------------------------- two files, same name
File.binwrite(File.join(TMP, 'a.jpg'), 'one')
ok('a free name is used as it is', PSD.free_name(TMP, 'b.jpg') == 'b.jpg')
ok('a taken name gets a number', PSD.free_name(TMP, 'a.jpg') == 'a (2).jpg',
   PSD.free_name(TMP, 'a.jpg'))
File.binwrite(File.join(TMP, 'a (2).jpg'), 'two')
ok('and the next one gets the next number',
   PSD.free_name(TMP, 'a.jpg') == 'a (3).jpg', PSD.free_name(TMP, 'a.jpg'))
ok('the extension stays on the end',
   PSD.free_name(TMP, 'a.jpg').end_with?('.jpg'))

# --------------------------------------------------- where dropped files land
Sketchup.reset_model!
Sketchup.active_model.path = File.join(TMP, 'job.skp')
d = PSD.drop_dir
ok('there is somewhere to put them', !d.to_s.empty? && File.directory?(d), d)
ok('they land beside the SketchUp file, so they travel with the job',
   File.dirname(d) == TMP.tr('\\', '/'), d)
ok('in a folder of our own, not loose next to the model',
   File.basename(d) == 'InteriorPro_images', d)
ok('asking twice does not trip over the folder already being there',
   PSD.drop_dir == d)

# An unsaved model has no folder of its own. It must still work.
Sketchup.active_model.path = ''
d2 = PSD.drop_dir
ok('an unsaved model still gets somewhere to put them',
   !d2.to_s.empty? && File.directory?(d2), d2)
ok('and it is not the same place as a saved job', d2 != d, [d, d2])
FileUtils.rm_rf(d2) if File.basename(d2.to_s) == 'InteriorPro_images'

puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
