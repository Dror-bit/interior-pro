function sinkDefaults(c){return {type:'single',width:Math.min(30,c.width-4),depth:Math.min(18,c.depth-6),bowl_depth:8,offset_x:0,front_setback:2,finish:'stainless',faucet:'arched',faucet_finish:'chrome',faucet_height:12};}
function sinkSpec(c){return c.kind==='sink'&&c.sink&&c.sink.type!=='none'?{...sinkDefaults(c),...c.sink}:null;}
function sinkBounds(c){const s=sinkSpec(c),x=(c.width-s.width)/2+s.offset_x,y=c.depth-s.front_setback;return {s,x,y};}
function sinkPlan(c,frame){
 const spec=sinkSpec(c);if(!spec)return '';const {s,x,y}=sinkBounds(c),point=(a,b)=>planPoint(c,a,b,frame);
 const polygon=(a,b,w,d,fill)=>svg('polygon',{points:[[a,b],[a+w,b],[a+w,b-d],[a,b-d]].map(p=>point(...p).join(',')).join(' '),fill,stroke:'#66767c','stroke-width':1});
 let out=polygon(x,y,s.width,s.depth,{stainless:'#b6c3c9',white:'#f4f3ed',black:'#33383a'}[s.finish])+polygon(x+.5,y-.5,s.width-1,s.depth-1,'#82969e');
 if(s.type==='double')out+=line(...point(x+s.width/2,y-.5),...point(x+s.width/2,y-s.depth+.5),'#d5dee2',{'stroke-width':3});
 const drains=s.type==='double'?[.25,.75]:[.5];for(const t of drains){const p=point(x+s.width*t,y-s.depth/2);out+=svg('circle',{cx:p[0],cy:p[1],r:Math.max(1,.65*frame.s),fill:'#3b494f'});}
 if(s.faucet!=='none'){const a=point(x+s.width/2,y-s.depth-1.5),b=point(x+s.width/2,y-s.depth+3.5);out+=line(...a,...b,{chrome:'#d6dfe2',brass:'#b39456',black:'#242729'}[s.faucet_finish],{'stroke-width':Math.max(2,.65*frame.s)});}
 return svg('g',{class:'sink-plan','pointer-events':'none'},out);
}
function sinkElevation(c,x,base,scale){
 const spec=sinkSpec(c);if(!spec)return '';const {s,x:offset}=sinkBounds(c),top=base-(c.z+c.height+1.5)*scale;
 let out=s.product_id?'':rect(x+offset*scale,top-.12*scale,s.width*scale,.12*scale,'#aab9c0');
 if(s.product_id==='kohler-k-6489')out+=rect(x+offset*scale,top+1.5*scale,s.width*scale,8.8125*scale,'#f4f3ed');
 if(s.faucet!=='none'){const cx=x+(offset+s.width/2)*scale;out+=line(cx,top,cx,top-s.faucet_height*scale,{chrome:'#8e9fa7',brass:'#b39456',black:'#242729'}[s.faucet_finish],{'stroke-width':Math.max(2,.64*scale)});out+=line(cx,top-1*scale,cx+2*scale,top-1*scale,'#65767d');}
 return svg('g',{class:'sink-elevation','pointer-events':'none'},out);
}
const sinkEditor=document.createElement('section');sinkEditor.id='sinkEditor';sinkEditor.className='wide';
sinkEditor.innerHTML='<h2>Sink & faucet</h2><p id="sinkCutoutStatus" role="status" hidden>Automatic countertop cutout unavailable — awaiting verified manufacturer template.</p>';
const sinkFields={type:['Sink',['none','single','double']],width:['Width',null],depth:['Front to back',null],bowl_depth:['Bowl depth',null],offset_x:['Side offset (+ right)',null],front_setback:['From cabinet front',null],finish:['Sink finish',['stainless','white','black']],faucet:['Faucet',['arched','none']],faucet_finish:['Faucet finish',['chrome','brass','black']],faucet_height:['Faucet height',null]};
for(const [key,[label,options]] of Object.entries(sinkFields)){const node=document.createElement('label');node.textContent=label;const input=document.createElement(options?'select':'input');input.id='sink_'+key;if(options)input.innerHTML=options.map(v=>`<option value="${v}">${v[0].toUpperCase()+v.slice(1)}</option>`).join('');else{input.type='number';input.step='0.125';}node.append(input);sinkEditor.append(node);}
$('cabinetControls').prepend(sinkEditor);
function validateSink(c,s){
 if(s.type==='none')return;
 const ranges={width:[12,48],depth:[10,28],bowl_depth:[4,12],offset_x:[-24,24],front_setback:[s.product_id==='kohler-k-6489'?-1:1.25,12],faucet_height:[6,20]};
 for(const [key,[min,max]] of Object.entries(ranges))if(!Number.isFinite(s[key])||s[key]<min||s[key]>max)throw Error(`Invalid sink ${key.replaceAll('_',' ')}`);
 const left=(c.width-s.width)/2+s.offset_x;
 const margin=s.product_id==='kohler-k-6489'?.125:1;if(left<margin||left+s.width>c.width-margin)throw Error('Sink must fit between cabinet sides with 1 inch clearance');
 if(s.front_setback+s.depth>c.depth-(s.product_id==='kohler-k-3838-1'?.5:3))throw Error('Sink does not fit the cabinet depth');
 if(s.type==='double'&&s.width<24)throw Error('Double sink needs at least 24 inches width');
 if(c.height+1.5-s.bowl_depth<=(c.toe_height??4)+1)throw Error('Sink bowl reaches the cabinet bottom');
}
function readSink(d){if(d.kind!=='sink')return d;const s={...d.sink};for(const [key,[,options]] of Object.entries(sinkFields))s[key]=options?$('sink_'+key).value:Number($('sink_'+key).value);validateSink(d,s);return {...d,sink:s.type==='none'?{type:'none'}:s};}
const sinkFill=fill;fill=function(){sinkFill();sinkEditor.hidden=selected?.kind!=='sink';$('sinkCutoutStatus').hidden=!['kohler-k-5287','kohler-k-33152'].includes(selected?.sink?.product_id);const s={...sinkDefaults(selected||{width:36,depth:24}),type:'none',...selected?.sink};for(const key of Object.keys(sinkFields)){$('sink_'+key).value=s[key];$('sink_'+key).disabled=!!s.product_id&&(['type','width','depth','bowl_depth','finish'].includes(key)||(s.product_id==='kohler-k-6489'&&['front_setback','offset_x'].includes(key)));}refreshCabinetPreview();};
const sinkDraft=cabinetDraft;cabinetDraft=function(){const d=sinkDraft();return d?readSink(d):d;};
const sinkSend=send;send=function(name,...args){try{if(name==='apply'){let d=JSON.parse(args[0]);if(d.kind==='sink')d=cabinets.some(c=>c.id===d.id)?readSink(d):{...d,sink:sinkDefaults(d)};args[0]=JSON.stringify(d);}sinkSend(name,...args);}catch(e){pending(false);$('error').textContent=e.message;}};

