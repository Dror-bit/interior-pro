const legacySurfaceDefaults={countertop_color:'white',countertop_thickness:.75,backsplash_height:0,sink_width:17,sink_depth:12,sink_height:6,sink_color:'white',sink_shape:'oval',faucet_finish:'brushed_nickel'};
const surfaceDefaults={...legacySurfaceDefaults,sink_shape:'icera_muse',sink_width:18.125,sink_depth:12.25,sink_height:7.875};
const colors={matte_black:'#25272a',brushed_nickel:'#b8b6af',satin_brass:'#c4a568',white:'#faf9f4',ivory:'#e5dfd0',gray:'#9ba39e',black:'#282c2d',white_oak:'#d9c7a9',chrome:'#b9c4cb',brass:'#b39456'};
function surfaces(){return Object.fromEntries(Object.entries(surfaceDefaults).map(([k,v])=>[k,typeof v==='number'?Number(el(k).value):el(k).value]));}
function columnLayout(cols,total){let x=0;return cols.map(c=>{const width=c.width??total/cols.length,row={x,width};x+=width;return row;});}
function sinkCenters(v){
 if(el('product').value==='makeup')return [];
 const usable=columns.map((c,i)=>c.kind==='makeup'?-1:i).filter(i=>i>=0),layout=columnLayout(columns,v.width);
 if(!usable.length)return [];
 if(v.sink_parts){
  const indices=v.sink_parts;
  if(indices.length===2&&indices[0]===indices[1]){const {x,width}=layout[indices[0]];return [x+width/4,x+3*width/4];}
  return indices.map(i=>layout[i].x+layout[i].width/2).sort((a,b)=>a-b);
 }
 if(v.basins===2&&usable.length===1){const {x,width}=layout[usable[0]];return [x+width/4,x+3*width/4];}
 if(v.basins===2)return [usable[0],usable.at(-1)].map(i=>layout[i].x+layout[i].width/2);
 const i=usable.sort((a,b)=>Math.abs(a-(columns.length-1)/2)-Math.abs(b-(columns.length-1)/2)||(columns[a].kind==='doors'?0:1)-(columns[b].kind==='doors'?0:1))[0];
 return [layout[i].x+layout[i].width/2];
}
function frontSvg(v,cols,mini=false){
 const W=300,H=150,px=W/(v.width||36),py=H/(v.height||30),fill=v.finish==='white_oak'?'url(#oak)':colors[v.finish]||colors.white;
 let out='';const make=el('product').value==='makeup';
 if(v.mount==='floor'&&v.legs){
  const runs=make?[{kind:'doors'}]:cols,layout=columnLayout(runs,v.width||36);
  runs.forEach((col,i)=>{
   if(col.kind==='makeup')return;
   const {x,width:bay}=layout[i];
   if(v.leg_style==='plinth'){out+=rect((x+.75)*px,H,(bay-1.5)*px,(v.support_height||4)*py,fill);return;}
   const leg=(lx)=>v.leg_style==='round'?`<rect data-support="round" x="${lx}" y="${H}" width="${1.5*px}" height="${(v.support_height||4)*py}" rx="${.75*px}" fill="${fill}" stroke="#777f74"/>`:rect(lx,H,1.5*px,(v.support_height||4)*py,fill);
   if(i===0||runs[i-1].kind==='makeup')out+=leg((x+1)*px);
   if(i===runs.length-1||runs[i+1].kind==='makeup')out+=leg((x+bay-2.5)*px);
  });
 }
 const draw=(fx,fy,fw,fh,drawer,i,handleLeft=false)=>{
  out+=rect(fx,fy,fw,fh,fill,mini?'':`data-column="${i}" style="cursor:pointer"`);
  if(v.style==='shaker')out+=rect(fx+2*px,fy+2*py,Math.max(1,fw-4*px),Math.max(1,fh-4*py),fill,'pointer-events="none"');
  if(['keaton','warwick','globe','hunter'].includes(v.handle)){
   const cx=drawer?fx+fw/2:(handleLeft?fx+px:fx+fw-px),cy=drawer?(v.style==='shaker'&&['keaton','warwick'].includes(v.handle)?fy+py:fy+fh/2):fy+Math.min(3*py,fh/2);
   out+=`<g class="preview-handle" pointer-events="none" transform="translate(${cx} ${cy}) scale(${px} ${py}) rotate(${!drawer&&['keaton','warwick'].includes(v.handle)?(handleLeft?90:-90):0})">${handlePreview[v.handle]}</g>`;
  }else if(v.handle&&v.handle!=='none')out+=rect(fx+fw/2-9,fy+fh/2,18,2,colors[v.handle]||colors.brass);
 };
 const actual=make?[{kind:'makeup',count:v.drawer?1:0}]:cols,layout=columnLayout(actual,v.width||36);
 actual.forEach((col,i)=>{
  const x=layout[i].x*px,bw=layout[i].width*px,n=col.count;
  const left=j=>{const side=col.door_handle_sides?.[j]||'auto';return side==='left'||(side==='auto'&&j%2===1);};
  if(col.kind==='makeup'){
   const extension=v.mount==='floor'?(v.legs?(v.support_height||4)*py:0):(v.position?.z||0)*py;
   if(i===0)out+=rect(x,0,.75*px,H+extension,fill);
   if(i===actual.length-1)out+=rect(x+bw-.75*px,0,.75*px,H+extension,fill);
   if(n)draw(x+2,1,bw-4,4.875*py,true,i);
   if(!mini)out+=`<text x="${x+bw/2}" y="110" text-anchor="middle" fill="#667768" font-size="11" data-column="${i}">מייק־אפ</text>`;
  }else if(col.kind==='doors_drawer'){
   const drawerHeight=5*py;
   draw(x+2,2,bw-4,drawerHeight-2,true,i);
   for(let j=0;j<n;j++)draw(x+j*bw/n+2,drawerHeight+2,bw/n-4,H-drawerHeight-4,false,i,left(j));
  }else for(let j=0;j<n;j++){
   const drawer=col.kind==='drawers';
   draw(x+(drawer?0:j*bw/n)+2,(drawer?j*H/n:0)+2,(drawer?bw:bw/n)-4,(drawer?H/n:H)-4,drawer,i,!drawer&&left(j));
  }
  if(!mini&&i===selectedColumn&&!make)out+=`<rect data-column="${i}" x="${x+1}" y="1" width="${bw-2}" height="148" fill="none" stroke="#315f4f" stroke-width="2"/>`;
 });
 return out;
}
function previewDimensions(v,x,ratio,bottom){
 const fmt=n=>`${Number(n.toFixed(3))}″`,width=300*ratio;
 const line=(a,b,y,label,attr='')=>`<g ${attr}><path d="M${a} ${y-4}v8m0 -4H${b}m0 -4v8" fill="none" stroke="#52685b"/><text x="${(a+b)/2}" y="${y-7}" text-anchor="middle" direction="ltr" font-size="12" fill="#283c32">${label}</text></g>`;
 const parts=el('product').value==='makeup'?[{width:v.width}]:columns;
 const top=95+Math.min(18,v.position.z),height=150*v.height/30,hx=x-16;
 const dx=x+width+18,dy=top-v.surfaces.countertop_thickness*5,ex=dx+18*ratio,ey=dy-50*v.height/30;
 const angle=Math.atan2(ey-dy,ex-dx)*180/Math.PI;
 const vertical=`<g data-dimension="height" role="button" tabindex="0" style="cursor:text"><path d="M${x-3} ${top}H${hx-4}m4 0v${height}m-4 0H${x-3}" fill="none" stroke="#52685b"/><text transform="translate(${hx-6} ${top+height/2}) rotate(-90)" text-anchor="middle" direction="ltr" font-size="12" fill="#283c32">${fmt(v.height)}</text></g>`;
 const depth=`<g data-dimension="depth" role="button" tabindex="0" style="cursor:text"><path d="M${dx-4} ${dy}h8m-4 0L${ex} ${ey}m-4 0h8" fill="none" stroke="#52685b"/><text transform="translate(${(dx+ex)/2+12} ${(dy+ey)/2}) rotate(${angle})" text-anchor="middle" direction="ltr" font-size="12" fill="#283c32">${fmt(v.depth)}</text></g>`;
 return `<g class="preview-dimensions">${vertical}${depth}${columnLayout(parts,v.width).map((c,i)=>line(x+c.x/v.width*width,x+(c.x+c.width)/v.width*width,bottom-53,fmt(c.width),`data-column="${i}" data-dimension="part" role="button" tabindex="0" style="cursor:text"`)).join('')}${line(x,x+width,bottom-20,fmt(v.width),'data-dimension="total"')}</g>`;
}
function renderPreview(v,imported){
 if(imported)return '<svg viewBox="0 0 400 330"><text x="200" y="110" text-anchor="middle">ארון מהגלריה · מידות מקוריות</text></svg>';
 const s=v.surfaces,W=300,px=W/v.width,py=150/v.height,depth=50,th=s.countertop_thickness*py,bh=s.backsplash_height*py;
 const ratio=Math.min(1.1,Math.max(.6,v.width/36)),x=200-150*ratio,top=colors[s.countertop_color],fill=v.finish==='white_oak'?'url(#oak)':colors[v.finish];
 const accessoryRise=accessoryItems.length?Math.max(...accessoryItems.map(a=>(accessoryPosition(a,v).above+a.height)*5))+60:0;
 const bottom=Math.max(350,95+Math.min(18,v.position.z)+(150+(v.mount==='floor'&&v.legs?v.support_height*150/v.height:0))*v.height/30+85);
 let sinks='';
 for(const center of sinkCenters(v)){
  if(s.sink_shape==='icera_muse'){sinks+=museSvg(basinPreview(v,sinkCenters(v).indexOf(center)),center,sinkCenters(v).indexOf(center));continue;}
  const cx=center*px+9,rx=s.sink_width*px/2,ry=s.sink_depth/v.depth*depth/2,cy=-th-depth/2;
  const bowl=(x,y,a,b,color)=>s.sink_shape==='square'?`<rect x="${x-a}" y="${y-b}" width="${a*2}" height="${b*2}" rx="${a*.22}" ry="${b*.22}" fill="${color}" stroke="#778078"/>`:`<ellipse cx="${x}" cy="${y}" rx="${a}" ry="${b}" fill="${color}" stroke="#778078"/>`;
  sinks+=`${bowl(cx,cy,rx,ry,'#5c6665')}
  ${bowl(cx,cy+Math.min(4,s.sink_height*.6),rx*.85,ry*.75,colors[s.sink_color])}
  <ellipse cx="${cx}" cy="${cy+Math.min(4,s.sink_height*.6)}" rx="${Math.max(2,.8*px)}" ry="2" fill="${colors[basinPreview(v,sinkCenters(v).indexOf(center)).surfaces.faucet_finish]}" stroke="#717876" stroke-width=".5"/>`;
 }
 return `<svg viewBox="-20 ${-20-accessoryRise} 460 ${bottom+20+accessoryRise}" role="img"><defs><pattern id="oak" width="80" height="120" patternUnits="userSpaceOnUse"><image href="textures/white_oak.jpg" width="120" height="80" transform="translate(80 0) rotate(90)"/></pattern></defs>
 <ellipse cx="200" cy="310" rx="150" ry="9" fill="#d8dcd2"/>
 <g transform="translate(${x} ${95+Math.min(18,v.position.z)}) scale(${ratio} ${v.height/30})">
 <path d="M300 0L318 -${depth}V${150-depth}L300 150Z" fill="${fill}" stroke="#899185"/>
 ${accessorySvg(v)}
 ${frontSvg(v,columns)}
 <path d="M0 0V-${th}L18 -${depth+th}H318V-${depth}L300 0Z" fill="${top}" stroke="#899185"/>
 <path d="M0 -${th}L18 -${depth+th}H318L300 -${th}Z" fill="${top}" stroke="#899185"/>
 ${sinks}
 ${bh>0?`<path d="M18 -${depth+th}V-${depth+th+bh}H318V-${depth+th}Z" fill="${top}" stroke="#899185"/>`:''}
 ${faucetSvg(v)}
 </g>${previewDimensions(v,x,ratio,bottom)}<text x="200" y="${bottom-2}" text-anchor="middle" font-size="10" fill="#687568">גובה ${v.height}″ · עומק ${v.depth}″ · משטח ${s.countertop_thickness}″</text></svg>`;
}
