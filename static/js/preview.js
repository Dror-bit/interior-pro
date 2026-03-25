let svgElement = null;
let isPanning = false;
let startX = 0, startY = 0;
let viewBoxX = 0, viewBoxY = 0;
let currentScale = 1;

function initPreviewControls() {
    const container = document.getElementById('preview-container');
    svgElement = container.querySelector('svg');
    if (!svgElement) return;

    // Parse initial viewBox
    const vb = svgElement.getAttribute('viewBox');
    if (vb) {
        const parts = vb.split(' ').map(Number);
        viewBoxX = parts[0];
        viewBoxY = parts[1];
    }

    // Mouse wheel zoom
    container.addEventListener('wheel', (e) => {
        e.preventDefault();
        const delta = e.deltaY > 0 ? 1.1 : 0.9;
        currentScale *= delta;
        currentScale = Math.max(0.1, Math.min(10, currentScale));
        updateViewBox();
    });

    // Pan
    container.addEventListener('mousedown', (e) => {
        isPanning = true;
        startX = e.clientX;
        startY = e.clientY;
        container.style.cursor = 'grabbing';
    });

    window.addEventListener('mousemove', (e) => {
        if (!isPanning) return;
        const dx = (e.clientX - startX) * currentScale;
        const dy = (e.clientY - startY) * currentScale;
        viewBoxX -= dx;
        viewBoxY -= dy;
        startX = e.clientX;
        startY = e.clientY;
        updateViewBox();
    });

    window.addEventListener('mouseup', () => {
        isPanning = false;
        const container = document.getElementById('preview-container');
        if (container) container.style.cursor = 'grab';
    });

    container.style.cursor = 'grab';
}

function updateViewBox() {
    if (!svgElement) return;
    const w = parseFloat(svgElement.getAttribute('width')) * currentScale;
    const h = parseFloat(svgElement.getAttribute('height')) * currentScale;
    svgElement.setAttribute('viewBox', `${viewBoxX} ${viewBoxY} ${w} ${h}`);
}
