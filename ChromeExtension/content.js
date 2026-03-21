// Autoclaw Content Script — captures DOM events and sends to background worker
// Runs on every page, lightweight until activated by background.js

let isRecording = false;

// Listen for recording state from background
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'SET_RECORDING') {
    isRecording = msg.recording;
    if (isRecording) {
      attachListeners();
      sendResponse({ ok: true, status: 'recording' });
    } else {
      detachListeners();
      sendResponse({ ok: true, status: 'stopped' });
    }
  }
  if (msg.type === 'PING') {
    sendResponse({ ok: true, recording: isRecording });
  }
  return true;
});

// ---------- Event Capture ----------

function bestSelector(el) {
  // Try aria-label first (most semantic)
  if (el.getAttribute('aria-label')) {
    const tag = el.tagName.toLowerCase();
    return `${tag}[aria-label="${el.getAttribute('aria-label')}"]`;
  }
  // Try id
  if (el.id) return `#${el.id}`;
  // Try name attribute (for form fields)
  if (el.name) {
    const tag = el.tagName.toLowerCase();
    return `${tag}[name="${el.name}"]`;
  }
  // Try data-testid
  if (el.dataset.testid) return `[data-testid="${el.dataset.testid}"]`;
  // Try unique class combo
  if (el.className && typeof el.className === 'string') {
    const classes = el.className.trim().split(/\s+/).slice(0, 3).join('.');
    if (classes) return `${el.tagName.toLowerCase()}.${classes}`;
  }
  // Fallback: tag + index
  return el.tagName.toLowerCase();
}

function fieldLabel(el) {
  // Check aria-label
  if (el.getAttribute('aria-label')) return el.getAttribute('aria-label');
  // Check placeholder
  if (el.placeholder) return el.placeholder;
  // Check associated <label>
  if (el.id) {
    const label = document.querySelector(`label[for="${el.id}"]`);
    if (label) return label.textContent.trim();
  }
  // Check name
  if (el.name) return el.name;
  // Check parent label
  const parentLabel = el.closest('label');
  if (parentLabel) return parentLabel.textContent.trim().substring(0, 50);
  return null;
}

function visibleText(el) {
  // Get visible text, truncated
  const text = (el.textContent || el.innerText || el.value || '').trim();
  return text.substring(0, 100);
}

function sendEvent(event) {
  if (!isRecording) return;
  chrome.runtime.sendMessage({ type: 'DOM_EVENT', event });
}

// ---------- Click Handler ----------

function onClickCapture(e) {
  const el = e.target;
  if (!el || !el.tagName) return;

  sendEvent({
    type: 'click',
    timestamp: Date.now(),
    url: window.location.href,
    pageTitle: document.title,
    selector: bestSelector(el),
    tagName: el.tagName.toLowerCase(),
    elementText: visibleText(el),
    fieldName: fieldLabel(el),
    value: null
  });
}

// ---------- Input Handler (debounced) ----------

const inputTimers = new WeakMap();

function onInputCapture(e) {
  const el = e.target;
  if (!el || !el.tagName) return;
  const tag = el.tagName.toLowerCase();
  if (tag !== 'input' && tag !== 'textarea' && tag !== 'select' && !el.isContentEditable) return;

  // Debounce — wait 800ms after last keystroke before sending
  if (inputTimers.has(el)) clearTimeout(inputTimers.get(el));
  inputTimers.set(el, setTimeout(() => {
    const value = el.isContentEditable
      ? (el.textContent || '').trim().substring(0, 200)
      : (el.value || '').substring(0, 200);

    sendEvent({
      type: 'input',
      timestamp: Date.now(),
      url: window.location.href,
      pageTitle: document.title,
      selector: bestSelector(el),
      tagName: tag,
      elementText: null,
      fieldName: fieldLabel(el),
      value: value
    });
  }, 800));
}

// ---------- Select/Change Handler ----------

function onChangeCapture(e) {
  const el = e.target;
  if (!el || el.tagName.toLowerCase() !== 'select') return;

  const selectedOption = el.options[el.selectedIndex];
  sendEvent({
    type: 'select',
    timestamp: Date.now(),
    url: window.location.href,
    pageTitle: document.title,
    selector: bestSelector(el),
    tagName: 'select',
    elementText: selectedOption ? selectedOption.text : '',
    fieldName: fieldLabel(el),
    value: el.value
  });
}

// ---------- Form Submit Handler ----------

function onSubmitCapture(e) {
  const form = e.target;
  sendEvent({
    type: 'submit',
    timestamp: Date.now(),
    url: window.location.href,
    pageTitle: document.title,
    selector: bestSelector(form),
    tagName: 'form',
    elementText: null,
    fieldName: null,
    value: null,
    formAction: form.action || window.location.href
  });
}

// ---------- Attach / Detach ----------

function attachListeners() {
  document.addEventListener('click', onClickCapture, true);
  document.addEventListener('input', onInputCapture, true);
  document.addEventListener('change', onChangeCapture, true);
  document.addEventListener('submit', onSubmitCapture, true);
  console.log('[Autoclaw] Recording DOM events');
}

function detachListeners() {
  document.removeEventListener('click', onClickCapture, true);
  document.removeEventListener('input', onInputCapture, true);
  document.removeEventListener('change', onChangeCapture, true);
  document.removeEventListener('submit', onSubmitCapture, true);
  console.log('[Autoclaw] Stopped recording DOM events');
}

// Send initial navigation event
if (isRecording) {
  sendEvent({
    type: 'navigate',
    timestamp: Date.now(),
    url: window.location.href,
    pageTitle: document.title,
    selector: null,
    tagName: null,
    elementText: null,
    fieldName: null,
    value: null
  });
}
