// Same geometry as the native SKP; cached raster clipped by the actual opening.
const museRasterCache=new Map();
function museSvg(v,center,index){
 const s=v.surfaces,px=300/v.width,sy=50/v.depth,sz=1.1;
 const key=[px,sy,s.sink_color,s.faucet_finish].join('|');
 const project=([x,y,z])=>[x*px+18*y/v.depth,-y*sy-z*sz];
 const opening=museSinkAsset.opening_points.map(project);
 const minX=Math.min(...opening.map(p=>p[0]))-1,minY=Math.min(...opening.map(p=>p[1]))-1;
 const w=Math.max(...opening.map(p=>p[0]))-minX+1,h=Math.max(...opening.map(p=>p[1]))-minY+1;
 let url=museRasterCache.get(key);
 if(!url){
  const canvas=document.createElement('canvas');canvas.width=Math.ceil(w*3);canvas.height=Math.ceil(h*3);
  const ctx=canvas.getContext('2d');ctx.scale(3,3);ctx.translate(-minX,-minY);
  const rgb=(colors[s.sink_color]||colors.white).match(/[a-f0-9]{2}/gi).map(v=>parseInt(v,16)),triangles=[];
  for(const part of museSinkAsset.parts){
   const projected=part.vertices.map(project);
   for(const face of part.faces){
    const ids=face.map(i=>Math.abs(i)-1),[a,b,c]=ids.map(i=>part.vertices[i]);
    const u=b.map((q,i)=>q-a[i]),edge=c.map((q,i)=>q-a[i]);
    const n=[u[1]*edge[2]-u[2]*edge[1],u[2]*edge[0]-u[0]*edge[2],u[0]*edge[1]-u[1]*edge[0]];
    if(n[0]*18/(v.depth*px)-n[1]+n[2]*sy/sz<=0)continue;
    const len=Math.hypot(...n)||1,shade=.88+.12*Math.max(0,(-.3*n[0]-.35*n[1]+.89*n[2])/len);
    triangles.push({points:ids.map(i=>projected[i]),order:ids.reduce((sum,i)=>sum-part.vertices[i][1]+part.vertices[i][2]*sy/sz,0)/3,
     fill:part.dark?'#44494a':`rgb(${rgb.map(v=>Math.round(v*shade)).join(',')})`});
   }
  }
  triangles.sort((a,b)=>a.order-b.order);
  for(const t of triangles){
   ctx.beginPath();t.points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();
   ctx.fillStyle=t.fill;ctx.fill();ctx.strokeStyle=t.fill;ctx.lineWidth=.25;ctx.stroke();
  }
  const [dx,dy]=project(museSinkAsset.drain);
  ctx.beginPath();ctx.ellipse(dx,dy,.81*px,.81*sy,0,0,Math.PI*2);ctx.fillStyle=colors[s.faucet_finish];ctx.fill();
  ctx.beginPath();ctx.ellipse(dx,dy,.60*px,.60*sy,0,0,Math.PI*2);ctx.fillStyle='#485052';ctx.fill();
  url=canvas.toDataURL();if(museRasterCache.size>32)museRasterCache.clear();museRasterCache.set(key,url);
 }
 const id='muse-opening-'+index,points=opening.map(p=>p.join(',')).join(' ');
 return `<g data-sink="icera_muse" transform="translate(${center*px+9} ${-s.countertop_thickness*150/v.height-25})">
 <defs><clipPath id="${id}"><polygon points="${points}"/></clipPath></defs>
 <polygon points="${points}" fill="#e2e3df"/>
 <image href="${url}" x="${minX}" y="${minY}" width="${w}" height="${h}" clip-path="url(#${id})"/>
 <polygon points="${points}" fill="none" stroke="#9a9e99" stroke-width=".7"/></g>`;
}
