let sinkParts=null;
function automaticSinkParts(count){
 const usable=columns.map((c,i)=>c.kind==='makeup'?-1:i).filter(i=>i>=0);
 if(!usable.length)return [];
 if(count===2)return [usable[0],usable.at(-1)];
 return [usable.sort((a,b)=>Math.abs(a-(columns.length-1)/2)-Math.abs(b-(columns.length-1)/2)||(columns[a].kind==='doors'?0:1)-(columns[b].kind==='doors'?0:1))[0]];
}
function syncSinkLocations(){
 columns.forEach(c=>{if(c.door_handle_sides&&['doors','doors_drawer'].includes(c.kind))c.door_handle_sides=Array.from({length:c.count},(_,i)=>c.door_handle_sides[i]||'auto');});
 const col=columns[selectedColumn],doorPanel=el('doorHandleSides');
 el('handlePartTitle').textContent=`מיקום הידיות בחלק ${selectedColumn+1} שנבחר בשרטוט`;
 doorPanel.hidden=!['doors','doors_drawer'].includes(col.kind)||el('product').value!=='vanity'||current()?.product_id==='gallery';
 doorPanel.replaceChildren();
 if(!doorPanel.hidden)for(let i=0;i<col.count;i++){
  const label=document.createElement('label');label.textContent=`צד ידית — דלת ${i+1} (משמאל)`;
  const select=document.createElement('select');select.dataset.doorIndex=i;
  select.replaceChildren(new Option('אוטומטי','auto'),new Option('ימין','right'),new Option('שמאל','left'));select.value=col.door_handle_sides?.[i]||'auto';label.append(select);doorPanel.append(label);
 }
 const count=Number(el('basins').value),usable=columns.map((c,i)=>c.kind==='makeup'?-1:i).filter(i=>i>=0);
 if(sinkParts&&(sinkParts.length!==count||sinkParts.some(i=>!usable.includes(i))))sinkParts=null;
 el('sinkLocations').hidden=el('product').value!=='vanity'||current()?.product_id==='gallery';
 const chosen=sinkParts||automaticSinkParts(count);
 [0,1].forEach(n=>{
  const select=el('sinkPart'+n);select.parentElement.hidden=n>=count;
  select.replaceChildren(new Option('אוטומטי',''),...usable.map(i=>new Option(`חלק ${i+1}${i===0?' — שמאל':i===columns.length-1?' — ימין':''}`,i)));
  select.value=sinkParts?String(chosen[n]):'';
 });
}
document.addEventListener('DOMContentLoaded',()=>{
 el('doorHandleSides').addEventListener('change',e=>{
  const i=Number(e.target.dataset.doorIndex);if(!Number.isInteger(i))return;
  const c=columns[selectedColumn];c.door_handle_sides=c.door_handle_sides||Array(c.count).fill('auto');c.door_handle_sides[i]=e.target.value;update();
 });
 [0,1].forEach(n=>el('sinkPart'+n).addEventListener('change',()=>{
  const value=el('sinkPart'+n).value;
  if(value==='')sinkParts=null;
  else{sinkParts=sinkParts||automaticSinkParts(Number(el('basins').value));sinkParts[n]=Number(value);}
  update();
 }));
});
