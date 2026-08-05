# encoding: utf-8
src = File.readlines('plan_editor.rb', encoding: 'UTF-8')
si = src.index { |l| l =~ /<<~HTML\s*$/ }
ei = (si...src.length).find { |i| src[i] =~ /^\s*HTML\s*$/ && i > si }
abort 'heredoc not found' unless si && ei
body = src[(si + 1)...ei].join
File.write('tmp_heredoc.rb', "# encoding: utf-8\n<<~HTML\n" + body + "\nHTML\n")
html = eval(File.read('tmp_heredoc.rb', encoding: 'UTF-8'))
File.write('out.html', html)
js = html[/<script>(.*)<\/script>/m, 1]
abort 'no <script> found' unless js
File.write('out.js', js)
puts "heredoc lines #{si + 2}..#{ei}, html #{html.bytesize} B, js #{js.bytesize} B"
