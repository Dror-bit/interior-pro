// Keep referenced nodes alive while removing instructional prose.
(function(){
 const clean=()=>document.querySelectorAll('.tiny,.editor-head p,.editor-preview>span,.legend>span').forEach(node=>{
  if(node.matches('label,[role="alert"]')||node.querySelector('input,select,button'))return;
  if(node.textContent)node.textContent='';
  node.style.setProperty('display','none','important');
 });
 clean();
 if(document.getElementById('settingsForm')&&!document.getElementById('standalone-door-swings')){
  const label=document.createElement('label'),box=document.createElement('input');box.type='checkbox';box.id='standalone-door-swings';box.style.width='auto';
  label.style.cssText='display:flex;align-items:center;gap:7px;margin:12px 0';label.append(box,document.createTextNode('Show door swings'));document.getElementById('settingsForm').prepend(label);
  const style=document.createElement('style');style.textContent='body:not(.show-door-swings) .plan-openings [stroke-dasharray]{display:none}';document.head.append(style);
  try{box.checked=localStorage.getItem('kitchen-door-swings')==='true';}catch{}
  const update=()=>{document.body.classList.toggle('show-door-swings',box.checked);try{localStorage.setItem('kitchen-door-swings',String(box.checked));}catch{}};
  box.onchange=update;update();
 }
 if(!window.kitchenNotesObserver){
  window.kitchenNotesObserver=new MutationObserver(clean);
  window.kitchenNotesObserver.observe(document.body,{childList:true,subtree:true,characterData:true});
 }
})();
