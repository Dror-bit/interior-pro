// Runtime-only house selection adapter; use the host's actual door outlines.
(function(){
 if(window.KitchenHouseSelection)return;
 const original=hitOpening;
 hitOpening=function(p){
  const direct=original(p);if(direct||activePage!==0)return direct;
  let best=null,distance=8/Math.max(scale,.01);
  for(const w of walls){const b=bandQuad(w);if(!b)continue;
   for(const s of w.syms||[]){if(!['door','double'].includes(s.kind))continue;
    const paths=[],old=polyline,x1=Math.max(0,s.t-s.w/2),x2=Math.min(b.len,s.t+s.w/2);
    polyline=points=>paths.push(points);
    try{if(s.kind==='double'){symLeaf(w,b,x1+JAMB,(x1+x2)/2,s.clicked);symLeaf(w,b,x2-JAMB,(x1+x2)/2,s.clicked);}else symLeaf(w,b,s.swing==='right'?x2-JAMB:x1+JAMB,s.swing==='right'?x1+JAMB:x2-JAMB,s.clicked);}finally{polyline=old;}
    for(const path of paths)for(let i=1;i<path.length;i++){const a=path[i-1],z=path[i],dx=z.x-a.x,dy=z.y-a.y,len=dx*dx+dy*dy,t=len?Math.max(0,Math.min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/len)):0,d=Math.hypot(p.x-a.x-t*dx,p.y-a.y-t*dy);if(d<distance){distance=d;best={w,s,b};}}
   }
  }return best;
 };
 const hostSelect=setSel;setSel=function(value){if(value&&activePage===0){window.KitchenSidebar?.close();window.KitchenWorkspace?.closeContext?.();}return hostSelect.apply(this,arguments);};
 window.KitchenHouseSelection=true;
})();
