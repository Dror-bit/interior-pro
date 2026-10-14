require 'json'
mesh=JSON.parse(File.read(File.join(__dir__,'assets/appliances/kohler-sinks/K-5285-mesh.json')))
part=mesh.fetch('definitions').first
edges=Hash.new(0);adj=Hash.new{|h,k|h[k]=[]}
part.fetch('faces').each do |face|
  face.each_with_index do |a,i|
    b=face[(i+1)%face.length];edges[[a,b].sort]+=1
    adj[a]<<b;adj[b]<<a
  end
end
raise 'Open or overlapping basin edges' unless edges.values.all?{|n|n==2}
seen={};stack=[adj.keys.first]
until stack.empty?
  v=stack.pop;next if seen[v];seen[v]=true;stack.concat(adj[v])
end
raise 'Basin and flange are disconnected' unless seen.size==adj.size
vertices=part.fetch('vertices')
raise 'Changed sink width' unless (vertices.map(&:first).max-32).abs<0.001
raise 'Changed sink top' unless vertices.map{|v|v[2]}.max.abs<0.001
puts 'PASS: K-5285 basin and flange form one closed connected mesh'
