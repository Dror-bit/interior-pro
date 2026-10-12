function planPoint(c,lx,frontDepth,frame){
 const [x,y]=KitchenPlacement.cabinetPoint(c,lx,-frontDepth,frame.local);
 return [frame.ox+x*frame.s,frame.base-y*frame.s];
}
function planDetails(c,frame){
 if(isAppliance(c)||plainPanel(c))return '';
 if(FrontLayouts.corner(c))return ['A','B'].map(wall=>planDetails({...c,wall,x:c.depth,width:c.width-c.depth,kind:c.kind==='corner_upper'?'wall':'doors',front_layout:'single'},frame)).join('');
 const rows=FrontLayouts.rows(c),door=rows.find(r=>r.kind==='doors'),drawer=rows.some(r=>r.kind==='drawer');let out='';
 const point=(x,y)=>planPoint(c,x,y,frame),path=pts=>svg('polyline',{points:pts.map(p=>p.join(',')).join(' '),fill:'none',stroke:'#839a8c','stroke-width':1.3,'stroke-dasharray':'4 3'});
 const leaves=door?(FrontLayouts.corner(c)?1:door.doors):0,available=FrontLayouts.corner(c)?c.width-c.depth:c.width,start=FrontLayouts.corner(c)?c.depth:0;
 for(let i=0;i<leaves;i++){
  const len=available/leaves-.125,left=i===0,hinge=start+(left?0:available),sign=left?1:-1;
  out+=path(Array.from({length:13},(_,j)=>{const a=j*Math.PI/24;return point(hinge+sign*len*Math.cos(a),c.depth+len*Math.sin(a));}));
  const a=point(hinge,c.depth),b=point(hinge,c.depth+len);out+=line(...a,...b,'#839a8c',{'stroke-dasharray':'4 3'});
  if(c.handle!=='none'){
   const hp=handleLayout(c,len,door.height,false,left),p=point(start+i*available/leaves+hp[0]+.16,c.depth+1);
   out+=svg('circle',{cx:p[0],cy:p[1],r:Math.max(2,frame.s*.35),fill:c.handle==='brass'?'#a38344':'#232b26',class:'plan-handle'});
  }
 }
 if(drawer){const a=point(c.width/2,c.depth),b=point(c.width/2,c.depth+12),l=point(c.width/2-2,c.depth+9),r=point(c.width/2+2,c.depth+9);out+=line(...a,...b,'#839a8c',{'stroke-dasharray':'4 3'})+path([l,b,r]);if(c.handle!=='none'){const p=point(c.width/2-2.5,c.depth+1),q=point(c.width/2+2.5,c.depth+1);out+=line(...p,...q,c.handle==='brass'?'#a38344':'#232b26',{'stroke-width':3,class:'plan-handle'});}}
 return svg('g',{'pointer-events':'none',class:'plan-openings'},out);
}
