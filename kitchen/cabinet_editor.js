/* Cabinet details are edited separately from the complete kitchen layout. */
const cabinetDialog=document.createElement('dialog');
cabinetDialog.id='cabinetDialog';
cabinetDialog.innerHTML=`<div class="editor-head"><div><h2 id="cabinetTitle">Cabinet details</h2><p>Fronts, glass, drawers and hardware</p></div><button type="button" id="closeCabinet" class="subtle">Close ✕</button></div><div class="editor-body"><div class="editor-preview"><svg id="cabinetPreview" viewBox="0 0 960 600" aria-label="Selected cabinet preview"></svg><svg id="cabinetTopPreview" viewBox="0 0 960 600" aria-label="Selected cabinet top view"></svg><span>Elevation + top · Dashed lines show opening direction</span></div><div id="cabinetControls" class="fields"></div></div><div class="editor-foot"><span id="cabinetEditorError" role="alert"></span><button type="button" id="saveCabinet" class="primary">Save cabinet</button></div>`;
document.body.append(cabinetDialog);
const editorStyle=document.createElement('style');editorStyle.textContent=`
#cabinetDialog{border:1px solid #cbd5ca;border-radius:14px;padding:0;width:min(1000px,94vw);max-width:94vw;height:min(720px,90vh);max-height:90vh;color:var(--ink);background:#fff;box-shadow:0 20px 80px #14281e40}
#cabinetDialog::backdrop{background:#172e2666}.editor-head{display:flex;align-items:center;justify-content:space-between;padding:16px 20px;border-bottom:1px solid var(--line)}.editor-head h2{font-size:20px;margin:0}.editor-head p{font-size:12px;color:var(--muted);margin:5px 0 0}.editor-body{display:grid;grid-template-columns:minmax(280px,1fr) 310px;height:calc(100% - 143px)}.editor-preview{position:relative;background:#f5f7f1;display:flex;align-items:center;justify-content:center;overflow:hidden}.editor-preview svg{width:100%;height:100%;pointer-events:none}.editor-preview span{position:absolute;bottom:16px;color:#79867e;font-size:12px}#cabinetControls{display:block;padding:18px;overflow-y:auto}#cabinetControls>label,#cabinetControls>section{margin-bottom:14px}#cabinetControls .fields{display:grid}.editor-foot{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:13px 20px;border-top:1px solid var(--line)}#saveCabinet{flex:0 0 170px}#cabinetEditorError{color:#a43425;font-size:12px}.library-summary{font-size:15px;font-weight:600;cursor:pointer;padding:10px 0}.cabinet-library{border-bottom:1px solid var(--line);margin-bottom:18px;padding-bottom:12px}.cabinet-library[open] summary{margin-bottom:12px}#openCabinet{width:100%;margin-top:12px;padding:12px}aside{padding-top:12px}.canvas-zone{padding:14px}.editor-body .tiny{font-size:11px}`;
document.head.append(editorStyle);
editorStyle.textContent+='.editor-preview{flex-direction:column}.editor-preview #cabinetPreview{height:58%;min-height:0}.editor-preview #cabinetTopPreview{height:42%;min-height:0;border-top:1px solid #dce3d9}.editor-preview span{font-size:10px;bottom:4px}';
editorStyle.textContent+=`@media(max-width:760px){main{display:flex;flex-direction:column;height:auto;min-height:0}.canvas-zone{order:0;min-height:480px;height:65vh}aside{order:1;overflow:visible;border-right:0}.toolbar{flex-wrap:wrap;gap:8px}.tabs button{padding:8px}.editor-body{display:flex;flex-direction:column;overflow-y:auto}.editor-preview{flex:0 0 240px}#cabinetControls{overflow:visible}.editor-head{padding:12px}.editor-head h2{font-size:17px}#saveCabinet{flex-basis:140px}}`;
// Keep all inputs owned by the existing form when they move into the dialog.
const fieldsContainer=$('form').querySelector('.fields');
const detailNodes=[...fieldsContainer.children].filter(el=>el.id==='builtinEditor'||el.id==='toeEditor'||el.hasAttribute('data-cabinet-field')||el.id==='applianceFinishField');
for(const node of detailNodes){$('cabinetControls').append(node);node.querySelectorAll('input,select,button').forEach(el=>el.setAttribute('form','form'));}
$('cabinetControls').append($('itemNote'));
const aside=document.querySelector('aside'),library=document.createElement('details');library.className='cabinet-library';
const summary=document.createElement('summary');summary.className='library-summary';summary.textContent='+ Add cabinets & appliances';library.append(summary);
while(aside.firstElementChild&&aside.firstElementChild.id!=='selection')library.append(aside.firstElementChild);
aside.prepend(library);
// One clear entry point; the catalog stays collapsed until requested.
library.id='cabinetLibrary';summary.hidden=true;
const addCabinetButton=document.createElement('button');
addCabinetButton.id='addCabinetButton';addCabinetButton.type='button';addCabinetButton.className='primary';
addCabinetButton.textContent='+ Add cabinet';addCabinetButton.style.cssText='width:100%;margin-bottom:12px';
addCabinetButton.setAttribute('aria-controls',library.id);addCabinetButton.setAttribute('aria-expanded','false');
library.before(addCabinetButton);
addCabinetButton.onclick=()=>{library.open=!library.open;addCabinetButton.setAttribute('aria-expanded',String(library.open));};
library.addEventListener('toggle',()=>addCabinetButton.setAttribute('aria-expanded',String(library.open)));
editorStyle.textContent+='.cabinet-library:not([open]){border:0;margin:0;padding:0}';
const generalSettings=[...library.querySelectorAll('details')].find(el=>el.querySelector('summary')?.textContent==='Kitchen settings');
if(generalSettings){generalSettings.id='kitchenGeneralSettings';library.after(generalSettings);}
editorStyle.textContent+='#kitchenGeneralSettings .tiny{display:none}';
const wallLabel=$('active_wall').parentElement;wallLabel.firstChild.textContent='Elevation wall';wallLabel.hidden=mode!=='front';wallLabel.style.marginBottom='0';document.querySelector('.toolbar .tabs').after(wallLabel);
const openButton=document.createElement('button');openButton.id='openCabinet';openButton.hidden=true;openButton.type='button';openButton.className='primary';openButton.textContent='Edit selected cabinet';$('form').before(openButton);
const dimsTitle=document.createElement('h2');dimsTitle.textContent='Size & position';dimsTitle.style.marginTop='20px';$('form').before(dimsTitle);
const originalFill=fill,originalDraw=draw,originalPending=pending;
fill=function(){originalFill();$('apply').textContent='Apply size & position';openButton.disabled=!selected;refreshCabinetPreview();};
pending=function(value){originalPending(value);$('saveCabinet').disabled=value;openButton.disabled=value||!selected;};
draw=function(...args){originalDraw(...args);if(!args[0])refreshCabinetPreview();};
function cabinetDraft(){
 if(!selected)return null;
 const d={...selected};
 for(const key of fields)d[key]=$(key).type==='checkbox'?$(key).checked:['wall','style','handle','finish','appliance_finish','handle_position','rotation_pivot'].includes(key)?$(key).value:Number($(key).value);
 if(!isAppliance(d)&&!plainPanel(d)){Object.assign(d,readFrontEditor());if(d.kind==='tall'&&window.readPantryEditor)d.pantry=readPantryEditor(d);validateToe(d);checkHandles(d);checkShaker(d);}
 return d;
}
function refreshCabinetPreview(){
 if(!cabinetDialog.open||!selected)return;
 $('cabinetControls').querySelectorAll('input,select,button').forEach(el=>el.setAttribute('form','form'));
 $('cabinetTitle').textContent=names[selected.kind]+' · '+fmt(selected.width);
 try{const d=cabinetDraft();originalDraw({...d,x:0,z:0,wall:'A'},'front',null);originalDraw({...d,x:0,z:0,wall:'A',_preview_rotation:true},'top',null,$('cabinetTopPreview'));$('cabinetEditorError').textContent=$('error').textContent;}
 catch(e){$('cabinetEditorError').textContent=e.message;}
}
function openCabinetEditor(){if(!selected||busy)return;cancelDrag();cabinetDialog.showModal();refreshCabinetPreview();$('closeCabinet').focus();}
openButton.addEventListener('click',openCabinetEditor);
$('closeCabinet').addEventListener('click',()=>cabinetDialog.close());
cabinetDialog.addEventListener('close',()=>{editorPreview=null;fill();draw();$('drawing').setAttribute('tabindex','0');$('drawing').focus();});
$('saveCabinet').addEventListener('click',()=>{if(busy)return;try{cabinetDraft();$('form').requestSubmit();}catch(e){$('cabinetEditorError').textContent=e.message;}});
$('cabinetControls').addEventListener('input',refreshCabinetPreview);
$('cabinetControls').addEventListener('change',refreshCabinetPreview);
new MutationObserver(()=>{if(cabinetDialog.open)$('cabinetEditorError').textContent=$('error').textContent;}).observe($('error'),{childList:true,subtree:true,characterData:true});
// Record completed clicks, so dragging never opens the editor.
let lastCabinetClick=null;
let clickStart=null,completedClick=false;
$('drawing').addEventListener('pointerdown',e=>{clickStart=e.target.closest('.cab')?{x:e.clientX,y:e.clientY}:null;},true);
$('drawing').addEventListener('pointerup',e=>{completedClick=!!clickStart&&Math.hypot(e.clientX-clickStart.x,e.clientY-clickStart.y)<3;clickStart=null;},true);
$('drawing').addEventListener('pointerup',e=>{
 if(!completedClick||!selected||busy){lastCabinetClick=null;return;}
 const now=performance.now();
 if(lastCabinetClick&&lastCabinetClick.id===selected.id&&now-lastCabinetClick.time<400&&Math.hypot(e.clientX-lastCabinetClick.x,e.clientY-lastCabinetClick.y)<6){lastCabinetClick=null;openCabinetEditor();}
 else lastCabinetClick={id:selected.id,time:now,x:e.clientX,y:e.clientY};
});
