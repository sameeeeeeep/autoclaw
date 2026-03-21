// Autoclaw Background Service Worker
// Manages WebSocket connection to Autoclaw macOS app and recording state

const WS_URL = 'ws://127.0.0.1:9849';
let ws = null;
let isRecording = false;
let reconnectTimer = null;

// ---------- WebSocket Connection ----------

function connect() {
  if (ws && ws.readyState === WebSocket.OPEN) return;

  try {
    ws = new WebSocket(WS_URL);

    ws.onopen = () => {
      console.log('[Autoclaw] Connected to macOS app');
      clearReconnectTimer();
      // Tell Autoclaw we're here
      ws.send(JSON.stringify({ type: 'extension_connected', version: '1.0.0' }));
      updateBadge();
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        handleAppMessage(msg);
      } catch (e) {
        console.error('[Autoclaw] Bad message:', e);
      }
    };

    ws.onclose = () => {
      console.log('[Autoclaw] Disconnected from macOS app');
      ws = null;
      isRecording = false;
      updateBadge();
      scheduleReconnect();
    };

    ws.onerror = (err) => {
      console.error('[Autoclaw] WebSocket error');
      ws = null;
      scheduleReconnect();
    };
  } catch (e) {
    console.error('[Autoclaw] Connect failed:', e);
    scheduleReconnect();
  }
}

function scheduleReconnect() {
  clearReconnectTimer();
  reconnectTimer = setTimeout(connect, 5000);
}

function clearReconnectTimer() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
}

// ---------- Messages from Autoclaw App ----------

function handleAppMessage(msg) {
  switch (msg.type) {
    case 'start_recording':
      isRecording = true;
      broadcastToTabs({ type: 'SET_RECORDING', recording: true });
      updateBadge();
      console.log('[Autoclaw] Recording started');
      break;

    case 'stop_recording':
      isRecording = false;
      broadcastToTabs({ type: 'SET_RECORDING', recording: false });
      updateBadge();
      console.log('[Autoclaw] Recording stopped');
      break;

    case 'ping':
      ws?.send(JSON.stringify({ type: 'pong', recording: isRecording }));
      break;
  }
}

// ---------- Messages from Content Scripts ----------

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'DOM_EVENT' && isRecording && ws?.readyState === WebSocket.OPEN) {
    // Forward DOM event to Autoclaw app via WebSocket
    ws.send(JSON.stringify({
      type: 'dom_event',
      tabId: sender.tab?.id,
      event: msg.event
    }));
    sendResponse({ ok: true });
  }
  return true;
});

// ---------- Tab Management ----------

async function broadcastToTabs(message) {
  try {
    const tabs = await chrome.tabs.query({});
    for (const tab of tabs) {
      try {
        chrome.tabs.sendMessage(tab.id, message).catch(() => {});
      } catch (e) { /* content script not loaded yet */ }
    }
  } catch (e) {
    console.error('[Autoclaw] Broadcast failed:', e);
  }
}

// Track navigation for navigate events
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (!isRecording || !ws || ws.readyState !== WebSocket.OPEN) return;
  if (changeInfo.status === 'complete' && tab.url) {
    ws.send(JSON.stringify({
      type: 'dom_event',
      tabId: tabId,
      event: {
        type: 'navigate',
        timestamp: Date.now(),
        url: tab.url,
        pageTitle: tab.title || '',
        selector: null,
        tagName: null,
        elementText: null,
        fieldName: null,
        value: null
      }
    }));
  }
});

// ---------- Badge ----------

function updateBadge() {
  const connected = ws && ws.readyState === WebSocket.OPEN;
  if (isRecording) {
    chrome.action.setBadgeText({ text: 'REC' });
    chrome.action.setBadgeBackgroundColor({ color: '#FF3B30' });
  } else if (connected) {
    chrome.action.setBadgeText({ text: 'ON' });
    chrome.action.setBadgeBackgroundColor({ color: '#34C759' });
  } else {
    chrome.action.setBadgeText({ text: '' });
  }
}

// ---------- Startup ----------

connect();
