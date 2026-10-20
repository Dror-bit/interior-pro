require_relative 'domain'
core=InteriorPro::Cabinetry;domain=InteriorPro::Laundry::Domain
def check(v,t);raise t unless v;end
def rejects(t);begin;yield;rescue ArgumentError;return;end;raise "Accepted: #{t}";end
make=->(rows){core.validate(core.create(domain:'laundry',assembly_id:'catalog').merge('cabinets'=>rows))}
%w[washer dryer washer_top dryer_rear stack pair_front pair_top upper].each do |product|
 c=domain.cabinet('test',product);check(domain.validate(make.call([c])),"Invalid default #{product}")
 if product!='upper'
  bad=core.copy(c);bad['width']+=0.125;rejects('scaled catalog machine'){domain.validate(make.call([bad]))}
  bad=core.copy(c);bad['model_id']='other';rejects('wrong model'){domain.validate(make.call([bad]))}
  bad=core.copy(c);bad['position']['z']=39;rejects('manual stacking'){domain.validate(make.call([bad]))}
 end
end
w=domain.cabinet('w','washer');d=domain.cabinet('d','dryer');d['position']['x']=28
check(domain.validate(make.call([w,d])),'Shared one-inch gap rejected')
d['position']['x']=27.875;rejects('side service gap'){domain.validate(make.call([w,d]))}
u=domain.cabinet('u','upper');u['position']['z']=57
check(domain.validate(make.call([domain.cabinet('d','dryer'),u])),'Valid dryer overhead rejected')
u['position']['z']=56.875;rejects('dryer overhead'){domain.validate(make.call([domain.cabinet('d','dryer'),u]))}
u['position']['z']=66;u['depth']=14.125;rejects('deep overhead'){domain.validate(make.call([domain.cabinet('d','dryer'),u]))}
u['depth']=12;u['position']['z']=57.875;rejects('top-loader lid clearance'){domain.validate(make.call([domain.cabinet('t','washer_top'),u]))}
u['position']['z']=58;check(domain.validate(make.call([domain.cabinet('t','washer_top'),u])),'Clear lid space rejected')
b=domain.cabinet('b');b['position']['y']=3;rejects('rear service gap'){domain.validate(make.call([w,b]))}
b['position']['y']=-35;rejects('door opening'){domain.validate(make.call([w,b]))}
u=domain.cabinet('u','upper');base=domain.cabinet('b');check(domain.validate(make.call([u,base])),'Upper/base vertical separation rejected')
u['position']['z']=30;rejects('upper/base overlap'){domain.validate(make.call([u,base]))}
w['position']['angle']=90;d['position'].merge!('x'=>0,'y'=>28,'angle'=>90);check(domain.validate(make.call([w,d])),'Rotated side gap rejected')
check(InteriorPro::Laundry::Appliances::MODELS['stack']['height']==78,'Stack height drift')
check(InteriorPro::Laundry::Appliances::MODELS['washer_top']['lid_open_height']==57.25,'Lid height drift')
check(InteriorPro::Laundry::Appliances::MODELS['pair_top']['width']==55,'Pair dimension drift')
puts 'PASS: fixed LG models, front/top/stack/pairs, upper cabinets, height-aware collisions, rotated side gaps, rear/door/lid/overhead clearances; manual stacking and scaling rejected.'
