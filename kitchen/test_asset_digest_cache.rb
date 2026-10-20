require 'tmpdir'
require 'json'
load File.join(__dir__,'kitchen_appliance_assets.rb')
assets=KitchenLab::ApplianceAssets
module DigestReadCounter
  def file(*args)
    $asset_digest_reads=($asset_digest_reads||0)+1
    super
  end
end
Digest::SHA256.singleton_class.prepend(DigestReadCounter)
Dir.mktmpdir('kitchen-digest') do |dir|
  file=File.join(dir,'asset.skp');File.binwrite(file,'first')
  first=assets.file_digest(file);reads=$asset_digest_reads
  20.times { raise 'Cache result changed' unless assets.file_digest(file)==first }
  raise 'Unchanged file was read again' unless $asset_digest_reads==reads
  File.binwrite(file,'second-longer')
  second=assets.file_digest(file)
  raise 'Changed file reused old digest' if second==first
  File.binwrite(file,'third--longer')
  # Explicit timestamp change also covers same-size content edits.
  File.utime(Time.now+2,Time.now+2,file)
  third=assets.file_digest(file)
  raise 'Same-sized edit ignored' if third==second
  File.delete(file)
  begin
    assets.file_digest(file)
    raise 'Deleted file accepted'
  rescue Errno::ENOENT
  end
  File.binwrite(file,'replacement')
  raise 'Replacement ignored' if assets.file_digest(file)==third
  140.times { |i|p=File.join(dir,i.to_s);File.binwrite(p,i.to_s);assets.file_digest(p) }
  raise 'Unbounded digest cache' if assets.instance_variable_get(:@file_digests).size>128
  assets.send(:remove_const,:USE_FILE_DIGEST_CACHE)
  assets.const_set(:USE_FILE_DIGEST_CACHE,false)
  reads=$asset_digest_reads
  2.times { assets.file_digest(file) }
  raise 'Kill switch ignored' unless $asset_digest_reads==reads+2
end
puts 'PASS asset digest cache: hits, edits, same-size edits, deletion, replacement, size bound, kill switch'
