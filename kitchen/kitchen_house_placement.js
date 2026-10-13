/* World-inch geometry shared by the house drag controller and offline tests. */
(function(root){
 const add=(a,b)=>a.map((v,i)=>v+b[i]),sub=(a,b)=>a.map((v,i)=>v-b[i]),mul=(a,s)=>a.map(v=>v*s),dot=(a,b)=>a[0]*b[0]+a[1]*b[1];
 function faces(walls){return walls.flatMap(w=>{if(Math.abs(w.sag||0)>=.0625||!w.corners||w.corners.length!==8)return [];const pts=Array.from({length:4},(_,i)=>w.corners.slice(i*2,i*2+2)),center=mul(pts.reduce(add,[0,0]),.25),axis=[w.ex-w.sx,w.ey-w.sy],len=Math.hypot(...axis);if(len<.01)return [];return pts.flatMap((a,i)=>{const b=pts[(i+1)%4],v=sub(b,a),length=Math.hypot(...v),u=mul(v,1/length);if(length<.01||Math.abs(dot(u,mul(axis,1/len)))<.98)return [];let n=[-u[1],u[0]];if(dot(n,sub(mul(add(a,b),.5),center))<0)n=mul(n,-1);return [{wall_id:w.id,face:i,a,b,u,n,length}];});});}
 function placement(c,origin,u,v,attachment={}){const fx=c.flip_x?-1:1,fy=c.flip_y?-1:1,A=mul(u,fx),B=mul(v,fy),o=sub(sub(origin,mul(A,c.flip_x?c.width:0)),mul(B,c.flip_y?-c.depth:0));return {x:o[0],y:o[1],angle:Math.atan2(A[1],A[0])*180/Math.PI,handedness:Math.round(A[0]*B[1]-A[1]*B[0]),...attachment};}
 function point(c,h,x,y){if(c.flip_x)x=c.width-x;if(c.flip_y)y=-c.depth-y;y*=h.handedness;const a=h.angle*Math.PI/180;return [h.x+x*Math.cos(a)-y*Math.sin(a),h.y+x*Math.sin(a)+y*Math.cos(a)];}
 function rowAt(row,h){const c=row.cabinet,dep=['corner_base','corner_lazy','corner_upper'].includes(c.kind)?c.width:c.depth;return {...row,cabinet:{...c,house_placement:h},basis:[[0,0],[1,0],[0,-1]].map(q=>point(c,h,...q)),polygon:[[0,0],[c.width,0],[c.width,-dep],[0,-dep]].map(q=>point(c,h,...q))};}
 function overlap(a,b){return [a,b].every(poly=>poly.every((p,i)=>{const v=sub(poly[(i+1)%poly.length],p),len=Math.hypot(...v);if(len<1e-8)return true;const n=[-v[1]/len,v[0]/len],aa=a.map(q=>dot(q,n)),bb=b.map(q=>dot(q,n));return Math.min(Math.max(...aa),Math.max(...bb))-Math.max(Math.min(...aa),Math.min(...bb))>.01;}));}
 function touchesWall(poly,w){if(w.corners?.length!==8)return false;const pts=Array.from({length:4},(_,i)=>w.corners.slice(i*2,i*2+2));return pts.some((a,i)=>{const v=sub(pts[(i+1)%4],a),len=Math.hypot(...v);if(len<.001)return false;const on=poly.filter(p=>Math.abs((p[0]-a[0])*v[1]-(p[1]-a[1])*v[0])/len<.02);if(on.length<2)return false;const ts=on.map(p=>dot(sub(p,a),v)/len);return Math.min(Math.max(...ts),len)-Math.max(Math.min(...ts),0)>.01;});}
 function propose(row,delta,walls,tolerance,rows=[],held=null){
  const c=row.cabinet,footDepth=['corner_base','corner_lazy','corner_upper'].includes(c.kind)?c.width:c.depth,b=row.basis,origin=add(b[0],delta),u=sub(b[1],b[0]),v=mul(sub(b[2],b[0]),-1);
  const center=add(origin,add(mul(u,c.width/2),mul(v,-footDepth/2))),candidates=[];
  const vertical=other=>Math.min(row.base_z+row.height,other.base_z+other.height)-Math.max(row.base_z,other.base_z)>.001;
  const free={h:placement(c,origin,u,v),rank:3,distance:0};
  const bases=[];
  if(c.kind.startsWith('corner_')){
   const fs=faces(walls);
   for(const a of fs)for(const b of fs){
    if(a.wall_id===b.wall_id||Math.abs(dot(a.u,b.u))>.001)continue;
    const diff=sub(b.a,a.a),cross=(x,y)=>x[0]*y[1]-x[1]*y[0],den=cross(a.u,b.u);
    const o=add(a.a,mul(a.u,cross(diff,b.u)/den)),x=b.n,front=a.n;
    const endA=add(o,mul(x,c.width)),endB=add(o,mul(front,c.width));
    const inside=(f,p)=>{const t=dot(sub(p,f.a),f.u);return t>=-.02&&t<=f.length+.02;};
    if(!inside(a,o)||!inside(b,o)||!inside(a,endA)||!inside(b,endB))continue;
    const targetCenter=add(o,mul(add(x,front),c.width/2)),distance=Math.hypot(...sub(center,targetCenter));
    const capture=Math.max(tolerance*2,c.width*.6)*(held?.corner?1.8:1);
    if(distance>capture)continue;
    const along=dot(sub(add(o,mul(x,c.width/2)),a.a),a.u);
    candidates.push({h:placement(c,o,x,mul(front,-1),{wall_id:a.wall_id,face:a.face,along}),rank:-1,distance,corner:true});
   }
  }
  for(const f of faces(walls)){
   if(f.length<c.width)continue;
   const capture=held?.placement.wall_id===f.wall_id&&held?.placement.face===f.face?tolerance*1.8:tolerance; const signed=dot(sub(center,f.a),f.n);
   // Catch pushing into the wall as well as approaching it. Never switch to
   // the opposite face while the cabinet center is still on this side.
   const currentReach=(Math.abs(dot(u,f.n))*c.width+Math.abs(dot(v,f.n))*footDepth)/2;
   if(signed<-.01||signed>Math.max(footDepth/2,currentReach)+capture)continue;
   const projected=dot(sub(center,f.a),f.u),along=Math.max(c.width/2,Math.min(f.length-c.width/2,projected));
   if(Math.abs(projected-along)>capture)continue;
   const back=add(f.a,mul(f.u,along)),x=[-f.n[1],f.n[0]],o=sub(back,mul(x,c.width/2));
   bases.push({h:placement(c,o,x,mul(f.n,-1),{wall_id:f.wall_id,face:f.face,along}),face:f,rank:1,distance:Math.abs(signed-footDepth/2)});
  }
  for(const base of (bases.length?bases:[free])){
   candidates.push(base);
   const positioned=rowAt(row,base.h),p=positioned.basis,x=sub(p[1],p[0]),front=sub(p[2],p[0]);
   for(const other of rows){
    if(other.id===row.id||!vertical(other)||!other.basis)continue;
    const q=other.basis,ox=sub(q[1],q[0]),of=sub(q[2],q[0]);
    if(dot(x,ox)<.999||dot(front,of)<.999)continue;
    for(const target of [add(q[0],mul(ox,other.cabinet.width)),sub(q[0],mul(x,c.width))]){
     const shift=sub(target,p[0]),alongShift=dot(shift,x),depthShift=dot(shift,front);
     const capture=held?.neighbor===other.id?tolerance*1.8:tolerance; if(Math.abs(alongShift)>capture||Math.abs(depthShift)>capture)continue;
     // On a wall, preserve its face even if the old neighbor has a small gap.
     const change=base.face?mul(x,alongShift):shift;
     let h={...base.h,x:base.h.x+change[0],y:base.h.y+change[1]};
     if(base.face){h.along+=dot(change,base.face.u);if(h.along<c.width/2-.001||h.along>base.face.length-c.width/2+.001)continue;}
     candidates.push({h,rank:base.face?0:2,distance:Math.hypot(...change),neighbor:other.id});
    }
   }
  }
  function assess(candidate){const h=candidate.h,next=rowAt(row,h);let error=null;
   for(const other of rows)if(other.id!==row.id&&vertical(other)&&overlap(next.polygon,other.polygon)){error='Cabinets overlap';break;}
   for(const w of walls){if(w.corners?.length===8&&overlap(next.polygon,Array.from({length:4},(_,i)=>w.corners.slice(i*2,i*2+2))))error='Cabinet intersects a wall';
    if(touchesWall(next.polygon,w)){const axis=[w.ex-w.sx,w.ey-w.sy],len=Math.hypot(...axis),t=mul(axis,1/len),ps=next.polygon.map(p=>dot(sub(p,[w.sx,w.sy]),t));const blocked=(w.kitchen_openings??w.ops??[]).find(([at,width,bottom,top])=>Math.min(Math.max(...ps),at+width/2)-Math.max(Math.min(...ps),at-width/2)>.01&&(bottom==null||top==null||Math.min(next.base_z+next.height,top)-Math.max(next.base_z,bottom)>.001));if(blocked)error=blocked[4]==='window'?'Window is too low for this cabinet.':'Door opening must remain clear.';}}
   return {row:next,placement:h,error,snapped:!!h.wall_id,neighbor:candidate.neighbor||null,corner:!!candidate.corner};
  }
  const matches=c=>held&&!held.error&&(c.h.wall_id||null)===(held.placement.wall_id||null)&&c.h.face===held.placement.face&&(c.neighbor||null)===(held.neighbor||null); candidates.sort((a,b)=>a.rank-b.rank||Number(matches(b))-Number(matches(a))||a.distance-b.distance);
  const cornerCandidates=candidates.filter(c=>c.corner);const results=(cornerCandidates.length?cornerCandidates:candidates).map(assess);return results.find(r=>!r.error)||results[0];
 }
 function bundle(row,rows){
  const owner=row.cabinet.surround_for||row.id;
  const members=rows.filter(r=>r.id===owner||r.cabinet.surround_for===owner);
  if(members.length<2)return {row,members:[row]};
  const o=row.basis[0],u=sub(row.basis[1],o),v=mul(sub(row.basis[2],o),-1);
  const coordinates=members.flatMap(r=>r.polygon.map(p=>[dot(sub(p,o),u),dot(sub(p,o),v)]));
  const xs=coordinates.map(p=>p[0]),ys=coordinates.map(p=>p[1]),xmin=Math.min(...xs),ymax=Math.max(...ys);
  const origin=add(o,add(mul(u,xmin),mul(v,ymax))),width=Math.max(...xs)-xmin,depth=ymax-Math.min(...ys);
  const bottom=Math.min(...members.map(r=>r.base_z)),top=Math.max(...members.map(r=>r.base_z+r.height));
  const aggregate={...row,base_z:bottom,height:top-bottom,cabinet:{...row.cabinet,kind:'doors',width,depth,flip_x:false,flip_y:false}};
  return {row:rowAt(aggregate,placement(aggregate.cabinet,origin,u,v)),members};
 }
 function moveBundle(group,next){
  const a=group.row.basis,b=next.basis,u=sub(a[1],a[0]),v=mul(sub(a[2],a[0]),-1),nu=sub(b[1],b[0]),nv=mul(sub(b[2],b[0]),-1);
  const transform=p=>{const d=sub(p,a[0]);return add(b[0],add(mul(nu,dot(d,u)),mul(nv,dot(d,v))));};
  return group.members.map(r=>{const basis=r.basis.map(transform);return rowAt(r,placement(r.cabinet,basis[0],sub(basis[1],basis[0]),mul(sub(basis[2],basis[0]),-1)));});
 }
 function bundleError(moved,rows,walls){
  const ids=new Set(moved.map(r=>r.id));
  for(const r of moved){
   for(const other of rows)if(!ids.has(other.id)&&Math.min(r.base_z+r.height,other.base_z+other.height)-Math.max(r.base_z,other.base_z)>.001&&overlap(r.polygon,other.polygon))return 'Cabinets overlap';
   for(const w of walls){
    if(w.corners?.length!==8)continue;
    if(overlap(r.polygon,Array.from({length:4},(_,i)=>w.corners.slice(i*2,i*2+2))))return 'Cabinet intersects a wall';
    if(touchesWall(r.polygon,w)){const axis=[w.ex-w.sx,w.ey-w.sy],len=Math.hypot(...axis);if(len<.001)continue;const t=mul(axis,1/len),ps=r.polygon.map(p=>dot(sub(p,[w.sx,w.sy]),t));const blocked=(w.kitchen_openings??w.ops??[]).find(([at,width,bottom,top])=>Math.min(Math.max(...ps),at+width/2)-Math.max(Math.min(...ps),at-width/2)>.01&&(bottom==null||top==null||Math.min(r.base_z+r.height,top)-Math.max(r.base_z,bottom)>.001));if(blocked)return blocked[4]==='window'?'Window is too low for this cabinet.':'Door opening must remain clear.';}
   }
  }
  return null;
 }
 root.KitchenHousePlacement={faces,placement,point,rowAt,overlap,propose,bundle,moveBundle,bundleError};
})(typeof globalThis!=='undefined'?globalThis:this);
