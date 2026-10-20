require_relative 'domain'
def check(v);raise 'Assertion failed' unless v;end
def rejects;begin;yield;rescue ArgumentError;return;end;raise 'Expected rejection';end
c=InteriorPro::Laundry::Domain
core=InteriorPro::Cabinetry
d=core.create(domain:'laundry',assembly_id:'test')
a=c.cabinet('a');b=c.cabinet('b');b['position']['x']=30
d['cabinets']=[a,b];check(c.validate(core.validate(d)))
b['position']['x']=29.875;rejects { c.validate(d) }
b['position'].merge!('x'=>54,'angle'=>90);check(!c.overlap?(a,b))
a['width']=10;rejects { c.validate(d) };a['width']=30
a['width']=30.01;rejects { c.validate(d) };a['width']=30
a['product_id']='washer';rejects { c.validate(d) }
puts 'PASS: laundry product limits, clean dimensions, touching vs overlap, rotated footprints, unsupported appliances.'
