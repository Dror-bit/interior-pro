// Project the same inch meshes used by SketchUp. Raster cache keeps live edits fast.
const faucetRasterCache=new Map();
function faucetRaster(id,finish,px,py,depth){
 const key=[id,finish,px,py,depth].join('|');
 if(faucetRasterCache.has(key))return faucetRasterCache.get(key);
 const asset=faucetAssets.find(a=>a.id===id);if(!asset)return null;
 const triangles=[],all=[];
 const color=({matte_black:'#25272a',brushed_nickel:'#b8b6af',satin_brass:'#c4a568',chrome:'#bac2c7',brass:'#b39456',black:'#242729'})[finish]||'#b8b6af';
 const rgb=color.match(/[a-f0-9]{2}/gi).map(n=>parseInt(n,16));
 for(const part of asset.parts){
  const projected=part.vertices.map(([x,y,z])=>[x*px+18*y/depth,-50*y/depth-z*py]);
  all.push(...projected);
  for(const face of part.faces){
   const ids=face.map(i=>Math.abs(i)-1),points=ids.map(i=>projected[i]),[a,b,c]=ids.map(i=>part.vertices[i]);
   const u=b.map((v,i)=>v-a[i]),v=c.map((v,i)=>v-a[i]);
   const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],length=Math.hypot(...n)||1;
   const shade=.64+.36*Math.max(0,(-.3*n[0]-.5*n[1]+.8*n[2])/length);
   const fill=part.dark?'#303236':`rgb(${rgb.map(v=>Math.round(Math.min(255,v*shade+18))).join(',')})`;
   triangles.push({points,fill,order:ids.reduce((sum,i)=>{const [x,y,z]=part.vertices[i];return sum+(-y+.06*x+.25*z);},0)/3});
  }
 }
 const xs=all.map(p=>p[0]),ys=all.map(p=>p[1]),minX=Math.min(...xs)-1,minY=Math.min(...ys)-1,w=Math.max(...xs)-minX+1,h=Math.max(...ys)-minY+1;
 const canvas=document.createElement('canvas');canvas.width=Math.ceil(w*3);canvas.height=Math.ceil(h*3);
 const ctx=canvas.getContext('2d');ctx.scale(3,3);ctx.translate(-minX,-minY);
 triangles.sort((a,b)=>a.order-b.order);
 for(const t of triangles){ctx.beginPath();t.points.forEach(([x,y],i)=>i?ctx.lineTo(x,y):ctx.moveTo(x,y));ctx.closePath();ctx.fillStyle=t.fill;ctx.fill();}
 const result={url:canvas.toDataURL(),minX,minY,w,h};
 if(faucetRasterCache.size>64)faucetRasterCache.clear();
 faucetRasterCache.set(key,result);return result;
}
function faucetSvg(v){return sinkCenters(v).map((x,i)=>faucetOneSvg(basinPreview(v,i),x)).join('');}
function faucetOneSvg(v,center){
 const asset=faucetAssets.find(a=>a.id===v.faucet_id);if(!asset)return '';
 const s=v.surfaces,px=300/v.width,py=150/v.height;
 const raster=faucetRaster(asset.id,s.faucet_finish,px,py,v.depth);
 const y=-(s.backsplash_height>0?s.countertop_thickness:0)-asset.bounds[1][1]-.25;
 return [center].map(x=>`<image data-faucet="${asset.id}" data-finish="${s.faucet_finish}" href="${raster.url}" x="${x*px+18+18*y/v.depth+raster.minX}" y="${-50-50*y/v.depth-s.countertop_thickness*py+raster.minY}" width="${raster.w}" height="${raster.h}"/>`).join('');
}
function updateFaucetGallery(){
 const make=el('product').value!=='vanity'||current()?.product_id==='gallery';
 el('faucetSettings').hidden=make;
 const selected=el('faucet_id').value,finish=el('faucet_finish').value;
 el('faucetLabel').textContent=faucetAssets.find(a=>a.id===selected)?.label||'ללא ברז';
 const grid=el('faucetCards');
 if(grid.dataset.finish!==finish){
  grid.innerHTML=faucetAssets.map(a=>{
   const preset=({chrome:'brushed_nickel',brass:'satin_brass',black:'matte_black'})[finish]||finish;
   return `<button type="button" data-faucet-choice="${a.id}" onclick="selectFaucet('${a.id}')"><img src="faucets/${a.id}-${preset}.png" alt=""><span dir="ltr">${a.label}</span></button>`;
  }).join('');grid.dataset.finish=finish;
 }
 grid.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.faucetChoice===selected)));
}
function selectFaucet(id){el('faucet_id').value=id;update();}
