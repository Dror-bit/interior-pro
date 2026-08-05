# encoding: utf-8
<<~HTML
          <!DOCTYPE html>
          <html><head><meta charset="utf-8"><style>
            html, body { margin:0; height:100%; overflow:hidden; font-family:Arial,sans-serif; font-size:13px; }
            #top { height:36px; background:#2f3542; color:#fff; display:flex; align-items:center; padding:0 10px; gap:8px; overflow:hidden; }
            #top .title { font-weight:bold; margin-right:auto; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
            #top button { flex:0 0 auto; white-space:nowrap; }
            button { border:0; border-radius:4px; padding:5px 10px; cursor:pointer; font-size:12px; }
            .blue { background:#4b89ff; color:#fff; } .gray { background:#57606f; color:#fff; }
            .red { background:#e0392b; color:#fff; }
            #main { display:flex; height:calc(100% - 66px); min-width:0; }
            /* min-width:0 + overflow:hidden let the canvas shrink instead of
               pushing the side panel off-screen at small window sizes. */
            #canvasWrap { flex:1 1 auto; min-width:0; overflow:hidden; position:relative; background:#fbfcfe; }
            canvas { display:block; }
            #side { flex:0 0 200px; width:200px; box-sizing:border-box; background:#f4f6f9; border-left:1px solid #d6dae0; padding:10px; overflow-y:auto; display:flex; flex-direction:column; }
            /* underBox already carries the margin-top:auto that pins the tail of
               the panel to the bottom - undo just follows it. */
            #undoWrap { margin-top:0; padding-top:10px; text-align:right; }
            #undoWrap button { display:inline-flex; align-items:center; gap:6px; }
            #side label { display:block; margin:8px 0 3px; color:#333; }
            #side input[type=text] { width:70px; padding:3px; border:1px solid #c3c9d1; border-radius:3px; }
            #side select { width:100%; padding:3px; border:1px solid #c3c9d1; border-radius:3px; }
            .seg { display:flex; gap:4px; }
            .seg button { background:#fff; border:1px solid #c3c9d1; color:#333; }
            .seg button.on { background:#dce9ff; border-color:#4b89ff; }
            #bottom { height:30px; background:#eceff3; border-top:1px solid #d6dae0; display:flex; align-items:center; padding:0 10px; gap:10px; overflow:hidden; }
            #vcb { background:#fffbe6; border:1px solid #e0b400; border-radius:3px; padding:3px 8px; min-width:70px; font-weight:bold; flex:0 0 auto; }
            #hint { color:#777; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
            #status { margin-top:14px; color:#555; font-size:12px; }
            .okmsg { color:#1a9d55; }
            .modebtn { flex:0 0 47%; margin-bottom:4px; }
            /* SketchUp-style dark tool strip: icon-only, grouped, 2 rows. */
            .sktb { display:flex; background:#26282d; border-radius:8px; padding:4px; gap:0; margin-bottom:8px; }
            .sktb-g { display:grid; grid-auto-flow:column; grid-template-rows:repeat(2, 26px); gap:2px; padding:0 4px; }
            .sktb-g + .sktb-g { border-left:1px solid #3d4148; }
            .sktb button { width:26px; height:26px; padding:0; border:0; border-radius:5px;
                           background:transparent; color:#cdd1d6; display:flex;
                           align-items:center; justify-content:center; cursor:pointer; }
            .sktb button:hover { background:#34373d; color:#ffffff; }
            .sktb button.on { background:#2f7de1; color:#ffffff; }
            .sktb button.danger:hover { background:#c62828; color:#ffffff; }
            /* Helper panels are parked at the BOTTOM and stay folded, so the
               side panel never shifts around while a tool section opens above.
               Guides and the background image both live here. */
            #botWrap { margin-top:auto; }
            .foldBox { background:#eef1f6; border:1px solid #d6dae0; border-radius:8px;
                       overflow:hidden; margin-top:8px; }
            .foldHead { display:flex; align-items:center; gap:6px; padding:7px 9px;
                        cursor:pointer; font-size:12px; font-weight:bold; color:#444;
                        user-select:none; }
            .foldHead:hover { background:#e4e8ee; }
            .foldBody { padding:0 9px 9px; }
            .foldDot { width:7px; height:7px; border-radius:50%; background:#1a9d55; display:none; }
            .caret { color:#8a8f98; font-size:11px; }
            .toolrow button { flex:1 1 0; display:flex; align-items:center; justify-content:center; padding:5px 0; }
          </style></head><body>
          <div id="top">
            <span class="title">Interior Pro - 2D Editor</span>
            <button class="blue" onclick="applyPending()">Apply to Model</button>
            <button class="gray" onclick="sketchup.build_plan()">Plans (2D)</button>
            <button class="gray" onclick="sketchup.sync_model()">Sync</button>
          </div>
          <div id="main">
            <div id="canvasWrap"><canvas id="cv"></canvas></div>
            <div id="side">
              <div class="seg" style="flex-wrap:wrap">
                <button id="modeSel" class="on modebtn" onclick="setMode('sel')">Select</button>
                <button id="modeWall" class="modebtn" onclick="setMode('wall')">Wall</button>
                <button id="modeDoor" class="modebtn" onclick="setMode('door')">Door</button>
                <button id="modeWin" class="modebtn" onclick="setMode('win')">Window</button>
                <button id="modeLine" class="modebtn" onclick="setMode('line')">Line</button>
              </div>

              <div id="secSel">
                <div id="selInfo" style="margin-top:12px; color:#555; font-size:12px">לא נבחר כלום — לחץ על קיר או פתח</div>
                <div id="editBar" class="sktb" style="display:none; margin-top:8px">
                  <div class="sktb-g">
                    <button id="ebRotFree" title="Free rotate - drag to any angle" onclick="startFreeRotate()"><svg width="16" height="16" viewBox="0 0 24 24"><path d="M4 14 A8 8 0 1 1 12 20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M4 9 L4 14 L9 14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/><circle cx="12" cy="12" r="1.6" fill="currentColor"/></svg></button>
                    <button id="ebMove" title="Free move - drag anywhere" onclick="startFreeMove()"><svg width="16" height="16" viewBox="0 0 24 24"><path d="M12 3 L12 21 M3 12 L21 12" stroke="currentColor" stroke-width="1.7"/><path d="M12 3 L9.5 6 M12 3 L14.5 6 M12 21 L9.5 18 M12 21 L14.5 18 M3 12 L6 9.5 M3 12 L6 14.5 M21 12 L18 9.5 M21 12 L18 14.5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg></button>
                    <button id="ebFlipH" title="Flip horizontal" onclick="flipSel('h')"><span style="font-size:14px">⇄</span></button>
                    <button id="ebFlipV" title="Flip vertical" onclick="flipSel('v')"><span style="font-size:14px">⇅</span></button>
                    <button id="ebArea" title="Area tag - show the square footage on this shape" onclick="toggleSelArea()"><svg width="16" height="16" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M6 15 L11 9 M10 15 L15 9 M14 15 L18 10" stroke="currentColor" stroke-width="1.1"/></svg></button>
                    <button id="ebOff" title="Offset - move the mouse to the side you want" onclick="startFreeOffset()"><svg width="16" height="16" viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6"/><rect x="8.5" y="8.5" width="7" height="7" fill="none" stroke="currentColor" stroke-width="1.6"/></svg></button>
                  </div>
                  <div class="sktb-g">
                    <button id="ebDup" title="Duplicate" onclick="duplicateSel()"><svg width="16" height="16" viewBox="0 0 24 24"><rect x="8" y="8" width="12" height="12" rx="2" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M16 5 L6 5 A2 2 0 0 0 4 7 L4 17" fill="none" stroke="currentColor" stroke-width="1.8"/></svg></button>
                    <button id="ebGrp" title="Group" onclick="groupSel()"><svg width="16" height="16" viewBox="0 0 24 24"><rect x="3" y="3" width="8" height="8" fill="none" stroke="currentColor" stroke-width="1.7"/><rect x="13" y="13" width="8" height="8" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M11 7 L17 7 L17 13" fill="none" stroke="currentColor" stroke-width="1.4" stroke-dasharray="2,2"/></svg></button>
                    <button id="ebUngrp" title="Ungroup" onclick="ungroupSel()"><svg width="16" height="16" viewBox="0 0 24 24"><rect x="3" y="3" width="8" height="8" fill="none" stroke="currentColor" stroke-width="1.7"/><rect x="13" y="13" width="8" height="8" fill="none" stroke="currentColor" stroke-width="1.7"/><path d="M10 14 L14 10" stroke="currentColor" stroke-width="1.6"/></svg></button>
                    <button id="ebDel" class="danger" title="Delete" onclick="deleteSelected()"><span style="font-size:14px">✕</span></button>
                  </div>
                </div>
                <div id="selWallOpts" style="display:none">
                  <label>Length</label><input type="text" id="selLen">
                  <label>Which end moves</label>
                  <div class="seg"><button id="mvS" onclick="setMovingEnd('start')">Start ●</button><button id="mvE" class="on" onclick="setMovingEnd('end')">End ●</button></div>
                  <div style="color:#777; font-size:11px; margin-top:4px">אפשר גם ללחוץ על הפינה עצמה בקנבס — ירוק = הקצה שיזוז, אדום = נשאר</div>
                  <div style="margin-top:6px"><button class="blue" style="width:100%" onclick="applyWallLen()">Apply length</button></div>
                  <label style="margin-top:12px">Move sideways (in)</label>
                  <input type="text" id="selMove" value="6">
                  <div class="seg" style="margin-top:6px">
                    <button onclick="moveWall(1)">Out ▲</button><button onclick="moveWall(-1)">In ▼</button>
                  </div>
                  <div style="color:#777; font-size:11px; margin-top:4px">או פשוט לגרור את הקיר בקנבס</div>
                  <label style="margin-top:12px">Corners</label>
                  <div class="seg">
                    <button id="cnKeep" class="on" onclick="setKeepCorners(true)">Keep joined</button>
                    <button id="cnCut" onclick="setKeepCorners(false)">Detach ✂</button>
                  </div>
                  <div style="color:#777; font-size:11px; margin-top:4px">Detach = הקיר זז/מתארך לבד, בלי לגרור את הקירות בפינות</div>
                  <div style="margin-top:6px"><button class="gray" style="width:100%" onclick="diagWall()">Diag → Ruby Console</button></div>
                </div>
                <div id="selThickOpts" style="display:none">
                  <label>Thickness (in)</label><input type="text" id="selTh">
                  <div style="margin-top:6px"><button class="blue" style="width:100%" onclick="applySelThickness()">Apply thickness</button></div>
                </div>
                <div id="selCopyOpts" style="display:none"></div>
                <div id="selShapeOpts" style="display:none">
                  <div style="color:#777; font-size:11px">
                    הזזה: כלי ← נקודת אחיזה ← הזז · Shift נועל ציר<br>
                    סיבוב: כלי ← מרכז ← נקודת התחלה ← סובב · Shift קפיצות 15°<br>
                    אופסט: כלי ← קו המתאר ← הזז לצד שרוצים<br>
                    בכולם: הקלד מידה + Enter · Esc ביטול
                  </div>
                </div>
                <div id="selSizeOpts" style="display:none">
                  <label>Width (in)</label><input type="text" id="selW">
                  <label>Height (in)</label><input type="text" id="selH">
                  <div id="selHeaderRow"><label>Header (in)</label><input type="text" id="selHead"></div>
                  <div style="margin-top:6px"><button class="blue" style="width:100%" onclick="applySelSize()">Apply size</button></div>
                </div>
                <div id="selDoorOpts" style="display:none">
                  <label>Hinge side</label>
                  <div class="seg"><button id="selSwL" onclick="editSwing('left', false)">L</button><button id="selSwR" onclick="editSwing('right', false)">R</button></div>
                  <div style="margin-top:6px"><button class="gray" style="width:100%" onclick="editSwing(null, true)">Flip In / Out</button></div>
                </div>
                <div style="margin-top:8px; color:#777; font-size:11px">גרור דלת/חלון להזזה לאורך הקיר · מקש Delete מוחק</div>
              </div>

              <div id="secWall">
                <label>Wall type (library)</label><select id="wallType" onchange="wallTypeChanged()"><option value="">Custom</option></select>
                <label>Thickness (in)</label><input type="text" id="th" value="5">
                <label>Height (in)</label><input type="text" id="hh" value="96">
                <label>Category</label>
                <div class="seg"><button id="catE" class="on" onclick="setCat('exterior')">Ext</button><button id="catI" onclick="setCat('interior')">Int</button></div>
                <label>Draw side</label>
                <div class="seg"><button id="sideL" class="on" onclick="setSide('L')">L</button><button id="sideR" onclick="setSide('R')">R</button></div>
              </div>

              <div id="secDoor" style="display:none">
                <label>Category</label>
                <div class="seg"><button id="dCatI" class="on" onclick="setDoorCat('interior')">Int</button><button id="dCatE" onclick="setDoorCat('exterior')">Ext</button></div>
                <label>Type</label><select id="dType" onchange="doorTypeChanged()"></select>
                <label>Width (in)</label><input type="text" id="dW" value="32">
                <label>Height (in)</label><input type="text" id="dH" value="80">
                <label>Hinge side</label>
                <div class="seg"><button id="dSwL" class="on" onclick="setSwing('left')">L</button><button id="dSwR" onclick="setSwing('right')">R</button></div>
                <div style="margin-top:10px; color:#777; font-size:11px">לחץ על קיר במודל (רק קירות שכבר עברו Apply)</div>
              </div>

              <div id="secWin" style="display:none">
                <label>Type</label><select id="wType" onchange="winTypeChanged()"></select>
                <label>Width (in)</label><input type="text" id="wW" value="24">
                <label>Height (in)</label><input type="text" id="wH" value="48">
                <label>Header (in)</label><input type="text" id="wHead" value="80">
                <div style="margin-top:10px; color:#777; font-size:11px">לחץ על קיר במודל (רק קירות שכבר עברו Apply)</div>
              </div>

              <div id="secLine" style="display:none">
                <div class="sktb">
                  <div class="sktb-g">
                    <button id="ltLine" title="Line" onclick="setLineTool('line')"><svg width="18" height="18" viewBox="0 0 24 24"><path d="M4 19 L20 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="4" cy="19" r="2.2" fill="currentColor"/><circle cx="20" cy="5" r="2.2" fill="currentColor"/></svg></button>
                    <button id="ltCirc" title="Circle" onclick="setLineTool('circle')"><svg width="18" height="18" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="2"/></svg></button>
                    <button id="ltArc" title="Arc" onclick="setLineTool('arc')"><svg width="18" height="18" viewBox="0 0 24 24"><path d="M4 18 A12 12 0 0 1 20 18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="4" cy="18" r="2.2" fill="currentColor"/><circle cx="20" cy="18" r="2.2" fill="currentColor"/></svg></button>
                    <button id="ltHex" title="Polygon - type a number then S for the side count" onclick="setLineTool('hex')"><svg width="18" height="18" viewBox="0 0 24 24"><path d="M12 3 L20 7.5 L20 16.5 L12 21 L4 16.5 L4 7.5 Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg></button>
                    <button id="ltRect" title="Rectangle" onclick="setLineTool('rect')"><svg width="18" height="18" viewBox="0 0 24 24"><rect x="4" y="6" width="16" height="12" fill="none" stroke="currentColor" stroke-width="2"/></svg></button>
                    <button id="ltMeas" title="Measure" onclick="setLineTool('measure')"><svg width="18" height="18" viewBox="0 0 24 24"><path d="M3 17 L17 3 L21 7 L7 21 Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M7 13 L9 15 M10 10 L12 12 M13 7 L15 9" stroke="currentColor" stroke-width="1.6"/></svg></button>
                    <button id="ltErase" title="Erase one segment" onclick="setLineTool('erase')"><svg width="18" height="18" viewBox="0 0 24 24"><path d="M10 18 L4 12 L13 3 L20 10 L12 18 Z" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/><path d="M3 21 H21" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>
                  </div>
                  <div class="sktb-g">
                    <button id="lsSolid" title="Solid line" onclick="setLinePreset('solid')"><svg width="18" height="10" viewBox="0 0 24 10"><path d="M2 5 L22 5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg></button>
                    <button id="lsDash" title="Dashed line" onclick="setLinePreset('dashed')"><svg width="18" height="10" viewBox="0 0 24 10"><path d="M2 5 L22 5" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-dasharray="5,4"/></svg></button>
                    <button id="lwThick" title="Thick line" onclick="setLinePreset('thick')"><svg width="18" height="10" viewBox="0 0 24 10"><path d="M2 5 L22 5" stroke="currentColor" stroke-width="4.5" stroke-linecap="round"/></svg></button>
                  </div>
                </div>
                <div id="lineHelp" style="color:#555; font-size:12px">קליק-קליק לציור. חזרה לנקודה הראשונה סוגרת צורה — ואז נוצר משטח במודל.</div>
                <div style="margin-top:8px"><button class="blue" style="width:100%" onclick="closeShape()">Close shape</button></div>
                <div style="margin-top:4px"><button class="gray" style="width:100%" onclick="endLine()">Finish line</button></div>
                <div style="margin-top:10px"><button class="gray" style="width:100%" onclick="undoLinePoint()">Undo last point</button></div>
              </div>

              <div id="status"></div>

              <div id="botWrap">
              <div id="dimBox" class="foldBox">
                <div class="foldHead" onclick="toggleFold('dim')">
                  <span style="flex:1 1 auto">מידות קיר — <span id="dimWhich">כל המידות</span></span>
                  <span id="dimCaret" class="caret">▾</span>
                </div>
                <div id="dimBody" class="foldBody" style="display:none">
                  <div class="seg">
                    <button id="dm_out" onclick="setDimMode('out')">חוץ</button>
                    <button id="dm_in" onclick="setDimMode('in')">פנים</button>
                  </div>
                  <div class="seg" style="margin-top:4px">
                    <button id="dm_both" class="on" onclick="setDimMode('both')">הכל</button>
                    <button id="dm_none" onclick="setDimMode('none')">ללא</button>
                  </div>
                </div>
              </div>

              <div id="guideBox" class="foldBox">
                <div class="foldHead" onclick="toggleFold('guide')">
                  <span id="guideDot" class="foldDot"></span>
                  <span style="flex:1 1 auto">קווי עזר</span>
                  <span id="guideCaret" class="caret">▾</span>
                </div>
                <div id="guideBody" class="foldBody" style="display:none">
                  <div class="seg">
                    <button id="guideBtn" onclick="toggleGuideMode()">קו עזר</button>
                    <button onclick="clearGuides()">נקה עזר</button>
                  </div>
                </div>
              </div>

              <div id="underBox" class="foldBox">
                <div class="foldHead" onclick="toggleFold('under')">
                  <span id="underDot" class="foldDot"></span>
                  <span style="flex:1 1 auto">תמונת רקע</span>
                  <span id="underCaret" class="caret">▾</span>
                </div>
                <div id="underBody" class="foldBody" style="display:none">
                <div class="seg">
                  <button onclick="sketchup.pick_underlay()">טען</button>
                  <button onclick="sketchup.clear_underlay()">הסר</button>
                </div>
                <div id="underRow" style="display:none">
                  <div style="margin-top:6px"><button class="blue" style="width:100%" onclick="startCalib()">כייל לפי מידה</button></div>
                  <label>שקיפות</label>
                  <input type="range" id="underOp" min="10" max="100" value="55" style="width:100%" oninput="setUnderOpacity(this.value)">
                  <div class="seg" style="margin-top:4px">
                    <button id="underLockBtn" class="on" onclick="toggleUnderLock()">נעול</button>
                    <button onclick="fitUnderlay(1)">מרכז</button>
                  </div>
                </div>
                </div>
              </div>
              </div>

              <div id="undoWrap"><button class="gray" id="undoBtn" onclick="undoAction()" title="Undo"><svg width="13" height="13" viewBox="0 0 24 24"><path d="M8 6 L4 10 L8 14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 10 H14 A5 5 0 0 1 14 20 H9" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>Undo</button></div>
            </div>
          </div>
          <div id="hiddenUndo" contenteditable="true" spellcheck="false" style="position:fixed; left:-9999px; top:0; width:10px; height:10px; opacity:0; overflow:hidden"></div>
          <div id="bottom">
            <span>Length:</span><span id="vcb">&nbsp;</span>
                  <span id="dbg" style="color:#b3261e; font-size:10.5px"></span>
            <span id="hint">Ctrl+C / Ctrl+V copy-paste walls · Click to start a wall - move - type length + Enter, or click. Right-click / Esc ends the chain. Wheel = zoom, middle-drag = pan.</span>
          </div>
          <script>
            var cv = document.getElementById('cv'), ctx = cv.getContext('2d');
            var walls = [];          // existing model walls (read-only)
            var pending = [];        // walls drawn here, not yet applied
            var mode = 'sel';
            var sel = null;           // {type:'wall', w} | {type:'sym', w, s} | {type:'pending', i}
            // Multi-select (2026-07-30): selList is the real selection; sel
            // stays as the LAST picked item so every existing single-item code
            // path keeps working untouched. New behaviour only kicks in when
            // selList holds more than one element.
            var selList = [];
            var rubber = null;        // rubber-band rectangle while dragging on empty space

            function selKey(o) {
              if (!o) return '';
              if (o.type === 'wall') return 'w:' + (o.w.id || '');
              if (o.type === 'sym') return 's:' + (o.s.id || '');
              if (o.type === 'sketch') return 'k:' + o.kind + ':' + (o.sk.id || o.i);
              return 'p:' + o.i;
            }
            function setSel(o) { selList = o ? [o] : []; sel = o || null; }
            function toggleSel(o) {
              if (!o) return;
              var k = selKey(o), at = -1;
              for (var i9 = 0; i9 < selList.length; i9++) {
                if (selKey(selList[i9]) === k) { at = i9; break; }
              }
              if (at >= 0) selList.splice(at, 1); else selList.push(o);
              sel = selList.length ? selList[selList.length - 1] : null;
            }
            var dragSym = null;       // {w, s, startT, curT, valid, moved}
            var dragWall = null;      // {w, b, from:{x,y}, off, moved} - sideways move
            var shiftDown = false;    // Shift = lock the current drawing direction (SketchUp style)
            var lockDir = null;       // locked unit direction while Shift is held
            var cat = 'exterior', sideOpt = 'L';
            var doorCat = 'interior', doorSwing = 'left';
            var scale = 1.6, panX = 60, panY = 60;   // model inches -> px
            var drawing = false, startPt = null, cursor = {x:0, y:0};
            var typed = '';
            var panning = false, panFrom = null;
            var fitted = false;
            var hoverHit = null;

            // Fallback catalogs - replaced by the real plugin libraries via
            // loadCatalogs() (DoorLibrary / WindowLibrary / WallLibrary).
            var DOOR_TYPES = {
              interior: ['Single', 'Double', 'Pocket', 'Folding', 'Closet'],
              exterior: ['Front Door', 'French Hinged', 'Sliding', 'Garage Door', 'Arched']
            };
            var DOOR_WH_CAT = null;   // {interior:{type:[w,h]}, exterior:{...}} from Ruby
            var DOOR_WH = { 'Single':[32,80], 'Double':[60,80], 'Pocket':[32,80], 'Folding':[48,80],
                            'Closet':[72,80], 'Front Door':[36,80], 'French Hinged':[60,80],
                            'Sliding':[60,80], 'Garage Door':[192,84], 'Arched':[36,96] };
            var WIN_TYPES = ['Casement', 'Casement XX', 'Single Hung', 'XOX Single Hung',
                             'Slider XO', 'Slider XOX', 'Garden Window', 'Arched'];
            var WIN_WH = { 'Casement':[24,48], 'Casement XX':[48,48], 'Single Hung':[24,36],
                           'XOX Single Hung':[96,48], 'Slider XO':[48,36], 'Slider XOX':[72,48],
                           'Garden Window':[60,48], 'Arched':[36,60] };
            var wallTypes = [];       // model wall types + user's wall library
            var curWallLib = '';      // selected wall type name ('' = custom)
            var modelDoors = {};      // per-category defaults from the model
            var modelWindow = null;

            function loadCatalogs(c) {
              if (!c) return;
              if (c.door_types) DOOR_TYPES = c.door_types;
              if (c.door_wh) DOOR_WH_CAT = c.door_wh;
              if (c.win_types && c.win_types.length) WIN_TYPES = c.win_types;
              if (c.win_wh) WIN_WH = c.win_wh;
              modelDoors = c.model_doors || {};
              modelWindow = c.model_windows || null;
              // Wall types IN THE MODEL come first and are the default.
              wallTypes = (c.model_walls || []).concat(c.wall_types || []);
              var sel2 = document.getElementById('wallType');
              sel2.innerHTML = '';
              var gm = null, gl = null;
              wallTypes.forEach(function(t){
                var o = document.createElement('option');
                o.value = t.name; o.textContent = t.name + ' — ' + t.th + '" (' + t.cat + ')';
                if (t.src === 'model') {
                  if (!gm) { gm = document.createElement('optgroup'); gm.label = 'In model (3D)'; sel2.appendChild(gm); }
                  gm.appendChild(o);
                } else {
                  if (!gl) { gl = document.createElement('optgroup'); gl.label = 'Library'; sel2.appendChild(gl); }
                  gl.appendChild(o);
                }
              });
              var oc = document.createElement('option');
              oc.value = ''; oc.textContent = 'Custom';
              sel2.appendChild(oc);
              // default = first model wall of the current category, else first entry
              var def = wallTypes.find(function(t){ return t.src === 'model' && t.cat === cat; }) ||
                        wallTypes.find(function(t){ return t.src === 'model'; });
              if (def) { sel2.value = def.name; wallTypeChanged(); } else { sel2.value = ''; curWallLib = ''; }
              fillSelect('dType', DOOR_TYPES[doorCat] || []);
              fillSelect('wType', WIN_TYPES);
              applyModelDoorDefaults();
              applyModelWindowDefaults();
            }

            // Door/window fields default to what was last placed in the model.
            function applyModelDoorDefaults() {
              var md = modelDoors[doorCat];
              if (!md || !md.type) { doorTypeChanged(); return; }
              var s = document.getElementById('dType');
              var has = Array.prototype.some.call(s.options, function(o){ return o.value === md.type; });
              if (has) s.value = md.type; else { doorTypeChanged(); return; }
              document.getElementById('dW').value = md.w || '';
              document.getElementById('dH').value = md.h || '';
              if (md.swing) setSwing(md.swing);
            }

            function applyModelWindowDefaults() {
              if (!modelWindow || !modelWindow.type) { winTypeChanged(); return; }
              var s = document.getElementById('wType');
              var has = Array.prototype.some.call(s.options, function(o){ return o.value === modelWindow.type; });
              if (has) s.value = modelWindow.type; else { winTypeChanged(); return; }
              document.getElementById('wW').value = modelWindow.w || '';
              document.getElementById('wH').value = modelWindow.h || '';
              document.getElementById('wHead').value = modelWindow.header || '';
            }

            function wallTypeChanged() {
              curWallLib = document.getElementById('wallType').value;
              var t = wallTypes.find(function(x){ return x.name === curWallLib; });
              if (!t) return;
              document.getElementById('th').value = t.th;
              if (t.h) document.getElementById('hh').value = t.h;
              setCat(t.cat === 'interior' ? 'interior' : 'exterior', true);
            }

            function fillSelect(id, list) {
              var el = document.getElementById(id);
              el.innerHTML = '';
              list.forEach(function(t){ var o = document.createElement('option'); o.value = t; o.textContent = t; el.appendChild(o); });
            }
            function doorTypeChanged() {
              var t = document.getElementById('dType').value;
              var wh = (DOOR_WH_CAT && DOOR_WH_CAT[doorCat] && DOOR_WH_CAT[doorCat][t]) || DOOR_WH[t] || [32, 80];
              document.getElementById('dW').value = wh[0];
              document.getElementById('dH').value = wh[1];
            }
            function winTypeChanged() {
              var t = document.getElementById('wType').value;
              var wh = WIN_WH[t] || [24, 48];
              document.getElementById('wW').value = wh[0];
              document.getElementById('wH').value = wh[1];
            }
            function setDoorCat(c) {
              doorCat = c;
              document.getElementById('dCatI').className = c === 'interior' ? 'on' : '';
              document.getElementById('dCatE').className = c === 'exterior' ? 'on' : '';
              fillSelect('dType', DOOR_TYPES[c]);
              applyModelDoorDefaults();
            }
            function setSwing(s) {
              doorSwing = s;
              document.getElementById('dSwL').className = s === 'left' ? 'on' : '';
              document.getElementById('dSwR').className = s === 'right' ? 'on' : '';
            }
            function setMode(m) {
              mode = m; endChain(); hoverHit = null; setSel(null); dragSym = null;
              // Doors/windows need applied walls - apply pending automatically.
              if ((m === 'door' || m === 'win') && pending.length) applyPending();
              document.getElementById('modeSel').className = (m === 'sel' ? 'on ' : '') + 'modebtn';
              document.getElementById('modeWall').className = (m === 'wall' ? 'on ' : '') + 'modebtn';
              document.getElementById('modeDoor').className = (m === 'door' ? 'on ' : '') + 'modebtn';
              document.getElementById('modeWin').className = (m === 'win' ? 'on ' : '') + 'modebtn';
              document.getElementById('modeLine').className = (m === 'line' ? 'on ' : '') + 'modebtn';
              document.getElementById('secSel').style.display = m === 'sel' ? '' : 'none';
              document.getElementById('secWall').style.display = m === 'wall' ? '' : 'none';
              document.getElementById('secDoor').style.display = m === 'door' ? '' : 'none';
              document.getElementById('secWin').style.display = m === 'win' ? '' : 'none';
              document.getElementById('secLine').style.display = m === 'line' ? '' : 'none';
              if (m !== 'line') endLine();
              var hint = m === 'line'
                ? 'קליק-קליק לצייר קו · הקלד אורך + Enter · קליק על הנקודה הראשונה סוגר צורה · Esc מסיים'
                : m === 'wall'
                ? 'Click to start a wall - move - type length + Enter, or click. Right-click / Esc ends the chain.'
                : (m === 'sel'
                  ? 'Click to select. Drag a wall sideways or an opening along the wall — while dragging you can TYPE an exact amount + Enter. Delete key removes.'
                  : 'Click on an applied wall to place. Green = fits, red = does not fit.');
              document.getElementById('hint').textContent = hint;
              updateSelPanel();
              draw();
            }

            function updateSelPanel() {
              var info = document.getElementById('selInfo');
              var dopts = document.getElementById('selDoorOpts');
              var sopts = document.getElementById('selSizeOpts');
              var wopts = document.getElementById('selWallOpts');
              var topts = document.getElementById('selThickOpts');
              var copts = document.getElementById('selCopyOpts');
              var shp = document.getElementById('selShapeOpts');
              var ebar = document.getElementById('editBar');
              if (!info) return;
              dopts.style.display = 'none';
              sopts.style.display = 'none';
              wopts.style.display = 'none';
              topts.style.display = 'none';
              copts.style.display = 'none';
              shp.style.display = 'none';
              ebar.style.display = 'none';
              if (!sel) {
                info.textContent = 'לא נבחר כלום — לחץ על קיר או פתח';
                return;
              }
              // Thickness applies to every wall in the selection - one or many.
              var wsel = selList.filter(function(o) { return o.type === 'wall' || o.type === 'pending'; });
              if (sel.type === 'sketch') { topts.style.display = 'none'; copts.style.display = 'none'; }
              if (wsel.length) {
                topts.style.display = '';
                copts.style.display = '';
                var ths = wsel.map(function(o) { return o.type === 'pending' ? (pending[o.i] || {}).th : o.w.th; });
                var same = ths.every(function(v) { return v === ths[0]; });
                document.getElementById('selTh').value = (same && ths[0] != null) ? ths[0] : '';
              }
              // The edit strip: only the actions that fit the selection show.
              var hasShapes = selList.some(function(o) { return o.type === 'sketch'; });
              var hasWalls = selList.some(function(o) { return o.type === 'wall' || o.type === 'pending'; });
              ebar.style.display = '';
              var eb = function(id, on) { document.getElementById(id).style.display = on ? '' : 'none'; };
              eb('ebMove', hasShapes);
              eb('ebOff', hasShapes);
              eb('ebArea', selList.some(function(o) { return o.type === 'sketch' && o.sk.closed; }));
              eb('ebFlipH', hasShapes || hasWalls); eb('ebFlipV', hasShapes || hasWalls);
              eb('ebDup', hasWalls);
              var shapeCount = selList.filter(function(o) { return o.type === 'sketch'; }).length;
              eb('ebGrp', shapeCount > 1);
              eb('ebUngrp', hasShapes && selList.some(function(o) { return o.type === 'sketch' && o.sk.gid; }));
              if (hasShapes) shp.style.display = '';
              if (selList.length > 1) {
                var nWall = 0, nOpen = 0, nShape = 0;
                selList.forEach(function(o) {
                  if (o.type === 'sym') nOpen++;
                  else if (o.type === 'sketch') nShape++;
                  else nWall++;
                });
                info.innerHTML = 'נבחרו <b>' + selList.length + '</b> אלמנטים' +
                  '<br><span style="font-size:11px; color:#777">' + nWall + ' קירות · ' + nOpen +
                  ' פתחים · ' + nShape + ' צורות</span>';
                return;
              }
              if (sel.type === 'sketch') {
                info.textContent = (sel.sk.closed ? 'צורה סגורה' : 'קו') + ' · ' +
                                   (sel.sk.pts.length / 2) + ' נקודות' +
                                   (sel.kind === 'pending' ? ' (לא הוחל)' : '') +
                                   (sel.sk.gid ? ' · בקבוצה' : '');
                shp.style.display = '';
                return;
              }
              if (sel.type === 'wall') {
                var b = bandQuad(sel.w);
                info.textContent = 'Wall: ' + fmtLen(b ? b.len : 0) + ' · ' + sel.w.th + '" · ' + sel.w.cat;
                wopts.style.display = '';
                document.getElementById('selLen').value = b ? fmtLen(b.len) : '';
              } else if (sel.type === 'pending') {
                var pw = pending[sel.i];
                var pb = pw ? bandQuad(pw) : null;
                info.innerHTML = 'Wall (not applied yet): ' + (pb ? fmtLen(pb.len) : '') +
                                 '<br><span style="color:#e0392b">עריכה כאן מקומית — ‏Apply to Model לבנייה</span>';
                wopts.style.display = '';
                document.getElementById('selLen').value = pb ? fmtLen(pb.len) : '';
              } else {
                info.textContent = (sel.s.body === 'window' ? 'Window' : 'Door') + ' · ' + fmtLen(sel.s.w);
                sopts.style.display = '';
                document.getElementById('selW').value = sel.s.w || '';
                document.getElementById('selH').value = sel.s.h || '';
                document.getElementById('selHeaderRow').style.display = sel.s.body === 'window' ? '' : 'none';
                document.getElementById('selHead').value = sel.s.header || '';
                if (sel.s.body === 'door') {
                  dopts.style.display = '';
                  document.getElementById('selSwL').className = sel.s.swing === 'left' ? 'on' : '';
                  document.getElementById('selSwR').className = sel.s.swing === 'right' ? 'on' : '';
                }
              }
            }

            // Which END of the wall moves when the length changes; the other
            // corner stays pinned. Set from the panel or by clicking the corner.
            var movingEnd = 'end';
            var keepCorners = true;   // false = corner partners do NOT follow
            function setKeepCorners(v) {
              keepCorners = v;
              document.getElementById('cnKeep').className = v ? 'on' : '';
              document.getElementById('cnCut').className = v ? '' : 'on';
              draw();
            }
            function setMovingEnd(e) {
              movingEnd = e;
              document.getElementById('mvS').className = e === 'start' ? 'on' : '';
              document.getElementById('mvE').className = e === 'end' ? 'on' : '';
              draw();
            }
            function fixedEndName() { return movingEnd === 'end' ? 'start' : 'end'; }
            // ---- duplicate / mirror (2026-07-30) -----------------------------
            // Both produce PENDING (blue) walls only - nothing touches the model
            // until Apply, so Undo/Esc always gets you out. Openings are NOT
            // copied: a duplicated wall comes out clean.
            // ---- free 2D lines / shapes (2026-07-31) -------------------------
            // curLine holds the chain being drawn; pendingSketches are finished
            // but not yet applied; sketches are what already exists in the model.
            var sketches = [];
            var pendingSketches = [];
            var curLine = null;     // { pts:[{x,y}...] }

            var ghostCopy = null;   // { src:[wall...], ox, oy } while placing
            var ghostOpen = null;   // { src:[opening...] } while pasting openings

            function selWallObjs() {
              var out = [];
              selList.forEach(function(o) {
                if (o.type === 'wall') out.push(o.w);
                else if (o.type === 'pending') { var pw4 = pending[o.i]; if (pw4) out.push(pw4); }
              });
              return out;
            }

            function cloneWall(w) {
              return { sx:w.sx, sy:w.sy, ex:w.ex, ey:w.ey,
                       th:w.th, ha:w.ha || 'left', cat:w.cat, ops:[],
                       h:(w.h > 1 ? w.h : (parseLen(document.getElementById('hh').value) || 96)),
                       lib:(w.lib || ''), anchor:'bottom-left' };
            }

            function selCentre(src) {
              var xs = [], ys = [];
              src.forEach(function(w) { xs.push(w.sx, w.ex); ys.push(w.sy, w.ey); });
              return { x:(Math.min.apply(null, xs) + Math.max.apply(null, xs)) / 2,
                       y:(Math.min.apply(null, ys) + Math.max.apply(null, ys)) / 2 };
            }

            var clipWalls = null;   // internal clipboard for Ctrl+C / Ctrl+V

            function selOpeningObjs() {
              var out = [];
              selList.forEach(function(o) { if (o.type === 'sym') out.push(o.s); });
              return out;
            }

            function copySelToClip() {
              var src = selWallObjs();
              var ops = selOpeningObjs();
              if (!src.length && !ops.length) return false;
              clipWalls = { src: src.map(cloneWall), openings: ops.slice(),
                            from: src.length ? selCentre(src) : { x:0, y:0 } };
              setStatusHint(src.length
                ? ('הועתקו ' + src.length + ' קירות · Ctrl+V להדבקה')
                : ('הועתקו ' + ops.length + ' פתחים · Ctrl+V ואז קליק על קיר'));
              return true;
            }

            // Openings paste onto a wall: move over the wall, click, and the
            // copy is cut there through the SAME pipeline the Door/Window modes
            // use. Walls paste as pending copies (nothing enters the model
            // until Apply). A clipboard holding walls pastes the walls.
            function pasteClip() {
              if (!clipWalls) return false;
              if (!clipWalls.src.length) {
                if (!clipWalls.openings || !clipWalls.openings.length) return false;
                ghostOpen = { src: clipWalls.openings.slice() };
                setStatusHint('קליק על קיר כדי להדביק את הפתח · Esc לביטול');
                draw();
                return true;
              }
              ghostCopy = { src: clipWalls.src.map(cloneWall), ox:0, oy:0, from: clipWalls.from };
              setStatusHint('הזז את העכבר וקליק כדי להדביק · Esc לביטול');
              draw();
              return true;
            }

            function placeGhostOpen(p) {
              var hw3 = hitWall(p);
              if (!hw3 || !hw3.w.id) return;
              ghostOpen.src.forEach(function(sm) {
                if (sm.body === 'window') {
                  sketchup.place_window(JSON.stringify({
                    wall_id: hw3.w.id, px: p.x, py: p.y,
                    window_type: sm.wtype || 'Casement',
                    width: sm.w, height: sm.h, header: sm.header || 80
                  }));
                } else {
                  sketchup.place_door(JSON.stringify({
                    wall_id: hw3.w.id, px: p.x, py: p.y,
                    category: sm.dcat || 'interior',
                    door_type: sm.dtype || 'Single',
                    width: sm.w, height: sm.h, swing: sm.swing || 'left'
                  }));
                }
              });
              ghostOpen = null;
              setStatusHint(null);
              draw();
            }

            function duplicateSel() {
              var src = selWallObjs();
              if (!src.length) return;
              ghostCopy = { src: src.map(cloneWall), ox:0, oy:0, from: selCentre(src) };
              setStatusHint('הזז את העכבר וקליק כדי להניח את העותק · Esc לביטול');
              draw();
            }

            function placeGhostCopy() {
              if (!ghostCopy) return;
              ghostCopy.src.forEach(function(c) {
                var n2 = cloneWall(c);
                n2.sx += ghostCopy.ox; n2.ex += ghostCopy.ox;
                n2.sy += ghostCopy.oy; n2.ey += ghostCopy.oy;
                pending.push(n2);
              });
              ghostCopy = null;
              setStatusHint(null);
              setSel(null); updateSelPanel(); updateStatus(); draw();
            }

            // Mirror about the selection's own centre. A mirror reverses
            // handedness, so start/end are swapped to keep each wall's band on
            // the mirrored-correct side.
            // Flip turns the SELECTION ITSELF over - it does not leave a mirrored
            // copy behind (changed 2026-08-01 at the user request; use Duplicate
            // when a second one is what you want). Walls already applied to the
            // model cannot flip in place yet, so they are reported and skipped.
            function mirrorSel(axis) {
              var src = selWallObjs();
              if (!src.length) return;
              var c = selCentre(src);
              var applied = 0, flipped = 0;
              selList.forEach(function(o) {
                if (o.type === 'wall') { applied++; return; }
                if (o.type !== 'pending') return;
                var w = pending[o.i];
                if (!w) return;
                if (axis === 'h') { w.sx = 2 * c.x - w.sx; w.ex = 2 * c.x - w.ex; }
                else { w.sy = 2 * c.y - w.sy; w.ey = 2 * c.y - w.ey; }
                // Mirroring reverses the drawing direction, so swap the ends to
                // keep the band on the same side of the line it was on.
                var tx = w.sx, ty = w.sy;
                w.sx = w.ex; w.sy = w.ey; w.ex = tx; w.ey = ty;
                flipped++;
              });
              setStatusHint(applied
                ? applied + ' קירות שכבר הוחלו לא נהפכו — אפשר להפוך רק קירות כחולים'
                : null);
              updateSelPanel(); updateStatus(); draw();
            }

            var statusHint = null;
            function setStatusHint(t) {
              statusHint = t;
              var el = document.getElementById('hint');
              if (el && t) el.textContent = t;
            }

            function loadSketches(list) { sketches = list || []; }

            // ---- rooms + area tags (2026-08-01) -----------------------------
            // Rooms come from RoomManager: a closed loop of walls IS a room, and
            // the area is net, face to face. Free shapes are NOT rooms - they
            // only carry an area tag when you ask for one.
            var rooms = [];
            function loadRooms(list) { rooms = list || []; draw(); }

            // Rooms measured live off the BLUE walls, before Apply. Same
            // detector as the real ones, just nothing written to the model.
            var pendingRooms = [];
            var lastPendSig = null, pendRoomTimer = null;
            function loadPendingRooms(list) { pendingRooms = list || []; draw(); }

            function schedulePendingRooms() {
              var sig = pending.map(function(w) {
                return [w.sx, w.sy, w.ex, w.ey, w.th].join(',');
              }).join(';');
              if (sig === lastPendSig) return;
              lastPendSig = sig;
              if (pendRoomTimer) clearTimeout(pendRoomTimer);
              if (!pending.length) { pendingRooms = []; return; }
              pendRoomTimer = setTimeout(function() {
                try {
                  sketchup.preview_rooms(JSON.stringify({ rows: pending.map(function(w) {
                    return { sx:w.sx, sy:w.sy, ex:w.ex, ey:w.ey, th:w.th, ha:w.ha || 'left' };
                  }) }));
                } catch (e) {}
              }, 180);
            }

            function polyCentroid(flat) {
              var n = flat.length / 2, a = 0, cx = 0, cy = 0;
              for (var i = 0; i < n; i++) {
                var j = (i + 1) % n;
                var cr = flat[i * 2] * flat[j * 2 + 1] - flat[j * 2] * flat[i * 2 + 1];
                a += cr;
                cx += (flat[i * 2] + flat[j * 2]) * cr;
                cy += (flat[i * 2 + 1] + flat[j * 2 + 1]) * cr;
              }
              a /= 2;
              if (Math.abs(a) < 1e-6) return { x: flat[0], y: flat[1] };
              return { x: cx / (6 * a), y: cy / (6 * a) };
            }

            function sqftOf(flat) { return Math.abs(signedArea(flat)) / 144; }
            function fmtSqft(v) { return (Math.round(v * 10) / 10) + ' SF'; }

            // One label painter for both rooms and shape tags, so they read the
            // same. Registers a clickable box so the name can be edited.
            function drawAreaLabel(cx, cy, line1, line2, col, tag) {
              var px = sx(cx), py = sy(cy);
              ctx.textAlign = 'center';
              ctx.font = 'bold 13px Arial';
              var w1 = line1 ? ctx.measureText(line1).width : 0;
              ctx.font = '12px Arial';
              var w2 = ctx.measureText(line2).width;
              var bw = Math.max(w1, w2) + 14;
              var bh = line1 ? 34 : 20;
              ctx.fillStyle = 'rgba(255,255,255,0.88)';
              ctx.fillRect(px - bw / 2, py - bh / 2, bw, bh);
              if (line1) {
                ctx.font = 'bold 13px Arial'; ctx.fillStyle = col;
                ctx.fillText(line1, px, py - bh / 2 + 14);
                ctx.font = '12px Arial'; ctx.fillStyle = '#555';
                ctx.fillText(line2, px, py - bh / 2 + 29);
              } else {
                ctx.font = '12px Arial'; ctx.fillStyle = col;
                ctx.fillText(line2, px, py + 4);
              }
              ctx.textAlign = 'left';
              if (tag) dimTags.push({ x:px - bw / 2, y:py - bh / 2, w:bw, h:bh, kind:tag.kind, data:tag.data });
            }

            function drawRooms() {
              var taken = [];
              rooms.forEach(function(r) {
                if (!r.pts || r.pts.length < 6) return;
                drawSketch(r.pts, true, 'rgba(26,110,224,0.35)', 1, null, [7, 5]);
                var c = polyCentroid(r.pts);
                taken.push(c);
                // Default names already end in the number ("Room 1"), so only
                // add it when the name does not carry it already.
                var nm = r.name || 'Room';
                var num = r.number ? String(r.number) : '';
                if (num && nm.slice(-num.length) !== num) nm += '  ' + num;
                drawAreaLabel(c.x, c.y, nm, fmtSqft(r.area), '#1a6ee0',
                              { kind:'room', data:r });
              });
              // Rooms still being drawn: area only, and never on top of a real
              // room that the model already knows about.
              pendingRooms.forEach(function(r) {
                if (!r.pts || r.pts.length < 6) return;
                var c = polyCentroid(r.pts);
                for (var i = 0; i < taken.length; i++) {
                  if (Math.hypot(taken[i].x - c.x, taken[i].y - c.y) < 6) return;
                }
                drawSketch(r.pts, true, 'rgba(47,107,216,0.5)', 1, null, [4, 4]);
                drawAreaLabel(c.x, c.y, '', fmtSqft(r.area), '#2f6bd8', null);
              });
            }

            // Area tags on free shapes - only the ones the user switched on.
            function drawShapeAreas() {
              function one(sk, kind, idx) {
                if (!sk.area_on || !sk.closed || !sk.pts || sk.pts.length < 6) return;
                var c = polyCentroid(sk.pts);
                drawAreaLabel(c.x, c.y, sk.area_name || '', fmtSqft(sqftOf(sk.pts)), '#7a5c33',
                              { kind:'skarea', data:{ sk:sk, kind:kind, i:idx } });
              }
              sketches.forEach(function(sk, i) { one(sk, 'model', i); });
              pendingSketches.forEach(function(sk, i) { one(sk, 'pending', i); });
            }

            // The area button: on for closed shapes, off again on a second press.
            function toggleSelArea() {
              var shapes = selList.filter(function(o) {
                return o.type === 'sketch' && o.sk.closed;
              });
              if (!shapes.length) {
                setStatusHint('שטח נמדד רק על צורה סגורה');
                return;
              }
              var turningOn = !shapes.every(function(o) { return o.sk.area_on; });
              var ids = [];
              shapes.forEach(function(o) {
                o.sk.area_on = turningOn;
                if (o.kind !== 'pending' && o.sk.id) ids.push(o.sk.id);
              });
              updateSelPanel(); draw();
              if (ids.length) sketchup.set_sketch_area(JSON.stringify({ ids: ids, on: turningOn }));
            }

            function editRoomName(r) {
              var nm = prompt('שם החדר', r.name || '');
              if (nm === null) return;
              nm = nm.trim();
              if (!nm) return;
              r.name = nm;
              draw();
              sketchup.rename_room(JSON.stringify({ id: r.id, name: nm }));
            }

            function editShapeAreaName(o) {
              var nm = prompt('שם השטח (ריק = בלי שם)', o.sk.area_name || '');
              if (nm === null) return;
              o.sk.area_name = nm.trim();
              draw();
              if (o.kind !== 'pending' && o.sk.id) {
                sketchup.rename_sketch_area(JSON.stringify({ id: o.sk.id, name: o.sk.area_name }));
              }
            }

            // ---- background underlay (2026-07-31) ----------------------------
            // An image parked behind the drawing. Its scale is set by pointing
            // at two ends of something whose real length you know, then typing
            // that length - from then on everything you trace is to scale.
            var underImg = null;
            var underX = 0, underY = 0;
            var underScale = 1;
            var underOpacity = 0.55;
            var underLocked = true;
            var calib = null;
            var dragUnder = null;

            // The helper panels fold away: they are set up once and then just
            // sit there, so they live at the bottom and open on demand. Nothing
            // in the side panel moves while you switch tools.
            var foldOpen = { guide:false, under:false };
            function toggleFold(which, force) {
              foldOpen[which] = (force === undefined) ? !foldOpen[which] : !!force;
              var on = foldOpen[which];
              document.getElementById(which + 'Body').style.display = on ? '' : 'none';
              document.getElementById(which + 'Caret').innerHTML = on ? '▴' : '▾';
            }
            function toggleUnderBox(force) { toggleFold('under', force); }

            // Placement (position + size + opacity + lock) is kept ON THE MODEL,
            // so a calibrated image comes back exactly where it was put instead
            // of being re-fitted to the window every time the editor opens.
            function saveUnderlay() {
              if (!underImg) return;
              try {
                sketchup.save_underlay(JSON.stringify({ x: underX, y: underY, scale: underScale,
                                                        opacity: underOpacity, locked: underLocked }));
              } catch (e) {}
            }

            function loadUnderlay(src, place) {
              if (!src) {
                underImg = null; calib = null;
                document.getElementById('underRow').style.display = 'none';
                document.getElementById('underDot').style.display = 'none';
                draw();
                return;
              }
              var im = new Image();
              im.onload = function() {
                underImg = im;
                document.getElementById('underRow').style.display = '';
                document.getElementById('underDot').style.display = '';
                if (place && place.scale > 0) {
                  underX = place.x; underY = place.y; underScale = place.scale;
                  underOpacity = place.opacity > 0 ? place.opacity : 0.55;
                  underLocked = place.locked !== false;
                  document.getElementById('underOp').value = Math.round(underOpacity * 100);
                  document.getElementById('underLockBtn').className = underLocked ? 'on' : '';
                  draw();
                } else {
                  fitUnderlay(1);
                }
              };
              im.src = src;
            }

            function fitUnderlay(save) {
              if (!underImg) return;
              var viewW = cv.width / scale;
              underScale = viewW * 0.8 / underImg.width;
              underX = mx(cv.width * 0.1);
              underY = my(cv.height * 0.1);
              if (save) saveUnderlay();
              draw();
            }

            function setUnderOpacity(v) { underOpacity = Math.max(0.05, v / 100); saveUnderlay(); draw(); }

            function toggleUnderLock() {
              underLocked = !underLocked;
              document.getElementById('underLockBtn').className = underLocked ? 'on' : '';
              saveUnderlay();
              draw();
            }

            function startCalib() {
              if (!underImg) return;
              calib = { a: null, b: null };
              setStatusHint('קליק על שתי נקודות שאתה יודע את המרחק ביניהן');
              draw();
            }

            function calibClick(p) {
              if (!calib) return false;
              if (!calib.a) { calib.a = p; draw(); return true; }
              calib.b = p;
              var pxd = Math.hypot(calib.b.x - calib.a.x, calib.b.y - calib.a.y);
              var ans = prompt('מה המרחק האמיתי בין שתי הנקודות?');
              var real = ans ? parseLen(ans) : null;
              if (real && real > 0.05 && pxd > 0.001) {
                var f = real / pxd;
                underX = calib.a.x + (underX - calib.a.x) * f;
                underY = calib.a.y + (underY - calib.a.y) * f;
                underScale *= f;
                // A calibrated image locks itself: a stray click must never
                // shift it once it is to scale.
                underLocked = true;
                document.getElementById('underLockBtn').className = 'on';
                saveUnderlay();
              }
              calib = null;
              setStatusHint(null);
              draw();
              return true;
            }

            function drawUnderlay() {
              if (!underImg) return;
              var w5 = underImg.width * underScale * scale;
              var h5 = underImg.height * underScale * scale;
              ctx.save();
              ctx.globalAlpha = underOpacity;
              try { ctx.drawImage(underImg, sx(underX), sy(underY), w5, h5); } catch (e) {}
              ctx.restore();
              if (calib && calib.a) {
                ctx.strokeStyle = '#e0392b'; ctx.lineWidth = 1.6;
                ctx.setLineDash([6, 4]);
                if (cursor) {
                  ctx.beginPath();
                  ctx.moveTo(sx(calib.a.x), sy(calib.a.y));
                  ctx.lineTo(sx(cursor.x), sy(cursor.y));
                  ctx.stroke();
                }
                ctx.setLineDash([]);
                ctx.beginPath();
                ctx.arc(sx(calib.a.x), sy(calib.a.y), 5, 0, Math.PI * 2);
                ctx.fillStyle = '#e0392b'; ctx.fill();
              }
            }

            // ---- arc / circle (2026-07-31) ----------------------------------
            var lineTool = 'line';     // 'line' | 'arc' | 'rect' | 'circle' | 'hex' | 'measure'
            // ONE line look at a time (radio, not two independent toggles):
            // thin solid / dashed / thick. Style + weight are derived from it.
            var linePreset = 'solid';  // 'solid' | 'dashed' | 'thick'
            var lineStyle = 'solid';   // derived
            var lineWeight = 1;        // derived
            var measA = null, measB = null;   // measure tool points
            var polySides = 6;         // polygon tool: type "8s" to change it

            // ---- guides (2026-07-31) ----------------------------------------
            // Editor-only helper lines - never model, never plans.
            // (The 3 in / 6 in / 1 ft module snap was removed 2026-08-01 at the
            // user request: free movement now always rounds to 1/2 in.)
            var guides = [];           // [{x1,y1,x2,y2}]
            var guideMode = false;
            var guideStart = null;

            // The green dot on the folded header says "something is live in
            // here" - guide mode is on, or there are guides on the canvas.
            function markGuideBox() {
              var d = document.getElementById('guideDot');
              if (d) d.style.display = (guideMode || guides.length) ? '' : 'none';
            }

            function toggleGuideMode() {
              guideMode = !guideMode;
              guideStart = null;
              document.getElementById('guideBtn').className = guideMode ? 'on' : '';
              setStatusHint(guideMode ? 'קליק בשתי נקודות ליצירת קו עזר · לחץ שוב לכיבוי' : null);
              markGuideBox();
              draw();
            }

            function clearGuides() { guides = []; markGuideBox(); draw(); }

            function guideClick(p) {
              if (!guideStart) { guideStart = p; draw(); return true; }
              guides.push({ x1: guideStart.x, y1: guideStart.y, x2: p.x, y2: p.y });
              guideStart = null;
              markGuideBox();
              draw();
              return true;
            }

            function drawGuides() {
              ctx.strokeStyle = '#00b8d9'; ctx.lineWidth = 1;
              ctx.setLineDash([3, 5]);
              guides.forEach(function(g) {
                // drawn well past both ends so it reads as an infinite helper
                var dx = g.x2 - g.x1, dy = g.y2 - g.y1;
                var L = Math.hypot(dx, dy) || 1;
                var ux = dx / L, uy = dy / L;
                ctx.beginPath();
                ctx.moveTo(sx(g.x1 - ux * 5000), sy(g.y1 - uy * 5000));
                ctx.lineTo(sx(g.x1 + ux * 5000), sy(g.y1 + uy * 5000));
                ctx.stroke();
              });
              if (guideStart && cursor) {
                ctx.beginPath();
                ctx.moveTo(sx(guideStart.x), sy(guideStart.y));
                ctx.lineTo(sx(cursor.x), sy(cursor.y));
                ctx.stroke();
              }
              ctx.setLineDash([]);
            }

            function setLinePreset(pv) {
              linePreset = pv;
              lineStyle = (pv === 'dashed') ? 'dashed' : 'solid';
              lineWeight = (pv === 'thick') ? 2 : 1;
              document.getElementById('lsSolid').className = pv === 'solid' ? 'on' : '';
              document.getElementById('lsDash').className = pv === 'dashed' ? 'on' : '';
              document.getElementById('lwThick').className = pv === 'thick' ? 'on' : '';
              draw();
            }
            // kept so older call sites keep working
            function setLineStyle(st) { setLinePreset(st === 'dashed' ? 'dashed' : 'solid'); }
            var arcPts = [];           // start, end (then the cursor bulges it)
            var circC = null;          // circle centre while dragging the radius

            // Repaint the tool row + help WITHOUT touching anything half-drawn,
            // so the side count can change mid-shape.
            function refreshToolUi() {
              var t = lineTool;
              document.getElementById('ltLine').className = t === 'line' ? 'on' : '';
              document.getElementById('ltArc').className = t === 'arc' ? 'on' : '';
              document.getElementById('ltRect').className = t === 'rect' ? 'on' : '';
              document.getElementById('ltCirc').className = t === 'circle' ? 'on' : '';
              document.getElementById('ltHex').className = t === 'hex' ? 'on' : '';
              document.getElementById('ltMeas').className = t === 'measure' ? 'on' : '';
              document.getElementById('ltErase').className = t === 'erase' ? 'on' : '';
              var helps = {
                line: 'קליק-קליק לציור. חזרה לנקודה הראשונה סוגרת צורה — ואז נוצר משטח במודל.',
                arc: 'קליק בהתחלה, קליק בסוף, ואז קליק כדי לקבוע את הקימור.',
                rect: 'קליק בפינה אחת ואז בפינה הנגדית · או הקלד רוחב,גובה + Enter.',
                circle: 'קליק במרכז, ואז קליק לרדיוס (או הקלד רדיוס + Enter).',
                hex: 'קליק במרכז, ואז קליק לרדיוס (או הקלד רדיוס + Enter) · הקלד מספר ואז S למספר צלעות.',
                measure: 'קליק בשתי נקודות למדידה. קליק נוסף מתחיל מדידה חדשה.',
                erase: 'ריחוף מדליק באדום את הקטע שיימחק · קליק מוחק רק אותו. צורה בקבוצה נמחקת שלמה.'
              };
              document.getElementById('lineHelp').innerHTML =
                (t === 'hex' ? 'מצולע ' + polySides + ' צלעות · ' : '') + (helps[t] || helps.line);
            }

            function setLineTool(t) {
              lineTool = t;
              if (curLine) finishLine(false);
              arcPts = []; circC = null; typed = ''; updateVcb();
              measA = null; measB = null; erasePick = null;
              refreshToolUi();
              draw();
            }

            // Circle through centre + radius. Closed, so it becomes a face.
            function circlePoints(c, r, segs) {
              var out = [];
              if (!(r > 0.01)) return out;
              for (var i2 = 0; i2 < segs; i2++) {
                var a2 = Math.PI * 2 * i2 / segs;
                out.push({ x: c.x + r * Math.cos(a2), y: c.y + r * Math.sin(a2) });
              }
              return out;
            }

            // Arc through three points (start, a point it passes through, end).
            // Collinear points degrade to a straight segment instead of failing.
            function arcPoints(p1, pm, p2, segs) {
              var d3 = 2 * (p1.x * (pm.y - p2.y) + pm.x * (p2.y - p1.y) + p2.x * (p1.y - pm.y));
              if (Math.abs(d3) < 1e-9) return [p1, p2];
              var s1 = p1.x * p1.x + p1.y * p1.y;
              var s2 = pm.x * pm.x + pm.y * pm.y;
              var s3 = p2.x * p2.x + p2.y * p2.y;
              var cx = (s1 * (pm.y - p2.y) + s2 * (p2.y - p1.y) + s3 * (p1.y - pm.y)) / d3;
              var cy = (s1 * (p2.x - pm.x) + s2 * (p1.x - p2.x) + s3 * (pm.x - p1.x)) / d3;
              var r3 = Math.hypot(p1.x - cx, p1.y - cy);
              if (!(r3 > 0.01) || !isFinite(r3)) return [p1, p2];
              var TP = Math.PI * 2;
              var nrm = function(a) { while (a < 0) a += TP; while (a >= TP) a -= TP; return a; };
              var a1 = Math.atan2(p1.y - cy, p1.x - cx);
              var am = nrm(Math.atan2(pm.y - cy, pm.x - cx) - a1);
              var ae = nrm(Math.atan2(p2.y - cy, p2.x - cx) - a1);
              var sweep = (am <= ae) ? ae : ae - TP;   // take the way through pm
              var out = [];
              for (var i3 = 0; i3 <= segs; i3++) {
                var a3 = a1 + sweep * i3 / segs;
                out.push({ x: cx + r3 * Math.cos(a3), y: cy + r3 * Math.sin(a3) });
              }
              return out;
            }

            function rectPoints(a, b) {
              return [{ x:a.x, y:a.y }, { x:b.x, y:a.y }, { x:b.x, y:b.y }, { x:a.x, y:b.y }];
            }

            // Flat-top hexagon around a centre, first vertex toward the cursor.
            function polyPoints(c, r, n, rot) {
              var out = [];
              if (!(r > 0.01)) return out;
              for (var i5 = 0; i5 < n; i5++) {
                var a5 = (rot || 0) + Math.PI * 2 * i5 / n;
                out.push({ x: c.x + r * Math.cos(a5), y: c.y + r * Math.sin(a5) });
              }
              return out;
            }

            function pushShape(pts, closed, shape) {
              if (!pts || pts.length < 2) return;
              var flat = [];
              pts.forEach(function(pt) { flat.push(pt.x, pt.y); });
              pendingSketches.push({ pts: flat, closed: !!closed, style: lineStyle,
                                     weight: lineWeight, shape: shape || 'line' });
              updateStatus();
              draw();
            }

            // One click of the Arc / Circle tools. Returns true if handled.
            function lineToolClick(p) {
              if (lineTool === 'measure') {
                if (!measA) { measA = p; }
                else if (!measB) { measB = p; }
                else { measA = p; measB = null; }
                draw();
                return true;
              }
              if (lineTool === 'rect') {
                if (!circC) { circC = p; return true; }
                if (Math.abs(p.x - circC.x) > 0.5 && Math.abs(p.y - circC.y) > 0.5) {
                  pushShape(rectPoints(circC, p), true, 'rect');
                }
                circC = null;
                return true;
              }
              if (lineTool === 'hex') {
                if (!circC) { circC = p; return true; }
                var rh = Math.hypot(p.x - circC.x, p.y - circC.y);
                var th2 = parseLen(typed);
                if (th2) rh = th2;
                pushShape(polyPoints(circC, rh, polySides, Math.atan2(p.y - circC.y, p.x - circC.x)),
                          true, 'poly');
                circC = null; typed = ''; updateVcb();
                return true;
              }
              if (lineTool === 'circle') {
                if (!circC) { circC = p; return true; }
                var rr = Math.hypot(p.x - circC.x, p.y - circC.y);
                var tv = parseLen(typed);
                if (tv) rr = tv;
                pushShape(circlePoints(circC, rr, 64), true, 'circle');
                circC = null; typed = ''; updateVcb();
                return true;
              }
              if (lineTool === 'arc') {
                if (arcPts.length < 2) { arcPts.push(p); return true; }
                pushShape(arcPoints(arcPts[0], p, arcPts[1], 48), false, 'arc');
                arcPts = [];
                return true;
              }
              return false;
            }

            function addLinePoint(p) {
              if (!curLine) { curLine = { pts: [p] }; draw(); return; }
              var first = curLine.pts[0];
              // back on the first point -> close the shape
              if (curLine.pts.length >= 2 && Math.hypot(p.x - first.x, p.y - first.y) < 12 / scale) {
                closeShape();
                return;
              }
              curLine.pts.push(p);
              draw();
            }

            function finishLine(closed) {
              if (!curLine || curLine.pts.length < 2) { curLine = null; draw(); return; }
              var flat = [];
              curLine.pts.forEach(function(pt) { flat.push(pt.x, pt.y); });
              pendingSketches.push({ pts: flat, closed: !!closed, style: lineStyle, weight: lineWeight });
              curLine = null;
              updateStatus();
              draw();
            }

            function closeShape() { finishLine(true); }
            function endLine() { finishLine(false); }

            function undoLinePoint() {
              if (curLine && curLine.pts.length > 1) { curLine.pts.pop(); draw(); return; }
              if (curLine) { curLine = null; draw(); return; }
              if (pendingSketches.length) { pendingSketches.pop(); updateStatus(); draw(); }
            }

            function sketchesDone(n) { pendingSketches = []; updateStatus(); draw(); }

            function flatten(pts) {
              var f = [];
              pts.forEach(function(pt) { f.push(pt.x, pt.y); });
              return f;
            }

            function drawSketch(pts, closed, color, width, fill, dash) {
              if (!pts || pts.length < 4) return;
              ctx.strokeStyle = color; ctx.lineWidth = width || 1.5;
              if (dash) ctx.setLineDash(dash);
              ctx.beginPath();
              ctx.moveTo(sx(pts[0]), sy(pts[1]));
              for (var i7 = 2; i7 < pts.length; i7 += 2) ctx.lineTo(sx(pts[i7]), sy(pts[i7 + 1]));
              if (closed) ctx.closePath();
              if (fill && closed) { ctx.fillStyle = fill; ctx.fill(); }
              ctx.stroke();
              if (dash) ctx.setLineDash([]);
            }

            function sketchWidth(sk) { return sk.weight === 2 ? 3.6 : 1.6; }
            function sketchDash(sk) { return sk.style === 'dashed' ? [8, 6] : null; }

            function applySelThickness() {
              var v = parseLen(document.getElementById('selTh').value);
              if (!v || v < 1) return;
              var ids = [];
              selList.forEach(function(o) {
                if (o.type === 'pending') { var pw3 = pending[o.i]; if (pw3) pw3.th = v; }
                else if (o.type === 'wall' && o.w.id) ids.push(o.w.id);
              });
              draw();
              if (ids.length) sketchup.set_thickness(JSON.stringify({ ids: ids, th: v }));
            }

            function applyWallLen() {
              var v = parseLen(document.getElementById('selLen').value);
              if (!v || v <= 6 || !sel) return;
              if (sel.type === 'pending') { setPendingLength(sel.i, v); return; }
              if (sel.type !== 'wall' || !sel.w.id) return;
              keepSel = { kind:'wall', id: sel.w.id };
              sketchup.set_wall_length(JSON.stringify({ wall_id: sel.w.id, len: v, fixed: fixedEndName(), keep: keepCorners }));
            }

            // Apply the value typed during a drag: wall = sideways distance in
            // the drag direction; opening = distance moved along the wall.
            function applyTypedDrag() {
              var neg = typed.trim().charAt(0) === '-';
              var v = parseLen(typed.replace('-', ''));
              typed = ''; updateVcb();
              if (!v) return;
              if (dragWall) {
                var dir = (dragWall.off < 0 ? -1 : 1) * (neg ? -1 : 1);
                var off = dir * v;
                var w = dragWall.w;
                dragWall = null;
                if (sel && sel.type === 'pending') { movePendingWall(sel.i, off); return; }
                keepSel = { kind:'wall', id: w.id };
                sketchup.move_wall(JSON.stringify({ wall_id: w.id, dist: -off, keep: keepCorners }));
                draw();
                return;
              }
              if (dragSym) {
                var dir2 = (dragSym.curT - dragSym.startT < 0 ? -1 : 1) * (neg ? -1 : 1);
                var s = dragSym.s;
                dragSym = null;
                keepSel = { kind:'sym', id: s.id };
                sketchup.move_opening(JSON.stringify({ id: s.id, body: s.body, delta: dir2 * v }));
                draw();
              }
            }

            function diagWall() {
              if (!sel || sel.type !== 'wall') return;
              sketchup.debug_wall(JSON.stringify({ wall_id: sel.w.id }));
            }

            // --- pending (not yet applied) wall helpers -------------------
            // Endpoints of OTHER pending walls that sit on pt (corner partners).
            function pendingPartners(idx, pt) {
              var out = [];
              var tol = 1.0;
              pending.forEach(function(o, j){
                if (j === idx) return;
                tol = (pending[idx].th + o.th) / 2 + 1;
                if (Math.hypot(o.sx - pt.x, o.sy - pt.y) < tol) out.push({ w:o, k:'s' });
                if (Math.hypot(o.ex - pt.x, o.ey - pt.y) < tol) out.push({ w:o, k:'e' });
              });
              return out;
            }

            function movePendingWall(idx, off) {
              var pw = pending[idx], b = bandQuad(pw); if (!b) return;
              var s0 = { x:pw.sx, y:pw.sy }, e0 = { x:pw.ex, y:pw.ey };
              var ps = keepCorners ? pendingPartners(idx, s0) : [];
              var pe = keepCorners ? pendingPartners(idx, e0) : [];
              pw.sx += b.nx*off; pw.sy += b.ny*off;
              pw.ex += b.nx*off; pw.ey += b.ny*off;
              ps.forEach(function(p2){
                if (p2.k === 's') { p2.w.sx = pw.sx; p2.w.sy = pw.sy; } else { p2.w.ex = pw.sx; p2.w.ey = pw.sy; }
              });
              pe.forEach(function(p2){
                if (p2.k === 's') { p2.w.sx = pw.ex; p2.w.sy = pw.ey; } else { p2.w.ex = pw.ex; p2.w.ey = pw.ey; }
              });
              updateSelPanel(); draw();
            }

            function setPendingLength(idx, len) {
              var pw = pending[idx], b = bandQuad(pw); if (!b) return;
              var oldPt = movingEnd === 'end' ? { x:pw.ex, y:pw.ey } : { x:pw.sx, y:pw.sy };
              var partners = keepCorners ? pendingPartners(idx, oldPt) : [];
              if (movingEnd === 'end') { pw.ex = pw.sx + b.ux*len; pw.ey = pw.sy + b.uy*len; }
              else { pw.sx = pw.ex - b.ux*len; pw.sy = pw.ey - b.uy*len; }
              var np = movingEnd === 'end' ? { x:pw.ex, y:pw.ey } : { x:pw.sx, y:pw.sy };
              partners.forEach(function(p2){
                if (p2.k === 's') { p2.w.sx = np.x; p2.w.sy = np.y; } else { p2.w.ex = np.x; p2.w.ey = np.y; }
              });
              updateSelPanel(); draw();
            }

            // Out / In are relative to the BUILDING (away from / toward the
            // centroid of all walls) — not to the wall's drawing direction, so
            // the buttons always feel right no matter how the wall was drawn.
            function outwardSign(w, b) {
              var all = walls.concat(pending);
              var cx = 0, cy = 0, n = 0;
              all.forEach(function(o){ cx += o.sx + o.ex; cy += o.sy + o.ey; n += 2; });
              if (!n) return 1;
              cx /= n; cy /= n;
              var mid = { x:(w.sx + w.ex)/2, y:(w.sy + w.ey)/2 };
              var probe = { x: mid.x + b.nx*10, y: mid.y + b.ny*10 };
              return Math.hypot(probe.x - cx, probe.y - cy) > Math.hypot(mid.x - cx, mid.y - cy) ? 1 : -1;
            }

            function moveWall(sign) {
              var v = parseLen(document.getElementById('selMove').value);
              if (!v || !sel) return;
              if (sel.type === 'pending') {
                var pw = pending[sel.i], pb = bandQuad(pw); if (!pb) return;
                movePendingWall(sel.i, sign * v * outwardSign(pw, pb));
                return;
              }
              if (sel.type !== 'wall') return;
              var b = bandQuad(sel.w); if (!b) return;
              var offN = sign * v * outwardSign(sel.w, b);   // in +n units
              keepSel = { kind:'wall', id: sel.w.id };
              // Ruby's positive distance = RIGHT perpendicular = -n
              sketchup.move_wall(JSON.stringify({ wall_id: sel.w.id, dist: -offN, keep: keepCorners }));
            }

            function applySelSize() {
              if (!sel || sel.type !== 'sym') return;
              sketchup.edit_opening_size(JSON.stringify({
                id: sel.s.id,
                body: sel.s.body,
                width: parseLen(document.getElementById('selW').value) || 0,
                height: parseLen(document.getElementById('selH').value) || 0,
                header: parseLen(document.getElementById('selHead').value) || 0
              }));
            }

            function editSwing(swing, flip) {
              if (!sel || sel.type !== 'sym' || sel.s.body !== 'door') return;
              sketchup.edit_door_swing(JSON.stringify({
                id: sel.s.id,
                swing: swing || sel.s.swing,
                flip_side: !!flip
              }));
            }

            // ---- offset / group (2026-07-31) ---------------------------------
            // Offset builds a parallel copy: every segment is pushed sideways by
            // the distance and the neighbouring offset lines are intersected, so
            // corners stay sharp instead of rounding off.
            function offsetPoly(flat, closed, d) {
              var n = flat.length / 2;
              if (n < 2) return null;
              var P = [];
              for (var i = 0; i < n; i++) P.push({ x: flat[i * 2], y: flat[i * 2 + 1] });
              var m = closed ? n : n - 1;
              var L = [];
              for (var i = 0; i < m; i++) {
                var a = P[i], b = P[(i + 1) % n];
                var dx = b.x - a.x, dy = b.y - a.y;
                var len = Math.hypot(dx, dy);
                if (len < 1e-6) { L.push(null); continue; }
                var nx = -dy / len, ny = dx / len;
                L.push({ p: { x: a.x + nx * d, y: a.y + ny * d }, u: { x: dx / len, y: dy / len },
                         nx: nx, ny: ny });
              }
              var out = [];
              function meet(l1, l2, fallback) {
                if (!l1 || !l2) return fallback;
                var ip = lineInt(l1.p, l1.u, l2.p, l2.u);
                return ip || fallback;
              }
              if (closed) {
                for (var i = 0; i < m; i++) {
                  var prev = L[(i - 1 + m) % m], cur = L[i];
                  var fb = cur ? { x: P[i].x + cur.nx * d, y: P[i].y + cur.ny * d } : P[i];
                  out.push(meet(prev, cur, fb));
                }
              } else {
                var f0 = L[0];
                out.push(f0 ? { x: P[0].x + f0.nx * d, y: P[0].y + f0.ny * d } : P[0]);
                for (var i = 1; i < m; i++) {
                  var cur2 = L[i];
                  var fb2 = cur2 ? { x: P[i].x + cur2.nx * d, y: P[i].y + cur2.ny * d } : P[i];
                  out.push(meet(L[i - 1], cur2, fb2));
                }
                var lastL = L[m - 1];
                out.push(lastL ? { x: P[n - 1].x + lastL.nx * d, y: P[n - 1].y + lastL.ny * d } : P[n - 1]);
              }
              var res = [];
              out.forEach(function(pt) { res.push(pt.x, pt.y); });
              return res;
            }

            // Signed area tells us the winding, so a POSITIVE offset is always
            // outward on a closed shape and a negative one goes inward,
            // whichever way the user happened to draw it.
            function signedArea(flat) {
              var n = flat.length / 2, a = 0;
              for (var i7 = 0; i7 < n; i7++) {
                var j7 = (i7 + 1) % n;
                a += flat[i7 * 2] * flat[j7 * 2 + 1] - flat[j7 * 2] * flat[i7 * 2 + 1];
              }
              return a / 2;
            }

            // ---- offset (interactive, 2026-08-01) ---------------------------
            // SketchUp style: press the button, then move the mouse to the side
            // you want and the new outline follows in dashed purple. The side
            // comes from the cursor, the distance from how far out you are - or
            // from a number you type. Click drops it, Esc cancels.
            var offOp = null;   // { shapes:[o], d, sgn, prev:[{pts,closed,sk}] }

            function startFreeOffset() {
              var shapes = selList.filter(function(o) { return o.type === 'sketch'; });
              if (!shapes.length) return;
              offOp = { shapes: shapes, start: null, d: 0, sgn: 1, prev: [] };
              setStatusHint('לחץ על קו המתאר כדי להתחיל');
              draw();
            }

            // SketchUp asks you to click the outline first, then set the
            // distance with the second click - same two-click rhythm as Move.
            function offStart(p) {
              if (!offOp) return;
              var q = snapPoint(p, null);
              offOp.start = { x: q.x, y: q.y };
              setStatusHint('הזז לצד שרוצים · הקלד מידה + Enter · Esc ביטול');
              draw();
            }

            function ptInPoly(flat, p) {
              var n = flat.length / 2, hit = false;
              for (var i = 0, j = n - 1; i < n; j = i++) {
                var xi = flat[i * 2], yi = flat[i * 2 + 1];
                var xj = flat[j * 2], yj = flat[j * 2 + 1];
                if ((yi > p.y) !== (yj > p.y) &&
                    p.x < (xj - xi) * (p.y - yi) / (yj - yi) + xi) hit = !hit;
              }
              return hit;
            }

            // How far the cursor is from the shape, and which side it is on.
            function offsetSideDist(sk, p) {
              var pl = skChain(sk), acc = chainAcc(pl);
              if (sk.closed) {
                return { d: chainProj(p, pl, acc).d, sgn: ptInPoly(sk.pts, p) ? -1 : 1 };
              }
              var bestD = 1e18, side = 1;
              for (var i = 1; i < pl.length; i++) {
                var a = pl[i - 1], b = pl[i];
                var dd = distToSeg(p, a.x, a.y, b.x, b.y);
                if (dd < bestD) {
                  bestD = dd;
                  var ux = b.x - a.x, uy = b.y - a.y, L = Math.hypot(ux, uy) || 1;
                  side = ((ux / L) * (p.y - a.y) - (uy / L) * (p.x - a.x)) >= 0 ? 1 : -1;
                }
              }
              return { d: bestD, sgn: side };
            }

            function offBuild(dist, sgn) {
              if (!offOp) return;
              offOp.d = dist; offOp.sgn = sgn;
              offOp.prev = [];
              if (!(dist > 0.05)) return;
              offOp.shapes.forEach(function(o) {
                // winding decides which way is OUT on a closed shape
                var w = o.sk.closed ? (signedArea(o.sk.pts) > 0 ? -1 : 1) : 1;
                var np = offsetPoly(o.sk.pts, o.sk.closed, dist * sgn * w);
                if (np) offOp.prev.push({ pts: np, closed: o.sk.closed, sk: o.sk });
              });
            }

            function offMove() {
              if (!offOp || !offOp.start || !cursor) return;
              var r = offsetSideDist(offOp.shapes[0].sk, cursor);
              offBuild(r.d, r.sgn);
              draw();
            }

            function offCommit() {
              if (!offOp) return;
              var made = 0;
              offOp.prev.forEach(function(pc) {
                pendingSketches.push({ pts: pc.pts, closed: pc.closed,
                                       style: pc.sk.style || 'solid',
                                       weight: pc.sk.weight || 1,
                                       shape: pc.sk.shape || 'line' });
                made++;
              });
              offOp = null;
              setStatusHint(null);
              updateStatus(); draw();
              return made;
            }

            function offCancel() {
              if (!offOp) return;
              offOp = null;
              setStatusHint(null);
              draw();
            }

            function drawOffOp() {
              if (!offOp) return;
              if (!offOp.start) {                  // still choosing where to start
                if (snapInd) {
                  ctx.beginPath();
                  ctx.arc(sx(snapInd.x), sy(snapInd.y), 6, 0, Math.PI * 2);
                  ctx.fillStyle = '#ffffff'; ctx.fill();
                  ctx.strokeStyle = snapInd.kind === 'end' ? '#1a9d55' : '#00b8d9';
                  ctx.lineWidth = 2.5; ctx.stroke();
                }
                return;
              }
              ctx.beginPath();                     // the point the offset started from
              ctx.arc(sx(offOp.start.x), sy(offOp.start.y), 4.5, 0, Math.PI * 2);
              ctx.fillStyle = '#c026d3'; ctx.fill();
              if (!offOp.prev.length) return;
              offOp.prev.forEach(function(pc) {
                drawSketch(pc.pts, pc.closed, '#c026d3', 1.8, null, [6, 4]);
              });
              if (!cursor) return;
              var txt = fmtLen(offOp.d);
              ctx.font = 'bold 13px Arial';
              var w9 = ctx.measureText(txt).width + 12;
              var tx = sx(cursor.x) + 14, ty = sy(cursor.y) - 12;
              ctx.fillStyle = '#ffffff'; ctx.fillRect(tx - w9 / 2, ty - 10, w9, 19);
              ctx.strokeStyle = '#c026d3'; ctx.lineWidth = 1; ctx.strokeRect(tx - w9 / 2, ty - 10, w9, 19);
              ctx.fillStyle = '#c026d3'; ctx.textAlign = 'center';
              ctx.fillText(txt, tx, ty + 5);
              ctx.textAlign = 'left';
            }

            // Grouping is an attribute (gid) shared by the members - clicking any
            // member selects the whole group. Nothing is nested in the model, so
            // every shape still regenerates from its own points.
            var gidSeq = 1;
            function groupSel() {
              var shapes = selList.filter(function(o) { return o.type === 'sketch'; });
              if (shapes.length < 2) return;
              var gid = 'g' + (Date0() % 100000) + '-' + (gidSeq++);
              var ids = [];
              shapes.forEach(function(o) {
                o.sk.gid = gid;
                if (o.kind !== 'pending' && o.sk.id) ids.push(o.sk.id);
              });
              if (ids.length) sketchup.set_sketch_group(JSON.stringify({ ids: ids, gid: gid }));
              updateSelPanel(); draw();
            }

            function ungroupSel() {
              var shapes = selList.filter(function(o) { return o.type === 'sketch'; });
              var ids = [];
              shapes.forEach(function(o) {
                o.sk.gid = null;
                if (o.kind !== 'pending' && o.sk.id) ids.push(o.sk.id);
              });
              if (ids.length) sketchup.set_sketch_group(JSON.stringify({ ids: ids, gid: '' }));
              updateSelPanel(); draw();
            }

            function Date0() { return gidSeq * 7919; }   // no Date in this context

            // Every shape sharing the clicked shape's gid.
            function groupMates(hit) {
              if (!hit || !hit.sk || !hit.sk.gid) return [hit];
              var out = [];
              sketches.forEach(function(sk, i) { if (sk.gid === hit.sk.gid) out.push({ type:'sketch', sk:sk, kind:'model', i:i }); });
              pendingSketches.forEach(function(sk, i) { if (sk.gid === hit.sk.gid) out.push({ type:'sketch', sk:sk, kind:'pending', i:i }); });
              return out.length ? out : [hit];
            }

            // ---- rotate / flip selected shapes (2026-07-31) ------------------
            // Pending shapes transform locally; shapes already in the model are
            // sent to Ruby and rebuilt in place (same id). Everything turns
            // about the combined centre of the selection.
            function selShapesCentre(shapes) {
              var xs = 1e15, ys = 1e15, xb = -1e15, yb = -1e15;
              shapes.forEach(function(o) {
                var f = o.sk.pts;
                for (var i = 0; i + 1 < f.length; i += 2) {
                  if (f[i] < xs) xs = f[i];
                  if (f[i] > xb) xb = f[i];
                  if (f[i + 1] < ys) ys = f[i + 1];
                  if (f[i + 1] > yb) yb = f[i + 1];
                }
              });
              return { x: (xs + xb) / 2, y: (ys + yb) / 2 };
            }

            function transformShapes(fn) {
              var shapes = selList.filter(function(o) { return o.type === 'sketch'; });
              if (!shapes.length) return;
              var c = selShapesCentre(shapes);
              var payload = [];
              shapes.forEach(function(o) {
                var f = o.sk.pts;
                var np = [];
                for (var i = 0; i + 1 < f.length; i += 2) {
                  var q = fn(f[i], f[i + 1], c);
                  np.push(q.x, q.y);
                }
                o.sk.pts = np;
                if (o.kind !== 'pending' && o.sk.id) payload.push({ id: o.sk.id, pts: np });
              });
              draw();
              if (payload.length) sketchup.update_sketches(JSON.stringify({ shapes: payload }));
            }

            // ---- free rotation (2026-07-31) ----------------------------------
            // Click the tool, then swing the mouse: the selection turns about
            // its own centre through ANY angle, live. Shift snaps to 15 deg,
            // typing an angle + Enter sets it exactly, Esc puts it back.
            var rotOp = null;   // { c, base, orig:[{o, pts}], ang }

            // The SketchUp protractor: click the centre, click a start point to
            // fix the base angle, then turn. Degrees can be typed at any point.
            function startFreeRotate() {
              var shapes = selList.filter(function(o) { return o.type === 'sketch'; });
              if (!shapes.length) return;
              rotOp = {
                c: null,
                base: null,
                baseP: null,
                ang: 0,
                orig: shapes.map(function(o) { return { o: o, pts: o.sk.pts.slice() }; })
              };
              setStatusHint('לחץ על מרכז הסיבוב');
              draw();
            }

            function rotCentre(p) {
              if (!rotOp) return;
              var q = snapPoint(p, null);
              rotOp.c = { x: q.x, y: q.y };
              setStatusHint('לחץ על נקודת התחלה — היא קובעת את זווית האפס');
              draw();
            }

            // The zero-angle arm gets the SAME axis inference as the turn
            // itself: it locks onto right / left / up / down as it passes them,
            // so the angle is measured from something square. Pointing at a
            // real corner still wins over the axis, as in SketchUp.
            function rotBaseAim() {
              if (!rotOp || !rotOp.c || !cursor) return null;
              var q = snapPoint(cursor, null);
              var L = Math.hypot(q.y - rotOp.c.y, q.x - rotOp.c.x);
              if (L < 0.5) return null;
              var a = Math.atan2(q.y - rotOp.c.y, q.x - rotOp.c.x);
              var axis = null;
              if (!q.snapped) {
                var Q = Math.PI / 2;
                var k = Math.round(a / Q) * Q;
                if (Math.abs(a - k) < 0.07) {
                  a = k;
                  axis = Math.abs(Math.cos(k)) > 0.5 ? 'x' : 'y';
                }
              }
              return { a: a, axis: axis,
                       p: { x: rotOp.c.x + Math.cos(a) * L, y: rotOp.c.y + Math.sin(a) * L } };
            }

            function rotSetBase(p) {
              if (!rotOp || !rotOp.c) return;
              cursor = { x: p.x, y: p.y };
              var aim = rotBaseAim();
              if (!aim) return;                     // too close to the centre to aim
              rotOp.base = aim.a;
              rotOp.baseP = aim.p;
              rotOp.axis = null;
              setStatusHint('הזז לסיבוב · Shift קפיצות 15° · הקלד מעלות + Enter · Esc ביטול');
              draw();
            }

            function rotApply(ang) {
              if (!rotOp) return;
              rotOp.ang = ang;
              var ca = Math.cos(ang), sa = Math.sin(ang), c = rotOp.c;
              rotOp.orig.forEach(function(rec) {
                var np = [];
                for (var i = 0; i + 1 < rec.pts.length; i += 2) {
                  var dx = rec.pts[i] - c.x, dy = rec.pts[i + 1] - c.y;
                  np.push(c.x + dx * ca - dy * sa, c.y + dx * sa + dy * ca);
                }
                rec.o.sk.pts = np;
              });
            }

            function rotMove() {
              if (!rotOp || !rotOp.c || rotOp.base === null || !cursor) return;
              var a = Math.atan2(cursor.y - rotOp.c.y, cursor.x - rotOp.c.x);
              rotOp.axis = null;
              if (shiftDown) {                    // Shift: 15-degree steps
                var step = Math.PI / 12;
                rotApply(Math.round((a - rotOp.base) / step) * step);
                draw();
                return;
              }
              // SketchUp inference: the arm locks onto right / left / up / down
              // as it passes them, so a square turn lands exactly square.
              var Q = Math.PI / 2;
              var k = Math.round(a / Q) * Q;
              if (Math.abs(a - k) < 0.07) {       // about 4 degrees
                a = k;
                rotOp.axis = Math.abs(Math.cos(k)) > 0.5 ? 'x' : 'y';
              }
              var d = a - rotOp.base;
              if (!rotOp.axis) {                  // otherwise a quarter turn still snaps clean
                var q2 = Math.round(d / Q) * Q;
                if (Math.abs(d - q2) < 0.035) d = q2;
              }
              rotApply(d);
              draw();
            }

            function rotCommit() {
              if (!rotOp) return;
              var payload = [];
              rotOp.orig.forEach(function(rec) {
                if (rec.o.kind !== 'pending' && rec.o.sk.id) {
                  payload.push({ id: rec.o.sk.id, pts: rec.o.sk.pts });
                }
              });
              rotOp = null;
              setStatusHint(null);
              draw();
              if (payload.length) sketchup.update_sketches(JSON.stringify({ shapes: payload }));
            }

            function rotCancel() {
              if (!rotOp) return;
              rotOp.orig.forEach(function(rec) { rec.o.sk.pts = rec.pts.slice(); });
              rotOp = null;
              setStatusHint(null);
              draw();
            }

            function snapRing() {                  // the point about to be picked
              if (!snapInd) return;
              ctx.beginPath();
              ctx.arc(sx(snapInd.x), sy(snapInd.y), 6, 0, Math.PI * 2);
              ctx.fillStyle = '#ffffff'; ctx.fill();
              ctx.strokeStyle = snapInd.kind === 'end' ? '#1a9d55' : '#00b8d9';
              ctx.lineWidth = 2.5; ctx.stroke();
            }

            function drawRotOp() {
              if (!rotOp || !cursor) return;
              if (!rotOp.c) { snapRing(); return; }          // choosing the centre
              var c = rotOp.c;
              ctx.beginPath();                               // the centre pin
              ctx.arc(sx(c.x), sy(c.y), 5, 0, Math.PI * 2);
              ctx.fillStyle = '#c026d3'; ctx.fill();
              if (rotOp.base === null) {                     // choosing the zero angle
                var aim = rotBaseAim();
                var bcol = !aim || !aim.axis ? '#8a8f98'
                         : (aim.axis === 'x' ? '#e0392b' : '#1a9d55');
                if (aim && aim.axis) {                       // the axis it snapped to
                  ctx.strokeStyle = bcol; ctx.lineWidth = 1;
                  ctx.setLineDash([2, 4]);
                  ctx.beginPath();
                  if (aim.axis === 'x') {
                    ctx.moveTo(sx(c.x - 4000), sy(c.y)); ctx.lineTo(sx(c.x + 4000), sy(c.y));
                  } else {
                    ctx.moveTo(sx(c.x), sy(c.y - 4000)); ctx.lineTo(sx(c.x), sy(c.y + 4000));
                  }
                  ctx.stroke();
                  ctx.setLineDash([]);
                }
                ctx.strokeStyle = bcol; ctx.lineWidth = (aim && aim.axis) ? 1.8 : 1.2;
                ctx.setLineDash([5, 4]);
                ctx.beginPath();
                ctx.moveTo(sx(c.x), sy(c.y));
                var bp = aim ? aim.p : cursor;
                ctx.lineTo(sx(bp.x), sy(bp.y));
                ctx.stroke();
                ctx.setLineDash([]);
                snapRing();
                return;
              }
              if (rotOp.baseP) {                             // the zero-angle arm stays visible
                ctx.strokeStyle = '#8a8f98'; ctx.lineWidth = 1.2;
                ctx.beginPath();
                ctx.moveTo(sx(c.x), sy(c.y));
                ctx.lineTo(sx(rotOp.baseP.x), sy(rotOp.baseP.y));
                ctx.stroke();
              }
              // Arm colour says what it is locked to: red across, green up.
              var rcol = rotOp.axis === 'x' ? '#e0392b' : (rotOp.axis === 'y' ? '#1a9d55' : '#c026d3');
              if (rotOp.axis) {                              // the axis it snapped to
                ctx.strokeStyle = rcol; ctx.lineWidth = 1;
                ctx.setLineDash([2, 4]);
                ctx.beginPath();
                if (rotOp.axis === 'x') {
                  ctx.moveTo(sx(c.x - 4000), sy(c.y)); ctx.lineTo(sx(c.x + 4000), sy(c.y));
                } else {
                  ctx.moveTo(sx(c.x), sy(c.y - 4000)); ctx.lineTo(sx(c.x), sy(c.y + 4000));
                }
                ctx.stroke();
                ctx.setLineDash([]);
              }
              ctx.strokeStyle = rcol; ctx.lineWidth = rotOp.axis ? 1.8 : 1.2;
              ctx.setLineDash([5, 4]);
              ctx.beginPath();
              ctx.moveTo(sx(c.x), sy(c.y));
              ctx.lineTo(sx(cursor.x), sy(cursor.y));
              ctx.stroke();
              ctx.setLineDash([]);
              var deg = rotOp.ang * 180 / Math.PI;
              while (deg <= -180) deg += 360;
              while (deg > 180) deg -= 360;
              var txt = deg.toFixed(1) + '°';
              ctx.font = 'bold 13px Arial';
              var w7 = ctx.measureText(txt).width + 12;
              var tx = (sx(c.x) + sx(cursor.x)) / 2, ty = (sy(c.y) + sy(cursor.y)) / 2;
              ctx.fillStyle = '#ffffff'; ctx.fillRect(tx - w7 / 2, ty - 10, w7, 19);
              ctx.strokeStyle = '#c026d3'; ctx.lineWidth = 1; ctx.strokeRect(tx - w7 / 2, ty - 10, w7, 19);
              ctx.fillStyle = '#c026d3'; ctx.textAlign = 'center';
              ctx.fillText(txt, tx, ty + 5);
              ctx.textAlign = 'left';
            }

            // ---- move (2026-08-01, SketchUp behaviour) ----------------------
            // Exactly the Move tool: pick the tool, CLICK A GRAB POINT on the
            // object (a corner, an end, a midpoint - it snaps), then move. The
            // object travels by grab-point to cursor, so nothing ever jumps.
            // Near-axis movement locks to the axis on its own (Shift forces it),
            // the destination snaps to other corners, and typing a distance +
            // Enter sets it exactly. Second click drops it, Esc puts it back.
            var moveOp = null;   // { grab, orig:[{o, pts}], dx, dy, lock }

            function startFreeMove() {
              var shapes = selList.filter(function(o) { return o.type === 'sketch'; });
              if (!shapes.length) return;
              moveOp = { grab: null, dx: 0, dy: 0, lock: null,
                         orig: shapes.map(function(o) { return { o: o, pts: o.sk.pts.slice() }; }) };
              setStatusHint('לחץ על נקודת אחיזה באובייקט — פינה, קצה או אמצע');
              draw();
            }

            function moveGrab(p) {
              if (!moveOp) return;
              var q = snapPoint(p, null);
              moveOp.grab = { x: q.x, y: q.y };
              setStatusHint('הזז · Shift נועל ציר · הקלד מרחק + Enter · Esc ביטול');
              draw();
            }

            function moveApply(dx, dy) {
              if (!moveOp) return;
              moveOp.dx = dx; moveOp.dy = dy;
              moveOp.orig.forEach(function(rec) {
                var f = rec.pts, np = [];
                for (var i = 0; i + 1 < f.length; i += 2) np.push(f[i] + dx, f[i + 1] + dy);
                rec.o.sk.pts = np;
              });
            }

            function moveMove() {
              if (!moveOp || !moveOp.grab || !cursor) return;
              var q = snapPoint(cursor, null);         // destination snaps like everything else
              var dx = q.x - moveOp.grab.x, dy = q.y - moveOp.grab.y;
              var lock = null;
              if (shiftDown) {                         // Shift forces the stronger axis
                lock = Math.abs(dx) >= Math.abs(dy) ? 'x' : 'y';
              } else if (Math.hypot(dx, dy) > 1) {     // and it locks on by itself near an axis
                if (Math.abs(dy) < Math.abs(dx) * 0.09) lock = 'x';
                else if (Math.abs(dx) < Math.abs(dy) * 0.09) lock = 'y';
              }
              if (lock === 'x') dy = 0; else if (lock === 'y') dx = 0;
              moveOp.lock = lock;
              moveApply(dx, dy);
              draw();
            }

            function moveCommit() {
              if (!moveOp) return;
              var payload = [];
              moveOp.orig.forEach(function(rec) {
                if (rec.o.kind !== 'pending' && rec.o.sk.id) {
                  payload.push({ id: rec.o.sk.id, pts: rec.o.sk.pts });
                }
              });
              moveOp = null;
              setStatusHint(null);
              draw();
              if (payload.length) sketchup.update_sketches(JSON.stringify({ shapes: payload }));
            }

            function moveCancel() {
              if (!moveOp) return;
              moveOp.orig.forEach(function(rec) { rec.o.sk.pts = rec.pts.slice(); });
              moveOp = null;
              setStatusHint(null);
              draw();
            }

            function drawMoveOp() {
              if (!moveOp) return;
              // Before the grab point is picked, just show what would be grabbed.
              if (!moveOp.grab) {
                if (snapInd) {
                  ctx.beginPath();
                  ctx.arc(sx(snapInd.x), sy(snapInd.y), 6, 0, Math.PI * 2);
                  ctx.fillStyle = '#ffffff'; ctx.fill();
                  ctx.strokeStyle = snapInd.kind === 'end' ? '#1a9d55' : '#00b8d9';
                  ctx.lineWidth = 2.5; ctx.stroke();
                }
                return;
              }
              var a = moveOp.grab, b = { x: a.x + moveOp.dx, y: a.y + moveOp.dy };
              // The locked axis draws in the SketchUp colours: red across, green up.
              var acol = moveOp.lock === 'x' ? '#e0392b' : (moveOp.lock === 'y' ? '#1a9d55' : '#c026d3');
              if (moveOp.lock) {
                ctx.strokeStyle = acol; ctx.lineWidth = 1;
                ctx.setLineDash([2, 4]);
                ctx.beginPath();
                if (moveOp.lock === 'x') {
                  ctx.moveTo(sx(a.x - 4000), sy(a.y)); ctx.lineTo(sx(a.x + 4000), sy(a.y));
                } else {
                  ctx.moveTo(sx(a.x), sy(a.y - 4000)); ctx.lineTo(sx(a.x), sy(a.y + 4000));
                }
                ctx.stroke();
                ctx.setLineDash([]);
              }
              ctx.strokeStyle = acol; ctx.lineWidth = 1.6;
              ctx.setLineDash([5, 4]);
              ctx.beginPath();
              ctx.moveTo(sx(a.x), sy(a.y));
              ctx.lineTo(sx(b.x), sy(b.y));
              ctx.stroke();
              ctx.setLineDash([]);
              ctx.beginPath();                     // the grab point itself
              ctx.arc(sx(a.x), sy(a.y), 4.5, 0, Math.PI * 2);
              ctx.fillStyle = acol; ctx.fill();
              if (snapInd) {                       // snapped destination
                ctx.beginPath();
                ctx.arc(sx(snapInd.x), sy(snapInd.y), 6, 0, Math.PI * 2);
                ctx.fillStyle = '#ffffff'; ctx.fill();
                ctx.strokeStyle = snapInd.kind === 'end' ? '#1a9d55' : '#00b8d9';
                ctx.lineWidth = 2.5; ctx.stroke();
              }
              var txt = fmtLen(Math.hypot(moveOp.dx, moveOp.dy));
              ctx.font = 'bold 13px Arial';
              var w8 = ctx.measureText(txt).width + 12;
              var tx = (sx(a.x) + sx(b.x)) / 2, ty = (sy(a.y) + sy(b.y)) / 2;
              ctx.fillStyle = '#ffffff'; ctx.fillRect(tx - w8 / 2, ty - 10, w8, 19);
              ctx.strokeStyle = '#c026d3'; ctx.lineWidth = 1; ctx.strokeRect(tx - w8 / 2, ty - 10, w8, 19);
              ctx.fillStyle = '#c026d3'; ctx.textAlign = 'center';
              ctx.fillText(txt, tx, ty + 5);
              ctx.textAlign = 'left';
            }

            // One Flip for everything: shapes turn in place, walls come out as
            // mirrored pending copies (their attributes cannot flip in place).
            function flipSel(axis) {
              var hasShapes = selList.some(function(o) { return o.type === 'sketch'; });
              if (hasShapes) flipShapes(axis);
              else mirrorSel(axis);
            }

            function flipShapes(axis) {
              transformShapes(function(x, y, c) {
                return axis === 'h' ? { x: 2 * c.x - x, y: y } : { x: x, y: 2 * c.y - y };
              });
            }

            function deleteShapes(list) {
              var ids = [];
              var pidx = [];
              list.forEach(function(o) {
                if (o.kind === 'pending') pidx.push(o.i);
                else if (o.sk.id) ids.push(o.sk.id);
              });
              pidx.sort(function(a, b) { return b - a; }).forEach(function(i) { pendingSketches.splice(i, 1); });
              if (ids.length) sketchup.delete_sketches(JSON.stringify({ ids: ids }));
              return ids.length > 0;
            }

            function deleteSelected() {
              if (!sel) return;
              if (sel.type === 'sketch' && selList.length === 1) {
                if (!confirm('למחוק את הצורה?')) return;
                deleteShapes([sel]);
                setSel(null); updateSelPanel(); updateStatus(); draw();
                return;
              }
              if (selList.length > 1) {
                if (!confirm('למחוק ' + selList.length + ' אלמנטים?')) return;
                var items = [];
                var shapes = selList.filter(function(o) { return o.type === 'sketch'; });
                if (shapes.length) deleteShapes(shapes);
                for (var d1 = selList.length - 1; d1 >= 0; d1--) {
                  var o = selList[d1];
                  if (o.type === 'sketch') continue;
                  if (o.type === 'pending') { pending.splice(o.i, 1); continue; }
                  if (o.type === 'wall') { if (o.w.id) items.push({ kind:'wall', id:o.w.id }); }
                  else if (o.s.id) items.push({ kind:'opening', id:o.s.id, body:o.s.body });
                }
                setSel(null); updateSelPanel(); draw();
                if (items.length) sketchup.delete_many(JSON.stringify({ items: items }));
                return;
              }
              if (sel.type === 'pending') { pending.splice(sel.i, 1); setSel(null); updateSelPanel(); draw(); return; }
              if (!confirm('למחוק את מה שנבחר?')) return;
              if (sel.type === 'wall') {
                sketchup.delete_wall(JSON.stringify({ wall_id: sel.w.id }));
              } else {
                sketchup.delete_opening(JSON.stringify({ id: sel.s.id, body: sel.s.body }));
              }
              setSel(null); updateSelPanel();
            }

            // ---- eraser (2026-08-01) ----------------------------------------
            // Shapes stay WHOLE in the model - nothing is split while drawing.
            // Only the eraser splits: it removes the stretch between the two
            // crossings either side of the click, so an X loses one arm and
            // keeps the other three. Crossings are other shapes, wall bands,
            // and (for straight shapes) the shape own corners. A shape that
            // belongs to a group is protected and erases whole.
            var erasePick = null;      // what the cursor is about to remove

            function skChain(sk) {
              var f = sk.pts || [], out = [], n = f.length / 2;
              for (var i = 0; i < n; i++) out.push({ x: f[i * 2], y: f[i * 2 + 1] });
              if (sk.closed && n > 2) out.push({ x: f[0], y: f[1] });
              return out;
            }

            function chainAcc(pl) {
              var acc = [0];
              for (var i = 1; i < pl.length; i++) {
                acc.push(acc[i - 1] + Math.hypot(pl[i].x - pl[i - 1].x, pl[i].y - pl[i - 1].y));
              }
              return acc;
            }

            function chainPt(pl, acc, s) {
              var L = acc[acc.length - 1];
              if (s <= 0) return { x: pl[0].x, y: pl[0].y };
              if (s >= L) return { x: pl[pl.length - 1].x, y: pl[pl.length - 1].y };
              for (var i = 1; i < pl.length; i++) {
                if (acc[i] >= s) {
                  var sg = acc[i] - acc[i - 1];
                  var t = sg > 0 ? (s - acc[i - 1]) / sg : 0;
                  return { x: pl[i - 1].x + (pl[i].x - pl[i - 1].x) * t,
                           y: pl[i - 1].y + (pl[i].y - pl[i - 1].y) * t };
                }
              }
              return { x: pl[pl.length - 1].x, y: pl[pl.length - 1].y };
            }

            // The stretch between two arc lengths, keeping every vertex inside
            // it - so a curve stays a curve after the cut.
            function chainSlice(pl, acc, a, b) {
              var out = [chainPt(pl, acc, a)];
              for (var i = 0; i < pl.length; i++) {
                if (acc[i] > a + 0.001 && acc[i] < b - 0.001) out.push({ x: pl[i].x, y: pl[i].y });
              }
              out.push(chainPt(pl, acc, b));
              return out;
            }

            // Same, on a closed shape: walks forward and through the seam.
            function chainSliceLoop(pl, acc, a, b) {
              var L = acc[acc.length - 1];
              var na = ((a % L) + L) % L, nb = ((b % L) + L) % L;
              if (nb < 0.001) nb = L;
              if (nb > na + 0.001) return chainSlice(pl, acc, na, nb);
              var p1 = chainSlice(pl, acc, na, L);
              var p2 = chainSlice(pl, acc, 0, nb);
              return p1.concat(p2.slice(1));
            }

            // Where two segments cross, as a fraction along the first one.
            // The epsilon matters: a shape that was already trimmed ENDS exactly
            // on the other one, and without it that touch reads as a miss.
            function segCross(a, b, c, d) {
              var rx = b.x - a.x, ry = b.y - a.y;
              var qx = d.x - c.x, qy = d.y - c.y;
              var den = rx * qy - ry * qx;
              if (Math.abs(den) < 1e-9) return null;          // parallel
              var t = ((c.x - a.x) * qy - (c.y - a.y) * qx) / den;
              var u = ((c.x - a.x) * ry - (c.y - a.y) * rx) / den;
              var E = 1e-7;
              if (t < -E || t > 1 + E || u < -E || u > 1 + E) return null;
              return Math.max(0, Math.min(1, t));
            }

            // Everything that can cut a shape: the other shapes, and the wall
            // bands - so a line can be trimmed exactly at the face of a wall.
            function cutterChains(skip) {
              var out = [];
              sketches.forEach(function(o) { if (o !== skip && o.pts && o.pts.length >= 4) out.push(skChain(o)); });
              pendingSketches.forEach(function(o) { if (o !== skip && o.pts && o.pts.length >= 4) out.push(skChain(o)); });
              var all = walls.concat(pending);
              all.forEach(function(w) {
                var b = bandQuad(w); if (!b) return;
                var C = endCorners(w, all, b);
                out.push([C.sp, C.ep, C.eq, C.sq, C.sp]);
              });
              return out;
            }

            function cutMarks(sk, pl, acc) {
              var L = acc[acc.length - 1];
              var shp = sk.shape || 'line';
              var smooth = (shp === 'arc' || shp === 'circle');
              var marks = [];
              if (!smooth) {                       // corners of a straight shape
                for (var i = 1; i + 1 < pl.length; i++) marks.push(acc[i]);
                if (sk.closed) marks.push(0);
              }
              var cutters = cutterChains(sk);
              for (var j = 1; j < pl.length; j++) {
                var a = pl[j - 1], b = pl[j];
                var segL = acc[j] - acc[j - 1];
                for (var k = 0; k < cutters.length; k++) {
                  var ch = cutters[k];
                  for (var m = 1; m < ch.length; m++) {
                    var t = segCross(a, b, ch[m - 1], ch[m]);
                    if (t !== null) marks.push(acc[j - 1] + t * segL);
                  }
                }
              }
              // A shape that ENDS on this one cuts it as well. Without this,
              // trimming one arc back to the crossing makes the crossing vanish
              // and the leftover of the other arc can no longer be erased on
              // its own - it reads as one whole shape again.
              cutters.forEach(function(ch) {
                if (ch.length < 2) return;
                var loop = Math.hypot(ch[0].x - ch[ch.length - 1].x,
                                      ch[0].y - ch[ch.length - 1].y) < 0.001;
                if (loop) return;                  // a closed chain has no free ends
                [ch[0], ch[ch.length - 1]].forEach(function(ep) {
                  var pr = chainProj(ep, pl, acc);
                  if (pr.d < 0.05) marks.push(pr.s);
                });
              });
              marks.sort(function(x, y) { return x - y; });
              var out = [];
              marks.forEach(function(v) {
                if (v < -0.001 || v > L + 0.001) return;
                if (!out.length || v - out[out.length - 1] > 0.05) out.push(v);
              });
              // on a closed shape 0 and L are the same point
              if (sk.closed && out.length > 1 && L - out[out.length - 1] < 0.05 && out[0] < 0.05) out.pop();
              return out;
            }

            function chainProj(p, pl, acc) {
              var bestD = 1e18, bestS = 0;
              for (var i = 1; i < pl.length; i++) {
                var ax = pl[i - 1].x, ay = pl[i - 1].y;
                var vx = pl[i].x - ax, vy = pl[i].y - ay;
                var LL = vx * vx + vy * vy;
                var t = LL > 0 ? ((p.x - ax) * vx + (p.y - ay) * vy) / LL : 0;
                t = Math.max(0, Math.min(1, t));
                var d = Math.hypot(p.x - (ax + vx * t), p.y - (ay + vy * t));
                if (d < bestD) { bestD = d; bestS = acc[i - 1] + t * Math.sqrt(LL); }
              }
              return { s: bestS, d: bestD };
            }

            function eraseFind(p) {
              var tol = 10 / scale;
              var best = null, bestD = tol;
              function scan(sk, kind, idx) {
                if (!sk.pts || sk.pts.length < 4) return;
                var pl = skChain(sk), acc = chainAcc(pl);
                if (acc[acc.length - 1] < 0.05) return;
                var pr = chainProj(p, pl, acc);
                if (pr.d < bestD) { bestD = pr.d; best = { sk:sk, kind:kind, i:idx, pl:pl, acc:acc, s:pr.s }; }
              }
              sketches.forEach(function(sk, i) { scan(sk, 'model', i); });
              pendingSketches.forEach(function(sk, i) { scan(sk, 'pending', i); });
              if (!best) return null;
              var sk = best.sk, pl = best.pl, acc = best.acc;
              var L = acc[acc.length - 1];
              function wholeShape() {
                return { sk:sk, kind:best.kind, i:best.i, whole:true,
                         cut: sk.pts.slice(), closed: !!sk.closed, rest: [] };
              }
              if (sk.gid) return wholeShape();          // grouped = protected
              var marks = cutMarks(sk, pl, acc);
              if (!marks.length) return wholeShape();   // nothing crosses it
              var cutPts, rest = [];
              if (sk.closed) {
                var before = null, after = null;
                for (var i2 = 0; i2 < marks.length; i2++) {
                  if (marks[i2] <= best.s) before = marks[i2];
                  if (after === null && marks[i2] > best.s) after = marks[i2];
                }
                if (before === null) before = marks[marks.length - 1] - L;
                if (after === null) after = marks[0] + L;
                cutPts = chainSliceLoop(pl, acc, before, after);
                var keep = chainSliceLoop(pl, acc, after, before);
                if (keep.length > 1) rest.push(keep);
              } else {
                var s0 = 0, s1 = L;
                for (var j2 = 0; j2 < marks.length; j2++) {
                  if (marks[j2] <= best.s) s0 = marks[j2];
                  else { s1 = marks[j2]; break; }
                }
                cutPts = chainSlice(pl, acc, s0, s1);
                if (s0 > 0.05) rest.push(chainSlice(pl, acc, 0, s0));
                if (L - s1 > 0.05) rest.push(chainSlice(pl, acc, s1, L));
              }
              if (!rest.length) return wholeShape();    // nothing would survive
              return { sk:sk, kind:best.kind, i:best.i, whole:false,
                       cut: flatten(cutPts), closed:false, rest: rest };
            }

            function eraseApply() {
              var t = erasePick;
              if (!t) return;
              erasePick = null;
              if (t.whole) {
                deleteShapes(groupMates({ type:'sketch', sk:t.sk, kind:t.kind, i:t.i }));
                setSel(null); updateSelPanel(); updateStatus(); draw();
                return;
              }
              if (t.kind === 'pending') {
                var src = pendingSketches[t.i];
                pendingSketches.splice(t.i, 1);
                t.rest.forEach(function(pc) {
                  pendingSketches.push({ pts: flatten(pc), closed:false, style:src.style,
                                         weight:src.weight, shape:src.shape || 'line' });
                });
                updateStatus(); draw();
                return;
              }
              var payload = { id: t.sk.id,
                              pieces: t.rest.map(function(pc) { return { pts: flatten(pc) }; }) };
              draw();
              sketchup.split_sketch(JSON.stringify(payload));
            }

            function distToSeg(p, ax, ay, bx, by) {
              var vx = bx - ax, vy = by - ay;
              var L = vx * vx + vy * vy;
              var t6 = L > 0 ? ((p.x - ax) * vx + (p.y - ay) * vy) / L : 0;
              t6 = Math.max(0, Math.min(1, t6));
              return Math.hypot(p.x - (ax + vx * t6), p.y - (ay + vy * t6));
            }

            // Click near any edge of a drawn shape selects it.
            function hitSketch(p) {
              var tol = 8 / scale;
              var best = null, bestD = tol;
              function scan(sk, kind, idx) {
                var f = sk.pts;
                if (!f || f.length < 4) return;
                var n = f.length / 2;
                for (var i6b = 0; i6b + 1 < n; i6b++) {
                  var d6 = distToSeg(p, f[i6b * 2], f[i6b * 2 + 1], f[(i6b + 1) * 2], f[(i6b + 1) * 2 + 1]);
                  if (d6 < bestD) { bestD = d6; best = { type:'sketch', sk:sk, kind:kind, i:idx }; }
                }
                if (sk.closed && n > 2) {
                  var dc = distToSeg(p, f[(n - 1) * 2], f[(n - 1) * 2 + 1], f[0], f[1]);
                  if (dc < bestD) { bestD = dc; best = { type:'sketch', sk:sk, kind:kind, i:idx }; }
                }
              }
              sketches.forEach(function(sk, i6) { scan(sk, 'model', i6); });
              pendingSketches.forEach(function(sk, i6) { scan(sk, 'pending', i6); });
              if (best) return best;
              // No edge under the cursor - a click INSIDE a closed shape
              // selects it too. The smallest containing shape wins, so an
              // inner shape is still pickable through an outer one.
              var bestArea = 1e18;
              function inside(sk) {
                var f = sk.pts;
                if (!sk.closed || !f || f.length < 6) return false;
                var n = f.length / 2, hit = false;
                for (var i = 0, j = n - 1; i < n; j = i++) {
                  var xi = f[i * 2], yi = f[i * 2 + 1], xj = f[j * 2], yj = f[j * 2 + 1];
                  if ((yi > p.y) !== (yj > p.y) &&
                      p.x < (xj - xi) * (p.y - yi) / (yj - yi) + xi) hit = !hit;
                }
                return hit;
              }
              function areaOf(sk) {
                var f = sk.pts, n = f.length / 2, a = 0;
                for (var i = 0; i < n; i++) {
                  var j2 = (i + 1) % n;
                  a += f[i * 2] * f[j2 * 2 + 1] - f[j2 * 2] * f[i * 2 + 1];
                }
                return Math.abs(a / 2);
              }
              function scanIn(sk, kind, idx) {
                if (!inside(sk)) return;
                var ar = areaOf(sk);
                if (ar < bestArea) { bestArea = ar; best = { type:'sketch', sk:sk, kind:kind, i:idx }; }
              }
              sketches.forEach(function(sk, i6) { scanIn(sk, 'model', i6); });
              pendingSketches.forEach(function(sk, i6) { scanIn(sk, 'pending', i6); });
              return best;
            }

            function hitOpening(p) {
              var best = null;
              walls.forEach(function(w){
                var b = bandQuad(w); if (!b || !w.syms) return;
                var dx = p.x - w.sx, dy = p.y - w.sy;
                var tt = dx*b.ux + dy*b.uy;
                var off = dx*b.nx + dy*b.ny;
                var tol = 8 / scale;
                w.syms.forEach(function(s){
                  if (tt < s.t - s.w/2 - 2 || tt > s.t + s.w/2 + 2) return;
                  if (off < b.q - tol - 4 || off > b.p + tol + 4) return;
                  best = { w:w, s:s, b:b };
                });
              });
              return best;
            }

            function hitPending(p) {
              for (var i = pending.length - 1; i >= 0; i--) {
                var w = pending[i];
                var b = bandQuad(w); if (!b) continue;
                var dx = p.x - w.sx, dy = p.y - w.sy;
                var tt = dx*b.ux + dy*b.uy;
                var off = dx*b.nx + dy*b.ny;
                if (tt >= -2 && tt <= b.len + 2 && off >= b.q - 3 && off <= b.p + 3) return i;
              }
              return -1;
            }

            function resize() {
              var w = document.getElementById('canvasWrap');
              cv.width = Math.max(80, w.clientWidth);
              cv.height = Math.max(80, w.clientHeight);
              draw();
            }
            window.onresize = resize;
            // Some SketchUp/CEF builds fire no resize event on dialog resize —
            // observe the wrapper too so the canvas always matches its box.
            try {
              new ResizeObserver(resize).observe(document.getElementById('canvasWrap'));
            } catch (e) {}

            function sx(x) { return x * scale + panX; }
            function sy(y) { return cv.height - (y * scale + panY); }
            function mx(px) { return (px - panX) / scale; }
            function my(py) { return (cv.height - py - panY) / scale; }

            function fmtLen(v) {
              var neg = v < 0; v = Math.abs(v);
              var ft = Math.floor(v / 12), inch = v - ft * 12;
              var r = Math.round(inch * 2) / 2;
              if (r >= 12) { ft += 1; r = 0; }
              var s = (ft > 0 ? ft + "' " : '') + (r % 1 === 0 ? r : r.toFixed(1)) + '"';
              return (neg ? '-' : '') + s;
            }

            // Accepts: 42 | 42" | 3' | 3' 6 | 3'6" | 3 6 (feet space inches)
            function parseLen(s) {
              s = String(s).trim(); if (!s) return null;
              var m = s.match(/^(\\d+(?:\\.\\d+)?)'\\s*(\\d+(?:\\.\\d+)?)?\\"?$/);
              if (m) return parseFloat(m[1]) * 12 + (m[2] ? parseFloat(m[2]) : 0);
              m = s.match(/^(\\d+(?:\\.\\d+)?)\\s+(\\d+(?:\\.\\d+)?)$/);
              if (m) return parseFloat(m[1]) * 12 + parseFloat(m[2]);
              m = s.match(/^(\\d+(?:\\.\\d+)?)\\"?$/);
              if (m) return parseFloat(m[1]);
              return null;
            }

            // Selection box, SketchUp behaviour (2026-08-01). Dragging LEFT to
            // RIGHT is a window select: only what fits entirely inside is taken.
            // Dragging RIGHT to LEFT is a crossing select: anything the box
            // touches is taken. It used to test the element CENTRE, which made
            // long walls and lines look like the box was broken.
            function rubberCrossing() { return rubber && rubber.x1 < rubber.x0; }

            function rubberPick() {
              var xa = Math.min(rubber.x0, rubber.x1), xb = Math.max(rubber.x0, rubber.x1);
              var ya = Math.min(rubber.y0, rubber.y1), yb = Math.max(rubber.y0, rubber.y1);
              var crossing = rubberCrossing();
              function inRect(x, y) { return x >= xa && x <= xb && y >= ya && y <= yb; }
              var RE = [[{x:xa,y:ya},{x:xb,y:ya}], [{x:xb,y:ya},{x:xb,y:yb}],
                        [{x:xb,y:yb},{x:xa,y:yb}], [{x:xa,y:yb},{x:xa,y:ya}]];
              function segHits(a, b) {
                if (inRect(a.x, a.y) || inRect(b.x, b.y)) return true;
                for (var i = 0; i < 4; i++) {
                  if (segCross(a, b, RE[i][0], RE[i][1]) !== null) return true;
                }
                return false;
              }
              // takes a list of points; window = every point in, crossing = any edge touched
              function ringTaken(P, closed) {
                if (!P || P.length < 2) return false;
                if (!crossing) {
                  for (var i = 0; i < P.length; i++) if (!inRect(P[i].x, P[i].y)) return false;
                  return true;
                }
                var m = closed ? P.length : P.length - 1;
                for (var j = 0; j < m; j++) {
                  if (segHits(P[j], P[(j + 1) % P.length])) return true;
                }
                return false;
              }
              function flatToPts(f) {
                var P = [];
                for (var i = 0; i + 1 < f.length; i += 2) P.push({ x:f[i], y:f[i + 1] });
                return P;
              }
              var out = [];
              var all = walls.concat(pending);
              function wallTaken(w) {
                var b = bandQuad(w); if (!b) return false;
                var C = endCorners(w, all, b);
                return ringTaken([C.sp, C.ep, C.eq, C.sq], true);
              }
              walls.forEach(function(w) {
                if (wallTaken(w)) out.push({ type:'wall', w:w });
                var b = bandQuad(w); if (!b) return;
                (w.syms || []).forEach(function(sy2) {
                  var hw = (sy2.w || 0) / 2;
                  var a1 = { x: w.sx + b.ux * (sy2.t - hw), y: w.sy + b.uy * (sy2.t - hw) };
                  var a2 = { x: w.sx + b.ux * (sy2.t + hw), y: w.sy + b.uy * (sy2.t + hw) };
                  if (ringTaken([a1, a2], false)) out.push({ type:'sym', w:w, s:sy2 });
                });
              });
              pending.forEach(function(pw, pi2) {
                if (wallTaken(pw)) out.push({ type:'pending', i:pi2 });
              });
              function skTaken(sk) {
                if (!sk.pts || sk.pts.length < 4) return false;
                return ringTaken(flatToPts(sk.pts), !!sk.closed);
              }
              sketches.forEach(function(sk, i1) { if (skTaken(sk)) out.push({ type:'sketch', sk:sk, kind:'model', i:i1 }); });
              pendingSketches.forEach(function(sk, i1) { if (skTaken(sk)) out.push({ type:'sketch', sk:sk, kind:'pending', i:i1 }); });
              return out;
            }

            // Solid box = window select, dashed = crossing. Same visual language
            // SketchUp uses, so the drag direction is readable while you drag.
            function drawRubber() {
              var x0 = sx(rubber.x0), y0 = sy(rubber.y0), x1 = sx(rubber.x1), y1 = sy(rubber.y1);
              var cross = rubberCrossing();
              ctx.save();
              ctx.fillStyle = cross ? 'rgba(26,157,85,0.07)' : 'rgba(75,137,255,0.07)';
              ctx.fillRect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
              ctx.strokeStyle = cross ? '#1a9d55' : '#4b89ff';
              ctx.lineWidth = 1;
              ctx.setLineDash(cross ? [4, 3] : []);
              ctx.strokeRect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
              ctx.restore();
            }

            function bandQuad(w) {
              var dx = w.ex - w.sx, dy = w.ey - w.sy;
              var len = Math.sqrt(dx*dx + dy*dy); if (len < 0.01) return null;
              var ux = dx/len, uy = dy/len, nx = -uy, ny = ux;
              var p, q;
              if (w.ha === 'left') { p = w.th; q = 0; }
              else if (w.ha === 'right') { p = 0; q = -w.th; }
              else { p = w.th/2; q = -w.th/2; }
              return { ux:ux, uy:uy, nx:nx, ny:ny, len:len, p:p, q:q };
            }

            function lineInt(p1, d1, p2, d2) {
              var denom = d1.x*d2.y - d1.y*d2.x;
              if (Math.abs(denom) < 1e-9) return null;
              var t = ((p2.x - p1.x)*d2.y - (p2.y - p1.y)*d2.x) / denom;
              return { x: p1.x + d1.x*t, y: p1.y + d1.y*t };
            }

            // Band corner points at both wall ends. Applied walls use the exact
            // mitered corners_xy from the model; pending walls get a JS miter
            // against the neighbour that shares the endpoint.
            function endCorners(w, all, b) {
              if (w.corners && w.corners.length === 8) {
                return { sp:{x:w.corners[0],y:w.corners[1]}, ep:{x:w.corners[2],y:w.corners[3]},
                         eq:{x:w.corners[4],y:w.corners[5]}, sq:{x:w.corners[6],y:w.corners[7]} };
              }
              var def = {
                sp:{x:w.sx + b.nx*b.p, y:w.sy + b.ny*b.p},
                sq:{x:w.sx + b.nx*b.q, y:w.sy + b.ny*b.q},
                ep:{x:w.ex + b.nx*b.p, y:w.ey + b.ny*b.p},
                eq:{x:w.ex + b.nx*b.q, y:w.ey + b.ny*b.q}
              };
              ['s','e'].forEach(function(end){
                var P = end === 's' ? {x:w.sx, y:w.sy} : {x:w.ex, y:w.ey};
                var partner = null, cont = true;
                (all || []).forEach(function(o){
                  if (o === w || partner) return;
                  if (Math.hypot(o.sx - P.x, o.sy - P.y) < 1.0) { partner = o; cont = (end === 'e'); }
                  else if (Math.hypot(o.ex - P.x, o.ey - P.y) < 1.0) { partner = o; cont = (end === 's'); }
                });
                if (!partner) return;
                var ob = bandQuad(partner); if (!ob) return;
                if (Math.abs(b.ux*ob.ux + b.uy*ob.uy) > 0.985) return;   // collinear
                var maxR = (w.th + partner.th) * 2 + 6;
                // Head-to-tail chains pair p-edge with p-edge; head-to-head pair p with q.
                [['p', b.p, cont ? ob.p : ob.q],
                 ['q', b.q, cont ? ob.q : ob.p]].forEach(function(sd){
                  var A = {x: w.sx + b.nx*sd[1], y: w.sy + b.ny*sd[1]};
                  var B = {x: partner.sx + ob.nx*sd[2], y: partner.sy + ob.ny*sd[2]};
                  var I = lineInt(A, {x:b.ux, y:b.uy}, B, {x:ob.ux, y:ob.uy});
                  if (I && Math.hypot(I.x - P.x, I.y - P.y) < maxR) def[end + sd[0]] = I;
                });
              });
              return def;
            }

            function drawWallBand(w, fillEx, fillIn, alpha, all) {
              var b = bandQuad(w); if (!b) return;
              var C = endCorners(w, all, b);
              var cuts = (w.ops || []).map(function(o){ return [o[0]-o[1]/2, o[0]+o[1]/2]; })
                                       .sort(function(a,c){ return a[0]-c[0]; });
              var segs = []; var pos = 0;
              cuts.forEach(function(c){
                if (c[0] - pos > 0.5) segs.push([pos, c[0]]);
                if (c[1] > pos) pos = c[1];
              });
              if (b.len - pos > 0.5) segs.push([pos, b.len]);
              if (!segs.length) segs = [[0, b.len]];
              ctx.globalAlpha = alpha;
              ctx.fillStyle = (w.cat === 'interior') ? fillIn : fillEx;
              ctx.strokeStyle = '#000'; ctx.lineWidth = 0.8;
              segs.forEach(function(sg){
                var a = sg[0], c = sg[1];
                var P1 = {x: w.sx + b.ux*a + b.nx*b.p, y: w.sy + b.uy*a + b.ny*b.p};
                var Q1 = {x: w.sx + b.ux*a + b.nx*b.q, y: w.sy + b.uy*a + b.ny*b.q};
                var P2 = {x: w.sx + b.ux*c + b.nx*b.p, y: w.sy + b.uy*c + b.ny*b.p};
                var Q2 = {x: w.sx + b.ux*c + b.nx*b.q, y: w.sy + b.uy*c + b.ny*b.q};
                if (a <= 0.05) { P1 = C.sp; Q1 = C.sq; }
                if (c >= b.len - 0.05) { P2 = C.ep; Q2 = C.eq; }
                ctx.beginPath();
                ctx.moveTo(sx(P1.x), sy(P1.y));
                ctx.lineTo(sx(P2.x), sy(P2.y));
                ctx.lineTo(sx(Q2.x), sy(Q2.y));
                ctx.lineTo(sx(Q1.x), sy(Q1.y));
                ctx.closePath(); ctx.fill(); ctx.stroke();
              });
              ctx.globalAlpha = 1;
            }

            // ---- door/window plan symbols on the canvas ----
            function wpt(w, b, t, off) {
              return { x: w.sx + b.ux*t + b.nx*off, y: w.sy + b.uy*t + b.ny*off };
            }
            function polyline(pts) {
              ctx.beginPath();
              pts.forEach(function(p, i){ i ? ctx.lineTo(sx(p.x), sy(p.y)) : ctx.moveTo(sx(p.x), sy(p.y)); });
              ctx.stroke();
            }
            function symRect(w, b, xa, xb, oa, ob) {
              polyline([wpt(w,b,xa,oa), wpt(w,b,xb,oa), wpt(w,b,xb,ob), wpt(w,b,xa,ob), wpt(w,b,xa,oa)]);
            }
            var JAMB = 1.5;

            // Per-type window plan symbol (exterior = q side). No glass lines.
            function winUnit(w, b, t, fx1, fx2) {
              var q = b.q, p = b.p, th = p - q, len = fx2 - fx1;
              var e1 = q + th*0.15, e2 = q + th*0.45, i1 = p - th*0.45, i2 = p - th*0.15;
              function blk(cx) { symRect(w, b, cx - 1, cx + 1, q + 1, p - 1); }
              if (/Casement XX/.test(t)) {
                casLeaf(w, b, fx1, fx1 + len/2, q);
                casLeaf(w, b, fx2, fx2 - len/2, q);
              } else if (/Casement/.test(t)) {
                casLeaf(w, b, fx1, fx2, q);
              } else if (/XOX/.test(t)) {
                // minimal slider style (user sketch): dividers + one line per panel
                var cm = (p + q)/2, w3 = len/3, d1 = fx1 + w3, d2 = fx2 - w3;
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7);
                symRect(w, b, d1 - 1, d1 + 1, q + 0.7, p - 0.7);
                symRect(w, b, d2 - 1, d2 + 1, q + 0.7, p - 0.7);
                polyline([wpt(w,b,d1+1,cm - th*0.11), wpt(w,b,d2-1,cm - th*0.11)]);
                polyline([wpt(w,b,fx1+0.5,cm + th*0.11), wpt(w,b,d1-1,cm + th*0.11)]);
                polyline([wpt(w,b,d2+1,cm + th*0.11), wpt(w,b,fx2-0.5,cm + th*0.11)]);
              } else if (/Slider|XO/.test(t)) {
                var cm2 = (p + q)/2, xm = (fx1 + fx2)/2;
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7);
                symRect(w, b, xm - 1, xm + 1, q + 0.7, p - 0.7);
                polyline([wpt(w,b,fx1+0.5,cm2 + th*0.11), wpt(w,b,xm-1,cm2 + th*0.11)]);
                polyline([wpt(w,b,xm+1,cm2 - th*0.11), wpt(w,b,fx2-0.5,cm2 - th*0.11)]);
              } else if (/Hung/.test(t)) {
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, e1, e2);
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, i1, i2);
              } else if (/Garden/.test(t)) {
                var gd = 12;
                symRect(w, b, fx1 + 1, fx2 - 1, q - gd, q);
                symRect(w, b, fx1 + 2, fx2 - 2, q - gd + 1, q - 1);
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, i1, i2);
              } else if (/Arched/.test(t)) {
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7);
                for (var i3 = 0; i3 < 24; i3 += 2) {
                  var t1 = i3/24, t2 = (i3+1)/24;
                  polyline([wpt(w, b, fx1 + len*t1, p - 1 - (th - 2)*Math.sin(Math.PI*t1)),
                            wpt(w, b, fx1 + len*t2, p - 1 - (th - 2)*Math.sin(Math.PI*t2))]);
                }
              } else {
                symRect(w, b, fx1 + 0.5, fx2 - 0.5, q + 0.7, p - 0.7);
              }
            }

            // Casement leaf pivoted ~20deg toward the exterior + thin arc.
            function casLeaf(w, b, hx, lx, q) {
              var len = Math.abs(lx - hx); if (len < 4) return;
              var dir = lx > hx ? 1 : -1, ang = 20*Math.PI/180;
              var lux = b.ux*dir*Math.cos(ang) - b.nx*Math.sin(ang);
              var luy = b.uy*dir*Math.cos(ang) - b.ny*Math.sin(ang);
              var pdx = b.nx*Math.cos(ang) + b.ux*dir*Math.sin(ang);
              var pdy = b.ny*Math.cos(ang) + b.uy*dir*Math.sin(ang);
              var h = wpt(w, b, hx, q);
              var tip = { x: h.x + lux*len, y: h.y + luy*len };
              polyline([h, tip, {x:tip.x+pdx*2, y:tip.y+pdy*2}, {x:h.x+pdx*2, y:h.y+pdy*2}, h]);
              var l = wpt(w, b, lx, q);
              var v0 = {x:l.x-h.x, y:l.y-h.y}, v1 = {x:tip.x-h.x, y:tip.y-h.y};
              var sweep = Math.atan2(v0.x*v1.y - v0.y*v1.x, v0.x*v1.x + v0.y*v1.y);
              var pts = [];
              for (var i4 = 0; i4 <= 10; i4++) {
                var a = sweep*i4/10, ca = Math.cos(a), sa = Math.sin(a);
                pts.push({ x: h.x + v0.x*ca - v0.y*sa, y: h.y + v0.x*sa + v0.y*ca });
              }
              polyline(pts);
            }

            function symJambs(w, b, x1, x2) {
              symRect(w, b, x1, x1 + JAMB, b.q, b.p);
              symRect(w, b, x2 - JAMB, x2, b.q, b.p);
            }
            function symHeader(w, b, x1, x2) {
              symDashed(w, b, x1 + JAMB, x2 - JAMB, b.p - 0.4);
              symDashed(w, b, x1 + JAMB, x2 - JAMB, b.q + 0.4);
            }

            function symArcDoor(w, b, x1, x2, swing, clicked) {
              symJambs(w, b, x1, x2);
              symHeader(w, b, x1, x2);
              symLeaf(w, b, swing === 'right' ? x2 - JAMB : x1 + JAMB,
                      swing === 'right' ? x1 + JAMB : x2 - JAMB, clicked);
            }

            // Leaf as a thin rectangle + arc (Chief-Architect style).
            function symLeaf(w, b, hx, lx, clicked) {
              var ss = clicked >= 0 ? -1 : 1;
              var edge = ss > 0 ? b.p : b.q;
              var len = Math.abs(lx - hx);
              if (len < 4) return;
              var dir = lx > hx ? 1 : -1;
              var ua = Math.min(hx, hx + dir*1.5), ub = Math.max(hx, hx + dir*1.5);
              // leaf rectangle spans [ua..ub] along the wall, edge..edge+ss*len across
              polyline([wpt(w,b,ua,edge), wpt(w,b,ub,edge),
                        wpt(w,b,ub,edge + ss*len), wpt(w,b,ua,edge + ss*len), wpt(w,b,ua,edge)]);
              var h = wpt(w, b, hx, edge), l = wpt(w, b, lx, edge);
              var leafEnd = { x: h.x + b.nx*ss*len, y: h.y + b.ny*ss*len };
              var v0 = { x: l.x - h.x, y: l.y - h.y };
              var crossZ = v0.x*(leafEnd.y - h.y) - v0.y*(leafEnd.x - h.x);
              var sweep = (crossZ >= 0 ? 1 : -1) * Math.PI/2;
              var pts = [];
              for (var i = 0; i <= 12; i++) {
                var a = sweep * i / 12, ca = Math.cos(a), sa = Math.sin(a);
                pts.push({ x: h.x + v0.x*ca - v0.y*sa, y: h.y + v0.x*sa + v0.y*ca });
              }
              polyline(pts);
            }
            function symDashed(w, b, x1, x2, off) {
              var pos = x1;
              while (pos < x2) {
                var e2 = Math.min(pos + 5, x2);
                polyline([wpt(w,b,pos,off), wpt(w,b,e2,off)]);
                pos += 8;
              }
            }
            function drawSyms(w) {
              var b = bandQuad(w); if (!b || !w.syms) return;
              ctx.strokeStyle = '#000'; ctx.lineWidth = 1;
              var cmid = (b.p + b.q) / 2;
              w.syms.forEach(function(s){
                var x1 = Math.max(0, s.t - s.w/2), x2 = Math.min(b.len, s.t + s.w/2);
                if (x2 - x1 < 1) return;
                if (s.kind === 'window') {
                  symJambs(w, b, x1, x2);
                  symRect(w, b, x1 + JAMB, x2 - JAMB, b.q, b.p);
                  winUnit(w, b, s.wtype || '', x1 + JAMB, x2 - JAMB);
                } else if (s.kind === 'door') {
                  symArcDoor(w, b, x1, x2, s.swing, s.clicked);
                } else if (s.kind === 'double') {
                  var xm = (x1 + x2) / 2;
                  symJambs(w, b, x1, x2);
                  symHeader(w, b, x1, x2);
                  symLeaf(w, b, x1 + JAMB, xm, s.clicked);
                  symLeaf(w, b, x2 - JAMB, xm, s.clicked);
                } else if (s.kind === 'sliding') {
                  symJambs(w, b, x1, x2);
                  symHeader(w, b, x1, x2);
                  var sf1 = x1 + JAMB, sf2 = x2 - JAMB, xm2 = (sf1 + sf2) / 2;
                  symRect(w, b, sf1+0.5, xm2+1.5, cmid+0.3, cmid+1.5);
                  symRect(w, b, xm2-1.5, sf2-0.5, cmid-1.5, cmid-0.3);
                } else if (s.kind === 'opening') {
                  // a doorway with no door: jambs and a header line, nothing else
                  symJambs(w, b, x1, x2);
                  symHeader(w, b, x1, x2);
                } else if (s.kind === 'garage') {
                  ctx.lineWidth = 2.5;
                  polyline([wpt(w,b,x1,b.q+0.7), wpt(w,b,x2,b.q+0.7)]);
                  ctx.lineWidth = 1;
                  symDashed(w, b, x1, x2, b.p + 3);
                } else if (s.kind === 'folding') {
                  symJambs(w, b, x1, x2);
                  symHeader(w, b, x1, x2);
                  var ff1 = x1 + JAMB, ff2 = x2 - JAMB;
                  var ss2 = s.clicked >= 0 ? -1 : 1;
                  var edge2 = ss2 > 0 ? b.p : b.q;
                  var nPan = 4;
                  var amp = (ff2 - ff1) / nPan;
                  var vs = [];
                  for (var i = 0; i <= nPan; i++) {
                    vs.push(wpt(w, b, ff1 + (ff2 - ff1) * i / nPan,
                                (i % 2 === 1) ? edge2 + ss2*amp : edge2));
                  }
                  for (var iL = 0; iL < nPan; iL++) {   // each leaf = thin rectangle
                    var A = vs[iL], B = vs[iL+1];
                    var lx2 = B.x - A.x, ly2 = B.y - A.y;
                    var ll = Math.hypot(lx2, ly2); if (ll < 1) continue;
                    var px2 = -ly2/ll*1.5, py2 = lx2/ll*1.5;
                    polyline([A, B, {x:B.x+px2, y:B.y+py2}, {x:A.x+px2, y:A.y+py2}, A]);
                  }
                } else if (s.kind === 'pocket') {
                  symJambs(w, b, x1, x2);
                  symHeader(w, b, x1, x2);
                  var pf1 = x1 + JAMB, pf2 = x2 - JAMB, xm3 = (pf1 + pf2) / 2;
                  symRect(w, b, pf1, xm3, cmid-0.6, cmid+0.6);
                  symDashed(w, b, xm3, pf2, cmid);
                }
              });
            }

            // Wall dimensions (2026-08-01): the two faces are measured from the
            // REAL mitered corners and each number is printed hard against the
            // face it belongs to - so where it sits tells you what it measures.
            // Outside is the side facing away from the middle of the drawing,
            // the same rule Move sideways uses.
            // Which wall dimensions to show: both / outside only / inside only
            // / none. A view setting, so it lives in the editor only.
            var dimMode = 'both';
            function setDimMode(m) {
              dimMode = m;
              ['out', 'in', 'both', 'none'].forEach(function(k) {
                var el = document.getElementById('dm_' + k);
                if (el) el.className = (k === m) ? 'on' : '';
              });
              var names = { out:'חוץ', in:'פנים', both:'כל המידות', none:'ללא' };
              var h = document.getElementById('dimWhich');
              if (h) h.textContent = names[m] || '';
              draw();
            }

            // A measurement always reads ALONG the thing it measures - a vertical
            // wall gets vertical numbers. Canvas y runs the other way from model
            // y, so the angle is negated, then folded so text is never upside
            // down.
            function textAt(txt, mx2, my2, ang, font, col) {
              var a = -ang;
              while (a > Math.PI / 2 + 0.001) a -= Math.PI;
              while (a < -Math.PI / 2 - 0.001) a += Math.PI;
              ctx.save();
              ctx.translate(sx(mx2), sy(my2));
              ctx.rotate(a);
              ctx.font = font;
              ctx.textAlign = 'center';
              var tw3 = ctx.measureText(txt).width + 6;
              ctx.fillStyle = 'rgba(255,255,255,0.82)';
              ctx.fillRect(-tw3 / 2, -8, tw3, 13);
              ctx.fillStyle = col;
              ctx.fillText(txt, 0, 3);
              ctx.restore();
              ctx.textAlign = 'left';
            }

            // Lengths on the free shapes too, not just walls: every straight
            // side gets its own number, a circle gets its diameter.
            function drawShapeDims() {
              if (dimMode === 'none') return;
              function one(sk) {
                var f = sk.pts;
                if (!f || f.length < 4) return;
                var shp = sk.shape || 'line';
                if (shp === 'arc') return;                 // a curve has no one length
                if (shp === 'circle') {
                  var xs2 = [], ys2 = [];
                  for (var k = 0; k + 1 < f.length; k += 2) { xs2.push(f[k]); ys2.push(f[k + 1]); }
                  var dia = Math.max(Math.max.apply(null, xs2) - Math.min.apply(null, xs2),
                                     Math.max.apply(null, ys2) - Math.min.apply(null, ys2));
                  if (dia < 1) return;
                  var cc = polyCentroid(f);
                  textAt('⌀ ' + fmtLen(dia), cc.x, cc.y - 8 / scale, 0, '11px Arial', '#7a5c33');
                  return;
                }
                var n = f.length / 2;
                var m = sk.closed ? n : n - 1;
                for (var i = 0; i < m; i++) {
                  var j = (i + 1) % n;
                  var ax = f[i * 2], ay = f[i * 2 + 1], bx = f[j * 2], by = f[j * 2 + 1];
                  var L = Math.hypot(bx - ax, by - ay);
                  if (L < 6) continue;
                  var ux2 = (bx - ax) / L, uy2 = (by - ay) / L;
                  var off = 7 / scale;                     // sit just off the line
                  textAt(fmtLen(L), (ax + bx) / 2 - uy2 * off, (ay + by) / 2 + ux2 * off,
                         Math.atan2(by - ay, bx - ax), '11px Arial', '#7a5c33');
                }
              }
              sketches.forEach(one);
              pendingSketches.forEach(one);
            }

            function dimLabel(w, color, all) {
              if (dimMode === 'none') return;
              var b = bandQuad(w); if (!b) return;
              var C = endCorners(w, all || walls.concat(pending), b);
              var outSign = outwardSign(w, b);
              // p edge sits at +n, q edge at -n, so outSign picks which is outer
              var pOuter = outSign > 0;
              // p is always the upper edge and q the lower, so each label steps
              // AWAY from the band on its own side - never both to one side.
              var faces = [
                { a: C.sp, z: C.ep, push: 6, outer: pOuter },
                { a: C.sq, z: C.eq, push: -6, outer: !pOuter }
              ];
              var wallAng = Math.atan2(b.uy, b.ux);
              var pt = function(along, off) {
                return { x: w.sx + b.ux * along + b.nx * off,
                         y: w.sy + b.uy * along + b.ny * off };
              };
              var line = function(p1, p2, col, wid) {
                ctx.strokeStyle = col; ctx.lineWidth = wid || 1;
                ctx.beginPath();
                ctx.moveTo(sx(p1.x), sy(p1.y));
                ctx.lineTo(sx(p2.x), sy(p2.y));
                ctx.stroke();
              };

              // A real dimension string, like the printed plan: a run line with
              // a witness line and a 45 degree tick at every stop, and the
              // length sitting in a gap in the line.
              function dimRun(stops, faceOff, dir, dist, col) {
                if (stops.length < 2) return;
                var runOff = faceOff + dir * dist;
                var a0 = stops[0].v, a1 = stops[stops.length - 1].v;
                line(pt(a0, runOff), pt(a1, runOff), col);
                var sdx = b.ux, sdy = -b.uy;                  // wall direction on screen
                var tdx = (sdx - sdy) * 0.7071, tdy = (sdx + sdy) * 0.7071;
                stops.forEach(function(st) {
                  line(pt(st.v, faceOff + dir * 1.5), pt(st.v, runOff + dir * 3), col);
                  var px3 = sx(pt(st.v, runOff).x), py3 = sy(pt(st.v, runOff).y);
                  ctx.strokeStyle = col; ctx.lineWidth = 1.4;
                  ctx.beginPath();
                  ctx.moveTo(px3 - tdx * 4, py3 - tdy * 4);
                  ctx.lineTo(px3 + tdx * 4, py3 + tdy * 4);
                  ctx.stroke();
                });
                for (var i = 0; i + 1 < stops.length; i++) {
                  var seg = stops[i + 1].v - stops[i].v;
                  if (seg < 6) continue;
                  var mid = (stops[i].v + stops[i + 1].v) / 2;
                  var m = pt(mid, runOff);
                  var isOp = stops[i].op;
                  textAt(fmtLen(seg), m.x, m.y, wallAng,
                         isOp ? 'bold 11px Arial' : '11px Arial',
                         isOp ? '#0a7d4f' : col);
                }
              }

              faces.forEach(function(f) {
                if (dimMode === 'out' && !f.outer) return;
                if (dimMode === 'in' && f.outer) return;
                var len = Math.hypot(f.z.x - f.a.x, f.z.y - f.a.y);
                if (len < 1) return;
                var dir = f.push > 0 ? 1 : -1;
                var faceOff = dir > 0 ? b.p : b.q;
                // the face runs between the real mitered corners, so the numbers
                // always add up to the face length
                var t0 = (f.a.x - w.sx) * b.ux + (f.a.y - w.sy) * b.uy;
                var t1 = (f.z.x - w.sx) * b.ux + (f.z.y - w.sy) * b.uy;
                var col = f.outer ? color : '#8a8f98';

                var chain = [{ v: t0, op: false }];
                if (f.outer) {
                  (w.ops || []).slice().sort(function(o1, o2) { return o1[0] - o2[0]; })
                    .forEach(function(o) {
                      var a = o[0] - o[1] / 2, z = o[0] + o[1] / 2;
                      if (a > t0 + 1 && z < t1 - 1 && z - a > 1) {
                        chain.push({ v: a, op: true });
                        chain.push({ v: z, op: false });
                      }
                    });
                }
                chain.push({ v: t1, op: false });

                if (chain.length > 2) {                 // chain first, overall behind it
                  dimRun(chain, faceOff, dir, 7, col);
                  dimRun([{ v: t0, op: false }, { v: t1, op: false }], faceOff, dir, 20, col);
                } else {
                  dimRun([{ v: t0, op: false }, { v: t1, op: false }], faceOff, dir, 7, col);
                }
              });
            }

            function drawGrid() {
              var stepPx = 12 * scale;
              while (stepPx < 14) stepPx *= 4;
              while (stepPx > 80) stepPx /= 2;
              ctx.strokeStyle = '#eef1f5'; ctx.lineWidth = 1;
              var x0 = ((panX % stepPx) + stepPx) % stepPx;
              for (var x = x0; x < cv.width; x += stepPx) { ctx.beginPath(); ctx.moveTo(x,0); ctx.lineTo(x,cv.height); ctx.stroke(); }
              var y0 = ((((cv.height - panY) % stepPx) + stepPx) % stepPx);
              for (var y = y0; y < cv.height; y += stepPx) { if (y < 0) continue; ctx.beginPath(); ctx.moveTo(0,y); ctx.lineTo(cv.width,y); ctx.stroke(); }
            }

            function draw() {
              ctx.clearRect(0, 0, cv.width, cv.height);
              drawUnderlay();
              drawGrid();
              drawGuides();
              // Outline only - a closed shape is NOT filled unless the user
              // asks for it (house rule, same as the floor hatch).
              sketches.forEach(function(sk) { drawSketch(sk.pts, sk.closed, '#7a5c33', sketchWidth(sk), null, sketchDash(sk)); });
              pendingSketches.forEach(function(sk) { drawSketch(sk.pts, sk.closed, '#2f6bd8', sketchWidth(sk), null, sketchDash(sk)); });
              // Eraser: the piece under the cursor lights up red before it goes.
              if (mode === 'line' && lineTool === 'erase' && erasePick) {
                drawSketch(erasePick.cut, erasePick.closed, '#e0392b', 4.4, null);
              }
              if (curLine && curLine.pts.length) {
                var lf = [];
                curLine.pts.forEach(function(pt) { lf.push(pt.x, pt.y); });
                drawSketch(lf, false, '#2f6bd8', 1.6, null);
                if (mode === 'line' && cursor) {
                  var lastP = curLine.pts[curLine.pts.length - 1];
                  var cp = chainEnd(lastP);
                  // Locked (parallel or Shift) draws magenta, free draws blue -
                  // so the colour itself tells you whether the point is held.
                  var locked = lockedNow;
                  var lcol = locked ? '#c026d3' : '#2f6bd8';
                  if (aimFrom) {          // magnet: reference point -> the locked point
                    ctx.strokeStyle = '#00b8d9'; ctx.lineWidth = 1;
                    ctx.setLineDash([2, 4]);
                    ctx.beginPath();
                    ctx.moveTo(sx(aimFrom.x), sy(aimFrom.y));
                    ctx.lineTo(sx(cp.x), sy(cp.y));
                    ctx.stroke();
                    ctx.setLineDash([]);
                    ctx.beginPath();
                    ctx.arc(sx(aimFrom.x), sy(aimFrom.y), 5, 0, Math.PI * 2);
                    ctx.fillStyle = '#ffffff'; ctx.fill();
                    ctx.strokeStyle = '#00b8d9'; ctx.lineWidth = 2; ctx.stroke();
                  }
                  ctx.strokeStyle = lcol; ctx.lineWidth = locked ? 1.8 : 1;
                  ctx.setLineDash([5, 4]);
                  ctx.beginPath();
                  ctx.moveTo(sx(lastP.x), sy(lastP.y));
                  ctx.lineTo(sx(cp.x), sy(cp.y));
                  ctx.stroke();
                  ctx.setLineDash([]);
                  if (locked) {                      // marker sitting on the locked point
                    ctx.beginPath();
                    ctx.arc(sx(cp.x), sy(cp.y), 5.5, 0, Math.PI * 2);
                    ctx.fillStyle = '#ffffff'; ctx.fill();
                    ctx.strokeStyle = '#c026d3'; ctx.lineWidth = 2.5; ctx.stroke();
                    ctx.fillStyle = '#c026d3'; ctx.font = 'bold 11px Arial'; ctx.textAlign = 'left';
                    ctx.fillText(aimFrom ? 'נעול לנקודה' : (parInd && !(shiftDown && lockDir) ? 'מקביל' : 'נעול'),
                                 sx(cp.x) + 12, sy(cp.y) + 14);
                  }
                  ctx.fillStyle = lcol; ctx.font = 'bold 12px Arial'; ctx.textAlign = 'left';
                  ctx.fillText(fmtLen(Math.hypot(cp.x - lastP.x, cp.y - lastP.y)), sx(cp.x) + 12, sy(cp.y) - 8);
                }
              }
              if (mode === 'line' && cursor && lineTool === 'rect' && circC) {
                drawSketch(flatten(rectPoints(circC, cursor)), true, '#2f6bd8', 1.2, null);
                ctx.fillStyle = '#2f6bd8'; ctx.font = 'bold 12px Arial'; ctx.textAlign = 'left';
                ctx.fillText(fmtLen(Math.abs(cursor.x - circC.x)) + ' x ' + fmtLen(Math.abs(cursor.y - circC.y)),
                             sx(cursor.x) + 12, sy(cursor.y) - 8);
              }
              if (mode === 'line' && cursor && lineTool === 'hex' && circC) {
                var rh2 = parseLen(typed) || Math.hypot(cursor.x - circC.x, cursor.y - circC.y);
                drawSketch(flatten(polyPoints(circC, rh2, polySides,
                                              Math.atan2(cursor.y - circC.y, cursor.x - circC.x))),
                           true, '#2f6bd8', 1.2, null);
                ctx.strokeStyle = '#8a8f98'; ctx.lineWidth = 1.1;
                ctx.setLineDash([7, 5]);
                ctx.beginPath();
                ctx.moveTo(sx(circC.x), sy(circC.y));
                ctx.lineTo(sx(cursor.x), sy(cursor.y));
                ctx.stroke();
                ctx.setLineDash([]);
                ctx.fillStyle = '#2f6bd8'; ctx.font = 'bold 12px Arial'; ctx.textAlign = 'left';
                ctx.fillText(polySides + ' צלעות · R ' + fmtLen(rh2), sx(circC.x) + 10, sy(circC.y) - 8);
              }
              if (mode === 'line' && cursor && lineTool === 'circle' && circC) {
                var rp = parseLen(typed) || Math.hypot(cursor.x - circC.x, cursor.y - circC.y);
                drawSketch(flatten(circlePoints(circC, rp, 48)), true, '#2f6bd8', 1.2, null);
                ctx.fillStyle = '#2f6bd8'; ctx.font = 'bold 12px Arial'; ctx.textAlign = 'left';
                ctx.fillText('R ' + fmtLen(rp) + '  ⌀ ' + fmtLen(rp * 2), sx(circC.x) + 10, sy(circC.y) - 8);
                ctx.strokeStyle = '#8a8f98'; ctx.lineWidth = 1.1;
                ctx.setLineDash([7, 5]);
                ctx.beginPath();
                ctx.moveTo(sx(circC.x), sy(circC.y));
                ctx.lineTo(sx(cursor.x), sy(cursor.y));
                ctx.stroke();
                ctx.setLineDash([]);
              }
              if (mode === 'line' && cursor && lineTool === 'arc' && arcPts.length) {
                var tag2 = function(txt, px2, py2, col) {
                  ctx.font = 'bold 12px Arial';
                  var w4 = ctx.measureText(txt).width + 10;
                  ctx.fillStyle = '#ffffff'; ctx.fillRect(px2 - w4 / 2, py2 - 9, w4, 17);
                  ctx.strokeStyle = col; ctx.lineWidth = 1; ctx.strokeRect(px2 - w4 / 2, py2 - 9, w4, 17);
                  ctx.fillStyle = col; ctx.textAlign = 'center';
                  ctx.fillText(txt, px2, py2 + 4);
                  ctx.textAlign = 'left';
                };
                if (arcPts.length === 1) {
                  // First leg: the chord itself, dashed, with its length.
                  ctx.strokeStyle = '#2f6bd8'; ctx.lineWidth = 1.4;
                  ctx.setLineDash([7, 5]);
                  ctx.beginPath();
                  ctx.moveTo(sx(arcPts[0].x), sy(arcPts[0].y));
                  ctx.lineTo(sx(cursor.x), sy(cursor.y));
                  ctx.stroke();
                  ctx.setLineDash([]);
                  tag2(fmtLen(Math.hypot(cursor.x - arcPts[0].x, cursor.y - arcPts[0].y)),
                       (sx(arcPts[0].x) + sx(cursor.x)) / 2, (sy(arcPts[0].y) + sy(cursor.y)) / 2 - 12, '#2f6bd8');
                } else {
                  var apts = arcPoints(arcPts[0], cursor, arcPts[1], 48);
                  drawSketch(flatten(apts), false, '#2f6bd8', 1.6, null);
                  // Chord (solid) + the bulge line from its midpoint to the apex,
                  // dashed green - the SketchUp arc read-out.
                  ctx.strokeStyle = '#8a8f98'; ctx.lineWidth = 1.2;
                  ctx.beginPath();
                  ctx.moveTo(sx(arcPts[0].x), sy(arcPts[0].y));
                  ctx.lineTo(sx(arcPts[1].x), sy(arcPts[1].y));
                  ctx.stroke();
                  var apex = apts[Math.floor(apts.length / 2)];
                  var midc = { x: (arcPts[0].x + arcPts[1].x) / 2, y: (arcPts[0].y + arcPts[1].y) / 2 };
                  ctx.strokeStyle = '#1a9d55'; ctx.lineWidth = 1.6;
                  ctx.setLineDash([7, 5]);
                  ctx.beginPath();
                  ctx.moveTo(sx(midc.x), sy(midc.y));
                  ctx.lineTo(sx(apex.x), sy(apex.y));
                  ctx.stroke();
                  ctx.setLineDash([]);
                  tag2(fmtLen(Math.hypot(arcPts[1].x - arcPts[0].x, arcPts[1].y - arcPts[0].y)),
                       (sx(arcPts[0].x) + sx(arcPts[1].x)) / 2, (sy(arcPts[0].y) + sy(arcPts[1].y)) / 2 + 20, '#8a8f98');
                  tag2(fmtLen(Math.hypot(apex.x - midc.x, apex.y - midc.y)),
                       (sx(midc.x) + sx(apex.x)) / 2, (sy(midc.y) + sy(apex.y)) / 2, '#1a9d55');
                }
              }
              if (mode === 'line' && lineTool === 'measure' && measA && cursor) {
                var mb = measB || snapPoint(cursor, null);
                ctx.strokeStyle = '#0a7d4f'; ctx.lineWidth = 1.4;
                ctx.setLineDash([6, 4]);
                ctx.beginPath();
                ctx.moveTo(sx(measA.x), sy(measA.y));
                ctx.lineTo(sx(mb.x), sy(mb.y));
                ctx.stroke();
                ctx.setLineDash([]);
                [measA, mb].forEach(function(mp) {
                  ctx.beginPath();
                  ctx.arc(sx(mp.x), sy(mp.y), 4, 0, Math.PI * 2);
                  ctx.fillStyle = '#0a7d4f'; ctx.fill();
                });
                var mtx = (sx(measA.x) + sx(mb.x)) / 2, mty = (sy(measA.y) + sy(mb.y)) / 2;
                var mtxt = fmtLen(Math.hypot(mb.x - measA.x, mb.y - measA.y));
                ctx.font = 'bold 13px Arial';
                var mw2 = ctx.measureText(mtxt).width + 10;
                ctx.fillStyle = '#ffffff'; ctx.fillRect(mtx - mw2 / 2, mty - 20, mw2, 17);
                ctx.strokeStyle = '#0a7d4f'; ctx.lineWidth = 1; ctx.strokeRect(mtx - mw2 / 2, mty - 20, mw2, 17);
                ctx.fillStyle = '#0a7d4f'; ctx.textAlign = 'center';
                ctx.fillText(mtxt, mtx, mty - 7);
                ctx.textAlign = 'left';
              }
              if (mode === 'line') {
                var anch2 = chainAnchor();
                if (shiftDown && lockDir && anch2) {       // locked-direction guide
                  ctx.strokeStyle = '#c026d3'; ctx.lineWidth = 1;
                  ctx.setLineDash([2, 4]);
                  ctx.beginPath();
                  ctx.moveTo(sx(anch2.x - lockDir.x * 2000), sy(anch2.y - lockDir.y * 2000));
                  ctx.lineTo(sx(anch2.x + lockDir.x * 4000), sy(anch2.y + lockDir.y * 4000));
                  ctx.stroke();
                  ctx.setLineDash([]);
                }
                if (parInd && !snapInd) {                  // parallel guide
                  ctx.strokeStyle = '#c026d3'; ctx.lineWidth = 1;
                  ctx.setLineDash([6, 5]);
                  ctx.beginPath();
                  ctx.moveTo(sx(parInd.x - parInd.dx * 3000), sy(parInd.y - parInd.dy * 3000));
                  ctx.lineTo(sx(parInd.x + parInd.dx * 3000), sy(parInd.y + parInd.dy * 3000));
                  ctx.stroke();
                  ctx.setLineDash([]);
                }
                if (snapInd && !lockedNow) {   // ring on the point: green = corner, cyan = midpoint
                  var mcol = snapInd.kind === 'end' ? '#1a9d55' : '#00b8d9';
                  ctx.beginPath();
                  ctx.arc(sx(snapInd.x), sy(snapInd.y), 6, 0, Math.PI * 2);
                  ctx.fillStyle = '#ffffff'; ctx.fill();
                  ctx.strokeStyle = mcol; ctx.lineWidth = 2.5; ctx.stroke();
                }
              }
              var all = walls.concat(pending);
              walls.forEach(function(w){ drawWallBand(w, '#444', '#cfcfcf', 1, all); drawSyms(w); dimLabel(w, '#1a6ee0', all); });
              pending.forEach(function(w){ drawWallBand(w, '#2f6bd8', '#9db8e8', 1, all); dimLabel(w, '#e0392b', all); });
              if (mode === 'wall' && drawing && startPt) {
                var end = currentEnd();
                var w = tempWall(startPt, end);
                drawWallBand(w, '#2f6bd8', '#9db8e8', 0.5, all);
                ctx.strokeStyle = '#1a6ee0'; ctx.lineWidth = 1;
                ctx.setLineDash([5,4]);
                ctx.beginPath(); ctx.moveTo(sx(startPt.x), sy(startPt.y)); ctx.lineTo(sx(end.x), sy(end.y)); ctx.stroke();
                ctx.setLineDash([]);
                var dd = Math.hypot(end.x - startPt.x, end.y - startPt.y);
                ctx.fillStyle = '#1a6ee0'; ctx.font = 'bold 12px Arial'; ctx.textAlign = 'left';
                ctx.fillText(fmtLen(dd), sx(end.x) + 12, sy(end.y) - 8);
                if (shiftDown && lockDir) {   // locked-direction guide line
                  ctx.strokeStyle = '#c026d3'; ctx.lineWidth = 1;
                  ctx.setLineDash([2,4]);
                  ctx.beginPath();
                  ctx.moveTo(sx(startPt.x - lockDir.x*2000), sy(startPt.y - lockDir.y*2000));
                  ctx.lineTo(sx(startPt.x + lockDir.x*4000), sy(startPt.y + lockDir.y*4000));
                  ctx.stroke();
                  ctx.setLineDash([]);
                  if (snapInd) {              // aim line: inference point -> locked wall end
                    ctx.strokeStyle = '#00b8d9'; ctx.lineWidth = 1;
                    ctx.setLineDash([3,3]);
                    ctx.beginPath();
                    ctx.moveTo(sx(snapInd.x), sy(snapInd.y));
                    ctx.lineTo(sx(end.x), sy(end.y));
                    ctx.stroke();
                    ctx.setLineDash([]);
                  }
                }
                if (snapInd) {                // inference point marker
                  ctx.fillStyle = snapInd.kind === 'end' ? '#1a9d55' : '#00b8d9';
                  ctx.beginPath();
                  ctx.arc(sx(snapInd.x), sy(snapInd.y), 5, 0, Math.PI*2);
                  ctx.fill();
                }
              }
              // Same marker while only HOVERING, before the chain has started.
              if (mode === 'wall' && !drawing && snapInd) {
                var hcol = snapInd.kind === 'end' ? '#1a9d55' : '#00b8d9';
                ctx.beginPath();
                ctx.arc(sx(snapInd.x), sy(snapInd.y), 6, 0, Math.PI * 2);
                ctx.fillStyle = '#ffffff'; ctx.fill();
                ctx.strokeStyle = hcol; ctx.lineWidth = 2.5; ctx.stroke();
              }
              if ((mode === 'door' || mode === 'win') && hoverHit) drawGhostOpening();
              dimTags = [];
              if (mode === 'sel') drawSelection();
              // Labels last, so they sit on top and stay clickable.
              drawShapeDims();
              drawRooms();
              drawShapeAreas();
              updateStatus();
            }

            function outlineBand(w, color) {
              var b = bandQuad(w); if (!b) return;
              ctx.strokeStyle = color; ctx.lineWidth = 2.5;
              ctx.beginPath();
              ctx.moveTo(sx(w.sx + b.nx*b.p), sy(w.sy + b.ny*b.p));
              ctx.lineTo(sx(w.ex + b.nx*b.p), sy(w.ey + b.ny*b.p));
              ctx.lineTo(sx(w.ex + b.nx*b.q), sy(w.ey + b.ny*b.q));
              ctx.lineTo(sx(w.sx + b.nx*b.q), sy(w.sy + b.ny*b.q));
              ctx.closePath(); ctx.stroke();
            }

            function outlineOpening(w, s, t, color) {
              var b = bandQuad(w); if (!b) return;
              var x1 = t - s.w/2, x2 = t + s.w/2;
              ctx.strokeStyle = color; ctx.lineWidth = 2.5;
              ctx.beginPath();
              ctx.moveTo(sx(w.sx + b.ux*x1 + b.nx*(b.p+2)), sy(w.sy + b.uy*x1 + b.ny*(b.p+2)));
              ctx.lineTo(sx(w.sx + b.ux*x2 + b.nx*(b.p+2)), sy(w.sy + b.uy*x2 + b.ny*(b.p+2)));
              ctx.lineTo(sx(w.sx + b.ux*x2 + b.nx*(b.q-2)), sy(w.sy + b.uy*x2 + b.ny*(b.q-2)));
              ctx.lineTo(sx(w.sx + b.ux*x1 + b.nx*(b.q-2)), sy(w.sy + b.uy*x1 + b.ny*(b.q-2)));
              ctx.closePath(); ctx.stroke();
            }

            function drawSelection() {
              if (dragWall && dragWall.moved) {   // live ghost of the sideways move
                var g = { sx:dragWall.w.sx + dragWall.b.nx*dragWall.off,
                          sy:dragWall.w.sy + dragWall.b.ny*dragWall.off,
                          ex:dragWall.w.ex + dragWall.b.nx*dragWall.off,
                          ey:dragWall.w.ey + dragWall.b.ny*dragWall.off,
                          th:dragWall.w.th, ha:dragWall.w.ha, cat:dragWall.w.cat, ops:dragWall.w.ops };
                drawWallBand(g, '#2f6bd8', '#9db8e8', 0.6, null);
                outlineBand(g, '#1a9d55');
                var mp = { x:(g.sx + g.ex)/2, y:(g.sy + g.ey)/2 };
                dimTag(sx(mp.x), sy(mp.y), typed ? typed : fmtLen(Math.abs(dragWall.off)), 'size', {});
                return;
              }
              if (dragSym && dragSym.moved) {
                outlineOpening(dragSym.w, dragSym.s, dragSym.curT, dragSym.valid ? '#1a9d55' : '#e0392b');
                return;
              }
              if (ghostOpen && hoverHit && hoverHit.w) {
                outlineOpening(hoverHit.w, { w: ghostOpen.src[0].w }, hoverHit.t, '#1a9d55');
              }
              if (ghostCopy) {
                ghostCopy.src.forEach(function(c) {
                  outlineBand({ sx:c.sx + ghostCopy.ox, sy:c.sy + ghostCopy.oy,
                                ex:c.ex + ghostCopy.ox, ey:c.ey + ghostCopy.oy,
                                th:c.th, ha:c.ha, cat:c.cat }, '#1a9d55');
                });
              }
              if (rotOp) drawRotOp();
              if (moveOp) drawMoveOp();
              if (offOp) drawOffOp();
              if (rubber && rubber.on) drawRubber();
              selList.forEach(function(o) {
                if (o.type === 'sketch') drawSketch(o.sk.pts, o.sk.closed, '#4b89ff', 3.2, null);
              });
              if (selList.length > 1) {      // multi-select: outline only, no dims
                selList.forEach(function(o) {
                  if (o.type === 'sketch') return;   // already outlined above
                  if (o.type === 'wall') outlineBand(o.w, '#4b89ff');
                  else if (o.type === 'pending') { var pw2 = pending[o.i]; if (pw2) outlineBand(pw2, '#4b89ff'); }
                  else outlineOpening(o.w, o.s, o.s.t, '#4b89ff');
                });
                return;
              }
              if (!sel) return;
              if (sel.type === 'sketch') return;
              if (sel.type === 'wall') { outlineBand(sel.w, '#4b89ff'); drawWallDims(sel.w); }
              else if (sel.type === 'pending') {
                var w = pending[sel.i];
                if (w) { outlineBand(w, '#4b89ff'); drawWallDims(w, sel.i); }
              }
              else { outlineOpening(sel.w, sel.s, sel.s.t, '#4b89ff'); drawOpeningDims(sel.w, sel.s); }
            }

            // ---- clickable dimension tags -------------------------------------
            // dimTags collects screen-space boxes; a click on one opens an inline
            // edit that repositions/resizes the opening (or the wall length).
            var dimTags = [];

            function dimTag(px, py, text, kind, data) {
              ctx.font = 'bold 11px Arial';
              var tw = ctx.measureText(text).width + 8;
              var th2 = 15;
              ctx.fillStyle = '#fff';
              ctx.strokeStyle = kind === 'size' ? '#e0392b' : '#1a6ee0';
              ctx.lineWidth = 1;
              ctx.beginPath(); ctx.rect(px - tw/2, py - th2/2, tw, th2); ctx.fill(); ctx.stroke();
              ctx.fillStyle = kind === 'size' ? '#e0392b' : '#1a6ee0';
              ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
              ctx.fillText(text, px, py);
              ctx.textBaseline = 'alphabetic';
              dimTags.push({ x:px - tw/2, y:py - th2/2, w:tw, h:th2, kind:kind, data:data });
            }

            function dimLine(w, b, x1, x2, off) {
              polyline([wpt(w,b,x1,off), wpt(w,b,x2,off)]);
              [x1, x2].forEach(function(x){
                polyline([wpt(w,b,x,off - 2), wpt(w,b,x,off + 2)]);
              });
            }

            function drawOpeningDims(w, s) {
              var b = bandQuad(w); if (!b) return;
              var hw = s.w/2, a = s.t - hw, c = s.t + hw;
              // neighbours on the same wall
              var prev = 0, next = b.len;
              (w.syms || []).forEach(function(o){
                if (o.id === s.id) return;
                var oa = o.t - o.w/2, oc = o.t + o.w/2;
                if (oc <= a && oc > prev) prev = oc;
                if (oa >= c && oa < next) next = oa;
              });
              var off = b.p + 10;
              ctx.strokeStyle = '#1a6ee0'; ctx.lineWidth = 0.9;
              dimLine(w, b, prev, a, off);
              dimLine(w, b, a, c, off);
              dimLine(w, b, c, next, off);
              var p1 = wpt(w, b, (prev + a)/2, off + 6);
              var p2 = wpt(w, b, (a + c)/2, off + 6);
              var p3 = wpt(w, b, (c + next)/2, off + 6);
              if (a - prev > 2) dimTag(sx(p1.x), sy(p1.y), fmtLen(a - prev), 'pos',
                                      { id:s.id, body:s.body, base:prev, hw:hw, wall:w });
              dimTag(sx(p2.x), sy(p2.y), fmtLen(s.w), 'size', { id:s.id, body:s.body, h:s.h });
              if (next - c > 2) dimTag(sx(p3.x), sy(p3.y), fmtLen(next - c), 'posEnd',
                                       { id:s.id, body:s.body, base:next, hw:hw, wall:w });
            }

            function drawWallDims(w, pi) {
              var b = bandQuad(w); if (!b) return;
              var off = b.q - 10;
              ctx.strokeStyle = '#1a6ee0'; ctx.lineWidth = 0.9;
              dimLine(w, b, 0, b.len, off);
              var p = wpt(w, b, b.len/2, off - 6);
              dimTag(sx(p.x), sy(p.y), fmtLen(b.len), 'wallLen',
                     { wall_id:w.id, len:b.len, pi:(pi == null ? null : pi) });
              // green = the end that will move, red = pinned corner
              var mv  = movingEnd === 'end' ? {x:w.ex, y:w.ey} : {x:w.sx, y:w.sy};
              var pin = movingEnd === 'end' ? {x:w.sx, y:w.sy} : {x:w.ex, y:w.ey};
              ctx.fillStyle = '#e0392b';
              ctx.beginPath(); ctx.arc(sx(pin.x), sy(pin.y), 5, 0, Math.PI*2); ctx.fill();
              ctx.fillStyle = '#1a9d55';
              ctx.beginPath(); ctx.arc(sx(mv.x), sy(mv.y), 7, 0, Math.PI*2); ctx.fill();
              // direction arrow out of the moving end
              var dirS = movingEnd === 'end' ? 1 : -1;
              var ax = sx(mv.x) + b.ux*dirS*26, ay = sy(mv.y) - b.uy*dirS*26;
              ctx.strokeStyle = '#1a9d55'; ctx.lineWidth = 2;
              ctx.beginPath(); ctx.moveTo(sx(mv.x), sy(mv.y)); ctx.lineTo(ax, ay); ctx.stroke();
              var ang2 = Math.atan2(ay - sy(mv.y), ax - sx(mv.x));
              ctx.beginPath();
              ctx.moveTo(ax, ay);
              ctx.lineTo(ax - 8*Math.cos(ang2 - 0.4), ay - 8*Math.sin(ang2 - 0.4));
              ctx.moveTo(ax, ay);
              ctx.lineTo(ax - 8*Math.cos(ang2 + 0.4), ay - 8*Math.sin(ang2 + 0.4));
              ctx.stroke();
            }

            // Click near a selected wall's corner to make THAT end the moving one.
            function hitWallEnd(px, py) {
              if (!sel || sel.type !== 'wall') return null;
              var w = sel.w;
              var ds = Math.hypot(sx(w.sx) - px, sy(w.sy) - py);
              var de = Math.hypot(sx(w.ex) - px, sy(w.ey) - py);
              if (ds < 12 && ds <= de) return 'start';
              if (de < 12) return 'end';
              return null;
            }

            function hitDimTag(px, py) {
              for (var i = dimTags.length - 1; i >= 0; i--) {
                var t = dimTags[i];
                if (px >= t.x && px <= t.x + t.w && py >= t.y && py <= t.y + t.h) return t;
              }
              return null;
            }

            function editDimTag(t) {
              if (t.kind === 'room') { editRoomName(t.data); return; }
              if (t.kind === 'skarea') { editShapeAreaName(t.data); return; }
              var cur = '';
              if (t.kind === 'wallLen') cur = fmtLen(t.data.len);
              else if (t.kind === 'size') cur = fmtLen(sel.s.w);
              else cur = '';
              // NOTE: never use backslash escapes inside this heredoc-embedded JS
              // (a single \\' would break the whole script).
              var v = prompt('הקלד מידה חדשה — feet inch, למשל: 3 6', cur);
              if (v === null) return;
              var val = parseLen(v);
              if (!val || val <= 0) return;
              if (t.kind === 'wallLen') {
                if (t.data.pi != null) { setPendingLength(t.data.pi, val); return; }
                if (!t.data.wall_id) { alert('הקיר עוד לא עבר Apply to Model'); return; }
                keepSel = { kind:'wall', id: t.data.wall_id };
                sketchup.set_wall_length(JSON.stringify({ wall_id: t.data.wall_id, len: val, fixed: fixedEndName(), keep: keepCorners }));
              } else if (t.kind === 'size') {
                sketchup.edit_opening_size(JSON.stringify({
                  id: t.data.id, body: t.data.body, width: val, height: 0, header: 0
                }));
              } else if (t.kind === 'pos') {
                sketchup.set_opening_t(JSON.stringify({
                  id: t.data.id, body: t.data.body, t: t.data.base + val + t.data.hw
                }));
              } else if (t.kind === 'posEnd') {
                sketchup.set_opening_t(JSON.stringify({
                  id: t.data.id, body: t.data.body, t: t.data.base - val - t.data.hw
                }));
              }
            }

            function openW() {
              return (mode === 'door' ? parseLen(document.getElementById('dW').value)
                                      : parseLen(document.getElementById('wW').value)) || 24;
            }

            function drawGhostOpening() {
              var h = hoverHit, b = h.b;
              var hw = openW() / 2;
              var ok = (h.t - hw >= 0) && (h.t + hw <= b.len);
              var x1 = h.t - hw, x2 = h.t + hw;
              ctx.strokeStyle = ok ? '#1a9d55' : '#e0392b';
              ctx.lineWidth = 2;
              ctx.beginPath();
              ctx.moveTo(sx(h.w.sx + b.ux*x1 + b.nx*b.p), sy(h.w.sy + b.uy*x1 + b.ny*b.p));
              ctx.lineTo(sx(h.w.sx + b.ux*x2 + b.nx*b.p), sy(h.w.sy + b.uy*x2 + b.ny*b.p));
              ctx.lineTo(sx(h.w.sx + b.ux*x2 + b.nx*b.q), sy(h.w.sy + b.uy*x2 + b.ny*b.q));
              ctx.lineTo(sx(h.w.sx + b.ux*x1 + b.nx*b.q), sy(h.w.sy + b.uy*x1 + b.ny*b.q));
              ctx.closePath(); ctx.stroke();
              hoverHit.ok = ok;
            }

            function hitWall(p) {
              var best = null;
              var tol = 8 / scale;
              walls.forEach(function(w){
                if (!w.id) return;
                var b = bandQuad(w); if (!b) return;
                var dx = p.x - w.sx, dy = p.y - w.sy;
                var tt = dx*b.ux + dy*b.uy;
                var off = dx*b.nx + dy*b.ny;
                if (tt < -2 || tt > b.len + 2) return;
                if (off < b.q - tol || off > b.p + tol) return;
                var mid = (b.p + b.q) / 2;
                var score = Math.abs(off - mid);
                if (!best || score < best.score) {
                  best = { w:w, b:b, t:Math.max(0, Math.min(b.len, tt)), off:off, score:score };
                }
              });
              return best;
            }

            function tempWall(s, e) {
              return { sx:s.x, sy:s.y, ex:e.x, ey:e.y,
                       th: parseLen(document.getElementById('th').value) || 5,
                       ha: mHa(), cat: cat, ops: [] };
            }
            function mHa() { return sideOpt === 'L' ? 'left' : 'right'; }   // preview only

            var snapInd = null;   // last inference point {x, y, kind:'end'|'mid'} for display

            function snapPoint(p, from) {
              snapInd = null;
              var r = 14 / scale;
              var bestEnd = null, bestEndD = r, bestMid = null, bestMidD = r;
              // Sketch corners and line ends snap exactly like wall ends do.
              function eyeSketch(flat) {
                if (!flat) return;
                for (var i8 = 0; i8 + 1 < flat.length; i8 += 2) {
                  var d8 = Math.hypot(flat[i8] - p.x, flat[i8 + 1] - p.y);
                  if (d8 < bestEndD) { bestEnd = { x:flat[i8], y:flat[i8 + 1] }; bestEndD = d8; }
                }
              }
              guides.forEach(function(g) { eyeSketch([g.x1, g.y1, g.x2, g.y2]); });
              sketches.forEach(function(sk) { eyeSketch(sk.pts); });
              pendingSketches.forEach(function(sk) { eyeSketch(sk.pts); });
              if (curLine) {
                var cf = [];
                curLine.pts.forEach(function(pt) { cf.push(pt.x, pt.y); });
                eyeSketch(cf);
              }
              var allW = walls.concat(pending);
              allW.forEach(function(w){
                // The drawn line is only ONE face of the wall. The real
                // corners you point at are the mitered band corners, so every
                // one of them is a snap target - outer as well as inner.
                // endCorners gives the SAME points that get drawn (mitered for
                // pending walls too), so the marker sits exactly on the corner.
                var cand = [{x:w.sx, y:w.sy}, {x:w.ex, y:w.ey}];
                var bq = bandQuad(w);
                var C4 = bq ? endCorners(w, allW, bq) : null;
                if (C4) cand.push(C4.sp, C4.ep, C4.eq, C4.sq);
                cand.forEach(function(c){
                  var d = Math.hypot(c.x - p.x, c.y - p.y);
                  if (d < bestEndD) { bestEnd = c; bestEndD = d; }
                });
                // Midpoint on BOTH faces, not only the drawn one - you need the
                // middle of whichever side you are working from, and on interior
                // walls just the same.
                var mids = [{ x:(w.sx + w.ex) / 2, y:(w.sy + w.ey) / 2 }];
                if (C4) {
                  mids.push({ x:(C4.sp.x + C4.ep.x) / 2, y:(C4.sp.y + C4.ep.y) / 2 });
                  mids.push({ x:(C4.sq.x + C4.eq.x) / 2, y:(C4.sq.y + C4.eq.y) / 2 });
                }
                mids.forEach(function(m) {
                  var dm = Math.hypot(m.x - p.x, m.y - p.y);
                  if (dm < bestMidD) { bestMid = m; bestMidD = dm; }
                });
              });
              if (bestEnd) {
                snapInd = { x:bestEnd.x, y:bestEnd.y, kind:'end' };
                return { x:bestEnd.x, y:bestEnd.y, snapped:true };
              }
              if (bestMid) {
                snapInd = { x:bestMid.x, y:bestMid.y, kind:'mid' };
                return { x:bestMid.x, y:bestMid.y, snapped:true };
              }
              var out = { x:p.x, y:p.y, snapped:false };
              if (from) {
                var dx = p.x - from.x, dy = p.y - from.y;
                var ang = Math.atan2(dy, dx), d = Math.hypot(dx, dy);
                var step = Math.PI / 4;
                var snapAng = Math.round(ang / step) * step;
                if (Math.abs(ang - snapAng) < 0.12) {
                  out.x = from.x + Math.cos(snapAng) * d;
                  out.y = from.y + Math.sin(snapAng) * d;
                }
              }
              // Free movement rounds to 1/2 in; anything that landed on a real
              // point or a typed length is left exactly where it is.
              out.x = Math.round(out.x * 2) / 2; out.y = Math.round(out.y * 2) / 2;
              return out;
            }

            // Capture the direction being drawn the moment Shift goes down
            // (snapped to 45deg when close to an axis) - SketchUp-style lock.
            // ---- parallel inference (2026-07-31) ----------------------------
            // If the segment being drawn is nearly parallel to an existing wall
            // or sketch edge, lock it EXACTLY parallel and show a guide. Point
            // snaps (corner / midpoint) always win over this.
            var parInd = null;      // { x, y, dx, dy } while a parallel lock holds

            function segDirs() {
              var out = [];
              walls.concat(pending).forEach(function(w) {
                var dx = w.ex - w.sx, dy = w.ey - w.sy;
                var d = Math.hypot(dx, dy);
                if (d > 1) out.push({ x: dx / d, y: dy / d });
              });
              function fromFlat(flat) {
                if (!flat) return;
                var n = flat.length / 2;
                for (var i4 = 0; i4 + 1 < n; i4++) {
                  var ax = flat[i4 * 2], ay = flat[i4 * 2 + 1];
                  var bx = flat[(i4 + 1) * 2], by = flat[(i4 + 1) * 2 + 1];
                  var dx2 = bx - ax, dy2 = by - ay;
                  var d2 = Math.hypot(dx2, dy2);
                  if (d2 > 1) out.push({ x: dx2 / d2, y: dy2 / d2 });
                }
              }
              sketches.forEach(function(sk) { fromFlat(sk.pts); });
              pendingSketches.forEach(function(sk) { fromFlat(sk.pts); });
              return out;
            }

            function applyParallel(anch, p) {
              parInd = null;
              var dx = p.x - anch.x, dy = p.y - anch.y;
              var d = Math.hypot(dx, dy);
              if (d < 1) return p;
              var ux = dx / d, uy = dy / d;
              var best = null, bestA = 0.07;      // about 4 degrees
              segDirs().forEach(function(sg) {
                var c4 = Math.abs(ux * sg.x + uy * sg.y);
                if (c4 > 1) c4 = 1;
                var a4 = Math.acos(c4);
                if (a4 < bestA) { bestA = a4; best = sg; }
              });
              if (!best) return p;
              var sgn = (ux * best.x + uy * best.y) >= 0 ? 1 : -1;
              parInd = { x: anch.x, y: anch.y, dx: best.x * sgn, dy: best.y * sgn };
              return { x: anch.x + best.x * sgn * d, y: anch.y + best.y * sgn * d };
            }

            // The point the current chain is growing from - a wall chain start
            // or the last point of the line being drawn.
            function chainAnchor() {
              if (mode === 'line') {
                return (curLine && curLine.pts.length) ? curLine.pts[curLine.pts.length - 1] : null;
              }
              return drawing ? startPt : null;
            }

            function captureLockDir() {
              var anch = chainAnchor();
              if (!anch) { lockDir = null; return; }
              // Shift pressed while a parallel inference is showing locks THAT
              // direction - hover until it goes parallel, hold Shift, then point
              // at any corner and the line runs out opposite it.
              if (parInd) { lockDir = { x: parInd.dx, y: parInd.dy }; return; }
              var dx = cursor.x - anch.x, dy = cursor.y - anch.y;
              var d = Math.hypot(dx, dy);
              if (d < 1) { lockDir = null; return; }
              var ang = Math.atan2(dy, dx);
              var snapAng = Math.round(ang / (Math.PI/4)) * (Math.PI/4);
              if (Math.abs(ang - snapAng) < 0.18) ang = snapAng;
              lockDir = { x: Math.cos(ang), y: Math.sin(ang) };
            }

            // Where the next point lands.
            // With a direction lock (Shift, or a parallel inference) the cursor
            // is FIRST snapped to a reference point - a corner, a wall end, a
            // midpoint - and that point is then projected onto the locked
            // direction. That is the magnet: point at anything and the line
            // runs out to exactly opposite it, still perfectly on the lock.
            var aimFrom = null;     // reference point feeding the projection
            var lockedNow = false;  // a direction lock is currently holding

            function chainEnd(anch) {
              aimFrom = null;
              lockedNow = false;
              if (!anch) return snapPoint(cursor, null);
              var typedLen = parseLen(typed);

              var dir = (shiftDown && lockDir) ? { x: lockDir.x, y: lockDir.y } : null;
              // No 45-degree snap while locked - the lock already fixes the angle.
              var q9 = snapPoint(cursor, dir ? null : anch);

              if (!dir) {
                if (!q9.snapped) {
                  var pq = applyParallel(anch, q9);
                  if (parInd) dir = { x: parInd.dx, y: parInd.dy };
                  q9 = pq;
                } else {
                  parInd = null;
                }
              }

              if (dir) {
                lockedNow = true;
                var basePt = q9.snapped ? q9 : cursor;
                var t9 = (basePt.x - anch.x) * dir.x + (basePt.y - anch.y) * dir.y;
                if (typedLen) t9 = typedLen;
                if (Math.abs(t9) < 0.5) t9 = t9 < 0 ? -0.5 : 0.5;
                var endPt = { x: anch.x + dir.x * t9, y: anch.y + dir.y * t9 };
                if (q9.snapped) aimFrom = { x: q9.x, y: q9.y };
                return endPt;
              }

              if (typedLen) {
                var dx9 = q9.x - anch.x, dy9 = q9.y - anch.y;
                var d9 = Math.hypot(dx9, dy9);
                if (d9 > 0.01) return { x: anch.x + dx9 / d9 * typedLen, y: anch.y + dy9 / d9 * typedLen };
              }
              return q9;
            }

            // An interior wall cannot run past the outside of the building
            // (2026-08-03). While drawing, the end is cut at the first exterior
            // face it reaches, so you can aim roughly and still land exactly on
            // the wall. A TYPED length is an explicit instruction and is never
            // clipped - the same rule the whole editor follows.
            function clampToBoundary(a, bpt) {
              if (!a || cat !== 'interior') return bpt;
              var dx = bpt.x - a.x, dy = bpt.y - a.y;
              var L = Math.hypot(dx, dy);
              if (L < 1) return bpt;
              var best = null;
              var allW = walls.concat(pending);
              allW.forEach(function(w) {
                if ((w.cat || 'exterior') !== 'exterior') return;
                var bq = bandQuad(w); if (!bq) return;
                var C = endCorners(w, allW, bq);
                [[C.sp, C.ep], [C.sq, C.eq], [C.sp, C.sq], [C.ep, C.eq]].forEach(function(sg) {
                  var t = segCross(a, bpt, sg[0], sg[1]);
                  if (t === null) return;
                  var d = t * L;
                  if (d < 1) return;               // ignore the face we started on
                  if (best === null || d < best) best = d;
                });
              });
              if (best === null) return bpt;
              return { x: a.x + dx / L * best, y: a.y + dy / L * best };
            }

            function currentEnd() {
              var typedLen = parseLen(typed);
              if (shiftDown && lockDir && startPt) {
                // Locked direction: any point (incl. endpoint snaps) projects
                // onto the locked ray; typed length wins.
                var p0 = snapPoint(cursor, null);
                var t = (p0.x - startPt.x)*lockDir.x + (p0.y - startPt.y)*lockDir.y;
                if (typedLen) t = typedLen;
                if (t < 1) t = 1;
                var lp2 = { x: startPt.x + lockDir.x*t, y: startPt.y + lockDir.y*t };
                return typedLen ? lp2 : clampToBoundary(startPt, lp2);
              }
              var p = snapPoint(cursor, startPt);
              if (typedLen && startPt) {
                var dx = p.x - startPt.x, dy = p.y - startPt.y;
                var d = Math.hypot(dx, dy);
                if (d > 0.01) return { x: startPt.x + dx/d*typedLen, y: startPt.y + dy/d*typedLen };
              }
              return clampToBoundary(startPt, p);
            }

            function commitSegment() {
              var end = currentEnd();
              if (!startPt || Math.hypot(end.x - startPt.x, end.y - startPt.y) < 1) return;
              var w = tempWall(startPt, end);
              w.h = parseLen(document.getElementById('hh').value) || 96;
              w.lib = curWallLib;
              w.anchor = 'bottom-left';
              if (sideOpt === 'R') {   // flip direction so the band side matches, keep bottom-left
                var t2 = { x: w.sx, y: w.sy };
                w.sx = w.ex; w.sy = w.ey; w.ex = t2.x; w.ey = t2.y;
                w.ha = 'left';
              }
              if (!mergeCollinear(w)) pending.push(w);
              startPt = end; typed = ''; updateVcb(); draw();
            }

            // A wall drawn as an exact continuation of a pending wall (collinear,
            // sharing an endpoint, same thickness/category) EXTENDS it instead of
            // creating a second wall - no seam, one wall.
            function mergeCollinear(w) {
              var dx = w.ex - w.sx, dy = w.ey - w.sy;
              var len = Math.hypot(dx, dy); if (len < 0.5) return false;
              var ux = dx/len, uy = dy/len;
              for (var i5 = 0; i5 < pending.length; i5++) {
                var p = pending[i5];
                if (p.th !== w.th || p.cat !== w.cat) continue;
                var pdx = p.ex - p.sx, pdy = p.ey - p.sy;
                var pl = Math.hypot(pdx, pdy); if (pl < 0.5) continue;
                var pux = pdx/pl, puy = pdy/pl;
                var dot = pux*ux + puy*uy;
                if (Math.abs(dot) < 0.9995) continue;
                if (dot > 0 && Math.hypot(p.ex - w.sx, p.ey - w.sy) < 0.6) { p.ex = w.ex; p.ey = w.ey; return true; }
                if (dot > 0 && Math.hypot(p.sx - w.ex, p.sy - w.ey) < 0.6) { p.sx = w.sx; p.sy = w.sy; return true; }
                if (dot < 0 && Math.hypot(p.sx - w.sx, p.sy - w.sy) < 0.6) { p.sx = w.ex; p.sy = w.ey; return true; }
                if (dot < 0 && Math.hypot(p.ex - w.ex, p.ey - w.ey) < 0.6) { p.ex = w.sx; p.ey = w.sy; return true; }
              }
              return false;
            }

            function endChain() {
              arcPts = []; circC = null; measA = null; measB = null;
              if (curLine) finishLine(false);
              drawing = false; startPt = null; typed = ''; updateVcb(); draw();
            }
            function updateVcb() { document.getElementById('vcb').innerHTML = typed ? typed : '&nbsp;'; }

            function updateStatus() {
              schedulePendingRooms();   // only fires when the blue walls changed
              document.getElementById('status').innerHTML =
                'Model walls: ' + walls.length + '<br>Pending here: <b>' + pending.length + '</b>' +
                (pendingSketches.length ? '<br>Shapes pending: <b>' + pendingSketches.length + '</b>' : '') +
                (pending.length || pendingSketches.length
                  ? '<br><span style="color:#e0392b">Not applied yet</span>'
                  : '<br><span class="okmsg">All applied</span>');
            }

            // ---- events ----
            cv.addEventListener('mousedown', function(ev) {
              evCount.md++; updateDbg();
              if (ev.button === 1) { panning = true; panFrom = {x:ev.offsetX, y:ev.offsetY}; ev.preventDefault(); return; }
              if (ev.button === 2) { endChain(); return; }
              if (ev.button !== 0) return;
              var p = {x:mx(ev.offsetX), y:my(ev.offsetY)};
              if (calib) { cursor = p; calibClick(p); return; }
              if (rotOp) {                       // centre, then zero angle, then turn
                cursor = p;
                if (!rotOp.c) rotCentre(p);
                else if (rotOp.base === null) rotSetBase(p);
                else rotCommit();
                return;
              }
              if (moveOp) {                      // 1st click grabs, 2nd click drops
                cursor = p;
                if (!moveOp.grab) moveGrab(p); else moveCommit();
                return;
              }
              if (offOp) {                       // 1st click picks the outline, 2nd sets the distance
                cursor = p;
                if (!offOp.start) offStart(p); else { offMove(); offCommit(); }
                return;
              }
              if (guideMode) { cursor = p; guideClick(snapPoint(p, null)); return; }
              if (mode === 'sel') {
                if (ghostCopy) { placeGhostCopy(); return; }
                if (ghostOpen) { placeGhostOpen(p); return; }
                var he = hitWallEnd(ev.offsetX, ev.offsetY);  // click a corner = choose moving end
                if (he) { setMovingEnd(he); return; }
                var dt = hitDimTag(ev.offsetX, ev.offsetY);   // click a dimension = edit it
                if (dt) { editDimTag(dt); return; }
                var hk = hitSketch(p);
                if (hk && !hitOpening(p) && !hitWall(p)) {
                  var mates = groupMates(hk);
                  if (ev.shiftKey) { mates.forEach(function(mm) { toggleSel(mm); }); }
                  else if (mates.length > 1) { selList = mates; sel = mates[mates.length - 1]; }
                  else { setSel(hk); }
                  dragSym = null;
                  updateSelPanel(); draw();
                  return;
                }
                var ho = hitOpening(p);
                if (ho) {
                  var oSel = { type:'sym', w:ho.w, s:ho.s };
                  if (ev.shiftKey) { toggleSel(oSel); updateSelPanel(); draw(); return; }
                  setSel(oSel);
                  dragSym = { w:ho.w, s:ho.s, b:ho.b, startT:ho.s.t, curT:ho.s.t,
                              sxy:{x:ev.offsetX, y:ev.offsetY}, valid:true, moved:false };
                } else {
                  var hw = hitWall(p);
                  if (hw) {
                    var wSel = { type:'wall', w:hw.w };
                    if (ev.shiftKey) { toggleSel(wSel); updateSelPanel(); draw(); return; }
                    setSel(wSel);
                    dragWall = { w:hw.w, b:hw.b, from:{x:p.x, y:p.y},
                                 sxy:{x:ev.offsetX, y:ev.offsetY}, off:0, moved:false };
                  } else {
                    var pi = hitPending(p);
                    var pSel = pi >= 0 ? { type:'pending', i:pi } : null;
                    if (ev.shiftKey) {
                      if (pSel) toggleSel(pSel);
                      updateSelPanel(); draw(); return;
                    }
                    setSel(pSel);
                    if (pi >= 0) {   // pending (blue) walls drag too
                      var pw0 = pending[pi];
                      dragWall = { w:pw0, b:bandQuad(pw0), pi:pi, from:{x:p.x, y:p.y},
                                   sxy:{x:ev.offsetX, y:ev.offsetY}, off:0, moved:false };
                    } else if (underImg && !underLocked) {   // move the background
                      dragUnder = { fx:p.x - underX, fy:p.y - underY };
                    } else {         // empty space -> rubber-band selection
                      rubber = { x0:p.x, y0:p.y, x1:p.x, y1:p.y,
                                 sx:ev.offsetX, sy:ev.offsetY, on:false };
                    }
                  }
                  dragSym = null;
                }
                updateSelPanel(); draw();
                return;
              }
              if (mode === 'line') {
                cursor = { x:p.x, y:p.y };
                if (lineTool === 'erase') { erasePick = eraseFind(p); eraseApply(); return; }
                var lp = (lineTool === 'line' && curLine) ? chainEnd(chainAnchor()) : snapPoint(p, null);
                if (lineToolClick(lp)) { draw(); return; }
                addLinePoint(lp);
                typed = ''; updateVcb();
                return;
              }
              if (mode === 'door' || mode === 'win') {
                hoverHit = hitWall(p);
                draw();
                if (!hoverHit) return;
                if (!hoverHit.ok) return;
                if (mode === 'door') {
                  sketchup.place_door(JSON.stringify({
                    wall_id: hoverHit.w.id, px: p.x, py: p.y,
                    category: doorCat,
                    door_type: document.getElementById('dType').value,
                    width: parseLen(document.getElementById('dW').value) || 32,
                    height: parseLen(document.getElementById('dH').value) || 80,
                    swing: doorSwing
                  }));
                } else {
                  sketchup.place_window(JSON.stringify({
                    wall_id: hoverHit.w.id, px: p.x, py: p.y,
                    window_type: document.getElementById('wType').value,
                    width: parseLen(document.getElementById('wW').value) || 24,
                    height: parseLen(document.getElementById('wH').value) || 48,
                    header: parseLen(document.getElementById('wHead').value) || 80
                  }));
                }
                return;
              }
              var ps = snapPoint(p, drawing ? startPt : null);
              if (!drawing) { drawing = true; startPt = ps; }
              else commitSegment();
            });
            // One movement handler in CANVAS pixel coords, driven by both the
            // canvas and the window (so a drag survives the cursor leaving the
            // canvas — that was why dragging felt dead).
            var evCount = { md:0, mm:0, mu:0 };
            function updateDbg() {
              var d = document.getElementById('dbg');
              if (d) d.textContent = 'md:' + evCount.md + ' mm:' + evCount.mm + ' mu:' + evCount.mu +
                                     (dragWall ? ' DRAG-WALL ' + dragWall.off.toFixed(2) + '"' : '') +
                                     (dragSym ? ' DRAG-OPENING' : '');
            }

            function handleMove(px, py) {
              evCount.mm++; updateDbg();
              if (dragUnder) {
                underX = mx(px) - dragUnder.fx;
                underY = my(py) - dragUnder.fy;
                draw();
                return;
              }
              if (calib) { cursor = { x:mx(px), y:my(py) }; draw(); return; }
              if (rotOp) {
                cursor = { x:mx(px), y:my(py) };
                if (!rotOp.c || rotOp.base === null) { snapPoint(cursor, null); draw(); }
                else rotMove();
                return;
              }
              if (moveOp) {
                cursor = { x:mx(px), y:my(py) };
                // Before the grab: still run the inference so the point you are
                // about to grab lights up green under the cursor.
                if (!moveOp.grab) { snapPoint(cursor, null); draw(); } else moveMove();
                return;
              }
              if (offOp) {
                cursor = { x:mx(px), y:my(py) };
                if (!offOp.start) { snapPoint(cursor, null); draw(); } else offMove();
                return;
              }
              if (guideMode) { cursor = { x:mx(px), y:my(py) }; draw(); return; }
              if (ghostOpen) {
                cursor = { x:mx(px), y:my(py) };
                hoverHit = hitWall(cursor);
                draw();
                return;
              }
              if (ghostCopy) {
                var gp = { x:mx(px), y:my(py) };
                ghostCopy.ox = gp.x - ghostCopy.from.x;
                ghostCopy.oy = gp.y - ghostCopy.from.y;
                draw();
                return;
              }
              if (rubber) {
                rubber.x1 = mx(px); rubber.y1 = my(py);
                if (!rubber.on && (Math.abs(px - rubber.sx) > 4 || Math.abs(py - rubber.sy) > 4)) rubber.on = true;
                draw();
                return;
              }
              if (panning) {
                panX += px - panFrom.x; panY -= py - panFrom.y;
                panFrom = {x:px, y:py}; draw(); return;
              }
              cursor = {x:mx(px), y:my(py)};
              if (mode === 'sel' && dragWall) {
                var sd = Math.hypot(px - dragWall.sxy.x, py - dragWall.sxy.y);
                if (sd < 4 && !dragWall.moved) return;   // plain click still selects
                dragWall.moved = true;
                var b3 = dragWall.b;
                var o = (cursor.x - dragWall.from.x)*b3.nx + (cursor.y - dragWall.from.y)*b3.ny;
                dragWall.off = Math.round(o * 4) / 4;   // 1/4" steps
                draw();
                return;
              }
              if (mode === 'sel' && dragSym) {
                var sd2 = Math.hypot(px - dragSym.sxy.x, py - dragSym.sxy.y);
                if (sd2 < 4 && !dragSym.moved) return;
                dragSym.moved = true;
                var w = dragSym.w, b = dragSym.b;
                var tt = (cursor.x - w.sx)*b.ux + (cursor.y - w.sy)*b.uy;
                var hw2 = dragSym.s.w / 2;
                tt = Math.max(hw2, Math.min(b.len - hw2, tt));
                dragSym.curT = tt;
                dragSym.valid = true;
                draw();
                return;
              }
              if (mode === 'line') {
                if (lineTool === 'erase') { erasePick = eraseFind(cursor); draw(); return; }
                // Recompute the inference every move so the marker shows BEFORE
                // the first click too - otherwise a corner snap is invisible.
                if (curLine && curLine.pts.length) chainEnd(chainAnchor());
                else snapPoint(cursor, null);
                draw();
                return;
              }
              if (mode === 'door' || mode === 'win') { hoverHit = hitWall(cursor); draw(); return; }
              // Wall mode BEFORE the first click: work out the inference now, so
              // the green corner marker shows while you are still aiming - it
              // used to appear only once a wall was already started.
              if (mode === 'wall' && !drawing) { snapPoint(cursor, null); draw(); return; }
              if (drawing) draw();
            }

            cv.addEventListener('mousemove', function(ev) {
              handleMove(ev.offsetX, ev.offsetY);
            });
            // Pointer events + capture: some SketchUp/CEF builds stop sending
            // mousemove once a button is held, which killed dragging.
            cv.addEventListener('pointerdown', function(ev) {
              try { cv.setPointerCapture(ev.pointerId); } catch (e) {}
            });
            cv.addEventListener('pointermove', function(ev) {
              if (!dragWall && !dragSym && !panning && !rubber && !dragUnder) return;
              var r = cv.getBoundingClientRect();
              handleMove(ev.clientX - r.left, ev.clientY - r.top);
            });
            cv.addEventListener('pointerup', function(ev) {
              try { cv.releasePointerCapture(ev.pointerId); } catch (e) {}
              finishDrag();
            });
            window.addEventListener('mousemove', function(ev) {
              if (!dragWall && !dragSym && !panning && !rubber && !dragUnder) return;
              var r = cv.getBoundingClientRect();
              handleMove(ev.clientX - r.left, ev.clientY - r.top);
            });
            window.addEventListener('mouseup', function() { finishDrag(); });

            function finishDrag() {
              evCount.mu++; updateDbg();
              panning = false;
              if (dragUnder) { dragUnder = null; saveUnderlay(); return; }
              if (rubber) {
                var picked = rubber.on ? rubberPick() : [];
                rubber = null;
                if (picked.length) { selList = picked; sel = picked[picked.length - 1]; }
                updateSelPanel(); draw();
                return;
              }
              if (mode === 'sel' && dragWall) {
                if (dragWall.moved && Math.abs(dragWall.off) >= 0.25) {
                  if (dragWall.pi != null) {          // not applied yet -> local move
                    movePendingWall(dragWall.pi, dragWall.off);
                  } else {
                    // our n is the LEFT perpendicular; Ruby expects RIGHT (outward)
                    keepSel = { kind:'wall', id: dragWall.w.id };
                    sketchup.move_wall(JSON.stringify({ wall_id: dragWall.w.id, dist: -dragWall.off, keep: keepCorners }));
                  }
                }
                dragWall = null;
                draw();
                return;
              }
              if (mode === 'sel' && dragSym) {
                var delta = dragSym.curT - dragSym.startT;
                if (dragSym.moved && Math.abs(delta) > 0.25) {
                  keepSel = { kind:'sym', id: dragSym.s.id };
                  sketchup.move_opening(JSON.stringify({ id: dragSym.s.id, body: dragSym.s.body, delta: delta }));
                }
                dragSym = null;
                draw();
              }
            }
            cv.addEventListener('contextmenu', function(ev) { ev.preventDefault(); });
            cv.addEventListener('wheel', function(ev) {
              ev.preventDefault();
              var f = ev.deltaY < 0 ? 1.15 : 1/1.15;
              var mxp = mx(ev.offsetX), myp = my(ev.offsetY);
              scale = Math.max(0.15, Math.min(12, scale * f));
              panX = ev.offsetX - mxp * scale;
              panY = (cv.height - ev.offsetY) - myp * scale;
              draw();
            }, { passive:false });

            window.addEventListener('keyup', function(ev) {
              if (ev.key === 'Shift') { shiftDown = false; lockDir = null; if (drawing || curLine) draw(); }
            });
            window.addEventListener('keydown', function(ev) {
              if (ev.key === 'Shift') {
                if (!shiftDown) { shiftDown = true; captureLockDir(); }
                if (rotOp) { rotMove(); return; }
                if (moveOp) { moveMove(); return; }
                if (drawing || curLine) draw();
                return;
              }
              if (ev.target.tagName === 'INPUT' || ev.target.tagName === 'SELECT') return;
              if (moveOp) {                      // typing an exact distance
                if (ev.key === 'Enter') {
                  var mv2 = parseLen(typed);
                  var mL = Math.hypot(moveOp.dx, moveOp.dy);
                  if (mv2 && mv2 > 0 && mL > 0.001) {
                    moveApply(moveOp.dx / mL * mv2, moveOp.dy / mL * mv2);
                  }
                  typed = ''; updateVcb();
                  if (moveOp.grab) moveCommit();
                  ev.preventDefault();
                  return;
                }
                if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); ev.preventDefault(); return; }
                if (/^[0-9.'" -]$/.test(ev.key)) { typed += ev.key; updateVcb(); ev.preventDefault(); return; }
              }
              if (offOp) {                       // typing an exact offset
                if (ev.key === 'Enter') {
                  var ov2 = parseLen(typed);
                  if (ov2 && ov2 > 0.05 && offOp.start) offBuild(ov2, offOp.sgn || 1);
                  typed = ''; updateVcb();
                  if (offOp.start) offCommit();
                  ev.preventDefault();
                  return;
                }
                if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); ev.preventDefault(); return; }
                if (/^[0-9.'" -]$/.test(ev.key)) { typed += ev.key; updateVcb(); ev.preventDefault(); return; }
              }
              if (rotOp) {                       // typing an exact angle
                if (ev.key === 'Enter') {
                  var av2 = parseFloat(typed);
                  if (isFinite(av2) && rotOp.base !== null) rotApply(av2 * Math.PI / 180);
                  typed = ''; updateVcb();
                  if (rotOp.base !== null) rotCommit();
                  ev.preventDefault();
                  return;
                }
                if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); ev.preventDefault(); return; }
                if (/^[0-9.-]$/.test(ev.key)) { typed += ev.key; updateVcb(); ev.preventDefault(); return; }
              }
              if (ev.key === 'Escape') {
                if (guideMode) { toggleGuideMode(); return; }
                if (rotOp) { rotCancel(); return; }
                if (moveOp) { moveCancel(); return; }
                if (offOp) { offCancel(); return; }
                if (ghostCopy || ghostOpen) { ghostCopy = null; ghostOpen = null; setStatusHint(null); draw(); return; }
                endChain();
                if (mode === 'sel') { setSel(null); rubber = null; dragSym = null; updateSelPanel(); draw(); }
                return;
              }
              // While dragging a wall / opening you can TYPE the exact amount
              // (SketchUp-style): digits go to the VCB, Enter applies.
              if (mode === 'sel' && (dragWall || dragSym)) {
                if (ev.key === 'Enter') { applyTypedDrag(); ev.preventDefault(); return; }
                if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); ev.preventDefault(); return; }
                if (/^[0-9.'" -]$/.test(ev.key)) { typed += ev.key; updateVcb(); ev.preventDefault(); return; }
              }
              if (mode === 'sel' && (ev.key === 'Delete' || ev.key === 'Backspace')) {
                deleteSelected(); ev.preventDefault(); return;
              }
              if (mode === 'line') {
                if (ev.key === 'Enter') {
                  if (lineTool === 'rect' && circC && typed) {
                    // SketchUp style: "12,8" / "12;8" / "12x8" = width, height.
                    // A single number makes a square. The rectangle grows into
                    // the quadrant the cursor is currently in.
                    var parts = typed.split(/[,;x]/);
                    var w6 = parseLen(parts[0]);
                    var h6 = parts.length > 1 ? parseLen(parts[1]) : w6;
                    if (w6 && h6 && w6 > 0.05 && h6 > 0.05) {
                      var sxn = (cursor.x - circC.x) < 0 ? -1 : 1;
                      var syn = (cursor.y - circC.y) < 0 ? -1 : 1;
                      pushShape(rectPoints(circC, { x: circC.x + w6 * sxn, y: circC.y + h6 * syn }),
                                true, 'rect');
                      circC = null;
                    }
                    typed = ''; updateVcb(); draw();
                    return;
                  }
                  if (lineTool === 'arc' && typed && arcPts.length) {
                    var av = parseLen(typed);
                    if (av && av > 0.05) {
                      if (arcPts.length === 1) {
                        // typed CHORD length, along the current cursor direction
                        var d5 = Math.hypot(cursor.x - arcPts[0].x, cursor.y - arcPts[0].y);
                        if (d5 > 0.01) {
                          arcPts.push({ x: arcPts[0].x + (cursor.x - arcPts[0].x) / d5 * av,
                                        y: arcPts[0].y + (cursor.y - arcPts[0].y) / d5 * av });
                        }
                      } else {
                        // typed BULGE height, on whichever side the cursor is
                        var mx5 = (arcPts[0].x + arcPts[1].x) / 2;
                        var my5 = (arcPts[0].y + arcPts[1].y) / 2;
                        var cx5 = arcPts[1].x - arcPts[0].x, cy5 = arcPts[1].y - arcPts[0].y;
                        var cl5 = Math.hypot(cx5, cy5);
                        if (cl5 > 0.01) {
                          var nx5 = -cy5 / cl5, ny5 = cx5 / cl5;
                          var side = ((cursor.x - mx5) * nx5 + (cursor.y - my5) * ny5) >= 0 ? 1 : -1;
                          pushShape(arcPoints(arcPts[0],
                                              { x: mx5 + nx5 * av * side, y: my5 + ny5 * av * side },
                                              arcPts[1], 48), false, 'arc');
                          arcPts = [];
                        }
                      }
                    }
                    typed = ''; updateVcb(); draw();
                    return;
                  }
                  if (lineTool === 'circle' && circC && typed) {
                    pushShape(circlePoints(circC, parseLen(typed), 64), true, 'circle');
                    circC = null; typed = ''; updateVcb();
                    return;
                  }
                  if (lineTool === 'hex' && circC && typed) {
                    var rr2 = parseLen(typed);
                    if (rr2 && rr2 > 0.05) {
                      var ang2 = cursor ? Math.atan2(cursor.y - circC.y, cursor.x - circC.x) : 0;
                      pushShape(polyPoints(circC, rr2, polySides, ang2), true, 'poly');
                      circC = null;
                    }
                    typed = ''; updateVcb(); draw();
                    return;
                  }
                  if (curLine && typed) { addLinePoint(chainEnd(chainAnchor())); typed = ''; updateVcb(); }
                  return;
                }
                if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); draw(); ev.preventDefault(); return; }
                // ev.code is the PHYSICAL key, so this works on a Hebrew
                // layout too (where that key types "ד", not "s").
                if (ev.code === 'KeyS' || ev.key === 's' || ev.key === 'S' || ev.key === 'ד') {
                  // SketchUp habit: type the count then S -> polygon sides.
                  var ns = parseInt(typed, 10);
                  if (ns >= 3 && ns <= 64) {
                    polySides = ns;
                    // Switch to the polygon tool WITHOUT clearing a centre that
                    // is already placed - the shape being drawn just changes
                    // its side count on the spot.
                    lineTool = 'hex';
                    refreshToolUi();
                    typed = ''; updateVcb();
                    // Loud confirmation in the VCB box that the count took.
                    var vb = document.getElementById('vcb');
                    if (vb) vb.innerHTML = '⬡ ' + polySides + ' צלעות';
                    draw();
                    ev.preventDefault();
                    return;
                  }
                  typed = ''; updateVcb(); draw();
                  ev.preventDefault();
                  return;
                }
                if (/^[0-9.'",;x ]$/.test(ev.key)) { typed += ev.key; updateVcb(); draw(); }
                return;
              }
              if (mode !== 'wall') return;
              if (ev.key === 'Enter') { if (drawing && typed) commitSegment(); return; }
              if (ev.key === 'Backspace') { typed = typed.slice(0, -1); updateVcb(); if (drawing) draw(); ev.preventDefault(); return; }
              if (/^[0-9.'" ]$/.test(ev.key)) { typed += ev.key; updateVcb(); if (drawing) draw(); }
            });

            // ---- side panel (wall) ----
            function setCat(c, keep) {
              cat = c;
              document.getElementById('catE').className = c === 'exterior' ? 'on' : '';
              document.getElementById('catI').className = c === 'interior' ? 'on' : '';
              if (keep) return;
              // Switching Ext/Int picks that category's wall type FROM THE MODEL.
              var m = wallTypes.find(function(t){ return t.src === 'model' && t.cat === c; }) ||
                      wallTypes.find(function(t){ return t.cat === c; });
              if (m) {
                document.getElementById('wallType').value = m.name;
                curWallLib = m.name;
                document.getElementById('th').value = m.th;
                if (m.h) document.getElementById('hh').value = m.h;
              } else {
                document.getElementById('th').value = c === 'interior' ? '4.5' : '5';
                curWallLib = '';
                document.getElementById('wallType').value = '';
              }
            }
            function setSide(s) {
              sideOpt = s;
              document.getElementById('sideL').className = s === 'L' ? 'on' : '';
              document.getElementById('sideR').className = s === 'R' ? 'on' : '';
            }
            function undoPending() { pending.pop(); draw(); }

            // One Undo for the whole editor: the newest pending wall first,
            // otherwise SketchUp's own undo stack (canvas re-syncs after).
            // One Undo for everything, newest thing first: a point of the line
            // being drawn, then a half-started arc/circle/rect, then the last
            // finished shape or wall, and only then SketchUp's own undo stack.
            function undoAction() {
              if (mode === 'line') {
                if (curLine && curLine.pts.length) { undoLinePoint(); return; }
                if (arcPts.length) { arcPts.pop(); draw(); return; }
                if (circC) { circC = null; draw(); return; }
                if (measB) { measB = null; draw(); return; }
                if (measA) { measA = null; draw(); return; }
                if (pendingSketches.length) { pendingSketches.pop(); updateStatus(); draw(); return; }
                if (pending.length) { undoPending(); return; }
                sketchup.undo_model();
                return;
              }
              if (pending.length) { undoPending(); return; }
              if (pendingSketches.length) { pendingSketches.pop(); updateStatus(); draw(); return; }
              sketchup.undo_model();
            }

            // Ctrl+Z (2026-07-30). Plain key events for Ctrl combos never reach
            // this dialog (verified), but the browser's EDIT pipeline does: a
            // focused contenteditable with one undoable edit turns Ctrl+Z into
            // a 'beforeinput' of type historyUndo. We cancel the text undo and
            // run our own. Clicking the canvas parks the focus there.
            var hu = document.getElementById('hiddenUndo');
            function armHiddenUndo() {
              if (!hu) return;
              try { hu.focus(); } catch (e) {}
              if (!hu.dataset.armed) {
                try { document.execCommand('insertText', false, 'x'); hu.dataset.armed = '1'; } catch (e) {}
              }
              // A non-empty selection inside the hidden element guarantees the
              // browser raises a 'copy' event on Ctrl+C (some builds skip it
              // when the selection is collapsed). preventDefault stops the
              // placeholder text ever reaching the real clipboard.
              try {
                if (window.getSelection && document.createRange) {
                  var rg = document.createRange();
                  rg.selectNodeContents(hu);
                  var selo = window.getSelection();
                  selo.removeAllRanges();
                  selo.addRange(rg);
                }
              } catch (e) {}
            }
            if (hu) {
              hu.addEventListener('beforeinput', function(ev) {
                if (ev.inputType === 'historyUndo') { ev.preventDefault(); undoAction(); }
                else if (ev.inputType === 'historyRedo') { ev.preventDefault(); }
              });
              // Ctrl+C / Ctrl+V ride the same edit pipeline as Ctrl+Z: the raw
              // key never reaches this dialog, but the browser's copy/paste
              // commands do. Listened for on document so they are caught
              // wherever the focus happens to sit.
              document.addEventListener('copy', function(ev) {
                if (copySelToClip()) { ev.preventDefault(); draw(); }
              });
              document.addEventListener('paste', function(ev) {
                if (pasteClip()) ev.preventDefault();
              });
              cv.addEventListener('mousedown', function() { setTimeout(armHiddenUndo, 0); });
              setTimeout(armHiddenUndo, 300);
            }

            // ---- Ruby bridge ----
            // Exterior walls always face OUT of the building, regardless of the
            // direction they were drawn in: if a wall's band points away from
            // the drawing's center, flip it (anchor stays bottom-left).
            function autoOrientExterior() {
              var ext = pending.filter(function(w){ return w.cat === 'exterior'; });
              if (ext.length < 3) return;
              var cx = 0, cy = 0, n = 0;
              ext.forEach(function(w){ cx += w.sx + w.ex; cy += w.sy + w.ey; n += 2; });
              cx /= n; cy /= n;
              ext.forEach(function(w){
                var b = bandQuad(w); if (!b) return;
                var mid = (b.p + b.q) / 2;
                var lx = (w.sx + w.ex)/2, ly = (w.sy + w.ey)/2;
                var bx = lx + b.nx*mid, by = ly + b.ny*mid;
                if (Math.hypot(bx - cx, by - cy) > Math.hypot(lx - cx, ly - cy)) {
                  var t = {x:w.sx, y:w.sy};
                  w.sx = w.ex; w.sy = w.ey; w.ex = t.x; w.ey = t.y;
                  w.ha = 'left';
                }
              });
              draw();
            }

            function applyPending() {
              if (pendingSketches.length) sketchup.apply_sketches(JSON.stringify(pendingSketches));
              if (!pending.length) return;
              autoOrientExterior();
              sketchup.apply_walls(JSON.stringify(pending));
            }
            function applyDone(n) { pending = []; draw(); }
            function planDone(ok) {}
            // Selection to restore after a model round-trip (edit/move/resize),
            // so the panel stays open on the same wall/opening.
            var keepSel = null;

            function loadWalls(list) {
              walls = list || [];
              hoverHit = null; dragSym = null; dragWall = null;
              var want = keepSel || (sel && sel.type === 'wall' ? { kind:'wall', id: sel.w.id } :
                        (sel && sel.type === 'sym' ? { kind:'sym', id: sel.s.id } : null));
              keepSel = null;
              sel = null;
              if (want) {
                for (var i6 = 0; i6 < walls.length && !sel; i6++) {
                  var w6 = walls[i6];
                  if (want.kind === 'wall' && w6.id === want.id) { sel = { type:'wall', w:w6 }; break; }
                  if (want.kind === 'sym') {
                    (w6.syms || []).forEach(function(s6){
                      if (!sel && s6.id === want.id) sel = { type:'sym', w:w6, s:s6 };
                    });
                  }
                }
              }
              selList = sel ? [sel] : [];
              if (typeof updateSelPanel === 'function') updateSelPanel();
              if (!fitted && walls.length) { fitView(); fitted = true; }
              draw();
            }
            function fitView() {
              var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
              walls.forEach(function(w){
                minX = Math.min(minX, w.sx, w.ex); maxX = Math.max(maxX, w.sx, w.ex);
                minY = Math.min(minY, w.sy, w.ey); maxY = Math.max(maxY, w.sy, w.ey);
              });
              if (minX > maxX) return;
              var pad = 60;
              scale = Math.min((cv.width - pad*2) / Math.max(maxX - minX, 60),
                               (cv.height - pad*2) / Math.max(maxY - minY, 60));
              scale = Math.max(0.15, Math.min(6, scale));
              panX = pad - minX * scale;
              panY = pad - minY * scale;
            }

            fillSelect('dType', DOOR_TYPES[doorCat]);
            fillSelect('wType', WIN_TYPES);
            doorTypeChanged();
            winTypeChanged();
            setMode('sel');
            setLineTool('line');
            setLinePreset('solid');
            resize();
            sketchup.editor_ready();
          </script>
          </body></html>

HTML
