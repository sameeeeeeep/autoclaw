// Query background for current state
chrome.runtime.sendMessage({ type: 'PING' }, (response) => {
  // Background doesn't respond to PING via onMessage — check badge instead
});

// Simple status check — try to reach background
const dot = document.getElementById('dot');
const status = document.getElementById('status');

// Check by reading the badge
chrome.action.getBadgeText({}, (text) => {
  if (text === 'REC') {
    dot.className = 'dot recording';
    status.textContent = 'Recording browser events...';
  } else if (text === 'ON') {
    dot.className = 'dot connected';
    status.textContent = 'Connected to Autoclaw';
  } else {
    dot.className = 'dot disconnected';
    status.textContent = 'Waiting for Autoclaw app...';
  }
});
