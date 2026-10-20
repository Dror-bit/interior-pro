const fs=require('fs'),vm=require('vm'),assert=require('assert');
const script=fs.readFileSync(__dirname+'/editor.html','utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
class Element{constructor(){this.value='';this.options=[];this.attrs={};}replaceChildren(...v){this.options=v;}add(v){this.options.push(v);}append(...v){this.options.push(...v);}setAttribute(k,v){this.attrs[k]=v;}reportValidity(){return (this.min===undefined||Number(this.value)>=Number(this.min))&&(this.max===undefined||Number(this.value)<=Number(this.max));}}
const elements={},messages=[],catalog=JSON.parse(fs.readFileSync(__dirname+'/../laundry/catalog_test_products.json'));
const context=vm.createContext({catalog,document:{getElementById:id=>elements[id]??=new Element(),createElement:()=>new Element()},Option:function(text,value){return {text,value};},window:{sketchup:{action:s=>messages.push(JSON.parse(s)),ready(){}},addEventListener(){}}});
const run=s=>vm.runInContext(s,context);run(script);
run(`render({domain:'laundry',assembly_id:'new',revision:0,cabinets:[]},null,true,catalog);el('product').value='upper';selectProduct();send('place2d');`);
assert.equal(messages.at(-1).product,'upper');assert.equal(messages.at(-1).values.position.z,66);assert.equal(messages.at(-1).values.height,30);assert.equal(messages.at(-1).values.shelves,2);
for(const type of ['washer','dryer','washer_top','dryer_rear','stack','pair_front','pair_top']){
 run(`el('product').value='${type}';selectProduct();send('place2d')`);
 assert.equal(messages.at(-1).product,type);assert.equal(elements.width.readOnly,true);assert.equal(elements.finish.disabled,true);assert.equal(messages.at(-1).values.front,'appliance');assert.equal(messages.at(-1).values.position.z,0);
 assert.equal(messages.at(-1).values.width,catalog[type].template.width);assert.equal(messages.at(-1).values.height,catalog[type].template.height);
}
run(`el('product').value='upper';selectProduct();send('place2d');`);assert.equal(messages.at(-1).product,'upper');assert.equal(elements.width.max,48,'Appliance size lock leaked into cabinet limits');
run(`render({domain:'laundry',assembly_id:'new',revision:2,cabinets:[{...catalog.upper.template,id:'upper-1',position:{x:10,y:15,z:72,angle:90}}]},'upper-1',true,catalog);el('elevation').value=75;send('save')`);
assert.equal(messages.at(-1).values.position.z,75);assert.equal(messages.at(-1).values.position.x,10);assert.equal(messages.at(-1).values.position.angle,90);assert.equal(elements.product.disabled,true);
run(`render({domain:'wardrobe',assembly_id:'ward',revision:0,cabinets:[]},null,true,catalog);send('place')`);
assert.equal(elements.productChooser.hidden,true);assert.equal(elements.upperFields.hidden,true);assert.equal(elements.width.readOnly,false);assert.equal(elements.finish.disabled,false);assert.equal(messages.at(-1).values.position.z,0);
console.log('PASS: laundry product chooser, fixed LG dimensions, stack/side-by-side/top-load options, elevated upper create/edit and wardrobe isolation.');
