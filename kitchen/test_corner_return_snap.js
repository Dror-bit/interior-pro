const fs=require('fs'),vm=require('vm');
vm.runInThisContext(fs.readFileSync(process.argv[2]||require('path').join(__dirname,'kitchen_house_placement.js'),'utf8'));
const P=globalThis.KitchenHousePlacement;
function row(id,kind,w,depth,x,y,angle=0,handedness=1){let c={kind,width:w,depth,house_placement:{x,y,angle,handedness}};return P.rowAt({id,cabinet:c,base_z:0,height:34.5},c.house_placement);}
const corner=row('corner','corner_base',38,24,0,0);
for(const gap of [.0752277180792,.5]){
 const moving=row('moving','doors',9,24,0,-47-gap,90);
 const result=P.propose(moving,[0,0],[],1,[corner,moving]);
 if(result.error||result.neighbor!=='corner'||Math.abs(result.placement.y+47)>1e-8)throw Error('Return corner snap failed: '+JSON.stringify(result));
}
const straight=row('straight','doors',36,24,38.1,0);
if(Math.abs(P.propose(straight,[0,0],[],1,[corner,straight]).placement.x-38)>1e-8)throw Error('Straight corner end failed');
const far=row('far','doors',9,24,0,-52,90);
if(P.propose(far,[0,0],[],1,[corner,far]).neighbor)throw Error('Snapped outside tolerance');
const upper={...corner,base_z:54};
if(P.propose(row('moving','doors',9,24,0,-47.1,90),[0,0],[],1,[upper]).neighbor)throw Error('Snapped different elevation');
console.log('PASS perpendicular corner end, straight end, capture tolerance and elevation isolation');
