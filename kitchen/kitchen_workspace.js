// Presentation only: retain original controls, IDs, callbacks and drawing tools.
(function(){
 if(window.KitchenWorkspace)return;
 const side=document.getElementById('side'),bar=side.querySelector('.modebar');
 let canvasRect=cv.getBoundingClientRect();const hostResize=resize;
 resize=function(){const r=cv.getBoundingClientRect(),wrap=document.getElementById('canvasWrap');panX+=canvasRect.left-r.left;panY+=r.top-canvasRect.top+Math.max(80,wrap.clientHeight)-cv.height;canvasRect=r;return hostResize.apply(this,arguments);};
 window.onresize=resize;
 const rail=document.createElement('div');rail.id='kp-tool-rail';
 const panel=document.createElement('div');panel.id='kp-properties';
 const heading=document.createElement('h2');heading.id='kp-panel-title';panel.append(heading);
 for(const child of [...side.children])if(child!==bar)panel.append(child);
 rail.append(bar);side.append(rail,panel);
 // User preference: no inline instructional notes. Retain controls and data.
 for(const note of panel.querySelectorAll('div:not([id])[style]')){
  if(['11px','12px'].includes(note.style.fontSize)&&!note.querySelector('button,input,select,label'))note.classList.add('kp-help-note');
 }
 const lineSection=document.getElementById('secLine'),lineHome=document.createComment('drawing tools original position');
 lineSection.before(lineHome);
 const dock=document.createElement('div');dock.id='kp-draw-dock';document.getElementById('canvasWrap').append(dock);
 const guideSection=document.getElementById('guideBox'),guideHome=document.createComment('guide tools original position');
 guideSection.before(guideHome);
 const resources=document.createElement('section');resources.id='kp-project-resources';panel.append(resources);
 const resourceHomes=['levelBox','underBox'].map(id=>{const node=document.getElementById(id),home=document.createComment(id+' original position');node.before(home);return {node,home};});
 const resourceButtons=resourceHomes.map(({node})=>{const button=document.createElement('button');button.type='button';button.className='modebtn';button.id='kp-open-'+node.id;const label=node.id==='levelBox'?'Floors':'Image / PDF';button.title=label;button.setAttribute('aria-label',label);button.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">'+(node.id==='levelBox'?'<path d="m3 7 9-4 9 4-9 4zM3 12l9 4 9-4M3 17l9 4 9-4"/>':'<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8" cy="8" r="2"/><path d="m4 18 6-6 4 4 3-3 4 5"/>')+'</svg><span>'+label+'</span>';rail.append(button);return button;});
 const settings=document.createElement('button');settings.type='button';settings.id='kp-view-settings';settings.title='Drawing settings';settings.setAttribute('aria-label','Drawing settings');
 settings.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3" fill="white"/><circle cx="15" cy="17" r="3" fill="white"/></svg><span>Settings</span>';
 settings.className='modebtn';rail.append(settings);
 const labels={modeSel:'Select',modeWall:'Wall',modeDoor:'Door',modeWin:'Window',modeLine:'Draw'};
 const cabinetButton=document.createElement('button');cabinetButton.id='modeCabinet';cabinetButton.type='button';cabinetButton.className='modebtn';cabinetButton.title='Add cabinet';cabinetButton.setAttribute('aria-label','Add cabinet');
 cabinetButton.innerHTML='<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="3" y="3" width="18" height="17" rx="1"/><path d="M12 3v17M3 17h18M9 8v4M15 8v4M5 20v2M19 20v2"/></svg><span>Cabinet</span>';
 cabinetButton.onclick=()=>{if(typeof sketchup.kitchen_open_catalog==='function')sketchup.kitchen_open_catalog();};
 bar.append(cabinetButton);
 for(const [id,label] of Object.entries(labels)){const button=document.getElementById(id);button.querySelector('span').textContent=label;button.title=label;button.setAttribute('aria-label',label);}
 const top=document.getElementById('top'),more=document.createElement('details');more.id='kp-more';
 more.innerHTML='<summary aria-label="More actions">•••</summary><div></div>';
 const menu=more.querySelector('div');
 for(const button of [...top.children])if(button.tagName==='BUTTON'&&button.id!=='applyBtn')menu.append(button);
 top.append(document.getElementById('undoBtn'),more);
 document.getElementById('applyBtn').textContent='Build 3D';
 const style=document.createElement('style');style.textContent=`
 body.kp-clean{font-family:'Segoe UI',Arial,sans-serif;color:#253c34;background:#f4f6f2}
 .kp-clean #top{height:48px;background:white;color:#253c34;border-bottom:1px solid #dce3da;padding:0 16px;gap:10px;overflow:visible}
 .kp-clean #top .title{font-size:14px;font-weight:600}.kp-clean #pageTabs{margin-right:auto}
 .kp-clean button{border-radius:6px;padding:7px 10px}.kp-clean .blue{background:#315f4f}.kp-clean .gray{background:#edf1eb;color:#344c40}
 .kp-clean #main{height:calc(100% - 79px)}.kp-clean #side{order:-1;flex:0 0 68px;width:68px;padding:8px;display:flex;flex-direction:row;gap:8px;border:0;border-right:1px solid #dce3da;background:white;overflow:hidden}
 .kp-clean #side.kp-expanded{flex-basis:314px;width:314px}.kp-clean #kp-tool-rail{flex:0 0 50px;display:flex;flex-direction:column;gap:14px}
 .kp-clean .modebar{display:flex;flex-direction:column;gap:5px}.kp-clean .modebtn{width:50px;min-height:49px;background:white;border:1px solid transparent;font-size:10px;color:#4b6256;border-radius:7px}
 .kp-clean .modebtn svg{width:21px;height:21px}.kp-clean .modebtn.on{background:#e8efe5;border-color:#b3c7b6;color:#27573e}.kp-clean .modebtn:hover{background:#f2f5ef;border-color:#ccd9cc}
 .kp-clean #kp-properties{flex:1;min-width:0;overflow:auto;padding:4px 7px 12px 3px}.kp-clean #kp-panel-title{font-size:14px;margin:6px 0 16px}
 .kp-clean #side:not(.kp-expanded) #kp-properties{display:none}.kp-clean #canvasWrap{margin:12px;border:1px solid #dce3da;border-radius:9px;background:#fafbf8}
 .kp-clean #status,.kp-clean #dbg,.kp-clean #hint,.kp-clean #lineHelp,.kp-clean #undoWrap{display:none!important}
 .kp-clean .kp-help-note,.kp-clean #wArcHint,.kp-clean #selInfo.kp-empty-note{display:none!important}
 .kp-clean #bottom{background:white;color:#627267;border-color:#dce3da}.kp-clean #vcb{background:#f3f6ee;border-color:#dce3da}
 .kp-clean #secSel:empty{display:none}.kp-clean #botWrap{display:none!important}.kp-clean #side.kp-settings #botWrap{display:block!important}.kp-clean #side.kp-settings #kp-properties>div:not(#botWrap){display:none!important}
 #kp-project-resources [hidden]{display:none!important}#kp-project-resources{display:none}.kp-clean #side.kp-resource #kp-project-resources{display:block!important}
 .kp-clean #side.kp-resource #kp-properties>*:not(#kp-panel-title):not(#kp-project-resources){display:none!important}
 .kp-clean #kp-tool-rail{overflow-y:auto;gap:7px}.kp-clean #kp-tool-rail .modebtn{flex-shrink:0}
 #kp-draw-dock{display:none}.kp-clean #kp-draw-dock{position:absolute;bottom:12px;left:12px;right:12px;z-index:12;pointer-events:none;align-items:flex-end;justify-content:center;gap:8px;flex-wrap:wrap}
 .kp-clean #kp-draw-dock #secLine{display:flex!important;pointer-events:auto;width:fit-content;max-width:100%;margin:0;padding:8px;background:white;border:1px solid #dce3da;border-radius:8px;box-shadow:0 3px 12px #20352822;align-items:center;gap:8px;flex-wrap:wrap}
 .kp-clean #kp-draw-dock.kp-drawing #secLine{display:flex!important}
 .kp-clean #kp-draw-dock #guideBox{pointer-events:auto;background:white;margin:0;min-width:140px;max-width:270px;max-height:50vh;overflow:auto;box-shadow:0 3px 12px #20352822}
 .kp-clean #kp-draw-dock .sktb{margin:0;flex-wrap:wrap}.kp-clean #kp-draw-dock #secLine>div{margin:0!important}.kp-clean #kp-draw-dock button{width:auto!important;min-width:30px}.kp-clean #kp-draw-dock svg{min-width:18px;min-height:18px}
 .kp-clean #side[data-tool="sel"] #secLine{display:none!important}.kp-clean .foldBox{background:white;border-color:#dce3da}.kp-clean .foldHead{font-weight:500}
 .kp-clean #kp-more{position:relative}.kp-clean #kp-more summary{list-style:none;cursor:pointer;padding:6px 9px;font-size:18px}.kp-clean #kp-more summary::-webkit-details-marker{display:none}
 .kp-clean #kp-more>div{position:absolute;right:0;top:36px;z-index:1000;min-width:170px;background:white;padding:8px;border:1px solid #dce3da;border-radius:8px;box-shadow:0 8px 25px #20352822;display:grid;gap:6px}.kp-clean #kp-more:not([open])>div{display:none}

 .kp-clean #editBar{background:transparent;padding:0;border:0;box-shadow:none;width:fit-content;max-width:100%;gap:5px;flex-wrap:wrap}
 .kp-clean #editBar .sktb-g{display:contents;border:0;padding:0}
 .kp-clean #editBar button{width:30px;height:30px;min-height:0;padding:0;border:1px solid #dce3da;background:white;color:#4b6256;border-radius:6px}
 .kp-clean #editBar button:hover{background:#edf1eb;color:#253c34}
 .kp-clean #editBar button.on{background:#315f4f;color:white}
 .kp-clean #editBar #ebDel:hover{background:#fff0ee;border-color:#dba9a2;color:#a12e25}
 .kp-clean #editBar button:focus-visible{outline:2px solid #315f4f;outline-offset:2px}
 @media(max-width:620px){.kp-clean #main{flex-direction:row}.kp-clean #side{max-height:none}.kp-clean #side.kp-expanded{flex-basis:270px;width:270px}.kp-clean #canvasWrap{margin:5px}.kp-clean #top .title{display:none}}
 `;document.head.append(style);
 let settingsOpen=false,resourceOpen=null,previousMode=mode;
 function update(){
  const house=activePage===0;
  const selectionInfo=document.getElementById('selInfo');
  selectionInfo.classList.toggle('kp-empty-note',selectionInfo.textContent.trim().startsWith('לא נבחר כלום'));
  if(house&&lineSection.parentNode!==dock)dock.append(lineSection);
  if(!house&&lineSection.parentNode===dock)lineHome.after(lineSection);
  if(house&&guideSection.parentNode!==dock)dock.append(guideSection);
  if(!house&&guideSection.parentNode===dock)guideHome.after(guideSection);
  resourceHomes.forEach(({node,home},i)=>{if(house&&node.parentNode!==resources)resources.append(node);if(!house&&node.parentNode===resources)home.after(node);node.hidden=house&&resourceOpen!==node.id;resourceButtons[i].classList.toggle('on',house&&resourceOpen===node.id);resourceButtons[i].setAttribute('aria-expanded',String(house&&resourceOpen===node.id));});
  dock.style.display=house?'flex':'none';dock.classList.toggle('kp-drawing',mode==='line');
  document.body.classList.toggle('kp-clean',house);
  if(mode!==previousMode){settingsOpen=false;resourceOpen=null;previousMode=mode;}
  const expanded=settingsOpen||!!resourceOpen||['wall','door','win'].includes(mode)||!!sel||(typeof selList!=='undefined'&&selList.length>0);
  const changed=side.classList.contains('kp-expanded')!==expanded;
  side.classList.toggle('kp-expanded',expanded);side.classList.toggle('kp-settings',settingsOpen);side.dataset.tool=mode;
  side.classList.toggle('kp-resource',!!resourceOpen);
  settings.classList.toggle('on',settingsOpen);settings.setAttribute('aria-expanded',String(settingsOpen));
  heading.textContent=resourceOpen?(resourceOpen==='levelBox'?'Floors':'Image / PDF'):settingsOpen?'Drawing settings':({sel:'Selection',wall:'Wall',door:'Door',win:'Window',line:'Draw'})[mode]||'Properties';
  if(changed)resize();
 }
 rail.addEventListener('click',e=>{const b=e.target.closest('button');if(b&&!resourceButtons.includes(b)){resourceOpen=null;if(b!==settings)settingsOpen=false;}},true);
 resourceButtons.forEach((button,i)=>button.onclick=()=>{const next=resourceOpen===resourceHomes[i].node.id?null:resourceHomes[i].node.id;setMode('sel');previousMode=mode;settingsOpen=false;resourceOpen=next;update();draw();});
 settings.onclick=()=>{settingsOpen=!settingsOpen;resourceOpen=null;update();};
 window.addEventListener('keydown',event=>{
  if(activePage!==0||event.code!=='Space'||event.ctrlKey||event.metaKey||event.altKey||event.isComposing)return;
  const target=event.target;
  if(target?.closest?.('input,textarea,select,[role="textbox"]')||(target?.isContentEditable&&target.id!=='hiddenUndo'))return;
  event.preventDefault();event.stopImmediatePropagation();
  if(event.repeat||window.KitchenHouseInsert?.state.pending||window.KitchenHouseDrag?.state.pending)return;
  window.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',code:'Escape',bubbles:true}));
  document.getElementById('modeSel').click();
 },true);
 const hostDraw=draw;draw=function(){update();return hostDraw.apply(this,arguments);};
 window.KitchenWorkspace={update,closeContext(){settingsOpen=false;resourceOpen=null;}};update();resize();
})();
