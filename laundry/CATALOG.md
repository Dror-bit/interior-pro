# LG laundry planning catalog — verified 2026-10-16

User selected LG, front and top opening washers, side-by-side and stacked layouts.
These are dimensionally fixed schematic planning models created by this plugin,
not manufacturer CAD or detailed fabrication/installation models. No appliance
asset is scaled. Decorative controls and doors are schematic. Units are inches.

| Product | W × H × D | Side / rear planning gap | Opening / overhead |
|---|---|---|---|
| WM4000HWA front-load washer | 27 × 39 × 30 1/4 | 1 / 4 | Door-open depth 55; top 1/4 |
| DLEX4000W electric dryer | 27 × 39 × 30 1/8 | 1 / 5 | Door-open depth 51 3/8; overhead 18, cabinet depth at most 14 |
| WT7400CW top-load washer | 27 × 44 1/2 × 28 3/8 | 1 / 4 | Lid open 57 1/4 high; planning cutout height 58 |
| DLE7400WE electric dryer, front opening | 27 × 44 1/4 × 29 1/2 | 1 / 5 | Door-open depth 50 1/4; overhead 18, cabinet depth at most 14 |
| WM4000HWA + DLEX4000W stacked | 27 × 78 × 30 1/4 | 1 / 5 1/2 | KSTK4 kit required; overhead 6; front based on washer door |

Side-by-side presets combine fixed individual machines with a shared 1-inch side
gap. Overall width is therefore 55. Their conservative planning envelope uses the
larger heights, depths, rear/door gaps and overhead allowances of the pair. These
presets are plugin layouts, not additional manufacturer SKUs. Individual machines
remain available for separate placement/edit/delete. Top-load washers cannot be
stacked; only the verified front-load stacked product permits an elevated dryer.
Both matching dryers open from the front.

## Primary sources

- [WM4000H_A LG Pro Builder, May 2025](https://www.lg.com/us/business/download/resources/CT00021979/WM4000H_A_LG_Pro_Builder_Spec_Sheet%5B20250528_051619%5D.pdf), dimensions/clearances and 78-inch stacked height.
- [WM4000H_A current LG specification](https://www.lg.com/us/support/products/documents/WM4000H_A_spec_sheet.pdf), fixed appliance size and KSTK4 accessory.
- [DLEX4000 / DLGX4001 LG Pro Builder, May 2025](https://www.lg.com/us/business/download/resources/CT00021979/DLEX4000_%20DLGX4001_%20LG%20Pro_Builder_Spec_Sheet%5B20250528_060503%5D.pdf), individual and stacked rear-vented planning profiles.
- [WT7400C LG Builder](https://www.lg.com/us/business/download/resources/CT00021979/WT7400C_%20LG%20Builder%20Spec%20Sheet%5B20220726_041839%5D.pdf), fixed size, lid-open height and cutout.
- [DLE7400 / DLG7401 LG Builder](https://www.lg.com/us/business/download/resources/CT00021979/DLE7400_E%20DLG7401_E%20LG%20Builder%20Spec%20Sheet%5B20220414_112739%5D.pdf), fixed size, door-open depth, cabinet spacing and rear-vent cutout.

Older 2024 stacked drawings show 77 1/2; the catalog uses the later May 2025
78-inch drawing. DLE7400 generic manuals can show 44 1/2; this catalog follows
the model-specific Builder sheet and LG product page, which state 44 1/4.
No mixed height arithmetic or invisible stretching is used.

## Fit scope

The rear-vented, open-front planning profile is intentionally conservative.
Expanded service envelopes are checked against other products in the same Laundry
design, including rotated footprints and vertical clearance. Side gaps may be
shared; two clearance envelopes may overlap without colliding with a machine.
Overhead cabinets respect dryer depth and height allowances; top-load lids retain
the cutout clearance. Stacking geometry stays one owned product for native history.

House walls, ceilings, delivery paths, enclosed closet ventilation, floor/support,
electrical, water, drain and duct routing are not installation-approval checks in
this slice. Keep the shown service zones clear of those objects and consult the
linked model-specific installation documentation for the actual site. Side/bottom
venting and pedestal variants are not offered by these profiles.

Upper cabinets are custom furniture, with width 12–48, height 12–48, depth 10–24,
bottom height 12–108, all in eighths, and 0–6 shelves with 3-inch minimum nominal
spacing. Default 30 × 30 × 12, bottom 66, two shelves. These are tool limits/defaults,
not manufacturer cabinet specifications or a claim about wall anchoring.
