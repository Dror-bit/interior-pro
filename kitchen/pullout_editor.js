(()=>{
 if(document.getElementById('pulloutEditor'))return;
 const section=document.createElement('section');section.id='pulloutEditor';section.className='wide';
 section.innerHTML='<h2>Pull-out storage</h2><label>Interior<select id="pulloutType"><option value="none">Standard cabinet</option><option value="spice">Spice rack</option><option value="waste">Trash pull-out</option><option value="storage">Storage pull-out</option></select></label><div id="pulloutOptions"><label>Extension (in)<input id="pulloutExtension" type="number" min="0" step="0.5" value="0"></label><label id="pulloutBinsLabel">Bins<select id="pulloutBins"><option value="1">One bin</option><option value="2">Two bins</option></select></label></div>';
 document.getElementById('cabinetControls').prepend(section);
 const el=id=>document.getElementById(id),eligible=d=>d&&d.kind==='doors'&&!d.surround_for&&!d.sink&&!d.appliance;
 function show(){el('pulloutOptions').hidden=el('pulloutType').value==='none';el('pulloutBinsLabel').hidden=el('pulloutType').value!=='waste';}
 function draft(){return el('pulloutType').value==='none'?null:{type:el('pulloutType').value,extension:Number(el('pulloutExtension').value),bins:Number(el('pulloutBins').value)};}
 const prevFill=fill;fill=function(...args){prevFill(...args);section.hidden=!eligible(selected);const p=selected?.pullout||{};el('pulloutType').value=p.type||'none';el('pulloutExtension').value=p.extension||0;el('pulloutExtension').max=Math.max(0,(selected?.depth||24)-3);el('pulloutBins').value=p.bins||2;show();};
 const prevDraft=cabinetDraft;cabinetDraft=function(...args){const d=prevDraft(...args);if(!eligible(d))return d;const p=draft();return {...d,pullout:p,...(p?{front_layout:'single'}:{})};};
 const prevSend=send;send=function(name,...args){if(name==='apply'){const d=JSON.parse(args[0]);if(selected&&d.id===selected.id&&eligible(d)){d.pullout=draft();if(d.pullout){d.front_layout='single';delete d.drawer_heights;}args[0]=JSON.stringify(d);}}return prevSend(name,...args);};
 el('pulloutType').onchange=show;show();
})();
