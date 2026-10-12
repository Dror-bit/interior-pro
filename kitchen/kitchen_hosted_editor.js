// Reuse cabinet controls, while keeping the house drawing as the workspace.
if (!window.openHostedCabinet) {
  const style=document.createElement('style');
  style.textContent='body.hosted-cabinet>header,body.hosted-cabinet>main,body.hosted-cabinet>footer{display:none!important}body.hosted-cabinet{background:#fff}body.hosted-cabinet #cabinetDialog{width:98vw;height:96vh;max-width:98vw;max-height:96vh}';
  document.head.append(style);
  window.openHostedCabinet=function(id){
    if(!cabinets.some(c=>c.id===id))return;
    document.body.classList.remove('hosted-catalog');
    document.getElementById('hostedCatalog')?.close();
    document.body.classList.add('hosted-cabinet');
    if(selected?.id!==id)choose(id);
    if(!cabinetDialog.open)openCabinetEditor();
  };
  cabinetDialog.addEventListener('close',()=>{
    if(document.body.classList.contains('hosted-cabinet'))sketchup.hosted_close();
  });
}
// Replaceable independently, so a live editor can receive this fix without reload.
  window.openHostedCatalog=function(){
    document.body.classList.add('hosted-cabinet','hosted-catalog');
    let dialog=document.getElementById('hostedCatalog');
    if(!dialog){
      dialog=document.createElement('dialog');dialog.id='hostedCatalog';
      dialog.style.cssText='width:min(650px,90vw);max-height:88vh;border:1px solid #dce3da;border-radius:12px;padding:20px;color:#253c34';
      dialog.innerHTML='<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:18px"><h2 style="margin:0;font-size:18px">Add cabinet</h2><button type="button" class="subtle" id="closeHostedCatalog">Close ×</button></div>';
      const catalog=document.getElementById('cabinetLibrary');catalog.open=true;dialog.append(catalog);
      const error=document.createElement('div');error.style.cssText='color:#a43425;font-size:13px';dialog.append(error);
      new MutationObserver(()=>{error.textContent=$('error').textContent;}).observe($('error'),{childList:true,subtree:true,characterData:true});
      document.body.append(dialog);
      $('closeHostedCatalog').onclick=()=>dialog.close();
    }
    if(dialog._hostedClose)dialog.removeEventListener('close',dialog._hostedClose,true);
    dialog._hostedClose=(event)=>{
      event.stopImmediatePropagation();
      if(!document.body.classList.contains('hosted-catalog'))return;
      document.body.classList.remove('hosted-catalog');
      if(!cabinetDialog.open)sketchup.hosted_close();
    };
    dialog.addEventListener('close',dialog._hostedClose,true);
    if(!dialog.open)dialog.showModal();
  };
