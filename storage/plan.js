(function(){
  if(window.StoragePlan)return;
  let rows=[],armed=null,selected=null,gesture=null,preview=null,pending=false;
  const key=r=>JSON.stringify([r.domain,r.assembly_id,r.id]);
  const note=document.createElement('div');note.id='storage-plan-note';note.style.cssText='position:absolute;right:20px;bottom:20px;background:white;border:1px solid #315e50;border-radius:6px;padding:9px;color:#315e50;pointer-events:none;display:none';document.getElementById('canvasWrap').append(note);
  const message=t=>{note.textContent=t||'';note.style.display=t?'block':'none';};
  const world=e=>{const r=cv.getBoundingClientRect();return [mx(e.clientX-r.left),my(e.clientY-r.top)];};
  const inside=(p,poly)=>{let hit=false;for(let i=0,j=poly.length-1;i<poly.length;j=i++){const a=poly[i],b=poly[j];if((a[1]>p[1])!==(b[1]>p[1])&&p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0])hit=!hit;}return hit;};
  const hit=(p,cycle=false)=>{const found=[...rows].reverse().filter(r=>inside(p,r.polygon));const index=found.findIndex(r=>key(r)===selected);return found[index<0?0:(cycle?(index+1)%found.length:index)];};
  const snap=n=>Math.round(n*8)/8;
  function outline(r){ctx.beginPath();r.polygon.forEach((p,i)=>i?ctx.lineTo(sx(p[0]),sy(p[1])):ctx.moveTo(sx(p[0]),sy(p[1])));ctx.closePath();}
  function send(action,row,values={}){pending=true;sketchup.storage_plan(JSON.stringify({action,domain:row.domain,assembly_id:row.assembly_id,revision:row.revision,id:row.id,...values}));}
  function reset(){gesture=null;preview=null;draw();}
  function proposed(e){const p=world(e),c=gesture.row.cabinet;return {x:snap(c.position.x+p[0]-gesture.start[0]),y:snap(c.position.y+p[1]-gesture.start[1])};}
  window.StoragePlan={
    load(data){rows=[...(data.cabinets||[])].sort((a,b)=>(a.cabinet.position.z||0)-(b.cabinet.position.z||0));const wasArmed=!!armed;armed=data.armed||null;if(armed&&!wasArmed){setMode('sel');selected=null;}if(selected&&!rows.some(r=>key(r)===selected))selected=null;gesture=null;preview=null;message(armed?'Storage: click the cabinet back-left corner. Esc cancels.':'');draw();},
    draw(){if(activePage!==0)return;ctx.save();try{ctx.lineWidth=1;ctx.setLineDash([]);for(const r of rows){ctx.fillStyle=r.domain==='wardrobe'?'#e4dacb':'#d5e4e7';ctx.strokeStyle=key(r)===selected?'#245b45':'#7a766e';const upper=r.cabinet.product_id==='upper';ctx.setLineDash(upper?[5,3]:[]);outline(r);if(!upper)ctx.fill();ctx.stroke();ctx.setLineDash([]);const p=r.polygon;ctx.beginPath();ctx.moveTo(sx(p[2][0]),sy(p[2][1]));ctx.lineTo(sx(p[3][0]),sy(p[3][1]));ctx.lineWidth=3;ctx.stroke();ctx.lineWidth=1;if(key(r)===selected&&r.clearance){ctx.strokeStyle='#b07a35';ctx.setLineDash([3,4]);outline({polygon:r.clearance});ctx.stroke();ctx.setLineDash([]);}if(Math.abs(sx(p[1][0])-sx(p[0][0]))+Math.abs(sy(p[1][1])-sy(p[0][1]))>30){ctx.fillStyle='#315e50';ctx.font='11px Arial';ctx.textAlign='center';const label=upper?'Upper '+r.cabinet.position.z+'in':({washer:'W',washer_top:'Top load',dryer:'D',dryer_rear:'D',stack:'W/D',pair_front:'W + D',pair_top:'Top load + D'}[r.cabinet.product_id]||'');const mid=upper?[(p[0][0]+p[1][0])/2,(p[0][1]+p[1][1])/2]:p.reduce((a,v)=>[a[0]+v[0]/4,a[1]+v[1]/4],[0,0]);ctx.fillText(label,sx(mid[0]),sy(mid[1])-4);}}if(preview){ctx.strokeStyle='#245b45';ctx.lineWidth=2;ctx.setLineDash([5,3]);outline(preview);ctx.stroke();}}finally{ctx.restore();}},
    clearSelection(){selected=null;gesture=null;preview=null;},
    result(error){pending=false;reset();message(error||(armed?'Storage: click to place. Esc cancels.':''));if(typeof armHiddenUndo==='function')armHiddenUndo();},
    get state(){return {selected,pending,armed,dragging:!!gesture,rows};}
  };
  const originalSelect=setSel;setSel=function(){window.StoragePlan.clearSelection();return originalSelect.apply(this,arguments);};
  cv.addEventListener('mousedown',e=>{
    if(activePage!==0||mode!=='sel'||e.button!==0||e.ctrlKey||e.metaKey||e.shiftKey||pending)return;
    const p=world(e);
    if(armed){e.preventDefault();e.stopImmediatePropagation();send('place',armed,{x:snap(p[0]),y:snap(p[1])});return;}
    if(typeof hitOpening==='function'&&hitOpening({x:p[0],y:p[1]}))return;
    const row=hit(p,e.altKey);if(!row){selected=null;return;}
    e.preventDefault();e.stopImmediatePropagation();setSel(null);window.KitchenHouseDrag?.clearSelection();selected=key(row);gesture={row,start:p,screen:[e.clientX,e.clientY],moved:false};cv.tabIndex=0;cv.focus({preventScroll:true});draw();
  },true);
  window.addEventListener('mousemove',e=>{if(!gesture)return;e.preventDefault();e.stopImmediatePropagation();if(!gesture.moved&&Math.hypot(e.clientX-gesture.screen[0],e.clientY-gesture.screen[1])<4)return;gesture.moved=true;const p=proposed(e),c=gesture.row.cabinet.position;preview={...gesture.row,polygon:gesture.row.polygon.map(v=>[v[0]+p.x-c.x,v[1]+p.y-c.y])};draw();},true);
  window.addEventListener('mouseup',e=>{if(!gesture)return;e.preventDefault();e.stopImmediatePropagation();const g=gesture,p=proposed(e);reset();if(g.moved)send('move',g.row,p);},true);
  cv.addEventListener('dblclick',e=>{if(activePage!==0||mode!=='sel'||armed||pending)return;const row=hit(world(e));if(!row)return;e.preventDefault();e.stopImmediatePropagation();send('edit',row);},true);
  window.addEventListener('keydown',e=>{
    if(e.target?.closest?.('input,textarea,select,[contenteditable]:not([contenteditable="false"]):not(#hiddenUndo)')||document.querySelector('dialog[open]'))return;
    if(e.key==='Escape'&&(armed||gesture)){e.preventDefault();e.stopImmediatePropagation();if(armed){armed=null;send('cancel',{});}reset();message('');return;}
    if(e.key!=='Delete'||activePage!==0||mode!=='sel'||!selected||e.repeat||pending||e.ctrlKey||e.metaKey||e.altKey||e.shiftKey)return;
    const row=rows.find(r=>key(r)===selected);if(!row)return;e.preventDefault();e.stopImmediatePropagation();send('remove',row);
  },true);
  window.addEventListener('blur',()=>{if(gesture)reset();});
})();
