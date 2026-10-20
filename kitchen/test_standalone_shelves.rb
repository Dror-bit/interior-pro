require_relative 'standalone_shelves'
s=InteriorPro::StandaloneShelves
raise unless s.validate(s::DEFAULTS)['width']==36
raise unless s.dimension('1 1/8')==1.125 && s.dimension('3/4')==0.75
['NaN','Infinity','1/0','0.12345'].each do |value|
  begin;s.dimension(value);raise 'Invalid dimension accepted';rescue ArgumentError;end
end
%w[width depth thickness].each do |key|
  begin;s.validate(s::DEFAULTS.merge(key=>0));raise 'Zero size accepted';rescue ArgumentError;end
end
begin;s.validate(s::DEFAULTS.merge('height'=>-1));raise 'Negative height';rescue ArgumentError;end
raise unless s.validate(s::DEFAULTS.merge('height'=>0))['height']==0
begin;s.validate(s::DEFAULTS.merge('thickness'=>20));raise 'Invalid board';rescue ArgumentError;end
puts 'PASS: shelf defaults, fractional inches, eighth-inch precision, invalid dimensions, zero floor height.'
