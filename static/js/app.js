const dropZone = document.getElementById('drop-zone');
const fileInput = document.getElementById('file-input');
const browseBtn = document.getElementById('browse-btn');
const uploadProgress = document.getElementById('upload-progress');
const progressFill = document.querySelector('.progress-fill');
const progressText = document.querySelector('.progress-text');
const configSection = document.getElementById('config-section');
const resultsSection = document.getElementById('results-section');
const fileInfoDiv = document.getElementById('file-info');
const layersList = document.getElementById('layers-list');
const previewContainer = document.getElementById('preview-container');
const downloadBtn = document.getElementById('download-btn');
const updateLayersBtn = document.getElementById('update-layers-btn');

let currentSessionId = null;

// Drop zone events
browseBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    fileInput.click();
});

dropZone.addEventListener('click', () => fileInput.click());

dropZone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropZone.classList.add('drag-over');
});

dropZone.addEventListener('dragleave', () => {
    dropZone.classList.remove('drag-over');
});

dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropZone.classList.remove('drag-over');
    const files = e.dataTransfer.files;
    if (files.length > 0) {
        uploadFile(files[0]);
    }
});

fileInput.addEventListener('change', () => {
    if (fileInput.files.length > 0) {
        uploadFile(fileInput.files[0]);
    }
});

async function uploadFile(file) {
    const ext = file.name.split('.').pop().toLowerCase();
    if (!['dwg', 'dxf', 'pdf'].includes(ext)) {
        alert('Unsupported file type. Please upload DWG, DXF, or PDF.');
        return;
    }

    uploadProgress.hidden = false;
    progressFill.style.width = '30%';
    progressText.textContent = 'Uploading...';
    resultsSection.hidden = true;

    const formData = new FormData();
    formData.append('file', file);

    try {
        progressFill.style.width = '60%';
        progressText.textContent = 'Processing...';

        const response = await fetch('/api/upload', {
            method: 'POST',
            body: formData,
        });

        if (!response.ok) {
            const err = await response.json();
            throw new Error(err.detail || 'Upload failed');
        }

        progressFill.style.width = '100%';
        progressText.textContent = 'Done!';

        const data = await response.json();
        currentSessionId = data.session_id;

        showResults(data);

    } catch (error) {
        progressText.textContent = `Error: ${error.message}`;
        progressFill.style.width = '100%';
        progressFill.style.background = '#E74C3C';
        setTimeout(() => {
            uploadProgress.hidden = true;
            progressFill.style.background = '';
        }, 3000);
    }
}

function showResults(data) {
    configSection.hidden = false;
    resultsSection.hidden = false;

    // File info
    fileInfoDiv.innerHTML = `
        <div class="info-item">
            <div class="label">File</div>
            <div class="value">${data.filename}</div>
        </div>
        <div class="info-item">
            <div class="label">Walls</div>
            <div class="value">${data.wall_count}</div>
        </div>
        <div class="info-item">
            <div class="label">Openings</div>
            <div class="value">${data.opening_count}</div>
        </div>
        <div class="info-item">
            <div class="label">Furniture</div>
            <div class="value">${data.furniture_count}</div>
        </div>
        <div class="info-item">
            <div class="label">Units</div>
            <div class="value">${data.units}</div>
        </div>
    `;

    // Layers
    layersList.innerHTML = '';
    const layerEntries = Object.entries(data.layers);
    if (layerEntries.length > 0) {
        for (const [name, type] of layerEntries) {
            const tag = document.createElement('div');
            tag.className = `layer-tag ${type || 'unknown'}`;
            tag.innerHTML = `
                <span>${name}</span>
                <select data-layer="${name}">
                    <option value="" ${!type ? 'selected' : ''}>--</option>
                    <option value="wall" ${type === 'wall' ? 'selected' : ''}>Wall</option>
                    <option value="door" ${type === 'door' ? 'selected' : ''}>Door</option>
                    <option value="window" ${type === 'window' ? 'selected' : ''}>Window</option>
                    <option value="furniture" ${type === 'furniture' ? 'selected' : ''}>Furniture</option>
                    <option value="ignore" ${type === 'ignore' ? 'selected' : ''}>Ignore</option>
                </select>
            `;
            layersList.appendChild(tag);
        }
        updateLayersBtn.hidden = false;
    }

    // Preview
    loadPreview();

    // Scroll to results
    setTimeout(() => {
        uploadProgress.hidden = true;
        resultsSection.scrollIntoView({ behavior: 'smooth' });
    }, 500);
}

async function loadPreview() {
    if (!currentSessionId) return;
    previewContainer.innerHTML = '<p>Loading preview...</p>';
    try {
        const response = await fetch(`/api/preview/${currentSessionId}`);
        if (response.ok) {
            const svg = await response.text();
            previewContainer.innerHTML = svg;
            initPreviewControls();
        }
    } catch (e) {
        previewContainer.innerHTML = '<p>Failed to load preview</p>';
    }
}

// Download
downloadBtn.addEventListener('click', () => {
    if (currentSessionId) {
        window.location.href = `/api/download/${currentSessionId}`;
    }
});

// Update layers
updateLayersBtn.addEventListener('click', async () => {
    if (!currentSessionId) return;

    const mapping = {};
    document.querySelectorAll('#layers-list select').forEach(select => {
        const layer = select.dataset.layer;
        const value = select.value;
        if (value && value !== 'ignore') {
            mapping[layer] = value;
        }
    });

    try {
        const response = await fetch(`/api/layers/${currentSessionId}/update`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ mapping }),
        });

        if (response.ok) {
            loadPreview();
        }
    } catch (e) {
        alert('Failed to update layers');
    }
});
