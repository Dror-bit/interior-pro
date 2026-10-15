// Canvas symbols consume the same cabinet data and FrontLayouts as the planner.
(function(){
 const colors={ivory:'#eeeae0',sage:'#87978b',charcoal:'#3d4549',oak:'#ba9365'};
 function cabinet(row){
  const c=row.cabinet,b=row.basis;if(!c||!b)return;
  const p=(x,y)=>[sx(b[0][0]+x*(b[1][0]-b[0][0])+y*(b[2][0]-b[0][0])),sy(b[0][1]+x*(b[1][1]-b[0][1])+y*(b[2][1]-b[0][1]))];
  const path=(pts,fill=null,stroke='#657367',dash=[],width=1)=>{ctx.setLineDash(dash);ctx.lineWidth=width;ctx.strokeStyle=stroke;ctx.beginPath();pts.forEach(([x,y],i)=>{const q=p(x,y);i?ctx.lineTo(...q):ctx.moveTo(...q);});if(fill){ctx.closePath();ctx.fillStyle=fill;ctx.fill();}ctx.stroke();};
  const rect=(x,y,w,d,fill)=>path([[x,y],[x+w,y],[x+w,y+d],[x,y+d],[x,y]],fill);
  const circle=(x,y,r,fill)=>path(Array.from({length:25},(_,i)=>[x+r*Math.cos(i*Math.PI/12),y+r*Math.sin(i*Math.PI/12)]),fill);
  const w=c.width,d=c.depth,corner=FrontLayouts.corner(c),upper=['wall','corner_upper'].includes(c.kind),appliance=['fridge','oven','wall_oven','dishwasher','hood','microwave'].includes(c.kind);
  const category=c.appliance?.category||({oven:'range'}[c.kind]||c.kind),overhead=category==='hood';
  const shape=corner?[[0,0],[w,0],[w,d],[d,d],[d,w],[0,w]]:[[0,0],[w,0],[w,d],[0,d]];
  ctx.globalAlpha=upper?.55:1;path(shape,overhead?null:appliance?'#e5ebed':colors[c.finish]||colors.ivory,'#657367',upper||overhead?[5,3]:[]);ctx.globalAlpha=1;
  if(!corner&&!overhead)path([[0,d-.75],[w,d-.75],[w,d],[0,d]],null,'#52665a');
  const hardware=c.handle==='brass'?'#a38344':'#303a3d';
  function front(x,y,width,turn=false,single=false){
   let rows;try{rows=FrontLayouts.rows(c);}catch{rows=[];}
   const door=rows.find(r=>r.kind==='doors'),drawer=rows.some(r=>r.kind==='drawer');
   const local=(u,v)=>turn?[y+v,x+u]:[x+u,y+v];
   const line=pts=>{if(window.KitchenShowDoorSwings===true)path(pts.map(q=>local(...q)),null,'#8b9e92',[4,3]);};
   const leaves=single?1:door?.doors||0;
   for(let i=0;i<leaves;i++){
    const left=i===0,len=width/leaves-.125,hinge=left?0:width,sign=left?1:-1;
    line(Array.from({length:17},(_,j)=>{const a=j*Math.PI/32;return [hinge+sign*len*Math.cos(a),len*Math.sin(a)];}));
    line([[hinge,0],[hinge,len]]);
    if(leaves===2)path([local(width/2,0),local(width/2,-.75)],null,'#52665a');
    if(c.handle!=='none'){const edge=c.handle_side??1.125;const q=local(left?width/leaves-edge:width/leaves+edge,1);circle(q[0],q[1],.45,hardware);}
   }
   if(drawer&&c.kind!=='sink'){line([[width/2,0],[width/2,10]]);line([[width/2-2,7],[width/2,10],[width/2+2,7]]);if(c.handle!=='none')path([local(width/2-2.5,1),local(width/2+2.5,1)],null,hardware,[],2.3);}
  }
  if(c.pullout){
   if(c.handle!=='none')path([[w/2-2,d+1],[w/2+2,d+1]],null,hardware,[],2.3);
   ctx.setLineDash([]);return;
  }
  if(!appliance&&!['filler','corner'].includes(c.kind)){if(corner){front(d,d,w-d,false,true);front(d,d,w-d,true,true);}else front(0,d,w);}
  // Deliberate plan symbols, rather than hundreds of overlapping mesh bounds.
  const ink='#465d68',light='#f3f6f7';
  const line=pts=>path(pts,null,ink,[],1.15);
  const handle=(left=.3,right=.7)=>path([[w*left,d-1.5],[w*right,d-1.5]],null,ink,[],2);
  if(c.appliance?.panel_ready){
   for(const part of c.appliance_parts||[]){if(part.panel_id)rect(part.x,-part.y-part.depth,part.width,part.depth,part.color);}
   ctx.setLineDash([]);return;
  }
  if(category==='range'||category==='cooktop'){
   const dim=c.appliance?.dimensions,ww=category==='cooktop'&&dim?dim.width:w-2,dd=category==='cooktop'&&dim?dim.depth:d-3;
   const x=(w-ww)/2,y=category==='cooktop'?(d-dd)/2:1;
   rect(x,y,ww,dd,light);
   let burners=(c.appliance_parts||[]).filter(part=>/burner.*cap|cooking zone/i.test(part.name||''));
   burners=burners.map(part=>({x:part.x+part.width/2,y:-part.y-part.depth/2,r:Math.min(part.width,part.depth)/2}));
   if(!burners.length){const n=c.appliance?.appearance?.burners||4;const slots=n===6?[[.2,.25],[.5,.25],[.8,.25],[.2,.65],[.5,.65],[.8,.65]]:[[.25,.25],[.75,.25],[.25,.65],[.75,.65]];if(n===5)slots.push([.5,.45]);burners=slots.map(([a,b])=>({x:x+ww*a,y:y+dd*b,r:Math.min(ww,dd)*.095}));}
   for(const b of burners){const r=Math.max(.65,b.r);circle(b.x,b.y,r,'#d4dfe3');circle(b.x,b.y,r*.48,ink);for(const [a,b1,a1,b2] of [[-1.3,0,-.65,0],[.65,0,1.3,0],[0,-1.3,0,-.65],[0,.65,0,1.3]])line([[b.x+a*r,b.y+b1*r],[b.x+a1*r,b.y+b2*r]]);}
   for(let i=0;i<Math.min(6,burners.length);i++)circle(x+ww*(i+1)/(Math.min(6,burners.length)+1),y+dd-1,.45,ink);
   if(category==='range')handle(.18,.82);
  }else if(category==='fridge'){
   const split=c.appliance?.appearance?.configuration==='side_by_side'?w*.43:w/2,front=d*.89;
   line([[0,front],[w,front]]);line([[split,front],[split,d]]);
   path([[split-2.3,d],[split-2.3,d+.8],[split-.6,d+.8]],null,ink,[],2);
   path([[split+2.3,d],[split+2.3,d+.8],[split+.6,d+.8]],null,ink,[],2);
   const cx=w/2,cy=d*.45,r=Math.min(w,d)*.13;
   for(let i=0;i<6;i++){const a=i*Math.PI/3,ux=Math.cos(a),uy=Math.sin(a),px=-uy,py=ux;
    line([[cx,cy],[cx+r*ux,cy+r*uy]]);
    line([[cx+r*(.72*ux+.23*px),cy+r*(.72*uy+.23*py)],[cx+r*.48*ux,cy+r*.48*uy],[cx+r*(.72*ux-.23*px),cy+r*(.72*uy-.23*py)]]);
   }
  }else if(category==='dishwasher'){
   rect(2,2,w-4,d-5,light);for(let i=0;i<5;i++){const x=4+(w-8)*i/4;line([[x,4],[x,d-5]]);}
   circle(w/2,d*.48,Math.min(w,d)*.19,'#e1e9ec');line([[w*.32,d*.4],[w*.68,d*.56]]);line([[w*.32,d*.56],[w*.68,d*.4]]);handle();
   for(let i=0;i<3;i++)circle(w-4-i*1.6,d-1.5,.3,ink);
  }else if(category==='hood'){
   const cx=w/2,cy=d*.48,r=Math.min(w,d)*.14;
   path([[1,1],[w-1,1],[w-1,d-1],[1,d-1],[1,1]],null,ink,[4,3]);
   for(const [x,y] of [[1,1],[w-1,1],[w-1,d-1],[1,d-1]])path([[x,y],[cx+(x<cx?-r:r),cy+(y<cy?-r:r)]],null,'#81949c',[3,3]);
   circle(cx,cy,r,null);for(let i=0;i<3;i++){const a=i*Math.PI*2/3;line([[cx,cy],[cx+r*.75*Math.cos(a),cy+r*.75*Math.sin(a)]]);}
  }else if(category==='wall_oven'){
   rect(2,2,w-4,d-5,light);for(const yy of [.3,.48,.66])line([[4,d*yy],[w-4,d*yy]]);rect(3,d-4,w-6,1.2,'#6b828d');handle(.2,.8);
  }else if(category==='microwave'){
   rect(2,2,w-7,d-5,light);circle((w-3)/2,d*.46,Math.min(w-8,d-6)*.29,null);line([[w-5,2],[w-5,d-3]]);for(let i=0;i<3;i++)circle(w-2.5,4+i*2,.45,ink);handle(.2,.7);
  }else for(const part of c.appliance_parts||[]){if(part.shape==='cylinder')circle(part.x+part.width/2,-part.y-part.depth/2,part.width/2,part.color);else rect(part.x,-part.y-part.depth,part.width,part.depth,part.color);}
  if(c.kind==='sink'&&c.sink&&c.sink.type!=='none'){
   const s={width:Math.min(30,w-4),depth:Math.min(18,d-6),offset_x:0,front_setback:2,...c.sink};const x=(w-s.width)/2+s.offset_x,y=d-s.front_setback-s.depth;
   rect(x,y,s.width,s.depth,s.finish==='white'?'#f4f3ed':'#b6c3c9');rect(x+.6,y+.6,s.width-1.2,s.depth-1.2,s.finish==='white'?'#d8dedc':'#82969e');
   if(s.type==='double')path([[x+s.width/2,y],[x+s.width/2,y+s.depth]],null,'#e0e8e9',[],2);
   if(s.drain_centres)for(const [dx,dy] of s.drain_centres)circle(x+dx,y-dy,.6,'#3b494f');
   else for(const t of s.type==='double'?[.25,.75]:[.5])circle(x+s.width*t,y+s.depth/2,.6,'#3b494f');
   if(s.faucet!=='none')path([[w/2,y-1.5],[w/2,y+3.5]],null,'#52656e',[],2);
  }
  for(const accessory of c.accessories||[]){
   const [x,y]=accessory.anchor,a=(accessory.angle||0)*Math.PI/180,p=accessory.snapshot,reach=p.manufacturer_outlet_reach_in||4;
   const rgb=accessory.finish_palette?.[accessory.material_mapping?.body_material||accessory.finish_id]?.rgb||[100,110,115],color='rgb('+rgb.join(',')+')';
   circle(x,-y,.65,color);path([[x,-y],[x+Math.sin(a)*reach,-y+Math.cos(a)*reach]],null,color,[],2.4);
  }
 }
 let rows=window.KitchenSymbols?.rows||[];
 window.KitchenSymbols={get rows(){return rows;},draw(){if(activePage!==0)return;ctx.save();try{for(const row of rows){if(row.cabinet)cabinet(row);else{ctx.beginPath();row.polygon.forEach((q,i)=>i?ctx.lineTo(sx(q[0]),sy(q[1])):ctx.moveTo(sx(q[0]),sy(q[1])));ctx.closePath();ctx.fillStyle='#eeeae0';ctx.fill();ctx.stroke();}}}finally{ctx.restore();}},load(payload){rows=payload.cabinets||[];}};
 if(!window.KP._symbolLoad){const load=window.KP.load;window.KP.load=function(payload){window.KitchenSymbols.load(payload);window.KitchenSidebar?.load(payload);return load.call(this,payload);};window.KP._symbolLoad=true;}
 window.KP.draw=()=>window.KitchenSymbols.draw();
})();
