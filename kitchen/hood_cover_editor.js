(()=>{
 const section=document.createElement('section');section.id='hoodCoverEditor';
 section.innerHTML='<h2>Hood cover</h2><label>Front style<select id="hoodCoverStyle"><option value="slab">Plain box</option><option value="shaker">Shaker</option></select></label><label>Cover height (in)<input id="hoodCoverHeight" type="number" step="any" max="96"></label><label>Cover depth (in)<input id="hoodCoverDepth" type="number" step="any" max="36"></label><p>Fixed front without doors or handles. Open underneath for the hood intake.</p><button type="button" id="applyHoodCover">Apply cover</button><p id="hoodCoverError" role="alert"></p>';
 $('cabinetControls').prepend(section);
 function bundle(){const id=selected?.surround_for||selected?.id;const owner=cabinets.find(c=>c.id===id);const parts=cabinets.filter(c=>c.surround_for===id);return owner?.kind==='hood'&&parts.some(c=>c.surround_part==='hood_front')?{owner,parts}:null;}
 function refresh(){const b=bundle();section.hidden=!b;if(!b)return;const front=b.parts.find(c=>c.surround_part==='hood_front'),side=b.parts.find(c=>c.surround_part==='left');$('hoodCoverStyle').value=front.style;$('hoodCoverHeight').value=front.height;$('hoodCoverHeight').min=b.owner.height;$('hoodCoverDepth').value=side.depth;$('hoodCoverDepth').min=b.owner.depth+1;$('hoodCoverError').textContent='';}
 const prior=fill;fill=function(...args){const r=prior(...args);refresh();return r;};
 $('applyHoodCover').onclick=()=>{if(busy)return;const b=bundle();if(!b)return;const height=Number($('hoodCoverHeight').value),depth=Number($('hoodCoverDepth').value);if(!Number.isFinite(height)||height<b.owner.height||height>96||!Number.isFinite(depth)||depth<b.owner.depth+1||depth>36){$('hoodCoverError').textContent='Cover dimensions must fit the hood. Check the minimum values.';return;}pending(true);sendCommands([{type:'update_hood_cover',payload:{id:b.owner.id,style:$('hoodCoverStyle').value,height,depth}}]);};
 refresh();
})();

// Save cabinet applies its cover choices in the same command batch and Undo step.
(()=>{
 if(window.hoodCoverSaveHook)return;
 window.hoodCoverSaveHook=true;
 const previous=sendCommands;
 sendCommands=function(commands){
  if(selected&&commands.some(c=>c.type==='update_cabinet'&&c.payload.id===selected.id)&&!commands.some(c=>c.type==='update_hood_cover')){
   const id=selected.surround_for||selected.id;
   const owner=cabinets.find(c=>c.id===id);
   const panel=document.getElementById('hoodCoverEditor');
   if(owner?.kind==='hood'&&panel&&!panel.hidden){
    commands=[...commands,{type:'update_hood_cover',payload:{id,style:document.getElementById('hoodCoverStyle').value,height:Number(document.getElementById('hoodCoverHeight').value),depth:Number(document.getElementById('hoodCoverDepth').value)}}];
   }
  }
  return previous(commands);
 };
})();
