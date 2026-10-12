/* Pure cabinet placement logic; coordinates are inches. */
const KitchenPlacement={
 island:{x:48,y:84,angle:0},
 pose:{x:0,y:0,z:0,angle:0,level:1},
 rotate(x,y,angle){const a=angle*Math.PI/180;return [x*Math.cos(a)-y*Math.sin(a),x*Math.sin(a)+y*Math.cos(a)];},
 point(wall,x,y,local=false){
  if(local)return [x,y];
  if(wall==='B')[x,y]=[-y,-x];
  if(wall==='I'){[x,y]=this.rotate(x,y,this.island.angle||0);x+=this.island.x;y-=this.island.y;}
  [x,y]=this.rotate(x,y,this.pose.angle||0);return [x+this.pose.x,y+this.pose.y];
 },
 along(wall,worldX,worldY){const o=this.point(wall,0,0),u=this.point(wall,1,0);return (worldX-o[0])*(u[0]-o[0])+(worldY-o[1])*(u[1]-o[1]);},
 cabinetPivot(c){return ({back_left:[0,0],back_right:[c.width,0],front_left:[0,-(c.depth??24)],front_right:[c.width,-(c.depth??24)]})[c.rotation_pivot]||[c.width/2,-(c.depth??24)/2];},
 cabinetPoint(c,x,y,local=false){if(c.flip_x)x=c.width-x;if(c.flip_y)y=-c.depth-y;if(!local&&c.house_placement){const p=c.house_placement,q=this.rotate(x,y*(p.handedness??1),p.angle);return [p.x+q[0],p.y+q[1]];}if(local){if(!c._preview_rotation)return [c.x+x,y];const [px,py]=this.cabinetPivot(c),q=this.rotate(x-px,y-py,c.rotation||0);return [c.x+px+q[0],py+q[1]];}if(c.width==null||c.depth==null)return this.point(this.wall(c),c.x+x,y);const [cx,cy]=this.cabinetPivot(c);const q=this.rotate(x-cx,y-cy,c.rotation||0);return this.point(this.wall(c),c.x+cx+q[0],cy+q[1]+(c.offset_y||0));},
 polygon(c,local=false){const dep=this.corner(c)&&c.kind!=='corner'?c.width:(c.depth??24);return [[0,0],[c.width,0],[c.width,-dep],[0,-dep]].map(p=>this.cabinetPoint(c,...p,local));},
 wall(c){return c.wall||'A';},
 corner(c){return ['corner','corner_base','corner_upper','corner_lazy'].includes(c.kind);},
 footprint(c,local=false){const p=this.polygon(c,local),x=p.map(v=>v[0]),y=p.map(v=>v[1]);return [Math.min(...x),Math.max(...x),Math.min(...y),Math.max(...y)];},
 overlap(a,b){
  if(Math.min(a.z+a.height,b.z+b.height)-Math.max(a.z,b.z)<=.001)return false;
  const aa=this.polygon(a),bb=this.polygon(b);
  return [aa,bb].every(poly=>poly.every((p,i)=>{const q=poly[(i+1)%poly.length],dx=q[0]-p[0],dy=q[1]-p[1],len=Math.hypot(dx,dy),axis=[-dy/len,dx/len],av=aa.map(v=>v[0]*axis[0]+v[1]*axis[1]),bv=bb.map(v=>v[0]*axis[0]+v[1]*axis[1]);return Math.min(Math.max(...av),Math.max(...bv))-Math.max(Math.min(...av),Math.min(...bv))>.001;}));
 },
 transfer(items,original,world,scale,held=null){
  const areas=['A','B',...(items.some(c=>this.wall(c)==='I')?['I']:[])];
  const choices=areas.map(wall=>{
   const o=this.point(wall,0,-original.depth/2),u=this.point(wall,1,-original.depth/2),dx=u[0]-o[0],dy=u[1]-o[1],px=world[0]-o[0],py=world[1]-o[1];
   return {wall,along:px*dx+py*dy,distance:Math.abs(-px*dy+py*dx)};
  }).filter(r=>r.along>=-3);
  const originalRun=choices.find(r=>r.wall===this.wall(original));
  const others=choices.filter(r=>r.wall!==this.wall(original)&&r.distance*scale<=(r.wall===held?30:20)).sort((a,b)=>a.distance-b.distance);
  const target=others[0];if(!target||(originalRun&&originalRun.distance<target.distance+5/scale))return null;
  const c={...original,wall:target.wall,rotation:0,offset_y:0,x:Math.max(0,Math.round((target.along-original.width/2)*8)/8)};
  const edges=items.filter(o=>o.id!==original.id).flatMap(o=>this.polygon(o).map(p=>this.along(target.wall,...p)));
  const options=[...new Set([0,...edges,...edges.map(x=>x-c.width)])].filter(x=>x>=0&&x<=1200&&Math.abs(x-c.x)*scale<=12).sort((a,b)=>Math.abs(a-c.x)-Math.abs(b-c.x));
  const available=options.find(x=>items.every(o=>o.id===c.id||!this.overlap({...c,x},o)));if(available!==undefined)c.x=Math.round(available*1e6)/1e6;
  const placed=items.map(o=>o.id===c.id?c:o);
  const valid=c.x<=1200&&placed.every((a,i)=>placed.slice(i+1).every(b=>!this.overlap(a,b)));
  return {preview:c,items:placed,valid};
 },
 plan(items,original,preview,mode,pointerX=preview.x,tolerance=6,previousSlot=null){
  let placed=items.map(c=>({...c}));
  const moved=placed.find(c=>c.id===original.id);Object.assign(moved,preview);
  let insertion=null,insertionSlot=null;
  if(mode==='insert'&&Math.abs(preview.z-original.z)<.001){
   const row=items.filter(c=>this.wall(c)===this.wall(original)&&Math.abs(c.z-original.z)<.001).sort((a,b)=>a.x-b.x);
   const remaining=row.filter(c=>c.id!==original.id);
   // An actual empty gap takes priority over reordering near its edges.
   const left=remaining.some(c=>c.x+c.width<=preview.x+.001),right=remaining.some(c=>c.x>=preview.x+preview.width-.001);
   const pointerInGap=!remaining.some(c=>pointerX>c.x+.001&&pointerX<c.x+c.width-.001);
   if(left&&right&&pointerInGap&&preview.x>=0&&preview.x<=1200&&placed.every((c,i)=>placed.slice(i+1).every(o=>!this.overlap(c,o))))return {valid:true,items:placed,insertion:null,insertionSlot:null,message:''};
   const slots=remaining.flatMap((c,i)=>[{x:c.x,index:i},{x:c.x+c.width,index:i+1}]);
   // A wider release zone prevents jitter at the insertion boundary.
   const held=previousSlot&&slots.find(s=>s.index===previousSlot.index&&s.x===previousSlot.x&&Math.abs(s.x-pointerX)<=tolerance*1.7);
   const slot=held||slots.filter(s=>Math.abs(s.x-pointerX)<=tolerance).sort((a,b)=>Math.abs(a.x-pointerX)-Math.abs(b.x-pointerX))[0];
   if(slot){
    insertionSlot=slot;
    const from=row.findIndex(c=>c.id===original.id),to=slot.index;
    const order=[...remaining];order.splice(to,0,original);
    const lo=Math.min(from,to),hi=Math.max(from,to);
    let x=row[lo].x;
    for(let i=lo;i<=hi;i++){
     const c=placed.find(p=>p.id===order[i].id);c.x=x;c.z=order[i].z;
     x+=c.width+(i<hi?Math.max(0,row[i+1].x-row[i].x-row[i].width):0);
    }
    insertion=placed.find(c=>c.id===original.id).x;
   }
  }
  const hits=items.filter(c=>c.id!==original.id&&this.overlap(preview,c));
  if(hits.length&&mode==='swap'){
   const target=hits.filter(c=>this.wall(c)===this.wall(original)&&Math.abs(c.z-original.z)<.001).sort((a,b)=>Math.abs(a.x+a.width/2-preview.x-preview.width/2)-Math.abs(b.x+b.width/2-preview.x-preview.width/2))[0];
   if(!target)return {valid:false,items:placed,message:'Swap requires cabinets on the same row.'};
   const row=items.filter(c=>this.wall(c)===this.wall(original)&&Math.abs(c.z-original.z)<.001).sort((a,b)=>a.x-b.x);
   const from=row.findIndex(c=>c.id===original.id),to=row.findIndex(c=>c.id===target.id),lo=Math.min(from,to),hi=Math.max(from,to);
   const section=row.slice(lo,hi+1),gaps=section.slice(1).map((c,i)=>Math.max(0,c.x-section[i].x-section[i].width));
   const reordered=section.filter(c=>c.id!==original.id);reordered.splice(from<to?reordered.length:0,0,original);
   let x=section[0].x;
   for(let i=0;i<reordered.length;i++){const c=placed.find(p=>p.id===reordered[i].id);c.x=x;c.z=reordered[i].z;x+=c.width+(gaps[i]||0);}
  }else if(hits.length&&mode==='push'){
   const direction=preview.x>=original.x?1:-1,queue=[moved];let steps=0;
   while(queue.length&&steps++<items.length*items.length+1){
    const current=queue.shift();
    for(const other of placed){
     if(this.wall(other)!==this.wall(original)||other.id===current.id||other.id===moved.id||!this.overlap(current,other))continue;
     other.x=direction>0?current.x+current.width:current.x-other.width;queue.push(other);
    }
   }
  }
  const valid=placed.every(c=>Number.isFinite(c.x)&&c.x>=0&&c.x<=1200&&(!this.corner(c)||c.x===items.find(o=>o.id===c.id).x))&&placed.every((c,i)=>placed.slice(i+1).every(o=>!this.overlap(c,o)));
  return {valid,items:placed,insertion,insertionSlot,message:valid?'':'Not enough space for this placement.'};
 }
};
