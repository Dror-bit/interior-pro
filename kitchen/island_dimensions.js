const KitchenDimensions={
 automatic(data,refs=[],preferences={}){
  const body=this.measure(data,'body',refs),walls=this.measure(data,'wall',refs);
  return [['vertical',['up','down']],['horizontal',['left','right']]].flatMap(([axis,sides])=>{
   const wanted=preferences[axis];const allowed=sides.includes(wanted)?[wanted]:sides;
   const candidates=allowed.map(side=>body.find(m=>m.side===side)||walls.find(m=>m.side===side)).filter(Boolean);
   candidates.sort((a,b)=>(a.basis==='body'?0:1)-(b.basis==='body'?0:1)||a.distance-b.distance);
   return candidates.length?[candidates[0]]:[];
  });
 },
 directions:{right:[1,0],left:[-1,0],up:[0,1],down:[0,-1]},
 noTop:['wall','tall','fridge','oven','wall_oven','oven_tower','micro_tower','fridge_surround','hood','microwave','corner_upper'],
 outline(d,basis){
  if(basis==='countertop'&&this.noTop.includes(d.kind))return null;
  const w=d.width,dep=d.depth+(basis==='countertop'&&d.kind!=='corner'?1:0);
  const pts=['corner_base','corner_lazy','corner_upper'].includes(d.kind)?[[0,0],[w,0],[w,-dep],[dep,-dep],[dep,-w],[0,-w]]:[[0,0],[w,0],[w,-dep],[0,-dep]];
  return pts.map(p=>KitchenPointPlacement.localPoint(KitchenPlacement.cabinetPoint(d,...p),KitchenPlacement.pose));
 },
 interval(poly,v){
  const hits=[];poly.forEach((a,i)=>{const b=poly[(i+1)%poly.length];if(v<Math.min(a[1],b[1])-1e-7||v>Math.max(a[1],b[1])+1e-7)return;
   if(Math.abs(b[1]-a[1])<1e-8){if(Math.abs(v-a[1])<1e-7)hits.push(a[0],b[0]);}
   else hits.push(a[0]+(v-a[1])/(b[1]-a[1])*(b[0]-a[0]));
  });return hits.length?[Math.min(...hits),Math.max(...hits)]:null;
 },
 between(a,b,[nx,ny]){
  const tx=-ny,ty=nx,project=p=>p.map(([x,y])=>[x*nx+y*ny,x*tx+y*ty]),aa=project(a),bb=project(b);
  const lo=Math.max(Math.min(...aa.map(p=>p[1])),Math.min(...bb.map(p=>p[1]))),hi=Math.min(Math.max(...aa.map(p=>p[1])),Math.max(...bb.map(p=>p[1])));if(hi-lo<1e-6)return null;
  const knots=[...new Set([lo,hi,...aa.concat(bb).map(p=>p[1]).filter(v=>v>lo&&v<hi)])].sort((a,b)=>a-b);
  const choices=knots.concat(knots.slice(1).map((v,i)=>(v+knots[i])/2)).flatMap(v=>{
   const ai=this.interval(aa,v),bi=this.interval(bb,v);if(!ai||!bi||bi[0]-ai[1]<-1e-6)return [];
   return [{distance:Math.max(0,bi[0]-ai[1]),from:[ai[1]*nx+v*tx,ai[1]*ny+v*ty],to:[bi[0]*nx+v*tx,bi[0]*ny+v*ty],v}];
  });choices.sort((a,b)=>Number(a.distance.toFixed(6))-Number(b.distance.toFixed(6))||Math.abs(a.v-(lo+hi)/2)-Math.abs(b.v-(lo+hi)/2));
  if(!choices.length)return null;const {v,...out}=choices[0];return out;
 },
 measure(data,basis='body',refs=[]){
  const island=data.filter(d=>KitchenPlacement.wall(d)==='I');if(!island.length)return [];
  const ip=island.map(d=>this.outline(d,basis==='wall'?'body':basis)).filter(Boolean);if(!ip.length)return [];
  const targets=basis==='wall'?refs.filter(r=>r.type==='wall'&&r.measurement_safe).map(r=>({id:r.id,points:r.points.map(p=>KitchenPointPlacement.localPoint(p,KitchenPlacement.pose))})):data.filter(d=>KitchenPlacement.wall(d)!=='I'&&island.some(i=>Math.min(i.z+i.height,d.z+d.height)>Math.max(i.z,d.z)+.001)).map(d=>({id:d.id,points:this.outline(d,basis)})).filter(r=>r.points);
  return Object.entries(this.directions).flatMap(([side,n])=>{
   const choices=ip.flatMap(p=>targets.flatMap(r=>{const m=this.between(p,r.points,n);return m?[{...m,target_id:r.id}]:[];}));
   choices.sort((a,b)=>Number(a.distance.toFixed(6))-Number(b.distance.toFixed(6))||String(a.target_id).localeCompare(String(b.target_id)));
   return choices.length?[{...choices[0],side,basis}]:[];
  });
 }
};
