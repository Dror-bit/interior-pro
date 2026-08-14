# encoding: utf-8
# rt50 - the address the sheet window loads a picture from (2026-08-14).
#
# The window showed a dashed box instead of the render. debug_images.rb was run
# on the user's own machine and measured three things:
#
#   loaded: 3840 x 2160, 24 bits
#   responds to resize:  false      <- SketchUp 2024 ImageRep has no resize
#   responds to save_as: false      <- and no save_as either
#   file:/// loaded:  YES 3840x2160 <- but the window reads the disk fine
#
# So the thumbnail maker was thrown away and the window is pointed straight at
# the file. Which makes the URL the only thing that can still go wrong - and
# this user's renders live in
#
#   C:/Users/rordt/OneDrive/Desktop/Clients/2026/3D/
#     15723 E La Belle St, La Puente, CA 91745/Rendering/1_1 - Photo.jpg
#
# Spaces, commas, a hyphen in the file name. An address that stops at the first
# space shows nothing, and looks exactly like the bug we just fixed.
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

REAL = 'C:/Users/rordt/OneDrive/Desktop/Clients/2026/3D/' \
       '15723 E La Belle St, La Puente, CA 91745/Rendering/1_1 - Photo.jpg'

u = PSD.file_url(REAL)
ok('a file address starts the way the browser expects',
   u.start_with?('file:///C:/Users/'), u[0, 40])
ok('every space is spelt out', !u.include?(' ') && u.include?('%20'), u)
ok('so is every comma', !u.include?(',') && u.include?('%2C'), u)
ok('the slashes stay slashes', u.count('/') == REAL.count('/') + 3, u)
ok('the colon after the drive letter stays', u.include?('C:/'), u)
ok('nothing is lost - it decodes back to the file',
   u.sub('file:///', '').gsub(/%([0-9A-F]{2})/) { $1.hex.chr } == REAL,
   u.sub('file:///', '').gsub(/%([0-9A-F]{2})/) { $1.hex.chr })

ok('a windows backslash path is turned round',
   PSD.file_url('C:\\pics\\a.jpg') == 'file:///C:/pics/a.jpg',
   PSD.file_url('C:\\pics\\a.jpg'))
ok('a plain path is left alone',
   PSD.file_url('C:/pics/a.jpg') == 'file:///C:/pics/a.jpg',
   PSD.file_url('C:/pics/a.jpg'))
ok('a mac path does not grow a second slash',
   PSD.file_url('/Users/me/a.jpg') == 'file:///Users/me/a.jpg',
   PSD.file_url('/Users/me/a.jpg'))

# A Hebrew folder name is bytes, not letters. Encoding it as characters gives
# an address the window cannot open.
heb = PSD.file_url('C:/תמונות/בית.jpg')
ok('a hebrew name is spelt out in bytes', heb.match?(/\A file:\/\/\/C:\/(%[0-9A-F]{2})+/x), heb)
ok('and it decodes back to the hebrew name',
   heb.sub('file:///', '').gsub(/%([0-9A-F]{2})/) { $1.hex.chr }
      .force_encoding('UTF-8') == 'C:/תמונות/בית.jpg',
   heb.sub('file:///', '').gsub(/%([0-9A-F]{2})/) { $1.hex.chr }.force_encoding('UTF-8'))

# A question mark would end the address and start a query string.
q = PSD.file_url('C:/pics/what?.jpg')
ok('a question mark cannot cut the address short', !q.include?('?'), q)
h2 = PSD.file_url('C:/pics/a#1.jpg')
ok('nor can a hash', !h2.include?('#'), h2)

# ------------------------------------------------------- what the window gets
TMP = File.join(File.dirname(File.expand_path(__FILE__)), 'rt50_tmp')
FileUtils.rm_rf(TMP)
FileUtils.mkdir_p(File.join(TMP, 'La Puente, CA'))
here = File.join(TMP, 'La Puente, CA', '1_1 - Photo.jpg').tr('\\', '/')
File.binwrite(here, 'not really a jpeg')

pay = PSD.image_payload('images' => [here, 'C:/gone/missing.jpg'])
ok('the window is told about every picture', pay.length == 2, pay.length)
ok('each one carries its place in the list',
   pay.map { |x| x['i'] } == [0, 1], pay.map { |x| x['i'] })
ok('and a short name to show', pay[0]['name'] == '1_1 - Photo.jpg', pay[0]['name'])
ok('and an address with the spaces spelt out',
   pay[0]['url'].include?('%20') && !pay[0]['url'].include?(' '), pay[0]['url'])
ok('a file that is there is marked as there', pay[0]['there'] == true)
ok('a file that has moved away is marked missing', pay[1]['there'] == false)
ok('the path is sent as well, so the sheet can match it to its picture',
   pay[0]['path'] == here, pay[0]['path'])

# the sheet looks the picture up by PATH, not by name - two renders in
# different folders can easily share a file name
pay2 = PSD.image_payload('images' => [here, here])
ok('the same file twice keeps two entries', pay2.length == 2)
ok('and both point at the same address', pay2[0]['url'] == pay2[1]['url'])

ok('no pictures means an empty list, not a crash',
   PSD.image_payload('images' => []) == [] &&
   PSD.image_payload({}) == [])

# -------------------------------------------------------- one way in, not three
# There were three buttons: one file, a whole folder, several at once. The user
# looked at them and said the middle two were the same thing as the third. So
# the window now has ONE button, and dragging. If a second one ever creeps back,
# this fails and somebody has to have the conversation again.
src = File.read('./plan_sheet_dialog.rb', encoding: 'UTF-8')
section = src[/<h4>תמונות ורינדורים<\/h4>(.*?)<h4>/m, 1].to_s
ok('the pictures section is still in the window', !section.empty?)
buttons = section.scan(/<button id="([a-z]+)"/).flatten
ok('there is exactly one way to add pictures', buttons == ['addmany'], buttons)
ok('and it opens the file window that takes several',
   src.include?('<input type="file" id="filepick" multiple'))
ok('dragging still lands in the same place',
   src.include?("takeFiles((e.dataTransfer&&e.dataTransfer.files)||[])"))
ok('no button is left calling a callback that was removed',
   !src.include?('sketchup.add_image()') && !src.include?('sketchup.add_image_folder()'))

FileUtils.rm_rf(TMP)
puts($fails.zero? ? "\nALL PASS" : "\n*** #{$fails} FAILED ***")
exit($fails.zero? ? 0 : 1)
