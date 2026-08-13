# encoding: utf-8
# plan_sheet_dialog.rb - the sheet window. See the page before it is printed.
#
# Shows the drawing document exactly as it will come out: pick the page size
# and the scale from the lists, drag the plan where you want it, turn layers
# off, then press Export PDF. Nothing is decided for the user.
#
# Ruby owns the document (plan_doc.rb) and the plan (plan_canvas.rb).
# The window only draws it and sends back what the user changed, so the
# preview and the PDF can never disagree - they are the same document.
#
#   InteriorPro::PlanSheetDialog.show

require 'json'

module InteriorPro
  module PlanSheetDialog
    ATTR_DICT  = 'InteriorPro'    unless const_defined?(:ATTR_DICT, false)
    ATTR_STATE = 'sheet_state'    unless const_defined?(:ATTR_STATE, false)

    class << self
      def show
        if @dialog
          begin; @dialog.close; rescue StandardError; end
          @dialog = nil
        end
        # Always read the model again when the window opens. Otherwise a door
        # or a window added since last time would be missing from the sheet
        # and from the tables (2026-08-12, the user hit exactly this).
        @doc = nil

        dlg = UI::HtmlDialog.new(
          dialog_title: 'Interior Pro - Sheet',
          preferences_key: 'InteriorPro_PlanSheet',
          width: 1180, height: 820, resizable: true
        )

        dlg.add_action_callback('sheet_ready') { |_| push_all(dlg) }

        dlg.add_action_callback('rebuild') do |_|
          @doc = nil
          push_all(dlg)
        end

        dlg.add_action_callback('set_state') do |_, json|
          begin
            st = JSON.parse(json.to_s)
            save_state(st)
            apply_state!(document, st)
            push_pages(dlg)
          rescue StandardError => e
            puts "[Sheet] set_state: #{e.message}"
          end
        end

        dlg.add_action_callback('export_pdf') do |_, json|
          begin
            st = JSON.parse(json.to_s)
            save_state(st)
            apply_state!(document, st)
            path = UI.savepanel('Save the sheet as PDF', default_dir,
                                default_name(st))
            if path
              path = "#{path}.pdf" unless path.downcase.end_with?('.pdf')
              InteriorPro::PlanPDF.export(document, path)
              dlg.execute_script("exportDone(#{JSON.generate(path)})")
            else
              dlg.execute_script('exportDone(null)')
            end
          rescue StandardError => e
            puts "[Sheet] export_pdf: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
            dlg.execute_script("exportFailed(#{JSON.generate(e.message)})")
          end
        end

        dlg.set_html(html)
        dlg.show
        @dialog = dlg
        dlg
      end

      # ------------------------------------------------------------ document

      def document
        @doc ||= begin
          st = load_state
          InteriorPro::PlanCanvas.build_document(
            Sketchup.active_model,
            size: st['size'], orientation: (st['orientation'] || 'landscape').to_sym,
            scale: st['scale'], address: st['address'],
            sheet_number: st['sheet_number'], sheet_title: st['sheet_title'],
            date: st['date']
          ).tap { |d| apply_state!(d, st) }
        end
      end

      # Everything the user can change, put back onto the document. Every page
      # is rebuilt out of his choices, so the window and the PDF cannot drift
      # apart - there is only one layout routine and they both run it.
      def apply_state!(doc, st)
        doc.job_address = st['address'].to_s if st.key?('address')
        doc.date        = st['date'] if st.key?('date')
        InteriorPro::PlanCanvas.layout_pages!(doc, st)
        doc
      end

      # ---------------------------------------------------------------- push

      def push_all(dlg)
        d = document
        payload = {
          doc: d.to_h,
          state: load_state,
          page_sizes: InteriorPro::PlanDoc.page_size_names,
          scales: InteriorPro::PlanDoc.scale_labels,
          bounds: d.canvas('MODEL').bounds
        }
        dlg.execute_script("loadSheet(#{JSON.generate(payload)})")
      rescue StandardError => e
        puts "[Sheet] push_all: #{e.message}\n#{e.backtrace.first(4).join("\n")}"
      end

      # Only the paper changes when a control moves; the plan itself does not,
      # so the shapes stay where they are in the window.
      def push_pages(dlg)
        d = document
        dlg.execute_script("applyPages(#{JSON.generate(d.pages.map(&:to_h))})")
      rescue StandardError => e
        puts "[Sheet] push_pages: #{e.message}"
      end

      # --------------------------------------------------------------- state

      DEFAULT_STATE = {
        'size' => 'ARCH D', 'orientation' => 'landscape', 'scale' => '1/4"',
        'address' => '', 'sheet_number' => 'A-101', 'sheet_title' => 'FLOOR PLAN',
        'hidden' => [], 'tables_own_page' => true
      }.freeze unless const_defined?(:DEFAULT_STATE, false)

      def load_state
        raw = Sketchup.active_model.get_attribute(ATTR_DICT, ATTR_STATE)
        st  = raw ? JSON.parse(raw.to_s) : {}
        DEFAULT_STATE.merge(st)
      rescue StandardError
        DEFAULT_STATE.dup
      end

      def save_state(st)
        keep = DEFAULT_STATE.keys + %w[origin_x origin_y date active zoom]
        clean = st.select { |k, _| keep.include?(k) }
        Sketchup.active_model.set_attribute(ATTR_DICT, ATTR_STATE, JSON.generate(clean))
      rescue StandardError => e
        puts "[Sheet] save_state: #{e.message}"
      end

      def default_dir
        home = ENV['USERPROFILE'] || ENV['HOME'] || '.'
        d = File.join(home.tr('\\', '/'), 'Desktop')
        File.directory?(d) ? d : home.tr('\\', '/')
      end

      def default_name(st)
        base = st['sheet_number'].to_s.strip
        base = 'plan' if base.empty?
        "#{base.gsub(/[^A-Za-z0-9._-]/, '_')}.pdf"
      end

      # ---------------------------------------------------------------- html

      def html
        <<~'HTML'
          <!DOCTYPE html>
          <html><head><meta charset="utf-8">
          <style>
            * { box-sizing: border-box; }
            body { margin:0; font:13px/1.4 Segoe UI, Arial, sans-serif;
                   background:#3a3a3a; color:#eee; display:flex; height:100vh; }
            #side { width:230px; flex:none; background:#2b2b2b; padding:12px;
                    overflow:auto; border-right:1px solid #111; }
            #stage { flex:1; overflow:auto; position:relative; padding:20px;
                     display:flex; align-items:flex-start; justify-content:center; }
            #sheetWrap { background:#fff; box-shadow:0 0 22px rgba(0,0,0,.55);
                         flex:none; margin:auto; }
            #zoombar { position:absolute; right:14px; bottom:14px; display:flex; gap:4px;
                       background:#2b2b2b; border:1px solid #555; border-radius:4px;
                       padding:4px; z-index:5; }
            #zoombar button { width:34px; margin:0; padding:4px 0; }
            #zoombar button.wide { width:52px; font-size:12px; }
            h4 { margin:14px 0 6px; font-size:11px; letter-spacing:.08em;
                 text-transform:uppercase; color:#9a9a9a; font-weight:600; }
            h4:first-child { margin-top:0; }
            select, input { width:100%; padding:5px 6px; background:#1e1e1e; color:#eee;
                            border:1px solid #555; border-radius:3px; font-size:13px; }
            .row { display:flex; gap:6px; }
            button { width:100%; padding:8px; margin-top:6px; background:#4a4a4a;
                     color:#fff; border:1px solid #666; border-radius:3px; cursor:pointer;
                     font-size:13px; }
            button:hover { background:#5a5a5a; }
            button.go { background:#1f6feb; border-color:#1f6feb; font-weight:600; }
            button.go:hover { background:#2b7cf7; }
            button.go2 { background:#3b5a86; border-color:#4a6ea3; font-weight:600; }
            button.go2:hover { background:#47699b; }
            label.chk { display:flex; align-items:center; gap:7px; padding:3px 0;
                        cursor:pointer; font-size:13px; }
            label.chk input { width:auto; }
            #msg { margin-top:10px; font-size:12px; color:#9ecbff; min-height:16px;
                   word-break:break-all; }
            #fit { font-size:12px; color:#c9c9c9; margin-top:6px; }
            .hint { font-size:11px; color:#888; margin-top:4px; }
          </style></head>
          <body>
            <div id="side">
              <h4>דף</h4>
              <select id="page"></select>

              <h4>גודל דף</h4>
              <select id="size"></select>
              <div class="row" style="margin-top:6px">
                <button id="land">לרוחב</button>
                <button id="port">לאורך</button>
              </div>

              <h4>קנה מידה</h4>
              <select id="scale"></select>
              <div id="fit"></div>

              <h4>שכבות</h4>
              <div id="layers"></div>
              <label class="chk" style="margin-top:6px">
                <input type="checkbox" id="ownpage"> טבלאות בדף נפרד
              </label>

              <h4>טייטל בלוק</h4>
              <input id="address" placeholder="Job address">
              <div class="row" style="margin-top:6px">
                <input id="num" placeholder="A-101">
                <input id="title" placeholder="FLOOR PLAN">
              </div>

              <h4>&nbsp;</h4>
              <button id="fitplan" class="go2">התאם את התוכנית לדף</button>
              <button id="center">מרכז את התוכנית</button>
              <button id="rebuild">קרא שוב מהמודל</button>
              <button id="pdf" class="go">Export PDF</button>
              <div class="hint">גרירה = מזיז את התוכנית על הדף.<br>
                גלגלת = זום פנימה והחוצה.<br>
                Shift+גרירה = מזיז את הדף עצמו.</div>
              <div id="msg"></div>
            </div>
            <div id="stage">
              <div id="sheetWrap"></div>
              <div id="zoombar">
                <button id="zout">&minus;</button>
                <button id="zfit" class="wide">התאם</button>
                <button id="zin">+</button>
              </div>
            </div>

          <script>
          var DOC=null, STATE=null, PAGE=null, BOUNDS=null, SCALES=[];
          var SF = {};      // scale label -> paper inches per model inch
          var ZOOM = null;  // null = fit the window; otherwise a multiplier

          function $(id){ return document.getElementById(id); }

          function scaleFactor(lbl){ return SF[lbl] || 0.25/12; }

          // ---- drawing ---------------------------------------------------
          function esc(s){ return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }

          function shapeSVG(s, tp, k){
            var o=[];
            function P(x,y){ var p=tp(x,y); return (p[0]*k).toFixed(2)+','+((PAGE.height-p[1])*k).toFixed(2); }
            var w = ((s.weight||0.012)*k).toFixed(2);
            if(s.type==='line'){
              o.push('<line x1="'+P(s.x1,s.y1).split(',')[0]+'" y1="'+P(s.x1,s.y1).split(',')[1]+
                     '" x2="'+P(s.x2,s.y2).split(',')[0]+'" y2="'+P(s.x2,s.y2).split(',')[1]+
                     '" stroke="#000" stroke-width="'+Math.max(w,0.6)+'"/>');
            } else if(s.type==='polyline'||s.type==='polygon'){
              var pts=s.points.map(function(p){ return P(p[0],p[1]); }).join(' ');
              if(s.fill){
                var c='rgb('+s.fill[0]+','+s.fill[1]+','+s.fill[2]+')';
                o.push('<polygon points="'+pts+'" fill="'+c+'" stroke="none"/>');
              } else {
                o.push('<'+(s.closed?'polygon':'polyline')+' points="'+pts+
                       '" fill="none" stroke="#000" stroke-width="'+Math.max(w,0.6)+'"/>');
              }
            } else if(s.type==='text'){
              var p=tp(s.x,s.y), px=p[0]*k, py=(PAGE.height-p[1])*k;
              // text drawn on the plan is in model inches and shrinks with the
              // scale; text put straight on the sheet is already paper inches.
              var hp = s.h * (s.__paper ? 1 : scaleFactor(STATE.scale));
              var fs = hp * k / 0.717;
              if(fs<1.5) return '';
              var anchor = s.__paper ? 'start' : 'middle';
              var base   = s.__paper ? 'alphabetic' : 'central';
              var rot = s.rotation ? ' transform="rotate('+(-s.rotation)+','+px.toFixed(1)+','+py.toFixed(1)+')"' : '';
              o.push('<text x="'+px.toFixed(1)+'" y="'+py.toFixed(1)+'" font-family="Helvetica,Arial"'+
                     ' font-size="'+fs.toFixed(1)+'" text-anchor="'+anchor+'" dominant-baseline="'+base+
                     '" fill="#000"'+(s.bold?' font-weight="700"':'')+(s.italic?' font-style="italic"':'')+
                     rot+'>'+esc(s.text)+'</text>');
            } else if(s.type==='table'){
              var cols=s.col_widths||[], rh=s.row_h||0.22, th=s.h||0.1;
              var all=[s.headers||[]].concat(s.rows||[]);
              var tw=cols.reduce(function(a,b){return a+b;},0);
              function L(x1,y1,x2,y2){
                o.push('<line x1="'+(x1*k).toFixed(1)+'" y1="'+((PAGE.height-y1)*k).toFixed(1)+
                       '" x2="'+(x2*k).toFixed(1)+'" y2="'+((PAGE.height-y2)*k).toFixed(1)+
                       '" stroke="#000" stroke-width="0.7"/>');
              }
              for(var i=0;i<=all.length;i++) L(s.x, s.y-i*rh, s.x+tw, s.y-i*rh);
              var xa=0;
              L(s.x, s.y, s.x, s.y-all.length*rh);
              for(var c=0;c<cols.length;c++){ xa+=cols[c]; L(s.x+xa, s.y, s.x+xa, s.y-all.length*rh); }
              all.forEach(function(row,ri){
                var cx=0;
                row.forEach(function(cell,ci){
                  var fs=th*k/0.717;
                  if(fs>=1.5&&cell) o.push('<text x="'+((s.x+cx+0.05)*k).toFixed(1)+'" y="'+
                    ((PAGE.height-(s.y-(ri+1)*rh+rh*0.3))*k).toFixed(1)+
                    '" font-family="Helvetica,Arial" font-size="'+fs.toFixed(1)+
                    '" fill="#000"'+(ri===0?' font-weight="700"':'')+'>'+esc(cell)+'</text>');
                  cx+=cols[ci]||1.2;
                });
              });
            } else if(s.type==='image'){
              var a=tp(s.x,s.y);
              o.push('<rect x="'+(a[0]*k).toFixed(1)+'" y="'+((PAGE.height-(s.y+s.h))*k).toFixed(1)+
                     '" width="'+(s.w*k).toFixed(1)+'" height="'+(s.h*k).toFixed(1)+
                     '" fill="none" stroke="#bbb" stroke-dasharray="3 3"/>');
            }
            return o.join('');
          }

          function activePage(){
            if(!DOC||!DOC.pages.length) return null;
            var i=STATE.active||0;
            return DOC.pages[i]||DOC.pages[0];
          }

          function fitK(){
            var stage=$('stage');
            return Math.min((stage.clientWidth-56)/PAGE.width,(stage.clientHeight-56)/PAGE.height);
          }

          function render(){
            PAGE=activePage();
            if(!DOC||!PAGE) return;
            var k=fitK()*(ZOOM||1);
            var W=PAGE.width*k, H=PAGE.height*k;
            function same(x,y){ return [x,y]; }

            var o=['<svg xmlns="http://www.w3.org/2000/svg" width="'+W.toFixed(0)+'" height="'+H.toFixed(0)+
                   '" viewBox="0 0 '+W.toFixed(0)+' '+H.toFixed(0)+'" style="display:block">'];
            o.push('<rect width="100%" height="100%" fill="#fff"/>');

            var v=(PAGE.views||[])[0];
            if(v){
              var sf=scaleFactor(STATE.scale);
              var cx=v.x+v.w/2, cy=v.y+v.h/2;
              var toPaper=function(mx,my){ return [cx+(mx-STATE.origin_x)*sf, cy+(my-STATE.origin_y)*sf]; };
              o.push('<clipPath id="vclip"><rect x="'+(v.x*k).toFixed(1)+'" y="'+((PAGE.height-v.y-v.h)*k).toFixed(1)+
                     '" width="'+(v.w*k).toFixed(1)+'" height="'+(v.h*k).toFixed(1)+'"/></clipPath>');
              o.push('<g clip-path="url(#vclip)">');
              var cv=(DOC.canvases||[]).filter(function(c){ return c.name===v.canvas; })[0];
              if(cv) cv.layers.forEach(function(l){
                if(STATE.hidden.indexOf(l.name)>=0) return;
                l.shapes.forEach(function(s){ o.push(shapeSVG(s,toPaper,k)); });
              });
              o.push('</g>');
              // the window itself, so the user can see where the plan may sit
              o.push('<rect x="'+(v.x*k).toFixed(1)+'" y="'+((PAGE.height-v.y-v.h)*k).toFixed(1)+
                     '" width="'+(v.w*k).toFixed(1)+'" height="'+(v.h*k).toFixed(1)+
                     '" fill="none" stroke="#bcd" stroke-width="1" stroke-dasharray="5 4"/>');
            }

            (PAGE.layers||[]).forEach(function(l){
              if(STATE.hidden.indexOf(l.name)>=0) return;
              l.shapes.forEach(function(s){ s.__paper=true; o.push(shapeSVG(s,same,k)); });
            });
            o.push('</svg>');
            $('sheetWrap').innerHTML=o.join('');
            hookDrag();
          }

          function setZoom(z){
            ZOOM = z;
            STATE.zoom = z;
            render();
          }

          // ---- dragging the plan -----------------------------------------
          var DRAG=null;
          function hookDrag(){
            var svg=$('sheetWrap').firstChild;
            if(!svg) return;
            svg.style.cursor='grab';
            svg.onmousedown=function(e){
              var stage=$('stage');
              var pan = e.shiftKey || e.button===1 || !(PAGE.views||[])[0];
              DRAG={x:e.clientX,y:e.clientY,ox:STATE.origin_x,oy:STATE.origin_y,
                    pan:pan, sl:stage.scrollLeft, st:stage.scrollTop};
              svg.style.cursor= pan ? 'move' : 'grabbing';
              e.preventDefault();
            };
          }

          function onMove(e){
            if(!DRAG) return;
            var stage=$('stage');
            if(DRAG.pan){
              stage.scrollLeft = DRAG.sl-(e.clientX-DRAG.x);
              stage.scrollTop  = DRAG.st-(e.clientY-DRAG.y);
              return;
            }
            var k=fitK()*(ZOOM||1);
            var sf=scaleFactor(STATE.scale);
            STATE.origin_x=DRAG.ox-(e.clientX-DRAG.x)/k/sf;
            STATE.origin_y=DRAG.oy+(e.clientY-DRAG.y)/k/sf;
            render();
          }

          function onUp(){
            if(!DRAG) return;
            var moved=!DRAG.pan;
            DRAG=null;
            var svg=$('sheetWrap').firstChild;
            if(svg) svg.style.cursor='grab';
            if(moved) push();
          }

          // ---- talking to Ruby -------------------------------------------
          function push(){ sketchup.set_state(JSON.stringify(STATE)); }

          function loadSheet(p){
            DOC=p.doc; STATE=p.state; BOUNDS=p.bounds; SCALES=p.scales;
            if(STATE.active===undefined||STATE.active===null) STATE.active=0;
            ZOOM = STATE.zoom || null;
            PAGE=DOC.pages[0];
            SF={};
            // 12" = 1' means one foot of building is 12 paper inches
            var per={'12"':12,'6"':6,'3"':3,'1-1/2"':1.5,'1"':1,'3/4"':0.75,'1/2"':0.5,
                     '3/8"':0.375,'1/4"':0.25,'3/16"':0.1875,'1/8"':0.125,'3/32"':0.09375,
                     '1/16"':0.0625,'1/32"':0.03125,'1/64"':0.015625,'1/128"':0.0078125};
            SCALES.forEach(function(s){ SF[s]=(per[s]||0.25)/12; });
            if(STATE.origin_x===undefined||STATE.origin_x===null) centerPlan(true);
            fill('size',p.page_sizes,STATE.size);
            fill('scale',SCALES,STATE.scale);
            $('address').value=DOC.job_address||'';
            $('num').value=STATE.sheet_number||'';
            $('title').value=STATE.sheet_title||'';
            $('ownpage').checked = STATE.tables_own_page!==false;
            buildLayers();
            fillPages();
            showFit();
            render();
          }

          function applyPages(pages){
            DOC.pages=pages;
            if(STATE.active>=pages.length) STATE.active=0;
            fillPages();
            buildLayers();
            showFit();
            render();
          }

          function fillPages(){
            var el=$('page'); el.innerHTML='';
            (DOC.pages||[]).forEach(function(p,i){
              var o=document.createElement('option');
              o.value=i; o.textContent=(i+1)+' - '+p.name;
              if(i===(STATE.active||0)) o.selected=true;
              el.appendChild(o);
            });
            el.disabled = (DOC.pages||[]).length<2;
          }

          function fill(id,list,val){
            var el=$(id); el.innerHTML='';
            list.forEach(function(s){
              var o=document.createElement('option'); o.value=s; o.textContent=s;
              if(s===val) o.selected=true; el.appendChild(o);
            });
          }

          function buildLayers(){
            var box=$('layers'); box.innerHTML='';
            var names=[];
            function add(n){ if(names.indexOf(n)<0) names.push(n); }
            (DOC.canvases||[]).forEach(function(c){ c.layers.forEach(function(l){ add(l.name); }); });
            // every sheet's layers, so a layer that moved to another page can
            // still be turned off from here
            (DOC.pages||[]).forEach(function(p){ (p.layers||[]).forEach(function(l){ add(l.name); }); });
            if(STATE.hidden.indexOf('SCHEDULES')>=0) add('SCHEDULES');
            names.forEach(function(n){
              var lab=document.createElement('label'); lab.className='chk';
              var cb=document.createElement('input'); cb.type='checkbox';
              cb.checked=STATE.hidden.indexOf(n)<0;
              cb.onchange=function(){
                var i=STATE.hidden.indexOf(n);
                if(cb.checked){ if(i>=0) STATE.hidden.splice(i,1); } else if(i<0) STATE.hidden.push(n);
                render(); push();
              };
              lab.appendChild(cb);
              lab.appendChild(document.createTextNode(n));
              box.appendChild(lab);
            });
          }

          function centerPlan(quiet){
            if(!BOUNDS) return;
            STATE.origin_x=(BOUNDS[0]+BOUNDS[2])/2;
            STATE.origin_y=(BOUNDS[1]+BOUNDS[3])/2;
            if(!quiet){ render(); push(); }
          }

          // The user pressed a button, so this one MAY change the scale: the
          // biggest one in his list that holds the whole drawing, centred.
          function fitPlan(){
            var pg=activePage(), v=pg&&(pg.views||[])[0];
            if(!BOUNDS||!v) return;
            var best=null;
            SCALES.forEach(function(s){
              if(best) return;
              if((BOUNDS[2]-BOUNDS[0])*SF[s]<=v.w&&(BOUNDS[3]-BOUNDS[1])*SF[s]<=v.h) best=s;
            });
            if(best){ STATE.scale=best; $('scale').value=best; }
            centerPlan(true);
            ZOOM=null; STATE.zoom=null;
            showFit(); render(); push();
          }

          // says what would fit. never changes the scale by itself.
          function showFit(){
            var pg=activePage();
            var v=pg&&(pg.views||[])[0];
            if(!BOUNDS||!v){ $('fit').textContent=''; return; }
            var sf=scaleFactor(STATE.scale);
            var mw=(BOUNDS[2]-BOUNDS[0])*sf, mh=(BOUNDS[3]-BOUNDS[1])*sf;
            if(mw<=v.w&&mh<=v.h){ $('fit').textContent='נכנס בדף ✓'; $('fit').style.color='#8fdf8f'; return; }
            var best=null;
            SCALES.forEach(function(s){
              if(best) return;
              var f=SF[s];
              if((BOUNDS[2]-BOUNDS[0])*f<=v.w&&(BOUNDS[3]-BOUNDS[1])*f<=v.h) best=s;
            });
            $('fit').textContent='לא נכנס. הכי גדול שנכנס: '+(best||'—');
            $('fit').style.color='#f0a860';
          }

          function exportDone(path){
            $('msg').textContent = path ? ('נשמר: '+path) : 'בוטל';
          }
          function exportFailed(m){ $('msg').textContent='שגיאה: '+m; }

          // ---- wiring -----------------------------------------------------
          window.addEventListener('load',function(){
            $('size').onchange=function(){ STATE.size=this.value; push(); };
            $('scale').onchange=function(){ STATE.scale=this.value; showFit(); render(); push(); };
            $('page').onchange=function(){ STATE.active=parseInt(this.value,10)||0; showFit(); render(); push(); };
            $('ownpage').onchange=function(){ STATE.tables_own_page=this.checked; push(); };
            $('zin').onclick=function(){ setZoom((ZOOM||1)*1.3); };
            $('zout').onclick=function(){ setZoom(Math.max((ZOOM||1)/1.3,0.2)); };
            $('zfit').onclick=function(){ setZoom(null); };
            $('stage').addEventListener('wheel',function(e){
              e.preventDefault();
              var z=(ZOOM||1)*(e.deltaY<0?1.15:1/1.15);
              setZoom(Math.min(Math.max(z,0.2),14));
            },{passive:false});
            window.addEventListener('mousemove',onMove);
            window.addEventListener('mouseup',onUp);
            $('land').onclick=function(){ STATE.orientation='landscape'; push(); };
            $('port').onclick=function(){ STATE.orientation='portrait'; push(); };
            $('center').onclick=function(){ centerPlan(false); };
            $('fitplan').onclick=function(){ fitPlan(); };
            $('rebuild').onclick=function(){ sketchup.rebuild(); };
            $('pdf').onclick=function(){ $('msg').textContent='שומר...'; sketchup.export_pdf(JSON.stringify(STATE)); };
            ['address','num','title'].forEach(function(id){
              $(id).onchange=function(){
                STATE.address=$('address').value;
                STATE.sheet_number=$('num').value;
                STATE.sheet_title=$('title').value;
                push();
              };
            });
            window.addEventListener('resize',render);
            sketchup.sheet_ready();
          });
          </script></body></html>
        HTML
      end
    end
  end
end
