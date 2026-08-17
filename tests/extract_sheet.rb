# encoding: utf-8
# extract_sheet.rb - pull the sheet window's JavaScript out of plan_sheet_dialog.rb
# so node can check it and run it.
#
# The twin of extract.rb, which does the same for the 2D editor. Same reason:
# a suite must RUN the code that ships, never a copy of it. Written the day a
# feature was reported dead in the window and there was no way to tell a
# broken script from a plugin that had not been reloaded (2026-08-17).
src = File.readlines('plan_sheet_dialog.rb', encoding: 'UTF-8')
si = src.index { |l| l =~ /<<~'HTML'\s*$/ }
ei = (si...src.length).find { |i| src[i] =~ /^\s*HTML\s*$/ && i > si }
abort 'heredoc not found' unless si && ei

# Single-quoted heredoc: the body is already literal, nothing to interpolate.
html = src[(si + 1)...ei].join
File.write('sheet.html', html)
js = html[/<script>(.*)<\/script>/m, 1]
abort 'no <script> found' unless js
File.write('sheet.js', js)
puts "sheet heredoc lines #{si + 2}..#{ei}, html #{html.bytesize} B, js #{js.bytesize} B"
