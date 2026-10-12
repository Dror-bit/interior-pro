(function(){
 if(window.KitchenSurround)return;
 const section=document.getElementById('kp-kitchen'),box=document.createElement('section');
 box.id='kp-surround';box.hidden=true;
 box.innerHTML='<h3 id="kp-surround-title"></h3><form id="kp-surround-form"><label id="kp-surround-height-row">Total height (in)<input id="kp-surround-height" type="number" min="18" max="96" step="0.125" value="96" required></label><label>Depth (in)<input id="kp-surround-depth" type="number" min="8" max="36" step="0.125" required></label><label>Side clearance (in)<input id="kp-surround-side" type="number" min="0" max="6" step="0.125" value="0.25" required></label><label>Top clearance (in)<input id="kp-surround-top" type="number" min="0" max="12" step="0.125" value="1" required></label><button type="submit">Add cabinet around appliance</button></form><div id="kp-surround-error" role="alert"></div>';
 section.prepend(box);
 const style=document.createElement('style');style.textContent='#kp-surround[hidden]{display:none!important}#kp-surround{padding-bottom:14px;border-bottom:1px solid #dce3da}#kp-surround-form{display:grid;grid-template-columns:1fr 1fr;gap:8px}#kp-surround input{box-sizing:border-box;width:100%;padding:6px;border:1px solid #dce3da;border-radius:5px}#kp-surround button{grid-column:1/-1;padding:9px;background:#315f4f;color:white;border:0;border-radius:5px}#kp-surround-error{color:#a43425;margin-top:8px}';document.head.append(style);
 const field=name=>document.getElementById('kp-surround-'+name);
 let current=null,revision=null,pending=false;
 function update(){
  const rows=window.KitchenSymbols?.rows||[],id=window.KitchenHouseDrag?.state.selected;
  const row=rows.find(r=>r.id===id&&['fridge','microwave','wall_oven'].includes(r.cabinet?.kind));
  box.hidden=activePage!==0||!row;
  if(!row){current=null;return;}
  if(current!==id){current=id;field('depth').value=row.cabinet.kind==='fridge'?24:row.cabinet.depth;field('height').value=96;field('side').value=.25;field('top').value=1;field('error').textContent='';}
  field('title').textContent=row.cabinet.kind==='fridge'?'Refrigerator cabinet':row.cabinet.kind==='wall_oven'?'Wall oven cabinet':'Microwave cabinet';
  field('height-row').style.display=row.cabinet.kind!=='microwave'?'grid':'none';
  const exists=rows.some(r=>r.cabinet?.surround_for===id),button=box.querySelector('button');
  button.disabled=pending||exists;button.textContent=exists?'Cabinet already added':'Add cabinet around appliance';
 }
 const load=KP.load;KP.load=function(data){revision=data.revision;const result=load.apply(this,arguments);update();return result;};
 const hostDraw=draw;draw=function(){const result=hostDraw.apply(this,arguments);update();return result;};
 field('form').onsubmit=e=>{e.preventDefault();if(pending||!current||box.querySelector('button').disabled||KitchenHouseDrag.state.pending||KitchenHouseDrag.state.dragging)return;pending=true;field('error').textContent='';update();sketchup.kitchen_add_surround(JSON.stringify({id:current,revision,options:{total_height:Number(field('height').value),depth:Number(field('depth').value),side_gap:Number(field('side').value),top_gap:Number(field('top').value)}}));};
 window.KitchenSurround={select(){update();if(!box.hidden){KitchenSidebar.open();}},result(error){pending=false;field('error').textContent=error||'';update();if(!error&&typeof armHiddenUndo==='function')armHiddenUndo();},get pending(){return pending;}};
})();
