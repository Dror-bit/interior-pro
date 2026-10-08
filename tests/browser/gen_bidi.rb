# encoding: utf-8
# gen_bidi.rb OUT.json - the runs rt282 pins and how PlanPDF.visual orders their letters, for tests/browser/bidi.js to hold against Chromium
require 'json'
require './plan_doc'
require './plan_pdf'
RUNS = ['[א] פריט 3.5', '(חדר) 2', 'שלום (world) עולם', '(12) חדרים', 'קיר חוץ 6" (A)', 'חדר 12 גדול', 'Room שלום 12 עולם (A) end',
        'שלום, עולם!', 'מידות לפי התוכנית 2026-10-07', '(שלום)', 'A-102  שרטוט 1', 'שלום', 'חדר שינה ראשי', %q(מפלס 2: גובה 9'-6"),
        'בית (דרור) 12/3', 'טלפון 050-1234567', 'ROOM 2 (חדר)', 'דלת D101 בקיר', 'שטח 42 SF', %q(1/4" = 1'-0" קנה מידה)].freeze
h = {}
RUNS.each { |r| h[r] = InteriorPro::PlanPDF.visual(r) }
File.write(ARGV[0] || 'bidi_pairs.json', JSON.generate(h))
puts "#{h.length} runs -> #{ARGV[0] || 'bidi_pairs.json'}"
