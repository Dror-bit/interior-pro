// Delegated capture keeps the existing part-selection listener from redrawing
// the clicked SVG before its inline editor has been positioned.
function editPreviewDimension(target){
 if(current()?.product_id==='gallery')return;
 const kind=target.dataset.dimension;
 if(!['part','height','depth'].includes(kind))return;
 document.getElementById('dimensionInput')?.blur();
 const part=Number(target.dataset.column),makeup=el('product').value==='makeup';
 const field=kind==='part'?(makeup?'width':'columnWidth'):kind;
 const previous=kind==='part'&&!makeup?columns[part].width:Number(el(field).value);
 const bounds=(target.querySelector('text')||target).getBoundingClientRect();
 const input=document.createElement('input');input.id='dimensionInput';input.type='number';input.step='0.125';input.value=previous;
 input.min=kind==='part'&&!makeup?'4':el(field).min;input.max=kind==='part'&&!makeup?'120':el(field).max;
 input.setAttribute('aria-label',kind==='part'?'רוחב החלק באינץ׳':kind==='height'?'גובה הארון באינץ׳':'עומק הארון באינץ׳');
 input.title='Enter לאישור · Escape לביטול';
 Object.assign(input.style,{position:'fixed',zIndex:'1000',width:'88px',height:'34px',padding:'4px',textAlign:'center',direction:'ltr',border:'2px solid #315f4f',boxShadow:'0 2px 8px #0002',left:Math.max(4,Math.min(innerWidth-92,bounds.x+bounds.width/2-44))+'px',top:Math.max(4,Math.min(innerHeight-38,bounds.y+bounds.height/2-17))+'px'});
 let closed=false;
 const close=()=>{closed=true;input.remove();};
 const commit=()=>{
  if(closed)return true;
  const value=Number(input.value),total=kind==='part'&&!makeup?columns.reduce((n,c,i)=>n+(i===part?value:c.width),0):0;
  if(!input.value.trim()||!Number.isFinite(value)||value<Number(input.min)||value>Number(input.max)||Math.abs(value*8-Math.round(value*8))>1e-6||total>120){
   input.setAttribute('aria-invalid','true');showError('יש להזין מידה בטווח '+input.min+'–'+input.max+' אינץ׳, בכפולות של שמינית. הרוחב הכולל עד 120 אינץ׳.');return false;
  }
  close();showError('');
  if(kind==='part'&&!makeup){selectedColumn=part;columns[part].width=value;}
  else el(field).value=value;
  update();return true;
 };
 input.addEventListener('keydown',e=>{if(e.key==='Enter'){e.preventDefault();e.stopPropagation();commit();}if(e.key==='Escape'){e.preventDefault();e.stopPropagation();close();}});
 input.addEventListener('blur',()=>{if(!commit())close();});
 document.body.appendChild(input);input.focus();input.select();
}
el('preview').addEventListener('click',event=>{
 const target=event.target.closest('[data-dimension]');
 if(!target||target.dataset.dimension==='total')return;
 event.preventDefault();event.stopImmediatePropagation();editPreviewDimension(target);
},true);
el('preview').addEventListener('keydown',event=>{
 if(!['Enter',' '].includes(event.key))return;
 const target=event.target.closest('[data-dimension]');if(!target||target.dataset.dimension==='total')return;
 event.preventDefault();editPreviewDimension(target);
});
