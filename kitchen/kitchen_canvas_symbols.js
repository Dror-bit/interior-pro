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
  const shape=corner?[[0,0],[w,0],[w,d],[d,d],[d,w],[0,w]]:[[0,0],[w,0],[w,d],[0,d]];
  ctx.globalAlpha=upper?.55:1;path(shape,appliance?'#d9e0e2':colors[c.finish]||colors.ivory,'#657367',upper?[5,3]:[]);ctx.globalAlpha=1;
  if(!corner)path([[0,d-.75],[w,d-.75],[w,d],[0,d]],null,'#52665a');
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
   if(drawer){line([[width/2,0],[width/2,10]]);line([[width/2-2,7],[width/2,10],[width/2+2,7]]);if(c.handle!=='none')path([local(width/2-2.5,1),local(width/2+2.5,1)],null,hardware,[],2.3);}
  }
  if(!appliance&&!['filler','corner'].includes(c.kind)){if(corner){front(d,d,w-d,false,true);front(d,d,w-d,true,true);}else front(0,d,w);}
  for(const part of c.appliance_parts||[]){if(part.shape==='cylinder')circle(part.x+part.width/2,-part.y-part.depth/2,part.width/2,part.color);else rect(part.x,-part.y-part.depth,part.width,part.depth,part.color);}
  if(appliance&&!c.appliance_parts?.length){
   if(c.kind==='oven'){rect(1,1,w-2,d-4,'#bcc5c7');for(const x of [w*.25,w*.75])for(const y of [d*.28,d*.65]){circle(x,y,Math.min(w,d)*.12,'#59666b');circle(x,y,Math.min(w,d)*.075,'#aeb9bc');}}
   else if(c.kind==='fridge'){path([[w/2,d],[w/2,d-4]],null,'#59666b');path([[w/2-2,d+1],[w/2-2,d-2]],null,hardware,[],2);path([[w/2+2,d+1],[w/2+2,d-2]],null,hardware,[],2);}
   else {rect(2,2,w-4,d-5,c.kind==='hood'?'#c4ccce':'#afbdc2');path([[w*.3,d-1],[w*.7,d-1]],null,hardware,[],2);}
  }
  if(c.kind==='sink'&&c.sink&&c.sink.type!=='none'){
   const s={width:Math.min(30,w-4),depth:Math.min(18,d-6),offset_x:0,front_setback:2,...c.sink};const x=(w-s.width)/2+s.offset_x,y=d-s.front_setback-s.depth;
   rect(x,y,s.width,s.depth,'#b6c3c9');rect(x+.6,y+.6,s.width-1.2,s.depth-1.2,'#82969e');
   if(s.type==='double')path([[x+s.width/2,y],[x+s.width/2,y+s.depth]],null,'#e0e8e9',[],2);
   for(const t of s.type==='double'?[.25,.75]:[.5])circle(x+s.width*t,y+s.depth/2,.6,'#3b494f');
   if(s.faucet!=='none')path([[w/2,y-1.5],[w/2,y+3.5]],null,'#52656e',[],2);
  }
 }
 let rows=window.KitchenSymbols?.rows||[];
 window.KitchenSymbols={get rows(){return rows;},draw(){if(activePage!==0)return;ctx.save();try{for(const row of rows){if(row.cabinet)cabinet(row);else{ctx.beginPath();row.polygon.forEach((q,i)=>i?ctx.lineTo(sx(q[0]),sy(q[1])):ctx.moveTo(sx(q[0]),sy(q[1])));ctx.closePath();ctx.fillStyle='#eeeae0';ctx.fill();ctx.stroke();}}}finally{ctx.restore();}},load(payload){rows=payload.cabinets||[];}};
 if(!window.KP._symbolLoad){const load=window.KP.load;window.KP.load=function(payload){window.KitchenSymbols.load(payload);window.KitchenSidebar?.load(payload);return load.call(this,payload);};window.KP._symbolLoad=true;}
 window.KP.draw=()=>window.KitchenSymbols.draw();
})();
