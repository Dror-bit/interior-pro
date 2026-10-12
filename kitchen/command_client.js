/* Transport only: cabinet defaults and validation belong to the Ruby engine. */
(function(root){
  function commandsFor(name,args){
    if(name==='settings')return [{type:'update_settings',payload:JSON.parse(args[0])}];
    if(name==='apply'){
      const {id,kind,...changes}=JSON.parse(args[0]);
      return [{type:'update_cabinet',payload:{id,changes}}];
    }
    if(name==='remove')return [{type:'remove_cabinet',payload:{id:args[0]}}];
    if(name==='place')return JSON.parse(args[0]).positions.map(({id,x,z,wall,rotation,offset_y})=>({type:'update_cabinet',payload:{id,changes:{x,z,...(wall===undefined?{}:{wall,rotation,offset_y})}}}));
    return null;
  }
  root.KitchenCommands={commandsFor};
})(typeof globalThis==='undefined'?window:globalThis);
